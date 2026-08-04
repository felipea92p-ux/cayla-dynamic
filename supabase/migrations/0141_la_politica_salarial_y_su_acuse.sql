-- ============================================================================
-- 0141 — La política salarial publicada, y la prueba de que se informó.
--
-- QUÉ PROMETE
--
-- Cerrar el numeral 25.23 del RLGIT, que es la otra infracción MUY GRAVE de la
-- Ley 30709: no basta TENER el cuadro de categorías y la política salarial —hay
-- que INFORMARLOS al trabajador, y hay que poder probarlo—.
--
-- La norma manda informar en tres momentos: al ingreso, al cambiar de categoría,
-- y AL CAMBIAR EL ESQUEMA REMUNERATIVO. CAYLA está cambiando el esquema ahora
-- mismo, así que este es exactamente el momento en que la obligación se activa.
--
-- QUÉ GUARDA, Y POR QUÉ ASÍ
--
--   politica_salarial          una fila por VERSIÓN publicada, con el documento
--                              entero congelado como texto. No una referencia al
--                              cuadro: el texto literal.
--
--   politica_salarial_acuses   quién dejó constancia de haber recibido QUÉ
--                              VERSIÓN, y cuándo.
--
-- POR QUÉ SE CONGELA EL TEXTO Y NO SE REGENERA
--
--   Es la misma lección de la 0096 (la foto del pago): si el documento se
--   regenerara desde las tablas cada vez que alguien lo abre, entonces el día
--   que cambien las bandas TODOS los acuses viejos pasarían a apuntar a un texto
--   que nadie firmó. La prueba de haber informado se evaporaría en silencio, sin
--   que ningún error saltara.
--
--   Congelando el texto, un acuse de agosto sigue apuntando al documento de
--   agosto. Y si el cuadro cambia, el sistema lo detecta —comparando la huella
--   del cuadro actual contra la guardada— y pide publicar una versión nueva, que
--   a su vez pide acuses nuevos.
--
-- POR QUÉ EL ACUSE POR SESIÓN VALE
--
--   Aquí no se firma un contrato: se deja constancia de haber sido informado.
--   La Ley 27269 reconoce la firma electrónica, y desde el D.S. 009-2011-TR las
--   boletas de pago se entregan sin firma física — el precedente de que un
--   documento laboral se comunica electrónicamente ya está asentado.
--   Lo que se guarda es más de lo que prueba una firma a mano: quién, cuándo, y
--   sobre todo QUÉ VERSIÓN. Un papel firmado no dice qué versión firmó.
--
-- QUÉ ASUME
--
--   · Que el documento lo arma la pantalla y lo manda ya renderizado. La base no
--     sabe maquetar; su trabajo es guardar exactamente lo que se comunicó.
--   · Que publicar es un acto deliberado de la Gerencia, no un efecto colateral
--     de editar una categoría.
--
-- NO MUEVE NINGÚN PAGO.
--
-- CÓMO SE REVIERTE:
--   drop table politica_salarial_acuses, politica_salarial;
-- ============================================================================

-- ── 1 · Las versiones publicadas ────────────────────────────────────────────

create table if not exists politica_salarial (
  version        int  primary key,
  documento      text not null check (btrim(documento) <> ''),
  huella_cuadro  text not null,
  notas          text,
  publicada_por  uuid references personas(id),
  publicada_at   timestamptz not null default now()
);

comment on table politica_salarial is
  'Cada version publicada del cuadro de categorias y politica salarial, con el documento congelado. Congelado y no regenerado: si se regenerara, cambiar una banda dejaria todos los acuses previos apuntando a un texto que nadie firmo.';
comment on column politica_salarial.documento is
  'El texto literal que se comunico. Es la prueba: tiene que poder mostrarse igual dentro de cinco anios.';
comment on column politica_salarial.huella_cuadro is
  'Huella del cuadro al momento de publicar. Sirve para detectar que el cuadro cambio y que hay que publicar una version nueva.';

-- ── 2 · Los acuses ──────────────────────────────────────────────────────────

create table if not exists politica_salarial_acuses (
  persona_id      uuid not null references personas(id),
  version         int  not null references politica_salarial(version),
  nombre_declarado text not null check (btrim(nombre_declarado) <> ''),
  acusado_at      timestamptz not null default now(),
  primary key (persona_id, version)
);

comment on table politica_salarial_acuses is
  'Constancia de que una persona fue informada de una version concreta. Es lo que cierra el numeral 25.23 del RLGIT.';
comment on column politica_salarial_acuses.nombre_declarado is
  'El nombre que la persona escribio al dejar constancia. No es un requisito legal; es lo que convierte un clic en un acto deliberado.';

create index if not exists idx_acuses_version on politica_salarial_acuses(version);

alter table politica_salarial        enable row level security;
alter table politica_salarial_acuses enable row level security;

-- Todo el mundo puede LEER la politica: informarla es justamente la obligacion.
drop policy if exists politica_lectura on politica_salarial;
create policy politica_lectura on politica_salarial
  for select to authenticated using (true);

-- Cada quien ve SU acuse; admin y lideres ven todos.
drop policy if exists acuses_lectura on politica_salarial_acuses;
create policy acuses_lectura on politica_salarial_acuses
  for select to authenticated
  using (persona_id = fn_persona_actual_id() or fn_es_admin_o_lider() is true);

-- ── 3 · Publicar ────────────────────────────────────────────────────────────

create or replace function fn_publicar_politica_salarial(
  p_documento text,
  p_notas     text default null
)
returns int
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo      uuid;
  v_version int;
  v_huella  text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede publicar la politica salarial.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien publica, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  if p_documento is null or btrim(p_documento) = '' then
    raise exception 'No se puede publicar una politica vacia.';
  end if;

  v_huella := md5(fn_cuadro_categorias()::text);

  -- Publicar dos veces el mismo texto sobre el mismo cuadro no crea version
  -- nueva: obligaria a todo el equipo a acusar de nuevo algo que no cambio.
  select version into v_version
  from politica_salarial
  where huella_cuadro = v_huella and documento = p_documento
  order by version desc limit 1;

  if v_version is not null then
    return v_version;
  end if;

  select coalesce(max(version), 0) + 1 into v_version from politica_salarial;

  insert into politica_salarial (version, documento, huella_cuadro, notas, publicada_por)
  values (v_version, p_documento, v_huella, nullif(btrim(coalesce(p_notas,'')), ''), v_yo);

  return v_version;
end;
$fn$;

grant  execute on function fn_publicar_politica_salarial(text, text) to authenticated;
revoke execute on function fn_publicar_politica_salarial(text, text) from public, anon;

-- ── 4 · Qué está publicado, y si quedó desactualizado ───────────────────────

create or replace function fn_politica_salarial_vigente()
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_yo   uuid;
  v_row  politica_salarial%rowtype;
  v_hoy  text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'Inicia sesion para ver la politica salarial.';
  end if;

  select * into v_row from politica_salarial order by version desc limit 1;

  if not found then
    return jsonb_build_object(
      'publicada',    false,
      'desactualizada', false,
      'mi_acuse',     null,
      'aviso', 'Todavia no se ha publicado ninguna version. Mientras tanto CAYLA sigue incursa en el numeral 25.23 del RLGIT.'
    );
  end if;

  v_hoy := md5(fn_cuadro_categorias()::text);

  return jsonb_build_object(
    'publicada',      true,
    'version',        v_row.version,
    'documento',      v_row.documento,
    'publicada_at',   v_row.publicada_at,
    'notas',          v_row.notas,
    -- Si el cuadro cambio despues de publicar, el documento que la gente acuso
    -- ya no describe la realidad. Hay que publicar de nuevo.
    'desactualizada', v_row.huella_cuadro <> v_hoy,
    'mi_acuse', (
      select jsonb_build_object('acusado_at', a.acusado_at, 'nombre', a.nombre_declarado)
      from politica_salarial_acuses a
      where a.persona_id = v_yo and a.version = v_row.version
    ),
    'total_personas', (
      select count(*)::int from personas
      where estado = 'activo' and en_planilla is true
    ),
    'total_acuses', (
      select count(*)::int from politica_salarial_acuses a
      join personas p on p.id = a.persona_id
      where a.version = v_row.version and p.estado = 'activo' and p.en_planilla is true
    )
  );
end;
$fn$;

grant  execute on function fn_politica_salarial_vigente() to authenticated;
revoke execute on function fn_politica_salarial_vigente() from public, anon;

-- ── 5 · Dejar constancia ────────────────────────────────────────────────────
-- Sin guard de rol a proposito: TODA persona tiene que poder acusar la suya. Un
-- acuse que solo un admin pudiera registrar no probaria nada.

create or replace function fn_acusar_politica_salarial(p_nombre text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_yo      uuid;
  v_version int;
  v_ya      timestamptz;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'Inicia sesion con tu usuario para dejar constancia.';
  end if;

  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'Escribe tu nombre para dejar constancia.';
  end if;

  select version into v_version from politica_salarial order by version desc limit 1;
  if v_version is null then
    raise exception 'Todavia no hay una politica publicada que acusar.';
  end if;

  -- El acuse no se sobrescribe: la fecha original es la prueba.
  select acusado_at into v_ya
  from politica_salarial_acuses
  where persona_id = v_yo and version = v_version;

  if v_ya is not null then
    return jsonb_build_object('version', v_version, 'acusado_at', v_ya, 'nuevo', false);
  end if;

  insert into politica_salarial_acuses (persona_id, version, nombre_declarado)
  values (v_yo, v_version, btrim(p_nombre));

  return jsonb_build_object('version', v_version, 'acusado_at', now(), 'nuevo', true);
end;
$fn$;

grant  execute on function fn_acusar_politica_salarial(text) to authenticated;
revoke execute on function fn_acusar_politica_salarial(text) from public, anon;

-- ── 6 · Quién falta ─────────────────────────────────────────────────────────
-- Lo que se le enseña a un inspector: la lista completa, con fecha al lado de
-- quien acuso y el hueco a la vista de quien no.

create or replace function fn_acuses_politica_salarial()
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_version int; v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver quien acuso la politica.';
  end if;

  select version into v_version from politica_salarial order by version desc limit 1;
  if v_version is null then
    return jsonb_build_object('version', null, 'personas', '[]'::jsonb);
  end if;

  select jsonb_build_object(
    'version', v_version,
    'personas', coalesce(jsonb_agg(jsonb_build_object(
      'persona_id', p.id,
      'nombre',     p.nombres || ' ' || p.apellidos,
      'rango',      s.rango,
      'acusado_at', a.acusado_at,
      'nombre_declarado', a.nombre_declarado
    ) order by (a.acusado_at is not null), p.apellidos, p.nombres), '[]'::jsonb)
  ) into v_out
  from personas p
  left join politica_salarial_acuses a
         on a.persona_id = p.id and a.version = v_version
  left join asignaciones_salario s
         on s.persona_id = p.id and s.vigente_hasta is null
  where p.estado = 'activo' and p.en_planilla is true;

  return v_out;
end;
$fn$;

grant  execute on function fn_acuses_politica_salarial() to authenticated;
revoke execute on function fn_acuses_politica_salarial() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (141, 'la_politica_salarial_y_su_acuse')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_pub int;
begin
  select count(*) into v_pub from politica_salarial;
  raise notice '0141 · versiones publicadas: %', v_pub;
  if v_pub = 0 then
    raise notice '0141 · ninguna todavia. Hasta publicar y recoger acuses, sigue abierta la 25.23.';
  end if;
  raise notice '0141 · publicar desde Documentacion. Cada persona acusa la suya al entrar.';
end $mig$;
