-- ============================================================================
-- ¿HAY AUSENCIAS QUE VAN A PAGAR CERO POR FALTARLES LA FIRMA DE DO?
-- ============================================================================
-- Solo LEE. Un solo select. Devuelve siempre una fila. Se pega en el SQL Editor.
--
-- POR QUÉ EXISTE, Y POR QUÉ JUSTO ESTE MES.
--
-- Hasta hace unos días, registrar un descanso médico o una maternidad bastaba
-- para que se pagaran. Desde la **0306** (26/08) y la **0314** (26/08) ya no:
-- sin la aprobación de Desarrollo Organizacional, esos días valen S/0.00. Es la
-- decisión correcta —la firma de DO es la que convierte días en plata— pero la
-- regla NACIÓ DENTRO DE ESTE MISMO PERIODO. Lo que el 20 de agosto se pagaba
-- solo, el 28 puede salir en cero.
--
-- Y no avisa nadie: la pantalla de Planilla no lo dice, y `fn_planilla_congelar`
-- no lo frena. El cierre saldría adelante sin protestar.
--
-- OJO: `antes_de_cerrar_el_mes.sql` NO cubre esto. Su chequeo 9 mira la
-- condición VIEJA —«¿es de un tipo que paga?»— así que grita por ausencias que
-- hoy se pagan perfectamente y se calla ante las que no. Esta consulta mira la
-- condición que de verdad decide.
--
-- CÓMO SE LEE
--
--   periodo   → tiene que decir 2026-07-29 -> 2026-08-28 (abierto).
--               Si dice otra cosa, PARA: el resto de la fila no significa nada.
--
--   veredicto = «OK - ninguna…»
--     → nada que hacer. Es el desenlace esperado.
--
--   veredicto = «OJO - N ausencia(s) SIN FIRMA DE DO»
--     → esas personas cobrarán S/0.00 por esos días. Una por una:
--        · si corresponde pagarla, que DO la apruebe en /admin/ausencias
--          (botón «Aprobar») ANTES de marcar el mes como pagado, y volver a
--          correr esta consulta hasta que diga OK;
--        · si NO corresponde, dejarla sin firmar — S/0.00 es su resultado
--          correcto — y anotarlo para que nadie la apruebe por inercia.
--     Si DO firma tarde, el mes cerrado NO se toca: la diferencia va como
--     retroactivo del periodo siguiente.
--
--   esas_si_se_pagan → informativo. Son las que están bien. Sirve para
--                      distinguirlas del ruido que da el chequeo 9 del otro
--                      archivo, que las nombra como si fueran un problema.
-- ============================================================================

with per as (
  select fecha_ini, fecha_fin, estado
  from periodos_planilla
  where (now() at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  order by fecha_ini desc limit 1
),
aus as (
  select pe.apellidos || ', ' || pe.nombres          as quien,
         t.nombre                                     as tipo,
         a.fecha_inicio, a.fecha_fin,
         (t.requiere_aprobacion and a.aprobada_at is null) as paga_cero
  from ausencias a
  join per d on a.fecha_inicio <= d.fecha_fin and a.fecha_fin >= d.fecha_ini
  join personas pe on pe.id = a.persona_id
  join tipos_ausencia t on t.codigo = a.tipo
  where a.anulada_at is null
    and t.paga is true
    and pe.en_planilla is true
)
select
  coalesce((select fecha_ini::text || ' -> ' || fecha_fin::text || '  (' || estado || ')' from per),
           'NO HAY PERIODO VIGENTE HOY - parate aqui')                       as periodo,

  case when not exists (select 1 from per)
         then 'NO HAY PERIODO VIGENTE HOY - parate aqui'
       when (select count(*) from aus where paga_cero) = 0
         then 'OK - ninguna ausencia pagable se queda sin la firma de DO'
       else 'OJO - ' || (select count(*) from aus where paga_cero)::text
            || ' ausencia(s) SIN FIRMA DE DO: esas saldran S/0.00' end       as veredicto,

  coalesce((select string_agg(quien || ' | ' || tipo || ' ' || fecha_inicio::text
                              || ' a ' || fecha_fin::text, '   -   ' order by quien)
            from aus where paga_cero), 'nadie')                              as sin_firma_pagan_cero,

  coalesce((select string_agg(quien || ' | ' || tipo || ' ' || fecha_inicio::text
                              || ' a ' || fecha_fin::text, '   -   ' order by quien)
            from aus where not paga_cero), 'ninguna')                        as esas_si_se_pagan;
