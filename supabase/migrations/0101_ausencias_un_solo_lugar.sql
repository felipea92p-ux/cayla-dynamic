-- ============================================================================
-- 0101 — Ausencias: un solo lugar para «por qué no vino»
-- ----------------------------------------------------------------------------
-- EL PROBLEMA
--
-- 1. El sistema no sabía qué hacer con un permiso concedido. Cuando a alguien
--    se le muere un familiar, o se resfría y se queda en casa, o se lesiona
--    jugando fútbol y descansa dos días, esos días se registran como FALTA
--    INJUSTIFICADA: entran en el semáforo disciplinario, cuentan para los
--    umbrales del art. 25-h y, si se juntan tres, el sistema ofrece generar una
--    carta de preaviso de despido — por los días que la empresa concedió.
--
--    Es exactamente el error que este sistema tiene escrito como el peor de
--    todos: acusar de falta a quien no debía.
--
-- 2. Y «por qué no vino» estaba escrito en CUATRO sitios distintos:
--      · `vacaciones`                    — rangos de fechas
--      · `justificaciones_asistencia`    — días sueltos, sin ninguna pantalla
--      · `expediente_disciplinario`      — días de suspensión
--      · `feriados_descanso_sustitutorio`— días compensatorios
--    Los dos primeros responden literalmente la misma pregunta con dos formas
--    distintas, y uno de ellos lleva meses invisible: existe, funciona, nadie
--    lo puede usar.
--
-- QUÉ PROMETE
--
--   1. Una sola tabla `ausencias` con todos los días que alguien no vino y por
--      qué. Vacaciones es un tipo más, no una tabla aparte.
--   2. Un catálogo `tipos_ausencia` editable: qué tipos hay, cuáles pagan,
--      cuáles exigen documento y cuáles exigen aprobación de DO. Cambiar la
--      política no exige una migración.
--   3. Que un día de ausencia registrada DEJE de contar como falta
--      injustificada, sin tocar ninguna de las funciones de faltas.
--
-- CÓMO SE CONSIGUE LO TERCERO SIN TOCAR NADA — y es la decisión importante
--
-- `vacaciones` y `justificaciones_asistencia` dejan de ser tablas y pasan a ser
-- VISTAS sobre `ausencias`, con exactamente las mismas columnas. Las nueve
-- funciones que las leen —fn_faltas, fn_falta_contadores, fn_faltas_resumen,
-- fn_vacaciones_resumen, fn_planilla_calcular y compañía— siguen funcionando
-- sin que se les cambie una línea.
--
-- Se eligió así después de reescribir a mano el cuerpo de fn_planilla_calcular
-- en la 0100 y perder por el camino el guard de seguridad de la 0090. La
-- lección quedó cara: cuando hay nueve lectores, se mueve el dato debajo de
-- ellos, no se reescriben los nueve.
--
-- QUÉ ASUME
--
--   · Que una persona no puede tener dos ausencias solapadas. No se puede estar
--     de vacaciones y con descanso médico el mismo día: uno de los dos registros
--     está mal, y es mejor que el sistema lo rechace a que los dos convivan y
--     nadie sepa cuál manda.
--   · Que el pago depende del TIPO, no de quién lo registre. Descanso médico y
--     maternidad pagan porque lo manda la ley peruana; el resto no paga porque
--     así lo decidió CAYLA. Un permiso «con goce» no existe en esta empresa.
--   · Que el documento se exige solo donde tiene sentido. En el Perú real,
--     obligar a alguien a sacar un certificado por un resfriado es obligarlo a
--     perder un día haciendo cola para probar algo que nadie discute. Por eso
--     `salud` existe como tipo propio: no paga, no exige papel, y NO es falta.
--
-- LO QUE NO ABSORBE, A PROPÓSITO
--
-- Las suspensiones (`expediente_disciplinario`) y los descansos sustitutorios
-- (`feriados_descanso_sustitutorio`) se quedan donde están. No son ausencias
-- concedidas: una es una sanción y la otra la contrapartida de un feriado
-- trabajado. Meterlas aquí mezclaría tres cosas que se deciden distinto.
--
-- CÓMO SE REVIERTE
--
--   No es reversible en un paso: `vacaciones` y `justificaciones_asistencia`
--   pasan a ser vistas y sus datos viven en `ausencias`. Para volver atrás hay
--   que recrear las dos tablas y volcar de vuelta las filas de su tipo. El
--   contenido no se pierde en ningún momento.
-- ============================================================================

-- ── El catálogo: qué tipos hay y cómo se comporta cada uno ──────────────────
create table if not exists tipos_ausencia (
  codigo               text primary key check (codigo ~ '^[a-z_]{3,30}$'),
  nombre               text not null check (length(trim(nombre)) >= 3),
  -- ¿Cobra esos días? Para descanso médico y maternidad esto lo manda la ley,
  -- no CAYLA: por eso vive en un catálogo y no en un `if` dentro del código.
  paga                 boolean not null default false,
  requiere_documento   boolean not null default false,
  requiere_aprobacion  boolean not null default false,
  descuenta_vacaciones boolean not null default false,
  -- Si en `ventana_alerta_dias` hay más de `alerta_desde` ausencias de este
  -- tipo, el sistema lo señala. No bloquea: avisa.
  alerta_desde         int,
  ventana_alerta_dias  int,
  activo               boolean not null default true,
  orden                int not null default 100
);

comment on table tipos_ausencia is
  'Qué tipos de ausencia existen y cómo se comporta cada uno. Editable sin migración: cambiar la política de permisos no debería exigir tocar el esquema.';
comment on column tipos_ausencia.paga is
  'Para descanso_medico y maternidad lo manda la ley peruana, no CAYLA. Para el resto es decisión de la empresa: en CAYLA no existe el permiso con goce.';

insert into tipos_ausencia (codigo, nombre, paga, requiere_documento, requiere_aprobacion, descuenta_vacaciones, alerta_desde, ventana_alerta_dias, orden) values
  ('vacaciones',       'Vacaciones',                      true,  false, false, true,  null, null, 10),
  ('descanso_medico',  'Descanso médico (con documento)', true,  true,  true,  false, null, null, 20),
  ('maternidad',       'Maternidad / paternidad / lactancia', true, true, true, false, null, null, 30),
  ('salud',            'Descanso por salud (sin documento)', false, false, false, false, 3, 60, 40),
  ('duelo',            'Duelo / fallecimiento de familiar', false, false, false, false, null, null, 50),
  ('permiso_personal', 'Permiso personal',                false, false, false, false, null, null, 60),
  ('cumpleanos',       'Cumpleaños',                      false, false, false, false, null, null, 70),
  ('estudios',         'Estudios',                        false, false, false, false, null, null, 80),
  ('otro',             'Otro',                            false, false, false, false, null, null, 90)
on conflict (codigo) do nothing;

alter table tipos_ausencia enable row level security;
drop policy if exists tipos_ausencia_select on tipos_ausencia;
create policy tipos_ausencia_select on tipos_ausencia
  for select to authenticated using (true);
revoke all on tipos_ausencia from anon, public;
grant select on tipos_ausencia to authenticated;

-- ── La tabla ────────────────────────────────────────────────────────────────
create table if not exists ausencias (
  id            uuid primary key default gen_random_uuid(),
  persona_id    uuid not null references personas(id),
  tipo          text not null references tipos_ausencia(codigo),
  fecha_inicio  date not null,
  fecha_fin     date not null,
  motivo        text,

  -- Solo para los tipos que exigen documento. Lo que se guarda no es el papel:
  -- es quién lo firmó y con qué colegiatura, que es lo verificable.
  doc_profesional  text,
  doc_colegiatura  text,
  doc_fecha        date,

  aprobada_por  uuid references personas(id),
  aprobada_at   timestamptz,

  registrada_por   uuid not null references personas(id),
  registrada_at    timestamptz not null default now(),
  -- Se registró más de 15 días después del hecho. No se prohíbe —el caso real
  -- es enterarse el lunes de algo del jueves— pero queda dicho.
  registrada_tarde boolean not null default false,

  -- Una ausencia no se borra: se anula con motivo. Igual que un marcaje (0081).
  anulada_at     timestamptz,
  anulada_por    uuid references personas(id),
  anulada_motivo text,

  constraint chk_ausencia_rango check (fecha_fin >= fecha_inicio),
  constraint chk_ausencia_anulacion check (
    (anulada_at is null and anulada_por is null and anulada_motivo is null)
    or (anulada_at is not null and anulada_por is not null
        and anulada_motivo is not null and length(trim(anulada_motivo)) >= 4)
  ),
  constraint chk_ausencia_aprobacion check (
    (aprobada_at is null and aprobada_por is null)
    or (aprobada_at is not null and aprobada_por is not null)
  )
);

comment on table ausencias is
  'Todos los días que alguien no vino, y por qué. Absorbe lo que antes eran las tablas `vacaciones` y `justificaciones_asistencia`, que ahora son vistas sobre esta. No absorbe suspensiones ni descansos sustitutorios: esos no son ausencias concedidas.';

create index if not exists idx_ausencias_persona on ausencias (persona_id, fecha_inicio);
create index if not exists idx_ausencias_tipo    on ausencias (tipo, fecha_inicio);

-- Estado imposible, imposible en el esquema: nadie está de vacaciones y con
-- descanso médico el mismo día. Si pasa, uno de los dos registros está mal, y
-- es mejor rechazarlo que dejar que convivan sin que nadie sepa cuál manda.
alter table ausencias drop constraint if exists ausencias_sin_solape;
alter table ausencias add constraint ausencias_sin_solape
  exclude using gist (
    persona_id with =,
    daterange(fecha_inicio, fecha_fin, '[]') with &&
  ) where (anulada_at is null);

alter table ausencias enable row level security;
revoke all on ausencias from anon, public;
grant select on ausencias to authenticated;

-- admin/líder ven todo · la encargada ve su sede · cada persona ve lo suyo.
-- Escrituras: ninguna policy, solo por las funciones de abajo.
drop policy if exists ausencias_select_admin_lider on ausencias;
create policy ausencias_select_admin_lider on ausencias
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists ausencias_select_supervisor on ausencias;
create policy ausencias_select_supervisor on ausencias
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and exists (select 1 from personas p
                 where p.id = ausencias.persona_id
                   and p.sede_base_id = fn_sede_actual_persona())
  );

drop policy if exists ausencias_select_propia on ausencias;
create policy ausencias_select_propia on ausencias
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- ── Mudanza: lo que ya existe se trae, no se pierde ─────────────────────────
insert into ausencias (id, persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, registrada_at)
select v.id, v.persona_id, 'vacaciones', v.fecha_inicio, v.fecha_fin, v.observacion, v.creado_por, v.creado_at
from vacaciones v
on conflict (id) do nothing;

-- Las justificaciones sueltas. Si alguna cae DENTRO de un periodo de vacaciones
-- ya migrado, se descarta: es redundante y el constraint de solape la rechazaría.
insert into ausencias (id, persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, registrada_at)
select j.id, j.persona_id,
       case j.motivo when 'permiso_concedido' then 'permiso_personal' else j.motivo end,
       j.fecha, j.fecha, j.observacion, j.creado_por, j.creado_at
from justificaciones_asistencia j
where not exists (
  select 1 from ausencias a
  where a.persona_id = j.persona_id
    and j.fecha between a.fecha_inicio and a.fecha_fin
)
on conflict (id) do nothing;

-- ── Las dos tablas viejas pasan a ser vistas ────────────────────────────────
-- Aquí está el truco de esta migración: las nueve funciones que leen
-- `vacaciones` o `justificaciones_asistencia` siguen leyendo exactamente lo
-- mismo, con los mismos nombres de columna, sin que se les toque una línea.
drop table if exists vacaciones cascade;
create view vacaciones with (security_invoker = true) as
select a.id, a.persona_id, a.fecha_inicio, a.fecha_fin,
       a.motivo as observacion, a.registrada_por as creado_por, a.registrada_at as creado_at
from ausencias a
where a.tipo = 'vacaciones' and a.anulada_at is null;

comment on view vacaciones is
  'Vista sobre `ausencias` (tipo = vacaciones). Era una tabla hasta la 0101. Se conserva con las mismas columnas para que fn_vacaciones_resumen, fn_faltas y la pantalla de Vacaciones sigan funcionando sin cambios.';

drop table if exists justificaciones_asistencia cascade;
create view justificaciones_asistencia with (security_invoker = true) as
select a.id, a.persona_id, g::date as fecha, a.tipo as motivo,
       a.motivo as observacion, a.registrada_por as creado_por, a.registrada_at as creado_at
from ausencias a
cross join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') g
where a.anulada_at is null
  -- Las vacaciones NO entran aquí: fn_faltas ya las mira por su propia puerta y
  -- duplicarlas cambiaría el motivo que muestra la pantalla.
  and a.tipo <> 'vacaciones';

comment on view justificaciones_asistencia is
  'Vista sobre `ausencias`, un día por fila. Era una tabla hasta la 0101 — existía, funcionaba y ninguna pantalla la usaba nunca. Un día de ausencia registrada deja de contar como falta injustificada gracias a esta vista, sin tocar ninguna función de faltas.';

-- Y siguen aceptando escritura directa, para que la mudanza sea de verdad
-- transparente: cualquier script o prueba que insertara en las tablas viejas
-- sigue funcionando, y la fila acaba en `ausencias`. El INSERT NO se concede a
-- `authenticated`: solo lo puede usar quien es dueño del esquema. Desde la
-- aplicación se escribe por las funciones, como siempre.
create or replace function fn_trg_vacaciones_insert()
returns trigger language plpgsql security definer set search_path = public as $t$
begin
  insert into ausencias (id, persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, registrada_at)
  values (coalesce(new.id, gen_random_uuid()), new.persona_id, 'vacaciones',
          new.fecha_inicio, new.fecha_fin, new.observacion,
          new.creado_por, coalesce(new.creado_at, now()));
  return new;
end;
$t$;
drop trigger if exists trg_vacaciones_insert on vacaciones;
create trigger trg_vacaciones_insert instead of insert on vacaciones
  for each row execute function fn_trg_vacaciones_insert();

create or replace function fn_trg_justificaciones_insert()
returns trigger language plpgsql security definer set search_path = public as $t$
begin
  insert into ausencias (id, persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, registrada_at)
  values (coalesce(new.id, gen_random_uuid()), new.persona_id,
          case new.motivo when 'permiso_concedido' then 'permiso_personal' else new.motivo end,
          new.fecha, new.fecha, new.observacion,
          new.creado_por, coalesce(new.creado_at, now()));
  return new;
end;
$t$;
drop trigger if exists trg_justificaciones_insert on justificaciones_asistencia;
create trigger trg_justificaciones_insert instead of insert on justificaciones_asistencia
  for each row execute function fn_trg_justificaciones_insert();

grant select on vacaciones, justificaciones_asistencia to authenticated;
revoke all on vacaciones, justificaciones_asistencia from anon, public;

-- ── Registrar ───────────────────────────────────────────────────────────────
create or replace function fn_registrar_ausencia(
  p_persona_id     uuid,
  p_tipo           text,
  p_fecha_inicio   date,
  p_fecha_fin      date,
  p_motivo         text default null,
  p_doc_profesional text default null,
  p_doc_colegiatura text default null,
  p_doc_fecha      date default null
)
returns uuid
language plpgsql security definer set search_path = public as $fn$
declare
  v_t tipos_ausencia%rowtype;
  v_editor uuid;
  v_id uuid;
  v_tarde boolean;
begin
  -- Quién puede: admin, líder o la encargada de la sede de esa persona. Como
  -- ningún permiso paga por sí solo (los que pagan exigen aprobación de DO más
  -- abajo), que la encargada registre no mueve dinero.
  v_editor := fn_verificar_corrector(p_persona_id);

  select * into v_t from tipos_ausencia where codigo = p_tipo and activo;
  if not found then raise exception 'Ese tipo de ausencia no existe o está desactivado.'; end if;

  if p_fecha_fin < p_fecha_inicio then
    raise exception 'La fecha de fin no puede ser anterior a la de inicio.';
  end if;

  if v_t.requiere_documento and (
       coalesce(trim(p_doc_profesional), '') = ''
    or coalesce(trim(p_doc_colegiatura), '') = ''
    or p_doc_fecha is null)
  then
    raise exception '% exige el documento: profesional o institución, número de colegiatura y fecha de emisión. Si no hay documento, regístralo como «Descanso por salud», que no paga pero tampoco cuenta como falta.', v_t.nombre;
  end if;

  -- Candado de planilla pagada: registrar una ausencia dentro de un periodo ya
  -- cerrado cambiaría lo que se pagó (los tipos que pagan) o el conteo de
  -- faltas de un periodo cerrado (todos los demás).
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and daterange(fecha_ini, fecha_fin, '[]') && daterange(p_fecha_inicio, p_fecha_fin, '[]')
    for share
  ) then
    raise exception 'Esas fechas caen en un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  -- Registrar hacia atrás se permite —el caso real es enterarse el lunes de algo
  -- del jueves— pero por encima de 15 días queda dicho que se registró tarde.
  v_tarde := p_fecha_inicio < fn_hoy_lima() - 15;

  insert into ausencias (
    persona_id, tipo, fecha_inicio, fecha_fin, motivo,
    doc_profesional, doc_colegiatura, doc_fecha,
    registrada_por, registrada_tarde,
    -- Lo que no exige aprobación nace aprobado: pedir un visto bueno que nadie
    -- va a dar sería dejar el registro en un limbo permanente.
    aprobada_por, aprobada_at
  )
  values (
    p_persona_id, p_tipo, p_fecha_inicio, p_fecha_fin, nullif(trim(p_motivo), ''),
    nullif(trim(p_doc_profesional), ''), nullif(trim(p_doc_colegiatura), ''), p_doc_fecha,
    v_editor, v_tarde,
    case when v_t.requiere_aprobacion then null else v_editor end,
    case when v_t.requiere_aprobacion then null else now() end
  )
  returning id into v_id;

  return v_id;
exception
  when exclusion_violation then
    raise exception 'Esa persona ya tiene otra ausencia registrada que se cruza con esas fechas.';
end;
$fn$;
grant execute on function fn_registrar_ausencia(uuid, text, date, date, text, text, text, date) to authenticated;
revoke execute on function fn_registrar_ausencia(uuid, text, date, date, text, text, text, date) from public, anon;

-- ── Anular ──────────────────────────────────────────────────────────────────
create or replace function fn_anular_ausencia(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_a ausencias%rowtype; v_editor uuid;
begin
  select * into v_a from ausencias where id = p_id;
  if not found then raise exception 'Esa ausencia ya no existe.'; end if;
  v_editor := fn_verificar_corrector(v_a.persona_id);

  if v_a.anulada_at is not null then raise exception 'Esa ausencia ya estaba anulada.'; end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo de la anulación es obligatorio (mínimo 4 caracteres).';
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and daterange(fecha_ini, fecha_fin, '[]') && daterange(v_a.fecha_inicio, v_a.fecha_fin, '[]')
    for share
  ) then
    raise exception 'Esas fechas caen en un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  update ausencias
     set anulada_at = now(), anulada_por = v_editor, anulada_motivo = trim(p_motivo)
   where id = p_id;
end;
$fn$;
grant execute on function fn_anular_ausencia(uuid, text) to authenticated;
revoke execute on function fn_anular_ausencia(uuid, text) from public, anon;

-- ── Aprobar (solo los tipos que pagan) ──────────────────────────────────────
create or replace function fn_aprobar_ausencia(p_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_a ausencias%rowtype;
begin
  -- La aprobación es de DO, no de la sede: es lo único que convierte días en
  -- plata, y por eso no la puede dar quien la registró desde la tienda.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede aprobar una ausencia remunerada.';
  end if;

  select * into v_a from ausencias where id = p_id;
  if not found then raise exception 'Esa ausencia ya no existe.'; end if;
  if v_a.anulada_at is not null then raise exception 'Esa ausencia está anulada.'; end if;
  if v_a.aprobada_at is not null then raise exception 'Esa ausencia ya estaba aprobada.'; end if;

  update ausencias set aprobada_por = fn_persona_actual_id(), aprobada_at = now() where id = p_id;
end;
$fn$;
grant execute on function fn_aprobar_ausencia(uuid) to authenticated;
revoke execute on function fn_aprobar_ausencia(uuid) from public, anon;

-- ── Leer ────────────────────────────────────────────────────────────────────
create or replace function fn_ausencias(p_desde date, p_hasta date, p_persona_id uuid default null)
returns table (
  id uuid, persona_id uuid, nombre text, sede text,
  tipo text, tipo_nombre text, paga boolean, requiere_aprobacion boolean,
  fecha_inicio date, fecha_fin date, dias int, motivo text,
  doc_profesional text, doc_colegiatura text, doc_fecha date,
  aprobada boolean, registrada_tarde boolean,
  registrada_por_nombre text, registrada_at timestamptz,
  anulada boolean, anulada_motivo text
)
language sql stable security definer set search_path = public as $fn$
  select a.id, a.persona_id, pe.nombres || ' ' || pe.apellidos, s.codigo,
         a.tipo, t.nombre, t.paga, t.requiere_aprobacion,
         a.fecha_inicio, a.fecha_fin, (a.fecha_fin - a.fecha_inicio + 1)::int, a.motivo,
         a.doc_profesional, a.doc_colegiatura, a.doc_fecha,
         (a.aprobada_at is not null), a.registrada_tarde,
         reg.nombres || ' ' || reg.apellidos, a.registrada_at,
         (a.anulada_at is not null), a.anulada_motivo
  from ausencias a
  join tipos_ausencia t on t.codigo = a.tipo
  join personas pe on pe.id = a.persona_id
  join sedes s on s.id = pe.sede_base_id
  left join personas reg on reg.id = a.registrada_por
  where daterange(a.fecha_inicio, a.fecha_fin, '[]') && daterange(p_desde, p_hasta, '[]')
    and (p_persona_id is null or a.persona_id = p_persona_id)
    and (fn_es_admin_o_lider()
         or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona())
         or a.persona_id = fn_persona_actual_id())
  order by a.fecha_inicio desc, pe.nombres;
$fn$;
grant execute on function fn_ausencias(date, date, uuid) to authenticated;
revoke execute on function fn_ausencias(date, date, uuid) from public, anon;

-- ── El aviso de reincidencia ────────────────────────────────────────────────
-- No bloquea ni acusa: cuenta y lo dice. La decisión de conversar es de una
-- persona, siempre — igual que con las tardanzas y las faltas.
create or replace function fn_ausencias_alerta(p_persona_id uuid default null)
returns table (persona_id uuid, nombre text, tipo text, tipo_nombre text,
               veces int, ventana_dias int, umbral int)
language sql stable security definer set search_path = public as $fn$
  select a.persona_id, pe.nombres || ' ' || pe.apellidos, t.codigo, t.nombre,
         count(*)::int, t.ventana_alerta_dias, t.alerta_desde
  from ausencias a
  join tipos_ausencia t on t.codigo = a.tipo
  join personas pe on pe.id = a.persona_id
  where t.alerta_desde is not null
    and a.anulada_at is null
    and a.fecha_inicio >= fn_hoy_lima() - t.ventana_alerta_dias
    and (p_persona_id is null or a.persona_id = p_persona_id)
    and (fn_es_admin_o_lider()
         or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  group by a.persona_id, pe.nombres, pe.apellidos, t.codigo, t.nombre, t.ventana_alerta_dias, t.alerta_desde
  having count(*) >= t.alerta_desde;
$fn$;
grant execute on function fn_ausencias_alerta(uuid) to authenticated;
revoke execute on function fn_ausencias_alerta(uuid) from public, anon;

create or replace function fn_tipos_ausencia()
returns setof tipos_ausencia
language sql stable security definer set search_path = public as $fn$
  select * from tipos_ausencia where activo order by orden, nombre;
$fn$;
grant execute on function fn_tipos_ausencia() to authenticated;
revoke execute on function fn_tipos_ausencia() from public, anon;

-- ── Las puertas viejas siguen abiertas, pero escriben en el sitio nuevo ─────
create or replace function fn_set_vacaciones(
  p_persona_id uuid, p_fecha_inicio date, p_fecha_fin date, p_observacion text default null
)
returns uuid language plpgsql security definer set search_path = public as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar vacaciones.';
  end if;
  return fn_registrar_ausencia(p_persona_id, 'vacaciones', p_fecha_inicio, p_fecha_fin, p_observacion);
end;
$fn$;
grant execute on function fn_set_vacaciones(uuid, date, date, text) to authenticated;
revoke execute on function fn_set_vacaciones(uuid, date, date, text) from public, anon;

create or replace function fn_quitar_vacaciones(p_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar vacaciones.';
  end if;
  if not exists (select 1 from ausencias where id = p_id and tipo = 'vacaciones' and anulada_at is null) then
    raise exception 'Ese periodo de vacaciones ya no existe.';
  end if;
  perform fn_anular_ausencia(p_id, 'Quitado desde la pantalla de Vacaciones');
end;
$fn$;
grant execute on function fn_quitar_vacaciones(uuid) to authenticated;
revoke execute on function fn_quitar_vacaciones(uuid) from public, anon;

create or replace function fn_justificar_falta(
  p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text default null
)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_tipo text;
begin
  -- Los motivos viejos siguen aceptándose para no romper nada que ya llame aquí.
  v_tipo := case p_motivo when 'permiso_concedido' then 'permiso_personal' else p_motivo end;
  perform fn_registrar_ausencia(p_persona_id, v_tipo, p_fecha, p_fecha, p_observacion);
end;
$fn$;
grant execute on function fn_justificar_falta(uuid, date, text, text) to authenticated;
revoke execute on function fn_justificar_falta(uuid, date, text, text) from public, anon;

create or replace function fn_quitar_justificacion(p_persona_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_id uuid;
begin
  perform fn_verificar_corrector(p_persona_id);
  select id into v_id from ausencias
   where persona_id = p_persona_id and tipo <> 'vacaciones' and anulada_at is null
     and p_fecha between fecha_inicio and fecha_fin
   limit 1;
  if v_id is null then return; end if;
  perform fn_anular_ausencia(v_id, 'Quitado desde la pantalla de asistencia');
end;
$fn$;
grant execute on function fn_quitar_justificacion(uuid, date) to authenticated;
revoke execute on function fn_quitar_justificacion(uuid, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (101, 'ausencias_un_solo_lugar')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
