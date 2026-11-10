-- ============================================================================
-- 0612_el_contrato_de_locacion_se_genera_y_se_firma_en_dynamic.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el contrato de locación de servicios de quien cobra por recibo por
--   honorarios (RxH) se GENERE en Dynamic y la persona lo FIRME desde «Lo mío»,
--   como ya pasa con el contrato de trabajo y el convenio de prácticas.
--   Pedido por Felipe el 2026-11-10.
--
--   Hasta la 0610 un contrato de locación solo podía entrar como escaneo de un
--   papel ya firmado. Esa vía sigue igual: esta migración suma la otra.
--
-- QUÉ ASUME
--   · La 0610 pegada tal cual (2026-11-10). El bloque 0 lo comprueba por el md5
--     de las cuatro funciones que reescribe y se niega a seguir si alguna no es
--     la que se pegó.
--   · `firmas_escaneadas` (0076): la firma de cada persona, como imagen.
--   · El texto lo arma la pantalla con `lib/admin/locacion-texto.ts`, igual que
--     el contrato de trabajo con `contrato-texto.ts` (0272): la base guarda el
--     documento congelado, no lo redacta.
--
-- ── LO QUE NO LLEVA, Y POR QUÉ ──────────────────────────────────────────────
--
--   Felipe pidió «cargo, horas, sueldo, modalidad», como el contrato de trabajo.
--   Esas cuatro cosas son los indicios con que un juez o SUNAFIL declaran que
--   una locación era en realidad un trabajo (art. 4 del D.S. 003-97-TR,
--   primacía de la realidad), y firmadas en el propio sistema serían la prueba.
--   Lo vio y eligió una locación CIVIL: servicio, entregables, plazo y
--   HONORARIOS. Por eso las columnas nuevas son `honorarios` y `periodicidad`,
--   y no hay cargo, jornada ni remuneración en ningún lado de la tabla.
--
-- ── CÓMO SE FIRMA ────────────────────────────────────────────────────────────
--
--   Como el contrato de trabajo desde la 0430: confirmar tu firma ES firmar. Se
--   guarda una COPIA de la imagen de la firma en ese momento (molde de la
--   0402): si la persona cambia su firma general después, el contrato sigue
--   mostrando la que firmó. La de CAYLA no se guarda: se estampa al mostrar con
--   la del firmante configurado, igual que en el contrato de trabajo.
--
--   Un contrato generado y sin firmar NO cubre a nadie: el tablero lo cuenta
--   aparte («falta firma») y no como contrato vigente.
--
-- ── ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles) ──────────────
--
--   · un contrato sin escaneo ni documento ........ check
--   · un escaneo a medias (ruta sin peso, etc.) .... check
--   · uno generado sin honorarios o sin RUC ........ check
--   · un RUC que no es de persona natural .......... check de forma
--   · firmado sin la copia de la firma, o al revés . check
--   · un escaneo sin fecha de firma ................ check (el papel ya llegó
--                                                     firmado)
--   · volver a firmar, o cambiar la firma de uno ya
--     firmado ...................................... trigger
--   · firmar el contrato de otra persona ........... la función
--   · terminar uno que nunca se firmó .............. la función (se anula)
--
-- ── SE ROMPE SI ─────────────────────────────────────────────────────────────
--
--   La pantalla arma el texto con datos viejos (un RUC mal escrito, honorarios
--   que cambiaron): la base no puede comprobar que el documento dice lo mismo
--   que las columnas, igual que en el contrato de trabajo. La salida es la de
--   siempre: anular y volver a generar antes de que lo firmen.
--
-- ── CÓMO SE PEGA ─────────────────────────────────────────────────────────────
--
--   En UNA pegada: altera una sola tabla (`contratos_locacion`), y lo demás son
--   funciones. Empieza con `lock_timeout = '3s'`: si falla por candado, se
--   repega.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   Con contratos generados ya guardados NO se revierte soltando las columnas:
--   se perdería el documento firmado. Si hace falta: anular los generados y
--   recién entonces
--     drop function fn_locacion_generar(uuid, text, date, date, numeric, text, text, text),
--                   fn_confirmar_mi_firma_locacion(uuid), fn_locacion_documento(uuid);
--   y volver a pegar las cuatro funciones de la 0610 (tablero, listar,
--   inmutables y terminar) desde ese archivo.
-- ============================================================================

set local lock_timeout = '3s';

-- ── 0 · La 0610 tiene que ser la que se pegó ────────────────────────────────
-- Las cuatro que esta migración reescribe, con el md5 de su cuerpo en la 0610.
-- Si alguna no coincide, es otra versión que nadie midió: PARAR.
do $$
declare
  v_esperado constant jsonb := jsonb_build_object(
    'fn_contratos_locacion_inmutables', 'b182b634ca32f5d4c5cd08e7b73a1baf',
    'fn_locaciones_tablero',            'ccdbeb1d432e2ad49dcaec1823396205',
    'fn_locaciones_listar',             'ca1e46790f94b2a52dc4680bc509134f',
    'fn_locacion_terminar',             '48fad6f4c033166dc5a5c1adc64eca77');
  v_ya_aplicada boolean := exists (select 1 from migraciones_aplicadas where numero = 612);
  r record;
begin
  if v_ya_aplicada then
    return;  -- repegar la 0612 no vuelve a medir: ya reemplazó estas cuatro.
  end if;
  for r in
    select k.nombre, k.md5_esperado, (
             select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = k.nombre) as md5_real
      from jsonb_each_text(v_esperado) as k(nombre, md5_esperado)
  loop
    if r.md5_real is distinct from r.md5_esperado then
      raise exception 'PARAR: % en esta base no es la de la 0610 (md5 % y se esperaba %). No se aplicó nada.',
        r.nombre, coalesce(r.md5_real, 'NO EXISTE'), r.md5_esperado;
    end if;
  end loop;
end;
$$;


-- ── 1 · La tabla: un contrato puede ser un escaneo o un documento ───────────
alter table contratos_locacion
  add column if not exists documento_html text,
  add column if not exists honorarios numeric(10,2),
  add column if not exists periodicidad text,
  add column if not exists ruc_locador text,
  add column if not exists firma_persona text,
  add column if not exists firma_persona_confirmada_at timestamptz;

-- Lo que antes era obligatorio porque todo contrato era un escaneo.
alter table contratos_locacion
  alter column storage_path drop not null,
  alter column nombre_archivo drop not null,
  alter column mime drop not null,
  alter column bytes drop not null,
  alter column fecha_firma drop not null;

alter table contratos_locacion
  drop constraint if exists locacion_tiene_papel,
  drop constraint if exists locacion_escaneo_completo,
  drop constraint if exists locacion_generado_completo,
  drop constraint if exists locacion_ruc_de_persona,
  drop constraint if exists locacion_periodicidad_valida,
  drop constraint if exists locacion_firma_coherente;

alter table contratos_locacion
  add constraint locacion_tiene_papel check (storage_path is not null or documento_html is not null),
  add constraint locacion_escaneo_completo check (
    (storage_path is null and nombre_archivo is null and mime is null and bytes is null)
    or (storage_path is not null and nombre_archivo is not null and mime is not null and bytes is not null)
  ),
  add constraint locacion_generado_completo check (
    documento_html is null
    or (btrim(documento_html) <> '' and honorarios > 0 and periodicidad is not null and ruc_locador is not null)
  ),
  -- RUC de persona natural: 10 + 9 dígitos (15 y 17 son los de quien no tiene DNI).
  add constraint locacion_ruc_de_persona check (ruc_locador is null or ruc_locador ~ '^(10|15|17)[0-9]{9}$'),
  add constraint locacion_periodicidad_valida check (periodicidad is null or periodicidad in ('mensual', 'total')),
  -- Un escaneo llega firmado. Uno generado tiene las tres cosas de la firma juntas, o ninguna.
  add constraint locacion_firma_coherente check (
    (documento_html is null and fecha_firma is not null
       and firma_persona is null and firma_persona_confirmada_at is null)
    or (documento_html is not null and (
          (fecha_firma is null and firma_persona is null and firma_persona_confirmada_at is null)
          or (fecha_firma is not null and firma_persona ~ '^data:image/(png|jpeg);base64,'
              and firma_persona_confirmada_at is not null)))
  );

comment on column contratos_locacion.documento_html is
  'El contrato generado en Dynamic, congelado (lib/admin/locacion-texto.ts). Null = se registró como escaneo de un papel firmado (0610). Las dos firmas no viajan aquí: se estampan al mostrar.';
comment on column contratos_locacion.firma_persona is
  'Copia de la firma de la persona al momento de firmar (molde 0402). No cambia si después cambia su firma general.';


-- ── 2 · Lo que no se edita: ahora también la firma, una vez ──────────────────
-- Después de creado se escribe, como mucho: la firma (una vez, solo en uno
-- generado), el término (una vez) o la anulación (una vez). Todo desde el
-- sistema.
create or replace function fn_contratos_locacion_inmutables()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un contrato de locación no se borra: si se registró por error, se anula con motivo.';
  end if;
  if current_user <> 'postgres' then
    raise exception 'Un contrato de locación solo se modifica desde el sistema.';
  end if;
  if old.anulado_at is not null then
    raise exception 'Ese contrato ya está anulado.';
  end if;
  if old.terminado_el is not null then
    raise exception 'Ese contrato ya se dio por terminado.';
  end if;
  if (new.id, new.persona_id, new.servicio, new.fecha_inicio, new.fecha_fin,
      new.storage_path, new.nombre_archivo, new.mime, new.bytes, new.registrado_por, new.registrado_at,
      new.documento_html, new.honorarios, new.periodicidad, new.ruc_locador)
     is distinct from
     (old.id, old.persona_id, old.servicio, old.fecha_inicio, old.fecha_fin,
      old.storage_path, old.nombre_archivo, old.mime, old.bytes, old.registrado_por, old.registrado_at,
      old.documento_html, old.honorarios, old.periodicidad, old.ruc_locador) then
    raise exception 'Un contrato de locación no se edita: si tiene un dato mal, se anula y se registra de nuevo.';
  end if;
  if old.fecha_firma is not null
     and (new.fecha_firma, new.firma_persona, new.firma_persona_confirmada_at)
         is distinct from (old.fecha_firma, old.firma_persona, old.firma_persona_confirmada_at) then
    raise exception 'Ese contrato ya está firmado.';
  end if;
  return new;
end;
$fn$;


-- ── 3 · DO genera el contrato ───────────────────────────────────────────────
-- Contrato: guarda el documento que armó la pantalla, sin firmar. Devuelve su
-- id. Solo para quien cobra hoy por honorarios: una locación ya terminada de
-- alguien que pasó a planilla se archiva como escaneo (0610), no se genera.
create or replace function fn_locacion_generar(
  p_persona_id     uuid,
  p_servicio       text,
  p_fecha_inicio   date,
  p_fecha_fin      date,
  p_honorarios     numeric,
  p_periodicidad   text,
  p_ruc_locador    text,
  p_documento_html text
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_p     personas%rowtype;
  v_id    uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional genera contratos de locación.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select * into v_p from personas p where p.id = p_persona_id;
  if not found or v_p.cuenta_de_servicio then
    raise exception 'Esa persona no existe.';
  end if;
  if v_p.estado <> 'activo' or v_p.tipo_vinculo <> 'rxh' then
    raise exception 'Solo se genera el contrato de quien cobra hoy por recibo por honorarios.';
  end if;

  if p_servicio is null or char_length(btrim(p_servicio)) < 3 then
    raise exception 'Escribe qué servicio se contrata (al menos 3 letras), con las palabras del contrato.';
  end if;
  if p_fecha_inicio is null or p_fecha_fin is null then
    raise exception 'Faltan las fechas de inicio y de fin del contrato.';
  end if;
  if p_fecha_fin < p_fecha_inicio then
    raise exception 'El contrato no puede terminar antes de empezar.';
  end if;
  if p_honorarios is null or p_honorarios <= 0 then
    raise exception 'Faltan los honorarios.';
  end if;
  if p_periodicidad is null or p_periodicidad not in ('mensual', 'total') then
    raise exception 'Elige si los honorarios son mensuales o por todo el servicio.';
  end if;
  if p_ruc_locador is null or btrim(p_ruc_locador) !~ '^(10|15|17)[0-9]{9}$' then
    raise exception 'El RUC tiene que ser el de una persona natural: 11 dígitos que empiezan con 10.';
  end if;
  -- Las dos firmas se estampan sobre estas marcas al mostrar: sin ellas, el
  -- contrato no tendría dónde llevarlas.
  if p_documento_html is null or position('<!--FIRMA_EMPRESA-->' in p_documento_html) = 0
     or position('<!--FIRMA_PERSONA-->' in p_documento_html) = 0 then
    raise exception 'El documento no tiene dónde llevar las firmas. Vuelve a generarlo.';
  end if;

  insert into contratos_locacion
    (persona_id, servicio, fecha_inicio, fecha_fin, honorarios, periodicidad, ruc_locador,
     documento_html, registrado_por)
  values
    (p_persona_id, btrim(p_servicio), p_fecha_inicio, p_fecha_fin, round(p_honorarios, 2), p_periodicidad,
     btrim(p_ruc_locador), p_documento_html, v_quien)
  returning id into v_id;

  return v_id;
end;
$fn$;


-- ── 4 · La persona firma SU contrato ────────────────────────────────────────
-- Confirmar es firmar (molde 0430), con la copia de su firma de ese momento
-- (molde 0402). Una sola vez: no se vuelve a firmar ni a cambiar la firma de
-- un contrato ya firmado.
create or replace function fn_confirmar_mi_firma_locacion(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_yo     uuid := fn_persona_actual_id();
  v_c      contratos_locacion%rowtype;
  v_imagen text;
begin
  if v_yo is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select * into v_c from contratos_locacion c where c.id = p_id for update;
  if not found or v_c.persona_id <> v_yo then
    -- El mismo mensaje para «no existe» y «no es tuyo»: no se confirma que exista.
    raise exception 'No se encontró ese contrato.';
  end if;
  if v_c.anulado_at is not null then
    raise exception 'Ese contrato está anulado.';
  end if;
  if v_c.documento_html is null then
    raise exception 'Ese contrato se firmó en papel: aquí no hay nada que firmar.';
  end if;
  if v_c.fecha_firma is not null then
    raise exception 'Ya firmaste este contrato.';
  end if;

  select f.imagen into v_imagen from firmas_escaneadas f where f.persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Hazlo aquí mismo, arriba, antes de firmar.';
  end if;

  update contratos_locacion
     set firma_persona = v_imagen, firma_persona_confirmada_at = now(), fecha_firma = fn_hoy_lima()
   where id = p_id;
end;
$fn$;


-- ── 5 · El documento, para mostrarlo ────────────────────────────────────────
-- Aparte del historial a propósito: el documento pesa, y la lista no lo
-- necesita. Lo ve DO, o la persona si es suyo y no está anulado (mismo cuidado
-- que el historial de la 0610: uno anulado puede ser el de otra persona).
create or replace function fn_locacion_documento(p_id uuid)
returns table (documento_html text, firma_persona text)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  return query
  select c.documento_html, c.firma_persona
    from contratos_locacion c
   where c.id = p_id
     and c.documento_html is not null
     and (fn_es_admin_o_lider() is true
          or (c.persona_id = fn_persona_actual_id() and c.anulado_at is null));
end;
$fn$;


-- ── 6 · Terminar: solo un contrato que se llegó a firmar ────────────────────
-- Mismo cuerpo que la 0610, con una regla más al leer el contrato.
create or replace function fn_locacion_terminar(p_id uuid, p_fecha date, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_c     contratos_locacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional termina contratos de locación.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe por qué termina (al menos 5 letras): queda anotado junto al contrato.';
  end if;
  if p_fecha is null then
    raise exception 'Falta el último día en que valió el contrato.';
  end if;

  select * into v_c from contratos_locacion c where c.id = p_id for update;
  if not found then
    raise exception 'Ese contrato no existe.';
  end if;
  if v_c.anulado_at is not null then
    raise exception 'Ese contrato está anulado: no se termina.';
  end if;
  if v_c.terminado_el is not null then
    raise exception 'Ese contrato ya se dio por terminado.';
  end if;
  -- CAMBIO 0612: uno generado que nadie firmó nunca valió; si no va, se anula.
  if v_c.fecha_firma is null then
    raise exception 'Ese contrato todavía no está firmado: si ya no va, se anula.';
  end if;
  if p_fecha >= v_c.fecha_fin then
    raise exception 'Esa fecha no es antes del fin del contrato: no hace falta terminarlo.';
  end if;
  if p_fecha < v_c.fecha_inicio - 1 then
    raise exception 'El último día no puede ser anterior a la víspera de su inicio.';
  end if;

  update contratos_locacion
     set terminado_el = p_fecha, terminado_motivo = btrim(p_motivo),
         terminado_por = v_quien, terminado_at = now()
   where id = p_id;
end;
$fn$;


-- ── 7 · El historial: dice si se generó en Dynamic y si falta la firma ──────
-- Mismo cuerpo que la 0610 (lo propio para quien no es DO, sin anulados ni
-- motivos internos), con dos columnas más y un estado más. `drop` + `create`:
-- Postgres no deja cambiar las columnas de una función que devuelve TABLE.
--
--   sin_firmar ... generado en Dynamic y todavía sin la firma de la persona
drop function if exists fn_locaciones_listar(uuid);
create function fn_locaciones_listar(p_persona_id uuid default null)
returns table (
  id                   uuid,
  persona_id           uuid,
  persona              text,
  servicio             text,
  fecha_inicio         date,
  fecha_fin            date,
  fecha_firma          date,
  storage_path         text,
  nombre_archivo       text,
  mime                 text,
  bytes                bigint,
  estado               text,
  registrado_por_nombre text,
  registrado_at        timestamptz,
  terminado_el         date,
  terminado_motivo     text,
  terminado_por_nombre text,
  anulado_at           timestamptz,
  anulado_motivo       text,
  anulado_por_nombre   text,
  es_digital           boolean,
  honorarios           numeric,
  periodicidad         text
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_do boolean := fn_es_admin_o_lider() is true;
  v_yo uuid    := fn_persona_actual_id();
begin
  if not v_do then
    if v_yo is null then
      raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
    end if;
    if p_persona_id is not null and p_persona_id <> v_yo then
      raise exception 'Solo Desarrollo Organizacional ve los contratos de locación de otra persona.';
    end if;
  end if;

  return query
  select c.id, c.persona_id, btrim(p.nombres || ' ' || p.apellidos), c.servicio,
         c.fecha_inicio, c.fecha_fin, c.fecha_firma,
         c.storage_path, c.nombre_archivo, c.mime, c.bytes,
         case when c.anulado_at is not null       then 'anulado'
              when c.fecha_firma is null          then 'sin_firmar'   -- CAMBIO 0612
              when c.terminado_el is not null     then 'terminado'
              when c.fecha_inicio > fn_hoy_lima() then 'por_empezar'
              when c.fecha_fin < fn_hoy_lima()    then 'concluido'
              else 'en_curso' end,
         btrim(pr.nombres || ' ' || pr.apellidos), c.registrado_at,
         c.terminado_el,
         case when v_do then c.terminado_motivo end,
         case when v_do then btrim(pt.nombres || ' ' || pt.apellidos) end,
         c.anulado_at, c.anulado_motivo, btrim(pa.nombres || ' ' || pa.apellidos),
         c.documento_html is not null, c.honorarios, c.periodicidad
    from contratos_locacion c
    join personas p       on p.id  = c.persona_id
    left join personas pr on pr.id = c.registrado_por
    left join personas pt on pt.id = c.terminado_por
    left join personas pa on pa.id = c.anulado_por
   where (v_do and (p_persona_id is null or c.persona_id = p_persona_id))
      or (not v_do and c.persona_id = v_yo and c.anulado_at is null)
   order by (c.anulado_at is not null), c.fecha_inicio desc, c.registrado_at desc, c.id desc;
end;
$fn$;


-- ── 8 · El tablero: un contrato sin firmar no cubre a nadie ─────────────────
-- Mismo cuerpo que la 0610, con dos cambios marcados:
--   · `vivos` deja fuera lo que no se firmó: un contrato vale desde que está
--     firmado, no desde que se generó;
--   · si a alguien le falta contrato (no tiene, se le venció o se le vence
--     pronto) y ya hay uno generado esperando su firma, su estado es
--     `sin_firmar`: lo que falta ya no es redactarlo, es que lo firme.
--   `pendiente_firma` lo dice en cualquier estado (una renovación generada
--   mientras el actual sigue vigente, por ejemplo).
drop function if exists fn_locaciones_tablero();
create function fn_locaciones_tablero()
returns table (
  persona_id      uuid,
  persona         text,
  sede            text,
  vinculo_actual  text,
  contrato_id     uuid,
  servicio        text,
  fecha_inicio    date,
  cubierto_hasta  date,
  dias_restantes  integer,
  n_contratos     integer,
  estado          text,
  pendiente_firma boolean
)
language sql stable security definer set search_path = public
as $fn$
  with vivos as (
    select c.*, coalesce(c.terminado_el, c.fecha_fin) as fin_real
      from contratos_locacion c
     where c.anulado_at is null
       and c.fecha_firma is not null   -- CAMBIO 0612
       and coalesce(c.terminado_el, c.fecha_fin) >= c.fecha_inicio
  ),
  ultimo as (
    select distinct on (v.persona_id)
           v.persona_id, v.id, v.servicio, v.fecha_inicio, v.fin_real
      from vivos v
     order by v.persona_id, v.fin_real desc, v.registrado_at desc, v.id desc
  ),
  resumen as (
    select v.persona_id,
           count(*)::int as n,
           bool_or(v.fecha_inicio <= fn_hoy_lima() and v.fin_real >= fn_hoy_lima()) as cubierta_hoy
      from vivos v
     group by v.persona_id
  ),
  -- CAMBIO 0612: generados que esperan la firma de la persona.
  por_firmar as (
    select distinct c.persona_id
      from contratos_locacion c
     where c.anulado_at is null and c.fecha_firma is null and c.fecha_fin >= fn_hoy_lima()
  ),
  abiertas as (
    select distinct c.persona_id
      from contratos_locacion c
     where c.anulado_at is null and c.terminado_el is null and c.fecha_fin >= fn_hoy_lima()
  ),
  filas as (
    select p.id as persona_id,
           p.nombres || ' ' || p.apellidos as persona,
           p.apellidos,
           coalesce(s.codigo, '—') as sede,
           case when p.estado <> 'activo' then 'cesada' else p.tipo_vinculo end as vinculo_actual,
           u.id as contrato_id, u.servicio, u.fecha_inicio, u.fin_real,
           coalesce(r.n, 0) as n,
           pf.persona_id is not null as pendiente,
           case
             when not (p.estado = 'activo' and p.tipo_vinculo = 'rxh') then 'abierta_sin_rxh'
             when u.id is null                         then 'sin_contrato'
             when u.fin_real < fn_hoy_lima()           then 'vencido'
             when not r.cubierta_hoy                   then 'por_empezar'
             when u.fin_real - fn_hoy_lima() <= 60     then 'por_vencer'
             else 'vigente'
           end as base
      from personas p
      left join sedes s       on s.id = p.sede_base_id
      left join ultimo u      on u.persona_id = p.id
      left join resumen r     on r.persona_id = p.id
      left join por_firmar pf on pf.persona_id = p.id
     where not p.cuenta_de_servicio
       and ((p.estado = 'activo' and p.tipo_vinculo = 'rxh')
            or p.id in (select a.persona_id from abiertas a))
       and fn_es_admin_o_lider() is true
  )
  select f.persona_id, f.persona, f.sede, f.vinculo_actual, f.contrato_id, f.servicio, f.fecha_inicio,
         f.fin_real, (f.fin_real - fn_hoy_lima())::int, f.n,
         case when f.pendiente and f.base in ('sin_contrato', 'vencido', 'por_vencer') then 'sin_firmar'
              else f.base end,
         f.pendiente
    from filas f
   order by case
              when f.base = 'abierta_sin_rxh' then 0
              when f.pendiente and f.base in ('sin_contrato', 'vencido', 'por_vencer') then 3
              when f.base = 'vencido'         then 1
              when f.base = 'sin_contrato'    then 2
              when f.base = 'por_vencer'      then 4
              when f.base = 'por_empezar'     then 5
              else 6
            end,
            f.fin_real nulls last, f.apellidos, f.persona_id;
$fn$;


-- ── 9 · Quién puede llamar qué ───────────────────────────────────────────────
grant execute on function
  fn_locaciones_tablero(), fn_locaciones_listar(uuid),
  fn_locacion_generar(uuid, text, date, date, numeric, text, text, text),
  fn_confirmar_mi_firma_locacion(uuid), fn_locacion_documento(uuid)
to authenticated;
revoke execute on function
  fn_locaciones_tablero(), fn_locaciones_listar(uuid),
  fn_locacion_generar(uuid, text, date, date, numeric, text, text, text),
  fn_confirmar_mi_firma_locacion(uuid), fn_locacion_documento(uuid)
from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (612, 'el_contrato_de_locacion_se_genera_y_se_firma_en_dynamic')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'contratos_locacion'
      and column_name in ('documento_html', 'honorarios', 'periodicidad', 'ruc_locador',
                          'firma_persona', 'firma_persona_confirmada_at')) as columnas_de_6,
  (select count(*) from pg_constraint
    where conrelid = 'public.contratos_locacion'::regclass
      and conname in ('locacion_tiene_papel', 'locacion_escaneo_completo', 'locacion_generado_completo',
                      'locacion_ruc_de_persona', 'locacion_periodicidad_valida', 'locacion_firma_coherente')) as reglas_de_6,
  (select count(*) from pg_proc where proname in (
     'fn_locacion_generar', 'fn_confirmar_mi_firma_locacion', 'fn_locacion_documento')) as funciones_nuevas_de_3,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 612) as registro;
