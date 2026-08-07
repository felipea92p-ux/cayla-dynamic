-- ============================================================================
-- 0173 — El sueldo fijo deja de cobrar el feriado dos veces
-- ============================================================================
--
-- QUÉ PROMETE
--   Que quien tiene `sueldo_fijo` no reciba el día de feriado prorrateado,
--   porque su remuneración mensual íntegra ya lo contiene. Conserva intacta la
--   sobretasa cuando sí trabajó el feriado: eso no es duplicado, es el art. 8
--   del D. Leg. 713 y le corresponde igual que a todos.
--   Nadie sin `sueldo_fijo` se mueve un centavo.
--
-- QUÉ ASUME
--   La 0171 es la versión vigente de `fn_planilla_calcular` — NO la 0166, que es
--   lo que `./scripts/donde-vive.sh` respondió. El script compara contra el
--   último archivo del directorio de trabajo, y la 0171 se creó en otra sesión
--   mientras esta corría. El cuerpo NO se copió del archivo: se extrajo de la
--   base con `pg_get_functiondef`, que es lo único que refleja lo aplicado.
--   md5(prosrc) de partida: 46c6c3de546f4da080d328a079470478
--   Si al aplicar esto ese md5 no cambia, se partió de la versión equivocada.
--
-- EL PROBLEMA, MEDIDO
--   fn_planilla_calcular paga el feriado en tres partes:
--     (1) las horas marcadas ese día        → ya están en `pago_base`
--     (2) esas horas otra vez               → la sobretasa del feriado laborado
--     (3) 7.5 * horas_mes / base_horas      → el día de feriado prorrateado
--   Para quien cobra por horas las tres son correctas. Para quien tiene
--   `sueldo_fijo`, `pago_base` es su salario mensual COMPLETO marque o no
--   (rama introducida en 0047), y ese salario ya incluye los feriados del mes.
--   La parte (3) se los vuelve a pagar.
--
--   Medido contra el Postgres local, periodo 29-jul → 28-ago-2026 (2 feriados),
--   persona con sueldo fijo de S/4,500 que NO trabajó ninguno de los dos:
--       pago_base ......... 4,500.00   (su mes íntegro)
--       monto_feriados .....  314.21   ← íntegramente duplicado
--   Y con sueldo fijo de S/2,800 que SÍ trabajó el 06-ago:
--       duplicado ..........  214.00   ← esto se elimina
--       sobretasa ..........  250.12   ← esto se conserva
--
-- POR QUÉ ASÍ Y NO DE OTRA FORMA
--   Se descartó anular todo `monto_feriados` para sueldo fijo: dejaría sin
--   sobretasa a quien vino a trabajar un feriado, y la norma no distingue por
--   forma de pago. Se descartó también tocar el factor 7.5 o el divisor
--   6.5*días: son correctos para quien cobra por horas — se auditaron y se
--   comportan exactamente como la regla del negocio pide (proporcional al
--   tiempo laborado). El defecto no está en la fórmula, está en a quién se le
--   aplica la parte (3).
--
-- LO QUE ESTA MIGRACIÓN NO ARREGLA (a propósito, va en la suya)
--   · Las vacaciones no suman horas, así que recortan la parte (3) un ~24 %.
--     Son descanso remunerado (D. Leg. 713 art. 15: la remuneración vacacional
--     es la que habría percibido de continuar laborando), así que deberían
--     contar. Pendiente de decisión con el contador.
--   · La parte (3) varía hasta 9.5 % entre periodos porque el numerador crece
--     con los días laborables y el divisor con los días del calendario.
--
-- CÓMO SE REVIERTE
--   Restaurar fn_planilla_calcular desde 0171. El cambio son DOS líneas dentro
--   del bloque `fer`, las dos marcadas «CAMBIO 0173»; el resto del cuerpo es
--   byte por byte idéntico a la 0171.
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
          round((pb.basica + (case when pe.con_hijos then v_asig else 0 end))
                * coalesce(tpen.tasa, v_tasa_afp), 2),
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
                 - round((pb.basica + (case when pe.con_hijos then v_asig else 0 end))
                         * coalesce(tpen.tasa, v_tasa_afp), 2)                                    -- CAMBIO 0110
                 + round(mov.bonos, 2) - round(mov.descuentos, 2)
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
          round(greatest(coalesce(pb.basica, 0)
                         + (case when pe.con_hijos then v_asig else 0 end),
                         v_rmv), 2),
        'aporte_essalud',
          round(greatest(coalesce(pb.basica, 0)
                         + (case when pe.con_hijos then v_asig else 0 end),
                         v_rmv) * v_tasa_essalud
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
          (coalesce(pb.basica, 0) + (case when pe.con_hijos then v_asig else 0 end)) < v_rmv
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
      select case when pe.sueldo_fijo then coalesce(sf.salario, 0)
                  else coalesce(hh.pago, 0) end as pago_base,
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
               coalesce(sum(case when tt.salario is null then x.h end), 0) as sin_sal
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
    ) pb on true
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
                             else 7.5 * h.horas_mes / v_base end)) * tt.salario / v_base end), 0) as monto,
             count(*) filter (where tt.salario is null and f.fecha >= pe.fecha_ingreso) as sin_tramo,
             count(*) filter (where f.fecha < pe.fecha_ingreso) as no_corresponde,
             count(*) filter (where ds.otorgado) as compensados,
             coalesce(jsonb_agg(jsonb_build_object(
               'fecha', f.fecha,
               'horas_trabajadas', coalesce(hf.h, 0),
               'proporcional_horas', case when f.fecha >= pe.fecha_ingreso
                                          then round(case when pe.sueldo_fijo then 0
                                                     else 7.5 * h.horas_mes / v_base end, 2) else 0 end,
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
  ) sub;

  return v_out;
end;






$function$;


insert into migraciones_aplicadas (numero, nombre)
values (173, 'el_sueldo_fijo_no_cobra_el_feriado_dos_veces')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
