-- ============================================================================
-- 0385 · Quién está trabajando sin horario vigente
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_personas_sin_horario_vigente(p_dias)` devuelve las personas que tienen
--   jornadas registradas en los últimos `p_dias` días **y a las que sí les
--   corresponde llevar horario**, pero que no tienen ninguno vigente en esas
--   fechas. Por cada una: cuántos días, el primero, el último, y si nunca tuvo
--   horario o se le abrió un hueco entre dos tramos.
--   No escribe nada: es una pregunta, no una corrección.
--
-- EL CASO REAL (producción, 2026-09-06)
--   Al revisar por qué un día decía «descanso (sin horario vigente)» salieron
--   16 personas con 127 días de jornada sin horario vigente en 60 días — unas
--   800 horas. Nadie lo sabía porque el sistema no lo dice en ninguna parte: el
--   único sitio donde asomaba era una línea gris, dentro de la pantalla de
--   Correcciones, y solo si alguien abría justo ese día de justo esa persona.
--
--   Dos formas distintas, que esta función distingue con `nunca_tuvo_horario`:
--     · el hueco entre tramos — el horario viejo terminó y el nuevo empezó unos
--       días después. Son 1-4 días y casi siempre a varias personas de la misma
--       sede a la vez, porque el cambio de horario se hace por tienda.
--     · nunca se le cargó ninguno.
--
-- POR QUÉ IMPORTA, Y NO ES SOLO COSMÉTICO
--   Cinco bloques de `fn_planilla_calcular` cuentan «días que le tocaba
--   trabajar» leyendo `horarios_asignados` (líneas 1180, 1251, 1358, 1455 y
--   1698 de la 0339). Sin horario vigente esa cuenta da CERO, y entonces un
--   descanso médico aprobado o una licencia con goce **se pagan en cero**. No
--   falla nada, no hay error: sale una boleta con un número más bajo.
--   Esta función no arregla ese cálculo — lo hace visible antes de que llegue
--   a una boleta, que es la mitad que se puede entregar sin tocar plata.
--
-- QUÉ ASUME, Y ES LA PARTE QUE MÁS SE PENSÓ
--   Que hay gente a la que NO le corresponde horario, y que meterla aquí
--   convertiría el aviso en ruido permanente — el mismo defecto que la 0384
--   acaba de arreglar en la lista de días por revisar. Se excluyen ANTES de
--   contar, nunca después (es la regla de la casa sobre falsos positivos):
--
--     · `tipo_vinculo in ('rxh','no_trabajador')` — un locador de servicios no
--       tiene jornada que cumplir; ese es justamente el rasgo del vínculo.
--     · `personal_direccion` — art. 5 del D.S. 007-2002-TR: el personal de
--       dirección está excluido de la jornada máxima. Se usa la columna propia
--       (0187) y NO el rol del sistema: darle admin a alguien para otra cosa no
--       puede quitarle su jornada.
--
--   Comprobado con Felipe el 2026-09-06: en Central hay dos personas sin
--   horario a propósito, una por RxH y otra por dirección. Sin estas dos
--   exclusiones el aviso nacería con dos falsos positivos permanentes de los 16
--   casos, y un aviso que chilla todos los días por algo correcto se aprende a
--   ignorar antes de que llegue el caso que sí importa.
--
--   Un practicante NO se excluye, aunque `en_planilla` sea false para él: tiene
--   convenio, jornada y tope de horas. Por eso la exclusión enumera los dos
--   vínculos sin jornada en vez de apoyarse en `en_planilla`, que respondería
--   otra pregunta.
--
-- POR QUÉ MIRA `jornadas` Y NO `personas`
--   Porque lo que interesa no es «a quién le falta el horario» sino «quién está
--   TRABAJANDO sin él». Alguien de vacaciones todo el mes, o que aún no empieza,
--   no tiene ningún problema que resolver hoy. Mide el daño, no el formulario.
--
-- CÓMO SE REVIERTE
--   `drop function fn_personas_sin_horario_vigente(integer);` — nada más
--   depende de ella salvo la banda de la Bandeja, que falla suave.
-- ============================================================================

DROP FUNCTION IF EXISTS public.fn_personas_sin_horario_vigente(integer);

CREATE FUNCTION public.fn_personas_sin_horario_vigente(p_dias integer DEFAULT 60)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, dias integer,
               primer_dia date, ultimo_dia date, nunca_tuvo_horario boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with dias_huerfanos as (
    select j.persona_id,
           (p.nombres || ' ' || p.apellidos) as nombre,
           s.codigo as sede,
           j.fecha
    from jornadas j
    join personas p on p.id = j.persona_id
    join sedes    s on s.id = p.sede_base_id
    where j.fecha >= fn_hoy_lima() - greatest(p_dias, 1)
      and j.fecha <= fn_hoy_lima()
      and p.estado = 'activo'
      -- Las exclusiones van AQUÍ, antes de contar. Ver el encabezado.
      and p.tipo_vinculo not in ('rxh', 'no_trabajador')
      and p.personal_direccion is not true
      and not exists (
        select 1 from horarios_asignados h
        where h.persona_id = j.persona_id
          and h.vigente_desde <= j.fecha
          and (h.vigente_hasta is null or h.vigente_hasta >= j.fecha)
      )
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona()))
  )
  select d.persona_id,
         d.nombre,
         d.sede,
         count(*)::int as dias,
         min(d.fecha)  as primer_dia,
         max(d.fecha)  as ultimo_dia,
         -- Distingue las dos formas: sin ningún tramo nunca se le cargó horario;
         -- con tramos, lo que hay es un hueco entre dos de ellos.
         not exists (
           select 1 from horarios_asignados ha where ha.persona_id = d.persona_id
         ) as nunca_tuvo_horario
  from dias_huerfanos d
  group by d.persona_id, d.nombre, d.sede
  order by count(*) desc, d.nombre;
$function$;
grant execute on function fn_personas_sin_horario_vigente(integer) to authenticated;
revoke execute on function fn_personas_sin_horario_vigente(integer) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (385, 'quien_trabaja_sin_horario_vigente')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
