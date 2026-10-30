-- ============================================================================
-- 0564 — Se puede acortar la asignación de educación de quien ya no está activo
-- ============================================================================
--
-- QUÉ PROMETE
--   Que DO pueda corregir el «hasta» de una asignación por educación de una
--   persona que ya cesó (inactiva), siempre que sea para ACORTARLO.
--
-- QUÉ SE VIO (2026-10-29/30, Emily Rico y Milagritos Zárate)
--   · Su asignación quedó guardada con «hasta» 29/10 y debía ser 28/10, el último
--     día del periodo. Al corregirla, la pantalla mostraba «¿De quién es?» vacío
--     y la base respondía «Esa persona no existe o no está activa.», sin llegar a
--     mirar la fecha: fn_educacion_registrar exigía personas.estado = 'activo'
--     también al CORREGIR. Las dos están inactivas.
--
-- QUÉ CAMBIA
--   fn_educacion_registrar, una sola condición:
--   · Alta (p_id nulo): igual que antes, la persona tiene que estar activa.
--   · Corrección (p_id no nulo): la asignación tiene que existir y ser de esa
--     persona. Si la persona está inactiva, solo se admite acortar el «hasta»:
--     el inicio y el costo no pueden cambiar y el fin no puede alargarse. Así no
--     se abre dinero nuevo a nombre de alguien que ya no trabaja.
--   Todo lo demás —la rama de recorte de la 0523, los periodos pagados, el
--   techo, la auditoría— queda tal cual. fn_educacion_cerrar no se toca.
--
-- POR QUÉ ASÍ
--   · Alargar o cambiar costo/inicio de un cesado SÍ movería plata: eso sigue
--     rechazado con un mensaje que dice por qué.
--   · Acortar es lo que repara un dato que ya no es cierto, y la 0523 ya lo
--     trata como recorte puro (no mueve lo pagado).
--
-- MD5 DE PARTIDA (pedido a PRODUCCIÓN el 2026-10-30, antes de escribir)
--   fn_educacion_registrar  c42ed2a996d76a08b96fe589df093240 · 12865 caracteres
--   = el cuerpo de la 0523 byte por byte (migraciones_aplicadas trae 450, 523,
--   524 y 529). OJO: el archivo de la 0523 NO está en main todavía; vive en la
--   rama claude/correction-not-allowed-95d14e. Esta migración parte de su cuerpo.
--   Se vuelve a pedir al ENTREGAR y DESPUÉS de renumerar.
--
-- CÓMO SE REVIERTE
--   Repegar fn_educacion_registrar de la 0523. No toca datos ni esquema.
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

  -- ⇩ CAMBIO 0564 ⇩ Una persona inactiva no recibe asignaciones nuevas, pero sí se
  -- le puede ACORTAR la que ya tenía: quien cesó antes de que terminara su
  -- vigencia sigue figurando hasta una fecha que ya no es cierta.
  if p_id is null then
    if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
      raise exception 'Esa persona no existe o no está activa.';
    end if;
  else
    select * into v_vieja from asignaciones_educacion
     where id = p_id and persona_id = p_persona_id;
    if v_vieja.id is null then
      raise exception 'Esa asignación no existe o no es de esa persona.';
    end if;
    if not exists (select 1 from personas where id = p_persona_id and estado = 'activo')
       and (p_vigente_hasta > v_vieja.vigente_hasta
            or p_vigente_desde <> v_vieja.vigente_desde
            or p_costo_declarado <> v_vieja.costo_declarado) then
      raise exception
        'Esa persona ya no está activa: de su asignación solo se puede acortar el «hasta», '
        'sin cambiar el inicio ni el costo.';
    end if;
  end if;
  -- ⇧ CAMBIO 0564 ⇧

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

insert into migraciones_aplicadas (numero, nombre)
values (564, 'se_puede_acortar_la_asignacion_de_educacion_de_quien_ya_no_esta_activo')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
