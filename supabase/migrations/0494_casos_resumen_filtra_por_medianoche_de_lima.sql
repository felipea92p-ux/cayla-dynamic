-- ============================================================================
-- 0494 — `fn_casos_resumen` filtra `p_desde` contra la medianoche de LIMA, no
-- la de UTC
-- ----------------------------------------------------------------------------
-- PROMETE: que `p_desde` en `fn_casos_resumen(p_desde date)` excluya de verdad
--   los reportes creados antes de la medianoche de Lima de esa fecha. Nada más
--   cambia: mismo nombre, mismos parámetros, misma tabla de retorno.
--
-- ASUME: `fn_casos_resumen` tal como quedó en la 0493 — confirmado con
--   `donde-vive.sh fn_casos_resumen` antes de escribir esta migración: es la
--   única versión, md5 local 54bace88d0ed6d1ff3681a7f52c34425. Esta función es
--   nueva (la trajo la 0493) y todavía no tiene md5 de producción que
--   comprobar: quien la pegue confirma primero que sigue siendo la única.
--
-- POR QUÉ. La 0493 comparaba `r.creado_at >= p_desde` con `p_desde date` y
--   `r.creado_at timestamptz`. Postgres resuelve ese `>=` convirtiendo
--   `p_desde` a un instante con el cast implícito `date → timestamptz`, que
--   asume medianoche EN EL TIMEZONE DE LA SESIÓN — y el servidor corre en UTC
--   (ver el comentario de la propia prueba 390: "el servidor corre en UTC").
--   Lima es UTC-5, así que la medianoche real de Lima cae 5 horas DESPUÉS de
--   la medianoche UTC que Postgres asumía. Eso deja una ventana de 5 horas
--   —de 00:00 a 05:00 UTC, es decir de 19:00 a 00:00 del día anterior en
--   Lima— donde un reporte que en Lima todavía es "de ayer" ya cuenta como
--   "de hoy" para el filtro.
--
--   Se reprodujo exacto: la prueba 390 falló en CI el 2026-09-29 a las 02:46
--   UTC (21:46 del 28/09 en Lima) con "con p_desde de mañana, ninguno
--   califica" — resultó 3, no 0. Confirmado en un Postgres desechable con esa
--   misma hora: `'2026-09-29 02:46:44+00'::timestamptz >= '2026-09-29'::date`
--   da `true` aunque en Lima seguía siendo 28/09. Fuera de esa ventana de 5
--   horas la prueba pasa siempre, así que se veía como un fallo intermitente
--   sin serlo: depende de a qué hora UTC corre el CI, no del azar.
--
--   El arreglo ancla `p_desde` a la medianoche DE LIMA antes de comparar, con
--   la misma fórmula que ya usa la 0488 para lo mismo (`(fecha + time
--   '00:00:00') at time zone 'America/Lima'`): sumar la hora primero fuerza
--   el tipo `timestamp` (sin zona) ANTES de aplicar `at time zone`, que es lo
--   que evita la ambigüedad de overload. Sin el `+ time '00:00:00'`,
--   `p_desde at time zone 'America/Lima'` con `p_desde` todavía `date` resulta
--   ambiguo: Postgres puede resolverlo como si `p_desde` ya fuera
--   `timestamptz` (la dirección Lima→UTC, la que NO queremos) en vez de
--   `timestamp` (la dirección UTC→Lima que sí queremos) — medido en el mismo
--   Postgres desechable: la forma sin el `+ time` daba el resultado
--   equivocado en silencio, sin ningún error que avisara.
--
--   No es una regla nueva: es la misma que ya obliga a nunca escribir
--   `America/Lima` fuera de `fecha-lima.ts` en el cliente, llevada a SQL —
--   cualquier comparación entre una fecha-calendario de Lima y un instante
--   tiene que pasar por esa zona explícita, nunca por el timezone de la
--   sesión.
--
-- CÓMO SE REVIERTE: recrear el cuerpo de la 0493
--   (`r.creado_at >= p_desde`) — vuelve a traer el bug de la ventana de 5h.
-- ============================================================================

create or replace function fn_casos_resumen(p_desde date default null)
returns table (
  mes         date,
  sede_id     uuid,
  sede_codigo text,
  tipo        text,
  via         text,
  estado      text,
  vencido     boolean
)
language sql
stable
security definer
set search_path = public
as $fn$
  select date_trunc('month', r.creado_at)::date,
         r.sede_id,
         s.codigo,
         r.tipo,
         r.via,
         r.estado,
         exists (
           select 1 from reporte_plazos p
            where p.reporte_id = r.id
              and p.cumplido_at is null
              and p.anulado_at is null
              and p.vence_at < now()
         )
    from reportes r
    join sedes s on s.id = r.sede_id
   where fn_reporte_motivo(r.id) is not null
     and (p_desde is null or r.creado_at >= (p_desde + time '00:00:00') at time zone 'America/Lima');
$fn$;

grant execute on function fn_casos_resumen(date) to authenticated;
revoke execute on function fn_casos_resumen(date) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (494, 'casos_resumen_filtra_por_medianoche_de_lima')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
