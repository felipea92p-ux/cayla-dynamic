-- ============================================================================
-- 0450 — La constancia de estudios se entrega, y Desarrollo Organizacional la
--        revisa.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que cada integrante con una asignación por educación suba desde su portal
--   la constancia de cada pago que hace a su institución —uno o varios
--   archivos—, que DO la apruebe o la rechace con motivo, y que todo quede en
--   un historial que nadie puede borrar ni reescribir.
--
--   Tres piezas, separadas a propósito:
--     ASIGNACIÓN  (asignaciones_educacion)    el beneficio. Ahora sabe además
--                                              cuándo es su próximo pago.
--     ENTREGA     (educacion_entregas)        la constancia de UN pago, con su
--                                              estado y quién la revisó.
--     ARCHIVO     (educacion_entrega_archivos) las páginas de esa entrega.
--   Más un aviso (educacion_avisos_fin) para «ya no voy a pagar».
--
-- LO QUE DECIDIÓ FELIPE (2026-09-15), Y POR QUÉ ESTA MIGRACIÓN ES COMO ES
--
--   · SOLO ALERTA. Aprobar o rechazar NO cambia lo que cobra nadie. La planilla
--     sigue preguntando `comprobante_url is not null`, igual que desde la 0150.
--     Esta migración no toca fn_planilla_calcular.
--   · Una entrega PENDIENTE o RECHAZADA nunca enciende ese pago. El espejo
--     (fn_educacion_refrescar_espejo) solo mira entregas APROBADAS. Era el
--     riesgo mayor: con el diseño de la 0290, un archivo subido por la propia
--     interesada habría activado el pago antes de que nadie lo mirara.
--   · El calendario sigue a la INSTITUCIÓN, no a la planilla: frecuencia y
--     próxima fecha de pago, que avanzan solas con cada constancia aprobada.
--   · Plazo: la constancia vence N días (5) antes del cierre del periodo en que
--     cae el pago. Aviso a la integrante N días (7) antes del plazo; aviso a DO
--     N días (7) antes del pago. Los tres números viven en `configuracion`.
--   · Aprueba solo DO (fn_es_admin_o_lider). Nadie aprueba su propia constancia.
--   · Mientras está pendiente se RETIRA (queda marcada, no se borra) o se
--     reemplaza. Revisada, ya no se toca.
--   · El rechazo exige categoría y un comentario de al menos 3 caracteres.
--   · Lo que carga DO a nombre de alguien queda aprobado al instante, con
--     registro de quién lo cargó. Los papeles que ya existían pasan como
--     aprobados («migrada»).
--
-- POR QUÉ `familia_id`
--
--   Una corrección que mueve plata cierra la fila de la asignación y abre otra
--   (0149). Si las constancias colgaran solo de la fila, la vigencia nueva
--   nacería sin ninguna aprobada y dejaría de pagar sin que nada lo avise — la
--   0290 lo evitaba COPIANDO los papeles, y copiar una entrega revisada
--   duplicaría registros de auditoría. Así que las filas de una misma
--   asignación comparten `familia_id` y el espejo mira la familia entera.
--
--   Las filas que ya existen arrancan cada una como su propia familia. No se
--   infiere el parentesco de correcciones pasadas: inferirlo (por `created_at`)
--   podría encender un pago en una fila que hoy no lo tiene, y eso es cambiar
--   plata. Se verifica al final (sección K): si una sola asignación cambiara de
--   «paga» a «no paga» o al revés, la migración aborta entera.
--
-- POR QUÉ LA TABLA DE LA 0290 SIGUE VIVA
--
--   `educacion_comprobantes` no se borra ni deja de aceptar filas: pasa a ser
--   una PUERTA que refleja cada papel como una entrega aprobada, con el MISMO
--   id. Entre que esto se pega y se fusiona la pantalla nueva, la vieja sigue
--   subiendo papeles por ahí (registrar y adjuntar), y con la tabla muerta una
--   asignación nueva registrada en esa ventana no cobraría. Reusar el id
--   conserva además el desempate de la 0391 (mes, fecha, id).
--
--   Lo que sí cambia: quitar un comprobante se niega. Borrar la fila vieja ya no
--   apagaría nada, y una función que parece funcionar sin hacer nada es peor
--   que una que dice que no.
--
-- QUÉ ASUME
--
--   · md5 de PARTIDA, medidos en PRODUCCIÓN el 2026-09-15 (coinciden con el
--     repositorio, tal cual, comentarios incluidos):
--       fn_educacion_registrar            dd2703802f41199b62a6807e0a8f7563 · 9988  (0327)
--       fn_educacion_por_atender          4d13250a46dc0009081f75b865b6bb01 ·  526  (0290)
--       fn_educacion_quitar_comprobante   8ecf49d83fb6a55cc09dd832c70b5f08 · 1025  (0290)
--       fn_educacion_espejo_comprobante   be9d44db873a2dcf2f9dba1fc37a3c50 ·  748  (0391)
--       fn_bandeja_marcar_visto           2acf861c9961c9d81dce9bcb7958d51f ·  593  (0436)
--     Si alguno cambió antes de pegar, PARAR: alguien las reescribió.
--   · El bucket privado `comprobantes` (0136/0154) con sus cuatro políticas, y
--     `fn_educacion_puede_ver` (0136): cada quien lee lo de su carpeta.
--   · periodos_planilla (0025), configuracion (0007), bandeja_vistos (0436),
--     correcciones_auditoria, fn_hoy_lima, fn_es_admin_o_lider,
--     fn_persona_actual_id.
--
-- QUÉ NO HACE
--
--   · No toca la planilla ni la boleta.
--   · No reescribe fn_educacion_listar ni fn_educacion_adjuntar_comprobante:
--     siguen funcionando sobre la tabla de la 0290 mientras la pantalla vieja
--     exista.
--   · No manda correos.
--   · No borra ningún archivo del almacén.
--
-- CÓMO SE REVIERTE
--
--   Las entregas enviadas desde el portal SE PIERDEN al revertir: guardarlas
--   antes (select * from educacion_entregas / educacion_entrega_archivos).
--
--   drop trigger if exists trg_educacion_comprobante_a_entrega on educacion_comprobantes;
--   -- el espejo de la 0290/0391, de vuelta:
--   create trigger trg_educacion_espejo_comprobante
--     after insert or update or delete on educacion_comprobantes
--     for each row execute function fn_educacion_espejo_comprobante();
--   drop table educacion_avisos_fin, educacion_entrega_archivos, educacion_entregas;
--   drop function fn_educacion_situacion(), fn_educacion_entregas(uuid),
--     fn_educacion_entregas_pendientes(), fn_educacion_avisos_fin_pendientes(),
--     fn_educacion_enviar_entrega(uuid,uuid,date,text,date,jsonb,text,uuid),
--     fn_educacion_retirar_entrega(uuid), fn_educacion_resolver_entrega(uuid,boolean,text,text),
--     fn_educacion_fijar_calendario(uuid,text,date), fn_educacion_avisar_fin(uuid,text,date),
--     fn_educacion_atender_aviso_fin(uuid,text), fn_educacion_configurar(text,int,int,int),
--     fn_educacion_avanzar_calendario(uuid), fn_educacion_plazo(date),
--     fn_educacion_parametro(text,int), fn_educacion_refrescar_espejo(uuid),
--     fn_educacion_puede_subir_entrega(text), fn_educacion_ruta_congelada(text),
--     fn_educacion_entrega_inmutable(), fn_educacion_archivo_inmutable(),
--     fn_educacion_entrega_espejo(), fn_educacion_archivo_espejo(),
--     fn_educacion_comprobante_a_entrega(), fn_educacion_familia_por_defecto();
--   alter table asignaciones_educacion drop column familia_id,
--     drop column frecuencia_pago, drop column proxima_fecha_pago;
--   -- políticas del almacén: volver a pegar las de la 0136 (insert, delete) y
--   -- la 0172 (update); drop policy comprobantes_insert_entrega_propia y
--   -- comprobantes_update_entrega_propia.
--   -- fn_educacion_registrar, fn_educacion_por_atender y
--   -- fn_educacion_quitar_comprobante: volver a pegar de la 0327 y la 0290.
--   -- fn_bandeja_marcar_visto y el check de bandeja_vistos: de la 0436.
--   delete from configuracion where clave like 'educacion_%';
-- ============================================================================


-- ── A · La foto de antes: quién cobra hoy ───────────────────────────────────
-- Se compara al final (sección K). Es la promesa de «solo alerta» escrita como
-- algo que se puede verificar, no como una intención.
create temp table _educacion_paga_antes_0450 on commit drop as
select id, (comprobante_url is not null) as con_papel
  from asignaciones_educacion;


-- ── B · La asignación aprende su calendario y su familia ────────────────────
alter table asignaciones_educacion
  add column if not exists familia_id         uuid,
  add column if not exists frecuencia_pago    text,
  add column if not exists proxima_fecha_pago date;

update asignaciones_educacion set familia_id = id where familia_id is null;

alter table asignaciones_educacion alter column familia_id set not null;

alter table asignaciones_educacion drop constraint if exists asignacion_educacion_frecuencia_valida;
alter table asignaciones_educacion add constraint asignacion_educacion_frecuencia_valida
  check (frecuencia_pago is null or frecuencia_pago in ('mensual', 'ciclo', 'unico', 'otra'));

create index if not exists idx_asignaciones_educacion_familia
  on asignaciones_educacion (familia_id, vigente_desde);

comment on column asignaciones_educacion.familia_id is
  'La asignación de la que esta fila es una vigencia. Una corrección que mueve plata '
  'cierra la fila y abre otra con el mismo familia_id (0450): las constancias se leen '
  'por familia, así que la vigencia nueva no nace sin sustento.';
comment on column asignaciones_educacion.frecuencia_pago is
  'Cada cuánto cobra la institución: mensual, ciclo, unico u otra. Solo orienta la '
  'fecha sugerida; la próxima fecha real es proxima_fecha_pago.';
comment on column asignaciones_educacion.proxima_fecha_pago is
  'Cuándo vuelve a pagar la integrante a su institución. La pone DO al registrar y '
  'avanza sola con cada constancia aprobada (fn_educacion_avanzar_calendario). null = '
  'sin calendario, o ya no quedan pagos declarados.';

-- Una fila nueva sin familia es su propia familia. La que abre una corrección
-- la trae puesta desde fn_educacion_registrar.
create or replace function fn_educacion_familia_por_defecto()
returns trigger
language plpgsql
as $$
begin
  new.familia_id := coalesce(new.familia_id, new.id);
  return new;
end;
$$;

drop trigger if exists trg_educacion_familia_por_defecto on asignaciones_educacion;
create trigger trg_educacion_familia_por_defecto
  before insert on asignaciones_educacion
  for each row execute function fn_educacion_familia_por_defecto();


-- ── C · Las tablas nuevas ───────────────────────────────────────────────────
-- Las referencias a la asignación son DEFERRABLE: la corrección de la 0149
-- borra la fila vieja ANTES de crear la nueva (si no, el candado del techo
-- sumaría las dos), y las entregas se mudan a la nueva en la misma
-- transacción. La comprobación llega al confirmar, así que una entrega nunca
-- queda colgando de una asignación que no existe; solo se le da tiempo a la
-- mudanza.
create table if not exists educacion_entregas (
  id                  uuid primary key default gen_random_uuid(),
  asignacion_id       uuid not null
                        references asignaciones_educacion(id) deferrable initially deferred,
  -- La fecha en que la integrante pagó a la institución: el pago que esta
  -- constancia sustenta.
  fecha_pago          date not null,
  tipo                text not null,
  -- La que ella declara al enviar. null = no hay más pagos declarados.
  proxima_fecha_pago  date,
  nota                text,
  estado              text not null default 'pendiente',
  -- colaboradora: la subió la propia integrante · do: la cargó DO a su nombre ·
  -- migrada: ya estaba antes de la 0450, o llegó por la tabla de la 0290 sin
  -- saber quién.
  origen              text not null default 'colaboradora',
  enviada_at          timestamptz not null default now(),
  enviada_por         uuid references personas(id),
  revisada_at         timestamptz,
  revisada_por        uuid references personas(id),
  retirada_at         timestamptz,
  motivo_categoria    text,
  motivo_comentario   text,
  reemplaza_a         uuid references educacion_entregas(id),

  constraint educacion_entrega_tipo_valido check (tipo in
    ('matricula', 'cuota_mensual', 'pago_ciclo', 'curso_taller', 'otro')),
  constraint educacion_entrega_estado_valido check (estado in
    ('pendiente', 'aprobada', 'rechazada', 'retirada')),
  constraint educacion_entrega_origen_valido check (origen in
    ('colaboradora', 'do', 'migrada')),
  constraint educacion_entrega_motivo_valido check (motivo_categoria is null or motivo_categoria in
    ('ilegible', 'no_corresponde_al_pago', 'a_nombre_de_otra_persona',
     'faltan_paginas_o_datos', 'otra_institucion', 'otro')),
  -- Los estados que NUNCA deben existir, uno por constraint para que el error
  -- diga cuál se violó.
  constraint educacion_entrega_pendiente_sin_revision check (
    estado <> 'pendiente' or (revisada_at is null and revisada_por is null and retirada_at is null)),
  constraint educacion_entrega_revisada_completa check (
    estado not in ('aprobada', 'rechazada')
    or (revisada_at is not null and (revisada_por is not null or origen = 'migrada'))),
  constraint educacion_entrega_retirada_con_fecha check (
    (estado = 'retirada') = (retirada_at is not null)),
  constraint educacion_entrega_rechazo_con_motivo check (
    estado <> 'rechazada'
    or (motivo_categoria is not null and length(trim(coalesce(motivo_comentario, ''))) >= 3)),
  constraint educacion_entrega_motivo_solo_si_rechazo check (
    estado = 'rechazada' or (motivo_categoria is null and motivo_comentario is null)),
  constraint educacion_entrega_proxima_despues check (
    proxima_fecha_pago is null or proxima_fecha_pago > fecha_pago)
);

comment on table educacion_entregas is
  'La constancia de UN pago a la institución, con su revisión (0450). No se borra ni se '
  'reescribe: se retira mientras está pendiente, o queda en el historial.';

-- Una sola entrega pendiente por pago. Es la red contra dos envíos casi
-- simultáneos del mismo archivo — mismo mecanismo que uq_solicitud_perfil_pendiente.
create unique index if not exists uq_educacion_entrega_pendiente
  on educacion_entregas (asignacion_id, fecha_pago) where estado = 'pendiente';
create index if not exists idx_educacion_entregas_asignacion
  on educacion_entregas (asignacion_id, fecha_pago desc);
create index if not exists idx_educacion_entregas_pendientes
  on educacion_entregas (enviada_at) where estado = 'pendiente';

create table if not exists educacion_entrega_archivos (
  id            uuid primary key default gen_random_uuid(),
  entrega_id    uuid not null references educacion_entregas(id),
  storage_path  text not null,
  nombre        text not null,
  -- null solo en papeles que llegaron antes de la 0450 (el almacén de la 0136
  -- no guardaba nada que se pudiera copiar con certeza).
  tipo_mime     text,
  bytes         bigint,
  orden         smallint not null,
  created_at    timestamptz not null default now(),
  constraint educacion_archivo_bytes_positivos check (bytes is null or bytes > 0),
  constraint educacion_archivo_no_duplicado unique (entrega_id, storage_path),
  constraint educacion_archivo_orden_unico unique (entrega_id, orden)
);

comment on table educacion_entrega_archivos is
  'Las páginas de una entrega de constancia (0450). DO aprueba o rechaza la entrega '
  'entera, no cada archivo.';

create table if not exists educacion_avisos_fin (
  id                uuid primary key default gen_random_uuid(),
  asignacion_id     uuid not null
                      references asignaciones_educacion(id) deferrable initially deferred,
  motivo            text not null,
  ultimo_pago       date,
  creado_at         timestamptz not null default now(),
  creado_por        uuid not null references personas(id),
  atendido_at       timestamptz,
  atendido_por      uuid references personas(id),
  respuesta         text,
  constraint educacion_aviso_fin_motivo check (length(trim(motivo)) >= 3),
  constraint educacion_aviso_fin_atendido_completo check (
    (atendido_at is null) = (atendido_por is null))
);

comment on table educacion_avisos_fin is
  'La integrante avisa que ya no va a pagar su estudio. No cierra nada: cerrar mueve '
  'plata y lo decide DO (fn_educacion_cerrar). Molde de movilidad_revisiones_pedidas.';

create unique index if not exists uq_educacion_aviso_fin_pendiente
  on educacion_avisos_fin (asignacion_id) where atendido_at is null;

-- Lectura: DO todo, cada quien lo suyo. Escritura: solo por las funciones.
alter table educacion_entregas         enable row level security;
alter table educacion_entrega_archivos enable row level security;
alter table educacion_avisos_fin       enable row level security;

revoke all on educacion_entregas, educacion_entrega_archivos, educacion_avisos_fin
  from authenticated, anon, public;
grant select on educacion_entregas, educacion_entrega_archivos, educacion_avisos_fin
  to authenticated;

drop policy if exists educacion_entregas_lectura on educacion_entregas;
create policy educacion_entregas_lectura on educacion_entregas
  for select to authenticated
  using (exists (
    select 1 from asignaciones_educacion a
     where a.id = educacion_entregas.asignacion_id
       and (fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id())));

drop policy if exists educacion_archivos_lectura on educacion_entrega_archivos;
create policy educacion_archivos_lectura on educacion_entrega_archivos
  for select to authenticated
  using (exists (
    select 1 from educacion_entregas e
      join asignaciones_educacion a on a.id = e.asignacion_id
     where e.id = educacion_entrega_archivos.entrega_id
       and (fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id())));

drop policy if exists educacion_avisos_fin_lectura on educacion_avisos_fin;
create policy educacion_avisos_fin_lectura on educacion_avisos_fin
  for select to authenticated
  using (exists (
    select 1 from asignaciones_educacion a
     where a.id = educacion_avisos_fin.asignacion_id
       and (fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id())));


-- ── D · Lo revisado no se reescribe ni se borra ─────────────────────────────
-- Un trigger y no la confianza (ver CLAUDE.md, «un campo sensible se cambia por
-- una función guardián»). Lo único que puede cambiar de una entrega es:
--   · su estado, y solo desde «pendiente»;
--   · a qué vigencia cuelga, cuando una corrección la muda (sección J).
create or replace function fn_educacion_entrega_inmutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception
      'Una entrega de constancia no se borra: se retira mientras está pendiente, o queda en el historial.';
  end if;

  if (new.id, new.fecha_pago, new.tipo, new.proxima_fecha_pago, new.nota, new.origen,
      new.enviada_at, new.enviada_por, new.reemplaza_a)
     is distinct from
     (old.id, old.fecha_pago, old.tipo, old.proxima_fecha_pago, old.nota, old.origen,
      old.enviada_at, old.enviada_por, old.reemplaza_a) then
    raise exception 'Lo que se envió en una constancia no se reescribe. Si hay que corregirlo, se envía otra.';
  end if;

  if old.estado <> 'pendiente'
     and (new.estado, new.revisada_at, new.revisada_por, new.retirada_at,
          new.motivo_categoria, new.motivo_comentario)
         is distinct from
         (old.estado, old.revisada_at, old.revisada_por, old.retirada_at,
          old.motivo_categoria, old.motivo_comentario) then
    raise exception 'Esta constancia ya está %: su revisión no se cambia.', old.estado;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_educacion_entrega_inmutable on educacion_entregas;
create trigger trg_educacion_entrega_inmutable
  before update or delete on educacion_entregas
  for each row execute function fn_educacion_entrega_inmutable();

create or replace function fn_educacion_archivo_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Un archivo de una constancia enviada no se cambia ni se borra.';
end;
$$;

drop trigger if exists trg_educacion_archivo_inmutable on educacion_entrega_archivos;
create trigger trg_educacion_archivo_inmutable
  before update or delete on educacion_entrega_archivos
  for each row execute function fn_educacion_archivo_inmutable();


-- ── E · Parámetros, plazo y espejo ──────────────────────────────────────────
-- Los días viven en `configuracion` y no acá: DO los cambia sin una migración.
-- El defecto solo se usa si alguien borró la fila.
create or replace function fn_educacion_parametro(p_clave text, p_defecto int)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (c.valor #>> '{}')::int from configuracion c where c.clave = p_clave),
                  p_defecto);
$$;

-- El último día para entregar la constancia de un pago: el fin del periodo de
-- planilla en que cae ese pago, menos N días. Si ese día ya quedó antes del
-- pago (la institución cobra el 27 y el periodo cierra el 28), el plazo pasa al
-- periodo siguiente. Los periodos se leen de periodos_planilla: no van siempre
-- del 29 al 28 (el de setiembre de 2026 cierra el 27). null = el periodo que
-- tocaría todavía no está creado.
create or replace function fn_educacion_plazo(p_fecha_pago date)
returns date
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_dias int := fn_educacion_parametro('educacion_dias_plazo_antes_cierre', 5);
  v_fin  date;
begin
  if p_fecha_pago is null then return null; end if;

  select pp.fecha_fin into v_fin
    from periodos_planilla pp
   where p_fecha_pago between pp.fecha_ini and pp.fecha_fin
   order by pp.fecha_ini, pp.id
   limit 1;

  if v_fin is null or v_fin - v_dias < p_fecha_pago then
    select pp.fecha_fin into v_fin
      from periodos_planilla pp
     where pp.fecha_ini > coalesce(v_fin, p_fecha_pago)
     order by pp.fecha_ini, pp.id
     limit 1;
  end if;

  return v_fin - v_dias;
end;
$$;

-- El espejo que lee la planilla, ahora desde las entregas APROBADAS de toda la
-- familia. Mismo desempate que la 0391: la más reciente por pago, luego por
-- revisión, luego el ancla.
create or replace function fn_educacion_refrescar_espejo(p_familia_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  with papel as (
    select ar.storage_path
      from educacion_entregas e
      join asignaciones_educacion x on x.id = e.asignacion_id
      join educacion_entrega_archivos ar on ar.entrega_id = e.id
     where x.familia_id = p_familia_id
       and e.estado = 'aprobada'
     order by e.fecha_pago desc, e.revisada_at desc, e.id desc, ar.orden, ar.id
     limit 1)
  update asignaciones_educacion a
     set comprobante_url = (select storage_path from papel)
   where a.familia_id = p_familia_id
     and a.comprobante_url is distinct from (select storage_path from papel);
$$;

create or replace function fn_educacion_entrega_espejo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_educacion_refrescar_espejo(a.familia_id)
     from asignaciones_educacion a
    where a.id in (new.asignacion_id, old.asignacion_id);
  return null;
end;
$$;

drop trigger if exists trg_educacion_entrega_espejo on educacion_entregas;
create trigger trg_educacion_entrega_espejo
  after insert or update on educacion_entregas
  for each row execute function fn_educacion_entrega_espejo();

create or replace function fn_educacion_archivo_espejo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_educacion_refrescar_espejo(a.familia_id)
     from educacion_entregas e
     join asignaciones_educacion a on a.id = e.asignacion_id
    where e.id = new.entrega_id;
  return null;
end;
$$;

drop trigger if exists trg_educacion_archivo_espejo on educacion_entrega_archivos;
create trigger trg_educacion_archivo_espejo
  after insert on educacion_entrega_archivos
  for each row execute function fn_educacion_archivo_espejo();


-- ── F · Los papeles que ya estaban pasan como aprobados ─────────────────────
-- Con el MISMO id que tenían en educacion_comprobantes. Idempotente: repegar
-- no duplica (on conflict).
insert into educacion_entregas
  (id, asignacion_id, fecha_pago, tipo, estado, origen, nota,
   enviada_at, enviada_por, revisada_at, revisada_por)
select c.id, c.asignacion_id, c.mes_cubierto, 'otro', 'aprobada', 'migrada', c.nota,
       c.created_at, c.subido_por, c.created_at, c.subido_por
  from educacion_comprobantes c
on conflict (id) do nothing;

insert into educacion_entrega_archivos (entrega_id, storage_path, nombre, tipo_mime, bytes, orden)
select c.id, c.storage_path, regexp_replace(c.storage_path, '^.*/', ''),
       o.metadata->>'mimetype', nullif(o.metadata->>'size', '')::bigint, 1
  from educacion_comprobantes c
  left join storage.objects o on o.bucket_id = 'comprobantes' and o.name = c.storage_path
on conflict (entrega_id, storage_path) do nothing;


-- ── G · La tabla de la 0290 pasa a ser una puerta ───────────────────────────
-- Su espejo se retira (ahora lo mantienen las entregas) y en su lugar cada
-- papel que entre por ahí se refleja como entrega aprobada.
drop trigger if exists trg_educacion_espejo_comprobante on educacion_comprobantes;

create or replace function fn_educacion_comprobante_a_entrega()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into educacion_entregas
    (id, asignacion_id, fecha_pago, tipo, estado, origen, nota,
     enviada_at, enviada_por, revisada_at, revisada_por)
  values
    (new.id, new.asignacion_id, new.mes_cubierto, 'otro', 'aprobada',
     case when new.subido_por is null then 'migrada' else 'do' end, new.nota,
     new.created_at, new.subido_por, new.created_at, new.subido_por)
  on conflict (id) do nothing;

  insert into educacion_entrega_archivos (entrega_id, storage_path, nombre, tipo_mime, bytes, orden)
  select new.id, new.storage_path, regexp_replace(new.storage_path, '^.*/', ''),
         o.metadata->>'mimetype', nullif(o.metadata->>'size', '')::bigint, 1
    from (select 1) uno
    left join storage.objects o on o.bucket_id = 'comprobantes' and o.name = new.storage_path
  on conflict (entrega_id, storage_path) do nothing;

  return null;
end;
$$;

drop trigger if exists trg_educacion_comprobante_a_entrega on educacion_comprobantes;
create trigger trg_educacion_comprobante_a_entrega
  after insert on educacion_comprobantes
  for each row execute function fn_educacion_comprobante_a_entrega();

comment on table educacion_comprobantes is
  'Desde la 0450, una PUERTA: cada fila que entra se refleja como entrega aprobada en '
  'educacion_entregas (mismo id), que es la verdad. Se conserva porque la pantalla de '
  'la 0290 todavía escribe acá.';

-- La 0290 dejó sin fila de papel a ninguna asignación con columna llena, pero
-- se comprueba igual: si existiera una, el espejo nuevo le apagaría el pago.
insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, nota, subido_por)
select a.id, a.comprobante_url, fn_educacion_mes_del_periodo(a.vigente_desde),
       'Cargado antes de la 0290 sin fila de papel; rescatado por la 0450.', a.registrado_por
  from asignaciones_educacion a
 where a.comprobante_url is not null
   and not exists (select 1 from educacion_entregas e where e.asignacion_id = a.id and e.estado = 'aprobada');

do $refrescar$
begin
  perform fn_educacion_refrescar_espejo(f.familia_id)
     from (select distinct familia_id from asignaciones_educacion) f;
end $refrescar$;


-- ── H · Funciones de la integrante ──────────────────────────────────────────
-- Avanza el calendario de la familia con una constancia aprobada. Solo hacia
-- adelante: aprobar tarde la constancia de un pago viejo no puede devolver la
-- próxima fecha al pasado.
create or replace function fn_educacion_avanzar_calendario(p_entrega_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update asignaciones_educacion a
     set proxima_fecha_pago = e.proxima_fecha_pago
    from educacion_entregas e
    join asignaciones_educacion x on x.id = e.asignacion_id
   where e.id = p_entrega_id
     and e.estado = 'aprobada'
     and a.familia_id = x.familia_id
     and (a.proxima_fecha_pago is null or e.fecha_pago >= a.proxima_fecha_pago);
$$;

revoke execute on function fn_educacion_avanzar_calendario(uuid) from public, anon, authenticated;

-- Enviar una constancia. Los archivos se suben ANTES a
-- `educacion/<persona>/entregas/<p_id>/…` (la política del almacén solo lo deja
-- mientras ese id no exista), y esta función los valida contra lo que el almacén
-- dice de verdad —tipo y peso—, no contra lo que declaró el navegador.
--
-- Si la subida se corta a la mitad no queda nada pendiente: sin esta llamada no
-- hay entrega. La pantalla conserva los archivos elegidos y reintenta con el
-- mismo id.
create or replace function fn_educacion_enviar_entrega(
  p_id                 uuid,
  p_asignacion_id      uuid,
  p_fecha_pago         date,
  p_tipo               text,
  p_proxima_fecha_pago date,
  p_archivos           jsonb,          -- [{ "ruta": "...", "nombre": "..." }]
  p_nota               text default null,
  p_reemplaza_a        uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_asg     asignaciones_educacion%rowtype;
  v_duena   boolean;
  v_prev    educacion_entregas%rowtype;
  v_estado  text;
  v_n       int;
  v_prefijo text;
  v_arch    jsonb;
  v_ruta    text;
  v_meta    jsonb;
  v_orden   int := 0;
  v_desde   date;
begin
  if v_yo is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;

  select * into v_asg from asignaciones_educacion where id = p_asignacion_id;
  if not found then raise exception 'Esa asignación por educación no existe.'; end if;

  v_duena := v_asg.persona_id = v_yo;
  if v_duena is not true and fn_es_admin_o_lider() is not true then
    raise exception 'Solo la propia integrante o Desarrollo Organizacional envían la constancia de este estudio.';
  end if;

  -- Lo propio siempre pasa por revisión, aunque quien lo envíe sea de DO.
  v_estado := case when v_duena then 'pendiente' else 'aprobada' end;

  if p_id is null then raise exception 'Falta el identificador del envío.'; end if;
  if exists (select 1 from educacion_entregas where id = p_id) then
    raise exception 'Ese envío ya existe. Para corregirlo, reemplázalo.';
  end if;
  if p_tipo is null or p_tipo not in ('matricula', 'cuota_mensual', 'pago_ciclo', 'curso_taller', 'otro') then
    raise exception 'Elige qué tipo de constancia es.';
  end if;
  if p_fecha_pago is null then
    raise exception 'Indica en qué fecha se pagó a la institución.';
  end if;
  if p_fecha_pago > fn_hoy_lima() then
    raise exception 'La fecha de pago (%) todavía no llega: la constancia se sube después de pagar.',
      to_char(p_fecha_pago, 'DD/MM/YYYY');
  end if;

  select min(vigente_desde) into v_desde
    from asignaciones_educacion where familia_id = v_asg.familia_id;
  if p_fecha_pago < v_desde - 62 then
    raise exception 'Ese pago (%) es de antes de que empezara este apoyo (%).',
      to_char(p_fecha_pago, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;
  if p_proxima_fecha_pago is not null and p_proxima_fecha_pago <= p_fecha_pago then
    raise exception 'La próxima fecha de pago tiene que ser posterior a la que se pagó.';
  end if;

  v_n := jsonb_array_length(coalesce(p_archivos, '[]'::jsonb));
  if v_n < 1 then raise exception 'Adjunta al menos un archivo.'; end if;
  if v_n > 10 then raise exception 'Una entrega admite hasta 10 archivos (llegaron %).', v_n; end if;

  if p_reemplaza_a is not null then
    select e.* into v_prev
      from educacion_entregas e
      join asignaciones_educacion x on x.id = e.asignacion_id
     where e.id = p_reemplaza_a and x.familia_id = v_asg.familia_id
       for update of e;
    if not found then raise exception 'La constancia que quieres reemplazar no es de este estudio.'; end if;

    if v_prev.estado = 'pendiente' then
      if v_prev.enviada_por is distinct from v_yo then
        raise exception 'Solo quien envió una constancia pendiente puede reemplazarla.';
      end if;
      update educacion_entregas set estado = 'retirada', retirada_at = now() where id = v_prev.id;
    elsif v_prev.estado <> 'rechazada' then
      raise exception 'Solo se reemplaza una constancia pendiente o rechazada; esta ya está %.', v_prev.estado;
    end if;
  end if;

  begin
    insert into educacion_entregas
      (id, asignacion_id, fecha_pago, tipo, proxima_fecha_pago, nota, estado, origen,
       enviada_por, revisada_at, revisada_por, reemplaza_a)
    values
      (p_id, p_asignacion_id, p_fecha_pago, p_tipo, p_proxima_fecha_pago,
       nullif(trim(coalesce(p_nota, '')), ''), v_estado,
       case when v_duena then 'colaboradora' else 'do' end,
       v_yo,
       case when v_estado = 'aprobada' then now() end,
       case when v_estado = 'aprobada' then v_yo end,
       p_reemplaza_a);
  exception when unique_violation then
    raise exception 'Ya hay una constancia pendiente para el pago del %. Reemplázala o retírala primero.',
      to_char(p_fecha_pago, 'DD/MM/YYYY');
  end;

  v_prefijo := 'educacion/' || v_asg.persona_id::text || '/entregas/' || p_id::text || '/';

  for v_arch in select x from jsonb_array_elements(p_archivos) x loop
    v_orden := v_orden + 1;
    v_ruta := v_arch->>'ruta';

    if v_ruta is null or left(v_ruta, length(v_prefijo)) <> v_prefijo then
      raise exception 'El archivo «%» no está en la carpeta de este envío.', coalesce(v_arch->>'nombre', v_ruta);
    end if;

    select o.metadata into v_meta
      from storage.objects o
     where o.bucket_id = 'comprobantes' and o.name = v_ruta;
    if not found then
      raise exception 'El archivo «%» no terminó de subir. Vuelve a intentarlo.', coalesce(v_arch->>'nombre', v_ruta);
    end if;

    if coalesce(v_meta->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
      raise exception 'El archivo «%» no es PDF, JPG ni PNG.', coalesce(v_arch->>'nombre', v_ruta);
    end if;
    if nullif(v_meta->>'size', '')::bigint > 10 * 1024 * 1024 then
      raise exception '«%» pesa más de 10 MB, que es el máximo por archivo.', coalesce(v_arch->>'nombre', v_ruta);
    end if;

    insert into educacion_entrega_archivos (entrega_id, storage_path, nombre, tipo_mime, bytes, orden)
    values (p_id, v_ruta,
            coalesce(nullif(trim(coalesce(v_arch->>'nombre', '')), ''), regexp_replace(v_ruta, '^.*/', '')),
            v_meta->>'mimetype', nullif(v_meta->>'size', '')::bigint, v_orden);
  end loop;

  if v_estado = 'aprobada' then
    perform fn_educacion_avanzar_calendario(p_id);
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_asg.persona_id, 'educacion_entrega', null,
     to_char(p_fecha_pago, 'DD/MM/YYYY') || ' · ' || v_n || ' archivo(s) · ' || v_estado,
     v_yo,
     case when v_duena then 'Constancia enviada para revisión'
          else 'Constancia cargada y aprobada por Desarrollo Organizacional' end);

  return p_id;
end;
$$;

create or replace function fn_educacion_retirar_entrega(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  v_e  educacion_entregas%rowtype;
  v_persona uuid;
begin
  select * into v_e from educacion_entregas where id = p_id for update;
  if not found then raise exception 'Esa constancia no existe.'; end if;

  select a.persona_id into v_persona from asignaciones_educacion a where a.id = v_e.asignacion_id;

  if v_yo is null or v_e.enviada_por is distinct from v_yo then
    raise exception 'Solo quien envió la constancia puede retirarla.';
  end if;
  if v_e.estado <> 'pendiente' then
    raise exception 'Esta constancia ya está % y queda en el historial: no se retira.', v_e.estado;
  end if;

  update educacion_entregas set estado = 'retirada', retirada_at = now() where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_persona, 'educacion_entrega', 'pendiente', 'retirada', v_yo,
     'La integrante retiró su constancia antes de la revisión');
end;
$$;

create or replace function fn_educacion_avisar_fin(
  p_asignacion_id uuid,
  p_motivo        text,
  p_ultimo_pago   date default null
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
  if not exists (select 1 from asignaciones_educacion
                  where id = p_asignacion_id and persona_id = v_yo) then
    raise exception 'Solo la propia integrante avisa que deja de pagar su estudio.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Cuenta brevemente por qué ya no vas a pagar.';
  end if;

  begin
    insert into educacion_avisos_fin (asignacion_id, motivo, ultimo_pago, creado_por)
    values (p_asignacion_id, trim(p_motivo), p_ultimo_pago, v_yo)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya avisaste que dejas de pagar este estudio; Desarrollo Organizacional lo está viendo.';
  end;

  return v_id;
end;
$$;


-- ── I · Funciones de Desarrollo Organizacional ──────────────────────────────
create or replace function fn_educacion_resolver_entrega(
  p_id         uuid,
  p_aprobar    boolean,
  p_categoria  text default null,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_e       educacion_entregas%rowtype;
  v_persona uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional revisa constancias de educación.';
  end if;

  -- `for update`: si dos personas de DO revisan la misma a la vez, la segunda
  -- espera, lee el estado ya cambiado, y recibe el aviso de abajo.
  select * into v_e from educacion_entregas where id = p_id for update;
  if not found then raise exception 'Esa constancia no existe.'; end if;

  select a.persona_id into v_persona from asignaciones_educacion a where a.id = v_e.asignacion_id;

  if v_e.estado <> 'pendiente' then
    raise exception 'Esta constancia ya está %: alguien la revisó antes.', v_e.estado;
  end if;
  if v_persona = v_yo then
    raise exception 'No puedes revisar tu propia constancia: la revisa otra persona de Desarrollo Organizacional.';
  end if;

  if p_aprobar is true then
    update educacion_entregas
       set estado = 'aprobada', revisada_at = now(), revisada_por = v_yo
     where id = p_id;
    perform fn_educacion_avanzar_calendario(p_id);
  else
    if p_categoria is null or p_categoria not in
       ('ilegible', 'no_corresponde_al_pago', 'a_nombre_de_otra_persona',
        'faltan_paginas_o_datos', 'otra_institucion', 'otro') then
      raise exception 'Elige el motivo del rechazo.';
    end if;
    if p_comentario is null or length(trim(p_comentario)) < 3 then
      raise exception 'Escribe qué tiene que corregir: la integrante lo va a leer.';
    end if;
    update educacion_entregas
       set estado = 'rechazada', revisada_at = now(), revisada_por = v_yo,
           motivo_categoria = p_categoria, motivo_comentario = trim(p_comentario)
     where id = p_id;
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_persona, 'educacion_entrega', 'pendiente',
     case when p_aprobar then 'aprobada' else 'rechazada · ' || p_categoria end,
     v_yo,
     case when p_aprobar then 'Constancia aprobada' else trim(p_comentario) end);
end;
$$;

create or replace function fn_educacion_fijar_calendario(
  p_asignacion_id uuid,
  p_frecuencia    text,
  p_proxima       date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asg asignaciones_educacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional fija el calendario de pagos de un estudio.';
  end if;
  select * into v_asg from asignaciones_educacion where id = p_asignacion_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;
  if p_frecuencia is not null and p_frecuencia not in ('mensual', 'ciclo', 'unico', 'otra') then
    raise exception 'La frecuencia es mensual, por ciclo, pago único u otra.';
  end if;

  update asignaciones_educacion
     set frecuencia_pago = p_frecuencia, proxima_fecha_pago = p_proxima
   where familia_id = v_asg.familia_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_asg.persona_id, 'educacion_calendario',
     coalesce(v_asg.frecuencia_pago, '—') || ' · ' || coalesce(to_char(v_asg.proxima_fecha_pago, 'DD/MM/YYYY'), '—'),
     coalesce(p_frecuencia, '—') || ' · ' || coalesce(to_char(p_proxima, 'DD/MM/YYYY'), '—'),
     fn_persona_actual_id(), 'Calendario de pagos de la institución');
end;
$$;

create or replace function fn_educacion_atender_aviso_fin(p_id uuid, p_respuesta text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional atiende estos avisos.';
  end if;
  update educacion_avisos_fin
     set atendido_at = now(), atendido_por = fn_persona_actual_id(),
         respuesta = nullif(trim(coalesce(p_respuesta, '')), '')
   where id = p_id and atendido_at is null;
  if not found then
    raise exception 'Ese aviso no existe o ya fue atendido.';
  end if;
end;
$$;

create or replace function fn_educacion_configurar(
  p_texto_valido     text,
  p_dias_plazo       int,
  p_dias_aviso_colab int,
  p_dias_aviso_do    int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional cambia esta configuración.';
  end if;
  if p_dias_plazo is null or p_dias_plazo not between 0 and 20 then
    raise exception 'Los días antes del cierre van de 0 a 20.';
  end if;
  if p_dias_aviso_colab is null or p_dias_aviso_colab not between 0 and 30
     or p_dias_aviso_do is null or p_dias_aviso_do not between 0 and 30 then
    raise exception 'Los días de aviso van de 0 a 30.';
  end if;

  insert into configuracion (clave, valor, descripcion) values
    ('educacion_constancias_validas', to_jsonb(coalesce(trim(p_texto_valido), '')),
     'Texto que ve la integrante al subir una constancia de estudios (0450).'),
    ('educacion_dias_plazo_antes_cierre', to_jsonb(p_dias_plazo),
     'La constancia de un pago vence estos días antes del cierre del periodo (0450).'),
    ('educacion_dias_aviso_colaboradora', to_jsonb(p_dias_aviso_colab),
     'Desde cuántos días antes del plazo se le avisa a la integrante (0450).'),
    ('educacion_dias_aviso_do', to_jsonb(p_dias_aviso_do),
     'Cuántos días antes del pago a la institución lo ve DO en su Bandeja (0450).')
  on conflict (clave) do update set valor = excluded.valor;
end;
$$;


-- ── J · Las lecturas: una sola definición de «en qué está» ──────────────────
-- La pantalla de DO, el portal, la Bandeja y el contador del menú preguntan lo
-- mismo. Se contesta una vez, acá; tres copias de una cuenta discrepan.
--
-- Una fila por familia (la vigencia más reciente representa al estudio).
-- estado_constancia, en orden de prioridad:
--   pendiente_revision · hay una constancia esperando a DO
--   rechazada          · la última se rechazó y no hay otra aprobada para ese pago
--   sin_calendario     · nadie dijo cuándo paga
--   al_dia             · el próximo pago todavía no llega (o cae fuera de la vigencia)
--   vencida            · el pago llegó y su plazo ya pasó sin constancia
--   por_vencer         · el plazo cae dentro del aviso a la integrante
--   falta_enviar       · el pago llegó y todavía hay tiempo
drop function if exists fn_educacion_situacion();
create or replace function fn_educacion_situacion()
returns table (
  familia_id           uuid,
  asignacion_id        uuid,
  persona_id           uuid,
  persona              text,
  sede                 text,
  rango                text,
  institucion          text,
  beneficiario         text,
  beneficiario_nombre  text,
  monto                numeric,
  vigente_desde        date,
  vigente_hasta        date,
  vigencia             text,
  paga                 boolean,
  frecuencia_pago      text,
  proxima_fecha_pago   date,
  dias_para_pago       int,
  pago_proximo         boolean,
  estado_constancia    text,
  fecha_pago_constancia date,
  plazo                date,
  dias_para_plazo      int,
  entrega_id           uuid,
  entrega_estado       text,
  entrega_enviada_at   timestamptz,
  entrega_archivos     int,
  motivo_categoria     text,
  motivo_comentario    text,
  aprobadas            int,
  aviso_fin_id         uuid,
  aviso_fin_motivo     text
)
language sql
stable
security definer
set search_path = public
as $$
  with par as (
    select fn_hoy_lima() as hoy,
           fn_educacion_parametro('educacion_dias_aviso_colaboradora', 7) as av_col,
           fn_educacion_parametro('educacion_dias_aviso_do', 7)           as av_do
  ),
  fam as (
    select distinct on (a.familia_id)
           a.*, min(a.vigente_desde) over (partition by a.familia_id) as desde_familia
      from asignaciones_educacion a
     where fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id()
     order by a.familia_id, a.vigente_desde desc, a.id desc
  )
  select
    f.familia_id, f.id, f.persona_id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    f.institucion, f.beneficiario, f.beneficiario_nombre, f.monto,
    f.desde_familia, f.vigente_hasta,
    case when f.desde_familia > par.hoy          then 'futura'
         when f.vigente_hasta < par.hoy          then 'terminada'
         when f.vigente_hasta <= par.hoy + 30    then 'por_terminar'
         else 'vigente' end,
    (f.comprobante_url is not null and f.vigente_hasta >= par.hoy),
    f.frecuencia_pago, f.proxima_fecha_pago,
    (f.proxima_fecha_pago - par.hoy)::int,
    coalesce(f.proxima_fecha_pago between par.hoy and par.hoy + par.av_do
             and f.proxima_fecha_pago <= f.vigente_hasta, false),
    est.estado,
    est.fecha,
    fn_educacion_plazo(est.fecha),
    (fn_educacion_plazo(est.fecha) - par.hoy)::int,
    ul.id, ul.estado, ul.enviada_at, ul.archivos, ul.motivo_categoria, ul.motivo_comentario,
    apr.n,
    av.id, av.motivo
  from fam f
  cross join par
  join personas p on p.id = f.persona_id
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select x.rango from asignaciones_salario x
     where x.persona_id = f.persona_id and x.vigente_hasta is null
     order by x.vigente_desde desc, x.id desc limit 1
  ) sal on true
  left join lateral (
    select e.id, e.fecha_pago
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado = 'pendiente'
     order by e.enviada_at desc, e.id desc limit 1
  ) pe on true
  left join lateral (
    select e.id, e.estado, e.fecha_pago, e.enviada_at, e.motivo_categoria, e.motivo_comentario,
           (select count(*)::int from educacion_entrega_archivos ar where ar.entrega_id = e.id) as archivos
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado <> 'retirada'
     order by e.fecha_pago desc, e.enviada_at desc, e.id desc limit 1
  ) ul on true
  left join lateral (
    select count(*)::int as n
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado = 'aprobada'
  ) apr on true
  left join lateral (
    select v.id, v.motivo
      from educacion_avisos_fin v join asignaciones_educacion x on x.id = v.asignacion_id
     where x.familia_id = f.familia_id and v.atendido_at is null
     order by v.creado_at desc, v.id desc limit 1
  ) av on true
  cross join lateral (
    select
      case
        when pe.id is not null                                   then 'pendiente_revision'
        when ul.estado = 'rechazada'                             then 'rechazada'
        when f.proxima_fecha_pago is null                        then 'sin_calendario'
        when f.proxima_fecha_pago > par.hoy
          or f.proxima_fecha_pago > f.vigente_hasta              then 'al_dia'
        when fn_educacion_plazo(f.proxima_fecha_pago) < par.hoy  then 'vencida'
        when fn_educacion_plazo(f.proxima_fecha_pago) - par.hoy <= par.av_col then 'por_vencer'
        else 'falta_enviar'
      end as estado,
      case
        when pe.id is not null        then pe.fecha_pago
        when ul.estado = 'rechazada'  then ul.fecha_pago
        else f.proxima_fecha_pago
      end as fecha
  ) est
  order by p.apellidos, p.nombres, f.institucion, f.familia_id;
$$;

-- El historial de un estudio. El nombre de quien revisó solo se le da a DO: la
-- integrante lee «Desarrollo Organizacional» (decisión de Felipe, 2026-09-15).
drop function if exists fn_educacion_entregas(uuid);
create or replace function fn_educacion_entregas(p_familia_id uuid)
returns table (
  id                 uuid,
  asignacion_id      uuid,
  fecha_pago         date,
  tipo               text,
  proxima_fecha_pago date,
  nota               text,
  estado             text,
  origen             text,
  enviada_at         timestamptz,
  enviada_por        text,
  revisada_at        timestamptz,
  revisada_por       text,
  retirada_at        timestamptz,
  motivo_categoria   text,
  motivo_comentario  text,
  reemplaza_a        uuid,
  archivos           jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.asignacion_id, e.fecha_pago, e.tipo, e.proxima_fecha_pago, e.nota,
         e.estado, e.origen, e.enviada_at,
         case when fn_es_admin_o_lider() is true then env.nombres || ' ' || env.apellidos end,
         e.revisada_at,
         case when fn_es_admin_o_lider() is true then rev.nombres || ' ' || rev.apellidos end,
         e.retirada_at, e.motivo_categoria, e.motivo_comentario, e.reemplaza_a,
         coalesce((select jsonb_agg(jsonb_build_object(
                     'id', ar.id, 'ruta', ar.storage_path, 'nombre', ar.nombre,
                     'tipo_mime', ar.tipo_mime, 'bytes', ar.bytes) order by ar.orden, ar.id)
                     from educacion_entrega_archivos ar where ar.entrega_id = e.id), '[]'::jsonb)
    from educacion_entregas e
    join asignaciones_educacion a on a.id = e.asignacion_id
    left join personas env on env.id = e.enviada_por
    left join personas rev on rev.id = e.revisada_por
   where a.familia_id = p_familia_id
     and (fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id())
   order by e.fecha_pago desc, e.enviada_at desc, e.id desc;
$$;

-- Una entrega = un pendiente. Para la zona «Por aprobar» de la Bandeja.
drop function if exists fn_educacion_entregas_pendientes();
create or replace function fn_educacion_entregas_pendientes()
returns table (
  id          uuid,
  familia_id  uuid,
  persona_id  uuid,
  persona     text,
  sede        text,
  institucion text,
  fecha_pago  date,
  tipo        text,
  enviada_at  timestamptz,
  archivos    int,
  es_reenvio  boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, a.familia_id, a.persona_id, p.nombres || ' ' || p.apellidos,
         coalesce(s.codigo, '?'), a.institucion, e.fecha_pago, e.tipo, e.enviada_at,
         (select count(*)::int from educacion_entrega_archivos ar where ar.entrega_id = e.id),
         e.reemplaza_a is not null
    from educacion_entregas e
    join asignaciones_educacion a on a.id = e.asignacion_id
    join personas p on p.id = a.persona_id
    left join sedes s on s.id = p.sede_base_id
   where e.estado = 'pendiente'
     and fn_es_admin_o_lider() is true
   order by e.enviada_at, e.id;
$$;

drop function if exists fn_educacion_avisos_fin_pendientes();
create or replace function fn_educacion_avisos_fin_pendientes()
returns table (
  id            uuid,
  asignacion_id uuid,
  familia_id    uuid,
  persona_id    uuid,
  persona       text,
  sede          text,
  institucion   text,
  motivo        text,
  ultimo_pago   date,
  creado_at     timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select v.id, v.asignacion_id, a.familia_id, a.persona_id, p.nombres || ' ' || p.apellidos,
         coalesce(s.codigo, '?'), a.institucion, v.motivo, v.ultimo_pago, v.creado_at
    from educacion_avisos_fin v
    join asignaciones_educacion a on a.id = v.asignacion_id
    join personas p on p.id = a.persona_id
    left join sedes s on s.id = p.sede_base_id
   where v.atendido_at is null
     and fn_es_admin_o_lider() is true
   order by v.creado_at, v.id;
$$;

-- ⇩⇩⇩ CAMBIO 0450 ⇩⇩⇩ El contador del menú cuenta lo que le toca hacer a DO, y
-- nada más: constancias por revisar, pagos cuyo plazo venció sin constancia,
-- estudios vigentes sin calendario, y avisos de «ya no voy a pagar».
--
-- Deja de contar «vigencia por terminar»: era la mitad del 17 del menú y casi
-- siempre una renovación normal («vence en 0 días» el día que renueva). Sigue
-- visible en la pantalla y en «Para saber» de la Bandeja, no en el número rojo.
create or replace function fn_educacion_por_atender()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case when fn_es_admin_o_lider() is not true then 0 else
    (select count(*)::int from educacion_entregas where estado = 'pendiente')
    + (select count(*)::int from fn_educacion_situacion() s
        where s.estado_constancia = 'vencida'
           or (s.estado_constancia = 'sin_calendario' and s.vigencia in ('vigente', 'por_terminar')))
    + (select count(*)::int from educacion_avisos_fin where atendido_at is null)
  end;
$$;

-- ⇩⇩⇩ CAMBIO 0450 ⇩⇩⇩ Quitar un comprobante se niega. Borrar la fila vieja ya no
-- apaga nada (la verdad está en educacion_entregas), y un papel aprobado es el
-- sustento de lo que ya se pagó.
create or replace function fn_educacion_quitar_comprobante(p_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional quita comprobantes de educación.';
  end if;
  raise exception
    'Desde la 0450 un comprobante aprobado no se quita: queda en el historial como sustento '
    'de lo que ya se pagó. Si no correspondía, registra la constancia correcta; si la '
    'asignación no debía pagarse, ciérrala.';
end;
$$;


grant execute on function fn_educacion_plazo(date)                                          to authenticated;
grant execute on function fn_educacion_enviar_entrega(uuid,uuid,date,text,date,jsonb,text,uuid) to authenticated;
grant execute on function fn_educacion_retirar_entrega(uuid)                                 to authenticated;
grant execute on function fn_educacion_avisar_fin(uuid,text,date)                            to authenticated;
grant execute on function fn_educacion_resolver_entrega(uuid,boolean,text,text)              to authenticated;
grant execute on function fn_educacion_fijar_calendario(uuid,text,date)                      to authenticated;
grant execute on function fn_educacion_atender_aviso_fin(uuid,text)                          to authenticated;
grant execute on function fn_educacion_configurar(text,int,int,int)                          to authenticated;
grant execute on function fn_educacion_situacion()                                           to authenticated;
grant execute on function fn_educacion_entregas(uuid)                                        to authenticated;
grant execute on function fn_educacion_entregas_pendientes()                                 to authenticated;
grant execute on function fn_educacion_avisos_fin_pendientes()                               to authenticated;
revoke execute on function fn_educacion_refrescar_espejo(uuid) from public, anon, authenticated;
revoke execute on function fn_educacion_parametro(text,int)    from public, anon;


-- ── K · Registrar y corregir, con la familia ────────────────────────────────
-- Cuerpo de la 0327 (md5 de partida arriba) con tres cambios marcados:
--   1. La vigencia nueva de una corrección hereda familia y calendario.
--   2. Deja de COPIAR los papeles: la familia ya los comparte. Copiarlos ahora
--      duplicaría entregas aprobadas en el historial.
--   3. Si la fila vieja se borra (nunca llegó a un periodo pagado), sus
--      entregas y avisos se mudan a la nueva antes de confirmar.
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


-- ── L · El almacén: la integrante sube lo suyo, y lo revisado se congela ────
-- La ruta de una entrega es educacion/<persona>/entregas/<entrega>/<archivo>.
-- Se puede escribir ahí solo mientras esa entrega no exista: en cuanto se envía,
-- sus archivos quedan como se mandaron.
create or replace function fn_educacion_puede_subir_entrega(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_persona text := split_part(p_path, '/', 2);
  v_entrega text := split_part(p_path, '/', 4);
begin
  if split_part(p_path, '/', 1) <> 'educacion' or split_part(p_path, '/', 3) <> 'entregas' then
    return false;
  end if;
  if v_persona !~ '^[0-9a-fA-F-]{36}$' or v_entrega !~ '^[0-9a-fA-F-]{36}$' then
    return false;
  end if;
  if v_persona::uuid is distinct from fn_persona_actual_id() then
    return false;
  end if;
  if not exists (select 1 from asignaciones_educacion where persona_id = v_persona::uuid) then
    return false;
  end if;
  return not exists (select 1 from educacion_entregas where id = v_entrega::uuid);
end;
$$;

create or replace function fn_educacion_ruta_congelada(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from educacion_entrega_archivos where storage_path = p_path);
$$;

grant execute on function fn_educacion_puede_subir_entrega(text) to authenticated;
grant execute on function fn_educacion_ruta_congelada(text)      to authenticated;

drop policy if exists comprobantes_insert_entrega_propia on storage.objects;
create policy comprobantes_insert_entrega_propia on storage.objects
  for insert to authenticated
  with check (bucket_id = 'comprobantes' and fn_educacion_puede_subir_entrega(name) is true);

-- `x-upsert` de la subida es un UPDATE cuando se reintenta el mismo archivo.
drop policy if exists comprobantes_update_entrega_propia on storage.objects;
create policy comprobantes_update_entrega_propia on storage.objects
  for update to authenticated
  using      (bucket_id = 'comprobantes' and fn_educacion_puede_subir_entrega(name) is true)
  with check (bucket_id = 'comprobantes' and fn_educacion_puede_subir_entrega(name) is true);

-- Las de DO (0136 y 0172), con una condición más: tampoco DO sobrescribe ni
-- borra el archivo de una constancia enviada.
drop policy if exists comprobantes_update on storage.objects;
create policy comprobantes_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
    and fn_educacion_ruta_congelada(name) is not true
  )
  with check (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
    and fn_educacion_ruta_congelada(name) is not true
  );

drop policy if exists comprobantes_delete on storage.objects;
create policy comprobantes_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
    and fn_educacion_ruta_congelada(name) is not true
  );


-- ── M · La Bandeja aprende dos tipos ────────────────────────────────────────
alter table bandeja_vistos drop constraint if exists bandeja_vistos_tipo_item_check;
alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check check (tipo_item in (
  'revision', 'revision_movilidad', 'revision_contrato',
  'solicitud_vacacion', 'solicitud_perfil',
  'entrega_educacion', 'aviso_fin_educacion'
));

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
  -- ⇩ CAMBIO 0450 ⇩ entrega_educacion y aviso_fin_educacion.
  if p_tipo_item not in ('revision', 'revision_movilidad', 'revision_contrato',
                          'solicitud_vacacion', 'solicitud_perfil',
                          'entrega_educacion', 'aviso_fin_educacion') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$$;


-- ── N · Los valores de partida ──────────────────────────────────────────────
-- `do nothing`: repegar no pisa lo que DO ya haya cambiado.
insert into configuracion (clave, valor, descripcion) values
  ('educacion_constancias_validas',
   to_jsonb('Sirve cualquier documento de la institución que muestre tu nombre (o el de tu hijo o hija), el concepto y el monto pagado: boleta o factura de la pensión o cuota, constancia de matrícula, comprobante de pago del ciclo o del curso. Si tiene varias páginas, súbelas todas en el mismo envío. Desarrollo Organizacional revisa cada una.'::text),
   'Texto que ve la integrante al subir una constancia de estudios (0450).'),
  ('educacion_dias_plazo_antes_cierre', to_jsonb(5),
   'La constancia de un pago vence estos días antes del cierre del periodo (0450).'),
  ('educacion_dias_aviso_colaboradora', to_jsonb(7),
   'Desde cuántos días antes del plazo se le avisa a la integrante (0450).'),
  ('educacion_dias_aviso_do', to_jsonb(7),
   'Cuántos días antes del pago a la institución lo ve DO en su Bandeja (0450).')
on conflict (clave) do nothing;


-- ── O · La promesa, comprobada: nadie cambió de «paga» a «no paga» ──────────
do $comprobar$
declare
  v_n     int;
  v_lista text;
begin
  select count(*), string_agg(p.nombres || ' ' || p.apellidos || ' (' || a.institucion || ')', ', ')
    into v_n, v_lista
    from asignaciones_educacion a
    join _educacion_paga_antes_0450 b on b.id = a.id
    join personas p on p.id = a.persona_id
   where (a.comprobante_url is not null) is distinct from b.con_papel;

  if v_n > 0 then
    raise exception
      '0450 se detiene: % asignación(es) cambiarían entre «paga» y «no paga»: %. No se aplicó nada.',
      v_n, v_lista;
  end if;
end $comprobar$;


insert into migraciones_aplicadas (numero, nombre)
values (450, 'la_constancia_de_estudios_se_entrega_y_se_revisa')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0450 · % entregas (% migradas) · la planilla no cambió para nadie.',
    (select count(*) from educacion_entregas),
    (select count(*) from educacion_entregas where origen = 'migrada');
end $fin$;
