-- ============================================================================
-- PARA PEGAR EN EL SQL EDITOR — cerrar los tramos de quien ya cesó
-- ============================================================================
-- QUÉ ARREGLA. Personas INACTIVAS que todavía tienen un tramo de salario o de
-- horario ABIERTO (`vigente_hasta is null`). Se les cierra con su propia
-- `fecha_cese`, que es lo que `fn_cesar_persona` habría hecho el día de su baja.
--
-- DE DÓNDE SALE EL DESAJUSTE. No fue un error de nadie: son bajas ANTERIORES a
-- la 0086. Esa migración regularizó a quienes ya estaban inactivos —les dedujo
-- la fecha de cese de su última jornada real y les puso el motivo
-- 'por_revisar', porque el motivo no se podía deducir— pero solo tocó la tabla
-- `personas`. Cerrar los tramos no era su trabajo, y desde entonces nadie lo
-- hizo: la pantalla de Equipo escribía `estado` a mano y ni siquiera llamaba a
-- `fn_cesar_persona` (arreglado el 2026-08-06).
--
-- QUÉ NO ES ESTO, Y CONVIENE SABERLO ANTES DE PEGARLO. **No corrige ningún
-- pago.** Se verificó contra el Postgres local, sobre las versiones vigentes:
--
--   · `fn_planilla_calcular` (0159) filtra `p.estado = 'activo'` en sus dos
--     consultas → a esta gente nunca se le calculó una planilla.
--   · `fn_provisiones` (0160) también → no se le provisionó nada.
--   · `fn_salarios_vigentes` **sí** las devuelve → esto es lo único que cambia:
--     hoy aparecen con un salario «vigente» meses después de haberse ido.
--
-- O sea: es dato sucio, no plata mal pagada. Se arregla porque un salario que
-- figura vigente para alguien que ya no está es exactamente el tipo de dato que
-- alguien va a creerse dentro de dos años, cuando nadie recuerde el caso.
--
-- QUÉ NO TOCA. A nadie activo: el `where` exige `estado = 'inactivo'` y una
-- `fecha_cese` no nula. Y no reabre ni mueve ningún tramo ya cerrado.
--
-- IDEMPOTENTE. Correrlo dos veces no hace nada la segunda: solo alcanza a los
-- tramos con `vigente_hasta is null`.
--
-- CÓMO SE REVIERTE. El paso 1 te da la lista exacta de lo que se va a tocar.
-- Guárdala antes de confirmar; para deshacer, volver a poner `vigente_hasta` en
-- null para esos mismos ids.
-- ============================================================================

-- ── 1 · Qué se va a tocar (mira esto ANTES) ───────────────────────────────
-- Una fila por tramo abierto de alguien que ya cesó. Si sale vacío, no hay nada
-- que arreglar y el resto del archivo sobra.
select 'salario' as que, a.id as tramo_id, p.id as persona_id,
       p.nombres, p.apellidos, p.fecha_cese as se_cerraria_el,
       a.vigente_desde, a.salario_mensual_soles
  from asignaciones_salario a
  join personas p on p.id = a.persona_id
 where p.estado = 'inactivo' and p.fecha_cese is not null
   and a.vigente_hasta is null
union all
select 'horario', h.id, p.id, p.nombres, p.apellidos, p.fecha_cese,
       h.vigente_desde, null
  from horarios_asignados h
  join personas p on p.id = h.persona_id
 where p.estado = 'inactivo' and p.fecha_cese is not null
   and h.vigente_hasta is null
 order by 4, 5, 1;


-- ── 2 · Un caso imposible que hay que descartar primero ───────────────────
-- Un tramo que EMPIEZA después del cese no se puede cerrar el día del cese: la
-- fila quedaría con vigente_hasta anterior a vigente_desde, que es un rango al
-- revés. Si esta consulta devuelve algo, NO sigas: esas filas se revisan una
-- por una, porque significan que a esa persona se le asignó un salario o un
-- horario después de haberse ido.
select 'salario' as que, a.id, p.nombres, p.apellidos,
       a.vigente_desde, p.fecha_cese
  from asignaciones_salario a
  join personas p on p.id = a.persona_id
 where p.estado = 'inactivo' and p.fecha_cese is not null
   and a.vigente_hasta is null and a.vigente_desde > p.fecha_cese
union all
select 'horario', h.id, p.nombres, p.apellidos, h.vigente_desde, p.fecha_cese
  from horarios_asignados h
  join personas p on p.id = h.persona_id
 where p.estado = 'inactivo' and p.fecha_cese is not null
   and h.vigente_hasta is null and h.vigente_desde > p.fecha_cese;


-- ── 3 · Cerrarlos ─────────────────────────────────────────────────────────
-- Dentro de una transacción para poder mirar el resultado antes de confirmarlo.
begin;

update asignaciones_salario a
   set vigente_hasta = p.fecha_cese
  from personas p
 where p.id = a.persona_id
   and p.estado = 'inactivo' and p.fecha_cese is not null
   and a.vigente_hasta is null
   and a.vigente_desde <= p.fecha_cese;   -- el caso del paso 2 se queda fuera

update horarios_asignados h
   set vigente_hasta = p.fecha_cese
  from personas p
 where p.id = h.persona_id
   and p.estado = 'inactivo' and p.fecha_cese is not null
   and h.vigente_hasta is null
   and h.vigente_desde <= p.fecha_cese;

-- Comprueba: esto tiene que devolver 0 filas.
select count(*) as quedan_abiertos
  from (
    select a.id from asignaciones_salario a join personas p on p.id = a.persona_id
     where p.estado = 'inactivo' and p.fecha_cese is not null and a.vigente_hasta is null
       and a.vigente_desde <= p.fecha_cese
    union all
    select h.id from horarios_asignados h join personas p on p.id = h.persona_id
     where p.estado = 'inactivo' and p.fecha_cese is not null and h.vigente_hasta is null
       and h.vigente_desde <= p.fecha_cese
  ) x;

-- Si está en 0: `commit;`   ·   si no: `rollback;`
-- No dejes la transacción abierta — bloquea filas para el resto del sistema.
commit;


-- ── 4 · Lo que este archivo NO arregla ────────────────────────────────────
-- El motivo de cese. Las bajas anteriores a la 0086 quedaron con
-- 'por_revisar', que quiere decir «no se pudo deducir», no «renunció». Sus
-- FECHAS sí son buenas (salen de su última jornada real). El motivo hay que
-- ponerlo a mano, uno por uno, y hoy no hay pantalla que lo haga: «Registrar
-- salida» solo actúa sobre quien está activa.
--
-- Es el dato que va a leer quien arme una liquidación o quien conteste una
-- inspección, así que conviene corregirlo mientras alguien todavía se acuerde
-- de por qué se fue cada una:
--
--   update personas set motivo_cese = 'renuncia'  -- o el que corresponda
--    where id = '<el uuid>' and estado = 'inactivo';
--
-- Los válidos (CHECK personas_motivo_cese_valido, 0086 + 0143):
--   renuncia · fin_contrato · fin_periodo_prueba · fin_servicio_rxh ·
--   mutuo_acuerdo · despido · por_revisar
--
-- Ojo con 'despido': afirma que la empresa terminó el vínculo CON CAUSA, y eso
-- exige carta de preaviso, seis días de descargo y carta de despido. Si el
-- contrato simplemente llegó a su fecha, el motivo es 'fin_contrato' y no exige
-- ninguno de esos papeles (ver la cabecera de la 0143).
