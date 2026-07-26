-- ============================================================================
-- 0080 — Feriados hasta 2032, y un aviso para que no se vuelva a acabar
-- ----------------------------------------------------------------------------
-- PROMETE: que la planilla siga pagando los feriados correctamente hasta
--   diciembre de 2032, y que el sistema avise con meses de anticipación antes
--   de quedarse sin calendario.
--
-- EL DEFECTO. La tabla `feriados` se sembró en la 0024 solo con 2026. El motor
-- de planilla la consulta para dos cosas: pagar el día feriado a quien no
-- trabaja, y aplicar la sobretasa a quien sí lo trabaja. Un día que no está en
-- la tabla simplemente NO ES FERIADO para el sistema: no hay error, no hay
-- aviso, la planilla sale más baja y cuadra consigo misma.
--
-- El 1 de enero de 2027 eso habría pasado con Año Nuevo. Nadie lo habría
-- notado hasta que una colaboradora reclamara — y para entonces habría varias
-- planillas pagadas de menos.
--
-- POR QUÉ SEIS AÑOS Y NO UNO. Decisión de Felipe (26/07/2026): "¿qué pasa si
-- mañana yo no estoy?". Un año resuelve el próximo enero y devuelve el mismo
-- riesgo al siguiente diciembre, cuando puede que quien sepa de esto ya no
-- esté mirando. El calendario de feriados nacionales es estable; cargarlo
-- largo cuesta lo mismo que cargarlo corto.
--
-- LAS FECHAS MÓVILES NO SE ADIVINARON. Jueves y Viernes Santo dependen de la
-- Pascua, que se calculó con el algoritmo gregoriano de computus
-- (Meeus/Jones/Butcher) y se validó contra 2024, 2025 y 2026 — este último
-- coincide exactamente con lo ya sembrado en la 0024.
--
-- LO QUE ESTO NO CUBRE. Si el Congreso crea un feriado nuevo o declara un día
-- no laborable puntual, no aparece acá. Para eso está el aviso: la pantalla de
-- Feriados es editable, y ahora dice cuándo se está por acabar el calendario.
--
-- Reversible: `delete from feriados where fecha >= '2027-01-01'` y soltar la
-- función de aviso.
-- ============================================================================

insert into feriados (fecha, nombre) values
  ('2027-01-01', 'Año Nuevo'),
  ('2027-03-25', 'Jueves Santo'),
  ('2027-03-26', 'Viernes Santo'),
  ('2027-05-01', 'Día del Trabajo'),
  ('2027-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2027-06-29', 'San Pedro y San Pablo'),
  ('2027-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2027-07-28', 'Fiestas Patrias'),
  ('2027-07-29', 'Fiestas Patrias'),
  ('2027-08-06', 'Batalla de Junín'),
  ('2027-08-30', 'Santa Rosa de Lima'),
  ('2027-10-08', 'Combate de Angamos'),
  ('2027-11-01', 'Todos los Santos'),
  ('2027-12-08', 'Inmaculada Concepción'),
  ('2027-12-09', 'Batalla de Ayacucho'),
  ('2027-12-25', 'Navidad'),
  ('2028-01-01', 'Año Nuevo'),
  ('2028-04-13', 'Jueves Santo'),
  ('2028-04-14', 'Viernes Santo'),
  ('2028-05-01', 'Día del Trabajo'),
  ('2028-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2028-06-29', 'San Pedro y San Pablo'),
  ('2028-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2028-07-28', 'Fiestas Patrias'),
  ('2028-07-29', 'Fiestas Patrias'),
  ('2028-08-06', 'Batalla de Junín'),
  ('2028-08-30', 'Santa Rosa de Lima'),
  ('2028-10-08', 'Combate de Angamos'),
  ('2028-11-01', 'Todos los Santos'),
  ('2028-12-08', 'Inmaculada Concepción'),
  ('2028-12-09', 'Batalla de Ayacucho'),
  ('2028-12-25', 'Navidad'),
  ('2029-01-01', 'Año Nuevo'),
  ('2029-03-29', 'Jueves Santo'),
  ('2029-03-30', 'Viernes Santo'),
  ('2029-05-01', 'Día del Trabajo'),
  ('2029-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2029-06-29', 'San Pedro y San Pablo'),
  ('2029-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2029-07-28', 'Fiestas Patrias'),
  ('2029-07-29', 'Fiestas Patrias'),
  ('2029-08-06', 'Batalla de Junín'),
  ('2029-08-30', 'Santa Rosa de Lima'),
  ('2029-10-08', 'Combate de Angamos'),
  ('2029-11-01', 'Todos los Santos'),
  ('2029-12-08', 'Inmaculada Concepción'),
  ('2029-12-09', 'Batalla de Ayacucho'),
  ('2029-12-25', 'Navidad'),
  ('2030-01-01', 'Año Nuevo'),
  ('2030-04-18', 'Jueves Santo'),
  ('2030-04-19', 'Viernes Santo'),
  ('2030-05-01', 'Día del Trabajo'),
  ('2030-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2030-06-29', 'San Pedro y San Pablo'),
  ('2030-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2030-07-28', 'Fiestas Patrias'),
  ('2030-07-29', 'Fiestas Patrias'),
  ('2030-08-06', 'Batalla de Junín'),
  ('2030-08-30', 'Santa Rosa de Lima'),
  ('2030-10-08', 'Combate de Angamos'),
  ('2030-11-01', 'Todos los Santos'),
  ('2030-12-08', 'Inmaculada Concepción'),
  ('2030-12-09', 'Batalla de Ayacucho'),
  ('2030-12-25', 'Navidad'),
  ('2031-01-01', 'Año Nuevo'),
  ('2031-04-10', 'Jueves Santo'),
  ('2031-04-11', 'Viernes Santo'),
  ('2031-05-01', 'Día del Trabajo'),
  ('2031-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2031-06-29', 'San Pedro y San Pablo'),
  ('2031-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2031-07-28', 'Fiestas Patrias'),
  ('2031-07-29', 'Fiestas Patrias'),
  ('2031-08-06', 'Batalla de Junín'),
  ('2031-08-30', 'Santa Rosa de Lima'),
  ('2031-10-08', 'Combate de Angamos'),
  ('2031-11-01', 'Todos los Santos'),
  ('2031-12-08', 'Inmaculada Concepción'),
  ('2031-12-09', 'Batalla de Ayacucho'),
  ('2031-12-25', 'Navidad'),
  ('2032-01-01', 'Año Nuevo'),
  ('2032-03-25', 'Jueves Santo'),
  ('2032-03-26', 'Viernes Santo'),
  ('2032-05-01', 'Día del Trabajo'),
  ('2032-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2032-06-29', 'San Pedro y San Pablo'),
  ('2032-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2032-07-28', 'Fiestas Patrias'),
  ('2032-07-29', 'Fiestas Patrias'),
  ('2032-08-06', 'Batalla de Junín'),
  ('2032-08-30', 'Santa Rosa de Lima'),
  ('2032-10-08', 'Combate de Angamos'),
  ('2032-11-01', 'Todos los Santos'),
  ('2032-12-08', 'Inmaculada Concepción'),
  ('2032-12-09', 'Batalla de Ayacucho'),
  ('2032-12-25', 'Navidad')
on conflict (fecha) do nothing;

-- ── El aviso: cuánto calendario queda ───────────────────────────────────────
-- Devuelve hasta cuándo hay feriados cargados y si urge extender. Lo consume
-- la pantalla de Feriados; se prefiere una función a una consulta suelta para
-- que el criterio de "se está acabando" viva en un solo lugar.
create or replace function fn_feriados_cobertura()
returns table (ultimo_feriado date, meses_restantes int, nivel text, mensaje text)
language sql stable security definer set search_path = public as $$
  with u as (select max(fecha) as f from feriados),
       m as (select u.f,
                    (extract(year  from age(u.f, (now() at time zone 'America/Lima')::date)) * 12
                   + extract(month from age(u.f, (now() at time zone 'America/Lima')::date)))::int as meses
             from u)
  select m.f,
         m.meses,
         case when m.meses < 3 then 'rojo' when m.meses < 12 then 'ambar' else 'verde' end,
         case
           when m.f is null then 'No hay ningún feriado cargado: la planilla no está pagando feriados.'
           when m.meses < 3 then
             'Quedan menos de 3 meses de feriados cargados (hasta ' || to_char(m.f,'DD/MM/YYYY') ||
             '). Después de esa fecha la planilla dejará de pagar los feriados SIN avisar.'
           when m.meses < 12 then
             'Quedan ' || m.meses || ' meses de feriados cargados (hasta ' || to_char(m.f,'DD/MM/YYYY') || '). Conviene extender el calendario.'
           else
             'Calendario cargado hasta ' || to_char(m.f,'DD/MM/YYYY') || ' (' || m.meses || ' meses).'
         end
  from m;
$$;
grant  execute on function fn_feriados_cobertura() to authenticated;
revoke execute on function fn_feriados_cobertura() from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (80, 'feriados_hasta_2032')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
