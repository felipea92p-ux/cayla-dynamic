-- ============================================================================
-- 0493_estadisticas_de_casos_para_el_dashboard.sql
-- ============================================================================
-- QUÉ PROMETE
--   Una función, `fn_casos_resumen(p_desde)`, que le da al Dashboard lo que
--   necesita para responder «¿cuántos reportan, sobre qué, y cómo va cada
--   sede?» sin exponer NUNCA quién escribió cada reporte. Devuelve una fila
--   por reporte que quien llama YA gestiona (mismo criterio que la Bandeja),
--   con solo: el mes en que se creó, la sede, el tipo, la vía, el estado y si
--   tiene un plazo vencido hoy. Nada de `autor_id`, `codigo` ni `relato`. El
--   panel arma las cuatro vistas (por categoría, por vía, tendencia, por
--   sede) agregando estas filas en el cliente — un solo viaje a la base por
--   cada carga de la pestaña «Casos».
--
-- QUÉ ASUME
--   · `fn_reporte_motivo(uuid)` (0483) ya decide, fila por fila, si quien
--     llama gestiona ese reporte — la misma regla que usa
--     `fn_reportes_bandeja()` (0488) para su lista. Esta función NO inventa
--     una regla de acceso nueva: agrega sobre el mismo conjunto que esa
--     bandeja ya deja ver. Por eso una líder de equipo, que solo gestiona los
--     reportes de su sede sin nadie de nivel 1+ involucrada, ve un resumen
--     acotado a eso — y el Título X, que `fn_reporte_motivo` nunca le abre a
--     una líder, nunca aparece en sus números tampoco. No hace falta un piso
--     de agregación aparte: lo hereda del mismo filtro fila por fila.
--   · `reporte_plazos` (0488): un plazo vencido es uno sin `cumplido_at` ni
--     `anulado_at`, con `vence_at < now()` — igual que en `fn_reportes_bandeja`.
--   · El Dashboard llama esto una vez por carga con `p_desde` en los últimos
--     6 meses (el tramo más largo que ofrece el selector de periodo) y
--     recorta a «este mes» o «3 meses» en el cliente, sin volver a pedirle
--     nada a la base.
--
-- POR QUÉ UNA FILA POR REPORTE Y NO YA AGRUPADO EN SQL
--   Agrupar acá (`group by` con `count(*)`) ahorraría bytes, pero fijaría de
--   antemano CUÁLES cortes existen (categoría, vía, mes, sede...). El panel
--   necesita cuatro cortes distintos de las mismas filas; devolverlas sueltas
--   dejó el SQL más simple y sin tener que adivinar hoy todos los cortes que
--   el panel va a querer mañana. El volumen es chico (reportes de una empresa
--   de ~30 personas en 6 meses, no un log), así que no pesa.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_casos_resumen(date);
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
     and (p_desde is null or r.creado_at >= p_desde);
$fn$;

grant execute on function fn_casos_resumen(date) to authenticated;
revoke execute on function fn_casos_resumen(date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (493, 'estadisticas_de_casos_para_el_dashboard')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_casos_resumen') as fn_creada,
  (select count(*) from migraciones_aplicadas where numero = 493) as migracion_registrada;
