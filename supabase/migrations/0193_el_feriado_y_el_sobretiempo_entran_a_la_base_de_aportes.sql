-- ============================================================================
-- 0193 — El feriado y el sobretiempo entran a la base de aportes
-- ============================================================================
--
-- QUÉ PROMETE
--   Que las dos sobretasas legales —el pago del feriado y el recargo del
--   sobretiempo— formen parte de la base de EsSalud y de pensión, como manda la
--   norma. Hoy quedan fuera y se declara menos que el sueldo pactado.
--
-- QUÉ ASUME
--   Que el cuerpo del que parte es el que deja la 0192, que centralizó la base
--   en `bri`. Sin ella este cambio habría que escribirlo en cinco sitios.
--
--   Antes de pegar, comprobar en producción:
--        select md5(prosrc) from pg_proc where proname = 'fn_planilla_calcular';
--      · 684634d24dd1a28ace4e99f1fd174ad6 → tiene la 0192. Pegar esta directo.
--      · ba9dfd2726ea59b86b43fc057c210ece → falta la 0192. Pegarla primero.
--     Cualquier otro valor: parar y preguntar.
--
-- ── POR QUÉ ESTAS DOS Y NO OTRAS COSAS QUE TAMBIÉN ESTÁN FUERA ──────────────
--
-- Porque no admiten discusión. El art. 19 del D.S. 001-97-TR enumera lo que NO
-- es remuneración y ninguna de las dos está en esa lista; SUNAT las nombra una
-- por una, con código propio, en la tabla 22 de la PLAME:
--
--     0105  Trabajo en sobretiempo — las dos primeras horas, recargo 25 %
--     0106  Trabajo en sobretiempo — las siguientes, recargo 35 %
--     0107  Trabajo en día feriado o día de descanso
--
-- Que el sobretiempo esté partido en dos códigos según el tramo confirma además
-- que la 0185 lo calcula como la PLAME espera recibirlo.
--
-- LO QUE ESTA MIGRACIÓN **NO** TOCA, Y NO ES UN OLVIDO:
--
--   · El complemento variable (`pago_base` − `basica`) y el plus por objetivos.
--     Tienen una defensa legal real —art. 19— y están dentro de una estructura
--     remunerativa decidida con el contador, con su exposición cuantificada en
--     docs/analisis-estructura-remunerativa-2026-07-30.md. Medido el 2026-08-08,
--     además, hoy valen CERO: se declara el sueldo íntegro (22 de 22 personas,
--     contra 1 de 23 en el periodo anterior).
--   · La movilidad y la asignación por educación: no remunerativas por el art.
--     19 incisos e) y f), y la declaración firmada que exige la 0159 es
--     justamente lo que sostiene que la movilidad lo sea.
--
-- ── POR QUÉ EL FERIADO PESA TANTO MÁS QUE EL SOBRETIEMPO ────────────────────
--
-- Medido en producción el 2026-08-08, periodo 28-jun → 28-jul:
--   feriados fuera de la base ....... S/ 4,035.07   (23 personas)
--   sobretiempo fuera ............... S/   100.03
--
-- No es que se paguen muchos feriados: es que el feriado NO es un extra sobre
-- el sueldo. Como en CAYLA se paga por horas, quien no marca el día feriado
-- tiene una básica más baja, y `monto_feriados` es exactamente la parte del
-- sueldo que la completa. `basica + feriados` ≈ el sueldo mensual pactado. Sin
-- sumarlo, se declara menos de lo que se acordó pagar.
--
-- ── QUIÉNES QUEDAN FUERA, Y POR QUÉ LA CONDICIÓN NO ES DECORACIÓN ───────────
--
-- Las sobretasas COMPLETAN una base declarada; no pueden crear una donde no la
-- hay. Sin la condición, medido:
--
--   · a un RxH le aparecían S/41.39 de descuento de pensión de la nada — su
--     básica es 0, así que hoy no se le descuenta nada, y sumarle el feriado se
--     lo inventaba. Un locador no aporta a pensión ni genera EsSalud.
--   · a alguien con sueldo fijo, S/46.45. Su básica es 0 a propósito (socios,
--     dirección): lo suyo no se declara por esta vía.
--
-- La condición es la MISMA que usa el lateral `ot` de la 0185, a propósito: dos
-- formas distintas de decir «quién queda fuera» es como se empieza a tener dos
-- verdades.
--
-- ── MEDIDO, seis casos comparando antes y después ───────────────────────────
--
--                        EsSalud (cuesta CAYLA)   neto de la persona
--   bajo la RMV .............. +S/  0.00 ......... −S/  8.77
--   sobre la RMV ............. +S/ 30.79 ......... −S/ 44.49
--   con hijos ................ +S/ 18.05 ......... −S/ 26.08
--   con sobretiempo .......... +S/ 34.60 ......... −S/ 49.97
--   sueldo fijo ..............  S/  0.00 ..........  S/  0.00
--   RxH ......................  S/  0.00 ..........  S/  0.00
--
-- Los dos números tiran en direcciones opuestas y hay que leerlos por separado.
-- EsSalud es COSTO DE LA EMPRESA y no toca a nadie más. La pensión es plata que
-- se le retiene a cada persona: **su neto baja**, y ese monto va a su propio
-- fondo de jubilación. No es un descuento nuevo inventado — es el que
-- correspondía y no se estaba haciendo. Aun así, hay que avisarle al equipo
-- antes de que lo vea en la boleta: un neto que baja sin explicación se lee
-- como un error, o como algo peor.
--
-- Quien está por debajo de la RMV no mueve su EsSalud, porque el piso de la Ley
-- 26790 art. 6 ya lo tenía en 9 % × RMV. La pensión sí le sube: no tiene piso.
--
-- CÓMO SE REVIERTE
--   Restaurar fn_planilla_calcular desde la 0192. El cambio es UN bloque dentro
--   del lateral `bri`, marcado «CAMBIO 0193».
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dias int; v_base numeric;
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_f_be numeric;   -- CAMBIO 0134: tasa de la bonificacion extraordinaria
  v_asig numeric; v_anio int; v_mes int;
  v_movilidad numeric; v_tasa_afp numeric;   -- CAMBIO 0110
  v_exige_decl numeric;                      -- CAMBIO 0159
  v_sexto_cts numeric;                       -- CAMBIO 0112
  v_rmv numeric; v_tasa_essalud numeric;     -- CAMBIO 0116
begin
  -- ⚠️ ESTE GUARD ES DE LA 0090 Y NO SE TOCA NUNCA.
  -- La 0076 abrió esta función a cualquier sesión con login —el terminal de
  -- tienda incluido— al conceder permisos en masa, y la 0090 lo cerró poniendo
  -- la comprobación DENTRO de la función, porque un `revoke` se deshace solo la
  -- próxima vez que alguien conceda en masa y un guard no.
  -- Quien copie este cuerpo para otra migración tiene que copiar esto también:
  -- al escribir la 0100 se copió el texto de la 0069, que es anterior, y el
  -- guard desapareció sin que nada fallara salvo la prueba 91.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular la planilla.';
  end if;

  v_dias := (p_fin - p_ini) + 1;
  v_base := 6.5 * v_dias;
  v_anio := extract(year from p_fin)::int;
  v_mes := extract(month from p_fin)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion": 0.08333, "cts": 0.04167, "vacaciones": 0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vacas := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0134 ⇩⇩⇩ LA BONIFICACION EXTRAORDINARIA DE LA LEY 30334.
  -- Versionada en parametros_laborales y no clavada en el codigo, por el mismo
  -- motivo que la movilidad (0118) y la asignacion familiar (0122): es una tasa
  -- legal, y el dia que cambie los periodos ya pagados no pueden moverse.
  -- Es 6.75 % para quien esta afiliado a una EPS. Hoy nadie lo esta y el sistema
  -- no tiene ese campo; cuando lo tenga, esta lectura pasa a ser por persona.
  select pl.valor into v_f_be
  from parametros_laborales pl
  where pl.clave = 'bonificacion_extraordinaria'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_f_be is null then v_f_be := 0.09; end if;
  -- CAMBIO 0112 — el sexto de la gratificación en la base de la CTS (Art. 16
  -- D.S. 001-97-TR). Arranca en 0: sin la clave, la CTS sale como hoy.
  v_sexto_cts := coalesce((v_prov->>'sexto_cts')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0122 ⇩⇩⇩ LA ASIGNACIÓN FAMILIAR, CON VIGENCIA.
  --
  -- Es el 10% de la RMV (Ley 25129), así que SUBE CUANDO SUBE LA RMV. El 28 de
  -- julio de 2026 se anunció el alza a S/1,300, que la llevaría de S/113 a S/130.
  --
  -- Hasta esta migración el monto vivía en 'configuracion' como un escalar SIN
  -- FECHA. El día que alguien lo actualizara a 130, TODOS los periodos ya pagados
  -- se recalcularían con el valor nuevo y las boletas viejas dejarían de
  -- reproducirse. Es el mismo defecto que ya nos mordió con tasa_afp y que la 0116
  -- y la 0118 resolvieron para la RMV, el EsSalud y la movilidad. A esta se le
  -- pasó, y se arregla ANTES de que salga la norma y no después.
  --
  -- Acá la lectura es exacta: un periodo de planilla tiene una sola asignación
  -- vigente, la del cierre, y los 15 usos de v_asig pertenecen al mismo periodo.
  select pl.valor into v_asig
  from parametros_laborales pl
  where pl.clave = 'asignacion_familiar'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;

  -- Respaldo, para que una base sin la fila se comporte igual que antes.
  if v_asig is null then
    select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
    from configuracion where clave = 'asignacion_familiar';
  end if;
  if v_asig is null then v_asig := 113.00; end if;

  -- ⇩⇩⇩ CAMBIO 0110 ⇩⇩⇩ Las dos viven en configuracion, no en el código.
  --
  -- AMBAS ARRANCAN EN CERO A PROPÓSITO. Si las claves no existen, la movilidad
  -- y el descuento de AFP salen 0 y NINGÚN pago se mueve: esta migración se puede
  -- pegar en producción sin que nadie cobre un sol distinto. Se activan con dos
  -- UPDATE cuando Felipe decida, no al aplicar la migración.
  --
  --   update configuracion set valor = '{"monto": 12.50}'::jsonb
  --    where clave = 'movilidad_diaria';
  --   update configuracion set valor = '{"tasa": 0.13}'::jsonb
  --    where clave = 'tasa_afp';
  --
  -- La tarifa vive en configuracion porque los pasajes cambian (Trujillo pasó de
  -- S/2.50 a S/2.00 en junio de 2026) y la tasa de AFP porque varía por AFP:
  -- entre 12.84% (Habitat) y 13.06% (Profuturo). El 13% es el techo práctico.
  -- ⇩⇩⇩ CAMBIO 0118 ⇩⇩⇩ LA TARIFA DE MOVILIDAD, CON VIGENCIA Y CON SUSTENTO.
  --
  -- Antes salía de 'configuracion', que guarda valores globales SIN fecha. El día
  -- que la tarifa cambie —y va a cambiar, porque sigue al pasaje— ese valor único
  -- recalcularía TODOS los periodos ya pagados. Es el mismo defecto que ya nos
  -- mordió con tasa_afp y que la 0116 evitó para la RMV.
  --
  -- Ahora sale de parametros_laborales, eligiendo la fila vigente al FIN del
  -- periodo. Cuando el pasaje suba se cierra la fila con vigente_hasta y se abre
  -- otra: el pasado queda intacto y el porqué de cada tarifa queda archivado en
  -- la columna 'sustento' de su propia fila.
  --
  -- Se conserva la lectura de 'configuracion' como respaldo, para que una base
  -- que aún no tenga la fila siga comportándose igual que antes.
  -- ⇩⇩⇩ CAMBIO 0159 ⇩⇩⇩ ¿Se exige la declaración de ruta en este periodo?
  -- Se lee al FIN del periodo, igual que la tarifa: un parámetro versionado que
  -- vale 0 mientras el candado está apagado. Los periodos ya pagados no cambian
  -- por encenderlo — es el mismo blindaje que la 0115 usó con la pensión.
  select pl.valor into v_exige_decl
  from parametros_laborales pl
  where pl.clave = 'movilidad_exige_declaracion'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_exige_decl is null then v_exige_decl := 0; end if;

  -- ⇩⇩⇩ CAMBIO 0166 ⇩⇩⇩ EL RESPALDO TIENE QUE SER LA FILA GENERAL, NO UNA CUALQUIERA.
  --
  -- Faltaba `sede_codigo is null`. Sin eso esta consulta miraba TODAS las filas
  -- de movilidad y se quedaba con la de fecha mas reciente: las de AQP, LIM y
  -- TRU son del 2026-07-29 y la general es del 2020, asi que el respaldo se
  -- quedaba con el pasaje de una ciudad cualquiera —la que el motor devolviera
  -- primero entre las tres empatadas— en vez de con el cero de la fila general.
  --
  -- Efecto real: quien esta en una sede sin tarifa propia no cobraba S/ 0.00,
  -- cobraba el pasaje de otra ciudad. Un cero se ve y se corrige; un monto
  -- plausible de otra ciudad no se nota nunca. Y es justo lo que el Exp.
  -- 01038-2019 castiga: un monto que no atiende a ningun criterio objetivo.
  --
  -- Encontrado el 2026-08-05 auditando esta misma migracion contra el Postgres
  -- local: el caso de control —Central sin sede fisica— debia dar 0.00 y dio
  -- 10.00. No lo encontro nadie leyendo; lo encontro correr el calculo.
  select pl.valor into v_movilidad
  from parametros_laborales pl
  where pl.clave = 'movilidad_diaria'
    and pl.sede_codigo is null
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;

  if v_movilidad is null then
    select coalesce((valor->>'monto')::numeric, 0) into v_movilidad
    from configuracion where clave = 'movilidad_diaria';
  end if;
  if v_movilidad is null then v_movilidad := 0; end if;

  select coalesce((valor->>'tasa')::numeric, 0) into v_tasa_afp
  from configuracion where clave = 'tasa_afp';
  if v_tasa_afp is null then v_tasa_afp := 0; end if;

  -- ⇩⇩⇩ CAMBIO 0116 ⇩⇩⇩ EL ESSALUD, DESDE UNA TABLA VERSIONADA.
  --
  -- La RMV y la tasa NO van en 'configuracion' a propósito. Esa tabla guarda
  -- valores globales SIN fecha, así que el día que la RMV suba de 1,130 a 1,200
  -- todos los periodos ya pagados se recalcularían con el valor nuevo — el mismo
  -- defecto que tenían movilidad_diaria y tasa_afp. Aquí se elige la fila vigente
  -- al FIN del periodo, que además es lo que manda la norma: el piso se congela
  -- con la RMV vigente al último día calendario del período declarado.
  select pl.valor into v_rmv
  from parametros_laborales pl
  where pl.clave = 'rmv'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_rmv is null then v_rmv := 0; end if;

  select pl.valor into v_tasa_essalud
  from parametros_laborales pl
  where pl.clave = 'tasa_essalud'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_tasa_essalud is null then v_tasa_essalud := 0; end if;

  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_feriados
  from feriados f
  where f.fecha between p_ini and p_fin;

  with pers as (
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, p.fecha_ingreso, p.sueldo_fijo,
           p.sueldo_base_legal,   -- CAMBIO 0105
           p.regimen_pension,     -- CAMBIO 0114
           p.tipo_vinculo, p.en_planilla,   -- CAMBIO 0117
           p.personal_direccion,  -- CAMBIO 0187 · art. 5 D.S. 007-2002-TR
           s.codigo as sede,
           -- CAMBIO 0166 · la sede que decide la MOVILIDAD es donde la persona
           -- trabaja de verdad, no su area administrativa. Central no es una
           -- ciudad: es un rotulo. Quien esta en CCO pero trabaja dentro de la
           -- tienda de Arequipa paga pasaje de Arequipa. Sin sede fisica cargada
           -- manda su sede base, asi que nadie cambia salvo quien se declare.
           coalesce(sf.codigo, s.codigo) as sede_movilidad,
           p.cobra_movilidad   -- CAMBIO 0166
    from personas p
    join sedes s on s.id = p.sede_base_id
    left join sedes sf on sf.id = p.sede_fisica_id
    where p.estado = 'activo'
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between p_ini and p_fin)
       or (p_periodo_id is not null and exists (
             select 1 from movimientos_planilla m
             where m.persona_id = p.id and m.periodo_id = p_periodo_id))
  ),
  horas as (
    select j.persona_id, j.fecha,
           coalesce(j.horas_trabajadas, 0) as h,
           (j.estado = 'auto_cerrada_pendiente') as pendiente
    from jornadas j
    where j.fecha between p_ini and p_fin
  ),
  -- ⇩⇩⇩ CAMBIO 0185 ⇩⇩⇩ Sobretiempo (D.S. 007-2002-TR arts. 9 y 10)
  --
  -- Se lee desde SIETE DÍAS ANTES de p_ini a propósito: un ciclo que empezó en
  -- el periodo anterior tiene que medirse entero o el exceso desaparece. Solo se
  -- PAGA lo que cae dentro del periodo — el filtro está más abajo, en `sobret`.
  --
  -- Se filtran las horas <= 0: el auto-cierre puede dejar jornadas negativas
  -- cuando la salida sintética queda antes de la entrada, y una negativa dentro
  -- de un ciclo bajaría el acumulado y escondería un exceso real.
  ot_dias as (
    select j.persona_id, j.fecha, j.horas_trabajadas as h
    from jornadas j
    where j.fecha between p_ini - 7 and p_fin
      and coalesce(j.horas_trabajadas, 0) > 0
  ),
  -- Rachas de días consecutivos. Un descanso las corta: en días seguidos, la
  -- fecha menos su número de orden da siempre el mismo valor.
  ot_islas as (
    select persona_id, fecha, h,
           fecha - (row_number() over (partition by persona_id order by fecha))::int as isla
    from ot_dias
  ),
  -- Dentro de cada racha, bloques de 7 días. Un ciclo = (racha, bloque), y los
  -- ciclos NO se solapan: por eso ninguna hora se paga dos veces.
  --
  -- El corte a 7 días es lo que hace que doce días seguidos de 8 h se midan como
  -- dos ciclos (56 h y 40 h → 8 h de exceso) y no como uno de 96 h → 48 h. El
  -- tope de 48 es SEMANAL: doce días son casi dos semanas y se miden como dos.
  ot_ciclos as (
    select persona_id, fecha, h, isla,
           ((row_number() over (partition by persona_id, isla order by fecha) - 1) / 7)::int as bloque
    from ot_islas
  ),
  -- El exceso se imputa AL DÍA en que el acumulado del ciclo cruza las 48 y a
  -- los siguientes. Así cada hora extra tiene una fecha, y las que caen en un
  -- periodo ya pagado se quedan fuera solas.
  ot_exceso as (
    select persona_id, fecha,
           greatest(0, least(h, sum(h) over (partition by persona_id, isla, bloque order by fecha) - 48)) as h_exceso
    from ot_ciclos
  ),
  -- El recargo se cuenta POR DÍA y se reinicia cada día: 25 % las dos primeras
  -- horas de ese día, 35 % las siguientes (D.S. 007-2002-TR art. 10). Lo que se
  -- guarda son las horas EQUIVALENTES de recargo — las horas en sí ya están
  -- pagadas dentro de pago_base, y sumarlas otra vez sería pagarlas dos veces.
  sobret as (
    select persona_id,
           sum(h_exceso) as horas,
           sum(least(h_exceso, 2) * 0.25 + greatest(h_exceso - 2, 0) * 0.35) as horas_recargo,
           min(fecha) as desde, max(fecha) as hasta
    from ot_exceso
    where h_exceso > 0 and fecha between p_ini and p_fin
    group by persona_id
  ),
  -- ⇧⇧⇧ CAMBIO 0185 ⇧⇧⇧
  tramos as (
    select a.persona_id, a.rango, a.salario_mensual_soles as salario,
           a.base_provision,                                   -- CAMBIO 0111
           greatest(a.vigente_desde, p_ini) as t_ini,
           least(coalesce(a.vigente_hasta, p_fin), p_fin) as t_fin
    from asignaciones_salario a
    where a.vigente_desde <= p_fin
      and (a.vigente_hasta is null or a.vigente_hasta >= p_ini)
  )
  select jsonb_build_object(
    'fecha_ini', p_ini,
    'fecha_fin', p_fin,
    'anio_etiqueta', v_anio,
    'mes_etiqueta', v_mes,
    'dias', v_dias,
    'base_horas', v_base,
    'feriados', v_feriados,
    'factores_provision', v_prov,
    'asignacion_monto', v_asig,
    'filas', coalesce(jsonb_agg(sub.fila order by sub.orden_nombre), '[]'::jsonb)
  )
  into v_out
  from (
    select (pe.nombres || ' ' || pe.apellidos) as orden_nombre,
      jsonb_build_object(
        'persona_id', pe.id,
        'nombre', pe.nombres || ' ' || pe.apellidos,
        'sede', pe.sede,
        'estado', pe.estado,
        'fecha_ingreso', pe.fecha_ingreso,
        'rango', ref.rango,
        'salario_ref', ref.salario,
        'horas_mes', round(h.horas_mes, 2),
        'dias_trabajados', h.dias,
        -- ⇩ CAMBIO 0110 ⇩ MOVILIDAD SUPEDITADA A LA ASISTENCIA.
        -- Se devenga por DÍA EFECTIVAMENTE ASISTIDO, que es el requisito del
        -- Art. 19 inciso e) del D.S. 001-97-TR: «el valor del transporte, siempre
        -- que esté supeditado a la asistencia al centro de trabajo». h.dias cuenta
        -- los días con horas > 0, así que si no vino, no la cobra, sin que nadie
        -- tenga que acordarse. La Res. 239-2020-SUNAFIL declaró remunerativa una
        -- movilidad de monto razonable justamente por pagarse 30 días cuando se
        -- laboraban 6.
        'monto_movilidad', round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla then 1 else 0 end)
          -- CAMBIO 0166: quien no devenga movilidad (se cubre por viaticos) no la devenga
          * (case when pe.cobra_movilidad then 1 else 0 end)
          -- CAMBIO 0159: sin declaracion firmada no devenga, si el candado esta encendido
          * (case when v_exige_decl > 0 and not decl.tiene_declaracion then 0 else 1 end), 2),   -- CAMBIO 0142
        'movilidad_diaria', tar.tarifa,
        -- ⇩ CAMBIO 0159 ⇩ Para que la pantalla pueda decir POR QUÉ salió cero.
        -- «Un cero no explica nada» (0100): sin esto, quien mire la planilla vería
        -- movilidad 0.00 y no sabría si es que no marcó o si le falta el papel.
        'movilidad_sin_declaracion', (v_exige_decl > 0 and not decl.tiene_declaracion),
        -- ⇩ CAMBIO 0110 ⇩ DESCUENTO DE AFP/ONP, visible en la boleta.
        -- Se calcula sobre la REMUNERACIÓN ASEGURABLE: la básica legal proporcional
        -- más la asignación familiar, que también es remuneración (Ley 25129). No
        -- entran la movilidad ni los bonos no remunerativos.
        -- Sale 0 para quien no tenga básica legal fijada (sueldo fijo: socios,
        -- dirección), porque para ellos pb.basica es 0.
        'descuento_afp',
          round(bri.base * coalesce(tpen.tasa, v_tasa_afp), 2),
        'tasa_afp', coalesce(tpen.tasa, v_tasa_afp),
        'regimen_pension', pe.regimen_pension,          -- CAMBIO 0114
        'tasa_es_del_regimen', (tpen.tasa is not null),  -- CAMBIO 0114
        'dias_pendientes', h.pendientes,
        -- ⇩ CAMBIO 0100 ⇩ por qué esta persona está en cero. Sin esto, «de
        -- vacaciones», «no marcó» y «sin salario» se ven exactamente igual: 0.
        'dias_vacaciones', vac.dias,
        'dias_laborables', lab.dias,
        'horas_sin_salario', round(pb.horas_sin_salario, 2),
        'pago_base', round(pb.pago_base, 2),
        -- CAMBIO 0105 — Desglose legal. Sale en cuanto la persona tiene básica
        -- legal fijada: ya NO hace falta puntuación, porque sin fila el defecto es
        -- 100 y el pago es el mismo de siempre. Sin básica legal sigue saliendo
        -- NULL y la boleta muestra el pago sin partir, antes que inventar una
        -- separación. Los de sueldo fijo (socios, dirección) quedan fuera.
        -- La básica tal cual, sin prorratear: la pantalla de Planilla la necesita
        -- para poder editarla en su celda.
        'sueldo_base_legal', pe.sueldo_base_legal,
        'basica_legal_prop',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else round(pb.basica, 2) end,
        'complemento_variable',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else round(pb.pago_base, 2) - round(pb.basica, 2) end,
        'rendimiento_pct',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else coalesce(rmp.porcentaje, 100) end,
        -- true cuando el 100 es el defecto y no una decisión escrita. Sirve para
        -- que la pantalla distinga «nadie lo ha puntuado» de «lo puntuaron 100».
        'rendimiento_por_defecto', (rmp.porcentaje is null),
        -- El coalesce va AQUÍ y no dentro del lateral: sin fila el lateral no
        -- devuelve nada, así que rmp.etiqueta sería NULL y la boleta se quedaría
        -- sin nombre en la fila del complemento.
        'complemento_etiqueta',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else coalesce(rmp.etiqueta, 'Rendimiento Extraordinario') end,
        'feriados_detalle', fer.detalle,
        'monto_feriados', round(fer.monto, 2),
        'feriados_no_corresponde', fer.no_corresponde,
        'feriados_compensados', fer.compensados,
        'objetivos_cumplidos', obj.cumplidos,
        'objetivos_total', obj.total,
        'monto_plus', round(obj.monto, 2),
        'bajo_desempeno', (obj.cumplidos is not null and obj.total > 0
                           and obj.cumplidos::numeric / obj.total < 0.3),
        'feriados_sin_salario', fer.sin_tramo,
        'con_hijos', pe.con_hijos,
        'asignacion_familiar', case when pe.con_hijos then round(v_asig, 2) else 0 end,
        'bonos', round(mov.bonos, 2),
        'descuentos', round(mov.descuentos, 2),
        'movimientos', mov.detalle,
        -- ⇩ CAMBIO 0113 ⇩ La base de provisión incluye la ASIGNACIÓN FAMILIAR.
        -- Los S/113 de la Ley 25129 son remuneración, así que integran la
        -- remuneración computable de gratificación, CTS y vacaciones. Antes se
        -- pagaban como línea aparte y quedaban fuera de la base.
        --
        -- ⇩⇩⇩ CAMBIO 0111 ⇩⇩⇩ Las cuatro provisiones llevan un FACTOR.
        --
        -- POR QUÉ EXISTE. La 0110 permite bajar el rango a la básica legal para que
        -- el Rendimiento Extraordinario desaparezca (la fórmula lo anula sola cuando
        -- rango = básica). Pero las provisiones se calculan sobre pago_base, así que
        -- bajar el rango de 1,320 a 1,130 les recortaría la gratificación, la CTS y
        -- las vacaciones en un 14.4% — unos S/422 al año por persona. Eso es plata
        -- del equipo, no del empleador, y Felipe decidió no tocarla.
        --
        -- CÓMO FUNCIONA. factor = base_provision / salario. Si base_provision está
        -- en NULL el factor sale 1 y NADA cambia: la migración se puede pegar sin
        -- que ninguna provisión se mueva. Si se pone en 1,320 mientras el salario es
        -- 1,130, el factor es 1.1681 y las provisiones quedan idénticas a las de
        -- antes de bajar el rango.
        --
        -- POR QUÉ UN FACTOR Y NO OTRA BASE. pago_base y feriados escalan LINEALMENTE
        -- con el salario del tramo (los dos usan tt.salario), así que multiplicar el
        -- resultado por el factor da exactamente lo mismo que haber calculado todo
        -- con el salario viejo. Verificado: (1,090.74 + 165.43) × 1.1681 = 1,467.33
        -- contra (1,274.14 + 193.25) = 1,467.39 con el rango en 1,320.
        --
        -- LO QUE NO CAMBIA: la movilidad sigue FUERA de esta base. El factor
        -- multiplica (pago_base + feriados), no la movilidad ni el AFP.
        'provision_gratificacion',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * v_f_grati, 2),
        -- CAMBIO 0134 — se calcula del MISMO numero que la gratificacion, nunca
        -- de una base propia: si manana cambia la formula de la grati, esta la
        -- sigue sola. Es la linea 0312 del PLAME.
        'provision_bonif_extraordinaria',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * v_f_grati * v_f_be, 2),
        'provision_cts',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * v_f_cts * (1 + v_sexto_cts), 2),
        'provision_vacaciones',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * v_f_vacas, 2),
        'provision_total',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * (v_f_grati * (1 + v_f_be) + v_f_cts * (1 + v_sexto_cts) + v_f_vacas), 2),   -- CAMBIO 0134
        -- Para que la pantalla pueda mostrar sobre qué base se provisionó.
        'base_provision', ref.base_provision,
        'factor_provision', coalesce(ref.base_provision / nullif(ref.salario, 0), 1),
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
                 + (case when pe.con_hijos then round(v_asig, 2) else 0 end)
                 + round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla then 1 else 0 end)
          -- CAMBIO 0159: sin declaracion firmada no devenga, si el candado esta encendido
          * (case when v_exige_decl > 0 and not decl.tiene_declaracion then 0 else 1 end), 2)              -- CAMBIO 0142
                 + round(coalesce(edu.monto, 0) * (case when pe.en_planilla then 1 else 0 end), 2)   -- CAMBIO 0120
                 - round((bri.base)
                         * coalesce(tpen.tasa, v_tasa_afp), 2)                                    -- CAMBIO 0110
                 + round(mov.bonos, 2) - round(mov.descuentos, 2)
                 -- CAMBIO 0185 · el recargo del sobretiempo. Solo el RECARGO:
                 -- las horas ya están dentro de pago_base.
                 + round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2)
      )
      || jsonb_build_object(
        -- ⇩⇩⇩ CAMBIO 0116 ⇩⇩⇩ EL APORTE DE ESSALUD QUE PAGA CAYLA.
        --
        -- NO entra en el 'total' y no debe entrar nunca: el 9% es íntegramente de
        -- cargo del empleador (Ley 26790 art. 6). Descontárselo al trabajador
        -- sería una retención ilegal. Va como dato, para que cada integrante vea
        -- lo que la empresa paga por él — que es lo que Felipe pidió el 2026-07-31.
        --
        -- LA BASE LLEVA PISO, y es lo que más se equivoca. La base imponible
        -- mínima mensual no puede ser inferior a la RMV, y ese piso se aplica
        -- «independientemente de las horas y días laborados» (reglamento de la
        -- Ley 26790, D.S. 009-97-SA modificado por el D.S. 020-2006-TR; criterio
        -- confirmado en el Informe 003-2007-SUNAT/2B0000).
        --
        -- O sea: por alguien que trabajó 6 h 35 min y devengó S/36.96, la empresa
        -- NO aporta 9% × 36.96 = S/3.33. Aporta 9% × 1,130 = S/101.70 — el mismo
        -- monto que por alguien de mes completo. Prorratear RMV/30 × días está
        -- expresamente prohibido, salvo el caso de subsidios (descanso médico,
        -- maternidad), que esta función todavía NO modela.
        --
        -- Consecuencia de gestión: el costo de EsSalud lo manda el número de
        -- personas, no el monto de la planilla. Calcularlo como «9% del total de
        -- la planilla» subestima el aporte real cuando hay gente de pocas horas.
        'base_essalud',
          round(greatest(bri.base, v_rmv), 2),
        'aporte_essalud',
          round(greatest(bri.base, v_rmv) * v_tasa_essalud
                * (case when pe.en_planilla then 1 else 0 end), 2),
        'essalud_tasa', v_tasa_essalud,
        -- ⇩⇩⇩ CAMBIO 0117 ⇩⇩⇩ Qué es esta persona para el sistema. Sin este dato
        -- la boleta no puede explicar por qué a alguien no le aparece movilidad ni
        -- EsSalud, y la pantalla de Planilla no puede advertir que un locador con
        -- conceptos laborales encima es un problema.
        -- ⇩ CAMBIO 0120 ⇩ Condicionada a en_planilla igual que la movilidad: un
        -- locador no recibe asignaciones laborales. Y el monto NO se prorratea por
        -- asistencia — es el costo de un estudio, no una compensación por venir.
        'monto_educacion',
          round(coalesce(edu.monto, 0) * (case when pe.en_planilla then 1 else 0 end), 2),
        -- ⇩ CAMBIO 0150 ⇩ Para que la boleta pueda decir de qué institución sale
        -- ese dinero. Una línea que dice sólo «S/270» no le permite a la persona
        -- cuadrar su propio pago, y un concepto no remunerativo que no se
        -- identifica es el que se reclasifica como sueldo.
        'instituciones_educacion',
          case when pe.en_planilla then edu.instituciones else null end,
        'tipo_vinculo', pe.tipo_vinculo,
        'en_planilla', pe.en_planilla,
        -- true cuando el piso fue lo que decidió la base, o sea cuando la persona
        -- devengó MENOS que la RMV. Sirve para que la boleta pueda explicarlo en
        -- vez de mostrar un número que no cuadra con el sueldo del mes.
        'essalud_es_piso',
          (bri.base) < v_rmv
      )
      -- ⇩ CAMBIO 0177 ⇩ Se CONCATENA en vez de ampliar el jsonb_build_object de
      -- arriba: ese ya tiene 57 pares y Postgres corta a 100 ARGUMENTOS. Agregar
      -- dos claves más ahí revienta con «cannot pass more than 100 arguments to
      -- a function», y no al escribirla sino al EJECUTARLA. Quien agregue el
      -- siguiente campo del JSON tiene que hacerlo acá.
      || jsonb_build_object(
        'monto_vacaciones', round(pb.monto_vacaciones, 2),
        'dias_vacaciones_pagados', pb.dias_vacaciones_pagados,
        -- CAMBIO 0185 · las tres piezas que la boleta necesita para explicarse:
        -- cuánto, cuántas horas y cuándo. Un monto pelado no se puede verificar
        -- contra el registro de asistencia, que es lo que lo sostiene.
        'monto_sobretiempo', round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2),
        'horas_sobretiempo', round(coalesce(ot.horas, 0), 2),
        'sobretiempo_desde', ot.desde,
        'sobretiempo_hasta', ot.hasta
      ) as fila
    from pers pe
    -- ⇩ CAMBIO 0142 ⇩ La tarifa de movilidad de LA SEDE de esta persona.
    --
    -- Antes era un escalar unico para las tres ciudades. Pero el Art. 19 inciso e)
    -- del D.S. 001-97-TR pide que el monto «razonablemente cubra el respectivo
    -- traslado», y el traslado no cuesta lo mismo en Arequipa que en Lima.
    --
    -- Una tarifa uniforme fijada al caso mas caro deja a las otras ciudades
    -- pagando por encima de su costo real, y ese exceso es lo que se reclasifica.
    -- El Exp. 01038-2019 de Lima Norte tumbo una movilidad ENTERA —no solo el
    -- exceso— porque el monto «depende del mero arbitrio del empleador sin
    -- atender a los lugares de residencia ni a otros criterios objetivos». Una
    -- tarifa que sigue al pasaje de cada ciudad es exactamente ese criterio.
    --
    -- Sin fila para su sede cae al valor general, asi que una base sin las filas
    -- nuevas se comporta exactamente igual que antes.
    cross join lateral (
      select coalesce((
        select pl.valor
        from parametros_laborales pl
        where pl.clave = 'movilidad_diaria'
          and pl.sede_codigo = pe.sede_movilidad   -- CAMBIO 0166
          and pl.vigente_desde <= p_fin
          and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
        order by pl.vigente_desde desc
        limit 1
      ), v_movilidad) as tarifa
    ) tar
    -- ⇩⇩⇩ CAMBIO 0159 ⇩⇩⇩ ¿Tiene su declaración de ruta firmada?
    --
    -- Cuenta si está firmada en o antes del fin del periodo: el papel tiene que
    -- existir antes de que el pago se haga, no antes de que el periodo empiece.
    -- Firmar a mitad de mes cubre ese mes, que es lo indulgente y lo defendible.
    --
    -- Una NEGATIVA no habilita: se documenta que se ofreció, pero sin pacto
    -- individual firmado el monto deja de ser no remunerativo, y pagarlo igual
    -- es exactamente lo que la RTF 05449-4-2007 sancionó — con el agravante de
    -- que el acta deja por escrito que la persona se negó.
    cross join lateral (
      select exists (
        select 1 from documentos_firmados d
        where d.tipo = 'ruta'
          and d.persona_id = pe.id
          and d.anulado_at is null
          and not d.es_negativa
          and d.fecha_firma <= p_fin
      ) as tiene_declaracion
    ) decl
    left join lateral (
      select coalesce(sum(x.h), 0) as horas_mes,
             count(*) filter (where x.h > 0) as dias,
             count(*) filter (where x.pendiente) as pendientes
      from horas x where x.persona_id = pe.id
    ) h on true
    left join lateral (
      -- CAMBIO 0105 — Puntuación de rendimiento del mes.
      --
      -- SIN FILA, EL DEFECTO ES 100 (decidido con Felipe el 2026-07-28). Eso no
      -- le cambia el sueldo a nadie: al 100% la fórmula da
      -- básica + (rango − básica) = el rango exacto, que es lo que ya se pagaba.
      -- Lo que sí gana es que la boleta muestre la estructura legal en TODAS,
      -- desde el primer mes, en vez de solo en las de quien tenga puntuación.
      -- Para bajarle a alguien hay que escribir su fila a mano: el sistema nunca
      -- recorta por omisión.
      select rm.porcentaje,
             coalesce(ec.etiqueta, 'Rendimiento Extraordinario') as etiqueta
      from rendimiento_mensual rm
      left join etiquetas_complemento ec on ec.codigo = rm.etiqueta_codigo
      where rm.persona_id = pe.id and rm.anio = v_anio and rm.mes = v_mes
      limit 1
    ) rmp on true
    left join lateral (
      -- SUELDO FIJO: quien lo tiene cobra su remuneración completa del periodo,
      -- marque o no (socios, dirección). Para el resto la fórmula es EXACTAMENTE
      -- la de siempre — la rama `else` es idéntica a la anterior, así que ningún
      -- pago existente se mueve.
      -- ⇩ CAMBIO 0177 ⇩ Un día de vacaciones vale el PROMEDIO de lo que se le
      -- pagó por día trabajado en el periodo. Es literal el art. 15 del D. Leg.
      -- 713: «la remuneración que hubiera percibido de continuar laborando».
      -- Se deriva de hh.pago en vez de recalcular el salario, para que cualquier
      -- cambio futuro en la fórmula del sueldo arrastre solo, sin dos verdades.
      -- Sueldo fijo no lo suma: ya cobra el periodo completo, marque o no.
      -- `horas_vacaciones` es el mismo día expresado en HORAS, y lo usa el bloque
      -- `fer`: si el día cuenta como trabajado para el sueldo, cuenta también
      -- para el prorrateo del feriado. Tenerlo en un solo sitio evita que el
      -- mismo día sea «trabajado» en una línea y «no trabajado» en la de al lado.
      select case when pe.sueldo_fijo then coalesce(sf.salario, 0)
                  else coalesce(hh.pago, 0)
                       + coalesce(hh.pago / nullif(hh.dias_marcados, 0), 0)
                         * coalesce(vacd.dias, 0) end as pago_base,
             case when pe.sueldo_fijo then 0
                  else coalesce(hh.pago / nullif(hh.dias_marcados, 0), 0)
                       * coalesce(vacd.dias, 0) end as monto_vacaciones,
             case when pe.sueldo_fijo then 0
                  else coalesce(hh.horas_totales / nullif(hh.dias_marcados, 0), 0)
                       * coalesce(vacd.dias, 0) end as horas_vacaciones,
             coalesce(vacd.dias, 0) as dias_vacaciones_pagados,
             coalesce(hh.basica, 0) as basica,   -- CAMBIO 0105
             coalesce(hh.sin_sal, 0) as horas_sin_salario
      from (select 1) _sf
      left join lateral (
        -- ⇩ CAMBIO 0105 ⇩ El salario del día deja de ser un bloque único: es la
        -- básica legal más la brecha hasta el rango, multiplicada por la
        -- puntuación del mes (100 si no hay fila). Dos guardas para que nunca
        -- pague de menos por descuido:
        --   · sin básica legal fijada → el salario del tramo, como siempre
        --   · si el tramo está por debajo de la básica → el tramo, sin subirlo
        -- Y la propiedad que lo hace seguro: al 100%, base + (rango − base) es
        -- el rango exacto, así que el defecto no mueve ningún pago.
        select coalesce(sum(case when tt.salario is not null then x.h * (
                 case
                   when pe.sueldo_base_legal is null then tt.salario
                   when tt.salario <= pe.sueldo_base_legal then tt.salario
                   -- CAMBIO 0171 · el rendimiento ya no escala el sueldo.
                   -- Antes: basica + (salario - basica) x porcentaje/100. Al 100%
                   -- daba el salario exacto, pero escribir un 80 le recortaba el
                   -- sueldo a una persona con dos clics. Ahora se paga el tramo.
                   else tt.salario
                 end
               ) / v_base end), 0) as pago,
               -- La parte que corresponde a la básica legal NO se escala por la
               -- puntuación: es lo fijo. Se prorratea solo por horas.
               coalesce(sum(case when tt.salario is not null and pe.sueldo_base_legal is not null
                                 then x.h * least(pe.sueldo_base_legal, tt.salario) / v_base end), 0) as basica,
               coalesce(sum(case when tt.salario is null then x.h end), 0) as sin_sal,
               -- CAMBIO 0177 · cuánto vale UN día de esta persona, en soles y en
               -- horas, sin volver a derivar su salario ni su jornada.
               count(*) filter (where x.h > 0) as dias_marcados,
               coalesce(sum(x.h), 0) as horas_totales
        from horas x
        left join lateral (
          select t.salario from tramos t
          where t.persona_id = x.persona_id and x.fecha between t.t_ini and t.t_fin
          order by t.t_ini desc limit 1
        ) tt on true
        where x.persona_id = pe.id
      ) hh on true
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id
        order by t.t_fin desc, t.t_ini desc limit 1
      ) sf on true
      -- ⇩⇩⇩ CAMBIO 0177 ⇩⇩⇩ Días del periodo que esta persona pasó de vacaciones
      -- Y que además le tocaba trabajar. Los domingos dentro del rango no se
      -- cuentan: no los habría trabajado, así que pagarlos sería pagar de más.
      -- La condición de «¿le tocaba?» es LA MISMA que usa el bloque `lab` y que
      -- usan las faltas (0054, 0060): horario_por_dia si existe, dias_laborables si no.
      left join lateral (
        select count(*)::int as dias
        from generate_series(p_ini, p_fin, interval '1 day') d
        join lateral (
          select ha.dias_laborables, ha.horario_por_dia
          from horarios_asignados ha
          where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
          order by ha.vigente_desde desc limit 1
        ) hv on true
        -- ⇩ CAMBIO 0186 ⇩ Solo a quien está en planilla. Un locador no tiene
        -- vacaciones: no son un permiso, son un beneficio social de una relación
        -- laboral. Va acá arriba y no en el `select` de fuera porque `vacd.dias`
        -- alimenta tres columnas —pago_base, monto_vacaciones y horas_vacaciones—
        -- y filtrar en una sola dejaría el día siendo «pagado» en un sitio y
        -- «no trabajado» en otro. Es el mismo cuidado que la 0177 se tomó con el
        -- feriado. Ver la cabecera para por qué esto es más que un monto.
        where pe.en_planilla
          and exists (
                select 1 from vacaciones v
                where v.persona_id = pe.id
                  and d.d::date between v.fecha_inicio and v.fecha_fin)
          and case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                else extract(dow from d.d)::int = any(hv.dias_laborables)
              end
      ) vacd on true
      -- ⇧⇧⇧ CAMBIO 0177 ⇧⇧⇧
    ) pb on true
    -- ⇩ CAMBIO 0185 ⇩ El sobretiempo de esta persona, si lo hubo.
    --
    -- NO aplica a RxH ni a sueldo fijo, y por motivos distintos:
    --   · RxH: un locador no tiene jornada de trabajo. Pagarle horas extras
    --     sería un indicio de laboralidad, igual que la movilidad supeditada a
    --     asistencia que la 0117 ya le quitó.
    --   · Sueldo fijo: el art. 5 del D.S. 007-2002-TR excluye de la jornada
    --     máxima al personal de dirección y a quien no está sujeto a
    --     fiscalización inmediata — que es exactamente quién tiene sueldo fijo
    --     acá. Y su pago no depende de horas: calcular recargo sobre un monto
    --     fijo no significaría nada.
    left join lateral (
      select s.horas, s.horas_recargo, s.desde, s.hasta
      from sobret s
      where s.persona_id = pe.id
        and pe.en_planilla is true
        and pe.sueldo_fijo is not true
        -- ⇩ CAMBIO 0187 ⇩ Personal de dirección. Es una tercera exclusión, no
        -- una variante de las dos de arriba: cobra por horas (no tiene sueldo
        -- fijo) y está en planilla (no es locador). Lo que la deja fuera es una
        -- categoría laboral, y por eso vive en su propia columna.
        and pe.personal_direccion is not true
    ) ot on true
    left join lateral (
      select t.rango, t.salario, t.base_provision              -- CAMBIO 0111
      from tramos t
      where t.persona_id = pe.id
      order by t.t_fin desc, t.t_ini desc
      limit 1
    ) ref on true
    -- ⇩⇩⇩ CAMBIO 0114 ⇩⇩⇩ La tasa de pensión EXACTA de esta persona.
    --
    -- Hasta la 0113 el descuento usaba una sola tasa global (configuracion.tasa_afp,
    -- el 13% aproximado). Ahora sale del régimen de cada uno: Profuturo cobra
    -- 13.06%, Integra 12.92%, Prima 12.97%, Habitat 12.84% y la ONP 13.00% exacto.
    --
    -- Se elige la fila VIGENTE a la fecha de fin del periodo, no la última: así un
    -- periodo de mayo se calcula con la comisión que estaba vigente en mayo, aunque
    -- la AFP la haya cambiado en junio. Las comisiones se mueven, y la prima de
    -- seguro la actualiza la SBS cada trimestre.
    --
    -- SI LA PERSONA NO TIENE RÉGIMEN ASIGNADO, el lateral no devuelve fila y más
    -- abajo el coalesce cae a la tasa global. Así nadie se queda sin descuento por
    -- un dato faltante, y la migración se puede aplicar aunque falten personas por
    -- clasificar.
    left join lateral (
      select tp.aporte + tp.comision + tp.prima as tasa
      from tasas_pension tp
      where tp.regimen = pe.regimen_pension
        and tp.vigente_desde <= p_fin
        and (tp.vigente_hasta is null or tp.vigente_hasta >= p_fin)
      order by tp.vigente_desde desc
      limit 1
    ) tpen on true
    -- ⇩⇩⇩ CAMBIO 0120 ⇩⇩⇩ LA ASIGNACIÓN POR EDUCACIÓN, por persona y con vigencia.
    --
    -- Por persona y no por rango porque depende del curso que cada uno lleva y de
    -- que traiga su comprobante. Dos personas del mismo rango pueden tener montos
    -- distintos, y eso no es un problema: es lo correcto, porque cada monto sigue
    -- el costo real de SU estudio. Que fueran todos iguales sería la señal de que
    -- el monto no sale de un comprobante sino de una resta.
    --
    -- Con vigencia porque alguien deja de estudiar en diciembre y en enero su
    -- asignación tiene que ser cero sin reescribir los meses en que sí estudió.
    -- ⇩⇩⇩ CAMBIO 0150 ⇩⇩⇩ Tres cambios, cada uno cerrando un agujero medido:
    --
    --   SUM y no LIMIT 1 · quien estudia y además tiene un hijo estudiando tenía
    --     dos filas y cobraba una; la otra se descartaba en silencio. El techo
    --     del rango se valida sobre la suma desde la 0149, así que sumar acá no
    --     puede pasarse del techo.
    --
    --   comprobante_url is not null · sin el papel no se paga. Una asignación se
    --     puede guardar mientras el comprobante llega (queda en amarillo en la
    --     pantalla), pero no devenga hasta que el papel esté cargado. Es lo que
    --     mantiene al concepto fuera de la remuneración: pagar sin comprobante es
    --     el caso exacto que la RTF 05449-4-2007 usó para desconocerlo.
    --
    --   p_ini y no p_fin · antes exigía seguir vigente el ÚLTIMO día del periodo,
    --     así que un ciclo que terminaba el 15 hacía que ese mes pagara CERO —
    --     habiendo estudiado y pagado la pensión del mes. Ahora basta con estar
    --     vigente al INICIAR el periodo y se paga el mes completo, que es como
    --     factura la institución.
    left join lateral (
      select sum(ae.monto) as monto,
             string_agg(distinct ae.institucion, ' · ') as instituciones
      from asignaciones_educacion ae
      where ae.persona_id = pe.id
        and ae.comprobante_url is not null
        and ae.vigente_desde <= p_ini
        and ae.vigente_hasta >= p_ini
    ) edu on true
    -- feriados: solo cuentan los que caen EN o DESPUÉS del ingreso de la persona
    left join lateral (
      -- ⇩⇩⇩ CAMBIO 0069 ⇩⇩⇩
      -- `ds.otorgado` = ese feriado se compensó con día libre (acta firmada).
      -- Cuando es true se anula el pago EXTRA de las horas laboradas (la
      -- sobretasa) y queda solo el día de feriado prorrateado — el feriado vale
      -- lo mismo que si no se hubiera trabajado. Las horas siguen pagadas en
      -- `pago_base`. Para volver a la lectura literal "adicional = 0",
      -- reemplazar todo el paréntesis por `0`.
      select coalesce(sum(case when tt.salario is not null and f.fecha >= pe.fecha_ingreso
               then ((case when ds.otorgado then 0 else coalesce(hf.h, 0) end)
                     + (case when pe.sueldo_fijo then 0
                             -- CAMBIO 0177 · + horas de vacaciones: son tiempo
                             -- remunerado, así que entran al prorrateo del feriado.
                             else 7.5 * (h.horas_mes + coalesce(pb.horas_vacaciones, 0))
                                  / v_base end)) * tt.salario / v_base end), 0) as monto,
             count(*) filter (where tt.salario is null and f.fecha >= pe.fecha_ingreso) as sin_tramo,
             count(*) filter (where f.fecha < pe.fecha_ingreso) as no_corresponde,
             count(*) filter (where ds.otorgado) as compensados,
             coalesce(jsonb_agg(jsonb_build_object(
               'fecha', f.fecha,
               'horas_trabajadas', coalesce(hf.h, 0),
               'proporcional_horas', case when f.fecha >= pe.fecha_ingreso
                                          then round(case when pe.sueldo_fijo then 0
                                                     else 7.5 * (h.horas_mes + coalesce(pb.horas_vacaciones, 0))
                                                          / v_base end, 2) else 0 end,   -- CAMBIO 0177
               'sin_salario', (tt.salario is null and f.fecha >= pe.fecha_ingreso),
               'antes_ingreso', (f.fecha < pe.fecha_ingreso),
               'descanso_sustitutorio', ds.otorgado,
               'descanso_fecha', ds.fecha_descanso
             ) order by f.fecha), '[]'::jsonb) as detalle
      from feriados f
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id and f.fecha between t.t_ini and t.t_fin
        order by t.t_ini desc limit 1
      ) tt on true
      left join horas hf on hf.persona_id = pe.id and hf.fecha = f.fecha
      left join lateral (
        -- Solo OTORGADO anula la sobretasa. PENDIENTE y NO_OTORGADO pagan
        -- normal — VALIDACIÓN 3: NO_OTORGADO revierte solo, sin tocar nada.
        select true as otorgado, d.fecha_descanso_sustitutorio as fecha_descanso
        from feriados_descanso_sustitutorio d
        where d.persona_id = pe.id and d.fecha_feriado = f.fecha and d.estado = 'OTORGADO'
        limit 1
      ) ds on true
      where f.fecha between p_ini and p_fin
      -- ⇧⇧⇧ CAMBIO 0069 ⇧⇧⇧
    ) fer on true
    left join lateral (
      select om.cumplidos, om.total,
             case
               when om.cumplidos is null or ref.salario is null then 0
               -- CAMBIO 0171 · el plus por objetivos deja de pagar. Antes:
               -- 21% del salario al 100% de metas, 12.6% desde el 60%. Se
               -- devuelven los objetivos (sirven para promover) y cero soles.
               else 0
             end as monto
      from (select 1) uno
      left join objetivos_mensuales om
        on om.persona_id = pe.id and om.anio = v_anio and om.mes = v_mes
    ) obj on true
    -- ⇩ CAMBIO 0100 ⇩ Días del periodo que caen dentro de un periodo de
    -- vacaciones de esta persona. Solo se LEE: esta función nunca escribe.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      where exists (
        select 1 from vacaciones v
        where v.persona_id = pe.id
          and d.d::date between v.fecha_inicio and v.fecha_fin
      )
    ) vac on true
    -- Días que esta persona TENÍA que trabajar según su horario vigente. Si son
    -- cero, no marcó porque no le tocaba: no es una ausencia, es un dato que falta.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia   -- CAMBIO 0109
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hh on true
      -- ⇩⇩⇩ CAMBIO 0109 ⇩⇩⇩ Dos arreglos en una condición.
      --
      -- 1. isodow → dow. Postgres tiene dos funciones de día de semana y devuelven
      --    números distintos para el domingo: dow da 0, isodow da 7. TODO el resto
      --    del sistema usa dow —la 0015 valida el rango 0..6, las faltas (0054, 0060),
      --    el auto-cierre (0036) y la pantalla de Turnos— y el esquema documenta
      --    «0=domingo … 6=sábado». Solo esta línea usaba isodow.
      --    Como el array solo admite 0..6, el domingo únicamente puede guardarse
      --    como 0, e isodow jamás devuelve 0: el domingo NUNCA contaba como día
      --    laborable. En Trujillo se trabaja domingo, así que a esa gente le faltaban
      --    ~4 días al mes en la cuenta.
      --    Ese era el origen del «21 de 10 días que te tocaba trabajar» que apareció
      --    en producción: dias_trabajados sí cuenta domingos y dias_laborables no.
      --    En su momento se corrigió el TEXTO de la boleta; esta es la causa.
      --
      -- 2. Preferir horario_por_dia. La 0016 dejó dicho que dias_laborables queda
      --    como RESUMEN de compatibilidad y que la fuente de verdad es
      --    horario_por_dia (claves 0..6, día ausente = descanso). Las faltas ya lo
      --    leen así; la planilla se había quedado en el campo viejo. Ahora usa el
      --    mismo orden de preferencia que 0054 y 0060, para que no haya dos
      --    respuestas distintas a «¿le tocaba trabajar este día?».
      --
      -- NO MUEVE NINGÚN PAGO. lab.dias se usa en un solo lugar de toda la función:
      -- el campo 'dias_laborables' del JSON. No entra en pago_base, ni en feriados,
      -- ni en las provisiones. El generador lo verifica abajo.
      where case
              when hh.horario_por_dia is not null
                then hh.horario_por_dia ? (extract(dow from d.d)::int::text)
              else extract(dow from d.d)::int = any(hh.dias_laborables)
            end
    ) lab on true
    left join lateral (
      select coalesce(sum(m.monto) filter (where m.tipo = 'bono'), 0) as bonos,
             coalesce(sum(m.monto) filter (where m.tipo = 'descuento'), 0) as descuentos,
             coalesce(jsonb_agg(jsonb_build_object(
               'id', m.id, 'tipo', m.tipo, 'concepto', m.concepto, 'monto', m.monto
             ) order by m.created_at) filter (where m.id is not null), '[]'::jsonb) as detalle
      from movimientos_planilla m
      where p_periodo_id is not null
        and m.periodo_id = p_periodo_id
        and m.persona_id = pe.id
    ) mov on true
    -- ⇩⇩⇩ CAMBIO 0192 ⇩⇩⇩ LA BASE IMPONIBLE, EN UN SOLO SITIO.
    --
    -- Refactor puro: esta migración NO cambia ni un céntimo. Lo único que hace
    -- es dejar de repetir cinco veces la misma expresión.
    --
    -- «básica + asignación familiar» estaba escrita literal en cinco lugares:
    -- descuento_afp, la resta de ese descuento dentro del total, base_essalud,
    -- aporte_essalud y essalud_es_piso. Cinco copias de una regla que la ley
    -- puede cambiar de un día para otro, y donde basta olvidar una para que la
    -- boleta muestre un descuento que no cuadra con su propia base.
    --
    -- Es el mismo patrón que en este repo ya juntó 35 copias de una condición de
    -- permiso y 32 del huso horario de Lima, y se resuelve igual: un solo sitio
    -- que lo diga, y todos leyendo de ahí.
    --
    -- QUÉ PROMETE ESTE BLOQUE
    --   bri.base = la remuneración afecta a EsSalud y a pensión, ANTES del piso
    --   de la RMV. El piso se aplica solo a EsSalud (Ley 26790 art. 6) y por eso
    --   vive fuera de acá: la pensión no tiene piso.
    --
    -- QUÉ ASUME
    --   Que la base sale de pb.basica y NO de pb.pago_base. La diferencia entre
    --   las dos es el complemento variable, y que quede fuera es una decisión de
    --   estructura remunerativa, no un olvido: está sustentada en
    --   docs/analisis-estructura-remunerativa-2026-07-30.md. Al 2026-08-08 esa
    --   diferencia es CERO —se declara el sueldo íntegro, medido: 22 de 22
    --   personas— pero la distinción sigue importando el día que alguien vuelva
    --   a mirar esto.
    left join lateral (
      select coalesce(pb.basica, 0)
             + (case when pe.con_hijos then v_asig else 0 end)
             -- ⇩ CAMBIO 0193 ⇩ Las dos sobretasas legales entran a la base.
             --
             -- No son conceptos que se puedan presentar como no remunerativos:
             -- el art. 19 del D.S. 001-97-TR no las lista, y SUNAT las nombra
             -- una por una con código propio en la PLAME —0105 (sobretiempo al
             -- 25 %), 0106 (al 35 %) y 0107 (feriado o día de descanso)—. No hay
             -- estructura que defender acá; simplemente no se estaban sumando.
             --
             -- El feriado es lo que más pesa, y la razón es que no es un extra
             -- sobre el sueldo: como en CAYLA se paga por horas, quien no marca
             -- el día feriado tiene una básica más baja, y `monto_feriados` es
             -- justo la parte del sueldo que la completa. Sin él se declara
             -- MENOS que el sueldo pactado.
             --
             -- Se leen ya redondeados, igual que en el `total`, para que la base
             -- que imprime la boleta sume exactamente lo que suman sus líneas.
             --
             -- La condición NO es decoración. Las sobretasas COMPLETAN una base
             -- declarada; no pueden crear una donde no la hay:
             --   · Un locador (RxH) no aporta a pensión ni genera EsSalud. Su
             --     básica es 0, así que hoy su descuento es 0 — y sumarle el
             --     feriado se lo inventaría. Medido antes de poner esto: le
             --     aparecían S/41.39 de pensión de la nada.
             --   · Sueldo fijo (socios, dirección) tiene básica 0 a propósito,
             --     y por la misma razón: lo suyo no se declara por esta vía.
             --     Sin la condición le salían S/46.45.
             -- Es la misma condición que usa el lateral `ot` de la 0185, y eso
             -- es a propósito: dos formas distintas de decir «quién queda fuera»
             -- es como se empieza a tener dos verdades.
             + (case when pe.en_planilla is true and pe.sueldo_fijo is not true
                     then round(coalesce(fer.monto, 0), 2)
                          + round(coalesce(ot.horas_recargo, 0)
                                  * coalesce(ref.salario, 0) / v_base, 2)
                     else 0 end)
             as base
    ) bri on true
    -- ⇧⇧⇧ CAMBIO 0192 ⇧⇧⇧
  ) sub;

  return v_out;
end;






$function$

;

insert into migraciones_aplicadas (numero, nombre)
values (193, 'el_feriado_y_el_sobretiempo_entran_a_la_base_de_aportes')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
