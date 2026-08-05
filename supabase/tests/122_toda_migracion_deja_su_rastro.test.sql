-- ============================================================================
-- 122_toda_migracion_deja_su_rastro.test.sql — el registro no puede mentir
-- ============================================================================
-- `migraciones_aplicadas` es lo ÚNICO que se puede consultar para saber qué hay
-- en producción sin abrir el SQL Editor y mirar función por función. Vale
-- exactamente lo que valga su completitud: con una omisión adentro, cualquier
-- auditoría de huecos da un resultado falso.
--
-- Y hasta hoy dependía de que quien escribe el archivo se acordara de agregar
-- una línea al final. En tres días ese olvido pasó cuatro veces:
--
--     0128 · 0131 · 0132   backfilleadas a mano por la 0146
--     0152                 la que hizo falta esta prueba
--
-- ── CÓMO FUNCIONA ───────────────────────────────────────────────────────────
--
-- Se comparan DOS registros que se escriben por caminos distintos:
--
--   supabase_migrations.schema_migrations   lo escribe el CLI de Supabase, solo
--                                           con haber aplicado el archivo. No
--                                           se puede olvidar: es automático.
--   migraciones_aplicadas                   lo escribe cada migración a mano.
--                                           Es lo que sí se olvida.
--
-- Si el primero tiene una versión que el segundo no, alguien olvidó su línea.
-- Es la misma forma de la prueba 90 (el espejo de la máquina de estados): dos
-- copias de una verdad, y una prueba que falla cuando se separan.
--
-- ── LO QUE ESTA PRUEBA *NO* PUEDE VER ───────────────────────────────────────
--
-- Dos archivos con el MISMO número. Comprobado empíricamente el 2026-08-05 con
-- las dos migraciones 0154 que existieron unos minutos: `supabase db reset`
-- aplica una, **saltea la otra en silencio y termina sin error**. La saltada
-- nunca corre, así que Postgres jamás se entera de que existió y ninguna prueba
-- de base de datos puede detectarla.
--
-- Eso se caza afuera, mirando nombres de archivo: `scripts/hooks/pre-push`.
-- Las dos defensas son necesarias y ninguna reemplaza a la otra.
-- ============================================================================
begin;
select plan(2);

-- ── 1 · Toda migración aplicada dejó su fila ────────────────────────────────
-- `is_empty` en vez de comparar un conteo: cuando falla, pgTAP imprime los
-- números que sobran. Un «esperaba 0, hubo 3» obligaría a ir a buscar cuáles.
select is_empty(
  $$ select m.version::int as sin_anotar
       from supabase_migrations.schema_migrations m
      where m.version ~ '^[0-9]+$'
        and m.version::int not in (select numero from migraciones_aplicadas)
      order by 1 $$,
  'Toda migración aplicada escribió su fila en migraciones_aplicadas');

-- ── 2 · Y ninguna fila inventa una migración que no corrió ──────────────────
-- El sentido inverso: una fila sin migración detrás significaría que alguien
-- anotó algo que no se aplicó, y el registro mentiría en la dirección peligrosa
-- —diciendo que algo está cuando no está—. Es lo que pasó con la 0089 en julio.
--
-- Las 0031 y 0033 se excluyen a propósito: existen solo como
-- `scripts/sql-manual/aplicar_*.sql`, fuera de git por datos personales, y la
-- fila la escribe quien las pega. Están documentadas en `docs/estado.md`.
select is_empty(
  $$ select a.numero as fila_sin_migracion
       from migraciones_aplicadas a
      where a.numero not in (31, 33)
        and not exists (
          select 1 from supabase_migrations.schema_migrations m
           where m.version ~ '^[0-9]+$' and m.version::int = a.numero)
      order by 1 $$,
  'Ninguna fila del registro nombra una migración que esta base no aplicó');

select * from finish();
rollback;
