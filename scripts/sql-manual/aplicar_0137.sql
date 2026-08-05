-- ############################################################################
-- ✅ ESTE ARCHIVO SÍ SE PEGA EN EL SQL EDITOR DE SUPABASE.
--
-- Es la migración 0137 lista para pegar de una sola vez. Es IDEMPOTENTE: si la
-- pegas dos veces no pasa nada malo.
--
-- Verificado el 04/08/2026 contra el Postgres local con el esquema completo de
-- producción: la migración aplica limpio y sus 10 pruebas pasan.
--
-- Al final devuelve una fila de comprobación. Tiene que decir:
--     funcion_creada = 1     migraciones_registradas = 4
--
-- (No confundir con supabase/tests/109_*.test.sql, que NUNCA se pega: ese usa
--  pgTAP, que solo existe en el Postgres local, y falla a propósito en prod.)
-- ############################################################################

-- ============================================================================
-- 0137 — Reabrir el día de alguien que ya marcó salida, sin dejarlo a medias.
--
-- QUÉ PROMETE
--
-- Que reabrir el día de una colaboradora que ya marcó su salida final sea una
-- sola operación: o queda todo hecho, o no queda nada. Y que deje rastro.
--
-- QUÉ ASUME
--
-- Que quien llama tiene la sesión de una TERMINAL activa. El terminal ya no se
-- recibe como dato: se deriva de la sesión (ver abajo).
--
-- ── EL PROBLEMA QUE RESUELVE ────────────────────────────────────────────────
--
-- Hasta hoy esto vivía en /api/reabrir-dia, y hacía TRES escrituras sueltas con
-- la llave de servicio: reescribía el tipo de la salida final, insertaba el
-- retorno, y recalculaba la jornada. Tres viajes independientes, sin transacción.
--
-- Si el segundo fallaba —se cae la red, se reinicia la función, expira el
-- token— la salida final YA se había convertido en salida temporal y el retorno
-- nunca entraba. Resultado: el día queda ABIERTO para siempre. La persona
-- aparece adentro, sus horas de ese día salen mal, y nadie se entera hasta que
-- alguien cuadra la planilla a fin de mes. Un error que no avisa es peor que uno
-- que revienta.
--
-- Y rompía dos reglas que este sistema sí sostiene en todos lados:
--   · los marcajes son APPEND-ONLY — aquí se hacía `update marcajes set tipo`,
--     y el registro de lo que la persona realmente marcó se perdía;
--   · toda escritura de marcaje pasa por función — aquí había un `insert`
--     directo desde el servidor de Next.
--
-- ── POR QUÉ ASÍ Y NO DE OTRA FORMA ──────────────────────────────────────────
--
-- 1. TODO DENTRO DE UNA FUNCIÓN. Una función de plpgsql es una transacción: si
--    algo revienta a la mitad, Postgres deshace lo anterior. No hay estado a
--    medias posible — no porque el código sea cuidadoso, sino porque el motor
--    no permite lo contrario.
--
-- 2. LA SALIDA FINAL SE ANULA, NO SE REESCRIBE. La 0081 ya decidió que las
--    marcas no se borran ni se pisan: se anulan y quedan. Aquí se hace igual —
--    se anula la salida final y se emite una salida temporal NUEVA con el mismo
--    instante. Así queda registrado que a las 18:03 esa persona marcó su salida
--    final de verdad, y que después se decidió tratarla como salida temporal.
--    Con el `update` anterior, esa primera intención desaparecía.
--
-- 3. EL TERMINAL SALE DE LA SESIÓN, NO DEL PARÁMETRO. Si la función recibiera
--    `p_terminal_id`, cualquier sesión con login podría mandar el id de un
--    terminal activo ajeno y reabrir días de otra sede. Derivándolo de
--    `auth.uid()` ese agujero no existe: no hay nada que falsificar. Esto es
--    además lo que permite que la ruta HTTP deje de usar la llave de servicio.
--
-- 4. `for update` SOBRE LA SALIDA FINAL. Dos terminales que reabren el mismo día
--    en el mismo segundo tomarían la misma fila; sin candado, ambas la anularían
--    y se insertarían DOS retornos. El candado hace que la segunda espere y
--    encuentre la marca ya anulada, así que su `not found` la detiene sola.
--
-- 5. NO SE REABRE UN DÍA YA PAGADO. Es el mismo guard de fn_anular_marcaje: si
--    el día cae en un periodo cerrado, reabrirlo movería horas de una planilla
--    que ya se pagó. Primero se reabre el periodo, con lo que eso implica.
--
-- ── SOBRE EL RASTRO ─────────────────────────────────────────────────────────
--
-- `correcciones_auditoria.corregido_por` exige una persona, y aquí quien actúa
-- es un kiosco. Se registra a la propia persona, que es quien tocó la pantalla,
-- y el campo dice `dia_reabierto_desde_terminal` para que nadie lea eso como
-- "una encargada corrigió a alguien". Es la verdad disponible: el terminal marca
-- sin PIN por decisión de Felipe (jul-2026), así que el sistema no puede afirmar
-- quién apretó el botón — solo desde qué kiosco se hizo, y eso sí queda, en el
-- `terminal_id` de las dos marcas nuevas.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_reabrir_dia(uuid, text);
--
-- y volver /api/reabrir-dia a su versión anterior (commit previo a esta
-- migración). No borra datos: las marcas anuladas por esta función siguen ahí.
-- ============================================================================

create or replace function fn_reabrir_dia(p_persona_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_term_id   uuid;
  v_term_sede uuid;
  v_cierre    marcajes;
  v_hoy       date;
  v_retorno   uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo del regreso es obligatorio.';
  end if;

  -- El terminal se deriva de la sesión (ver punto 3 del encabezado).
  select t.id, t.sede_id into v_term_id, v_term_sede
  from terminales t
  where t.auth_user_id = auth.uid()
    and t.activo is true;
  if v_term_id is null then
    raise exception 'Esta operación solo se hace desde una terminal activa.';
  end if;

  -- `fn_hoy_lima()` y no `current_date`: el servidor corre en UTC, y a partir de
  -- las 19:00 de Lima `current_date` ya devuelve el día siguiente. Lo blinda la
  -- prueba 92.
  v_hoy := fn_hoy_lima();

  select * into v_cierre
  from marcajes m
  where m.persona_id = p_persona_id
    and m.tipo = 'salida_final'
    and m.anulada_at is null
    and (m.timestamp_marca at time zone 'America/Lima')::date = v_hoy
  order by m.timestamp_marca desc
  limit 1
  for update;

  if not found then
    raise exception 'No hay una salida final de hoy para reabrir.';
  end if;

  -- Cada sede reabre lo suyo. Se compara contra la sede DEL MARCAJE y no contra
  -- la sede base de la persona: quien viaja entre sedes marcó su salida donde
  -- estaba, y es esa terminal la que puede corregirla.
  if v_cierre.sede_id <> v_term_sede then
    raise exception 'Esa marca es de otra sede: se reabre desde la terminal donde se marcó.';
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_hoy between fecha_ini and fecha_fin
  ) then
    raise exception 'Ese día cae en un periodo ya PAGADO: reabrirlo alteraría una planilla pagada. Reabre el periodo primero.';
  end if;

  update marcajes
     set anulada_at     = now(),
         anulada_por    = p_persona_id,
         anulada_motivo = 'Día reabierto desde terminal: ' || trim(p_motivo)
   where id = v_cierre.id;

  -- La salida vuelve a emitirse como temporal, en el MISMO instante que la
  -- original: el rato de afuera tiene que descontarse desde que se fue, no desde
  -- que el sistema se enteró.
  insert into marcajes
    (client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen)
  values
    (gen_random_uuid(), p_persona_id, v_cierre.sede_id, v_term_id,
     'salida_otro', trim(p_motivo), v_cierre.timestamp_marca, 'terminal');

  insert into marcajes
    (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen)
  values
    (gen_random_uuid(), p_persona_id, v_cierre.sede_id, v_term_id,
     'retorno_otro', now(), 'terminal')
  returning id into v_retorno;

  insert into correcciones_auditoria
    (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_cierre.id, p_persona_id, 'dia_reabierto_desde_terminal',
     'salida_final @ ' || v_cierre.timestamp_marca::text,
     'salida_otro (mismo instante) + retorno_otro',
     p_persona_id, trim(p_motivo));

  -- El trigger de marcajes ya recalcula; esto lo deja explícito para quien lea
  -- la función sin conocerlo, y es idempotente.
  perform fn_recalcular_jornada(p_persona_id, v_hoy);

  return jsonb_build_object('ok', true, 'marcaje_retorno_id', v_retorno);
end;
$fn$;

grant  execute on function fn_reabrir_dia(uuid, text) to authenticated;
revoke execute on function fn_reabrir_dia(uuid, text) from public, anon;

comment on function fn_reabrir_dia(uuid, text) is
  'Reabre el dia de quien ya marco salida final: anula esa salida, la reemite como temporal en el mismo instante y registra el retorno. Todo en una transaccion. El terminal sale de auth.uid(), nunca de un parametro.';

insert into migraciones_aplicadas (numero, nombre) values (137, 'reabrir_el_dia_sin_dejarlo_a_medias')
on conflict (numero) do nothing;

-- Las 0128, 0131 y 0132 se aplicaron sin registrarse: no llevaban este insert.
-- Se registran acá para que `migraciones_aplicadas` vuelva a ser legible como
-- "lo que hay en produccion". Idempotente: si alguna ya está, no pasa nada.
insert into migraciones_aplicadas (numero, nombre) values
  (128, 'la_base_declarada_por_rango'),
  (131, 'reabrir_para_cambiar_firmante'),
  (132, 'el_tope_de_educacion_por_rango')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_reabrir_dia')                as funcion_creada,
  (select count(*) from migraciones_aplicadas where numero in (128,131,132,137)) as migraciones_registradas;
