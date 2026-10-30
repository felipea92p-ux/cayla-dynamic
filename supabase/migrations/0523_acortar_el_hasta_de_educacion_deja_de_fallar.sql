-- ============================================================================
-- 0523 — Acortar el «hasta» de una asignación por educación deja de fallar
-- ============================================================================
--
-- QUÉ PROMETE
--   Que dar por terminada una asignación por educación en una fecha ANTERIOR al
--   primer periodo abierto funcione, desde la pantalla de Educación (Corregir)
--   y desde «Cerrar». Hasta hoy fallaba con «Alguno de los datos no es válido»,
--   y dejaba pagándose en octubre un apoyo que ya había terminado.
--
-- QUÉ SE VIO (2026-10-16, Sandra Ramírez, AQP)
--   · Duolingo, tramo 2: del 29/08 al 28/09, S/104.25. El periodo de octubre
--     arranca el 28/09 (los periodos se encadenan al día siguiente del cierre
--     anterior, y septiembre cerró el 27/09), así que la fila seguía vigente el
--     PRIMER día de octubre.
--   · Ese primer día es el «día de referencia» de la regla de la 0233 (el primer
--     día del periodo con alguna asignación vigente). Solo Duolingo lo estaba, y
--     las otras dos —Pop in colors S/135 e Italo Peruano S/30, desde el 10/10—
--     quedaban sin pagar. La boleta de octubre sumaba S/104.25 donde tocaban
--     S/165.00, y por el concepto equivocado.
--   · Corregir la fila con «hasta» 21/09 caía en la rama «mueve plata» de
--     fn_educacion_registrar: la fila vieja se cierra el día anterior al primer
--     periodo abierto y nace otra desde ese día —el 28/09—, con hasta 21/09.
--     desde > hasta viola el check de la tabla (0120) y la base lo rechaza con el
--     error 23514, que la pantalla traduce a un aviso que no dice nada.
--   · «Cerrar» tampoco servía: miraba si la fecha de CIERRE (27/09) cae en un
--     periodo pagado, y el 27/09 es el último día de septiembre.
--
-- QUÉ CAMBIA
--   1. fn_educacion_registrar: un recorte puro —misma persona, mismo costo, mismo
--      inicio, fin más temprano— cierra la fila en esa fecha en vez de abrir una
--      vigencia nueva. Antes comprueba que los días QUE SE QUITAN (del siguiente
--      al fin nuevo en adelante) no caigan en un periodo pagado; si caen, el
--      mensaje dice cuál es la fecha de fin más temprana que se admite.
--      Si el fin es anterior al primer periodo abierto y además cambia otra cosa,
--      dice eso, en vez del aviso genérico.
--   2. fn_educacion_cerrar: mismo criterio —al acortar se mira el día siguiente
--      al fin nuevo—. Alargar o fijar sigue mirando la fecha escrita.
--
-- QUÉ NO CAMBIA (y queda pendiente)
--   La regla del día de referencia en fn_planilla_calcular. Mientras un estudio
--   pueda terminar justo el primer día de un periodo, tapa a los demás de esa
--   persona. Con este cambio el caso de Sandra se resuelve con sus datos
--   (Duolingo hasta el 27/09); la regla en sí necesita reescribir la función de
--   planilla entera y va aparte.
--
-- POR QUÉ ASÍ
--   · Un recorte no mueve plata en lo ya pagado: quita días del final. La rama
--     de «mueve plata» existe para cambios de costo o de inicio, que sí tocan lo
--     que se devengó.
--   · Lo pagado sigue intacto: acortar hasta una fecha que deja días de un
--     periodo pagado sin cobertura se rechaza, como antes.
--   · Deja rastro en correcciones_auditoria ('educacion_cierre', con el motivo).
--
-- MD5 DE PARTIDA (pedidos a PRODUCCIÓN el 2026-10-16, antes de escribir)
--   fn_educacion_registrar  0398618a4324d32278b2f7b37e9b8c65 · 9985 caracteres  (0450)
--   fn_educacion_cerrar     abf7fbd0f40c145d2ff8671b9226555f · 1128 caracteres  (0327)
--   Coinciden con el repositorio tal cual. Se vuelven a pedir al ENTREGAR.
--
-- CÓMO SE REVIERTE
--   Repegar fn_educacion_registrar de la 0450 y fn_educacion_cerrar de la 0327.
--   No toca datos ni esquema.
-- ============================================================================

create or replace function fn_educacion_registrar(
  p_persona_id          uuid,
  p_institucion         text,
  p_costo_declarado     numeric,
  p_beneficiario        text,
  p_vigente_desde       date,
  p_vigente_hasta       date,
  p_beneficiario_nombre text default null,
  p_comprobante_url     text default null,
  p_nota                text default null,
  p_id                  uuid default null,   -- no nulo = corregir
  p_motivo              text default null    -- obligatorio al corregir
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id       uuid;
  v_yo       uuid := fn_persona_actual_id();
  v_monto    numeric;
  v_vieja    asignaciones_educacion%rowtype;
  v_mueve    boolean;
  v_desde    date;
  v_borrada  boolean := false;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra asignaciones por educación.';
  end if;

  if p_institucion is null or length(trim(p_institucion)) < 3 then
    raise exception 'Falta la institución que emite el comprobante.';
  end if;
  if p_beneficiario not in ('trabajador', 'hijo') then
    raise exception 'El beneficiario es «trabajador» o «hijo» (llegó «%»).', p_beneficiario;
  end if;
  if p_beneficiario = 'hijo'
     and (p_beneficiario_nombre is null or length(trim(p_beneficiario_nombre)) < 3) then
    raise exception 'Si el comprobante es de un hijo, escribe a nombre de quién está.';
  end if;
  if p_costo_declarado is null or p_costo_declarado <= 0 then
    raise exception 'El costo que dice el comprobante tiene que ser mayor que cero.';
  end if;
  if p_vigente_hasta is null then
    raise exception 'Falta hasta cuándo vale el comprobante. Una matrícula cubre un ciclo, no la eternidad.';
  end if;
  if p_vigente_hasta < p_vigente_desde then
    raise exception 'La fecha de fin (%) es anterior a la de inicio (%).', p_vigente_hasta, p_vigente_desde;
  end if;

  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no existe o no está activa.';
  end if;

  -- ⇩ CAMBIO 0281 ⇩ con las fechas y excluyendo la fila que se corrige.
  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado,
                                p_vigente_desde, p_vigente_hasta, p_id);

  if v_monto <= 0 then
    raise exception
      'No queda techo libre para esas fechas: las asignaciones que ya tiene vigentes '
      'agotan el tope de su rango. Cierra o acorta la otra asignación, mueve estas '
      'fechas, o sube el tope en topes_educacion_rango si la política cambió.';
  end if;

  -- ── Alta ────────────────────────────────────────────────────────────────
  if p_id is null then
    if fn_educacion_fecha_pagada(p_vigente_desde, p_persona_id) is true then
      raise exception
        'Esa fecha de inicio (%) cae en un periodo ya PAGADO: registrarla cambiaría una '
        'planilla cerrada. Registra desde el periodo abierto, o reabre el periodo primero.',
        p_vigente_desde;
    end if;

    insert into asignaciones_educacion (
      persona_id, monto, institucion, costo_declarado, cobertura_pct,
      beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
      nota, registrado_por
    ) values (
      p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
      p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      p_vigente_desde, p_vigente_hasta,
      nullif(trim(coalesce(p_nota, '')), ''), v_yo
    )
    returning id into v_id;

    -- ⇩ CAMBIO 0290 ⇩ El papel entra en educacion_comprobantes, que desde la
    -- 0450 lo refleja como entrega aprobada.
    if p_comprobante_url is not null then
      insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
      values (v_id, p_comprobante_url, fn_educacion_mes_del_periodo(p_vigente_desde), v_yo)
      on conflict do nothing;
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (p_persona_id, 'educacion_alta', null,
       trim(p_institucion) || ' · S/' || to_char(v_monto, 'FM999999.00') ||
       ' · ' || p_vigente_desde::text || ' a ' || p_vigente_hasta::text,
       v_yo, coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Alta de asignación por educación'));

    return v_id;
  end if;

  -- ── Corrección ──────────────────────────────────────────────────────────
  select * into v_vieja from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se corrige. Esto mueve lo que cobra una persona.';
  end if;

  -- ¿La corrección mueve plata? Sólo el costo y las fechas lo hacen. Cambiar el
  -- nombre de la institución o subir el comprobante que faltaba no cambia un
  -- céntimo, y obligar a abrir vigencia nueva por eso llenaría la lista de filas
  -- cerradas por erratas.
  v_mueve := (v_vieja.costo_declarado is distinct from p_costo_declarado)
          or (v_vieja.vigente_desde   is distinct from p_vigente_desde)
          or (v_vieja.vigente_hasta   is distinct from p_vigente_hasta)
          or (v_vieja.persona_id      is distinct from p_persona_id);

  if not v_mueve then
    update asignaciones_educacion set
      institucion         = trim(p_institucion),
      beneficiario        = p_beneficiario,
      beneficiario_nombre = nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      nota                = nullif(trim(coalesce(p_nota, '')), '')
    where id = p_id;

    -- El comprobante se enlaza en un segundo paso, cuando el archivo terminó de
    -- subir. Desde la 0290 eso es una fila más, no un update de la columna.
    if p_comprobante_url is not null then
      insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
      values (p_id, p_comprobante_url, fn_educacion_mes_del_periodo(v_vieja.vigente_desde), v_yo)
      on conflict do nothing;
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_vieja.persona_id, 'educacion_datos', v_vieja.institucion,
       trim(p_institucion), v_yo, trim(p_motivo));

    return p_id;
  end if;

  -- ⇩ CAMBIO 0450 ⇩ Las constancias son del estudio de ESA persona: cambiar de
  -- persona una asignación que ya tiene constancias le colgaría el historial
  -- de una a otra.
  if v_vieja.persona_id is distinct from p_persona_id and exists (
       select 1 from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
        where x.familia_id = v_vieja.familia_id) then
    raise exception
      'Esta asignación ya tiene constancias de otra persona: no se le cambia la persona. '
      'Ciérrala y registra una nueva.';
  end if;

  -- ⇩ CAMBIO 0523 ⇩ Acortar SOLO el «hasta» no abre una vigencia nueva: cierra.
  -- Un recorte puro —misma persona, mismo costo, mismo inicio, fin más temprano—
  -- no mueve lo que cobra nadie en lo ya pagado: quita días del final. La rama de
  -- abajo, pensada para cambios de costo o de inicio, fuerza que el cambio rija
  -- desde el primer periodo abierto; con un fin anterior a ese día fabricaba una
  -- fila con desde > hasta y la base la rechazaba (check de 0120), con el aviso
  -- genérico «Alguno de los datos no es válido». Lo que sí hay que cuidar es que
  -- los días que se QUITAN —del día siguiente al fin nuevo en adelante— no caigan
  -- en un periodo pagado; la fecha de fin nueva puede estar en uno.
  if v_vieja.persona_id = p_persona_id
     and v_vieja.costo_declarado = p_costo_declarado
     and v_vieja.vigente_desde = p_vigente_desde
     and p_vigente_hasta < coalesce(v_vieja.vigente_hasta, 'infinity'::date) then

    if fn_educacion_fecha_pagada(p_vigente_hasta + 1, p_persona_id) is true then
      raise exception
        'Acortar hasta el % quitaría días de un periodo ya PAGADO: lo pagado no se reescribe. '
        'La fecha de fin más temprana que se admite es el %.',
        p_vigente_hasta, fn_educacion_desde_cuando_puede_regir() - 1;
    end if;

    update asignaciones_educacion
       set vigente_hasta       = p_vigente_hasta,
           institucion         = trim(p_institucion),
           beneficiario        = p_beneficiario,
           beneficiario_nombre = nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
           nota                = nullif(trim(coalesce(p_nota, '')), '')
     where id = p_id;

    if p_comprobante_url is not null then
      insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
      values (p_id, p_comprobante_url, fn_educacion_mes_del_periodo(v_vieja.vigente_desde), v_yo)
      on conflict do nothing;
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_vieja.persona_id, 'educacion_cierre', v_vieja.vigente_hasta::text,
       p_vigente_hasta::text, v_yo, trim(p_motivo));

    return p_id;
  end if;

  -- ⇩ CAMBIO 0523 ⇩ Si llegó aquí con el fin anterior al día en que puede regir
  -- el cambio, mezcló un recorte con otro cambio (costo, inicio…): se dice, en
  -- vez de dejar que la base lo rechace sin explicar.
  if p_vigente_hasta < greatest(fn_educacion_desde_cuando_puede_regir(), v_vieja.vigente_desde) then
    raise exception
      'Esa fecha de fin (%) es anterior al primer periodo abierto (%), y junto con ella cambias '
      'otra cosa. Lo ya pagado no se corrige: acorta solo el «hasta», o cambia lo otro aparte.',
      p_vigente_hasta, greatest(fn_educacion_desde_cuando_puede_regir(), v_vieja.vigente_desde);
  end if;

  -- Mueve plata: la fila vieja se cierra el día anterior al que rige el cambio y
  -- nace una nueva. Lo ya pagado queda escrito tal como se pagó.
  v_desde := greatest(fn_educacion_desde_cuando_puede_regir(), v_vieja.vigente_desde);

  if fn_educacion_fecha_pagada(v_desde, p_persona_id) is true then
    raise exception
      'No hay ningún periodo abierto desde el que aplicar esta corrección: todos los que '
      'tocan esta asignación están pagados. Reabre el periodo primero.';
  end if;

  -- ⇩ CAMBIO 0281 ⇩ el tramo que de verdad va a regir, no el que se escribió.
  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado,
                                greatest(v_desde, p_vigente_desde), p_vigente_hasta, p_id);

  if v_monto <= 0 then
    raise exception
      'No queda techo libre para esas fechas: las asignaciones que ya tiene vigentes '
      'agotan el tope de su rango. Cierra o acorta la otra asignación, mueve estas '
      'fechas, o sube el tope en topes_educacion_rango si la política cambió.';
  end if;

  if v_desde > v_vieja.vigente_desde then
    update asignaciones_educacion
       set vigente_hasta = v_desde - 1
     where id = p_id;
  else
    -- La fila vieja nunca llegó a devengar en un periodo pagado: se reemplaza
    -- entera en vez de dejar un tramo de un día que no significa nada.
    delete from asignaciones_educacion where id = p_id;
    v_borrada := true;
  end if;

  -- ⇩ CAMBIO 0281 ⇩ `created_at` viaja con la fila. Desde esta migración ese
  -- campo decide el orden en que las asignaciones se reparten el techo, así que
  -- corregir una no puede mandarla al final de la cola.
  -- ⇩ CAMBIO 0450 ⇩ y también la familia y el calendario de pagos.
  insert into asignaciones_educacion (
    persona_id, monto, institucion, costo_declarado, cobertura_pct,
    beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
    nota, registrado_por, created_at,
    familia_id, frecuencia_pago, proxima_fecha_pago
  ) values (
    p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
    p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
    greatest(v_desde, p_vigente_desde), p_vigente_hasta,
    nullif(trim(coalesce(p_nota, '')), ''), v_yo, v_vieja.created_at,
    case when v_vieja.persona_id = p_persona_id then v_vieja.familia_id end,
    v_vieja.frecuencia_pago, v_vieja.proxima_fecha_pago
  )
  returning id into v_id;

  -- ⇩ CAMBIO 0450 ⇩ Ya no se copian los papeles a la vigencia nueva: la
  -- familia los comparte. Si la vieja se borró, lo que colgaba de ella se muda.
  if v_borrada then
    update educacion_entregas  set asignacion_id = v_id where asignacion_id = p_id;
    update educacion_avisos_fin set asignacion_id = v_id where asignacion_id = p_id;
  end if;

  if p_comprobante_url is not null then
    insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
    values (v_id, p_comprobante_url,
            fn_educacion_mes_del_periodo(greatest(v_desde, p_vigente_desde)), v_yo)
    on conflict do nothing;
  end if;

  perform fn_educacion_refrescar_espejo(
    (select familia_id from asignaciones_educacion where id = v_id));

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'educacion_nueva_vigencia',
     'S/' || to_char(v_vieja.monto, 'FM999999.00') || ' desde ' || v_vieja.vigente_desde::text,
     'S/' || to_char(v_monto, 'FM999999.00') || ' desde ' || greatest(v_desde, p_vigente_desde)::text,
     v_yo, trim(p_motivo));

  return v_id;
end;
$$;

grant execute on function fn_educacion_registrar(uuid,text,numeric,text,date,date,text,text,text,uuid,text)
  to authenticated;

create or replace function fn_educacion_cerrar(p_id uuid, p_hasta date, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r       asignaciones_educacion%rowtype;
  v_toca  date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional cierra asignaciones por educación.';
  end if;

  select * into r from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_hasta < r.vigente_desde then
    raise exception 'La fecha de cierre (%) es anterior al inicio (%).', p_hasta, r.vigente_desde;
  end if;

  -- ⇩ CAMBIO 0523 ⇩ Se mira lo que el cierre CAMBIA, no la fecha que se escribe.
  -- Acortar quita los días desde el siguiente al fin nuevo; que el fin nuevo sea
  -- el último día de un periodo pagado (el 27/09 cuando octubre empieza el 28/09)
  -- no toca nada pagado, y la 0327 lo rechazaba igual. Alargar o fijar sí cambia
  -- el día que se escribe, así que ahí manda esa fecha, como siempre.
  v_toca := case when p_hasta < coalesce(r.vigente_hasta, 'infinity'::date)
                 then p_hasta + 1 else p_hasta end;

  if fn_educacion_fecha_pagada(v_toca, r.persona_id) is true then
    raise exception
      'Esa fecha de cierre (%) cambiaría días de un periodo ya PAGADO (desde el %): '
      'la vigencia no se acorta ahí.', p_hasta, v_toca;
  end if;

  update asignaciones_educacion set vigente_hasta = p_hasta where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id, 'educacion_cierre', r.vigente_hasta::text, p_hasta::text,
     fn_persona_actual_id(),
     coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Cierre de asignación por educación'));
end;
$$;

grant execute on function fn_educacion_cerrar(uuid, date, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (523, 'acortar_el_hasta_de_educacion_deja_de_fallar')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
