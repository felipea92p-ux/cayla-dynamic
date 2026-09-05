-- ============================================================================
-- 0287 — El contrato firmado se registra siempre, y sus dos plazos se miden
-- ============================================================================
--
-- QUÉ PROMETE
--   1. Que subir el escaneo de un contrato firmado NUNCA falle por el estado
--      de la persona.
--   2. Que una adenda de prórroga mueva la fecha de vencimiento, igual que una
--      renovación.
--   3. Que el sistema pueda responder «¿a quién le falta contrato?» partiendo
--      de las PERSONAS y no de los contratos.
--   4. Que los dos plazos que el propio contrato promete —copia en 3 días
--      hábiles, comunicación a la Autoridad de Trabajo en 15 días naturales—
--      dejen de existir solo en el papel.
--
-- QUÉ ASUME
--   La 0272 (`contratos_generados`, `fn_contrato_registrar`), la 0144
--   (`fn_set_fin_contrato`, `personas.fecha_fin_contrato`) y la 0231
--   (`fn_contratos_desnaturalizados`).
--
-- ── EL DEFECTO 1, Y POR QUÉ ERA EL PEOR ────────────────────────────────────
--
-- Al adjuntar el escaneo, la 0272 llama a `fn_set_fin_contrato`, que corta con
-- «Esa persona ya está inactiva». O sea: si alguien CESÓ entre que se imprimió
-- el contrato y que volvió firmado, su contrato firmado NO SE PUEDE REGISTRAR
-- NUNCA. Todo se revierte y el archivo queda huérfano en el bucket.
--
-- Y es al revés de lo que hace falta: el papel de quien ya no está es
-- precisamente el que hay que poder archivar —es el que sustenta lo que se le
-- pagó y en qué condiciones—. Ahora el escaneo se registra SIEMPRE; lo que se
-- omite, cuando la persona ya no está activa, es mover su fecha de
-- vencimiento, que para alguien cesado no significa nada. Y se dice en la
-- auditoría, para que la omisión no sea silenciosa.
--
-- ── EL DEFECTO 2 ───────────────────────────────────────────────────────────
--
-- La fecha nueva solo se propagaba para `nuevo` y `renovacion`. Una adenda de
-- prórroga guardaba su `fecha_fin` y la persona seguía marcada con la vieja:
-- el sistema la habría contado como vencida —o desnaturalizada— estando al
-- día. Felipe decidió (2026-08-24) hacer las prórrogas como `renovacion`, así
-- que hoy esto no le pasa a nadie; se arregla igual porque una trampa que solo
-- espera a que alguien elija la otra opción sigue siendo una trampa.
--
-- ── LOS DOS PLAZOS ─────────────────────────────────────────────────────────
--
-- La cláusula décima octava del contrato que este sistema imprime promete
-- entregar copia a la colaboradora dentro de 3 días hábiles del inicio de la
-- prestación, y comunicar el contrato a la Autoridad Administrativa de Trabajo
-- dentro de 15 días naturales de suscrito. Hasta hoy no había dónde anotar si
-- se cumplieron.
--
-- Se guardan como FECHAS y no como booleanos: «sí, se entregó» no sirve para
-- probar nada; «se entregó el 3 de enero» sí. Nullable = todavía no.
--
-- ⚠️ LO QUE ESTA MIGRACIÓN NO DECIDE. Si la comunicación al MTPE sigue siendo
-- exigible y en qué forma es una pregunta legal que este repositorio no puede
-- responder —el trámite cambió con el aplicativo virtual—. Lo que sí es
-- verificable es que el contrato que CAYLA imprime se obliga a hacerlo en 15
-- días. Mientras esa cláusula esté en el papel, el plazo existe. Si el abogado
-- la cambia, se cambia el molde y estos campos siguen sirviendo igual.
--
-- CÓMO SE REVIERTE
--   alter table contratos_generados
--     drop column if exists copia_entregada_at,
--     drop column if exists comunicado_mtpe_at;
--   drop function if exists fn_contrato_marcar_tramite(uuid, text, date);
--   drop function if exists fn_contratos_tablero();
--   Y volver a pegar la 0272 para `fn_contrato_registrar`.
-- ============================================================================


-- ── A · Los dos plazos que el contrato promete ─────────────────────────────
alter table contratos_generados add column if not exists copia_entregada_at date;
alter table contratos_generados add column if not exists comunicado_mtpe_at  date;

comment on column contratos_generados.copia_entregada_at is
  'Cuando se le entrego copia del contrato a la colaboradora. La clausula '
  'decima octava da 3 dias habiles desde el inicio de la prestacion. Fecha y '
  'no booleano: «se entrego» no prueba nada, «se entrego el 3 de enero» si.';
comment on column contratos_generados.comunicado_mtpe_at is
  'Cuando se comunico el contrato a la Autoridad Administrativa de Trabajo. La '
  'clausula decima octava da 15 dias naturales desde la suscripcion. Si esa '
  'obligacion cambia, se cambia el molde del contrato: este campo sigue '
  'sirviendo para anotar la fecha en que se hizo.';


-- ── B · Registrar la firma: ya no falla por el estado de la persona ────────
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
  v_id      uuid;
  v_yo      uuid := fn_persona_actual_id();
  v_activa  boolean;
  v_nota    text := '';
  r         contratos_generados%rowtype;
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

    -- El archivo tiene que ser EL DE ESTE CONTRATO. `p_storage_path` es texto
    -- libre, y `fn_contrato_puede_ver` resuelve el permiso por el uuid que va
    -- en el nombre del archivo: apuntar la fila de una persona al escaneo de
    -- otra dejaría a la primera sin poder abrir su propio contrato y a la
    -- segunda viéndolo. Se cierra acá, que es donde se elige el path.
    if p_storage_path !~ ('^contratos/' || p_id::text || '\.') then
      raise exception 'La ruta del escaneo no corresponde a este contrato.';
    end if;

    update contratos_generados
       set storage_path = p_storage_path, fecha_firma = p_fecha_firma, registrado_por = v_yo
     where id = p_id;

    -- La fecha de vencimiento se mueve recién con la firma puesta: un borrador
    -- descartado nunca debe haber tocado este dato.
    --
    -- PERO NO SE DEJA CAER EL REGISTRO SI LA PERSONA YA NO ESTÁ ACTIVA. Ese era
    -- el defecto: `fn_set_fin_contrato` corta con «ya está inactiva», y quien
    -- cesó entre imprimir y firmar se quedaba SIN PODER ARCHIVAR su contrato
    -- firmado — justo el papel que hay que conservar. Para alguien cesado la
    -- fecha de vencimiento no significa nada; el documento sí.
    select (estado = 'activo') into v_activa from personas where id = r.persona_id;
    if r.tipo in ('nuevo', 'renovacion', 'adendum') then
      if v_activa is true then
        perform fn_set_fin_contrato(r.persona_id, r.fecha_fin, 'Contrato firmado — generador de contratos');
      else
        v_nota := ' · no se movió su fecha de vencimiento: la persona ya no está activa';
      end if;
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'contrato_firmado', null,
       r.tipo || ' · firmado el ' || p_fecha_firma::text, v_yo,
       'Escaneo del contrato firmado registrado' || v_nota);

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


-- ── C · Anotar cuándo se cumplió cada plazo ────────────────────────────────
-- Una sola función para los dos trámites, con el trámite como parámetro: son
-- el mismo gesto (anotar una fecha en un contrato ya firmado) y separarlos en
-- dos funciones idénticas solo duplicaría los guards.
create or replace function fn_contrato_marcar_tramite(
  p_id      uuid,
  p_tramite text,                 -- 'copia' | 'mtpe'
  p_fecha   date default null     -- null = hoy
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r      contratos_generados%rowtype;
  v_f    date := coalesce(p_fecha, fn_hoy_lima());
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional anota estos trámites.';
  end if;
  if p_tramite not in ('copia', 'mtpe') then
    raise exception 'Trámite inválido: «%». Solo «copia» o «mtpe».', p_tramite;
  end if;
  if v_f > fn_hoy_lima() then
    raise exception 'La fecha no puede ser futura: un trámite se anota cuando ya se hizo.';
  end if;

  select * into r from contratos_generados where id = p_id;
  if not found then raise exception 'Ese contrato no existe.'; end if;
  if r.anulado_at is not null then raise exception 'Ese contrato está anulado.'; end if;
  -- Sin firma no hay nada que entregar ni que comunicar: los dos plazos corren
  -- sobre un contrato SUSCRITO, y anotarlos sobre un borrador daría por hecho
  -- un trámite imposible.
  if r.fecha_firma is null then
    raise exception 'Ese contrato todavía no está firmado.';
  end if;

  if p_tramite = 'copia' then
    update contratos_generados set copia_entregada_at = v_f where id = p_id;
  else
    update contratos_generados set comunicado_mtpe_at = v_f where id = p_id;
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id,
     case when p_tramite = 'copia' then 'contrato_copia_entregada' else 'contrato_comunicado_mtpe' end,
     null, v_f::text, fn_persona_actual_id(),
     case when p_tramite = 'copia'
          then 'Entrega de copia del contrato a la colaboradora'
          else 'Comunicacion del contrato a la Autoridad Administrativa de Trabajo' end);
end;
$$;

grant execute on function fn_contrato_marcar_tramite(uuid, text, date) to authenticated;


-- ── D · El tablero: parte de las PERSONAS, no de los contratos ─────────────
--
-- La lista del historial arranca `from contratos_generados`, así que quien no
-- tiene ninguno ES INVISIBLE ahí. Con veinte contratos venciendo el mismo día,
-- la pregunta que hay que poder hacer no es «¿qué generé?» sino «¿a quién le
-- falta?», y esa solo se responde partiendo de la gente.
--
-- Es el mismo criterio de `fn_documentos_tablero` (0157): se arma de quien
-- está en planilla, así que alguien que entra aparece pendiente desde su
-- primer día sin que nadie lo agregue a una lista.
create or replace function fn_contratos_tablero()
returns table (
  persona_id            uuid,
  persona               text,
  sede                  text,
  fecha_fin_contrato    date,
  dias_restantes        int,
  contrato_id           uuid,
  tipo                  text,
  fecha_firma           date,
  copia_entregada_at    date,
  comunicado_mtpe_at    date,
  copia_vence           date,
  mtpe_vence            date,
  dias_marcados_despues int,
  estado                text
)
language sql
stable
security definer
set search_path = public
as $$
  with ultimo as (
    -- El contrato que manda por persona: el más reciente sin anular.
    select distinct on (c.persona_id)
           c.persona_id, c.id, c.tipo, c.fecha_firma, c.fecha_inicio,
           c.copia_entregada_at, c.comunicado_mtpe_at
      from contratos_generados c
     where c.anulado_at is null
     order by c.persona_id, c.generado_at desc
  ),
  -- Marcó días DESPUÉS de su fecha de fin: el riesgo del art. 77 que la 0231
  -- ya sabe calcular y que hasta hoy no miraba ninguna pantalla.
  desn as (select * from fn_contratos_desnaturalizados())
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '—'),
    p.fecha_fin_contrato,
    (p.fecha_fin_contrato - fn_hoy_lima())::int,
    u.id, u.tipo, u.fecha_firma,
    u.copia_entregada_at, u.comunicado_mtpe_at,
    -- Los dos plazos de la cláusula décima octava. El de la copia corre desde
    -- el inicio de la prestación y es en días HÁBILES; se aproxima con días
    -- calendario + 2, que es lo que puede hacer una consulta sin calendario de
    -- feriados delante — y para avisar con tiempo basta.
    (u.fecha_inicio + 5)::date,
    (u.fecha_firma + 15)::date,
    coalesce(d.dias_marcados_despues, 0),
    case
      when d.persona_id is not null                     then 'desnaturalizado'
      when u.id is null                                 then 'sin_contrato'
      when u.fecha_firma is null                        then 'sin_firmar'
      when p.fecha_fin_contrato is null                 then 'sin_vencimiento'
      when p.fecha_fin_contrato < fn_hoy_lima()         then 'vencido'
      when p.fecha_fin_contrato - fn_hoy_lima() <= 60   then 'por_vencer'
      when u.copia_entregada_at is null
        or u.comunicado_mtpe_at is null                 then 'tramite_pendiente'
      else 'ok'
    end
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join ultimo u on u.persona_id = p.id
  left join desn d on d.persona_id = p.id
  where p.estado = 'activo'
    and p.en_planilla
    and fn_es_admin_o_lider() is true
  -- Lo que urge primero: quien ya está en riesgo, y después por vencimiento.
  order by
    case
      when d.persona_id is not null then 0
      when u.id is null then 1
      when u.fecha_firma is null then 2
      else 3
    end,
    p.fecha_fin_contrato nulls last,
    p.apellidos;
$$;

grant execute on function fn_contratos_tablero() to authenticated;


-- ── E · El listado, con los dos plazos y con quién hizo qué ────────────────
-- Devuelve TABLE, así que no admite `create or replace` con columnas nuevas:
-- se borra y se vuelve a crear, como hace la 0161 con `fn_documentos_tablero`.
drop function if exists fn_contratos_listar(uuid);

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
  generado_por          text,
  storage_path          text,
  fecha_firma           date,
  copia_entregada_at    date,
  comunicado_mtpe_at    date,
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
    c.generado_at,
    gen.nombres || ' ' || gen.apellidos,
    c.storage_path, c.fecha_firma,
    c.copia_entregada_at, c.comunicado_mtpe_at,
    c.anulado_at, c.anulado_motivo,
    (c.anulado_at is null and c.id = (
       select c2.id from contratos_generados c2
        where c2.persona_id = c.persona_id and c2.anulado_at is null
        order by c2.generado_at desc limit 1))
  from contratos_generados c
  join personas p on p.id = c.persona_id
  left join personas gen on gen.id = c.generado_por
  left join sedes s on s.id = c.sede_id
  where (fn_es_admin_o_lider() is true or c.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or c.persona_id = p_persona_id)
  order by c.generado_at desc;
$$;

grant execute on function fn_contratos_listar(uuid) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (287, 'el_contrato_firmado_se_registra_y_sus_plazos_se_miden')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_personas int;
  v_sin      int;
begin
  select count(*) into v_personas from personas where estado = 'activo' and en_planilla;
  select count(*) into v_sin
    from personas p
   where p.estado = 'activo' and p.en_planilla
     and not exists (select 1 from contratos_generados c
                      where c.persona_id = p.id and c.anulado_at is null);
  raise notice '0287 · personas en planilla: %', v_personas;
  raise notice '0287 · de esas, SIN ningun contrato generado: %', v_sin;
  raise notice '0287 · el tablero ya se puede consultar: select * from fn_contratos_tablero();';
end $mig$;
