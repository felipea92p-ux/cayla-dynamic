-- ============================================================================
-- 0598 — `fn_liquidaciones_lista`: la lista de /admin/liquidaciones deja de
--        recalcular la liquidación de cada persona que ya cobró
-- ============================================================================
--
-- QUÉ PROMETE
--   La pantalla Liquidaciones vuelve a abrir. Los mismos valores de siempre en
--   las mismas columnas —quién cesó, cuándo vence, cuánto, si se pagó—, SIN las
--   dos columnas `descuadra` y `descuadra_real`, que eran lo único caro.
--
-- QUÉ ASUME
--   No reescribe ninguna función existente: crea una nueva y no toca
--   `fn_liquidaciones_pendientes` (0475), que queda tal cual para quien la use
--   y para las pruebas 133, 192, 194 y 359. Por eso no hay «md5 de partida».
--   Comprobado con `./scripts/donde-vive.sh fn_liquidaciones_lista` el
--   2026-11-05: no existía en ninguna migración ni rama.
--
-- ── EL DEFECTO ───────────────────────────────────────────────────────────────
--   2026-11-05, Liquidaciones muestra «No se pudo leer la lista: canceling
--   statement due to statement timeout» y la lista vacía. `fn_liquidaciones_
--   pendientes` llama `fn_liquidacion_diferencias` para CADA cesada, y cuando
--   la persona ya cobró eso corre el motor de planilla entero. La 0475 bajó el
--   costo a la mitad; la lista solo crece, porque a nadie se le borra, y ya se
--   canceló una vez más. Es el mismo defecto que la 0474 resolvió para la
--   Bandeja, en la otra pantalla.
--
-- ── LA CORRECCIÓN ────────────────────────────────────────────────────────────
--   Para quien ya cobró, el total sale de la foto congelada
--   (`liquidacion_pagada.total`), sin cálculo. `fn_liquidacion` solo corre para
--   quien NO ha cobrado, que es poca gente y la que de verdad necesita el
--   número de hoy. Las diferencias contra lo pagado se piden por persona, al
--   abrirla (`fn_liquidacion_diferencias`, que la pantalla ya llama).
--
-- ── LO QUE SE PIERDE, DICHO CLARO ────────────────────────────────────────────
--   La columna «Cálculo cambió» del CSV de Pagadas. Esa pastilla ya no estaba
--   en la lista (docs/estado.md, 2026-10-21); solo sobrevivía en el CSV.
--
-- ── IDEMPOTENTE · CÓMO SE REVIERTE ───────────────────────────────────────────
--   `create or replace`. Se revierte con
--   `drop function if exists fn_liquidaciones_lista();` y volviendo la pantalla
--   a pedir `fn_liquidaciones_pendientes`.
-- ============================================================================

create or replace function fn_liquidaciones_lista()
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
  pagada         boolean
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
    (f.persona_id is not null)
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select lp.* from liquidacion_pagada lp
    where lp.persona_id = p.id order by lp.version desc limit 1
  ) f on f.anulada is not true
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_es_admin_o_lider() is true
  order by (f.persona_id is not null), p.fecha_cese desc, p.id;
$fn$;

comment on function fn_liquidaciones_lista() is
  'La lista de /admin/liquidaciones: quién cesó y qué le falta cobrar. A '
  'diferencia de fn_liquidaciones_pendientes (0475) no calcula descuadra ni '
  'descuadra_real: para quien ya cobró usa la foto congelada, sin motor de '
  'planilla. Ver 0598.';

revoke execute on function fn_liquidaciones_lista() from public, anon;
grant  execute on function fn_liquidaciones_lista() to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (598, 'liquidaciones_lista_sin_el_calculo_de_diferencias')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
