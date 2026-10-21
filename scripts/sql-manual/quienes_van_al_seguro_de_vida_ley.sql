-- ============================================================================
-- ¿Quiénes tienen que estar en la póliza del Seguro de Vida Ley?
--
-- PARA QUÉ. La cotización de La Positiva (agosto 2026) habla de 19 personas.
-- El diseño remunerativo del sistema asume 26. Antes de firmar hay que saber si
-- esa diferencia son personas que legítimamente no van (recibo por honorarios,
-- accionistas, cesadas) o si hay gente trabajando que quedaría sin cobertura.
--
-- POR QUÉ IMPORTA EL NÚMERO EXACTO. El D.Leg. 688, con la modificación del
-- D.U. 044-2019, hace obligatorio el seguro DESDE EL PRIMER DÍA de trabajo. Si
-- una persona en planilla queda fuera de la póliza y fallece o queda inválida,
-- el capital lo paga CAYLA de su patrimonio: 16 remuneraciones por muerte
-- natural, 32 por muerte accidental o invalidez total y permanente. Sobre una
-- base de S/1,130 son S/18,080 y S/36,160 respectivamente, por persona.
--
-- Ese riesgo no se cubre hacia atrás: ninguna aseguradora vende cobertura
-- retroactiva. La única forma de cerrarlo es que la póliza salga completa.
--
-- CÓMO SE CORRE — LEER ESTO PRIMERO.
--
-- Son CUATRO consultas separadas, y el SQL Editor de Supabase solo muestra el
-- resultado de la ÚLTIMA cuando le das Run a todo. Así que van de a una:
--
--   1. Pega el archivo completo en el SQL Editor.
--   2. SELECCIONA con el mouse el bloque que quieres correr —desde su título
--      hasta el punto y coma— y recién ahí dale Run (o ⌘+Enter).
--   3. Repite con el siguiente bloque.
--
-- Cuando hay texto seleccionado, el editor corre solo eso. Es la forma de ver
-- los cuatro resultados sin que se pisen entre ellos.
--
-- Ninguna de las cuatro escribe nada. Son SELECT: se pueden correr las veces
-- que haga falta, en cualquier orden, sin riesgo.
--
-- ⚠️  EL RESULTADO ES INFORMACIÓN PERSONAL. Nombres, DNI, fechas de nacimiento
--     y remuneraciones. No pegar la salida en git, ni en un chat, ni en este
--     repositorio. Va directo a la aseguradora por el canal que Felipe decida.
--     Este archivo sí puede vivir en git porque solo contiene la consulta.
-- ============================================================================


-- ── 1 · De dónde sale la diferencia con el 19 ───────────────────────────────
-- Se lee primero. Si acá cuadra 19, no hay nada más que hacer.
--
-- `en_planilla` es una columna DERIVADA (migración 0085): vale true para
-- tipo_vinculo 'planilla' y 'prueba'. Se desagrega a propósito, porque para el
-- seguro los dos casos van juntos y para las provisiones no.

select
  coalesce(p.tipo_vinculo, '(sin definir)')            as tipo_de_vinculo,
  p.estado,
  count(*)                                              as personas,
  count(*) filter (where p.fecha_cese is not null)      as con_fecha_de_cese
from personas p
where not p.cuenta_de_servicio                          -- una estación de retail no es una persona (0490)
group by 1, 2
order by 1, 2;


-- ── 2 · La lista que va a la aseguradora ────────────────────────────────────
-- Todas las personas con vínculo laboral vivo hoy. Incluye 'prueba' A PROPÓSITO:
-- la obligación del seguro nace de la prestación efectiva de servicios, no del
-- tipo de contrato ni de la formalización. Quien viene a trabajar está cubierto
-- desde su primer día, y el D.Leg. 688 no distingue por modalidad.
--
-- Quedan fuera, y está bien que queden fuera:
--   · 'rxh'            → contrato civil, no hay vínculo laboral
--   · 'no_trabajador'  → accionistas
--   · cuenta_de_servicio → las «ESTACIÓN — …» de retail: son una caja o un
--                          almacén compartido, no una persona (0490). Desde la
--                          0544 nacen 'no_trabajador'; el filtro sigue por si
--                          alguna quedó en planilla de antes (el 2026-10-21 la
--                          de Producción hizo salir 21 «a cubrir» cuando eran 20).
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
  and p.en_planilla                                     -- planilla + prueba
  and not p.cuenta_de_servicio                          -- una estación de retail no es una persona (0490)
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
  and p.en_planilla
  and not p.cuenta_de_servicio                          -- una estación de retail no es una persona (0490)
  and (p.fecha_cese is null or p.fecha_cese > current_date)
  and (p.documento is null
       or dp.persona_id is null
       or dp.fecha_nacimiento is null
       or p.sueldo_base_legal is null)
order by p.apellidos, p.nombres;


-- ── 4 · La suma asegurada que CAYLA está cubriendo ──────────────────────────
-- No es un dato para la aseguradora: es para que Felipe vea el tamaño del
-- riesgo que la póliza cierra, y contra eso mida los S/170 mensuales.
--
-- El capital del D.Leg. 688 se calcula sobre la remuneración mensual: 16 sueldos
-- por muerte natural, 32 por muerte accidental o invalidez total y permanente.
-- La cifra de abajo es el escenario de un solo siniestro, no la suma de todos.

select
  count(*)                                   as trabajadores_a_cubrir,
  sum(p.sueldo_base_legal)                   as masa_remunerativa_mensual,
  max(p.sueldo_base_legal) * 16              as maximo_por_muerte_natural,
  max(p.sueldo_base_legal) * 32              as maximo_por_accidente_o_invalidez,
  round(170.0 / nullif(sum(p.sueldo_base_legal), 0) * 100, 3)
                                             as prima_mensual_en_pct_de_la_masa
from personas p
where p.estado = 'activo'
  and p.en_planilla
  and not p.cuenta_de_servicio                          -- una estación de retail no es una persona (0490)
  and (p.fecha_cese is null or p.fecha_cese > current_date);

-- Sobre la última columna: la prima del Seguro de Vida Ley se cotiza como un
-- porcentaje de la remuneración asegurable, y el mercado peruano se mueve
-- aproximadamente entre 0.53 % y 0.75 % mensual. Si el número sale cerca o por
-- encima de 0.75 %, hay margen para pedir cotización a Pacífico, Rímac o Mapfre
-- antes de firmar. Si sale por debajo de 0.60 %, la de La Positiva está bien y
-- no vale la pena gastar dos semanas en comparar.
--
-- Y recordar lo que Dante confirmó: en este seguro no hay comisión de corredor,
-- se paga directo a la aseguradora. Cualquier intermediario que aparezca
-- cobrando una comisión está cobrando algo que el reglamento no contempla.
