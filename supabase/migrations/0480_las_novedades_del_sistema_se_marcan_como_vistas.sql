-- ============================================================================
-- 0480_las_novedades_del_sistema_se_marcan_como_vistas.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que cada persona pueda marcar una novedad del sistema como «entendida» y
--   ver cuáles ya marcó, para que «Lo mío» le muestre solo las que le faltan y
--   no se las repita cada día. Nadie ve ni escribe las marcas de otra.
--
-- QUÉ ASUME
--   · Que las novedades NO viven en la base: son una lista escrita a mano en
--     `apps/web/lib/novedades.ts`, que sale con el mismo despliegue que la
--     mejora que cuenta. Por eso `novedad_id` es texto libre con un formato
--     fijo (`AAAA-MM-DD-lo-que-cambio`) y NO una llave foránea: la base no puede
--     saber qué ids existen, solo que el que llega tiene forma de id.
--   · Que `fn_persona_actual_id()` identifica a quien marca.
--   Nada más: no toca `anuncios`, `anuncios_leidos`, `bandeja_vistos` ni
--   ninguna función existente.
--
-- ── POR QUÉ UNA TABLA PROPIA Y NO `bandeja_vistos` NI `anuncios_leidos` ───────
--
--   `anuncios_leidos.anuncio_id` es una llave foránea a `anuncios`: una novedad
--   no es una fila de `anuncios` (la firmaría una persona de DO que no la
--   escribió, y su aviso saldría antes que la mejora que cuenta — ver el
--   encabezado de `novedades.ts`).
--   `bandeja_vistos.item_id` es `uuid` y su `check` de tipos y su función se
--   reescriben en cada migración de la Bandeja (0436, 0450, 0453, 0461, 0473):
--   colgarle esto la enredaría con una zona que otras sesiones tocan a la vez,
--   y la propia Bandeja dejó dicho que los anuncios no entran en ella porque
--   «no piden nada de vuelta».
--   Esto es la tercera cosa: un marcador liviano de «ya lo entendí», hermano de
--   `anuncios_leidos` y con su mismo molde.
--
-- ── ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles) ──────────────
--
--   · una marca sin persona ................ `not null` + llave foránea
--   · la misma novedad marcada dos veces ..... llave primaria (persona, novedad)
--   · un id que no tiene forma de id ......... `check` sobre el formato y el
--       largo: vacío, con mayúsculas, con espacios o de 4 000 caracteres no
--       entran ni por la función ni por un insert directo
--   · una persona leyendo las marcas de otra .. RLS: solo `persona_id` propia
--   · escribir sin pasar por la función ....... sin policies de insert/update/
--       delete y sin esos permisos: mismo patrón que `anuncios` y `bandeja_vistos`
--
-- ── POR QUÉ `do nothing` Y NO `do update` AL MARCAR DE NUEVO ─────────────────
--
--   `visto_at` guarda la PRIMERA vez que la persona la entendió. Marcarla otra
--   vez no debe correr esa fecha (a diferencia de `bandeja_vistos`, donde la
--   fecha dice «la vi por última vez»): aquí la marca es un hecho, no una
--   preferencia que se refresca.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_marcar_novedad_vista(text);
--   drop table if exists novedades_vistas;
--   Nada cuelga de esta tabla: ningún cálculo de planilla ni de asistencia la
--   lee. Revertir solo hace que «Lo mío» calle las novedades (el código las
--   oculta si no puede leer sus marcas) y que Anuncios las muestre por fecha.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- ── 1 · Qué novedad entendió cada persona ────────────────────────────────────
create table if not exists novedades_vistas (
  persona_id uuid not null references personas(id),
  -- Mismo formato que `FORMATO_ID_NOVEDAD` en `apps/web/lib/novedades.ts`, y
  -- `tests/novedades.test.ts` comprueba que todo id de la lista lo cumple: si
  -- alguien lo cambia en un solo lado, una novedad legítima deja de poder
  -- marcarse y la prueba lo dice antes de llegar aquí.
  novedad_id text not null check (
    novedad_id ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$'
    and char_length(novedad_id) <= 100
  ),
  visto_at   timestamptz not null default now(),
  primary key (persona_id, novedad_id)
);

comment on table novedades_vistas is
  'Qué novedad del sistema (lista en apps/web/lib/novedades.ts) ya entendió cada persona. Marcador liviano, no un acuse legal. Escritura solo por fn_marcar_novedad_vista.';

alter table novedades_vistas enable row level security;

-- Lectura: la propia, sin excepción. Ni admin ni líder necesitan saber quién
-- entendió qué: esto no es una auditoría, es la memoria de cada quien.
drop policy if exists novedades_vistas_select_propia on novedades_vistas;
create policy novedades_vistas_select_propia on novedades_vistas
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- Sin policies de insert/update/delete: toda escritura pasa por la función de
-- abajo, igual que `anuncios` (0351).
grant select on novedades_vistas to authenticated;
revoke all on novedades_vistas from anon, public;

-- ── 2 · Marcar como entendida — idempotente ──────────────────────────────────
-- Una sola sentencia: o queda la marca o no queda nada. Volver a marcar la
-- misma novedad no falla ni corre la fecha de la primera vez.
create or replace function fn_marcar_novedad_vista(p_novedad_id text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  insert into novedades_vistas (persona_id, novedad_id)
  values (v_persona, p_novedad_id)
  on conflict (persona_id, novedad_id) do nothing;
end;
$fn$;
grant execute on function fn_marcar_novedad_vista(text) to authenticated;
revoke execute on function fn_marcar_novedad_vista(text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (480, 'las_novedades_del_sistema_se_marcan_como_vistas')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables where table_name = 'novedades_vistas') as tabla_novedades_vistas,
  (select count(*) from pg_proc where proname = 'fn_marcar_novedad_vista') as fn_marcar_vista,
  (select relrowsecurity from pg_class where relname = 'novedades_vistas') as rls_activa,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 480) as registro;
