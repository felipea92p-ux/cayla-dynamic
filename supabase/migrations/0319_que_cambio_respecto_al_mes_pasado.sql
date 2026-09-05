-- ============================================================================
-- 0319 — Qué cambió respecto al mes pasado
-- ----------------------------------------------------------------------------
-- EL PROBLEMA
--
-- Todos los frenos que Dynamic pone antes de cerrar un mes son frenos de
-- REGLA: `antes_de_cerrar_el_mes.sql` pregunta si cuadra, `a_quien_le_pega.sql`
-- pregunta a quién le toca una norma concreta, el candado de la 0243/0244
-- pregunta si alguien va a cobrar dos veces. Todos son buenos y todos tienen el
-- mismo límite: solo encuentran lo que alguien ya sabía preguntar.
--
-- No existe —medido: `grep` de «variacion», «mes_anterior» y «periodo_anterior»
-- sobre `apps/web` y las 297 migraciones no devuelve nada— ninguna pregunta de
-- FORMA: ¿esto se parece al mes pasado?
--
-- Y tres hallazgos ya confirmados en `docs/hallazgos-abiertos.md` son de forma,
-- no de regla. Se pueden ver sin conocer la norma que los produce:
--
--     «cobra S/0 y el mes pasado cobró un sueldo»       S/1 509,64 medidos
--        └ quien cesa sin marcas desaparece de la planilla
--     «cobra el mes íntegro y trabajó doce días»        S/1 306,45 medidos
--        └ la rama de sueldo fijo no prorratea
--     «cobra días posteriores a su cese»                S/  193,55 medidos
--
-- Los tres se encontraron con auditorías de decenas de agentes contra la ley.
-- Una tabla ordenada por |Δ| los habría puesto arriba, cada mes, en dos
-- segundos. Eso es lo único que hace esta función.
--
-- QUÉ PROMETE
--
--   1. `fn_planilla_variacion(periodo)` devuelve, persona por persona, cuánto
--      se movió su pago respecto del periodo anterior — y las filas salen
--      ORDENADAS POR MAGNITUD DEL CAMBIO, que es el punto entero.
--   2. Marca por su nombre las siete formas que un mes tiene de no parecerse
--      al anterior (`avisos`) —salió, entró, cobra cero, empieza a cobrar,
--      trabajó y no cobra, salto, cobra igual y trabajó menos— y por separado
--      las razones legítimas por las que alguien se movió (`explica`).
--   3. No calcula ni una cifra de planilla por su cuenta y no escribe nada.
--
-- POR QUÉ ESTÁ HECHA ASÍ
--
-- ── Los dos lados los pide `fn_proyeccion_periodo`, no `fn_planilla_calcular`.
-- Esa es la decisión de diseño que importa. `fn_proyeccion_periodo` ya sabe,
-- desde la 0313, que un mes pagado se LEE de su foto y solo uno abierto se
-- calcula. Preguntar directamente a `fn_planilla_calcular` habría recalculado
-- el mes anterior con las reglas de hoy, y entonces esta función compararía el
-- presente contra un pasado que nunca ocurrió — mintiendo justo donde promete
-- avisar. La regla de la casa contra escribir una quinta copia de una regla ya
-- escrita se aplica igual aquí: la pregunta «¿cuál es la cifra buena de este
-- periodo?» ya tiene dueño.
--
-- ── `avisos` y `explica` son dos listas y no una. En este sistema el falso
-- positivo es el peor error: acusar de falta a quien no debía cuesta más que
-- dejar pasar una falta real. Un informe que grita «cobra S/0» sin decir «cesó
-- el 12» enseña a ignorarlo en dos meses. Así que las razones legítimas —cesó,
-- ingresó, le cambió el sueldo, tuvo ausencias aprobadas— viajan en su propia
-- lista, al lado del aviso, no en vez de él. La función no decide cuál gana:
-- las pone juntas y decide una persona. Es la misma doctrina que ya rige el
-- sistema —avisa, nunca sanciona sola— aplicada al dinero en vez de a la
-- conducta.
--
-- ── Los umbrales viven en `configuracion`, no en el cuerpo. Cuatro números que
-- van a querer ajustarse después de dos o tres cierres, igual que
-- `planilla_provisiones`. Clavarlos aquí obligaría a una migración para
-- moverlos.
--
-- ── Los avisos que no son un simple salto. `cobra_igual_trabajo_menos` es el
-- que caza al sueldo fijo que no prorratea: el total no se mueve mientras las
-- horas se desploman. `trabajo_y_no_cobra` es su reverso. Y `empieza_a_cobrar`
-- existe porque con el mes anterior en 0 no hay porcentaje que calcular, así
-- que `salto` es ciego justo ahí. Un umbral de porcentaje a secas no ve
-- ninguno de los tres.
--
-- ── El salto exige las DOS condiciones, porcentaje Y soles. Solo porcentaje y
-- un pago pequeño dispara por céntimos; solo soles y un salto grande sobre un
-- sueldo grande se esconde. Es la forma barata de que la tabla no chille.
--
-- QUÉ ASUME
--
--   · Que el periodo anterior es el inmediatamente anterior por `fecha_fin`.
--     Se puede pasar otro a mano con `p_previo_id` — por ejemplo para saltarse
--     un periodo corto o comparar contra el mismo mes del año pasado.
--   · Que los periodos de CAYLA duran entre 20 y 46 días y NO son meses
--     calendario. Por eso el sobre devuelve `dias` de los dos lados y marca
--     `periodos_de_distinto_largo`. La fórmula (`salario × horas /
--     (6.5 × días_del_periodo)`) hace que el total de quien trabaja completo
--     aguante bastante bien un periodo más largo —más días trabajados, hora más
--     barata—, así que la comparación cruda es legible; pero si los dos lados
--     no miden lo mismo, la pantalla tiene que poder decirlo.
--   · Que sin periodo anterior no hay nada que comparar: devuelve
--     `sin_previo = true` y ninguna fila, en vez de marcar a las treinta
--     personas como recién entradas.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   · No bloquea el cierre. No es un freno: es una lista.
--   · No toca `fn_planilla_calcular`. Ni una línea. Por eso esta migración no
--     entra en el ritual de md5 de partida ni compite con el cierre del 28.
--   · No compara contra la foto del MISMO periodo — esa pregunta ya la
--     responde `fn_planilla_foto_diferencias` (0096) y es otra cosa: allí se
--     busca deriva, aquí se busca diferencia.
--
-- CÓMO SE REVIERTE
--
--     drop function if exists fn_planilla_variacion(uuid, uuid);
--     delete from configuracion where clave = 'planilla_variacion_umbrales';
--
-- No hay tabla nueva, ni columna, ni trigger, ni dato que rescatar. Ninguna
-- función existente cambia de cuerpo.
-- ============================================================================


-- ── 1 · Los umbrales ────────────────────────────────────────────────────────
-- `on conflict do nothing`: si alguien ya los ajustó, esta migración no se los
-- pisa al volver a pegarse.

insert into configuracion (clave, valor, descripcion)
values (
  'planilla_variacion_umbrales',
  '{"salto_pct": 25, "salto_soles": 100, "quieto_pct": 2, "horas_caen_pct": 20}'::jsonb,
  'Cuándo el informe de variación marca a alguien. `salto_pct` y `salto_soles` se exigen JUNTOS para el aviso «salto». `quieto_pct` y `horas_caen_pct` definen «cobra igual y trabajó menos»: el total se mueve menos de quieto_pct mientras las horas caen más de horas_caen_pct.'
)
on conflict (clave) do nothing;


-- ── 2 · La función ──────────────────────────────────────────────────────────

create or replace function fn_planilla_variacion(
  p_periodo_id uuid,
  p_previo_id  uuid default null
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_act        record;
  v_prev       record;
  v_proy_act   jsonb;
  v_proy_prev  jsonb;
  v_umb        jsonb;
  v_salto_pct      numeric;
  v_salto_soles    numeric;
  v_quieto_pct     numeric;
  v_horas_caen_pct numeric;
  v_filas      jsonb;
  v_resumen    jsonb;
begin
  -- Mismo guard, misma superficie y mismas palabras que `fn_proyeccion_periodo`
  -- y `fn_planilla_calcular`. `is not true` y no `not (...)`: un null no pasa
  -- como autorizado. Ver CLAUDE.md — la forma es obligatoria aunque desde la
  -- 0078 estos booleanos ya no devuelvan null.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la variación de la planilla.';
  end if;

  select * into v_act from periodos_planilla where id = p_periodo_id;
  if not found then
    raise exception 'Periodo inexistente.';
  end if;

  -- El anterior por `fecha_fin`, salvo que la llamada diga otro. `fecha_fin <
  -- fecha_ini` del actual y no `id <> actual`: los periodos no se solapan
  -- (constraint `periodos_sin_solape`, 0025), así que esto los ordena de verdad
  -- por el tiempo y no por el orden en que alguien los creó.
  if p_previo_id is not null then
    select * into v_prev from periodos_planilla where id = p_previo_id;
    if not found then
      raise exception 'El periodo de comparación no existe.';
    end if;
  else
    select * into v_prev
      from periodos_planilla
     where fecha_fin < v_act.fecha_ini
     order by fecha_fin desc
     limit 1;
  end if;

  if v_prev.id is null then
    return jsonb_build_object(
      'periodo_id',   v_act.id,
      'periodo_desde', v_act.fecha_ini,
      'periodo_hasta', v_act.fecha_fin,
      'sin_previo',   true,
      'filas',        '[]'::jsonb,
      'resumen',      jsonb_build_object('personas_actual', 0, 'personas_previo', 0));
  end if;

  v_proy_act  := fn_proyeccion_periodo(v_act.id);
  v_proy_prev := fn_proyeccion_periodo(v_prev.id);

  select valor into v_umb from configuracion where clave = 'planilla_variacion_umbrales';
  v_umb := coalesce(v_umb, '{}'::jsonb);
  v_salto_pct      := coalesce((v_umb->>'salto_pct')::numeric, 25);
  v_salto_soles    := coalesce((v_umb->>'salto_soles')::numeric, 100);
  v_quieto_pct     := coalesce((v_umb->>'quieto_pct')::numeric, 2);
  v_horas_caen_pct := coalesce((v_umb->>'horas_caen_pct')::numeric, 20);

  with
  act as (
    select (f->>'persona_id')::uuid                          as persona_id,
           f->>'nombre'                                      as nombre,
           f->>'sede'                                        as sede,
           f->>'rango'                                       as rango,
           coalesce((f->>'total')::numeric, 0)               as total,
           coalesce((f->>'horas_mes')::numeric, 0)           as horas,
           coalesce((f->>'dias_trabajados')::int, 0)         as dias,
           nullif(f->>'salario_ref', '')::numeric            as salario
      from jsonb_array_elements(coalesce(v_proy_act->'filas', '[]'::jsonb)) f
  ),
  prev as (
    select (f->>'persona_id')::uuid                          as persona_id,
           f->>'nombre'                                      as nombre,
           coalesce((f->>'total')::numeric, 0)               as total,
           coalesce((f->>'horas_mes')::numeric, 0)           as horas,
           coalesce((f->>'dias_trabajados')::int, 0)         as dias,
           nullif(f->>'salario_ref', '')::numeric            as salario
      from jsonb_array_elements(coalesce(v_proy_prev->'filas', '[]'::jsonb)) f
  ),
  -- Días de ausencia APROBADA y no anulada que caen dentro de cada periodo.
  -- Es la explicación más común de una caída legítima, y la que más falsos
  -- positivos evita. Se recorta al periodo con `greatest`/`least` porque una
  -- ausencia puede empezar antes o acabar después.
  aus as (
    select a.persona_id,
           sum(greatest(0, (least(a.fecha_fin, v_act.fecha_fin)
                          - greatest(a.fecha_inicio, v_act.fecha_ini)) + 1))
             filter (where a.fecha_inicio <= v_act.fecha_fin
                       and a.fecha_fin    >= v_act.fecha_ini)      as dias_act,
           sum(greatest(0, (least(a.fecha_fin, v_prev.fecha_fin)
                          - greatest(a.fecha_inicio, v_prev.fecha_ini)) + 1))
             filter (where a.fecha_inicio <= v_prev.fecha_fin
                       and a.fecha_fin    >= v_prev.fecha_ini)     as dias_prev
      from ausencias a
     where a.aprobada_at is not null
       and a.anulada_at  is null
       and a.fecha_inicio <= v_act.fecha_fin
       and a.fecha_fin    >= v_prev.fecha_ini
     group by a.persona_id
  ),
  juntas as (
    select coalesce(a.persona_id, p.persona_id)               as persona_id,
           coalesce(a.nombre, p.nombre)                       as nombre,
           a.sede, a.rango,
           coalesce(a.total, 0)   as total_act,   coalesce(p.total, 0)   as total_prev,
           coalesce(a.horas, 0)   as horas_act,   coalesce(p.horas, 0)   as horas_prev,
           coalesce(a.dias, 0)    as dias_act,    coalesce(p.dias, 0)    as dias_prev,
           a.salario as salario_act, p.salario as salario_prev,
           (a.persona_id is null) as salio,
           (p.persona_id is null) as entro,
           coalesce(au.dias_act, 0)  as aus_act,
           coalesce(au.dias_prev, 0) as aus_prev,
           pe.fecha_cese, pe.fecha_ingreso
      from act a
      full outer join prev p on p.persona_id = a.persona_id
      left join personas pe   on pe.id = coalesce(a.persona_id, p.persona_id)
      left join aus au        on au.persona_id = coalesce(a.persona_id, p.persona_id)
  ),
  medidas as (
    select j.*,
           round(j.total_act - j.total_prev, 2) as delta,
           case when j.total_prev > 0
                then round((j.total_act - j.total_prev) / j.total_prev * 100, 1)
           end                                  as delta_pct,
           case when j.horas_prev > 0
                then round((j.horas_act - j.horas_prev) / j.horas_prev * 100, 1)
           end                                  as horas_pct
      from juntas j
     -- Quien no cobró ni trabajó en NINGUNO de los dos periodos no tiene nada
     -- que decir en esta tabla. Medido: sin esta línea, la cuenta de admin del
     -- montaje ocupaba una fila de ceros. Una tabla que se lee entera cada mes
     -- no puede gastar filas en silencio. `personas_actual` cuenta, entonces,
     -- a quien tuvo pago u horas — que es el número que interesa.
     where j.total_act <> 0 or j.total_prev <> 0
        or j.horas_act <> 0 or j.horas_prev <> 0
  )
  select
    jsonb_agg(
      jsonb_build_object(
        'persona_id',  m.persona_id,
        'nombre',      m.nombre,
        'sede',        m.sede,
        'rango',       m.rango,
        'total_actual', m.total_act,
        'total_previo', m.total_prev,
        'delta',        m.delta,
        'delta_pct',    m.delta_pct,
        'horas_actual', m.horas_act,
        'horas_previo', m.horas_prev,
        'horas_pct',    m.horas_pct,
        'dias_actual',  m.dias_act,
        'dias_previo',  m.dias_prev,
        'ausencias_actual', m.aus_act,
        'ausencias_previo', m.aus_prev,
        'salario_actual',   m.salario_act,
        'salario_previo',   m.salario_prev,

        -- ── Los avisos: «mira esto» ────────────────────────────────────────
        'avisos', (
          select coalesce(jsonb_agg(x), '[]'::jsonb) from (
            select 'salio'::text as x where m.salio
            union all
            select 'entro'      where m.entro
            union all
            select 'cobra_cero' where not m.salio and m.total_act = 0 and m.total_prev > 0
            union all
            select 'trabajo_y_no_cobra' where m.horas_act > 0 and m.total_act = 0
            union all
            select 'salto'
             where not m.salio and not m.entro
               and m.delta_pct is not null
               and abs(m.delta_pct) >= v_salto_pct
               and abs(m.delta)     >= v_salto_soles
            union all
            -- El reverso de `cobra_cero`, y hace falta decirlo aparte: con el
            -- previo en 0 no hay porcentaje que calcular, así que `salto` no
            -- puede verlo. Medido en la auditoría de esta migración: quien
            -- pasaba de S/0 a S/1 918 no levantaba ni un aviso. Que casi
            -- siempre lo explique un ingreso no lo hace menos digno de una
            -- línea — la explicación viaja al lado, en `explica`.
            select 'empieza_a_cobrar'
             where not m.salio
               and m.total_prev = 0
               and m.total_act >= v_salto_soles
            union all
            -- El detector del sueldo fijo que no prorratea: el pago se queda
            -- quieto mientras las horas se caen.
            --
            -- ⚠️ `aus_act <= aus_prev` NO es un detalle: sin esa condición
            -- este aviso se dispara con cualquier ausencia aprobada —
            -- vacaciones, descanso médico, maternidad—, porque las tres se
            -- pagan SIN marcaje: el total se queda quieto y las horas se van a
            -- cero por diseño. Medido en la auditoría: quien pasó el periodo
            -- entero de vacaciones fue de 169 h a 0 cobrando lo mismo, y solo
            -- se libró del aviso porque su total se movió un 4,4 % — o sea por
            -- suerte. Un aviso que marca a media empresa cada vez que alguien
            -- toma vacaciones se ignora al segundo mes, y aquí el falso
            -- positivo es el peor error. La fila sigue apareciendo en la tabla
            -- con `mas_ausencias` en `explica`: no se esconde, solo no se
            -- grita.
            select 'cobra_igual_trabajo_menos'
             where not m.salio and not m.entro
               and m.total_prev > 0 and m.total_act > 0
               and m.aus_act <= m.aus_prev
               and m.delta_pct is not null and abs(m.delta_pct) <= v_quieto_pct
               and m.horas_pct is not null and m.horas_pct <= -v_horas_caen_pct
          ) s
        ),

        -- ── Las explicaciones: «por esto se movió» ─────────────────────────
        -- No son avisos y no se mezclan con ellos. Van al lado para que quien
        -- lea la tabla no tenga que ir a buscarlas a otra pantalla.
        'explica', (
          select coalesce(jsonb_agg(x), '[]'::jsonb) from (
            select 'ceso'::text as x
             where m.fecha_cese is not null
               and m.fecha_cese between v_prev.fecha_ini and v_act.fecha_fin
            union all
            select 'ingreso'
             where m.fecha_ingreso is not null
               and m.fecha_ingreso between v_prev.fecha_ini and v_act.fecha_fin
            union all
            select 'sueldo_cambio'
             where m.salario_act is distinct from m.salario_prev
               and m.salario_act is not null and m.salario_prev is not null
            union all
            select 'mas_ausencias'  where m.aus_act > m.aus_prev
            union all
            select 'menos_ausencias' where m.aus_act < m.aus_prev
          ) s
        )
      )
      -- EL ORDEN ES LA FUNCIÓN. Lo más movido arriba; a igualdad de movimiento,
      -- por nombre, para que dos lecturas seguidas den la misma tabla.
      order by abs(m.delta) desc, m.nombre
    ),
    jsonb_build_object(
      'personas_actual', count(*) filter (where not m.salio),
      'personas_previo', count(*) filter (where not m.entro),
      'entraron',        count(*) filter (where m.entro),
      'salieron',        count(*) filter (where m.salio),
      'total_actual',    round(coalesce(sum(m.total_act), 0), 2),
      'total_previo',    round(coalesce(sum(m.total_prev), 0), 2),
      'total_delta',     round(coalesce(sum(m.total_act - m.total_prev), 0), 2),
      'horas_actual',    round(coalesce(sum(m.horas_act), 0), 2),
      'horas_previo',    round(coalesce(sum(m.horas_prev), 0), 2)
    )
    into v_filas, v_resumen
  from medidas m;

  return jsonb_build_object(
    'sin_previo',     false,
    'periodo_id',     v_act.id,
    'periodo_desde',  v_act.fecha_ini,
    'periodo_hasta',  v_act.fecha_fin,
    'periodo_estado', v_act.estado,
    'periodo_dias',   (v_act.fecha_fin - v_act.fecha_ini) + 1,
    'periodo_fuente', v_proy_act->>'fuente',

    'previo_id',      v_prev.id,
    'previo_desde',   v_prev.fecha_ini,
    'previo_hasta',   v_prev.fecha_fin,
    'previo_estado',  v_prev.estado,
    'previo_dias',    (v_prev.fecha_fin - v_prev.fecha_ini) + 1,
    'previo_fuente',  v_proy_prev->>'fuente',

    -- Los periodos duran entre 20 y 46 días. Si los dos lados no miden lo
    -- mismo, la pantalla lo tiene que decir antes que ninguna cifra.
    'periodos_de_distinto_largo',
        (v_act.fecha_fin - v_act.fecha_ini) <> (v_prev.fecha_fin - v_prev.fecha_ini),

    'umbrales',       jsonb_build_object(
                        'salto_pct', v_salto_pct, 'salto_soles', v_salto_soles,
                        'quieto_pct', v_quieto_pct, 'horas_caen_pct', v_horas_caen_pct),
    'resumen',        v_resumen,
    'filas',          coalesce(v_filas, '[]'::jsonb));
end;
$function$;

comment on function fn_planilla_variacion(uuid, uuid) is
  'Qué cambió respecto al periodo anterior, persona por persona, ordenado por '
  'magnitud del cambio. Los dos lados los pide a `fn_proyeccion_periodo`, así '
  'que un periodo pagado se compara por lo que se PAGÓ (su foto, CAMBIO 0313) y '
  'no por lo que se recalcularía hoy. Separa `avisos` (mira esto) de `explica` '
  '(por esto se movió). Solo lee: no bloquea el cierre ni escribe nada.';

grant execute on function fn_planilla_variacion(uuid, uuid) to authenticated;
revoke execute on function fn_planilla_variacion(uuid, uuid) from public, anon;


-- ── 3 · El rastro ───────────────────────────────────────────────────────────
-- La prueba 122 lo exige en cada push: sin esta fila, `que-falta-pegar.sh` no
-- sabría si esta migración llegó a producción.

insert into migraciones_aplicadas (numero, nombre)
values (319, 'que_cambio_respecto_al_mes_pasado')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── 4 · Comprobación ────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado del último
-- select. Las cinco columnas tienen que salir en `true`.

select
  '0319 · OK'                                                  as migracion,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_variacion') = 1
                                                               as existe_y_sin_sobrecargas,
  position('fn_proyeccion_periodo' in (select p.prosrc from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_variacion')) > 0
                                                               as compara_contra_la_foto_no_contra_el_recalculo,
  (select count(*) from configuracion where clave = 'planilla_variacion_umbrales') = 1
                                                               as estan_los_umbrales,
  has_function_privilege('authenticated',
    'fn_planilla_variacion(uuid, uuid)', 'execute')            as la_pantalla_la_puede_llamar,
  (select count(*) from migraciones_aplicadas where numero = 319) = 1
                                                               as quedo_el_rastro;
