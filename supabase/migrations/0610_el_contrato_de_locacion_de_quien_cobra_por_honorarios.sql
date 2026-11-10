-- ============================================================================
-- 0610_el_contrato_de_locacion_de_quien_cobra_por_honorarios.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el contrato de locación de servicios de quien cobra por recibo por
--   honorarios (RxH) viva DENTRO de Dynamic, y que Desarrollo Organizacional
--   pueda responder sin salir del sistema: ¿a quién le falta su contrato, a
--   quién se le vence pronto y a quién ya se le venció?
--
--   Hasta hoy Contratos dejaba fuera a los RxH a propósito (el generador solo
--   hace contratos de trabajo y convenios de prácticas), y con eso nada avisaba
--   si un locador trabajaba sin contrato escrito o con uno vencido.
--
-- QUÉ ASUME
--   · `personas.tipo_vinculo = 'rxh'` es quien cobra por honorarios (0085).
--   · `fn_es_admin_o_lider()` es DO y dirección (0078). La líder de equipo no
--     tiene la pantalla de Contratos y tampoco ve esto.
--   · `fn_hoy_lima()` es «hoy» (0091).
--   · Que el navegador sube el escaneo al bucket `contratos-locacion` ANTES de
--     llamar a `fn_locacion_registrar`, y que Storage guarda su peso y su tipo
--     en `storage.objects.metadata` (molde de la 0482 y la 0503).
--
-- ── POR QUÉ UNA TABLA PROPIA Y NO `contratos_generados` ─────────────────────
--
--   `contratos_generados` (0272) es la del contrato de TRABAJO, y lo dice en
--   sus columnas: cargo, remuneración mensual, horas semanales y el texto que
--   imprimió el generador, las cuatro obligatorias. Además, al registrar el
--   escaneo firmado, `fn_contrato_registrar` copia la fecha de fin a
--   `personas.fecha_fin_contrato`, y de esa fecha cuelgan la alerta del art. 77
--   del D.S. 003-97-TR (trabajar pasado el plazo vuelve indefinido un contrato
--   de trabajo) y el corte de las faltas (0396).
--
--   Las tres cosas son laborales. Escritas sobre un locador, el propio sistema
--   dejaría constancia de cargo, jornada y remuneración, que son justo los
--   indicios con que un juez declara que una locación era en realidad una
--   relación de trabajo (primacía de la realidad). Por eso esta tabla no tiene
--   ninguna de esas columnas y NO escribe en `personas`.
--
--   Se descartó el Archivo de la empresa (0503): guarda papeles con
--   vencimiento, pero no sabe de personas, así que no podría decir a quién le
--   falta contrato, que es la pregunta.
--
-- ── ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles) ──────────────
--
--   · un contrato sin escaneo ................... not null + la función exige
--                                                  que el archivo exista en
--                                                  Storage
--   · un escaneo en dos contratos vivos ......... índice único parcial
--   · una locación vigente para alguien de
--     planilla (dos vínculos a la vez) .......... la función, al registrar.
--     Y si la persona pasa a planilla DESPUÉS
--     (eso se hace en Equipo y esta migración
--     no lo toca), el tablero la muestra como
--     `abierta_sin_rxh` hasta que DO termine
--     su locación ............................... el tablero
--   · terminar antes de la víspera de empezar,
--     o después de su fin ........................ check + la función
--   · firmado en el futuro ...................... la función
--   · un contrato sin servicio .................. check
--   · uno que termina antes de empezar .......... check
--   · una ruta con nombres o DNI ................ check de forma `<uuid>.<ext>`
--   · terminado y anulado a la vez .............. check
--   · un término o una anulación a medias ....... check (fecha, motivo y autor
--                                                  van juntos o ninguno)
--   · un contrato editado o borrado ............. trigger: después de crearse
--                                                  solo se escribe su término
--                                                  o su anulación, una vez y
--                                                  desde el sistema
--   · alguien fuera de DO leyéndolo ............. RLS + política de Storage
--   · pisar o borrar un escaneo registrado ...... la política de update y
--                                                  delete de Storage exige que
--                                                  ningún contrato lo use
--
-- ── CONCURRENCIA ─────────────────────────────────────────────────────────────
--
--   Dos personas de DO registran el MISMO escaneo a la vez: el índice único
--   parcial deja entrar a una y la otra recibe el error. Dos escaneos distintos
--   de la misma persona a la vez entran los dos, y está bien: puede tener dos
--   contratos.
--
-- ── NÚMEROS ─────────────────────────────────────────────────────────────────
--
--   Hoy, un puñado de personas por honorarios (los hallazgos de planilla citan
--   dos). Con una renovación al año, del orden de 30 filas en tres años.
--   Ninguna consulta necesita más índice que el de la persona.
--
-- ── SE ROMPE SI ─────────────────────────────────────────────────────────────
--
--   Una misma persona presta DOS servicios distintos a la vez, con dos
--   contratos. El tablero muestra uno por persona (el que llega más lejos) y
--   el otro solo se ve en su historial: si el que se muestra vence después,
--   el que vence antes no avisa.
--
-- ── CÓMO SE PEGA — EN DOS PARTES, UNA POR UNA ───────────────────────────────
--
--   Toca dos tablas en uso: `personas` (la llave foránea toma un candado sobre
--   ella) y `storage.objects` (crear una política toma uno exclusivo). Pegadas
--   juntas, el SQL Editor las retiene a las dos hasta el final, y es la forma
--   del deadlock de la 0591. Así que cada parte toca una sola:
--     PARTE 1 · la tabla y sus funciones   (solo `personas`)
--     PARTE 2 · el almacén y el registro   (solo `storage.objects`)
--   Cada una empieza con `set local lock_timeout = '3s'`: si no consigue el
--   candado en 3 segundos falla en vez de quedarse en cola, y se repega. La
--   parte 2 se niega a correr si falta la 1. Las dos son idempotentes. Entera,
--   en un solo bloque, sigue valiendo en una base sin tráfico (las pruebas).
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_locaciones_tablero(), fn_locaciones_listar(uuid),
--     fn_locacion_registrar(uuid, text, date, date, date, text, text),
--     fn_locacion_anular(uuid, text), fn_locacion_terminar(uuid, date, text),
--     fn_locacion_libre(text);
--   drop policy contratos_locacion_insert/select/update/delete on storage.objects;
--   drop table contratos_locacion;   -- se lleva su trigger y sus índices
--   drop function if exists fn_contratos_locacion_inmutables();
--   delete from storage.objects where bucket_id = 'contratos-locacion';  -- vaciar antes
--   delete from storage.buckets where id = 'contratos-locacion';
--   Nada de planilla, asistencia ni pago lee esta tabla: revertir solo quita
--   la pestaña. Ojo: borrarla destruye el registro de quién subió cada
--   contrato y cuándo.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- ═══ PARTE 1 · La tabla y sus funciones (solo `personas`, por la llave) ═════
-- Se pega primero y sola.

set local lock_timeout = '3s';


-- ── 1 · La tabla ─────────────────────────────────────────────────────────────
create table if not exists contratos_locacion (
  id               uuid primary key default gen_random_uuid(),
  persona_id       uuid not null references personas(id),
  -- El servicio que se contrata, con las palabras del contrato: «Diseño de la
  -- colección de verano», «Asesoría contable». Es lo único que describe el
  -- vínculo: no hay cargo, jornada ni remuneración (ver arriba por qué).
  servicio         text not null check (char_length(btrim(servicio)) between 3 and 300),
  fecha_inicio     date not null,
  -- Obligatoria: el Código Civil le pone plazo máximo a la locación (art.
  -- 1768), y sin fin no hay forma de avisar que se venció.
  fecha_fin        date not null,
  fecha_firma      date not null,
  -- `<uuid>.<ext>` en el bucket `contratos-locacion`, y nada más: ni nombres
  -- ni DNI en la ruta.
  storage_path     text not null check (storage_path ~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$'),
  -- El nombre con que se subió, para reconocerlo al abrirlo.
  nombre_archivo   text not null check (char_length(btrim(nombre_archivo)) between 1 and 255),
  mime             text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif')),
  bytes            bigint not null check (bytes > 0),
  registrado_por   uuid not null references personas(id),
  registrado_at    timestamptz not null default now(),
  -- Terminó antes de su fecha: la persona pasó a planilla, o se resolvió.
  terminado_el     date,
  terminado_motivo text,
  terminado_por    uuid references personas(id),
  terminado_at     timestamptz,
  -- Se registró por error (otra persona, un dato mal escrito).
  anulado_at       timestamptz,
  anulado_por      uuid references personas(id),
  anulado_motivo   text,
  constraint locacion_fin_no_antes_del_inicio check (fecha_fin >= fecha_inicio),
  -- Se termina, como pronto, la víspera de empezar (nunca entró en vigor) y,
  -- como tarde, en su fecha de fin.
  constraint locacion_termina_dentro_del_plazo check (
    terminado_el is null or (terminado_el <= fecha_fin and terminado_el >= fecha_inicio - 1)
  ),
  constraint locacion_termino_completo check (
    (terminado_el is null and terminado_motivo is null and terminado_por is null and terminado_at is null)
    or (terminado_el is not null and terminado_por is not null and terminado_at is not null
        and char_length(btrim(terminado_motivo)) >= 5)
  ),
  constraint locacion_anulacion_completa check (
    (anulado_at is null and anulado_por is null and anulado_motivo is null)
    or (anulado_at is not null and anulado_por is not null and char_length(btrim(anulado_motivo)) >= 5)
  ),
  -- Un contrato terminado existió; uno anulado no. No pueden ser las dos cosas.
  constraint locacion_terminado_o_anulado check (terminado_el is null or anulado_at is null)
);

comment on table contratos_locacion is
  'Contrato de locación de servicios de quien cobra por recibo por honorarios (RxH). Solo DO. Ninguna fila se edita ni se borra: después de creada solo se escribe su término o su anulación, por las funciones de la 0610. No escribe en personas.fecha_fin_contrato a propósito.';

create index if not exists idx_contratos_locacion_persona on contratos_locacion (persona_id);


-- ── 2 · Lo que no se edita ni se borra ───────────────────────────────────────
-- Molde de campo sensible (0261, 0295, 0342, 0503): un cliente por PostgREST
-- conecta como `authenticated`; una función `security definer` de esta
-- migración corre como `postgres`.
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
  if (new.id, new.persona_id, new.servicio, new.fecha_inicio, new.fecha_fin, new.fecha_firma,
      new.storage_path, new.nombre_archivo, new.mime, new.bytes, new.registrado_por, new.registrado_at)
     is distinct from
     (old.id, old.persona_id, old.servicio, old.fecha_inicio, old.fecha_fin, old.fecha_firma,
      old.storage_path, old.nombre_archivo, old.mime, old.bytes, old.registrado_por, old.registrado_at) then
    raise exception 'Un contrato de locación no se edita: si tiene un dato mal, se anula y se registra de nuevo.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists contratos_locacion_inmutables on contratos_locacion;
create trigger contratos_locacion_inmutables
  before update or delete on contratos_locacion
  for each row execute function fn_contratos_locacion_inmutables();


-- ── 3 · Permisos y RLS ───────────────────────────────────────────────────────
-- Leer: solo DO. Escribir: nadie directo. Se quita lo que Supabase concede por
-- defecto (incluye escribir y `truncate`, que no pasa por RLS).
alter table contratos_locacion enable row level security;

drop policy if exists contratos_locacion_select_do on contratos_locacion;
create policy contratos_locacion_select_do on contratos_locacion
  for select to authenticated using (fn_es_admin_o_lider() is true);

revoke all on contratos_locacion from anon, authenticated, public;
grant select on contratos_locacion to authenticated;


-- ── 3b · El escaneo de cada contrato ─────────────────────────────────────────
-- Un archivo está «libre» si ningún contrato lo usa: solo entonces se puede
-- pisar o borrar (limpiar un huérfano). Es lo que vuelve inmutable lo ya
-- registrado, también del lado del archivo.
create or replace function fn_locacion_libre(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select not exists (select 1 from contratos_locacion c where c.storage_path = p_path);
$fn$;

grant execute on function fn_locacion_libre(text) to authenticated;
revoke execute on function fn_locacion_libre(text) from public, anon;

-- Un mismo escaneo no sostiene dos contratos vivos: sería registrar dos veces
-- el mismo papel. Uno anulado sí deja su archivo libre para registrarlo bien.
create unique index if not exists idx_contratos_locacion_ruta_viva
  on contratos_locacion (storage_path) where anulado_at is null;


-- ── 4 · El tablero: una fila por cada persona activa por honorarios ─────────
-- Parte de las PERSONAS y no de los contratos, igual que `fn_contratos_tablero`
-- (0287): quien no tiene ninguno tiene que verse.
--
-- Contrato: devuelve a cada RxH activo (sin las cuentas de servicio, 0491) con
-- el contrato que llega más lejos y el estado de su cobertura, y ADEMÁS a quien
-- ya no es RxH activo pero conserva una locación abierta. Un término anticipado
-- cuenta como el fin real. Los anulados no cuentan. Quien no es DO recibe la
-- lista vacía, como en el tablero hermano.
--
--   abierta_sin_rxh  pasó a planilla (o cesó) y su locación sigue abierta: dos
--                    vínculos a la vez hasta que alguien la termine
--   vencido ........ su último contrato ya terminó y sigue activa por honorarios
--   sin_contrato ... no hay ninguno registrado
--   por_vencer ..... cubierta hoy y hasta dentro de 60 días o menos (la misma
--                    ventana de Contratos y de Equipo)
--   por_empezar .... hoy no está cubierta, pero hay un contrato que empieza después
--   vigente ........ cubierta hoy y por más de 60 días
--
-- Un contrato ya firmado que empieza cuando termina el actual cuenta como
-- cobertura: «vence pronto» no salta si la renovación ya está registrada.
--
-- `vinculo_actual` dice qué es hoy la persona: `rxh`, otro `tipo_vinculo`, o
-- `cesada`. Solo cambia algo en las filas `abierta_sin_rxh`.
--
-- `drop` + `create` y no `create or replace`: Postgres no deja cambiar las
-- columnas de una función que devuelve TABLE (mismo camino que la 0161).
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
  estado          text
)
language sql stable security definer set search_path = public
as $fn$
  with vivos as (
    select c.*, coalesce(c.terminado_el, c.fecha_fin) as fin_real
      from contratos_locacion c
     where c.anulado_at is null
       -- Uno terminado antes de empezar nunca estuvo en vigor: no cubre nada.
       and coalesce(c.terminado_el, c.fecha_fin) >= c.fecha_inicio
  ),
  ultimo as (
    -- El que llega más lejos. `registrado_at` y `id` como desempate: dos
    -- registrados en la misma transacción empatan en `now()` (0312, 0389).
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
  -- Quien ya no es RxH activo y tiene una locación sin terminar que todavía
  -- no llega a su fecha de fin.
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
           case
             when not (p.estado = 'activo' and p.tipo_vinculo = 'rxh') then 'abierta_sin_rxh'
             when u.id is null                         then 'sin_contrato'
             when u.fin_real < fn_hoy_lima()           then 'vencido'
             when not r.cubierta_hoy                   then 'por_empezar'
             when u.fin_real - fn_hoy_lima() <= 60     then 'por_vencer'
             else 'vigente'
           end as estado
      from personas p
      left join sedes s   on s.id = p.sede_base_id
      left join ultimo u  on u.persona_id = p.id
      left join resumen r on r.persona_id = p.id
     where not p.cuenta_de_servicio
       and ((p.estado = 'activo' and p.tipo_vinculo = 'rxh')
            or p.id in (select a.persona_id from abiertas a))
       and fn_es_admin_o_lider() is true
  )
  select f.persona_id, f.persona, f.sede, f.vinculo_actual, f.contrato_id, f.servicio, f.fecha_inicio,
         f.fin_real, (f.fin_real - fn_hoy_lima())::int, f.n, f.estado
    from filas f
   -- Lo que urge primero: dos vínculos a la vez, y quien trabaja sin contrato vigente.
   order by case f.estado
              when 'abierta_sin_rxh' then 0
              when 'vencido'         then 1
              when 'sin_contrato'    then 2
              when 'por_vencer'      then 3
              when 'por_empezar'     then 4
              else 5
            end,
            f.fin_real nulls last, f.apellidos, f.persona_id;
$fn$;


-- ── 5 · El historial de cada persona ─────────────────────────────────────────
-- Todos sus contratos, anulados incluidos, con el estado ya resuelto: la regla
-- de qué es «en curso» vive aquí y en ningún otro sitio. Con `p_persona_id`
-- nulo devuelve los de todos.
--
--   anulado ...... se registró por error; no cuenta
--   terminado .... terminó antes de su fecha (`terminado_el`)
--   por_empezar .. empieza después de hoy
--   concluido .... llegó a su fecha de fin
--   en_curso ..... lo demás
create or replace function fn_locaciones_listar(p_persona_id uuid default null)
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
  anulado_por_nombre   text
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve los contratos de locación.';
  end if;

  return query
  select c.id, c.persona_id, btrim(p.nombres || ' ' || p.apellidos), c.servicio,
         c.fecha_inicio, c.fecha_fin, c.fecha_firma,
         c.storage_path, c.nombre_archivo, c.mime, c.bytes,
         case when c.anulado_at is not null       then 'anulado'
              when c.terminado_el is not null     then 'terminado'
              when c.fecha_inicio > fn_hoy_lima() then 'por_empezar'
              when c.fecha_fin < fn_hoy_lima()    then 'concluido'
              else 'en_curso' end,
         btrim(pr.nombres || ' ' || pr.apellidos), c.registrado_at,
         c.terminado_el, c.terminado_motivo, btrim(pt.nombres || ' ' || pt.apellidos),
         c.anulado_at, c.anulado_motivo, btrim(pa.nombres || ' ' || pa.apellidos)
    from contratos_locacion c
    join personas p       on p.id  = c.persona_id
    left join personas pr on pr.id = c.registrado_por
    left join personas pt on pt.id = c.terminado_por
    left join personas pa on pa.id = c.anulado_por
   where p_persona_id is null or c.persona_id = p_persona_id
   -- Los que valen primero, del más reciente al más viejo; los anulados al
   -- final, porque no cuentan. `id` como ancla del empate (0312, 0389).
   order by (c.anulado_at is not null), c.fecha_inicio desc, c.registrado_at desc, c.id desc;
end;
$fn$;


-- ── 5b · Registrar un contrato firmado ───────────────────────────────────────
-- Contrato:
--   p_storage_path  `<uuid>.<ext>` ya subido al bucket `contratos-locacion`.
--                   EL ARCHIVO VA PRIMERO (molde de la 0503): si Storage no
--                   responde, la subida falla entera y no queda ninguna fila;
--                   un archivo subido y nunca registrado es inofensivo, y la
--                   política de delete permite limpiarlo porque nadie lo usa.
--   Devuelve el id del contrato. Todo en una transacción.
--
-- A quién: a quien cobra hoy por honorarios. A una persona de planilla solo
-- se le puede archivar una locación que YA terminó (la que tuvo antes de
-- pasar a planilla): registrarle una vigente dejaría a la misma persona con un
-- vínculo civil y uno laboral a la vez. Una persona que ya cesó sí puede
-- recibir el suyo: el papel de quien ya no está es justo el que hay que poder
-- archivar (lección de la 0287).
--
-- Se degrada así: sin Storage, DO no puede registrar ni abrir contratos; el
-- tablero sigue viéndose porque vive en Postgres. No se pierde ningún dato.
create or replace function fn_locacion_registrar(
  p_persona_id     uuid,
  p_servicio       text,
  p_fecha_inicio   date,
  p_fecha_fin      date,
  p_fecha_firma    date,
  p_storage_path   text,
  p_nombre_archivo text
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_p     personas%rowtype;
  v_obj   storage.objects%rowtype;
  v_id    uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra contratos de locación.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select * into v_p from personas p where p.id = p_persona_id;
  if not found or v_p.cuenta_de_servicio then
    raise exception 'Esa persona no existe.';
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
  if p_fecha_firma is null then
    raise exception 'Falta la fecha de firma.';
  end if;
  if p_fecha_firma > fn_hoy_lima() then
    raise exception 'La fecha de firma no puede ser posterior a hoy.';
  end if;
  if v_p.tipo_vinculo <> 'rxh' and p_fecha_fin >= fn_hoy_lima() then
    raise exception 'Esa persona no cobra por honorarios: solo se le puede archivar una locación que ya terminó.';
  end if;

  if p_nombre_archivo is null or btrim(p_nombre_archivo) = '' then
    raise exception 'Falta el nombre del archivo.';
  end if;
  if p_storage_path is null or p_storage_path !~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$' then
    raise exception 'La ruta del archivo no tiene la forma esperada.';
  end if;
  -- El peso y el tipo salen de Storage, no de lo que diga el navegador.
  select * into v_obj from storage.objects o
   where o.bucket_id = 'contratos-locacion' and o.name = p_storage_path;
  if not found then
    raise exception 'El archivo no llegó al almacén. Vuelve a subirlo.';
  end if;
  if exists (select 1 from contratos_locacion c where c.storage_path = p_storage_path and c.anulado_at is null) then
    raise exception 'Ese archivo ya está registrado en otro contrato.';
  end if;

  insert into contratos_locacion
    (persona_id, servicio, fecha_inicio, fecha_fin, fecha_firma,
     storage_path, nombre_archivo, mime, bytes, registrado_por)
  values
    (p_persona_id, btrim(p_servicio), p_fecha_inicio, p_fecha_fin, p_fecha_firma,
     p_storage_path, btrim(p_nombre_archivo),
     v_obj.metadata->>'mimetype', (v_obj.metadata->>'size')::bigint, v_quien)
  returning id into v_id;

  return v_id;
end;
$fn$;


-- ── 5c · Anular un registro equivocado ───────────────────────────────────────
-- Para lo que se registró mal: otra persona, una fecha, el servicio mal
-- escrito. El contrato anulado no cuenta para nada, pero se queda en el
-- historial con su motivo, y su escaneo también. Uno ya terminado no se anula:
-- existió, y su término dice cuándo dejó de valer.
create or replace function fn_locacion_anular(p_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_c     contratos_locacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional anula contratos de locación.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe por qué se anula (al menos 5 letras): queda anotado junto al contrato.';
  end if;

  -- `for update`: dos personas de DO sobre el mismo contrato se ordenan, y la
  -- segunda recibe «ya está anulado» en vez de pisar el motivo de la primera.
  select * into v_c from contratos_locacion c where c.id = p_id for update;
  if not found then
    raise exception 'Ese contrato no existe.';
  end if;
  if v_c.anulado_at is not null then
    raise exception 'Ese contrato ya está anulado.';
  end if;
  if v_c.terminado_el is not null then
    raise exception 'Ese contrato ya se dio por terminado: no se anula.';
  end if;

  update contratos_locacion
     set anulado_at = now(), anulado_por = v_quien, anulado_motivo = btrim(p_motivo)
   where id = p_id;
end;
$fn$;


-- ── 5d · Terminar una locación antes de su fecha ─────────────────────────────
-- Para cuando la persona pasa a planilla, cesa o el contrato se resuelve. La
-- fecha es el último día en que valió: puede ser futura (se sabe que pasa a
-- planilla el 1 de diciembre) y, como pronto, la víspera de empezar (nunca
-- entró en vigor). No toca `personas`: pasar a planilla se hace en Equipo, y
-- este registro solo cierra el vínculo civil.
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


-- ── 6 · Quién puede llamar qué ───────────────────────────────────────────────
-- Desde la 0076 ninguna función nace con EXECUTE para nadie: sin estos grants
-- la pestaña queda vacía sin dar error (0204).
grant execute on function
  fn_locaciones_tablero(), fn_locaciones_listar(uuid),
  fn_locacion_registrar(uuid, text, date, date, date, text, text),
  fn_locacion_anular(uuid, text), fn_locacion_terminar(uuid, date, text)
to authenticated;
revoke execute on function
  fn_locaciones_tablero(), fn_locaciones_listar(uuid),
  fn_locacion_registrar(uuid, text, date, date, date, text, text),
  fn_locacion_anular(uuid, text), fn_locacion_terminar(uuid, date, text)
from public, anon;


-- ═══ PARTE 2 · El almacén de los escaneos (solo `storage.objects`) ══════════
-- Se pega DESPUÉS de la parte 1 y sola. Lleva el registro: así nunca dice
-- «aplicada» sin estarlo.

set local lock_timeout = '3s';

do $$
begin
  if to_regclass('public.contratos_locacion') is null
     or to_regprocedure('public.fn_locacion_libre(text)') is null then
    raise exception 'Falta la PARTE 1 (la tabla y sus funciones): pégala primero y sola, y después esta.';
  end if;
end;
$$;

-- Privado. Un contrato firmado llega casi siempre en PDF; las fotos se admiten
-- para el que solo existe impreso. HEIC porque así guarda un iPhone sus fotos
-- (0170). 50 MB, el tope de los demás buckets de papeles.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contratos-locacion', 'contratos-locacion', false, 52428800,
        array['application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Las CUATRO políticas, no una: Supabase Storage escribe con
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *` y necesita insert, select y
-- update para subir (0172, 0175, 0197 costaron medio día por faltar una).
drop policy if exists contratos_locacion_insert on storage.objects;
drop policy if exists contratos_locacion_select on storage.objects;
drop policy if exists contratos_locacion_update on storage.objects;
drop policy if exists contratos_locacion_delete on storage.objects;

create policy contratos_locacion_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'contratos-locacion'
    and fn_es_admin_o_lider() is true
    and name ~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$'
  );

create policy contratos_locacion_select on storage.objects
  for select to authenticated
  using (bucket_id = 'contratos-locacion' and fn_es_admin_o_lider() is true);

create policy contratos_locacion_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'contratos-locacion' and fn_es_admin_o_lider() is true and fn_locacion_libre(name))
  with check (bucket_id = 'contratos-locacion' and fn_es_admin_o_lider() is true and fn_locacion_libre(name));

create policy contratos_locacion_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'contratos-locacion' and fn_es_admin_o_lider() is true and fn_locacion_libre(name));

insert into migraciones_aplicadas (numero, nombre)
values (610, 'el_contrato_de_locacion_de_quien_cobra_por_honorarios')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'contratos_locacion') as tabla_de_1,
  (select count(*) from pg_proc where proname in (
     'fn_locaciones_tablero', 'fn_locaciones_listar', 'fn_contratos_locacion_inmutables',
     'fn_locacion_libre', 'fn_locacion_registrar', 'fn_locacion_anular', 'fn_locacion_terminar')) as funciones_de_7,
  (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'contratos\_locacion\_%') as politicas_storage_de_4,
  (select count(*) from storage.buckets where id = 'contratos-locacion' and public is false) as bucket_privado,
  (select relrowsecurity from pg_class where relname = 'contratos_locacion') as rls_activa,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 610) as registro;
