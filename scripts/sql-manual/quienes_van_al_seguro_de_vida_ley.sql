-- ============================================================================
-- ¿Quiénes tienen que estar en la póliza del Seguro de Vida Ley?
--
-- PARA QUÉ. El Seguro de Vida Ley YA ESTÁ CONTRATADO con Pacífico Seguros
-- (póliza colectiva Nº 143720; visto en los certificados el 2026-10-21). En
-- agosto de 2026 se había cotizado La Positiva por 19 personas, pero lo
-- contratado es Pacífico. Este archivo ya no sirve para decidir si firmar:
-- sirve para saber QUIÉN TIENE QUE ESTAR DECLARADO a Pacífico hoy y cruzarlo
-- contra los certificados que Pacífico emite (consulta 5). Pacífico solo cubre
-- a quien declara: sin declaración no hay certificado ni cobertura.
--
-- A QUIÉN CUENTA (decisión de Felipe, 2026-10-21): solo `tipo_vinculo =
-- 'planilla'`. Quedan fuera 'prueba' (la prueba de tres días, 0536), 'rxh',
-- 'practicante', 'no_trabajador' y las cuentas de servicio (estaciones de
-- retail, 0490: no son personas). Objeción registrada: este archivo incluía a
-- 'prueba' porque la obligación nace con el trabajo efectivo y no con el
-- contrato; mientras dura la prueba esas personas no tienen seguro de vida.
-- Si Felipe cambia de criterio, se cambia `p.tipo_vinculo = 'planilla'` por
-- `p.en_planilla` (planilla + prueba) en las consultas 2, 3, 4 y 5.
--
-- POR QUÉ IMPORTA EL NÚMERO EXACTO. El D.Leg. 688, con la modificación del
-- D.U. 044-2019, hace obligatorio el seguro DESDE EL PRIMER DÍA de trabajo. Si
-- una persona en planilla queda fuera de la póliza y fallece o queda inválida,
-- el capital lo paga CAYLA de su patrimonio: 16 remuneraciones por muerte
-- natural, 32 por muerte accidental o invalidez total y permanente. Sobre la
-- RMV de S/1,230 son S/19,680 y S/39,360 respectivamente, por persona.
--
-- Ese riesgo no se cubre hacia atrás. Según el certificado de Pacífico, la
-- cobertura de cada persona empieza a las cero horas del día 1 del mes en que
-- se la declara por primera vez: declarar tarde es un hueco sin seguro. Una
-- alta de planilla se declara en el mismo mes en que ingresa.
--
-- CÓMO SE CORRE — LEER ESTO PRIMERO.
--
-- Son CINCO consultas separadas, y el SQL Editor de Supabase solo muestra el
-- resultado de la ÚLTIMA cuando le das Run a todo. Así que van de a una:
--
--   1. Pega el archivo completo en el SQL Editor.
--   2. SELECCIONA con el mouse el bloque que quieres correr —desde su título
--      hasta el punto y coma— y recién ahí dale Run (o ⌘+Enter).
--   3. Repite con el siguiente bloque.
--
-- Cuando hay texto seleccionado, el editor corre solo eso. Es la forma de ver
-- los cinco resultados sin que se pisen entre ellos.
--
-- Ninguna de las cinco escribe nada. Son SELECT: se pueden correr las veces
-- que haga falta, en cualquier orden, sin riesgo.
--
-- ⚠️  EL RESULTADO ES INFORMACIÓN PERSONAL. Nombres, DNI, fechas de nacimiento
--     y remuneraciones. No pegar la salida en git, ni en un chat, ni en este
--     repositorio. Va directo a la aseguradora por el canal que Felipe decida.
--     Este archivo sí puede vivir en git porque solo contiene la consulta.
-- ============================================================================


-- ── 1 · Cómo se reparte el equipo por vínculo ───────────────────────────────
-- Se lee primero: da el tamaño de cada grupo. Al seguro va solo 'planilla'
-- (ver el encabezado). Las cuentas de servicio no se cuentan: no son personas.
--
-- `en_planilla` es una columna DERIVADA (migración 0085): vale true para
-- tipo_vinculo 'planilla' y 'prueba'. Se desagrega a propósito.

select
  coalesce(p.tipo_vinculo, '(sin definir)')            as tipo_de_vinculo,
  p.estado,
  count(*)                                              as personas,
  count(*) filter (where p.fecha_cese is not null)      as con_fecha_de_cese
from personas p
where not p.cuenta_de_servicio
group by 1, 2
order by 1, 2;


-- ── 2 · La lista que tiene que estar declarada a Pacífico ───────────────────
-- Las personas en planilla hoy (criterio de Felipe, 2026-10-21: solo 'planilla').
--
-- Quedan fuera:
--   · 'prueba'         → decisión de Felipe; ver la objeción en el encabezado
--   · 'rxh'            → contrato civil, no hay vínculo laboral
--   · 'practicante'    → modalidad formativa, tiene su propio seguro (FOLA)
--   · 'no_trabajador'  → accionistas y otras filas sin vínculo
--   · cuentas de servicio → estaciones de retail, no son personas (0490)
--   · estado inactivo o con fecha de cese cumplida → ya no trabajan

select
  p.apellidos || ', ' || p.nombres                     as trabajador,
  coalesce(dp.nombre_dni, '⚠ falta nombre según DNI')  as nombre_segun_dni,
  coalesce(p.documento, '⚠ FALTA DNI')                 as documento,
  dp.fecha_nacimiento,
  p.fecha_ingreso,
  s.codigo                                             as sede,
  p.tipo_vinculo,
  p.sueldo_base_legal                                  as remuneracion_asegurable
from personas p
join sedes s                on s.id = p.sede_base_id
left join datos_personales dp on dp.persona_id = p.id
where p.estado = 'activo'
  and p.tipo_vinculo = 'planilla'
  and not p.cuenta_de_servicio
  and (p.fecha_cese is null or p.fecha_cese > current_date)
order by p.apellidos, p.nombres;


-- ── 3 · Lo que la aseguradora va a pedir y hoy no tenemos ───────────────────
-- Un dato faltante no es un detalle administrativo: sin DNI o sin fecha de
-- nacimiento la aseguradora no emite el certificado individual, y esa persona
-- se queda fuera de la póliza sin que nadie lo note hasta que haga falta.
--
-- Si esto devuelve cero filas, la lista del punto 2 se puede enviar tal cual.

select
  p.apellidos || ', ' || p.nombres  as trabajador,
  case when p.documento is null        then 'sin DNI'                    end as falta_documento,
  case when dp.persona_id is null      then 'sin ficha personal'         end as falta_ficha,
  case when dp.fecha_nacimiento is null then 'sin fecha de nacimiento'   end as falta_nacimiento,
  case when p.sueldo_base_legal is null then 'sin remuneración declarada' end as falta_sueldo
from personas p
left join datos_personales dp on dp.persona_id = p.id
where p.estado = 'activo'
  and p.tipo_vinculo = 'planilla'
  and not p.cuenta_de_servicio
  and (p.fecha_cese is null or p.fecha_cese > current_date)
  and (p.documento is null
       or dp.persona_id is null
       or dp.fecha_nacimiento is null
       or p.sueldo_base_legal is null)
order by p.apellidos, p.nombres;


-- ── 4 · La suma asegurada que CAYLA está cubriendo ──────────────────────────
-- No es un dato para la aseguradora: es para que Felipe vea el tamaño del
-- riesgo que la póliza cierra, y contra eso mida la prima mensual de Pacífico.
--
-- El capital del D.Leg. 688 se calcula sobre la remuneración mensual: 16 sueldos
-- por muerte natural, 32 por muerte accidental o invalidez total y permanente.
-- La cifra de abajo es el escenario de un solo siniestro, no la suma de todos.

select
  count(*)                                   as trabajadores_a_cubrir,
  sum(p.sueldo_base_legal)                   as masa_remunerativa_mensual,
  max(p.sueldo_base_legal) * 16              as maximo_por_muerte_natural,
  max(p.sueldo_base_legal) * 32              as maximo_por_accidente_o_invalidez
from personas p
where p.estado = 'activo'
  and p.tipo_vinculo = 'planilla'
  and not p.cuenta_de_servicio
  and (p.fecha_cese is null or p.fecha_cese > current_date);

-- Hasta el 2026-10-21 había una quinta columna, `prima_mensual_en_pct_de_la_masa`,
-- que dividía S/170 (la cotización de La Positiva) entre esta masa. Se quitó: la
-- prima de Pacífico es otra y no está en este repo (sale de las condiciones
-- particulares o de la factura). El porcentaje se calcula a mano:
-- prima mensual real ÷ masa_remunerativa_mensual × 100. Una referencia SIN
-- VERIFICAR, de una sesión anterior: la prima de este seguro se cotizaría como
-- porcentaje de la remuneración asegurable, entre 0.53 % y 0.75 % mensual.
--
-- Y recordar lo que Dante confirmó: en este seguro no hay comisión de corredor,
-- se paga directo a la aseguradora. Cualquier intermediario que aparezca
-- cobrando una comisión está cobrando algo que el reglamento no contempla.


-- ── 5 · Cruce contra los certificados de Pacífico ───────────────────────────
-- Responde dos cosas. A) Quién está en planilla y NO tiene certificado: hay que
-- declararlo o pedirle el certificado a Pacífico. B) Quién tiene certificado y
-- hoy NO figura en planilla activa: sobra en la declaración, o cambió de
-- vínculo. Se corre cada mes, después de declarar a Pacífico.
--
-- ⚠️  ANTES DE CORRERLA: reemplaza la fila de ejemplo por los DNI de los
--     certificados que tengas (uno por línea, entre comillas, con coma al
--     final salvo en la última). Ese DNI es información personal: NO guardes
--     el archivo con ellos ni lo subas a git.
--
-- Se compara por documento. Si una misma persona sale en A y en B, el documento
-- está escrito distinto (espacios, ceros): se corrige en la ficha, no aquí.

with certificados(documento) as (
  values
    ('00000000')   -- ← fila de ejemplo: bórrala y pon los DNI reales
),
en_planilla as (
  select p.id, p.apellidos, p.nombres, trim(p.documento) as documento,
         p.tipo_vinculo, s.codigo as sede, p.fecha_ingreso, p.sueldo_base_legal
  from personas p
  join sedes s on s.id = p.sede_base_id
  where p.estado = 'activo'
    and p.tipo_vinculo = 'planilla'
    and not p.cuenta_de_servicio
    and (p.fecha_cese is null or p.fecha_cese > current_date)
)
select 'A · EN PLANILLA SIN CERTIFICADO'                            as situacion,
       e.apellidos || ', ' || e.nombres                             as persona,
       coalesce(e.documento, '⚠ FALTA DNI')                         as documento,
       e.sede, e.tipo_vinculo, e.fecha_ingreso,
       e.sueldo_base_legal,
       e.sueldo_base_legal * 16                                     as capital_muerte_natural,
       e.sueldo_base_legal * 32                                     as capital_accidente_o_invalidez,
       case when dp.persona_id is null then 'sin ficha personal'
            when dp.fecha_nacimiento is null then 'sin fecha de nacimiento' end as dato_que_falta
from en_planilla e
left join datos_personales dp on dp.persona_id = e.id
where not exists (select 1 from certificados c where c.documento = e.documento)
union all
select 'B · CERTIFICADO SIN PLANILLA HOY',
       coalesce(p.apellidos || ', ' || p.nombres, '(no está en el sistema)'),
       c.documento,
       null, coalesce(p.tipo_vinculo, '—') || ' / ' || coalesce(p.estado::text, '—'), p.fecha_ingreso,
       null, null, null, null
from certificados c
left join personas p on trim(p.documento) = c.documento
where not exists (select 1 from en_planilla e where e.documento = c.documento)
order by 1, 2;
