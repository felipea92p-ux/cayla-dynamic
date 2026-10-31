-- ============================================================================
-- 0572_la_invitacion_a_la_cuenta_sale_sola_una_vez.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que cada correo de acceso que el sistema le manda a una persona —la
--   invitación para que elija su clave, o el enlace de «recuperar acceso»—
--   quede anotado, y que la base haga imposible mandarle más de:
--     · UNA invitación automática en toda su vida (la que sale sola en cuanto
--       su ficha tiene correo), y
--     · UNA manual por cada correo (el botón «Invitar» o «Reenviar» de Cuentas).
--
-- QUÉ ASUME
--   · Que quien escribe aquí es `/api/admin/cuentas`, con la llave de servicio:
--     el envío lo hace Supabase Auth, que la base no puede llamar. Por eso no
--     hay función guardián: la llave de servicio se salta RLS, y el freno que
--     sí la alcanza son los índices únicos de abajo.
--   · Que el orden es RESERVAR → ENVIAR → CERRAR. La fila se inserta en
--     'reservada' ANTES de pedirle el correo a Supabase; si dos pedidos llegan
--     a la vez (dos pantallas guardando, un doble clic), el segundo choca con el
--     índice único y no envía nada. Es el mismo compare-and-set que
--     `fn_alertas_reservar` (0362) hace con los avisos por correo.
--   Nada más: no toca `personas`, ni Auth, ni ninguna función existente.
--
-- ── POR QUÉ UNA TABLA Y NO UNA MARCA EN LA CUENTA DE ACCESO ─────────────────
--
--   La invitación automática sale ANTES de que exista la cuenta: no hay en
--   Auth dónde anotar «ya se intentó». Y la Ley 30709 obliga a informar la
--   política salarial y a poder PROBARLO: «se le mandó el acceso a tal correo
--   tal día, y lo mandó el sistema / lo mandó tal persona» es parte de esa
--   prueba, y tiene que poder leerse con un SELECT, no escarbando metadatos.
--
-- ── POR QUÉ «UNA MANUAL POR CORREO» Y NO «UNA MANUAL Y PUNTO» ───────────────
--
--   El caso que hace falta cubrir es el correo mal escrito: la invitación se va
--   a `jenifer@…` en vez de `jennifer@…`, nadie la abre, y en Cuentas se
--   corrige el correo. Con «una y punto» esa persona se quedaba sin forma de
--   recibir su acceso, y la salida sería borrar filas a mano. Con «una por
--   correo», corregir el correo abre exactamente un envío más — y nada más.
--
-- ── ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles) ──────────────
--
--   · dos invitaciones automáticas para la misma persona ... índice único
--       parcial (persona) donde origen='automatica' y no fallida
--   · dos envíos manuales al mismo correo de la misma persona  índice único
--       parcial (persona, correo) donde origen='manual' y no fallida
--   · una automática con autor, o una manual sin autor ..... `check`
--   · un correo con mayúsculas o espacios (dos «distintos» que
--       son el mismo buzón y burlarían el índice) .......... `check`
--   · una fila cerrada sin fecha de cierre, o abierta con ella  `check`
--   · un fallo sin motivo ................................... `check`
--   · un cliente del navegador escribiendo aquí ............. sin policies de
--       escritura y con los permisos revocados (mismo molde que la 0480)
--
--   Un envío FALLIDO no cuenta como envío: no llegó ningún correo. Por eso los
--   índices excluyen 'fallida' y el sistema puede volver a intentarlo — sobre
--   todo cuando el motivo fue el tope de correos por hora del proyecto.
--
-- ── SI EL ENVÍO MUERE A MEDIAS ───────────────────────────────────────────────
--   Una fila puede quedarse en 'reservada' si la función de Vercel se corta
--   entre reservar y cerrar. La ruta la da por fallida pasada una hora (el
--   mismo plazo que usan las alertas, 0362) y entonces se puede reintentar. En
--   el peor caso eso es un segundo correo a quien sí recibió el primero, que
--   es mejor que dejar a alguien sin acceso para siempre por un corte de red.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop table if exists invitaciones_cuenta;
--   Nada de planilla ni de asistencia la lee. Sin ella, la pantalla de Cuentas
--   se niega a invitar (dice que falta esta migración) y no sale ningún correo
--   automático: sin dónde reservar, no hay forma de prometer «una sola vez».
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

create table if not exists invitaciones_cuenta (
  id          uuid primary key default gen_random_uuid(),
  persona_id  uuid not null references personas(id),
  correo      text not null check (
    correo = lower(btrim(correo))
    and correo ~ '^[^@[:space:]]+@[^@[:space:]]+$'
    and char_length(correo) <= 254
  ),
  -- 'automatica': la mandó el sistema al ver que la ficha tiene correo.
  -- 'manual': alguien apretó «Invitar» o «Reenviar» en Cuentas.
  origen      text not null check (origen in ('automatica', 'manual')),
  -- 'invitacion': el correo para elegir su clave. 'recuperacion': el de
  -- «recuperar acceso», que es lo único que Supabase acepta mandarle a quien ya
  -- tiene una clave puesta a mano (ver la acción `reinvitar` de la ruta).
  tipo        text not null check (tipo in ('invitacion', 'recuperacion')),
  enviada_por uuid references personas(id),
  estado      text not null default 'reservada' check (estado in ('reservada', 'enviada', 'fallida')),
  detalle     text,
  creada_at   timestamptz not null default now(),
  resuelta_at timestamptz,
  constraint invitaciones_cuenta_autor_segun_origen
    check ((origen = 'automatica') = (enviada_por is null)),
  constraint invitaciones_cuenta_cierre_con_fecha
    check ((estado = 'reservada') = (resuelta_at is null)),
  constraint invitaciones_cuenta_fallo_con_motivo
    check (estado <> 'fallida' or nullif(btrim(detalle), '') is not null)
);

comment on table invitaciones_cuenta is
  'Cada correo de acceso (invitación o recuperar acceso) que se le mandó a una persona. Una automática por persona y una manual por correo; lo escribe /api/admin/cuentas con la llave de servicio (0572).';

create unique index if not exists invitaciones_cuenta_una_automatica
  on invitaciones_cuenta (persona_id)
  where origen = 'automatica' and estado <> 'fallida';

create unique index if not exists invitaciones_cuenta_una_manual_por_correo
  on invitaciones_cuenta (persona_id, correo)
  where origen = 'manual' and estado <> 'fallida';

alter table invitaciones_cuenta enable row level security;

-- Lectura: admin y Líder DO, que son quienes gestionan cuentas. Una líder de
-- equipo no necesita saber a qué correo personal se le mandó el acceso a otra.
drop policy if exists invitaciones_cuenta_select_gestion on invitaciones_cuenta;
create policy invitaciones_cuenta_select_gestion on invitaciones_cuenta
  for select to authenticated using (fn_rol_actual() in ('admin', 'lider_do'));

revoke all on invitaciones_cuenta from anon, authenticated, public;
grant select on invitaciones_cuenta to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (572, 'la_invitacion_a_la_cuenta_sale_sola_una_vez')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables where table_name = 'invitaciones_cuenta') as tabla,
  (select count(*) from pg_indexes where tablename = 'invitaciones_cuenta' and indexname like 'invitaciones_cuenta_una_%') as indices_unicos,
  (select relrowsecurity from pg_class where relname = 'invitaciones_cuenta') as rls_activa,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 572) as registro;
