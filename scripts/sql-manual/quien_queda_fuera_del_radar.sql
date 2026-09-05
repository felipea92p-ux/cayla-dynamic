-- ============================================================================
-- quien_queda_fuera_del_radar.sql
-- ============================================================================
-- QUÉ RESPONDE
--   A quién NO le mide tardanzas el semáforo disciplinario, y por cuál de las
--   dos razones. No escribe nada: solo lee.
--
-- POR QUÉ HACE FALTA
--   `fn_tardanzas_resumen` filtra por DOS columnas distintas que es fácil
--   confundir, y significan cosas opuestas:
--
--     en_planilla = false   → NO tiene jornada. Es RxH (locación de servicios).
--                             Excluirla es CORRECTO y ya está resuelto: desde la
--                             0191 el sistema ni siquiera le mide la hora de
--                             entrada. Medirle tardanza a un locador es, además,
--                             un indicio de laboralidad en su contra.
--
--     sueldo_fijo = true    → SÍ tiene jornada; lo que no depende de las horas
--                             es su pago. Excluirla del radar disciplinario es
--                             una DECISIÓN, y hoy está tomada en un solo lado:
--                             el semáforo la esconde, pero
--                             fn_expediente_generar_tardanza no la filtra, así
--                             que se le podría emitir un memo que el semáforo
--                             nunca mostró.
--
--   Antes de decidir hay que saber a cuántas personas afecta cada caso. Puede
--   que la columna `sueldo_fijo` no filtre a nadie y la decisión sea vacía.
--
-- CÓMO SE LEE
--   `motivo` dice por qué queda fuera. Si ninguna fila dice
--   «sueldo_fijo — decisión pendiente», no hay nada que decidir: basta con
--   alinear las dos funciones y seguir.
-- ============================================================================

select
  pe.nombres || ' ' || pe.apellidos as persona,
  s.codigo                         as sede,
  pe.tipo_vinculo,
  pe.en_planilla,
  pe.sueldo_fijo,
  pe.personal_direccion,
  case
    when pe.en_planilla is not true then 'RxH / sin jornada — exclusión correcta (0191)'
    when pe.sueldo_fijo             then 'sueldo_fijo — DECISIÓN PENDIENTE'
  end as motivo,
  -- Cuántos días con tardanza medible tiene registrados aun estando fuera del
  -- radar. Si es 0 para todas, la decisión no cambia nada en la práctica.
  (select count(*) from jornadas j
    where j.persona_id = pe.id
      and j.fecha >= (now() at time zone 'America/Lima')::date - 180
      and j.minutos_tarde is not null
      and j.minutos_tarde > 0
      and j.minutos_tarde <= 180) as dias_con_tardanza_180d
from personas pe
join sedes s on s.id = pe.sede_base_id
where pe.estado = 'activo'
  and (pe.en_planilla is not true or pe.sueldo_fijo)
order by 7, 1;
