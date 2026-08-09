-- ############################################################################
-- ####  SOLO LEE. Instantáneo. Léela tú: lleva nombres.                    ####
-- ############################################################################
--
-- como_los_trata_el_sistema.sql — el retrato completo de un locador
--
-- ── PARA QUÉ ────────────────────────────────────────────────────────────────
--   Antes de cambiarle el tipo de vínculo a alguien hay que ver TODO lo que el
--   sistema hace por esa persona, no solo el campo que uno tiene en la cabeza.
--   Cambiar `tipo_vinculo` de `planilla` a `rxh` apaga de golpe la movilidad, la
--   educación, el EsSalud, el sobretiempo y el pago de vacaciones. Si alguna de
--   esas la está recibiendo de verdad, el cambio le mueve el pago.
--
--   El 2026-08-08 se descubrió que `docs/estado.md` afirmaba que los tres
--   locadores cobraban «monto fijo mensual» y era falso: cobran por hora. Ese
--   dato estaba escrito, nadie lo había comprobado, y es uno de los indicios de
--   laboralidad que miran SUNAFIL y los jueces. Se decidió durante semanas sobre
--   una premisa que la base desmentía. De ahí esta consulta.
--
-- ── LA COLUMNA QUE MÁS PESA ─────────────────────────────────────────────────
--   `aporte_essalud`. El 9 % es de cargo del empleador y solo se paga POR UN
--   TRABAJADOR. Si sale un número para alguien que factura por honorarios, hay
--   dos posibilidades y hay que saber cuál:
--
--     · se declara de verdad en la PLAME → esa persona YA está registrada como
--       trabajadora ante SUNAT y EsSalud, y la discusión sobre indicios sobra;
--     · o el sistema lo calcula y nadie lo declara → es un número de pantalla.
--
--   Las dos tienen arreglo. Confundirlas, no.
-- ############################################################################

with periodo as (
  -- El periodo abierto; si no hay ninguno, el último que exista.
  select fecha_ini, fecha_fin
  from periodos_planilla
  order by (estado = 'abierto') desc, fecha_fin desc
  limit 1
),
pl as (
  select e from periodo p,
       jsonb_array_elements(fn_planilla_calcular(p.fecha_ini, p.fecha_fin) -> 'filas') e
),
pr as (
  select e from jsonb_array_elements(
       fn_provisiones((now() at time zone 'America/Lima')::date) -> 'personas') e
)
select p.nombres || ' ' || p.apellidos as persona,
       p.tipo_vinculo,
       p.en_planilla    as tratado_como_trabajador,
       p.sueldo_fijo    as cobra_marque_o_no,
       p.rol,
       -- Lo que RECIBE hoy. Esto es lo que se movería al cambiarle el vínculo.
       (select e ->> 'pago_base'       from pl where (e ->> 'persona_id')::uuid = p.id) as pago_base,
       (select e ->> 'monto_movilidad' from pl where (e ->> 'persona_id')::uuid = p.id) as movilidad,
       (select e ->> 'monto_educacion' from pl where (e ->> 'persona_id')::uuid = p.id) as educacion,
       (select e ->> 'aporte_essalud'  from pl where (e ->> 'persona_id')::uuid = p.id) as essalud,
       (select e ->> 'monto_sobretiempo' from pl where (e ->> 'persona_id')::uuid = p.id) as sobretiempo,
       -- Y lo que se le PROVISIONA.
       (select e ->> 'grati_total' from pr where (e ->> 'persona_id')::uuid = p.id) as prov_grati,
       (select e ->> 'cts_total'   from pr where (e ->> 'persona_id')::uuid = p.id) as prov_cts,
       (select e ->> 'vac'         from pr where (e ->> 'persona_id')::uuid = p.id) as prov_vacaciones,
       -- Las banderas de la 0196. En blanco = decide el tipo de vínculo.
       p.devenga_grati, p.devenga_cts, p.devenga_vacaciones
from personas p
where p.estado = 'activo'
  -- Quien no está en planilla, y también quien SÍ lo está pero tiene una
  -- bandera puesta: el caso de Carlos, `planilla` en el sistema y locador en la
  -- realidad.
  and (p.en_planilla is not true
       or p.devenga_grati is not null
       or p.devenga_cts is not null
       or p.devenga_vacaciones is not null)
order by 1;
