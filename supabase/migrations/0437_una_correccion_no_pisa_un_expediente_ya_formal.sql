-- ============================================================================
-- 0437 — Corregir un marcaje no pisa un expediente disciplinario ya formal
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que ninguna de las cinco puertas que tocan un marcaje
-- (fn_corregir_marca, fn_anular_marcaje, fn_reactivar_marcaje,
-- fn_confirmar_auto_cierre, fn_agregar_marcaje) deje corregir el día de una
-- persona cuando ya existe, para esa misma fecha, un expediente disciplinario
-- FIRMADO o ENTREGADO construido sobre el dato que se está a punto de cambiar.
--
-- Auditoría de la pantalla de Correcciones (2026-09-13): hoy se puede corregir
-- cualquier marcaje sin ningún aviso aunque ya exista un memo o una
-- amonestación firmada sobre esa fecha — el hueco de mayor consecuencia legal
-- que encontró esa auditoría, y el que Felipe decidió cerrar bloqueando.
--
-- QUÉ ASUME:
--   · Que expediente_disciplinario no tiene, ni tuvo nunca, un marcaje_id ni
--     un jornada_id: su único vínculo con el hecho es persona_id + la columna
--     `hechos jsonb`, un arreglo de {fecha, hora_prog, hora_marca, minutos}
--     (tardanza) o {fecha, tipo} (falta) — confirmado leyendo 0056 y sus
--     ALTER posteriores (0075, 0205, 0206, 0212, 0303, 0408), y
--     fn_expediente_generar_falta (vigente en 0390) / fn_expediente_generar_
--     tardanza (vigente en 0413), que arman `hechos` leyendo `jornadas`,
--     nunca `marcajes`. Por eso el candado compara por FECHA, no por id.
--   · Que 'borrador' NO bloquea. Un expediente en borrador todavía no se le
--     entregó a nadie ni lo firmó nadie — corregir el marcaje ANTES de
--     formalizarlo es, si acaso, lo deseable: evita generar mal un memo que
--     todavía no existe para la persona. El candado solo mira 'firmado' y
--     'entregado' (del check constraint de 0056: 'borrador','firmado',
--     'entregado','anulado', más 'cerrado_sin_entrega' de la 0412) — que es
--     cuando el hecho ya quedó comunicado o decidido. 'anulado' y
--     'cerrado_sin_entrega' tampoco bloquean: ya están inertes.
--   · Que la fecha correcta para comparar es la de la JORNADA
--     (fn_fecha_de_jornada), no la del reloj — la misma variable
--     v_fecha_jornada que fn_anular_marcaje, fn_reactivar_marcaje,
--     fn_corregir_marca y fn_confirmar_auto_cierre ya calculan para el
--     candado de periodo pagado (0307/0327). fn_agregar_marcaje es la única
--     de las cinco que no maneja cruce de medianoche (no calcula
--     fecha_jornada al insertar): ahí se compara contra su propia v_fecha,
--     que es la misma que ya usa para su propio candado de periodo pagado.
--
-- POR QUÉ SE ELIGIÓ ASÍ:
--   · Un helper nuevo, fn_dia_con_expediente_formal(persona_id, fecha), en vez
--     de repetir el jsonb_array_elements cinco veces: es la misma pregunta
--     («¿esta persona ya tiene, para este día, un expediente formal?») hecha
--     desde cinco puertas distintas, y este repositorio ya sabe lo que cuesta
--     responder la misma pregunta de cinco formas distintas (0386-0389, sobre
--     "cuál es el vigente"). Un solo lugar, mismo criterio en las cinco.
--   · Se BLOQUEA, no se avisa-y-se-deja-seguir ni se deja como está: un memo
--     firmado sobre un hecho que el sistema mismo acaba de invalidar es
--     exactamente lo que el art. 25 del D.S. 003-97-TR pide evitar (sanción
--     sustentada y progresiva, documentada) — un aviso que alguien puede no
--     leer no es una garantía real, y el costo de frenar acá es un paso extra
--     (ir a Disciplina primero), no una imposibilidad.
--   · El mensaje de la excepción manda a Disciplina y explica la consecuencia,
--     no solo dice "no se puede": la salida es resolver o anular el
--     expediente ahí, no quedarse trabado sin saber por qué.
--
-- QUÉ NO CAMBIA: ninguna firma (los mismos argumentos de siempre en las cinco
-- funciones, así que no hace falta `drop` ni volver a `grant`), el candado de
-- periodo pagado (0307/0327), la máquina de estados, fn_verificar_corrector,
-- ni nada más de lo que ya hacían estas cinco funciones — el único bloque
-- nuevo en cada una es el marcado «CAMBIO 0437», insertado justo después del
-- candado de periodo pagado ya existente. Cuerpos de partida verificados
-- contra 0327_el_candado_de_horas_pasa_a_ser_por_grupo.sql con donde-vive.sh
-- el 2026-09-13 (única definición vigente en las cinco; el Postgres local no
-- tiene aplicadas todas las migraciones hoy, así que el cuerpo se tomó del
-- archivo, no de pg_get_functiondef — confirmar el md5 contra producción
-- antes de pegar, como manda CLAUDE.md).
--
-- SE REVIERTE: `drop function fn_dia_con_expediente_formal(uuid, date)` y
-- `create or replace` de las cinco funciones con el cuerpo que trae
-- 0327_el_candado_de_horas_pasa_a_ser_por_grupo.sql (líneas 277-797 de esa
-- migración).
-- ============================================================================

-- ── El helper: la misma pregunta, un solo lugar ─────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_dia_con_expediente_formal(p_persona_id uuid, p_fecha date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
      from expediente_disciplinario e
     where e.persona_id = p_persona_id
       and e.estado in ('firmado', 'entregado')
       and exists (
             select 1 from jsonb_array_elements(e.hechos) h
              where (h->>'fecha')::date = p_fecha
           )
  );
$function$;

comment on function fn_dia_con_expediente_formal(uuid, date) is
  '0437 — true si esa persona ya tiene, para esa fecha, un expediente '
  'disciplinario firmado o entregado que cuenta ese día entre sus hechos. '
  'Compara por fecha porque expediente_disciplinario no referencia ningún '
  'marcaje_id ni jornada_id: solo persona_id + hechos jsonb.';

-- ── 1 · fn_anular_marcaje ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la anulación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca ya está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0437 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(v_ant.persona_id, v_fecha_jornada) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado construido sobre este marcaje: anularlo lo dejaría sustentado en un hecho que el propio sistema acaba de invalidar. Resuelve o anula el expediente en Disciplina antes de tocar este marcaje.';
  end if;

  update marcajes
     set anulada_at = now(), anulada_por = v_corr, anulada_motivo = trim(p_motivo)
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_anulado',
          v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, 'anulada', v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$function$;

-- ── 2 · fn_reactivar_marcaje ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la reactivación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  -- Autorización primero: los mensajes de estado de abajo cuentan cosas de una
  -- marca que quien pregunta puede no tener derecho a conocer.
  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is null then
    raise exception 'Esa marca no está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: reactivarla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0437 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(v_ant.persona_id, v_fecha_jornada) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado construido sobre este marcaje: reactivarlo cambiaría el hecho sobre el que ya se construyó ese expediente. Resuelve o anula el expediente en Disciplina antes de tocar este marcaje.';
  end if;

  if v_ant.tipo = 'salida_final' and exists (
    select 1 from marcajes
    where persona_id = v_ant.persona_id
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null
      and id <> p_marcaje_id
  ) then
    raise exception 'Ese día ya tiene otra salida final activa. Anula primero la que sobra: dos salidas finales el mismo día dejan el cálculo al azar.';
  end if;

  update marcajes
     set anulada_at = null, anulada_por = null, anulada_motivo = null
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_reactivado',
          'anulada: ' || coalesce(v_ant.anulada_motivo, ''), v_ant.tipo::text, v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$function$;

-- ── 3 · fn_corregir_marca ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_corregir_marca(p_marcaje_id uuid, p_nuevo_tipo tipo_marca DEFAULT NULL::tipo_marca, p_nuevo_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_tipo tipo_marca; v_ts timestamptz; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada: reactívala antes de corregirla.';
  end if;

  v_tipo := coalesce(p_nuevo_tipo, v_ant.tipo);
  v_ts   := coalesce(p_nuevo_ts,   v_ant.timestamp_marca);
  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  if v_tipo = v_ant.tipo and v_ts = v_ant.timestamp_marca then
    raise exception 'No hay nada que cambiar en esa marca.';
  end if;

  if fn_familia_marca(v_tipo) is distinct from fn_familia_marca(v_ant.tipo) then
    raise exception 'No se puede convertir % en %: una salida solo puede pasar a ser otra salida, y un retorno a otro retorno.',
      v_ant.tipo, v_tipo;
  end if;

  if (v_ts at time zone 'America/Lima')::date is distinct from v_fecha then
    raise exception 'Esa corrección movería la marca al %, y aquí solo se corrige la hora dentro de su mismo día. Si de verdad pertenece a otro día: anúlala y agrégala en el día correcto.',
      to_char((v_ts at time zone 'America/Lima')::date, 'DD/MM/YYYY');
  end if;

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: corregirla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0437 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(v_ant.persona_id, v_fecha_jornada) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado construido sobre este marcaje: corregirlo cambiaría el hecho sobre el que ya se construyó ese expediente. Resuelve o anula el expediente en Disciplina antes de tocar este marcaje.';
  end if;

  update marcajes
     set tipo = v_tipo, timestamp_marca = v_ts, estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  if v_tipo is distinct from v_ant.tipo then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'tipo', v_ant.tipo::text, v_tipo::text, v_corr, trim(p_motivo));
  end if;
  if v_ts is distinct from v_ant.timestamp_marca then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, v_ts::text, v_corr, trim(p_motivo));
  end if;

  -- ¿La corrección dejó el día imposible? Se sella, igual que hace el terminal.
  -- Avisa sin impedir: el flujo normal pasa por aquí a mitad de camino.
  if fn_dia_incoherente(v_ant.persona_id, v_fecha) then
    update marcajes
       set estado_revision = 'pendiente_revision'
     where persona_id = v_ant.persona_id
       and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
       and anulada_at is null
       and estado_revision = 'normal';
  else
    perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  end if;

  return v_nuevo;
end;
$function$;

-- ── 4 · fn_confirmar_auto_cierre ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.origen <> 'auto_cierre' then
    raise exception 'Solo se confirma una marca puesta por el auto-cierre.';
  end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada.';
  end if;
  if v_ant.estado_revision = 'revisada' then
    raise exception 'Ese auto-cierre ya está confirmado.';
  end if;

  -- CAMBIO 0307 · Acá `v_fecha` no lo usa nadie más que el candado, así que
  -- pasa a ser directamente la fecha de la JORNADA: una marca de madrugada
  -- pertenece al turno que cierra, no al día del calendario en que cae.
  v_fecha := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  -- CAMBIO 0327 · El candado mira el GRUPO (tipo_vinculo) de la persona
  -- dueña de la marca, no el periodo entero: si planilla ya pagó pero RxH
  -- todavía no, confirmar un auto-cierre de alguien de planilla sigue
  -- bloqueado aunque el grupo RxH de ese periodo siga abierto.
  if fn_fecha_en_periodo_pagado(v_fecha, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: confirmarla haría que ese día empiece a medir salida anticipada y tiempo adicional, cambiando una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0437 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(v_ant.persona_id, v_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado construido sobre este marcaje: confirmarlo cambiaría cómo se mide ese día (salida anticipada, tiempo adicional), el mismo hecho sobre el que ya se construyó ese expediente. Resuelve o anula el expediente en Disciplina antes de confirmar esta marca.';
  end if;

  update marcajes set estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'auto_cierre_confirmado',
          'pendiente_revision', 'revisada', v_corr,
          coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Confirmado: esa es su salida final.'));

  return v_nuevo;
end;
$function$;

-- ── 5 · fn_agregar_marcaje ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_agregar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_ts timestamp with time zone, p_motivo text, p_motivo_otro text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sede uuid; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  v_fecha := (p_ts at time zone 'America/Lima')::date;

  if fn_fecha_en_periodo_pagado(v_fecha, p_persona_id) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: agregar un marcaje ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0437 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(p_persona_id, v_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado construido sobre él: agregar un marcaje ahí cambiaría el hecho que ese expediente ya documentó. Resuelve o anula el expediente en Disciplina antes de agregar este marcaje.';
  end if;

  v_corr := fn_verificar_corrector(p_persona_id);

  -- La sede la manda el DÍA, no el escritorio: si la persona ya marcó ese día
  -- (por ejemplo, de visita en otra tienda), la corrección se graba en esa misma
  -- sede. Solo si el día está vacío cae a su sede base. Sin esto, la jornada
  -- queda partida entre dos sedes y el terminal ve media verdad.
  select m.sede_id into v_sede
  from marcajes m
  where m.persona_id = p_persona_id
    and (m.timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and m.sede_id is not null
  order by m.timestamp_marca, m.id
  limit 1;

  if v_sede is null then
    select sede_base_id into v_sede from personas where id = p_persona_id;
  end if;
  if v_sede is null then raise exception 'Persona no encontrada.'; end if;

  insert into marcajes (client_uuid, persona_id, sede_id, tipo, motivo_otro, timestamp_marca, origen, estado_revision)
  values (gen_random_uuid(), p_persona_id, v_sede, p_tipo, p_motivo_otro, p_ts, 'admin_correccion', 'revisada')
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_nuevo.id, p_persona_id, 'marcaje_agregado', null, p_tipo::text || ' @ ' || p_ts::text, v_corr, trim(p_motivo));

  perform fn_resellar_dia(p_persona_id, v_fecha);

  return v_nuevo;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre) values (437, 'una_correccion_no_pisa_un_expediente_ya_formal')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- Las cinco puertas llevan el marcador nuevo, y sigue habiendo una sola
-- versión de cada una (ninguna quedó con sobrecarga por accidente).
select
  p.proname,
  position('CAMBIO 0437' in p.prosrc) > 0 as tiene_el_candado,
  (select count(*) from pg_proc pp where pp.proname = p.proname) as una_sola_version
from pg_proc p
where p.proname in ('fn_anular_marcaje', 'fn_reactivar_marcaje', 'fn_corregir_marca',
                     'fn_confirmar_auto_cierre', 'fn_agregar_marcaje')
order by p.proname;
