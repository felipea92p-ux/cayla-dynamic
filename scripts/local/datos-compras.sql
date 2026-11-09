-- Compras inventadas por hora para las tiendas de la base local: las que leen Turnos (repetición del día,
-- sugerencia de la semana) e Inicio (Tendencias · Gente en piso frente a la venta).
--
-- Por qué hace falta: `fn_compras_por_hora` (0585) lee la forma de `retail.ventas` que tiene PRODUCCIÓN
-- —ubicacion_id, estado, es_prueba— y no la que construyen las migraciones de este repo (la 0220, con sede_id).
-- Sin esto, en local la función falla y las pantallas dicen «no se pudieron leer las compras de retail».
--
-- Qué hace: suma esas tres columnas a `retail.ventas` y la tabla `retail.ubicaciones` (las dos solo si faltan),
-- una caja y una ubicación por tienda, y para los últimos 40 días un número de compras por hora que sube por la
-- tarde y un 60 % el fin de semana. Siempre el mismo para la misma fecha y hora (no usa random()).
-- Solo cuenta tickets: el monto va en 0, porque ninguna pantalla de Dynamic lee montos de retail.
--
-- Se puede repetir: borra lo que sembró la vez anterior (por su nota) antes de sembrar.
--   psql -f scripts/local/datos-compras.sql        (con las variables de scripts/local/comun.sh)
-- Para quitarlo: delete from retail.ventas where nota = 'compras inventadas (datos-compras.sql)';

begin;

alter table retail.ventas add column if not exists ubicacion_id uuid;
alter table retail.ventas add column if not exists estado text;
alter table retail.ventas add column if not exists es_prueba boolean;
create table if not exists retail.ubicaciones (id uuid primary key default gen_random_uuid(), sede_dynamic_id uuid);

insert into retail.ubicaciones (sede_dynamic_id)
select s.id from sedes s
 where s.tipo = 'tienda' and s.activa
   and not exists (select 1 from retail.ubicaciones u where u.sede_dynamic_id = s.id);

-- Una caja cerrada por tienda, reconocible por su fecha imposible.
insert into retail.cajas (sede_id, monto_apertura, abierta_en, estado)
select s.id, 0, '2001-01-01 00:00-05', 'cerrada' from sedes s
 where s.tipo = 'tienda' and s.activa
   and not exists (select 1 from retail.cajas c where c.sede_id = s.id and c.abierta_en = '2001-01-01 00:00-05');

delete from retail.ventas where nota = 'compras inventadas (datos-compras.sql)';

with perfil (sede, hora, base) as (
  values ('TRU', 10, 1), ('TRU', 11, 2), ('TRU', 12, 3), ('TRU', 13, 4), ('TRU', 14, 3), ('TRU', 15, 3), ('TRU', 16, 5), ('TRU', 17, 6),
         ('AQP', 10, 1), ('AQP', 11, 2), ('AQP', 12, 4), ('AQP', 13, 5), ('AQP', 14, 3), ('AQP', 15, 2), ('AQP', 16, 3), ('AQP', 17, 4)
),
cuantas as (
  select s.id as sede_id, u.id as ubicacion_id, c.id as caja_id, d::date as fecha, p.hora,
         greatest(0, round(p.base * case when extract(dow from d) in (0, 6) then 1.6 else 1 end
                           + abs(hashtext(s.codigo || d::date::text || p.hora::text)) % 3 - 1))::int as n
    from perfil p
    join sedes s on s.codigo = p.sede and s.tipo = 'tienda' and s.activa
    join retail.ubicaciones u on u.sede_dynamic_id = s.id
    join retail.cajas c on c.sede_id = s.id and c.abierta_en = '2001-01-01 00:00-05'
   cross join generate_series(fn_hoy_lima() - 40, fn_hoy_lima() - 1, interval '1 day') d
)
insert into retail.ventas (sede_id, caja_id, metodo_pago, monto_total, nota, created_at, ubicacion_id, estado, es_prueba)
select sede_id, caja_id, 'pos', 0, 'compras inventadas (datos-compras.sql)',
       (fecha + make_time(hora, (g * 13) % 60, 0)) at time zone 'America/Lima',
       ubicacion_id, 'completada', false
  from cuantas
 cross join lateral generate_series(1, n) g;

commit;

select s.codigo, count(*) as compras, min(v.created_at)::date as desde, max(v.created_at)::date as hasta
  from retail.ventas v join retail.ubicaciones u on u.id = v.ubicacion_id join sedes s on s.id = u.sede_dynamic_id
 where v.nota = 'compras inventadas (datos-compras.sql)'
 group by s.codigo order by s.codigo;
