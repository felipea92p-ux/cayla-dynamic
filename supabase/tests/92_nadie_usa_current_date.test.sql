-- ============================================================================
-- 92_nadie_usa_current_date.test.sql — El guardián de la zona horaria
-- ============================================================================
-- El servidor de Supabase corre en UTC. `current_date` desnudo resuelve en UTC,
-- así que entre las 19:00 y la medianoche de Lima el sistema cree que es mañana.
--
-- Este bug entró CUATRO veces: se arregló en la 0034, en la 0035, en la 0079 y
-- en la 0091. Las tres primeras arreglaron la función que había dado el
-- problema y confiaron en que nadie escribiera la siguiente. No funcionó.
--
-- Esta prueba es lo que hace que la cuarta sea la última: recorre TODAS las
-- funciones del sistema y falla si alguna usa `current_date` fuera de un
-- comentario. Si estás leyendo esto porque acaba de fallar, no busques un rodeo:
-- cambia ese `current_date` por `fn_hoy_lima()` y sigue.
--
-- Qué NO cuenta como infracción:
--   · Mencionarlo en un comentario (avisar del peligro es lo correcto).
--   · Las funciones de extensiones (pgcrypto, pg_cron): no son nuestras.
-- ============================================================================
begin;
select plan(2);

-- Quita los comentarios de línea antes de buscar, para que avisar del peligro en
-- un comentario no cuente como usarlo.
create or replace function _sin_comentarios(p_src text)
returns text language sql immutable as $$
  select string_agg(split_part(linea, '--', 1), E'\n')
  from unnest(string_to_array(p_src, E'\n')) as linea;
$$;

select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and _sin_comentarios(pg_get_functiondef(p.oid)) ~* '\mcurrent_date\M'),
  '',
  'ninguna función del sistema usa current_date desnudo — el servidor corre en UTC, usa fn_hoy_lima()');

-- Y que fn_hoy_lima() diga de verdad el día de Lima, no el de UTC.
-- Entre las 00:00 y las 05:00 UTC (19:00–24:00 de Lima) los dos difieren, y es
-- exactamente la franja donde el sistema se equivocaba.
select is(
  fn_hoy_lima(),
  (now() at time zone 'America/Lima')::date,
  'fn_hoy_lima() devuelve el día de Lima');

drop function _sin_comentarios(text);

select * from finish();
rollback;
