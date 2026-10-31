-- ============================================================================
-- 0578 · EL SUELDO SE CAMBIA POR GRUPO, Y EL COMUNICADO LLEGA SOLO A QUIEN TOCA
-- ============================================================================
--
-- QUÉ PROMETE (Felipe, 2026-10-31)
--   1. SUELDO POR DEFECTO de los practicantes, como parámetros de clase plata
--      (fecha de vigencia, solo la dirección): `sueldo_defecto_preprofesional` y
--      `sueldo_defecto_egresado`, los dos en S/ 1 230. Honorarios no tiene valor
--      por defecto (decisión de Felipe). Planilla se define después.
--   2. CAMBIO DE SUELDO POR GRUPO: `fn_sueldo_grupo_vista_previa(grupo)` lista a
--      todo el grupo (preprofesionales, egresados u honorarios) con su sueldo de
--      hoy y si tiene el sueldo por defecto; `fn_sueldo_grupo_cambiar(grupo,
--      personas, monto, desde, motivo)` cambia a las personas marcadas, una por
--      una, por la puerta de siempre (`fn_set_salario`, con su candado de
--      periodos pagados). Solo la dirección. Un practicante no puede quedar por
--      debajo de la RMV vigente en esa fecha (Ley 28518, art. 45).
--   3. COMUNICADO EN BORRADOR, SOLO PARA QUIEN TOCA: `anuncios` gana `estado`
--      (borrador / publicado) y `audiencia` (las personas a las que va). Un
--      cambio por grupo deja un borrador para esas personas, con qué cambia,
--      desde cuándo y que una disconformidad se registra en Reportes. Nadie del
--      equipo ve un borrador; DO lo revisa y lo publica desde Anuncios
--      (`fn_anuncio_publicar_borrador`). `fn_comunicado_borrador` deja uno para
--      cualquier alcance (lo usa la pantalla al cambiar la base o el tope).
--
-- QUÉ ASUME
--   · md5 de PRODUCCIÓN pedido antes de escribir (2026-10-31), igual al local:
--       fn_anuncios_vigentes 568eae403d93dfc84a69306582be9593 (752) — se reescribe
--       fn_publicar_anuncio  fbdb730b273d0918557442af4dc7709c (781) — no se toca
--       fn_set_salario       267bc313d451a846948cdd4cad36caa9 (2979) — no se toca, se llama
--   · La 0574 pegada (parámetros con fechas).
--
-- POR QUÉ ASÍ
--   · Un anuncio de antes queda `publicado` y sin audiencia: se ve igual que hoy.
--   · La audiencia son PERSONAS, no un filtro: el comunicado va a quien se le
--     cambió algo, aunque después cambie de vínculo.
--   · El cambio por grupo no inventa otra forma de escribir sueldos: llama a
--     fn_set_salario por persona, que ya valida, audita y frena lo pagado.
--
-- CÓMO SE REVIERTE
--   Pegar de nuevo fn_anuncios_vigentes de la 0351 (con drop function antes) y la
--   política anuncios_select_equipo de la 0351; drop de las funciones nuevas. Las
--   columnas nuevas de anuncios pueden quedarse (no molestan).
-- ============================================================================

-- ── 0 · Guardia ────────────────────────────────────────────────────────────
do $guardia$
declare v_src text;
begin
  if to_regprocedure('public.fn_parametro_valor_en(text,date)') is null then
    raise exception 'PARA. Falta la 0574 (parámetros con fechas).';
  end if;
  select prosrc into v_src from pg_proc
   where proname = 'fn_anuncios_vigentes' and pronamespace = 'public'::regnamespace;
  if v_src is null then
    raise exception 'PARA. No existe fn_anuncios_vigentes.';
  end if;
  if position('audiencia' in v_src) = 0 and md5(v_src) <> '568eae403d93dfc84a69306582be9593' then
    raise exception 'PARA. fn_anuncios_vigentes no es la de la 0351 (md5 %). Pide el md5 a producción.', md5(v_src);
  end if;
end
$guardia$;

-- ── 1 · Sueldo por defecto de los practicantes ─────────────────────────────
insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen, almacen_clave, alcance, editable, base, orden, roles_cambia)
values
  ('sueldo_defecto_preprofesional', 'Subvención por defecto del practicante preprofesional',
   'La subvención (jornada completa) que se propone al cambiar el sueldo del grupo y que marca quién está «en el valor por defecto».',
   'soles', 'plata', 'decimal', 1, 20000, 1230, 'vigencias', 'sueldo_defecto_preprofesional',
   'practicante_preprofesional', true, 'Ley 28518 art. 45 (no menor a la RMV)', 300, array['admin']),
  ('sueldo_defecto_egresado', 'Subvención por defecto del practicante egresado',
   'La subvención (jornada completa) que se propone al cambiar el sueldo del grupo y que marca quién está «en el valor por defecto».',
   'soles', 'plata', 'decimal', 1, 20000, 1230, 'vigencias', 'sueldo_defecto_egresado',
   'practicante_profesional', true, 'Ley 28518 art. 45 (no menor a la RMV)', 310, array['admin'])
on conflict (parametro) do update
   set nombre = excluded.nombre, descripcion = excluded.descripcion, base = excluded.base, orden = excluded.orden;

-- ── 2 · Anuncios: borrador y audiencia ─────────────────────────────────────
alter table anuncios add column if not exists estado text not null default 'publicado';
alter table anuncios add column if not exists audiencia jsonb;
do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'anuncios_estado_valido') then
    alter table anuncios add constraint anuncios_estado_valido check (estado in ('borrador', 'publicado'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'anuncios_audiencia_forma') then
    alter table anuncios add constraint anuncios_audiencia_forma
      check (audiencia is null or (jsonb_typeof(audiencia) = 'object' and jsonb_typeof(audiencia -> 'personas') = 'array'));
  end if;
end
$c$;

comment on column anuncios.audiencia is
  'null = para todos (o su sede). {"personas": [uuid…], "descripcion": "…"} = solo para esas personas. 0578.';

-- ¿Este anuncio le llega a esta persona? Una sola regla, para la función y la política.
create or replace function fn_anuncio_le_llega(p_audiencia jsonb, p_persona uuid)
returns boolean
language sql
immutable
as $fn$
  select p_audiencia is null
      or (p_persona is not null and (p_audiencia -> 'personas') ? p_persona::text);
$fn$;

drop policy if exists anuncios_select_equipo on anuncios;
create policy anuncios_select_equipo on anuncios
  for select to authenticated
  using (anulado_at is null
         and estado = 'publicado'
         and fn_anuncio_le_llega(audiencia, fn_persona_actual_id())
         and (sede_id is null
              or sede_id = (select p.sede_base_id from personas p where p.id = fn_persona_actual_id())));

drop function if exists fn_anuncios_vigentes(boolean);
create function fn_anuncios_vigentes(p_incluir_anulados boolean default false)
returns table (id uuid, titulo text, cuerpo text, sede_id uuid, sede_codigo text,
               publicado_por_nombre text, publicado_at timestamptz, anulado_at timestamptz,
               mi_leido_at timestamptz, total_lectores integer,
               estado text, audiencia_descripcion text, audiencia_total integer)
language sql
stable
security definer
set search_path = public
as $fn$
  select a.id, a.titulo, a.cuerpo,
         a.sede_id, sd.codigo,
         pu.nombres || ' ' || pu.apellidos, a.publicado_at,
         a.anulado_at,
         al.leido_at,
         (select count(*)::int from anuncios_leidos where anuncio_id = a.id),
         a.estado,
         a.audiencia ->> 'descripcion',
         case when a.audiencia is null then null else jsonb_array_length(a.audiencia -> 'personas') end
  from anuncios a
  join personas pu on pu.id = a.publicado_por
  left join sedes sd on sd.id = a.sede_id
  left join anuncios_leidos al on al.anuncio_id = a.id and al.persona_id = fn_persona_actual_id()
  where (
    a.anulado_at is null
    or (p_incluir_anulados and fn_es_admin_o_lider() is true)
  )
  and (
    fn_es_admin_o_lider() is true
    or (a.estado = 'publicado'                                             -- CAMBIO 0578: un borrador no se ve
        and fn_anuncio_le_llega(a.audiencia, fn_persona_actual_id())       -- CAMBIO 0578: solo a quien va
        and (a.sede_id is null
             or a.sede_id = (select p.sede_base_id from personas p where p.id = fn_persona_actual_id())))
  )
  order by (a.estado = 'borrador') desc, a.publicado_at desc;
$fn$;

revoke all on function fn_anuncios_vigentes(boolean) from public, anon;
grant execute on function fn_anuncios_vigentes(boolean) to authenticated;

-- Deja un comunicado en BORRADOR para unas personas. Solo admin o DO.
create or replace function fn_comunicado_borrador(p_personas uuid[], p_descripcion text, p_titulo text, p_cuerpo text)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_yo uuid := fn_persona_actual_id();
  v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede preparar un comunicado.';
  end if;
  if v_yo is null then
    raise exception 'No puedo identificar quién prepara el comunicado.';
  end if;
  if coalesce(cardinality(p_personas), 0) = 0 then
    raise exception 'El comunicado no tiene a nadie a quien llegar.';
  end if;
  if btrim(coalesce(p_titulo, '')) = '' or btrim(coalesce(p_cuerpo, '')) = '' then
    raise exception 'El comunicado necesita título y cuerpo.';
  end if;
  insert into anuncios (titulo, cuerpo, sede_id, publicado_por, estado, audiencia)
  values (left(btrim(p_titulo), 200), btrim(p_cuerpo), null, v_yo, 'borrador',
          jsonb_build_object('personas', to_jsonb(p_personas), 'descripcion', coalesce(btrim(p_descripcion), '')))
  returning id into v_id;
  return v_id;
end;
$fn$;

revoke all on function fn_comunicado_borrador(uuid[], text, text, text) from public, anon;
grant execute on function fn_comunicado_borrador(uuid[], text, text, text) to authenticated;

-- Revisar y publicar el borrador (puede corregir el texto antes).
create or replace function fn_anuncio_publicar_borrador(p_id uuid, p_titulo text default null, p_cuerpo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_yo uuid := fn_persona_actual_id();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede publicar un comunicado.';
  end if;
  update anuncios
     set titulo = coalesce(nullif(left(btrim(p_titulo), 200), ''), titulo),
         cuerpo = coalesce(nullif(btrim(p_cuerpo), ''), cuerpo),
         estado = 'publicado',
         publicado_por = coalesce(v_yo, publicado_por),
         publicado_at = now()
   where id = p_id and estado = 'borrador' and anulado_at is null;
  if not found then
    raise exception 'Ese comunicado no está en borrador (o ya se publicó o anuló).';
  end if;
end;
$fn$;

revoke all on function fn_anuncio_publicar_borrador(uuid, text, text) from public, anon;
grant execute on function fn_anuncio_publicar_borrador(uuid, text, text) to authenticated;

-- Las personas activas de un alcance (lo usa la pantalla para el comunicado de un parámetro).
create or replace function fn_personas_de_alcance(p_alcance text)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(array_agg(p.id order by p.apellidos, p.nombres), array[]::uuid[])
    from personas p
   where p.estado = 'activo' and coalesce(p.cuenta_de_servicio, false) = false
     and fn_es_admin_o_lider() is true
     and case p_alcance
           when 'practicante_preprofesional' then p.tipo_vinculo = 'practicante' and p.practicante_modalidad = 'preprofesional'
           when 'practicante_profesional'    then p.tipo_vinculo = 'practicante' and p.practicante_modalidad = 'profesional'
           when 'rxh'                        then p.tipo_vinculo = 'rxh'
           when 'planilla'                   then p.tipo_vinculo = 'planilla'
           else false end;
$fn$;

revoke all on function fn_personas_de_alcance(text) from public, anon;
grant execute on function fn_personas_de_alcance(text) to authenticated;

-- ── 3 · El cambio de sueldo por grupo ──────────────────────────────────────
-- grupo: 'practicante_preprofesional' · 'practicante_profesional' · 'rxh'
create or replace function fn_sueldo_grupo_vista_previa(p_grupo text)
returns table (persona_id uuid, nombre text, rango text, sueldo_actual numeric, es_por_defecto boolean)
language plpgsql
stable
security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  v_defecto numeric := case p_grupo
    when 'practicante_preprofesional' then fn_parametro_valor_en('sueldo_defecto_preprofesional', fn_hoy_lima())
    when 'practicante_profesional'    then fn_parametro_valor_en('sueldo_defecto_egresado', fn_hoy_lima())
  end;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo la dirección o Desarrollo Organizacional puede ver los sueldos del grupo.';
  end if;
  if p_grupo not in ('practicante_preprofesional', 'practicante_profesional', 'rxh') then
    raise exception 'Grupo desconocido: %.', p_grupo;
  end if;
  return query
  select p.id,
         btrim(p.apellidos || ', ' || p.nombres),
         a.rango,
         a.salario_mensual_soles,
         (v_defecto is not null and a.salario_mensual_soles = v_defecto)
    from personas p
    left join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
   where p.estado = 'activo' and coalesce(p.cuenta_de_servicio, false) = false
     and p.id = any(fn_personas_de_alcance(p_grupo))
   order by 2;
end;
$fn$;

revoke all on function fn_sueldo_grupo_vista_previa(text) from public, anon;
grant execute on function fn_sueldo_grupo_vista_previa(text) to authenticated;

create or replace function fn_sueldo_grupo_cambiar(p_grupo text, p_personas uuid[], p_monto numeric, p_desde date, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_motivo   text := btrim(coalesce(p_motivo, ''));
  v_grupo    uuid[];
  v_rmv      numeric;
  v_p        uuid;
  v_rango    text;
  v_n        int := 0;
  v_desc     text;
  v_anuncio  uuid;
  v_pagado   date;
begin
  if fn_rol_actual()::text is distinct from 'admin' then
    raise exception 'Solo la dirección puede cambiar el sueldo de un grupo.';
  end if;
  if p_grupo not in ('practicante_preprofesional', 'practicante_profesional', 'rxh') then
    raise exception 'Grupo desconocido: %.', p_grupo;
  end if;
  if coalesce(cardinality(p_personas), 0) = 0 then
    raise exception 'No marcaste a nadie.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto tiene que ser mayor a cero.';
  end if;
  if p_desde is null then
    raise exception 'Falta desde cuándo rige.';
  end if;
  if length(v_motivo) < 3 then
    raise exception 'Escribe el motivo del cambio: es lo que explica el monto dentro de un año.';
  end if;

  v_pagado := fn_parametro_periodo_pagado_desde(p_grupo, p_desde);
  if v_pagado is not null then
    raise exception 'El periodo que termina el % ya está pagado para este grupo: un sueldo desde el % reescribiría lo ya pagado.', v_pagado, p_desde;
  end if;

  if p_grupo like 'practicante%' then
    select pl.valor into v_rmv from parametros_laborales pl
     where pl.clave = 'rmv' and pl.sede_codigo is null and pl.vigente_desde <= p_desde
       and (pl.vigente_hasta is null or pl.vigente_hasta >= p_desde)
     order by pl.vigente_desde desc limit 1;
    if v_rmv is not null and p_monto < v_rmv then
      raise exception 'La subvención de un practicante no puede ser menor a la RMV vigente (S/ %) — Ley 28518, art. 45.', round(v_rmv, 2);
    end if;
  end if;

  v_grupo := fn_personas_de_alcance(p_grupo);
  foreach v_p in array p_personas loop
    if not (v_p = any(v_grupo)) then
      raise exception 'Una de las personas marcadas no pertenece a este grupo.';
    end if;
    select a.rango into v_rango from asignaciones_salario a
     where a.persona_id = v_p and a.vigente_hasta is null;
    perform fn_set_salario(v_p, coalesce(v_rango, 'colibri'), p_monto, p_desde,
                           'Cambio por grupo (' || p_grupo || '): ' || v_motivo);
    v_n := v_n + 1;
  end loop;

  v_desc := case p_grupo
    when 'practicante_preprofesional' then 'Practicantes preprofesionales'
    when 'practicante_profesional'    then 'Practicantes egresados'
    else 'Honorarios' end;
  v_anuncio := fn_comunicado_borrador(
    p_personas, v_desc || ' (' || v_n || ')',
    'Cambio en tu ' || case when p_grupo = 'rxh' then 'monto de honorarios' else 'subvención' end
      || ' desde el ' || to_char(p_desde, 'DD/MM/YYYY'),
    'Desde el ' || to_char(p_desde, 'DD/MM/YYYY') || ', tu '
      || case when p_grupo = 'rxh' then 'monto de honorarios' else 'subvención por la jornada completa' end
      || ' pasa a S/ ' || to_char(p_monto, 'FM999G990D00') || '.'
      || case when p_grupo like 'practicante%'
              then ' Se te sigue pagando en proporción a las horas que marques según tu horario.' else '' end
      || E'\n\nMotivo: ' || v_motivo
      || E'\n\nSi no estás de acuerdo o algo no cuadra, regístralo en Reportes y Desarrollo Organizacional atenderá tu caso.');

  return jsonb_build_object('cambiados', v_n, 'anuncio_id', v_anuncio);
end;
$fn$;

revoke all on function fn_sueldo_grupo_cambiar(text, uuid[], numeric, date, text) from public, anon;
grant execute on function fn_sueldo_grupo_cambiar(text, uuid[], numeric, date, text) to authenticated;

-- ── 4 · El comunicado de un cambio de parámetro (base, tope, sueldo por defecto) ─
-- La pantalla lo pide después de un cambio con fecha: arma el borrador para las
-- personas del alcance del parámetro. Devuelve null si el alcance no tiene a nadie.
create or replace function fn_parametro_comunicado(p_parametro text, p_antes numeric, p_nuevo numeric, p_desde date)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  c parametros_catalogo%rowtype;
  v_personas uuid[];
  v_desc text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede preparar un comunicado.';
  end if;
  select * into c from parametros_catalogo where parametro = p_parametro;
  if not found or c.alcance is null then
    raise exception 'Ese parámetro no tiene a quién avisar.';
  end if;
  v_personas := fn_personas_de_alcance(c.alcance);
  if coalesce(cardinality(v_personas), 0) = 0 then
    return null;
  end if;
  v_desc := case c.alcance
    when 'practicante_preprofesional' then 'Practicantes preprofesionales'
    when 'practicante_profesional'    then 'Practicantes egresados'
    when 'rxh'                        then 'Honorarios'
    else 'Planilla' end;
  return fn_comunicado_borrador(
    v_personas, v_desc || ' (' || cardinality(v_personas) || ')',
    'Cambio en «' || c.nombre || '» desde el ' || to_char(p_desde, 'DD/MM/YYYY'),
    'Desde el ' || to_char(p_desde, 'DD/MM/YYYY') || ', «' || c.nombre || '» pasa de '
      || trim_scale(p_antes)::text || ' a ' || trim_scale(p_nuevo)::text || ' ' || c.unidad || '. '
      || c.descripcion
      || E'\n\nSi no estás de acuerdo o algo no cuadra, regístralo en Reportes y Desarrollo Organizacional atenderá tu caso.');
end;
$fn$;

revoke all on function fn_parametro_comunicado(text, numeric, numeric, date) from public, anon;
grant execute on function fn_parametro_comunicado(text, numeric, numeric, date) to authenticated;

-- ── Registro ───────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (578, 'el_sueldo_se_cambia_por_grupo_y_avisa_a_quien_toca')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ───────────────────────────────────────────────────────────
-- Debe dar: 2 · true · 0 · true · true · «578 · el_sueldo_…»
select
  (select count(*) from parametros_catalogo where parametro like 'sueldo_defecto_%')  as sueldos_por_defecto,
  (select 'estado' = any(proargnames) from pg_proc where proname = 'fn_anuncios_vigentes'
     and pronamespace = 'public'::regnamespace)                                        as anuncios_dicen_su_estado,
  (select count(*) from anuncios where estado <> 'publicado')                           as borradores,
  (to_regprocedure('public.fn_sueldo_grupo_cambiar(text,uuid[],numeric,date,text)') is not null) as existe_el_cambio_por_grupo,
  (to_regprocedure('public.fn_anuncio_publicar_borrador(uuid,text,text)') is not null)  as existe_publicar_borrador,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 578)      as registro;
