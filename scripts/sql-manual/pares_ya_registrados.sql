-- ############################################################################
-- ####  ¿QUÉ OTRAS PERSONAS YA ESTÁN REGISTRADAS DOS VECES?  (solo lectura)  ####
-- ############################################################################
--
-- SE CORRE DESPUÉS de pegar la 0506, que es la que trae `fn_nombres_parecidos`.
-- No escribe nada. En el SQL Editor de producción, tal cual.
--
-- POR QUÉ HACE FALTA. La 0506 frena los duplicados NUEVOS. Los que ya existen
-- —entre las personas activas y entre las ~27 que ya salieron— nadie los ha
-- medido: el 2026-10-04 apareció uno por casualidad, mirando la pantalla. Esta
-- consulta aplica la misma regla a cada pareja de la tabla.
--
-- CÓMO SE LEE
--   · Cada fila es UNA pareja que «podría ser la misma persona». Casi todas serán
--     homónimos legítimos (dos Quispe, hermanas); las que importan son las que
--     tienen la misma persona dos veces: mismo nombre, fechas de ingreso pegadas,
--     una con marcajes y la otra sin ellos, o una inactiva y otra activa (un
--     reingreso que se registró de nuevo en vez de reactivarse).
--   · `marcajes_a` y `marcajes_b` ayudan a decidir cuál se queda: la que tiene
--     marcajes es la que se usó.
--   · NO decide nada ni borra nada. Cada pareja se revisa a mano.
--
-- NOTA: las estaciones de retail (`cuenta_de_servicio`, 0490) se excluyen.
-- ############################################################################

select a.id                                          as id_a,
       a.nombres || ' ' || a.apellidos               as una,
       a.estado                                      as estado_a,
       a.fecha_ingreso                               as ingreso_a,
       (select count(*) from public.marcajes m where m.persona_id = a.id) as marcajes_a,
       b.id                                          as id_b,
       b.nombres || ' ' || b.apellidos               as otra,
       b.estado                                      as estado_b,
       b.fecha_ingreso                               as ingreso_b,
       (select count(*) from public.marcajes m where m.persona_id = b.id) as marcajes_b
  from public.personas a
  join public.personas b on a.id < b.id
 where public.fn_nombres_parecidos(a.nombres, a.apellidos, b.nombres, b.apellidos)
   and coalesce((to_jsonb(a) ->> 'cuenta_de_servicio')::boolean, false) is not true
   and coalesce((to_jsonb(b) ->> 'cuenta_de_servicio')::boolean, false) is not true
 order by greatest(a.created_at, b.created_at) desc;
