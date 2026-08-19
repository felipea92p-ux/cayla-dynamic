-- ============================================================================
-- 0272 — Los contratos generados entran al sistema
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el contrato de trabajo de cada persona se arme desde los datos que el
--   sistema YA tiene (identidad, sueldo vigente, horario, sede) en vez de
--   llenarse a mano cláusula por cláusula, y que el texto exacto que se
--   imprimió quede congelado — antes de que exista el escaneo firmado, no
--   después — para que si pasan varios días entre imprimir y firmar (20
--   renovaciones no se firman en una tarde) quede constancia de qué se le dio
--   a leer a cada persona.
--
-- QUÉ ASUME
--   · `fn_es_admin_o_lider()` (0078) y `fn_persona_actual_id()`.
--   · `fn_set_fin_contrato` (0144): se llama SOLO cuando el contrato ya quedó
--     firmado, nunca desde el borrador — un borrador puede descartarse, y la
--     fecha de vencimiento de una persona no debe moverse por un documento
--     que nadie firmó todavía.
--   · `personas.estado`, `sedes`, `correcciones_auditoria`.
--
-- POR QUÉ TABLA PROPIA Y NO `documentos_firmados`
--   Esa tabla (0157) tiene su modelo armado alrededor de `alcance` y tres
--   constraints mutuamente excluyentes pensadas para tres papeles cortos
--   (ruta, política, bono). Un contrato necesita ocho columnas propias
--   —cargo, sede, remuneración, fechas, horas semanales, el texto completo—
--   que ahí serían columnas nullable de un solo tipo entre cuatro, rompiendo
--   la legibilidad que esas constraints hoy tienen. Mismo criterio con el que
--   la 0157 le dio bucket y tabla propios en vez de reusar `expediente_adjuntos`.
--
-- POR QUÉ EL BORRADOR EXISTE ANTES DE LA FIRMA (a diferencia de `documentos_firmados`)
--   En `documentos_firmados` la fila se crea cuando ya se conoce la fecha de
--   firma — es un papel corto que se sube el mismo día. Un contrato de 13
--   páginas se imprime, se revisa y se firma días después, y lo que hay que
--   poder probar es qué texto EXACTO se imprimió, exista o no todavía el
--   escaneo. Por eso `fn_contrato_registrar` sin `p_id` congela el
--   `documento_html` de inmediato (borrador, sin firma), y una segunda llamada
--   con `p_id` adjunta `storage_path` + `fecha_firma` cuando el escaneo llega.
--
-- POR QUÉ NO GUARDA UN HASH DE LOS DATOS DE ORIGEN
--   `documento_html` ya es el texto íntegro, y es la fuente reconstructible:
--   no hay un flujo de "actualizar" un contrato ya generado (a diferencia de
--   `politica_salarial`, que SÍ recalcula un cuadro vivo y necesita `huella_
--   cuadro` para detectar cuándo quedó desactualizado). Un contrato se genera
--   una vez y no se reescribe; agregar un hash sería una columna que nadie
--   consulta.
--
-- QUÉ NO HACE ESTA MIGRACIÓN
--   No cambia ningún sueldo, no genera ningún contrato, no toca
--   `personas.fecha_fin_contrato` de nadie. Solo dejar la pieza — la
--   pantalla que la usa (`/admin/contratos`) es aparte.
--
-- CÓMO SE REVIERTE
--   drop table contratos_generados;  (los archivos quedan en el bucket y hay
--   que vaciarlo aparte)
--   drop function fn_contrato_registrar(uuid,text,text,uuid,numeric,date,date,
--        numeric,text,uuid,text,date), fn_contrato_anular(uuid,text),
--        fn_contratos_listar(uuid), fn_contrato_puede_ver(text);
--   delete from storage.buckets where id = 'contratos';
-- ============================================================================


-- ── A · El bucket ───────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'contratos', 'contratos', false,
  50 * 1024 * 1024,
  array['image/jpeg','image/png','image/heic','image/webp','application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- ── B · La tabla ─────────────────────────────────────────────────────────────
create table if not exists contratos_generados (
  id                    uuid primary key default gen_random_uuid(),
  persona_id            uuid not null references personas(id) on delete restrict,

  tipo                  text not null check (tipo in ('nuevo', 'renovacion', 'adendum')),

  -- Lo que dice el contrato al momento de generarse. No se lee en vivo desde
  -- `personas`/`asignaciones_salario` después de firmado: lo firmado es lo
  -- firmado, aunque el sueldo o el cargo de esa persona cambien más tarde.
  cargo                 text not null check (btrim(cargo) <> ''),
  sede_id               uuid not null references sedes(id),
  remuneracion_mensual  numeric(10,2) not null check (remuneracion_mensual >= 0),
  fecha_inicio          date not null,
  fecha_fin             date not null check (fecha_fin > fecha_inicio),

  -- Null = no se pudo determinar desde el horario de esa persona. NUNCA cero:
  -- un cero se leería como «jornada de cero horas», que es peor que dejar la
  -- cláusula pendiente de completar a mano, que es lo que pasa hoy sin esto.
  horas_semanales       numeric(5,2) check (horas_semanales is null or horas_semanales > 0),

  -- El texto congelado completo — la fuente reconstructible. Ver cabecera:
  -- por qué no se guarda además un hash de los datos que lo generaron.
  documento_html        text not null check (btrim(documento_html) <> ''),

  generado_por          uuid not null references personas(id),
  generado_at           timestamptz not null default now(),

  -- Los tres siguientes van juntos o ninguno: mientras no exista el escaneo
  -- firmado, el contrato es un borrador. Ver cabecera.
  storage_path          text,
  fecha_firma           date,
  registrado_por        uuid references personas(id),

  -- Nada se borra.
  anulado_at            timestamptz,
  anulado_por           uuid references personas(id),
  anulado_motivo        text,

  constraint contrato_firma_coherente check (
    (storage_path is null and fecha_firma is null and registrado_por is null)
    or (storage_path is not null and fecha_firma is not null and registrado_por is not null)
  ),
  constraint contrato_anulado_con_motivo check (
    (anulado_at is null and anulado_por is null and anulado_motivo is null)
    or (anulado_at is not null and anulado_por is not null
        and anulado_motivo is not null and length(trim(anulado_motivo)) >= 3)
  )
);

comment on table contratos_generados is
  'Cada contrato de trabajo generado por el sistema, con su texto completo '
  'congelado en el momento de generarse — antes de que exista el escaneo '
  'firmado, no después. Se versiona por fila, nunca se reemplaza: si un '
  'contrato se generó por error, se anula (con motivo) y se genera uno nuevo.';

create index if not exists idx_contratos_persona
  on contratos_generados (persona_id, generado_at desc)
  where anulado_at is null;

alter table contratos_generados enable row level security;

-- Leer: DO todo, cada quien lo suyo. Escribir NO se concede: pasa por
-- función, igual que documentos_firmados, expedientes y salarios.
drop policy if exists contratos_lectura on contratos_generados;
create policy contratos_lectura on contratos_generados
  for select to authenticated
  using (fn_es_admin_o_lider() is true or persona_id = fn_persona_actual_id());


-- ── C · Los archivos del bucket ─────────────────────────────────────────────
-- El path es "contratos/<id de la fila>.<ext>", igual que en la 0157.
create or replace function fn_contrato_puede_ver(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id      text;
  v_persona uuid;
begin
  if split_part(p_path, '/', 1) <> 'contratos' then return false; end if;
  v_id := split_part(split_part(p_path, '/', 2), '.', 1);
  if v_id !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  if fn_es_admin_o_lider() is true then return true; end if;

  select c.persona_id into v_persona from contratos_generados c where c.id = v_id::uuid;
  return v_persona = fn_persona_actual_id();
end;
$$;

grant execute on function fn_contrato_puede_ver(text) to authenticated;

drop policy if exists contratos_insert on storage.objects;
create policy contratos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'contratos'
    and split_part(name, '/', 1) = 'contratos'
    and fn_es_admin_o_lider() is true
  );

drop policy if exists contratos_select on storage.objects;
create policy contratos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'contratos' and fn_contrato_puede_ver(name));

drop policy if exists contratos_delete on storage.objects;
create policy contratos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'contratos'
    and split_part(name, '/', 1) = 'contratos'
    and fn_es_admin_o_lider() is true
  );


-- ── D · Generar el borrador, y adjuntar la firma después ───────────────────
-- Todos los parámetros llevan default: los dos usos de esta función (generar
-- un borrador nuevo, o adjuntar la firma a uno existente) no comparten qué es
-- obligatorio, así que lo obligatorio de cada rama se exige adentro — mismo
-- criterio que ya usa `fn_documento_registrar` (0157) con `p_persona_id`.
create or replace function fn_contrato_registrar(
  p_persona_id            uuid    default null,
  p_tipo                  text    default null,
  p_cargo                 text    default null,
  p_sede_id               uuid    default null,
  p_remuneracion_mensual  numeric default null,
  p_fecha_inicio          date    default null,
  p_fecha_fin             date    default null,
  p_horas_semanales       numeric default null,
  p_documento_html        text    default null,
  p_id                    uuid    default null,   -- no nulo = adjuntar firma a un borrador existente
  p_storage_path          text    default null,
  p_fecha_firma           date    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_yo uuid := fn_persona_actual_id();
  r    contratos_generados%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional genera contratos.';
  end if;

  -- ── Adjuntar la firma a un borrador ya generado ──
  if p_id is not null then
    select * into r from contratos_generados where id = p_id;
    if not found then raise exception 'Ese contrato no existe.'; end if;
    if r.anulado_at is not null then raise exception 'Ese contrato está anulado.'; end if;
    if r.storage_path is not null then raise exception 'Ese contrato ya tiene un escaneo registrado.'; end if;
    if p_storage_path is null then raise exception 'Falta el escaneo firmado.'; end if;
    if p_fecha_firma is null then raise exception 'Falta la fecha en que se firmó.'; end if;
    if p_fecha_firma > fn_hoy_lima() then raise exception 'La fecha de firma no puede ser futura.'; end if;

    update contratos_generados
       set storage_path = p_storage_path, fecha_firma = p_fecha_firma, registrado_por = v_yo
     where id = p_id;

    -- Recién con la firma puesta se mueve la fecha de vencimiento de la
    -- persona — un borrador descartado nunca debe haber tocado este dato.
    if r.tipo in ('nuevo', 'renovacion') then
      perform fn_set_fin_contrato(r.persona_id, r.fecha_fin, 'Contrato firmado — generador de contratos');
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'contrato_firmado', null,
       r.tipo || ' · firmado el ' || p_fecha_firma::text, v_yo,
       'Escaneo del contrato firmado registrado');

    return p_id;
  end if;

  -- ── Generar el borrador ──
  if p_tipo not in ('nuevo', 'renovacion', 'adendum') then
    raise exception 'Tipo de contrato inválido: «%».', p_tipo;
  end if;
  if p_persona_id is null or not exists (
    select 1 from personas where id = p_persona_id and estado = 'activo'
  ) then
    raise exception 'Esa persona no existe o no está activa.';
  end if;
  if p_cargo is null or btrim(p_cargo) = '' then
    raise exception 'Falta el cargo.';
  end if;
  if p_sede_id is null then
    raise exception 'Falta la sede.';
  end if;
  if p_remuneracion_mensual is null or p_remuneracion_mensual < 0 then
    raise exception 'Falta la remuneración, o es inválida.';
  end if;
  if p_fecha_inicio is null or p_fecha_fin is null or p_fecha_fin <= p_fecha_inicio then
    raise exception 'Las fechas del contrato son inválidas.';
  end if;
  if p_documento_html is null or btrim(p_documento_html) = '' then
    raise exception 'Falta el texto del contrato.';
  end if;

  insert into contratos_generados (
    persona_id, tipo, cargo, sede_id, remuneracion_mensual,
    fecha_inicio, fecha_fin, horas_semanales, documento_html, generado_por
  ) values (
    p_persona_id, p_tipo, trim(p_cargo), p_sede_id, p_remuneracion_mensual,
    p_fecha_inicio, p_fecha_fin, p_horas_semanales, p_documento_html, v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'contrato_generado', null,
     p_tipo || ' · generado el ' || fn_hoy_lima()::text, v_yo,
     'Alta de borrador de contrato');

  return v_id;
end;
$$;

grant execute on function fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, uuid, text, date
) to authenticated;


-- ── E · Anular, que no es borrar ────────────────────────────────────────────
create or replace function fn_contrato_anular(p_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r contratos_generados%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional anula contratos.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se anula.';
  end if;

  select * into r from contratos_generados where id = p_id;
  if not found then raise exception 'Ese contrato no existe.'; end if;
  if r.anulado_at is not null then raise exception 'Ese contrato ya estaba anulado.'; end if;

  update contratos_generados
     set anulado_at = now(), anulado_por = fn_persona_actual_id(), anulado_motivo = trim(p_motivo)
   where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id, 'contrato_anulado',
     r.tipo || ' · generado el ' || r.generado_at::date::text, 'anulado',
     fn_persona_actual_id(), trim(p_motivo));
end;
$$;

grant execute on function fn_contrato_anular(uuid, text) to authenticated;


-- ── F · Listar ───────────────────────────────────────────────────────────────
create or replace function fn_contratos_listar(p_persona_id uuid default null)
returns table (
  id                    uuid,
  persona_id            uuid,
  persona               text,
  tipo                  text,
  cargo                 text,
  sede                  text,
  remuneracion_mensual  numeric,
  fecha_inicio          date,
  fecha_fin             date,
  horas_semanales       numeric,
  generado_at           timestamptz,
  storage_path          text,
  fecha_firma           date,
  anulado_at            timestamptz,
  anulado_motivo        text,
  vigente               boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id, c.persona_id, p.nombres || ' ' || p.apellidos,
    c.tipo, c.cargo, s.nombre,
    c.remuneracion_mensual, c.fecha_inicio, c.fecha_fin, c.horas_semanales,
    c.generado_at, c.storage_path, c.fecha_firma,
    c.anulado_at, c.anulado_motivo,
    -- Vigente = el más reciente sin anular de esa persona.
    (c.anulado_at is null and c.id = (
       select c2.id from contratos_generados c2
        where c2.persona_id = c.persona_id and c2.anulado_at is null
        order by c2.generado_at desc limit 1))
  from contratos_generados c
  join personas p on p.id = c.persona_id
  left join sedes s on s.id = c.sede_id
  where (fn_es_admin_o_lider() is true or c.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or c.persona_id = p_persona_id)
  order by c.generado_at desc;
$$;

grant execute on function fn_contratos_listar(uuid) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (272, 'los_contratos_generados_entran_al_sistema')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_personas int;
begin
  select count(*) into v_personas from personas where estado = 'activo' and en_planilla;
  raise notice '0272 · personas en planilla que podrian necesitar un contrato: %', v_personas;
  raise notice '0272 · contratos generados: 0 (la tabla nace vacia)';
  raise notice '0272 · esta migracion no cambia ningun sueldo ni ninguna fecha_fin_contrato.';
end $mig$;
