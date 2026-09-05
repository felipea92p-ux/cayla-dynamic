-- ============================================================================
-- 0200_el_semaforo_sabe_en_que_escalon_esta_cada_quien.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que la pantalla de Disciplina muestre a quien cruzó SU umbral, no un umbral
--   genérico. Quien tiene una suspensión vigente aparece con UNA tardanza,
--   porque desde ahí ya corresponde imputación de cargos.
--
-- QUÉ ASUME
--   Ningún permiso cambia. La escala legal (RIT art. 7 b/c/d) es la que ya
--   aplicaba el generador desde la 0059: esta migración no la cambia, la MUEVE.
--
--   Se asegura UNA columna, y no es capricho — ver «el seguro» más abajo.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
-- La pantalla y el generador del memo respondían dos preguntas distintas
-- creyendo responder la misma:
--
--   fn_tardanzas_resumen           lista a quien lleva 2+ este mes
--                                  y rotula «amonestación» a las 3
--   fn_expediente_generar_tardanza escala según el último memo VIGENTE:
--                                  3 sin antecedente · 2 tras amonestación
--                                  1 tras suspensión · imputación = se niega
--
-- Para quien arrastra una suspensión vigente el umbral real es UNA tardanza, y
-- la pantalla seguía pidiendo tres. Reproducido contra Postgres local dentro de
-- BEGIN … ROLLBACK, con una suspensión firmada el 30-jul y una sola tardanza
-- posterior:
--
--   tardanzas_del_mes | escalon                | umbral_real              | sale
--           1         | suspension · 30-Jul    | 0 → imputación de cargos |  NO
--
-- El expediente ya se podía generar y el semáforo decía «Nadie con tardanzas
-- relevantes este mes». Es el falso NEGATIVO simétrico del que persigue este
-- repositorio: aquí el sistema no acusa de más, deja de avisar. «Dynamic avisa,
-- nunca sanciona solo» — y en este caso no avisaba.
--
-- ── CÓMO SE ARREGLA, Y POR QUÉ ASÍ ──────────────────────────────────────────
--
-- NO copiando la escala a la segunda función. Dos copias de una regla es cómo
-- se arregla una y se olvida la otra — el defecto que este repositorio persigue
-- y, literalmente, la causa de este mismo hallazgo.
--
-- La escala se extrae a `fn_tardanza_escalon(persona)`, que responde de una vez
-- las cuatro cosas que dependen del historial: qué documento toca, cuántas
-- tardanzas hacen falta, desde qué fecha se cuenta (el corte del non bis in
-- idem) y si está bloqueado. Las DOS funciones la consumen. Si mañana cambia el
-- RIT, se cambia en un sitio.
--
-- ── QUÉ CAMBIA PARA CADA QUIEN ──────────────────────────────────────────────
--
--   Sin antecedente vigente   NADA. Sigue apareciendo a las 2 y rotulando
--                             «amonestación» a las 3. Es el caso de casi todo
--                             el equipo, y a propósito no se mueve.
--   Tras una amonestación     aparece con 1 (antes con 2) y rotula
--                             «suspensión» a las 2.
--   Tras una suspensión       aparece con 1 y rotula «imputación» con esa 1.
--   Con imputación vigente    aparece rotulado «bloqueado»: el generador se
--                             niega y la decisión es de Gerencia. Antes se
--                             mezclaba con los demás sin decirlo.
--
-- `fn_expediente_generar_tardanza` conserva EXACTAMENTE su comportamiento y sus
-- mensajes de error, palabra por palabra. Lo único que cambia es de dónde saca
-- los números. La prueba 155 lo fija.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, Y ES DELIBERADO ──────────────────────────
--
-- No toca el filtro `sueldo_fijo = false` de fn_tardanzas_resumen. Hay ahí una
-- divergencia real —el semáforo excluye a quien tiene sueldo fijo y el generador
-- NO, así que esa persona es invisible en la pantalla y sancionable desde la
-- base— pero quitarlo haría aparecer gente nueva en Disciplina de golpe. Es una
-- decisión de negocio, no una corrección; queda anotada en hallazgos-abiertos.
--
-- Tampoco toca los feriados. El hallazgo nº4 sigue abierto: un feriado trabajado
-- genera tardanza contra la hora normal de entrada, y ni el semáforo ni el
-- generador lo excluyen. Esta migración hace que esas tardanzas se vean ANTES,
-- lo que aumenta el valor de cerrar el nº4 — no lo sustituye.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Volviendo a pegar la 0189 (sus dos funciones son las de partida) y soltando
--   `fn_tardanza_escalon`. Revertir significa volver a pedir tres tardanzas en
--   pantalla a quien por escala ya le corresponde una imputación.
--
-- ── ⚠️ ANTES DE PEGAR: comprobar de dónde se partió ─────────────────────────
--   Las dos funciones que se reescriben vienen de la 0189. Confirma en el SQL
--   Editor que producción tiene ESA versión, no otra — el md5 se le pregunta a
--   producción, nunca se copia del local:
--
--     select proname, md5(prosrc) from pg_proc p
--       join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public'
--        and proname in ('fn_tardanzas_resumen', 'fn_expediente_generar_tardanza');
--
--   Debe devolver, si producción está en la 0189:
--     fn_tardanzas_resumen             928f45222dbff5e3a8546a76240ebaba
--     fn_expediente_generar_tardanza   4501814631800382c02cdd128b108971
--
--   Esos dos valores son los del Postgres LOCAL de esta Mac reconstruido desde
--   las migraciones. Sirven como referencia de «esto es la 0189», NO como prueba
--   de lo que hay en producción. Si no coinciden, para y mide la diferencia
--   antes de pegar nada.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Y `scripts/sql-manual/por_que_no_sale_en_disciplina.sql`
--   debe dejar de mostrar filas con `umbral_real = 0` y `sale_en_pantalla = f`.
-- ============================================================================

-- ── EL SEGURO: la columna que la pantalla va a pedir ────────────────────────
--
-- `suspension_fechas` la crea la 0075, y si esa migración NO está en producción
-- la columna no existe. Desde esta entrega la pantalla de Disciplina y la del
-- memo la piden en su `select`, y PostgREST no devuelve la columna que falta:
-- **falla la consulta entera**. El legajo se quedaría en blanco y el memo no
-- abriría — en una pantalla que se usa todos los días.
--
-- Se asegura acá, idempotente y con la MISMA sentencia que usa la 0075, así que
-- si la 0075 ya está esto no hace nada. No se copia ninguna función: eso sería
-- crear una segunda definición de la que `donde-vive.sh` avisa. Solo la columna,
-- que es lo único de lo que depende que la pantalla siga abriendo.
--
-- Las FUNCIONES de la 0075 (fn_dias_suspension, fn_expediente_set_suspension) NO
-- se aseguran acá a propósito: si faltan, el panel lo detecta (PGRST202), cae al
-- cálculo por calendario y lo dice en pantalla con todas sus letras. Un aviso
-- visible es mejor que una copia de la migración de otro.
alter table expediente_disciplinario
  add column if not exists suspension_fechas date[];

-- ── La escala, en un solo sitio ─────────────────────────────────────────────
-- RIT art. 7 b/c/d sobre D.S. 003-97-TR art. 25: la progresión es amonestación
-- → suspensión → imputación de cargos → (descargos, art. 31) → decisión. Un
-- antecedente deja de pesar a los 12 meses.
--
-- Devuelve también el CORTE (non bis in idem): las tardanzas de esa fecha o
-- anteriores ya se sancionaron y no se vuelven a contar.
create or replace function public.fn_tardanza_escalon(p_persona_id uuid)
returns table (nivel_siguiente text, minimo int, corte date, doc_previo uuid, bloqueado boolean)
language sql
stable security definer
set search_path = public
as $function$
  with prev as (
    select e.id, e.nivel, e.periodo_hasta,
           (e.firmado_at >= now() - interval '12 months') as vigente
    from expediente_disciplinario e
    where e.persona_id = p_persona_id
      and e.tipo_causal = 'tardanza'
      and e.estado in ('firmado', 'entregado')
    order by e.firmado_at desc
    limit 1
  )
  select
    -- Qué documento toca. Sin antecedente vigente —y también tras una llamada
    -- verbal, que no es escalón— se empieza por la amonestación escrita.
    case
      when p.vigente and p.nivel = 'imputacion'   then 'despido'
      when p.vigente and p.nivel = 'suspension'   then 'imputacion'
      when p.vigente and p.nivel = 'amonestacion' then 'suspension'
      else 'amonestacion'
    end,
    -- Cuántas tardanzas nuevas hacen falta. `null` = no hay número que valga:
    -- con una imputación vigente decide Gerencia, no el sistema.
    case
      when p.vigente and p.nivel = 'imputacion'   then null::int
      when p.vigente and p.nivel = 'suspension'   then 1
      when p.vigente and p.nivel = 'amonestacion' then 2
      else 3
    end,
    case when p.vigente then p.periodo_hasta end,
    p.id,
    coalesce(p.vigente and p.nivel = 'imputacion', false)
  from (select 1) _
  left join prev p on true;
$function$;

grant execute on function public.fn_tardanza_escalon(uuid) to authenticated;

-- ── fn_expediente_generar_tardanza · misma escala, ahora prestada ───────────
-- Comportamiento IDÉNTICO al de la 0189, mensajes de error incluidos palabra
-- por palabra. Lo único que cambia es que los números ya no viven aquí.
CREATE OR REPLACE FUNCTION public.fn_expediente_generar_tardanza(p_persona_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_esc       record;
  v_cutoff    date;
  v_n         int;
  v_hechos    jsonb;
  v_desde     date;
  v_hasta     date;
  v_id        uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  select * into v_esc from fn_tardanza_escalon(p_persona_id);

  if v_esc.bloqueado then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  end if;

  v_cutoff := coalesce(v_esc.corte, date '2000-01-01');

  -- tardanzas del MES en curso, POSTERIORES al cutoff, no levantadas (non bis in idem)
  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)
      and j.fecha <= fn_hoy_lima()
      -- `fn_tardanza_es_medible` reemplaza al viejo `is not null`: el papel
      -- disciplinario NUNCA se arma con una medición dudosa.
      and fn_tardanza_es_medible(j.minutos_tarde) and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  if v_n < v_esc.minimo then
    raise exception '%', case v_esc.nivel_siguiente
      when 'imputacion' then 'No corresponde: no hay tardanzas nuevas tras la suspensión.'
      when 'suspension' then format('Aún no corresponde suspensión: necesita 2 tardanzas nuevas tras la amonestación (lleva %s).', v_n)
      else format('Aún no corresponde amonestación: necesita 3 tardanzas en el mes (lleva %s).', v_n)
    end;
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_esc.nivel_siguiente, v_hechos, v_desde, v_hasta,
    v_esc.doc_previo,
    -- suspensión: default 1 día al día siguiente, EDITABLE antes de firmar
    case when v_esc.nivel_siguiente = 'suspension' then 1 else null end,
    case when v_esc.nivel_siguiente = 'suspension' then fn_hoy_lima() + 1 else null end,
    case when v_esc.nivel_siguiente = 'suspension' then fn_hoy_lima() + 1 else null end,
    null);

  return v_id;
end;
$function$;

-- ── fn_tardanzas_resumen · el semáforo deja de preguntar lo mismo a todos ───
-- Devuelve TABLE y gana dos columnas, así que hay que soltarla y recrearla: es
-- la segunda forma de definir que documenta donde-vive.sh.
-- Se sueltan LAS DOS firmas. La 0057 la creó SIN argumentos y la 0067 la
-- cambió a `(p_as_of date default null)`; desde entonces cada versión suelta
-- solo la de `(date)`. Si por lo que sea la de cero argumentos siguiera viva en
-- alguna base, convivirían dos sobrecargas y la llamada de la pantalla
-- —`rpc("fn_tardanzas_resumen", {})`— se volvería ambigua: PostgREST responde
-- PGRST203 «could not choose the best candidate function» y la lista se queda
-- vacía. Soltar la que ya no existe no cuesta nada; dejarla viva cuesta un
-- semáforo mudo.
drop function if exists public.fn_tardanzas_resumen();
drop function if exists public.fn_tardanzas_resumen(date);
CREATE OR REPLACE FUNCTION public.fn_tardanzas_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, tardanzas_mes integer, umbral text,
               ultima_fecha date, sin_medir integer, minimo integer, nivel_siguiente text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
           -- El corte y el escalón salen de la MISMA función que usa el
           -- generador. Antes el corte se recalculaba aquí con su propia
           -- subconsulta: dos sitios donde escribir la misma regla.
           esc.corte, esc.minimo, esc.nivel_siguiente, esc.bloqueado
    from personas pe
    join sedes s on s.id = pe.sede_base_id
    cross join lateral fn_tardanza_escalon(pe.id) esc
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  conteo as (
    select m.id as pid,
           count(distinct j.fecha) filter (
             where fn_tardanza_es_medible(j.minutos_tarde)) as n,
           -- Los días cuya tardanza pasa de tres horas. No suman al umbral legal
           -- —no se puede sancionar con una medición dudosa— pero no son
           -- invisibles.
           count(distinct j.fecha) filter (
             where not fn_tardanza_es_medible(j.minutos_tarde)) as sm,
           max(j.fecha) filter (
             where fn_tardanza_es_medible(j.minutos_tarde)) as ult
    from medibles m
    join jornadas j on j.persona_id = m.id
      and j.fecha >= date_trunc('month', coalesce(p_as_of, fn_hoy_lima()))::date
      and j.fecha <= coalesce(p_as_of, fn_hoy_lima())
      and (m.corte is null or j.fecha > m.corte)   -- no cuenta lo ya sancionado
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (
        select 1 from tardanzas_justificadas tj
        where tj.persona_id = m.id and tj.fecha = j.fecha)
    group by m.id
  )
  select m.id, m.nombre, m.sede, c.n::int,
    -- `umbral` deja de ser «amonestación o aviso» y pasa a nombrar el escalón
    -- ALCANZADO. Los tres consumidores comparaban contra 'amonestacion' para
    -- pintar el rojo; ahora comparan contra 'aviso'.
    case
      when m.bloqueado          then 'bloqueado'
      when c.n >= m.minimo      then m.nivel_siguiente
      else 'aviso'
    end as umbral,
    c.ult, c.sm::int, m.minimo, m.nivel_siguiente
  from medibles m join conteo c on c.pid = m.id
  -- Se asoma un escalón antes de su propio umbral, nunca por debajo de 1.
  -- Con mínimo 3 eso son 2, que es exactamente lo que hacía antes.
  where c.n >= greatest(coalesce(m.minimo, 1) - 1, 1) or c.sm > 0
  order by
    case when m.bloqueado then 2 when c.n >= m.minimo then 1 else 0 end desc,
    c.n desc, c.sm desc, m.nombre;
$function$;

-- ⚠️ EL GRANT VA AQUÍ Y NO ES OPCIONAL. Un `drop function` se lleva por delante
-- los permisos, y arriba hay uno obligatorio: la función devuelve TABLE y
-- Postgres no deja añadirle una columna con `create or replace`.
--
-- Esto ya pasó, y costó días de semáforo ciego. La 0189 hizo exactamente este
-- drop y no volvió a otorgar; el último `grant` de esta función era de la 0067.
-- Como el proyecto revoca el EXECUTE que Postgres da a PUBLIC por defecto, no
-- hubo red: `authenticated` dejó de poder ejecutarla, PostgREST devolvió error
-- y la pantalla lo imprimió como «Nadie con tardanzas relevantes este mes».
-- Ver la 0204, que es la que levantó las dos pantallas caídas.
grant execute on function public.fn_tardanzas_resumen(date) to authenticated;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (200, 'el_semaforo_sabe_en_que_escalon_esta_cada_quien')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- `desalineados` es el número que motivó la migración: personas activas cuyo
-- escalón ya permite generar el documento y que la regla vieja (n >= 2) no
-- mostraba. Después de pegar esto debe ser 0, porque ya no existe esa regla.
-- `en_escalon_avanzado` es cuánta gente arrastra un antecedente vigente, para
-- que el 0 signifique algo y no sea «no había a quién mirar».
with esc as (
  select pe.id,
         (fn_tardanza_escalon(pe.id)).*
  from personas pe
  where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
),
n as (
  select e.id, e.minimo, e.bloqueado,
         count(distinct j.fecha) filter (where fn_tardanza_es_medible(j.minutos_tarde)) as n
  from esc e
  left join jornadas j on j.persona_id = e.id
    and j.fecha >= date_trunc('month', fn_hoy_lima())::date
    and j.fecha <= fn_hoy_lima()
    and (e.corte is null or j.fecha > e.corte)
    and j.minutos_tarde is not null and j.minutos_tarde > 0
    and not exists (select 1 from tardanzas_justificadas tj
                     where tj.persona_id = e.id and tj.fecha = j.fecha)
  group by e.id, e.minimo, e.bloqueado
)
select
  count(*) filter (where n >= minimo and n < 2)      as desalineados,
  count(*) filter (where minimo is null or minimo < 3) as en_escalon_avanzado,
  count(*) filter (where n >= minimo)                as en_umbral_hoy,
  (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.proname = 'fn_tardanza_escalon') as escala_en_un_solo_sitio
from n;
