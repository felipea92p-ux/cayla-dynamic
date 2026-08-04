-- ============================================================================
-- 0137 — Reabrir el día sin dejarlo a medias
-- ============================================================================
--
-- QUÉ PROMETE
--   Reabrir el día de alguien que ya marcó su salida final es UNA operación:
--   o quedan las cuatro escrituras (se anula la salida final, se emite la
--   salida temporal en su mismo instante, se emite el retorno, y se deja el
--   rastro en `correcciones_auditoria`), o no queda ninguna. Nunca a medias.
--
-- QUÉ ASUME
--   · Quien llama tiene sesión de una terminal ACTIVA (`terminales.auth_user_id`
--     = `auth.uid()`). No se recibe la terminal por parámetro a propósito: un
--     id que viaja en el cuerpo de la petición lo elige quien llama.
--   · `fn_recalcular_jornada` es idempotente (0081), así que llamarla de más
--     no cuesta nada.
--   · La persona a la que se le reabre el día está en la misma sede donde marcó.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--   Esto ya existía, escrito a mano en `apps/web/app/api/reabrir-dia/route.ts`
--   con la llave de servicio. Esa versión hace tres escrituras sueltas —
--   reclasificar la salida, insertar el retorno, recalcular— sin transacción
--   que las una. Si la segunda falla después de que la primera pasó, la salida
--   final YA quedó convertida en salida temporal y no hay retorno: la persona
--   figura adentro indefinidamente, sus horas dejan de cerrar, y el único
--   registro de lo que pasó es un error en el log de Vercel. Ese es el estado a
--   medias que da nombre a esta migración. El cuerpo de una función plpgsql es
--   una sola transacción; ahí el estado intermedio no existe.
--
--   Y al bajarlo a la base se ganan tres cosas que la ruta no tenía:
--
--   · EL CANDADO DE PERIODO PAGADO. La ruta deja reabrir un día que cae dentro
--     de un periodo ya PAGADO. Reabrirlo mueve las horas con las que se pagó, y
--     la foto (0096) empieza a discrepar sin que nadie lo pidiera.
--   · EL RASTRO. La ruta muta el marcaje sin dejar traza. Toda edición manual
--     deja rastro en `correcciones_auditoria` con motivo obligatorio; esta no lo
--     hacía, y es la que más lo necesita porque la dispara la propia persona.
--   · APPEND-ONLY. La ruta hace `update marcajes set tipo = 'salida_otro'` sobre
--     la marca original: exactamente lo que la 0081 prohibió. Acá la original se
--     ANULA y se emiten dos marcas nuevas. La marca que la persona hizo de
--     verdad sigue siendo legible tal como la hizo.
--
--   La salida temporal se emite en el MISMO instante que la original y no en
--   `now()`: el rato de afuera tiene que descontarse desde que la persona se
--   fue, no desde que el sistema se enteró. Emitirla en `now()` le regala los
--   minutos que tardó en volver a la terminal.
--
--   La sede se compara contra la sede DEL MARCAJE y no contra la sede base de
--   la persona. Es lo que hace que quien viaja entre sedes funcione sin un `if`
--   aparte: si marcó su salida en TRU, es la terminal de TRU la que la corrige.
--
-- DE DÓNDE SALE ESTE ARCHIVO
--   El 2026-08-04 a las 21:04 este SQL se aplicó a mano contra el Postgres local
--   y se registró como 0137 en `migraciones_aplicadas`, pero el archivo nunca se
--   guardó en git: la función quedó viva en la base y sin fuente. Este archivo
--   la recupera **verbatim** desde `pg_get_functiondef`, sin un solo cambio de
--   comportamiento, para que el número 0137 vuelva a tener dueño. Se conserva su
--   número —y no se le da uno nuevo— porque el registro ya dice 137 con este
--   nombre: renumerarla dejaría el 137 muerto para siempre y abriría otro hueco.
--
-- LO QUE ESTA MIGRACIÓN NO HACE, Y HAY QUE SABERLO
--   **Nadie la llama todavía.** `fn_reabrir_dia` no aparece en una sola línea de
--   `apps/web`: la terminal sigue pegándole a `/api/reabrir-dia`, que hace el
--   trabajo a mano con la llave de servicio. Aplicar esto no cambia ningún
--   comportamiento — deja el arreglo disponible y apagado.
--
--   Y no se puede cablear la ruta tal como está: corre con la llave de servicio,
--   donde `auth.uid()` es null y esta función respondería siempre «solo se hace
--   desde una terminal activa». La forma correcta es que la terminal la invoque
--   con su propia sesión (ya la tiene: `marcar/page.tsx:247` saca el
--   `access_token`) y que la ruta desaparezca — su única razón de existir era
--   usar la llave de servicio para saltarse RLS, y el guard de sede que la
--   justificaba ahora vive acá adentro. Eso es un cambio de contrato entre la
--   terminal y la base, y va en su propia migración con su propio commit.
--
-- CÓMO SE REVIERTE
--   `drop function if exists fn_reabrir_dia(uuid, text);` y borrar la fila 137 de
--   `migraciones_aplicadas`. No hay cambio de datos ni de esquema que deshacer, y
--   como nada la invoca, quitarla no rompe ninguna pantalla.
--
-- POR QUÉ HAY HUECOS ALREDEDOR
--   0133 · no existe en ningún archivo, rama ni commit. Se saltó al crear la
--          0134 el 2026-08-04. Hueco real, sin dueño.
--   0136 · la toma `origin/educacion-con-comprobante` (commit f1b1fa7, ya en
--          GitHub) con la pantalla de educación y su comprobante.
--   0108 · vive solo en `origin/movilidad-supeditada-a-asistencia`, sin fusionar.
--          La reemplazaron la 0117 y la 0118.
--   0031 y 0033 · existen como `scripts/sql-manual/aplicar_00NN_*.sql`, fuera de
--          git por datos personales.
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
$function$;

-- La 0076 quitó el EXECUTE que PUBLIC tenía por defecto sobre las funciones, así
-- que sin esta línea la terminal —que entra como `authenticated`— no podría
-- invocarla. `service_role` y `postgres` los concede el default privilege.
grant execute on function fn_reabrir_dia(uuid, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (137, 'reabrir_el_dia_sin_dejarlo_a_medias')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_llamadas int;
begin
  select count(*) into v_llamadas
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosrc like '%fn_reabrir_dia%'
    and p.proname <> 'fn_reabrir_dia';

  raise notice '0137 · fn_reabrir_dia recuperada desde la base y versionada.';
  raise notice '0137 · funciones de la base que la invocan: % (se espera 0).', v_llamadas;
  raise notice '0137 · la terminal sigue usando /api/reabrir-dia: esto no cambia ningun comportamiento.';
end $mig$;
