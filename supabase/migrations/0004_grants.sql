-- CAYLA Dynamic — privilegios a nivel de tabla.
-- RLS controla FILAS; esto habilita el acceso base a nivel de tabla/función que
-- Postgres exige independientemente de RLS. service_role tiene bypassrls a nivel
-- de fila, pero igual necesita estos grants a nivel de tabla.

grant usage on schema public to anon, authenticated, service_role;

grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant all on all functions in schema public to service_role;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;

alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on sequences to service_role;
