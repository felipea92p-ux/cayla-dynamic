-- ============================================================================
-- 0331 — Las diecinueve pasan a comisión mixta
-- ============================================================================
--
-- QUÉ PROMETE
--   Que a quien hoy está en un régimen de comisión SOBRE FLUJO se le deje de
--   retener la comisión de su AFP, desde el primer periodo que todavía no se ha
--   pagado. Su descuento pasa de 12.84 %-13.06 % a 11.37 %.
--
-- QUÉ ASUME, Y ES LO ÚNICO QUE HAY QUE DISCUTIR
--   · Que la **0328** está aplicada: sin sus cuatro filas de tasa, esta
--     migración no encuentra a dónde mover a nadie y aborta antes de tocar nada.
--   · Que la `fn_planilla_calcular` que corre en la base donde se pegue LEE el
--     historial de `asignaciones_regimen_pension` (0261). No se da por supuesto:
--     se comprueba contra el catálogo antes de tocar nada, porque es lo único
--     que sostiene la promesa de no mover un mes pagado. Ver «Freno 0».
--   · Que **nadie del equipo se afilió al SPP antes de febrero de 2013**.
--     Decisión de Felipe el 2026-08-31, después de que el contador avisara del
--     error: «Todos son jóvenes, no creo que nadie se haya afiliado antes de
--     2013». Es la condición que determina el esquema: la Ley 29903 mandó a
--     mixta de forma obligatoria a todo el que entrara al sistema desde
--     entonces, y en flujo solo siguen quienes ya estaban antes y pidieron
--     quedarse.
--   · Que si el contador encuentra una excepción, devolverla cuesta UNA llamada
--     desde la pantalla de Datos personales, o esto en el SQL Editor:
--         select fn_cambiar_regimen_pension('<uuid>', 'integra', '<fecha>',
--                'se afilió antes de 2013 y se quedó en flujo');
--     Por eso esta migración se puede aplicar con la suposición escrita en vez
--     de esperar la confirmación una por una: el costo de equivocarse es una
--     línea, y el costo de esperar es un mes más de retención indebida.
--
-- ── LO QUE SE MIDIÓ EN PRODUCCIÓN ANTES DE ESCRIBIR ESTO ────────────────────
--
-- El SELECT final de la 0328, el 2026-08-31:
--
--     personas hoy en comisión sobre flujo                    19
--     periodos ya pagados involucrados                         2
--     soles retenidos de más si todas fueran mixta        304.47
--
-- Esos S/304.47 ya salieron del sueldo de esas personas y **esta migración no
-- los devuelve**: solo corta la sangría hacia adelante. Qué se hace con lo ya
-- retenido —devolverlo, compensarlo en la boleta siguiente— es una decisión de
-- Felipe con el contador, y cuando esté tomada se ejecuta por la puerta de los
-- movimientos de planilla, no por acá. `scripts/sql-manual/afp_cuanto_se_retuvo_de_mas.sql`
-- lo desglosa persona por persona.
--
-- ── POR QUÉ NO SE TOCA NI UN PERIODO PAGADO ─────────────────────────────────
--
-- El cambio rige desde el primer día del primer periodo cuyo estado NO es
-- 'pagado'. Es exactamente lo que hizo la 0115 cuando encendió el descuento, y
-- por el mismo motivo: la 0261 versionó la pertenencia a un régimen, así que un
-- tramo que empieza hoy no alcanza a los meses ya depositados. Reimprimir la
-- boleta de julio seguirá dando lo que se depositó en julio.
--
-- Y no es solo prolijidad contable: cambiar hacia atrás significaría que la
-- planilla ya cerrada de dos meses deja de cuadrar con lo que salió del banco.
--
-- ── EL DEFECTO QUE ENCONTRÓ LA AUDITORÍA, Y QUE ESTA MIGRACIÓN YA NO TIENE ──
--
-- La primera versión de este archivo hacía esas tres cosas y NO ALCANZABA. Se
-- midió contra el Postgres local, con un periodo pagado y uno abierto, y a una
-- de las tres personas de prueba le cambió el mes YA PAGADO:
--
--     MARZO (pagado) · SinTramo · profuturo_mixta · 11.37 %   ← estaba mal
--
-- El motivo es la cascada de la 0261. `fn_planilla_calcular` resuelve el
-- régimen así: el tramo vigente a la fecha de cierre del periodo Y SI NO HAY
-- TRAMO, la columna `personas.regimen_pension`. Quien no tenía tramo abierto se
-- quedaba, para marzo, sin ninguna fila que lo cubriera —la nueva empieza el 1
-- de abril— y caía a la columna, que el paso 3 acababa de reescribir. El tramo
-- nuevo protegía el pasado de todos MENOS de quien no tenía historial, que es
-- justo a quien más se lo debía.
--
-- Se arregla escribiendo también el tramo del pasado: a quien no tiene ninguno,
-- se le escribe su régimen ANTERIOR desde su ingreso hasta el día antes del
-- cambio. Y eso no es inventar historia —que es lo que la 0261 se negó a hacer
-- con la jubilación—: es escribir el valor que la columna YA TENÍA y que la
-- planilla YA VENÍA APLICANDO a esos meses. Se registra lo que pasó, no lo que
-- suponemos que pasó.
--
-- EL MISMO AGUJERO ESTÁ EN `fn_cambiar_regimen_pension`, y esta migración no lo
-- toca: cambiarle el régimen desde la pantalla a alguien sin tramo reescribe
-- sus meses pagados por esta misma vía. Su freno de la 0203 mira que la FECHA no
-- caiga en un periodo pagado, y aquí la fecha está bien — lo que alcanza al
-- pasado es el `update` de la columna. Queda anotado aparte; arreglarlo dentro
-- de una migración que mueve el sueldo de diecinueve personas mezclaría dos
-- cosas que tienen que poder revertirse por separado.
--
-- ── POR QUÉ NO USA fn_cambiar_regimen_pension ───────────────────────────────
--
-- Sería lo natural —es la puerta de siempre— pero esa función exige
-- `fn_persona_actual_id()`, y en el SQL Editor no hay sesión de nadie: devuelve
-- null y la función se niega, con razón. Así que esta migración hace a mano lo
-- mismo que hace ella, en el mismo orden, y **eso es una deuda a vigilar**: dos
-- sitios que escriben el mismo historial pueden separarse. Se acota escribiendo
-- los tres pasos juntos y en el mismo orden que la función:
--   1. cerrar el tramo abierto el día antes,
--   2. abrir el tramo nuevo,
--   3. poner `personas.regimen_pension` en sintonía.
--
-- ── EL RASTRO, Y POR QUÉ NO VA A `correcciones_auditoria` ───────────────────
--
-- Esa tabla contesta «qué persona cambió este dato, y por qué». Acá no lo
-- cambió una persona mirando una ficha: se corrige un defecto del sistema para
-- diecinueve a la vez, con el mismo motivo. `corregido_por` es NOT NULL y
-- apunta a `personas`, así que escribir esas filas obligaría a elegir a alguien
-- —y elegir a alguien sería inventar quién lo hizo—.
--
-- El rastro va donde sí es verdad: en la `nota` de cada tramo de
-- `asignaciones_regimen_pension`, que es el registro que la planilla lee y que
-- queda fechado. Dice el porqué completo, para quien lo lea dentro de dos años
-- sin este archivo delante.
--
-- CÓMO SE REVIERTE
--   Para todos (borra los dos tramos que escribe: el nuevo y el del pasado):
--     delete from asignaciones_regimen_pension where nota like '0331 ·%';
--     update asignaciones_regimen_pension set vigente_hasta = null
--      where nota like '%(reabierto por revertir la 0331)%';
--     update personas set regimen_pension = replace(regimen_pension, '_mixta', '')
--      where regimen_pension like '%\_mixta';
--   Para una sola persona, que es el caso realista, ver «QUÉ ASUME» arriba.
-- ============================================================================

do $mig$
declare
  v_desde   date;
  v_periodo text;
  v_movidas int := 0;
  v_faltan  int;
begin
  -- ── Freno 0 · ¿esta base LEE el historial de régimen? ─────────────────────
  --
  -- Es el freno más importante de los tres, y el menos obvio. Todo lo que hace
  -- esta migración para no tocar los meses pagados —el tramo del pasado, el
  -- tramo nuevo desde el periodo abierto— descansa en que `fn_planilla_calcular`
  -- resuelva el régimen por `asignaciones_regimen_pension`, que es lo que
  -- introdujo la 0261.
  --
  -- Si la función que corre en esta base fuera ANTERIOR a la 0261, leería solo
  -- `personas.regimen_pension` y los tramos serían decoración: el `update` de la
  -- columna del paso 3 alcanzaría TODOS los meses, incluidos los depositados.
  -- Diecinueve boletas ya pagadas cambiarían de cifra en silencio, y la planilla
  -- cerrada dejaría de cuadrar con lo que salió del banco.
  --
  -- No es paranoia de laboratorio: este repositorio ya se llevó ese susto. El
  -- 2026-08-25 producción corría `fn_planilla_calcular` cuarenta y cuatro
  -- migraciones por detrás del repo sin que nadie lo notara, y la 0261 es
  -- exactamente el tipo de cambio que una repegada vieja revierte en silencio.
  -- La comprobación cuesta una consulta al catálogo y se hace ACÁ, en la base
  -- donde se va a aplicar, en vez de confiar en que el archivo del repo describa
  -- lo que corre en producción.
  -- Se exige que la lean TODAS las sobrecargas, no que la lea alguna. Con un
  -- `exists` bastaría una sola para dar el visto bueno, y si conviven dos
  -- versiones —que es como se manifestó el choque de la 0297 con la 0299— la
  -- que se ejecuta puede ser justamente la que no la lee. Y `is not true` en vez
  -- de `not (...)` por la regla de la casa: sin filas, `bool_and` devuelve null,
  -- y un null no puede pasar por autorizado.
  if coalesce(
       (select bool_and(p.prosrc like '%asignaciones_regimen_pension%')
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
       false) is not true then
    raise exception '0331 · la fn_planilla_calcular de esta base NO lee asignaciones_regimen_pension, así que le falta la cascada de la 0261. Sin ella el régimen sale solo de la columna y esta migración reescribiría los meses YA PAGADOS de 19 personas. NO se aplica nada. Revisa qué versión de fn_planilla_calcular corre acá (la línea PLANILLA de que_falta_pegar.sql lo dice).';
  end if;

  -- ── Freno 1 · sin la 0328 no hay a dónde mover a nadie ────────────────────
  -- Se comprueba ANTES de tocar nada. Sin esto, los tramos nuevos violarían el
  -- CHECK de códigos y la migración moriría a mitad — dejando a unos movidos y
  -- a otros no, que es el estado más difícil de diagnosticar.
  select count(*) into v_faltan
  from (values ('profuturo_mixta'),('prima_mixta'),('integra_mixta'),('habitat_mixta')) as v(r)
  where not exists (select 1 from tasas_pension tp where tp.regimen = v.r);

  if v_faltan > 0 then
    raise exception '0331 · faltan % tasas de comisión mixta. Pega primero la 0328.', v_faltan;
  end if;

  -- ── Freno 2 · el «desde», leído de la base y no escrito a mano ────────────
  -- Igual que la 0115. Una fecha escrita a mano envejece: esta migración puede
  -- pegarse mañana o dentro de dos semanas, y en el medio se cierra un periodo.
  select p.fecha_ini, to_char(p.fecha_ini,'DD/MM/YYYY') || ' → ' || to_char(p.fecha_fin,'DD/MM/YYYY')
    into v_desde, v_periodo
  from periodos_planilla p
  where p.estado <> 'pagado'
  order by p.fecha_ini
  limit 1;

  if v_desde is null then
    -- Sin periodo abierto se arranca el día siguiente al último pagado, para no
    -- alcanzar nada ya depositado.
    select max(p.fecha_fin) + 1 into v_desde from periodos_planilla p where p.estado = 'pagado';
    v_periodo := '(no hay periodo abierto; se usa el día siguiente al último pagado)';
  end if;

  if v_desde is null then
    -- Base recién creada (CI, `supabase db reset`, un clon nuevo): no hay
    -- ningún periodo, ni abierto ni pagado, así que no hay NADA que proteger —
    -- cualquier fecha es segura. En producción esto nunca pasa (hay periodos
    -- desde el origen de la empresa); esta rama solo existe para que la
    -- migración se pueda reconstruir desde cero. Agregado el 2026-08-31 porque
    -- sin esto `supabase db start`/`db reset` abortaba en CUALQUIER base
    -- vacía —incluido el runner de GitHub Actions, que puso `main` en rojo
    -- (job `db-tests`, desde el commit que trajo esta migración).
    v_desde := (now() at time zone 'America/Lima')::date;
    v_periodo := '(base sin ningún periodo — nada que proteger, se usa hoy)';
  end if;

  -- ── A quién ───────────────────────────────────────────────────────────────
  -- El régimen EFECTIVO, con la misma cascada que usa la planilla desde la 0261
  -- y que usa `fn_cambiar_regimen_pension` para saber cuál era el anterior: el
  -- tramo abierto si lo hay, y si no la columna. Leer solo la columna dejaría
  -- fuera a quien tenga tramo y columna divergentes — que es justo el caso que
  -- la 0277 se tomó el trabajo de reconciliar.
  create temp table t_0331_mueve on commit drop as
  select p.id as persona_id,
         coalesce(h.regimen, p.regimen_pension) as antes,
         coalesce(h.regimen, p.regimen_pension) || '_mixta' as despues,
         h.id            as tramo_abierto,
         h.vigente_desde as tramo_desde
  from personas p
  left join asignaciones_regimen_pension h
         on h.persona_id = p.id and h.vigente_hasta is null
  where coalesce(h.regimen, p.regimen_pension) in ('profuturo','prima','integra','habitat');

  select count(*) into v_movidas from t_0331_mueve;

  -- ── 1 · Cerrar el tramo abierto el día antes ──────────────────────────────
  -- Solo los que EMPIEZAN antes del cambio. Un tramo que ya empieza el mismo
  -- día o después no cubre ningún periodo pagado, así que cerrarlo dejaría un
  -- tramo de longitud negativa; a ese se le cambia el régimen en el sitio, más
  -- abajo. Es el caso de quien cambió de AFP esta misma semana.
  update asignaciones_regimen_pension h
     set vigente_hasta = v_desde - 1,
         nota = coalesce(h.nota || ' · ', '') || '(cerrado por la 0331)'
    from t_0331_mueve m
   where h.id = m.tramo_abierto
     and m.tramo_desde < v_desde;

  -- ── 1 bis · Y a quien NO tiene tramo, se le escribe el del PASADO ─────────
  --
  -- Este es el paso que la primera versión no tenía y que le cambiaba un mes ya
  -- pagado. Ver «EL DEFECTO QUE ENCONTRÓ LA AUDITORÍA» en la cabecera.
  --
  -- Arranca en su ingreso —antes de eso no se le pagaba nada— pero nunca antes
  -- del día siguiente a su último tramo cerrado, si tuviera alguno: el índice
  -- `asignacion_regimen_sin_solape` prohíbe que dos filas cubran el mismo día, y
  -- con razón — «¿en qué régimen estaba?» no puede tener dos respuestas.
  --
  -- Y solo si hay pasado que proteger. A quien entró dentro del periodo abierto
  -- no se le escribe: un tramo que termina antes de empezar no existe, y su
  -- CHECK `rango_valido` lo rechazaría.
  insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, vigente_hasta, asignado_por, nota)
  select m.persona_id, m.antes, d.desde, v_desde - 1, null,
         '0331 · tramo del PASADO, escrito para que los periodos ya pagados sigan '
         || 'viendo el régimen con el que se pagaron. No se inventa nada: es el valor '
         || 'que `personas.regimen_pension` ya tenía y que la planilla ya venía '
         || 'aplicando a esos meses. Sin esta fila, la cascada de la 0261 caería a la '
         || 'columna —que la 0331 acaba de cambiar— y le reescribiría el pasado.'
  from t_0331_mueve m
  cross join lateral (
    select greatest(
             coalesce(p.fecha_ingreso, date '2000-01-01'),
             coalesce((select max(h2.vigente_hasta) + 1
                         from asignaciones_regimen_pension h2
                        where h2.persona_id = m.persona_id), date '2000-01-01')
           ) as desde
    from personas p where p.id = m.persona_id
  ) d
  where m.tramo_abierto is null
    and d.desde <= v_desde - 1;

  -- ── 2 · El tramo nuevo ────────────────────────────────────────────────────
  insert into asignaciones_regimen_pension (persona_id, regimen, vigente_desde, asignado_por, nota)
  select m.persona_id, m.despues, v_desde, null,
         '0331 · pasa de ' || m.antes || ' (comisión sobre flujo) a comisión mixta. '
         || 'Su AFP no le cobra comisión del sueldo desde febrero de 2023: solo se '
         || 'retienen el aporte de 10 % y la prima de 1.37 %. Quien entró al SPP desde '
         || '2013 está en mixta por la Ley 29903, y aquí nadie se afilió antes. '
         || 'Lo detectó el contador el 2026-08-31; hasta entonces se le retenía la '
         || 'comisión completa. Aplicado por migración, sin sesión de usuario.'
  from t_0331_mueve m
  where m.tramo_abierto is null or m.tramo_desde < v_desde;

  -- El caso del tramo que ya empezaba hoy o después: se corrige en el sitio.
  update asignaciones_regimen_pension h
     set regimen = m.despues,
         nota = coalesce(h.nota || ' · ', '') || '0331 · corregido a comisión mixta en el propio tramo'
    from t_0331_mueve m
   where h.id = m.tramo_abierto
     and m.tramo_desde >= v_desde;

  -- ── 3 · La ficha, en sintonía ─────────────────────────────────────────────
  -- La planilla lee el tramo; la ficha lee la columna. Dejarlas distintas es lo
  -- que la 0277 vino a arreglar, así que no se vuelve a abrir esa grieta.
  update personas p
     set regimen_pension = m.despues
    from t_0331_mueve m
   where p.id = m.persona_id;

  raise notice '0331 · % personas pasan a comisión mixta desde el % (periodo %).',
    v_movidas, to_char(v_desde,'DD/MM/YYYY'), v_periodo;
end
$mig$;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (331, 'las_diecinueve_pasan_a_comision_mixta')
on conflict (numero) do nothing;

-- ── La comprobación ─────────────────────────────────────────────────────────
--
-- Un solo SELECT porque el SQL Editor solo devuelve el último. Lista a quién se
-- movió, desde cuándo y cuánto baja su descuento — que es lo que hay que poder
-- enseñarle al contador. Si sale vacío, nadie estaba en comisión sobre flujo:
-- o ya se aplicó, o la 0328 todavía no está.
--
-- `queda_alguien_en_flujo` tiene que decir 0. Si dice otra cosa, alguien quedó a
-- medias y hay que mirarlo antes de cerrar el mes.

select p.nombres || ' ' || p.apellidos                      as persona,
       h.regimen                                            as regimen_ahora,
       to_char(h.vigente_desde, 'DD/MM/YYYY')               as rige_desde,
       round((select tp.aporte + tp.comision + tp.prima
                from tasas_pension tp
               where tp.regimen = h.regimen
                 and tp.vigente_desde <= h.vigente_desde
                 and (tp.vigente_hasta is null or tp.vigente_hasta >= h.vigente_desde)
               order by tp.vigente_desde desc limit 1) * 100, 2) as se_le_retiene_ahora,
       (select count(*) from personas p2
         where p2.regimen_pension in ('profuturo','prima','integra','habitat'))
                                                            as queda_alguien_en_flujo
from asignaciones_regimen_pension h
join personas p on p.id = h.persona_id
where h.vigente_hasta is null
  and h.regimen like '%\_mixta'
order by 1;
