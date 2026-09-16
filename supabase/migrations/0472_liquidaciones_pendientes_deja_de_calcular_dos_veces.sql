-- ============================================================================
-- 0472 — `fn_liquidaciones_pendientes` deja de calcular la misma liquidación
--        dos veces por persona
-- ============================================================================
--
-- QUÉ PROMETE
--   Los mismos valores de siempre —ni una cifra ni un booleano cambia—, con
--   UNA sola llamada a `fn_liquidacion_diferencias` por persona en vez de dos.
--   Sirve a `/admin/liquidaciones`, la única pantalla que llama a esta
--   función hoy (la Bandeja pasó a `fn_liquidaciones_vencidas_bandeja`,
--   0471, que ni siquiera calcula esto).
--
-- QUÉ ASUME
--   `fn_liquidacion_diferencias` (0454) es la única definición vigente,
--   comprobado con `./scripts/donde-vive.sh`. Md5 de partida (Postgres local,
--   sin comentarios): 24a08306ff6ae9924dab03340def6b20 — pedido a producción
--   antes de pegar, como manda CLAUDE.md.
--
-- ── EL DEFECTO ───────────────────────────────────────────────────────────────
--   La 0454 calculaba `descuadra` y `descuadra_real` con dos `exists(select 1
--   from fn_liquidacion_diferencias(p.id) ...)` separados. Postgres no
--   recuerda el resultado de una llamada a función entre dos sitios distintos
--   del mismo SELECT: cada `exists` vuelve a ejecutar la función completa, y
--   `fn_liquidacion_diferencias` —cuando la persona sí cobró— hace un cálculo
--   de liquidación entero por dentro (`fn_liquidacion` → `fn_planilla_calcular`).
--   Con 17 cesadas en el Postgres local, esta función tardaba 518 ms; en
--   producción llegó a cancelarse por `statement_timeout` (ver 0471).
--
-- ── LA CORRECCIÓN ────────────────────────────────────────────────────────────
--   Un solo `left join lateral` llama `fn_liquidacion_diferencias(p.id)` una
--   vez, y de ese mismo resultado se leen los dos booleanos con `bool_or`.
--   No hace falta condicionarlo a "solo si ya cobró": `fn_liquidacion_diferencias`
--   ya resuelve eso por dentro —busca su propia `liquidacion_pagada` y, si no
--   hay ninguna o está anulada, vuelve vacía antes de tocar `fn_liquidacion`—,
--   así que llamarla para quien no cobró es barato (una búsqueda que no
--   encuentra nada), nunca un cálculo completo de más.
--
--   Cuentas antes / después, en llamadas a `fn_liquidacion` (la cara, la que
--   corre el motor de planilla): con N cesadas pagadas y M pendientes, antes
--   eran 2N + M; ahora son N + M. Para quien ya cobró, la mitad del costo.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--   No toca `fn_liquidaciones_vencidas_bandeja` (0471): esa ya no calcula
--   `descuadra`/`descuadra_real` en absoluto, por eso no necesita este arreglo.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--   `create or replace` — mismo nombre, misma firma, mismas columnas de
--   retorno que la 0454, así que no hace falta `drop function`.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   Volver a pegar el cuerpo de `fn_liquidaciones_pendientes` tal como está
--   en la 0454.
-- ============================================================================

create or replace function fn_liquidaciones_pendientes()
returns table (
  persona_id     uuid,
  persona        text,
  sede           text,
  fecha_ingreso  date,
  fecha_cese     date,
  vence_el       date,
  dias_restantes int,
  vencido        boolean,
  total          numeric,
  pagada         boolean,
  descuadra      boolean,
  descuadra_real boolean
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
    p.fecha_ingreso,
    p.fecha_cese,
    (p.fecha_cese + 2),
    (p.fecha_cese + 2 - fn_hoy_lima())::int,
    (fn_hoy_lima() > p.fecha_cese + 2 and f.persona_id is null),
    round(coalesce(f.total, (fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric, 0), 2),
    (f.persona_id is not null),
    coalesce(dif.hay_diferencia, false),      -- CAMBIO 0472
    coalesce(dif.hay_diferencia_real, false)  -- CAMBIO 0472
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select lp.* from liquidacion_pagada lp
    where lp.persona_id = p.id order by lp.version desc limit 1
  ) f on f.anulada is not true
  -- CAMBIO 0472 · una sola llamada a fn_liquidacion_diferencias, no dos.
  left join lateral (
    select
      bool_or(true)              as hay_diferencia,
      bool_or(d.origen = 'real') as hay_diferencia_real
    from fn_liquidacion_diferencias(p.id) d
  ) dif on true
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_es_admin_o_lider() is true
  order by (f.persona_id is not null), p.fecha_cese desc;
$fn$;

comment on function fn_liquidaciones_pendientes() is
  'Quién cesó y qué le falta cobrar. descuadra: cualquier diferencia contra lo '
  'pagado. descuadra_real: solo la que NO explica el cierre de Planilla — la '
  'que de verdad hay que revisar. Ver 0251, 0454 y 0472 (una sola llamada a '
  'fn_liquidacion_diferencias, no dos).';

insert into migraciones_aplicadas (numero, nombre)
values (472, 'liquidaciones_pendientes_deja_de_calcular_dos_veces')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
