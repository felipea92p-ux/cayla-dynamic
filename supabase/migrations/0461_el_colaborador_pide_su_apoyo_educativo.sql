-- ============================================================================
-- 0461 — El colaborador pide su propio apoyo educativo, y DO lo aprueba
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Hasta hoy solo Desarrollo Organizacional podía dar de alta una asignación
--   por educación: la integrante tenía que pedírselo por otro canal (chat,
--   conversación) para que alguien de DO llenara el formulario por ella.
--
--   Esta migración le da a cualquier integrante una SOLICITUD: llena el mismo
--   formulario (institución, de quién es el estudio, costo, fechas, un
--   comprobante inicial opcional), y queda «pendiente». DO la aprueba —nace la
--   asignación real, con el mismo cálculo de siempre— o la rechaza con un
--   motivo que la integrante lee y puede corregir.
--
--   Tres piezas, siguiendo el mismo molde que la 0450:
--     SOLICITUD (educacion_solicitudes)  lo que pide la integrante.
--     REVISIÓN  (fn_educacion_resolver_solicitud)  DO aprueba o rechaza.
--     ASIGNACIÓN (asignaciones_educacion)  nace SOLO al aprobar, con
--       fn_educacion_registrar — la misma función y el mismo cálculo del 75 %
--       con tope por rango que ya usa el alta manual. No hay una segunda
--       fórmula que mantener sincronizada con la primera.
--
-- LO QUE DECIDIÓ FELIPE (2026-09-15)
--
--   · El monto NUNCA lo declara la integrante: lo sigue calculando el sistema
--     al aprobar, exactamente como hoy. La solicitud no lleva un campo monto.
--   · Puede tener una sola solicitud pendiente a la vez.
--   · Un rechazo no bloquea: puede volver a solicitar cuantas veces quiera.
--   · Mientras está pendiente puede verla y retirarla (mismo patrón que
--     retirar una entrega de constancia). Revisada, queda en su historial.
--   · Aprobar/rechazar cuenta en el mismo «Pendientes de revisión» de
--     Educación —el mismo bolito del menú, la misma Bandeja— y no en una
--     categoría aparte.
--
-- POR QUÉ NO HAY UN «MONTO ESTIMADO» EN PANTALLA PARA LA INTEGRANTE
--
--   `fn_educacion_saldo`/`fn_educacion_monto` (0281) tienen su propio guard:
--   «cuánto estudia una persona y cuánto cobra por ello es dato de DO». Darle
--   a la integrante un cálculo en vivo del tope de su rango significaría
--   sortear ese guard —tocar una regla de acceso a datos financieros que nadie
--   me pidió cambiar—. Se prefirió no hacerlo: ella ve lo que declaró (costo,
--   fechas); el monto lo ve por primera vez cuando DO aprueba, igual que hoy
--   lo ve recién cuando DO da de alta la asignación a mano.
--
-- QUÉ ASUME
--
--   · md5 de PARTIDA, medidos contra el estado que deja la 0453 aplicada
--     (0450+0451+0452+0453 en una transacción de prueba, 2026-09-15 — la base
--     local compartida sigue en la 0449, así que no se pudo pedir a
--     producción; Felipe lo reconfirma en el SQL Editor antes de pegar):
--       fn_educacion_por_atender   a8fdbfef94cbe078b30e504a5bf9e0c9 ·  440
--       fn_bandeja_marcar_visto    5a80418516d4a6d60dad579ef8542cf8 ·  725
--     Si alguno cambió antes de pegar, PARAR: alguien las reescribió.
--   · `fn_educacion_registrar`, `fn_educacion_situacion`, `asignaciones_educacion`,
--     `educacion_entregas`, el bucket `comprobantes` y sus funciones de la 0450,
--     `bandeja_vistos` (0436/0450/0453), `correcciones_auditoria`,
--     `fn_hoy_lima`, `fn_es_admin_o_lider`, `fn_persona_actual_id`.
--
-- QUÉ NO HACE
--
--   · No toca `fn_planilla_calcular`, `fn_educacion_saldo` ni `fn_educacion_monto`:
--     el cálculo del 75 % con tope por rango es exactamente el mismo de siempre.
--   · No cambia qué es una entrega/constancia ni cómo se revisa (0450): una
--     solicitud aprobada nace como una asignación normal, que a partir de ahí
--     sigue el camino de constancias que ya existe.
--   · No manda correos.
--
-- CÓMO SE REVIERTE
--
--   Las solicitudes que ya se enviaron SE PIERDEN al revertir: guardarlas antes
--   (`select * from educacion_solicitudes`).
--
--   drop trigger if exists trg_educacion_solicitud_inmutable on educacion_solicitudes;
--   drop function if exists educacion_solicitudes;
--   drop table educacion_solicitudes;
--   -- fn_educacion_por_atender y fn_bandeja_marcar_visto: volver a pegar los
--   -- cuerpos declarados arriba como «md5 de PARTIDA» (son los que deja la 0453).
--   alter table bandeja_vistos drop constraint if exists bandeja_vistos_tipo_item_check;
--   alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check check (tipo_item in (
--     'revision', 'revision_movilidad', 'revision_contrato',
--     'solicitud_vacacion', 'solicitud_perfil',
--     'entrega_educacion', 'aviso_fin_educacion'));
--   -- políticas del almacén: drop policy comprobantes_insert_solicitud_propia,
--   -- comprobantes_update_solicitud_propia;
--   drop function if exists fn_educacion_solicitar(text,numeric,text,text,date,date,text,text),
--     fn_educacion_retirar_solicitud(uuid), fn_educacion_resolver_solicitud(uuid,boolean,text),
--     fn_educacion_solicitudes_pendientes(), fn_educacion_puede_subir_solicitud(text);
-- ============================================================================


-- ── A · La tabla ─────────────────────────────────────────────────────────────
-- Los estados que nunca deben existir, uno por constraint (CLAUDE.md, «estados
-- imposibles primero»): igual molde que educacion_entregas (0450).
create table if not exists educacion_solicitudes (
  id                  uuid primary key default gen_random_uuid(),
  persona_id          uuid not null references personas(id),
  institucion         text not null,
  costo_declarado     numeric not null,
  beneficiario        text not null,
  beneficiario_nombre text,
  vigente_desde       date not null,
  vigente_hasta       date not null,
  comprobante_url     text,
  nota                text,
  estado              text not null default 'pendiente',
  enviada_at          timestamptz not null default now(),
  revisada_at         timestamptz,
  revisada_por        uuid references personas(id),
  motivo_rechazo      text,
  retirada_at         timestamptz,
  -- La asignación que nació al aprobar. null hasta entonces; nunca cambia después.
  asignacion_id       uuid references asignaciones_educacion(id),

  constraint educacion_solicitud_estado_valido check (estado in ('pendiente', 'aprobada', 'rechazada', 'retirada')),
  constraint educacion_solicitud_beneficiario_valido check (beneficiario in ('trabajador', 'hijo')),
  constraint educacion_solicitud_costo_positivo check (costo_declarado > 0),
  constraint educacion_solicitud_fechas_validas check (vigente_hasta >= vigente_desde),
  constraint educacion_solicitud_pendiente_sin_revision check (
    estado <> 'pendiente'
    or (revisada_at is null and revisada_por is null and retirada_at is null and asignacion_id is null)),
  constraint educacion_solicitud_aprobada_completa check (
    estado <> 'aprobada'
    or (revisada_at is not null and revisada_por is not null and asignacion_id is not null and motivo_rechazo is null)),
  constraint educacion_solicitud_rechazada_completa check (
    estado <> 'rechazada'
    or (revisada_at is not null and revisada_por is not null and asignacion_id is null
        and motivo_rechazo is not null and length(trim(motivo_rechazo)) >= 3)),
  constraint educacion_solicitud_retirada_con_fecha check ((estado = 'retirada') = (retirada_at is not null))
);

comment on table educacion_solicitudes is
  'Lo que pide una integrante para que CAYLA le abra un apoyo educativo (0461). DO la aprueba '
  '—nace la asignación vía fn_educacion_registrar— o la rechaza con motivo. No se borra ni se '
  'reescribe: se retira mientras está pendiente, o queda en el historial.';

-- Una sola solicitud pendiente por persona (red contra el doble envío, mismo
-- mecanismo que uq_educacion_entrega_pendiente).
create unique index if not exists uq_educacion_solicitud_pendiente
  on educacion_solicitudes (persona_id) where estado = 'pendiente';
create index if not exists idx_educacion_solicitudes_persona
  on educacion_solicitudes (persona_id, enviada_at desc);
create index if not exists idx_educacion_solicitudes_pendientes
  on educacion_solicitudes (enviada_at) where estado = 'pendiente';

alter table educacion_solicitudes enable row level security;
revoke all on educacion_solicitudes from authenticated, anon, public;
grant select on educacion_solicitudes to authenticated;

drop policy if exists educacion_solicitudes_lectura on educacion_solicitudes;
create policy educacion_solicitudes_lectura on educacion_solicitudes
  for select to authenticated
  using (fn_es_admin_o_lider() is true or persona_id = fn_persona_actual_id());


-- ── B · Lo revisado no se reescribe ni se borra (mismo molde que la 0450) ───
create or replace function fn_educacion_solicitud_inmutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una solicitud de apoyo educativo no se borra: se retira mientras está pendiente, o queda en el historial.';
  end if;

  if (new.persona_id, new.institucion, new.costo_declarado, new.beneficiario, new.beneficiario_nombre,
      new.vigente_desde, new.vigente_hasta, new.comprobante_url, new.nota, new.enviada_at)
     is distinct from
     (old.persona_id, old.institucion, old.costo_declarado, old.beneficiario, old.beneficiario_nombre,
      old.vigente_desde, old.vigente_hasta, old.comprobante_url, old.nota, old.enviada_at) then
    raise exception 'Lo que se pidió en una solicitud no se reescribe. Si hay que corregirlo, se envía otra.';
  end if;

  if old.estado <> 'pendiente'
     and (new.estado, new.revisada_at, new.revisada_por, new.motivo_rechazo, new.retirada_at, new.asignacion_id)
         is distinct from
         (old.estado, old.revisada_at, old.revisada_por, old.motivo_rechazo, old.retirada_at, old.asignacion_id) then
    raise exception 'Esta solicitud ya está %: su revisión no se cambia.', old.estado;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_educacion_solicitud_inmutable on educacion_solicitudes;
create trigger trg_educacion_solicitud_inmutable
  before update or delete on educacion_solicitudes
  for each row execute function fn_educacion_solicitud_inmutable();


-- ── C · La integrante pide, ve y retira su solicitud ─────────────────────────
create or replace function fn_educacion_solicitar(
  p_institucion         text,
  p_costo_declarado     numeric,
  p_beneficiario        text,
  p_beneficiario_nombre text default null,
  p_vigente_desde       date default null,
  p_vigente_hasta       date default null,
  p_comprobante_url     text default null,
  p_nota                text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  v_id uuid;
begin
  if v_yo is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;

  if p_institucion is null or length(trim(p_institucion)) < 3 then
    raise exception 'Escribe qué institución emite el comprobante.';
  end if;
  if p_beneficiario not in ('trabajador', 'hijo') then
    raise exception 'Elige de quién es el estudio.';
  end if;
  if p_beneficiario = 'hijo' and (p_beneficiario_nombre is null or length(trim(p_beneficiario_nombre)) < 3) then
    raise exception 'Escribe a nombre de quién está el comprobante.';
  end if;
  if p_costo_declarado is null or p_costo_declarado <= 0 then
    raise exception 'El costo que dice el comprobante tiene que ser mayor que cero.';
  end if;
  if p_vigente_desde is null or p_vigente_hasta is null then
    raise exception 'Indica desde y hasta cuándo vale el comprobante.';
  end if;
  if p_vigente_hasta < p_vigente_desde then
    raise exception 'La fecha de fin es anterior a la de inicio.';
  end if;

  begin
    insert into educacion_solicitudes
      (persona_id, institucion, costo_declarado, beneficiario, beneficiario_nombre,
       vigente_desde, vigente_hasta, comprobante_url, nota)
    values
      (v_yo, trim(p_institucion), p_costo_declarado, p_beneficiario,
       nullif(trim(coalesce(p_beneficiario_nombre, '')), ''), p_vigente_desde, p_vigente_hasta,
       p_comprobante_url, nullif(trim(coalesce(p_nota, '')), ''))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud pendiente de revisión. Retírala si quieres cambiarla.';
  end;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'educacion_solicitud', null,
     trim(p_institucion) || ' · costo declarado S/' || to_char(p_costo_declarado, 'FM999999.00'),
     v_yo, 'Solicitud de apoyo educativo enviada');

  return v_id;
end;
$$;

create or replace function fn_educacion_retirar_solicitud(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  v_s  educacion_solicitudes%rowtype;
begin
  select * into v_s from educacion_solicitudes where id = p_id for update;
  if not found then raise exception 'Esa solicitud no existe.'; end if;

  if v_yo is null or v_s.persona_id is distinct from v_yo then
    raise exception 'Solo quien envió la solicitud puede retirarla.';
  end if;
  if v_s.estado <> 'pendiente' then
    raise exception 'Esta solicitud ya está % y queda en el historial: no se retira.', v_s.estado;
  end if;

  update educacion_solicitudes set estado = 'retirada', retirada_at = now() where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'educacion_solicitud', 'pendiente', 'retirada', v_yo, 'La integrante retiró su solicitud antes de la revisión');
end;
$$;


-- ── D · DO revisa: aprobar nace la asignación, rechazar exige motivo ─────────
-- Aprobar llama a fn_educacion_registrar — el MISMO cálculo del 75 % con tope
-- por rango que usa el alta manual. No hay una segunda fórmula que mantener
-- sincronizada con la primera (CLAUDE.md, «antes de agregar, borra» / «núcleo
-- mínimo»): si esa función cambia el día de mañana, esta la sigue sin tocarla.
create or replace function fn_educacion_resolver_solicitud(
  p_id      uuid,
  p_aprobar boolean,
  p_motivo  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_s       educacion_solicitudes%rowtype;
  v_asig_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional revisa solicitudes de apoyo educativo.';
  end if;

  -- `for update`: si dos personas de DO la revisan a la vez, la segunda espera,
  -- lee el estado ya cambiado, y recibe el aviso de abajo.
  select * into v_s from educacion_solicitudes where id = p_id for update;
  if not found then raise exception 'Esa solicitud no existe.'; end if;

  if v_s.estado <> 'pendiente' then
    raise exception 'Esta solicitud ya está %: alguien la revisó antes.', v_s.estado;
  end if;
  if v_s.persona_id = v_yo then
    raise exception 'No puedes aprobar tu propia solicitud: la revisa otra persona de Desarrollo Organizacional.';
  end if;

  if p_aprobar is true then
    v_asig_id := fn_educacion_registrar(
      v_s.persona_id, v_s.institucion, v_s.costo_declarado, v_s.beneficiario,
      v_s.vigente_desde, v_s.vigente_hasta, v_s.beneficiario_nombre, v_s.comprobante_url,
      v_s.nota, null, null);

    update educacion_solicitudes
       set estado = 'aprobada', revisada_at = now(), revisada_por = v_yo, asignacion_id = v_asig_id
     where id = p_id;
  else
    if p_motivo is null or length(trim(p_motivo)) < 3 then
      raise exception 'Escribe qué corregir: la integrante lo va a leer.';
    end if;

    update educacion_solicitudes
       set estado = 'rechazada', revisada_at = now(), revisada_por = v_yo, motivo_rechazo = trim(p_motivo)
     where id = p_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_s.persona_id, 'educacion_solicitud', 'pendiente', 'rechazada', v_yo, trim(p_motivo));
  end if;

  return v_asig_id;
end;
$$;

-- Para Bandeja y `/admin/educacion`: una fila por solicitud pendiente, con lo
-- que la pantalla necesita para pintarla sin una segunda consulta. Mismo molde
-- que fn_educacion_entregas_pendientes (0450).
create or replace function fn_educacion_solicitudes_pendientes()
returns table (
  id             uuid,
  persona_id     uuid,
  persona        text,
  sede           text,
  institucion    text,
  costo_declarado numeric,
  vigente_desde  date,
  vigente_hasta  date,
  enviada_at     timestamptz,
  comprobante_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.persona_id, p.nombres || ' ' || p.apellidos, coalesce(sed.codigo, '?'),
         s.institucion, s.costo_declarado, s.vigente_desde, s.vigente_hasta, s.enviada_at,
         s.comprobante_url
    from educacion_solicitudes s
    join personas p on p.id = s.persona_id
    left join sedes sed on sed.id = p.sede_base_id
   where fn_es_admin_o_lider() is true and s.estado = 'pendiente'
   order by s.enviada_at;
$$;

grant execute on function fn_educacion_solicitar(text,numeric,text,text,date,date,text,text) to authenticated;
grant execute on function fn_educacion_retirar_solicitud(uuid)                              to authenticated;
grant execute on function fn_educacion_resolver_solicitud(uuid,boolean,text)                to authenticated;
grant execute on function fn_educacion_solicitudes_pendientes()                             to authenticated;


-- ── E · El almacén: la integrante sube el comprobante de SU solicitud ────────
-- Mismo molde que fn_educacion_puede_subir_entrega (0450), pero antes de que
-- exista ninguna asignación: la ruta es educacion/<persona>/solicitudes/<solicitud>/<archivo>,
-- y se puede escribir ahí solo mientras esa solicitud no exista todavía. Leerla
-- ya la cubre fn_educacion_puede_ver (0136): no distingue subcarpeta.
create or replace function fn_educacion_puede_subir_solicitud(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_persona    text := split_part(p_path, '/', 2);
  v_solicitud  text := split_part(p_path, '/', 4);
begin
  if split_part(p_path, '/', 1) <> 'educacion' or split_part(p_path, '/', 3) <> 'solicitudes' then
    return false;
  end if;
  if v_persona !~ '^[0-9a-fA-F-]{36}$' or v_solicitud !~ '^[0-9a-fA-F-]{36}$' then
    return false;
  end if;
  if v_persona::uuid is distinct from fn_persona_actual_id() then
    return false;
  end if;
  return not exists (select 1 from educacion_solicitudes where id = v_solicitud::uuid);
end;
$$;

grant execute on function fn_educacion_puede_subir_solicitud(text) to authenticated;

drop policy if exists comprobantes_insert_solicitud_propia on storage.objects;
create policy comprobantes_insert_solicitud_propia on storage.objects
  for insert to authenticated
  with check (bucket_id = 'comprobantes' and fn_educacion_puede_subir_solicitud(name) is true);

-- `x-upsert` de la subida es un UPDATE cuando se reintenta el mismo archivo.
drop policy if exists comprobantes_update_solicitud_propia on storage.objects;
create policy comprobantes_update_solicitud_propia on storage.objects
  for update to authenticated
  using      (bucket_id = 'comprobantes' and fn_educacion_puede_subir_solicitud(name) is true)
  with check (bucket_id = 'comprobantes' and fn_educacion_puede_subir_solicitud(name) is true);


-- ── F · El contador y la Bandeja aprenden la solicitud ───────────────────────
-- Cuerpo de la 0450 (md5 de partida arriba) con un cambio marcado.
create or replace function fn_educacion_por_atender()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case when fn_es_admin_o_lider() is not true then 0 else
    (select count(*)::int from educacion_entregas where estado = 'pendiente')
    -- ⇩ CAMBIO 0461 ⇩ las solicitudes pendientes cuentan igual que las entregas.
    + (select count(*)::int from educacion_solicitudes where estado = 'pendiente')
    + (select count(*)::int from fn_educacion_situacion() s
        where s.estado_constancia = 'vencida'
           or (s.estado_constancia = 'sin_calendario' and s.vigencia in ('vigente', 'por_terminar')))
    + (select count(*)::int from educacion_avisos_fin where atendido_at is null)
  end;
$$;

alter table bandeja_vistos drop constraint if exists bandeja_vistos_tipo_item_check;
alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check check (tipo_item in (
  'revision', 'revision_movilidad', 'revision_contrato',
  'solicitud_vacacion', 'solicitud_perfil',
  'entrega_educacion', 'aviso_fin_educacion',
  'solicitud_educacion'
));

-- Cuerpo de la 0453 (md5 de partida arriba) con un tipo agregado.
create or replace function fn_bandeja_marcar_visto(p_tipo_item text, p_item_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;
  -- ⇩ CAMBIO 0461 ⇩ solicitud_educacion.
  if p_tipo_item not in ('revision', 'revision_movilidad', 'revision_contrato',
                          'solicitud_vacacion', 'solicitud_perfil',
                          'entrega_educacion', 'aviso_fin_educacion',
                          'solicitud_educacion') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$$;

grant execute on function fn_bandeja_marcar_visto(text, uuid) to authenticated;
revoke execute on function fn_bandeja_marcar_visto(text, uuid) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (461, 'el_colaborador_pide_su_apoyo_educativo')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
