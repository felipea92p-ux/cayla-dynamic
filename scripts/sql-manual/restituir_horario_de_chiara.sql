-- ############################################################################
-- ####  RESTITUIR EL HORARIO QUE SE VACIÓ DURANTE UN DESCANSO MÉDICO      ####
-- ############################################################################
--
-- Caso: Chiara Flores, 2026-08-14. Escribe en `horarios_asignados`.
-- Deja copia de seguridad ANTES de tocar nada. Reversible — abajo está cómo.
--
-- ── QUÉ PASÓ ────────────────────────────────────────────────────────────────
--
-- Se enfermó de dengue y le vaciaron el horario mientras estaba de baja:
--
--     26/07   45.0 h/semana  →  28.5 h      (−16.5 h)
--     27/07   28.5 h         →   6.0 h      (−22.5 h, solo sábado)
--     29/07   empieza el descanso médico, con certificado
--     03/08   termina el certificado
--     10/08   vuelve a lun–sáb
--
-- Y ahí se cierra el círculo: `fn_planilla_calcular` mira ese horario para saber
-- qué días le tocaba trabajar, y responde «solo el sábado». De los seis días de
-- su descanso médico le paga UNO. **La ausencia provocó el cambio de horario, y
-- el cambio de horario anuló el pago de la ausencia.**
--
-- Vaciar el horario de quien está de baja hace tres cosas a la vez, y ninguna se
-- ve: le quita el pago de la baja, apaga sus faltas y apaga sus tardanzas. Una
-- baja se registra como AUSENCIA, nunca tocando el horario.
--
-- ── POR QUÉ EMPIEZA EL 29 Y NO EL 26 ────────────────────────────────────────
--
-- Los días 26, 27 y 28 de julio NO tienen ninguna ausencia que los justifique
-- —su permiso fue solo el 25— y caen en el PERIODO ANTERIOR. Devolverle el
-- horario desde el 26 le abriría tres faltas dentro de un periodo ya cerrado.
--
-- La ventana es 29/07 → 09/08: su baja entera (descanso médico 29/07–03/08 más
-- el reposo 04/08–09/08), toda justificada por `justificaciones_asistencia`, y
-- toda dentro del periodo abierto que se cierra el 28 de agosto.
--
-- ── POR QUÉ SE MODIFICA UN TRAMO EN VEZ DE CERRARLO ─────────────────────────
--
-- Porque cerrarlo no serviría. El cálculo elige el horario así:
--
--     where ha.vigente_desde <= el_dia   order by ha.vigente_desde desc  limit 1
--
-- **Ignora `vigente_hasta`.** Un tramo cerrado sigue ganando para los días
-- posteriores a su `vigente_desde`. Así que para que esos días se midan contra
-- su jornada real hay que cambiar el contenido del tramo del 02/08 e insertar
-- uno nuevo que cubra del 29/07 al 01/08.
--
-- ── LA JORNADA QUE SE LE DEVUELVE ───────────────────────────────────────────
--
-- 45 h/semana en 6 días de 7.5 h (decisión de Felipe, 2026-08-14). Sale de sus
-- propios datos: `horas_semana_objetivo` = 45 y sus tramos del 12/07 y el 20/07
-- suman 45.00 h exactas. 45 / 6 = 7.5.
--
-- 07:45 → 16:15 con 60 min de refrigerio = 7.5 h. La hora de entrada es la suya
-- de siempre.
--
-- ── LO QUE CAMBIA EN SU PAGO ────────────────────────────────────────────────
--
-- Su descanso médico pasa de 1 día pagado a 4: el 30 y 31 de julio, el sábado 1
-- y el lunes 3. El 29 es feriado —ya se paga en su propia línea— y el domingo 2
-- no es laborable. Con la valoración de hoy son unos S/122 en vez de S/30.
-- ############################################################################

begin;

-- ── 1 · Copia de seguridad, antes de nada ───────────────────────────────────
create table if not exists respaldo_horarios_chiara_20260814 as
select h.* from horarios_asignados h
join personas p on p.id = h.persona_id
where p.nombres ilike 'Chiara%';

-- ── 2 · El tramo del 02/08 pasa a su jornada real ───────────────────────────
update horarios_asignados h
   set dias_laborables = array[1,2,3,4,5,6],
       hora_entrada    = time '07:45',
       hora_salida     = time '16:15',
       horario_por_dia = jsonb_build_object(
         '1', jsonb_build_object('e','07:45','s','16:15','r',60),
         '2', jsonb_build_object('e','07:45','s','16:15','r',60),
         '3', jsonb_build_object('e','07:45','s','16:15','r',60),
         '4', jsonb_build_object('e','07:45','s','16:15','r',60),
         '5', jsonb_build_object('e','07:45','s','16:15','r',60),
         '6', jsonb_build_object('e','07:45','s','16:15','r',60))
from personas p
where p.id = h.persona_id
  and p.nombres ilike 'Chiara%'
  and h.vigente_desde = date '2026-08-02';

-- ── 3 · Y un tramo nuevo para el 29/07 → 01/08 ──────────────────────────────
-- `vigente_hasta` NO puede quedar en null: hay un índice único que solo admite
-- un tramo abierto por persona, y el suyo es el del 10/08.
insert into horarios_asignados
  (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables,
   horas_semana_objetivo, horario_por_dia)
select p.id, date '2026-07-29', date '2026-08-01', time '07:45', time '16:15',
       60, 60, array[1,2,3,4,5,6], 45.00,
       jsonb_build_object(
         '1', jsonb_build_object('e','07:45','s','16:15','r',60),
         '2', jsonb_build_object('e','07:45','s','16:15','r',60),
         '3', jsonb_build_object('e','07:45','s','16:15','r',60),
         '4', jsonb_build_object('e','07:45','s','16:15','r',60),
         '5', jsonb_build_object('e','07:45','s','16:15','r',60),
         '6', jsonb_build_object('e','07:45','s','16:15','r',60))
from personas p
where p.nombres ilike 'Chiara%';

commit;

-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
-- delete from horarios_asignados h using personas p
--   where p.id = h.persona_id and p.nombres ilike 'Chiara%';
-- insert into horarios_asignados select * from respaldo_horarios_chiara_20260814;

-- ── Comprobación: día por día de su descanso médico ─────────────────────────
with dm as (
  select dd.d::date as dia, a.persona_id
  from ausencias a
  join personas p on p.id = a.persona_id
  join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
  where p.nombres ilike 'Chiara%'
    and a.tipo = 'descanso_medico' and a.anulada_at is null
)
select dm.dia,
       to_char(dm.dia, 'Dy')                                    as dia_semana,
       exists (select 1 from feriados f where f.fecha = dm.dia)  as es_feriado,
       hv.dias_laborables,
       case
         when hv.persona_id is null then 'SIN HORARIO'
         when hv.horario_por_dia is not null
           then case when hv.horario_por_dia ? (extract(dow from dm.dia)::int::text)
                     then 'le tocaba' else 'no le tocaba' end
         else case when extract(dow from dm.dia)::int = any(hv.dias_laborables)
                   then 'le tocaba' else 'no le tocaba' end
       end                                                      as le_tocaba,
       case
         when exists (select 1 from feriados f where f.fecha = dm.dia) then 'no (feriado, ya se paga aparte)'
         when hv.horario_por_dia ? (extract(dow from dm.dia)::int::text) then '✓ SE LE PAGA'
         else 'no (no laborable)'
       end                                                      as veredicto
from dm
left join lateral (
  select ha.* from horarios_asignados ha
  where ha.persona_id = dm.persona_id and ha.vigente_desde <= dm.dia
  order by ha.vigente_desde desc limit 1
) hv on true
order by dm.dia;
