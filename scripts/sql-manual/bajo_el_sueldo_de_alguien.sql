-- ############################################################################
-- ####  ¿LE BAJÓ EL SUELDO A ALGUIEN?  — SOLO LEE, NO ESCRIBE NADA        ####
-- ############################################################################
--
-- Nace de un hallazgo LATERAL, y por eso existe: el 2026-08-20, la consulta del
-- descanso semanal devolvió de paso el salario vigente de cada persona en dos
-- periodos consecutivos, y dos habían BAJADO — Nicole Blas de S/1,320 a
-- S/1,130 (−14 %) y Janis Revilla de S/1,450 a S/1,185 (−18 %). Juntas, S/455
-- al mes. Nadie estaba buscando eso.
--
-- ── LA HIPÓTESIS BENIGNA YA ESTÁ DESCARTADA, Y SE DESCARTÓ MIDIENDO ─────────
--
-- Lo primero que se pensó fue «serán tramos mal cargados»: uno nuevo que no
-- cerró al anterior, o dos vigentes a la vez, y el cálculo eligiendo el que no
-- era. Eso habría significado que a esas dos personas se les paga de menos
-- todos los meses, que es mucho peor que la sobretasa que fuimos a buscar.
--
-- NO PUEDE SER. La tabla tiene dos defensas que lo impiden físicamente:
--
--   · `idx_salario_vigente_unico` — índice único sobre `persona_id` donde
--     `vigente_hasta is null`: una persona no puede tener dos tramos abiertos.
--   · `asignacion_salario_sin_solape` — EXCLUDE gist sobre el rango de fechas:
--     dos tramos de la misma persona no pueden pisarse NI UN DÍA.
--
-- Se comprobó intentándolo contra el Postgres local: los dos insert rebotan.
-- Por eso esta consulta NO trae avisos de solape ni de tramos abiertos. Un
-- guardián que no puede saltar nunca es ruido, y el ruido enseña a no mirar.
--
-- ── LO QUE QUEDA, ENTONCES ──────────────────────────────────────────────────
--
-- Que la bajada es un dato REAL: alguien cerró un tramo y abrió otro más bajo.
-- Eso no lo decide una consulta, pero sí puede enseñar lo único que distingue
-- las dos lecturas posibles: QUIÉN lo hizo y QUÉ escribió al hacerlo.
--
--   · Con acuerdo escrito de la persona, una rebaja es válida — la doctrina la
--     admite por convenio, y hay jurisprudencia sobre reducción consensuada.
--   · Sin acuerdo, el art. 30 b) de la LPCL la llama acto de hostilidad —«la
--     reducción inmotivada de la remuneración»— y le da a la persona derecho a
--     exigir el cese del acto o a darse por despedida.
--
-- La nota vacía no prueba que no hubo acuerdo. Prueba que el sistema no lo
-- sabe, que es justo lo que hay que arreglar antes de que alguien pregunte.
--
-- ES UN SOLO SELECT y LA SESIÓN DE ADMIN VA DENTRO, igual que las otras
-- consultas de esta carpeta: el SQL Editor solo muestra la última sentencia.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
gente as (
  select p.id, p.apellidos || ', ' || p.nombres as quien,
         coalesce(s.codigo, '?') as sede
  -- `cross join sesion` al final y no una coma antes del left join: la coma
  -- hace que el LEFT JOIN se ate a `sesion` en vez de a `personas`, y Postgres
  -- lo rechaza. Es solo para que la sesión de admin se establezca.
  from personas p
  left join sedes s on s.id = p.sede_base_id
  cross join sesion
  where coalesce(p.en_planilla, false)
),
tramos as (
  select a.persona_id, a.rango, a.salario_mensual_soles as salario,
         a.vigente_desde, a.vigente_hasta, a.nota, a.created_at,
         (select pa.apellidos || ', ' || pa.nombres from personas pa
           where pa.id = a.asignado_por)                       as lo_asigno,
         lag(a.salario_mensual_soles) over w                   as salario_anterior
  from asignaciones_salario a
  window w as (partition by a.persona_id order by a.vigente_desde)
),
-- Solo la gente a la que le bajó alguna vez. Listar los tramos de las 22
-- personas para encontrar dos es la forma de que no se vea ninguna.
afectadas as (
  select distinct persona_id from tramos
  where salario_anterior is not null and salario < salario_anterior
)
select
  g.quien,
  g.sede,
  t.rango,
  t.salario,
  to_char(t.vigente_desde, 'DD/MM/YYYY')                        as desde,
  coalesce(to_char(t.vigente_hasta, 'DD/MM/YYYY'), '— vigente') as hasta,
  case when t.salario_anterior is null then '(primer tramo)'
       when t.salario < t.salario_anterior
         then '🔴 BAJA ' || to_char(t.salario - t.salario_anterior, 'S9999D99')
              || '  (' || to_char(round(100.0 * (t.salario - t.salario_anterior)
                                        / t.salario_anterior, 1), 'S990D9') || ' %)'
       when t.salario > t.salario_anterior
         then 'sube ' || to_char(t.salario - t.salario_anterior, 'S9999D99')
       else 'igual' end                                         as cambio,
  coalesce(t.lo_asigno, '⚠ no consta quién')                    as lo_asigno,
  coalesce(nullif(trim(t.nota), ''), '⚠ SIN NOTA — nada explica el cambio') as nota,
  to_char(t.created_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI')   as se_cargo
from tramos t
join gente g on g.id = t.persona_id
join afectadas a on a.persona_id = t.persona_id
order by g.quien, t.vigente_desde;
