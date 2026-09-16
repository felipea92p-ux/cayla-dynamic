-- ============================================================================
-- 0471 — La Bandeja deja de pagar por un cálculo que no usa
-- ============================================================================
--
-- QUÉ PROMETE
--   Una función nueva y liviana, `fn_liquidaciones_vencidas_bandeja()`, que
--   devuelve SOLO las liquidaciones vencidas y sin pagar — lo único que la
--   Bandeja necesita (`esLiquidacionParaBandeja`, bandeja-fuentes.ts:139) — y
--   nada más. No toca `fn_liquidaciones_pendientes()`: esa sigue siendo la
--   única fuente de `/admin/liquidaciones`, que sí necesita `descuadra` y
--   `descuadra_real`.
--
-- QUÉ ASUME
--   `fn_liquidacion` (0244) es la única definición vigente, comprobado con
--   `./scripts/donde-vive.sh`. `liquidacion_pagada` (0167) versiona por
--   persona y `anulada` marca la que no cuenta como pago.
--
-- ── EL PROBLEMA QUE ESTO CIERRA ─────────────────────────────────────────────
--
--   `fn_liquidaciones_pendientes()` (0454) calcula la liquidación completa
--   —motor de planilla incluido— de CADA persona cesada, y para cada una que
--   YA COBRÓ la calcula DOS VECES más (`descuadra` y `descuadra_real` llaman
--   `fn_liquidacion_diferencias` por separado). Medido en el Postgres local
--   con 17 cesadas: 518 ms. Producción lo canceló hoy con «canceling
--   statement due to statement timeout» — el límite del rol `authenticated`
--   (~8s, docs/hallazgos-abiertos.md:1958) — porque a nadie se le borra
--   (se marca inactivo, para siempre), así que esta lista solo crece.
--
--   Pero la Bandeja (`bandeja-fuentes.ts:340`, todo admin o líder, en cada
--   carga) pedía esa función completa y tiraba `descuadra`/`descuadra_real`
--   sin usarlos — pagaba el cálculo más caro del sistema por un dato que
--   descarta. Esta migración le da su propia función, que filtra ANTES de
--   calcular: solo entra a `fn_liquidacion` quien de verdad está pendiente
--   (hoy, 1 a 3 personas), nunca quien ya cobró.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--   No arregla la doble llamada a `fn_liquidacion_diferencias` dentro de
--   `fn_liquidaciones_pendientes()` — esa sigue costándole cara a
--   `/admin/liquidaciones` (pantalla de uso puntual, no en cada carga de la
--   Bandeja). Queda para una migración aparte.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--   `create or replace`.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_liquidaciones_vencidas_bandeja();
--   Y en bandeja-fuentes.ts, volver a pedir "fn_liquidaciones_pendientes".
-- ============================================================================

create or replace function fn_liquidaciones_vencidas_bandeja()
returns table (
  persona_id     uuid,
  persona        text,
  sede           text,
  fecha_cese     date,
  vence_el       date,
  dias_restantes int,
  total          numeric,
  pagada         boolean,
  vencido        boolean
)
language sql
stable
security definer
set search_path = public
as $fn$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_cese,
    (p.fecha_cese + 2),
    (p.fecha_cese + 2 - fn_hoy_lima())::int,
    round(coalesce((fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric, 0), 2),
    false,
    true
  from personas p
  left join sedes s on s.id = p.sede_base_id
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_hoy_lima() > p.fecha_cese + 2
    and not exists (
      select 1 from liquidacion_pagada lp
      where lp.persona_id = p.id and lp.anulada is not true
    )
    and fn_es_admin_o_lider() is true
  order by p.fecha_cese desc;
$fn$;

comment on function fn_liquidaciones_vencidas_bandeja() is
  'Cesadas sin liquidación pagada, ya vencidas (fecha_cese + 2 días). Para la '
  'Bandeja: nunca calcula sobre quien ya cobró, a diferencia de '
  'fn_liquidaciones_pendientes (0454), que sirve a /admin/liquidaciones. Ver 0471.';

revoke execute on function fn_liquidaciones_vencidas_bandeja() from public, anon;
grant  execute on function fn_liquidaciones_vencidas_bandeja() to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (471, 'la_bandeja_deja_de_pagar_por_un_calculo_que_no_usa')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
