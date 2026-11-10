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
--   · alguien fuera de DO leyéndolo ............. RLS
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
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_locaciones_tablero(), fn_locaciones_listar();
--   drop table contratos_locacion;   -- se lleva su trigger
--   drop function if exists fn_contratos_locacion_inmutables();
--   Nada de planilla, asistencia ni pago lee esta tabla: revertir solo quita
--   la pestaña. Ojo: borrarla destruye el registro de quién subió cada
--   contrato y cuándo.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- Si una tabla está ocupada, mejor fallar a los 3 s y repegar que dejar en
-- cola a todo el que llegue detrás (la FK toma un candado sobre `personas`).
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
  constraint locacion_termina_dentro_del_plazo check (terminado_el is null or terminado_el <= fecha_fin),
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


-- ── 4 · El tablero: una fila por cada persona activa por honorarios ─────────
-- Parte de las PERSONAS y no de los contratos, igual que `fn_contratos_tablero`
-- (0287): quien no tiene ninguno tiene que verse.
--
-- Contrato: devuelve a cada RxH activo (sin las cuentas de servicio, 0491) con
-- el contrato que llega más lejos y el estado de su cobertura. Un término
-- anticipado cuenta como el fin real. Los anulados no cuentan. Quien no es DO
-- recibe la lista vacía, como en el tablero hermano.
--
--   vencido ....... su último contrato ya terminó y sigue activa por honorarios
--   sin_contrato .. no hay ninguno registrado
--   por_vencer .... cubierta hoy y hasta dentro de 60 días o menos (la misma
--                   ventana de Contratos y de Equipo)
--   por_empezar ... hoy no está cubierta, pero hay un contrato que empieza después
--   vigente ....... cubierta hoy y por más de 60 días
--
-- Un contrato ya firmado que empieza cuando termina el actual cuenta como
-- cobertura: «vence pronto» no salta si la renovación ya está registrada.
create or replace function fn_locaciones_tablero()
returns table (
  persona_id      uuid,
  persona         text,
  sede            text,
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
  filas as (
    select p.id as persona_id,
           p.nombres || ' ' || p.apellidos as persona,
           p.apellidos,
           coalesce(s.codigo, '—') as sede,
           u.id as contrato_id, u.servicio, u.fecha_inicio, u.fin_real,
           coalesce(r.n, 0) as n,
           case
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
     where p.estado = 'activo'
       and not p.cuenta_de_servicio
       and p.tipo_vinculo = 'rxh'
       and fn_es_admin_o_lider() is true
  )
  select f.persona_id, f.persona, f.sede, f.contrato_id, f.servicio, f.fecha_inicio,
         f.fin_real, (f.fin_real - fn_hoy_lima())::int, f.n, f.estado
    from filas f
   -- Lo que urge primero: quien trabaja sin contrato vigente.
   order by case f.estado
              when 'vencido'      then 0
              when 'sin_contrato' then 1
              when 'por_vencer'   then 2
              when 'por_empezar'  then 3
              else 4
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


-- ── 6 · Quién puede llamar qué ───────────────────────────────────────────────
-- Desde la 0076 ninguna función nace con EXECUTE para nadie: sin estos grants
-- la pestaña queda vacía sin dar error (0204).
grant execute on function fn_locaciones_tablero(), fn_locaciones_listar(uuid) to authenticated;
revoke execute on function fn_locaciones_tablero(), fn_locaciones_listar(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (610, 'el_contrato_de_locacion_de_quien_cobra_por_honorarios')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'contratos_locacion') as tabla_de_1,
  (select count(*) from pg_proc where proname in (
     'fn_locaciones_tablero', 'fn_locaciones_listar', 'fn_contratos_locacion_inmutables')) as funciones_de_3,
  (select relrowsecurity from pg_class where relname = 'contratos_locacion') as rls_activa,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 610) as registro;
