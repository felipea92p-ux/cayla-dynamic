-- ============================================================================
-- 0318 · REABRIR EL DÍA NO PUEDE ANULAR LA SALIDA DE ANOCHE
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_reabrir_dia` solo pueda tocar la salida final de la jornada de HOY,
--   nunca la de quien cerró tienda pasada la medianoche.
--
-- EL DEFECTO, MEDIDO
--   Ana entra el martes a las 15:00 y cierra tienda a las 00:30 del miércoles.
--   La 0240 lo guarda BIEN: `fecha_jornada` = martes, jornada del martes cerrada
--   con 9,50 h.
--
--   El miércoles llega a las 08:00 y marca entrada. El terminal repartía las
--   marcas por la fecha de CALENDARIO, así que veía esa salida como «de hoy» y
--   le mostraba «Ya cerraste tu día. ¿Volviste a entrar?». El único botón hacia
--   adelante llama a esta función, que buscaba la salida así:
--
--       and (m.timestamp_marca at time zone 'America/Lima')::date = v_hoy
--
--   Encuentra la de las 00:30 —la salida REAL de anoche— y la anula.
--
--       jornada del martes      9,50 h cerrada  →  sin horas, abierta
--       lo que paga la boleta      S/109,62     →  S/0,00
--
--   En un sistema cuyo principio escrito es que los marcajes son append-only.
--
-- LA SEGUNDA BARRERA, NO LA PRIMERA
--   El terminal ya no muestra esa pantalla: desde `jornadaEnCursoPorPersona`
--   reparte por `fecha_jornada`, así que el botón no se pulsa. Esta migración
--   cubre lo que quede — una pestaña abierta desde ayer, la cola offline
--   reenviando algo, o cualquier futuro cliente. Las dos mitades del par se
--   arreglan juntas: es la lección que este repo lleva pagando todo agosto, y
--   hoy ya la cobró tres veces (0308, 0310, y esta).
--
-- POR QUÉ `coalesce` Y NO `fecha_jornada = v_hoy`
--   Porque las marcas normales NO llevan esa columna: solo la lleva la salida
--   que cruza medianoche. Exigirla dejaría sin poder reabrir a todo el mundo.
--   El null es el caso corriente, no el raro — y hay una prueba que lo fija.
--
-- QUÉ NO CAMBIA
--   Quien cierra su día a las 16:00 y vuelve a entrar sigue pudiendo reabrir,
--   igual que siempre. Comprobado en local antes de escribir esto: la salida
--   del mismo día tiene `fecha_jornada` en null, el `coalesce` cae al
--   calendario, y la función se comporta idéntica.
--
-- LO QUE ESTA MIGRACIÓN NO ARREGLA
--   El otro P1 del mismo informe, que también está vivo y medido: cuando el
--   auto-cierre llega primero, la salida de madrugada se RECHAZA con «tipo
--   salida_final no válido en el estado actual» —el error que la 0240 dice
--   haber arreglado— el terminal ofrece ENTRADA, la acepta, y nace un día
--   fantasma. Medido: 8,00 h registradas donde se trabajaron 11,50. Ése toca
--   `fn_registrar_marcaje` y va en su propia migración.
--
-- CÓMO SE REVIERTE
--   Dejando la condición en `(m.timestamp_marca at time zone 'America/Lima')
--   ::date = v_hoy`. No hay datos que deshacer: el `select` solo lee.
--
-- MD5 DE PARTIDA (pedido a PRODUCCIÓN antes de escribir)
--   → 8730c7a1a53a239e9d983449ad4eafa1 · 3 304 caracteres
--   Confirmado por Felipe el 2026-08-26 en el SQL Editor, junto con los de
--   `fn_auto_cierre` y `fn_registrar_marcaje`. Los tres coinciden con esta Mac.
--
-- MD5 DE LLEGADA (medido DESPUÉS de fijar el número 0318 — el marcador
--   «CAMBIO 00NN» cambia con él, y el hash cambia mientras la longitud NO)
--   → 291b5832218258c618e3434aa0634093 · 4 819 caracteres
--   Si no coincide pero la longitud sí:
--   select position('CAMBIO 0318' in prosrc) from pg_proc
--    where proname='fn_reabrir_dia';   → 928
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_reabrir_dia(p_persona_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- ⇩⇩⇩ CAMBIO 0318 ⇩⇩⇩ LA JORNADA MANDA SOBRE EL CALENDARIO.
    --
    -- Acá decía solo `(m.timestamp_marca at time zone 'America/Lima')::date =
    -- v_hoy`, y con eso esta función ANULABA LA SALIDA REAL DE ANOCHE.
    --
    -- Quien cierra tienda a las 00:30 tiene su salida guardada con la
    -- `fecha_jornada` del día anterior — eso lo hace bien la 0240. Pero por
    -- calendario esa marca ES de hoy, así que era la que encontraba este
    -- `select`, y el `update` de abajo la anulaba.
    --
    -- Medido contra el Postgres local, con el caso del informe de agosto: Ana
    -- entra el martes 15:00 y cierra a las 00:30 del miércoles. Jornada del
    -- martes: 9,50 h cerradas, S/109,62. Tras pulsar «Sí, volví a entrar»: sin
    -- horas, abierta, S/0,00.
    --
    -- `coalesce` y no `fecha_jornada = v_hoy` a secas: las marcas normales NO
    -- llevan esa columna —solo la lleva la salida que cruza medianoche— así que
    -- exigirla dejaría sin poder reabrir a todo el mundo. El caso corriente es
    -- el null.
    --
    -- ESTA ES LA SEGUNDA BARRERA, no la primera. El terminal ya no muestra esa
    -- pantalla desde que reparte por `fecha_jornada`
    -- (`jornadaEnCursoPorPersona`), así que el botón no se pulsa. Esto cubre lo
    -- que quede: una pestaña vieja abierta desde ayer, o la cola offline
    -- reenviando algo. Las dos mitades del par se arreglan juntas, que es la
    -- lección que este repo lleva pagando todo agosto.
    and coalesce(m.fecha_jornada,
                 (m.timestamp_marca at time zone 'America/Lima')::date) = v_hoy
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
$function$

;

insert into migraciones_aplicadas (numero, nombre)
values (318, '0318_reabrir_el_dia_no_toca_la_salida_de_anoche')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
-- Un solo select, porque el SQL Editor de Supabase corre nada más el último.
select
  case when (select count(*) from migraciones_aplicadas where numero = 318) = 1
        and (select count(*) from pg_proc
              where proname = 'fn_reabrir_dia'
                and prosrc like '%CAMBIO 0318%'
                and prosrc like '%coalesce(m.fecha_jornada%') = 1
       then '0318 · OK — reabrir el día ya no puede tocar la salida de anoche'
       else '0318 · ATENCION — no entró, revisa antes de seguir'
  end as resultado,
  (select md5(prosrc)    from pg_proc where proname = 'fn_reabrir_dia') as md5_de_llegada,
  (select length(prosrc) from pg_proc where proname = 'fn_reabrir_dia') as caracteres;
