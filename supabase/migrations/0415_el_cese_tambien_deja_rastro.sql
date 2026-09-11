-- ============================================================================
-- 0415 · EL CESE TAMBIÉN DEJA RASTRO
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cesar a una persona deje una fila en `correcciones_auditoria` —quién
--   lo hizo y con qué motivo— igual que ya hace su hermana `fn_reactivar_persona`
--   desde la 0209. No cambia ningún candado ni ninguna regla de negocio: la
--   fecha, el `estado`, el cierre de tramos de salario/horario y los mensajes
--   de error quedan byte por byte iguales a la 0327.
--
-- QUÉ ASUME
--   Que `fn_es_admin_o_lider()` en true implica `fn_persona_actual_id()` no
--   nulo dentro de la misma transacción: las dos leen
--   `personas where auth_user_id = auth.uid()` (0005/0078), así que si hay rol
--   admin/líder hay fila. El chequeo explícito de abajo es, por eso, un
--   cinturón que nunca debería dispararse en un cese real — mismo espíritu
--   defensivo que ya usa `fn_cambiar_regimen_pension` (0261) para el mismo par
--   de funciones.
--
-- POR QUÉ IMPORTA
--   De los cuatro campos "sensibles" que ya tienen puerta única (régimen de
--   pensión → 0261, rol → 0295/0296, sede → 0342, y el cese, que siempre fue
--   una función y nunca un UPDATE directo desde el navegador), el cese era el
--   único sin auditoría — pese a ser el de mayor consecuencia: decide la
--   liquidación y si hubo causa justa. Hoy, cesar con el motivo equivocado
--   ("renuncia" en vez de "despido justificado", que cambia lo que corresponde
--   pagar) no deja ningún rastro de qué se escribió ni quién lo escribió;
--   corregirlo exige reactivar y volver a cesar, y esas dos tampoco lo cuentan.
--   Señalado en la auditoría de arquitectura del 2026-09-03
--   (`docs/hallazgos-abiertos.md`, sección "Alta", comparación contra otros ERP)
--   y verificado hoy con `donde-vive.sh`: seguía en la 0327, sin tocar.
--
-- POR QUÉ UNA SOLA FILA, Y NO UNA POR COLUMNA
--   `fn_cambiar_regimen_pension` audita un campo porque cambia un solo campo.
--   El cese cambia cuatro (`estado`, `fecha_cese`, `motivo_cese`,
--   `tipo_vinculo`) a la vez, pero son una sola decisión de negocio, no cuatro
--   independientes — no hay un mundo donde `estado` cambie sin que cambien las
--   otras tres. Una fila con `campo_modificado = 'personas.estado'` y el motivo
--   de negocio (el texto de `p_motivo`, más `p_tipo_vinculo` si vino) en el
--   campo `motivo` es proporcional al hecho; cuatro filas idénticas en
--   `corregido_at` serían ruido para quien lea el historial de la persona.
--
-- CÓMO SE REVIERTE
--   Pegar de nuevo el cuerpo vigente en `0327_el_candado_de_horas_pasa_a_ser_por_grupo.sql`
--   (líneas 2164-2238) con `create or replace function`. No hay trigger ni
--   tabla nueva que dropear.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
--
-- MD5 DE PARTIDA (ground truth, Postgres LOCAL — contenedor
-- supabase_db_cayla-dynamic, migración 409 aplicada, `pg_proc.prosrc`):
--   con comentarios:  2c252903cef9d78cbcc4253fe510774e
--   sin comentarios:  d37d1a4cc3ad5357df7552f66a1ca342
--   longitud: 3375
-- Aún NO verificado contra producción — eso se hace en el mensaje en que se
-- entregue este SQL, no en este archivo, por la regla de la casa (CLAUDE.md).
-- ============================================================================

create or replace function fn_cesar_persona(
  p_persona_id uuid,
  p_fecha_cese date,
  p_motivo text,
  p_tipo_vinculo text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_p personas%rowtype; v_hoy date := (now() at time zone 'America/Lima')::date;
        v_desde date;
        v_actor uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un cese.';
  end if;

  -- Se pide temprano, antes de tocar nada: si no se puede auditar, no se cesa.
  -- Ver "QUÉ ASUME" arriba — en la práctica nunca debería disparar esta rama.
  v_actor := fn_persona_actual_id();
  if v_actor is null then
    raise exception 'No puedo identificar quién hace el cese, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  -- 0174: toma el candado de la fila ANTES de mirar el estado, para que un
  -- segundo cese simultáneo espere aquí, relea la fila ya cesada y rebote.
  select * into v_p from personas where id = p_persona_id for update;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva (cesó el %).', to_char(v_p.fecha_cese, 'DD/MM/YYYY');
  end if;

  -- La fecha tiene que ser posible.
  if p_fecha_cese > v_hoy then
    raise exception 'El último día trabajado no puede ser futuro (pusiste %).', to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;
  if p_fecha_cese < v_p.fecha_ingreso then
    raise exception 'El último día trabajado (%) no puede ser anterior a su ingreso (%).',
      to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_p.fecha_ingreso, 'DD/MM/YYYY');
  end if;

  -- No se cesa dentro de un periodo ya pagado: eso cambiaría el cálculo de una
  -- planilla cerrada. Mismo criterio que fn_set_fecha_ingreso (0037), acotado a
  -- esta persona para no congelar al equipo entero.
  if fn_fecha_en_periodo_pagado(p_fecha_cese, p_persona_id) then
    raise exception 'El % cae dentro de un periodo de planilla ya PAGADO. Reabre ese periodo primero (queda rastro) o corrige la fecha.',
      to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;

  -- 0176: no se puede cerrar un tramo que todavía no empezó. Se avisa acá, con
  -- la fecha concreta y qué hacer, en vez de dejar que reviente el constraint.
  select min(vigente_desde) into v_desde from asignaciones_salario
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un salario que empieza el %, después del último día que pusiste (%). Corrige ese salario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  select min(vigente_desde) into v_desde from horarios_asignados
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un horario que empieza el %, después del último día que pusiste (%). Corrige ese horario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  -- Sus tramos se cierran. Hoy quedan abiertos para siempre y eso hace que un
  -- salario "vigente" siga apareciendo años después de que la persona se fue.
  update asignaciones_salario set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;
  update horarios_asignados  set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;

  update personas
     set estado = 'inactivo',
         fecha_cese = p_fecha_cese,
         motivo_cese = p_motivo,
         tipo_vinculo = coalesce(p_tipo_vinculo, tipo_vinculo),
         fecha_estado_cambio = now()
   where id = p_persona_id;

  -- El rastro que faltaba. p_motivo no es texto libre: son los códigos fijos
  -- de `personas_motivo_cese_valido` (0086/0143/0325, p. ej. 'despido'), así
  -- que el texto sale corto — sigue siendo más de lo que había, que era nada.
  -- `||` propaga NULL, así que cuando no vino p_tipo_vinculo el `coalesce` de
  -- afuera cae en '.' — sin `if` aparte.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'personas.estado', 'activo', 'inactivo',
     v_actor,
     'Cese con último día trabajado el ' || to_char(p_fecha_cese, 'DD/MM/YYYY')
       || '. Motivo: ' || p_motivo
       || coalesce('. Vínculo pasa a ' || p_tipo_vinculo || '.', '.'));
end;
$function$;

grant  execute on function fn_cesar_persona(uuid, date, text, text) to authenticated;
revoke execute on function fn_cesar_persona(uuid, date, text, text) from public, anon;

comment on function fn_cesar_persona(uuid, date, text, text) is
  'Única forma de cesar a una persona. Cierra sus tramos de salario y horario en la fecha de cese, '
  'se niega si el cese cae en un periodo YA PAGADO o antes de un tramo futuro, y deja rastro en '
  '`correcciones_auditoria` con el motivo y quién lo hizo — igual que su hermana '
  '`fn_reactivar_persona` (0209). Antes de la 0415, era el único de los cuatro campos sensibles '
  '(régimen de pensión, rol, sede, cese) sin auditoría, pese a ser el de mayor consecuencia.';

-- ── Cómo se comprueba que entró ──────────────────────────────────────────────
select
  case when prosrc ilike '%correcciones_auditoria%'
    then '✅ fn_cesar_persona ya audita'
    else '❌ no entró'
  end
from pg_proc where proname = 'fn_cesar_persona';

insert into migraciones_aplicadas (numero, nombre) values (415, 'el_cese_tambien_deja_rastro')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
