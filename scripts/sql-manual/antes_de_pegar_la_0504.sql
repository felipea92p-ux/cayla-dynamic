-- ============================================================================
-- Antes de pegar la 0504 (los practicantes pasan de EsSalud al seguro FOLA)
--
-- PARA QUÉ. La 0504 quita el aporte de EsSalud a TODOS los practicantes de una
-- vez, y la póliza de Pacífico es nominal: cuatro pólizas, una por persona.
-- Quien sea practicante y no esté en una de las cuatro queda sin ningún seguro
-- (Ley 28518, art. 52.5). Esta consulta responde dos cosas, en un solo
-- resultado:
--
--   1. QUIÉNES SON los practicantes que no están cesados, para cruzarlos con
--      los cuatro nombres de las pólizas. Debe salir exactamente la misma gente.
--   2. QUÉ VERSIÓN corre hoy en producción de las dos funciones que la 0504
--      reescribe. El md5 se pide a producción y se vuelve a pedir justo antes de
--      entregar el SQL (CLAUDE.md): un md5 es una foto, no una garantía.
--
-- Referencia medida el 2026-10-02 (fn_planilla_calcular_nucleo): md5
-- 27dda4084d0efbad293c36d66a39adf7, 116375 caracteres, 0 retornos de carro,
-- marcador «CAMBIO 0495» en la posición 15443. fn_set_tipo_vinculo debe ser la
-- de la 0324: UNA sola versión, de dos argumentos, 2610 caracteres.
--
-- Solo LEE. No cambia nada. Sin datos personales dentro del archivo: los
-- nombres salen en pantalla, no están escritos aquí.
--
-- CÓMO SE CORRE. Pegar entero en el SQL Editor y dar Run: es un solo select.
-- ============================================================================
select clave, valor
  from (
    select 1 as o, 'nucleo · md5' as clave, md5(prosrc) as valor
      from pg_proc where proname = 'fn_planilla_calcular_nucleo'
    union all
    select 2, 'nucleo · largo', length(prosrc)::text
      from pg_proc where proname = 'fn_planilla_calcular_nucleo'
    union all
    select 3, 'nucleo · retornos de carro', (length(prosrc) - length(replace(prosrc, chr(13), '')))::text
      from pg_proc where proname = 'fn_planilla_calcular_nucleo'
    union all
    select 4, 'nucleo · posición de CAMBIO 0495', position('CAMBIO 0495' in prosrc)::text
      from pg_proc where proname = 'fn_planilla_calcular_nucleo'
    union all
    select 5, 'nucleo · ya trae el CAMBIO 0504', (position('CAMBIO 0504' in prosrc) > 0)::text
      from pg_proc where proname = 'fn_planilla_calcular_nucleo'
    union all
    select 6, 'set_tipo_vinculo · versiones', count(*)::text
      from pg_proc where proname = 'fn_set_tipo_vinculo'
    union all
    select 7, 'set_tipo_vinculo · md5', md5(prosrc)
      from pg_proc where proname = 'fn_set_tipo_vinculo'
    union all
    select 8, 'set_tipo_vinculo · largo', length(prosrc)::text
      from pg_proc where proname = 'fn_set_tipo_vinculo'
    union all
    select 9, 'set_tipo_vinculo · retornos de carro', (length(prosrc) - length(replace(prosrc, chr(13), '')))::text
      from pg_proc where proname = 'fn_set_tipo_vinculo'
    union all
    select 10,
           'practicante · ' || p.apellidos || ' ' || p.nombres,
           p.estado || ' · ' || coalesce(p.practicante_modalidad, 'sin modalidad')
             || ' · ingreso ' || coalesce(p.fecha_ingreso::text, 'sin fecha')
      from personas p
     where p.tipo_vinculo = 'practicante'
       and p.estado <> 'inactivo'
  ) t
 order by o, clave;
