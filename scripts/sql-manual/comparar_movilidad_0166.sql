-- ############################################################################
-- ####  COMPARACIÓN ANTES / DESPUÉS DE LA 0166 — SOLO LEE, NO ESCRIBE     ####
-- ############################################################################
--
-- PARA QUÉ
--   Ver, sobre los datos reales de producción, qué movilidad está cobrando hoy
--   cada persona — y volver a verlo después de pegar la 0166 para
--   comparar fila por fila. La 0166 mueve plata; esto es la prueba de que mueve
--   solo la que debe.
--
-- CÓMO SE USA
--   1. Pega esto en el SQL Editor ANTES de aplicar la 0166. Copia el resultado
--      (o toma captura). Esa es la foto del «antes».
--   2. Pega la 0166:  ./scripts/dame-el-sql.sh 166
--      (aplicar_0166.sql se borró el 2026-08-08 — llevaba un cuerpo viejo de
--       fn_planilla_calcular. El script avisa de eso antes de entregártela.)
--   3. Vuelve a pegar esto. Compara.
--
-- QUÉ DEBERÍA CAMBIAR, y NADA MÁS
--   · ESTEFANY  → tarifa 10.00 (hoy sale un monto sin criterio)
--   · FELIPE    → movilidad 0.00
--   · Quien esté en una sede SIN tarifa propia → pasa a 0.00
--       (hoy cobra el pasaje de otra ciudad; ver el punto 3 de la migración 0166)
--   · TODOS LOS DEMÁS → exactamente el mismo número que antes
--
--   Si cambia alguien que no está en esa lista, NO SIGAS: avisa antes de
--   correr la planilla del mes.
--
-- POR QUÉ FUNCIONA ANTES Y DESPUÉS
--   Solo llama a `fn_planilla_calcular`, que existe en los dos momentos. No
--   menciona las columnas nuevas, así que no falla por no existir todavía.
--
-- NO LLEVA NOMBRES NI MONTOS DE NADIE: el archivo vive en git, los datos salen
-- al ejecutarlo y se quedan en tu pantalla.
-- ############################################################################

-- `fn_planilla_calcular` exige sesión de admin para saber quién calcula, y el
-- SQL Editor no la trae: sin esto responde «Solo un administrador o líder puede
-- calcular la planilla». Se le presta una, igual que hace
-- `a_quien_le_falta_firmar.sql`.
-- Solo lee: la planilla no escribe nada cuando se la llama sin periodo.
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and auth_user_id is not null limit 1), false) as _sesion_prestada;

-- Ajusta el mes si quieres mirar otro periodo.
with periodo as (
  select date_trunc('month', fn_hoy_lima())::date                       as ini,
         (date_trunc('month', fn_hoy_lima()) + interval '1 month - 1 day')::date as fin
),
filas as (
  select jsonb_array_elements(fn_planilla_calcular(p.ini, p.fin)->'filas') as f
  from periodo p
)
select
  f->>'nombre'                                as persona,
  f->>'sede'                                  as sede,
  -- De qué sede sale su tarifa. Distinto de la columna anterior solo para quien
  -- tenga sede física declarada (0166): ver de un vistazo por qué cobra lo que
  -- cobra, sin tener que abrir su ficha.
  coalesce(sf.codigo, f->>'sede')             as tarifa_de,
  (f->>'dias_trabajados')::numeric            as dias_asistidos,
  (f->>'movilidad_diaria')::numeric           as tarifa_por_dia,
  (f->>'monto_movilidad')::numeric            as movilidad_del_mes,
  -- POR QUÉ SALIÓ CERO. El orden NO es cosmético: primero las causas
  -- ESTRUCTURALES —las que valen todos los meses— y solo después las de este
  -- mes en particular.
  --
  -- Salió de una lectura real (2026-08-06): Catherine aparecía como «no tiene
  -- días asistidos», y es cierto que no los tiene, pero es RxH y no cobraría
  -- movilidad ni asistiendo todos los días. Ese mensaje mandaba a revisar su
  -- marcaje cuando no hay nada que revisar. Un diagnóstico que nombra la causa
  -- equivocada es peor que no dar ninguno.
  case
    when (f->>'monto_movilidad')::numeric > 0               then ''
    when not p.en_planilla                                  then
      'no devenga: ' || coalesce(p.tipo_vinculo, 'sin vínculo') || ' (0117)'
    when not coalesce(p.cobra_movilidad, true)              then
      coalesce(nullif(trim(p.movilidad_motivo), ''), 'excluida en su ficha, sin motivo escrito')
    when coalesce((f->>'movilidad_diaria')::numeric, 0) = 0 then 'su sede no tiene tarifa cargada'
    when (f->>'movilidad_sin_declaracion')::boolean         then 'le falta la declaración firmada'
    when coalesce((f->>'dias_trabajados')::numeric, 0) = 0  then 'este mes no asistió ningún día'
    else 'revisar: ningún motivo conocido explica el cero'
  end                                         as por_que_cero
from filas
join personas p on p.id = (f->>'persona_id')::uuid
left join sedes sf on sf.id = p.sede_fisica_id
order by (f->>'monto_movilidad')::numeric desc nulls last, f->>'nombre';
