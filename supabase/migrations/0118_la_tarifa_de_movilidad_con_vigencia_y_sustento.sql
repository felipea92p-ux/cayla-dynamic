-- ============================================================================
-- 0118 — La tarifa de movilidad, con vigencia y con su sustento archivado.
--
-- QUÉ CAMBIA. La tarifa deja de vivir en 'configuracion' —un valor global sin
-- fecha— y pasa a parametros_laborales, la tabla versionada que creó la 0116.
--
-- POR QUÉ IMPORTA, y no es teórico: la tarifa de movilidad SIGUE AL PASAJE, así
-- que va a cambiar. Con un valor único sin fecha, el día que se actualice de
-- S/10 a S/11 todos los periodos ya pagados se recalcularían con el valor nuevo
-- y las boletas viejas dejarían de reproducirse. Es exactamente lo que ya nos
-- pasó con tasa_afp.
--
-- Ahora la función elige la fila vigente al FIN del periodo. Cuando el pasaje
-- suba: se cierra la fila con vigente_hasta y se abre otra. El pasado queda
-- intacto.
--
-- ── LA TARIFA ARRANCA EN CERO, A PROPÓSITO ──────────────────────────────────
--
-- Esta migración NO enciende la movilidad. Siembra la fila en 0.00 para que
-- pegarla no mueva un solo pago, igual que hicieron la 0110 a la 0114.
--
-- Y hay una razón concreta para no encenderla todavía: falta el papel. La
-- **RTF 05449-4-2007** es el precedente que importa — de 21 trabajadores con
-- movilidad, solo 7 tenían convenio exhibido, y **los otros 14 perdieron sin
-- discusión**. El inciso e) del art. 19 del D.S. 001-97-TR nombra el «pacto
-- individual o convención colectiva» como la vía del monto fijo. Sin los 26
-- convenios firmados, pagar la movilidad es pagar sin sustento.
--
-- CÓMO SE ENCIENDE, cuando los convenios estén firmados. Una sola sentencia,
-- y el sustento va adentro porque es parte del dato:
--
--   insert into parametros_laborales (clave, valor, vigente_desde, sustento)
--   values ('movilidad_diaria', 10.00, '<inicio del periodo abierto>',
--     'Tarifa de movilidad supeditada a asistencia: S/10.00 por dia efectivamente '
--     'marcado. MEMORIA DE CALCULO: 4 traslados x S/2.50 = S/10.00. Los cuatro '
--     'traslados son ingreso, salida a refrigerio, retorno y salida final: el '
--     'personal se retira a almorzar a su domicilio y regresa, lo que habilita un '
--     'refrigerio de 1 hora 15 minutos (superior al minimo legal de 45 min del '
--     'art. 7 del D.S. 007-2002-TR). Referencia de costo: colectivo urbano de '
--     'Trujillo a S/2.50 por tramo, tarifa vigente tras el alza de combustible de '
--     'julio 2026. Algunos trabajadores realizan hasta cuatro tramos o recurren a '
--     'taxi por congestion; la tarifa uniforme se fija al caso mas oneroso. '
--     'Art. 19 inciso e) del D.S. 001-97-TR. Codigo PLAME 0909.');
--
--   update parametros_laborales set vigente_hasta = '<dia anterior>'
--    where clave = 'movilidad_diaria' and valor = 0 and vigente_hasta is null;
--
-- ── POR QUÉ EL SUSTENTO VA EN LA BASE Y NO EN UN DOCUMENTO APARTE ───────────
-- Porque un memorándum en una carpeta se pierde y una fila no. El **Exp.
-- 1038-2019 Lima** reclasificó una movilidad de S/553 por ser «mero arbitrio del
-- empleador» — lo que faltaba no era el monto, era poder explicar de dónde salía.
-- (Advertencia sobre esa cita: es sentencia de vista de Sala Laboral, NO casación,
-- así que no es precedente vinculante; sirve para saber qué se ataca.)
-- Con el sustento pegado a la tarifa, cada periodo puede reproducir el porqué del
-- número que pagó, incluso años después y aunque la tarifa ya haya cambiado.
--
-- ── LO QUE NO TOCA ──────────────────────────────────────────────────────────
-- Se conserva la lectura de 'configuracion' como respaldo: una base sin la fila
-- nueva se comporta exactamente como antes. El divisor, la 0109, la 0112, la
-- 0114 y la condición de vínculo de la 0117 quedan intactos y el generador lo
-- verifica.
--
-- CÓMO SE REVIERTE: restaurar fn_planilla_calcular desde la 0117 y borrar las
-- filas de clave 'movilidad_diaria' de parametros_laborales.
-- ============================================================================

-- La fila en CERO. Vigencia desde el origen para que siempre se encuentre y
-- siempre dé 0 hasta que se abra la fila con la tarifa real.
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('movilidad_diaria', 0.00, '2020-03-01',
  'Tarifa en CERO a proposito: la movilidad no esta encendida. Se siembra asi para '
  'que aplicar la migracion no mueva ningun pago. Para encenderla hay que abrir una '
  'fila nueva con la tarifa y su memoria de calculo, y cerrar esta con '
  'vigente_hasta. No encender antes de tener los convenios individuales firmados '
  'por cada trabajador: la RTF 05449-4-2007 desconocio la movilidad de 14 de 21 '
  'trabajadores justamente por falta de convenio exhibido.')
on conflict (clave, vigente_desde) do nothing;

create or replace function fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_dias int; v_base numeric;
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_asig numeric; v_anio int; v_mes int;
  v_movilidad numeric; v_tasa_afp numeric;   -- CAMBIO 0110
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
  -- CAMBIO 0112 — el sexto de la gratificación en la base de la CTS (Art. 16
  -- D.S. 001-97-TR). Arranca en 0: sin la clave, la CTS sale como hoy.
  v_sexto_cts := coalesce((v_prov->>'sexto_cts')::numeric, 0);

  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
  from configuracion where clave = 'asignacion_familiar';
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
  select pl.valor into v_movilidad
  from parametros_laborales pl
  where pl.clave = 'movilidad_diaria'
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
           s.codigo as sede
    from personas p
    join sedes s on s.id = p.sede_base_id
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
        'monto_movilidad', round(coalesce(h.dias, 0) * v_movilidad * (case when pe.en_planilla then 1 else 0 end), 2),
        'movilidad_diaria', v_movilidad,
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
                * (v_f_grati + v_f_cts * (1 + v_sexto_cts) + v_f_vacas), 2),
        -- Para que la pantalla pueda mostrar sobre qué base se provisionó.
        'base_provision', ref.base_provision,
        'factor_provision', coalesce(ref.base_provision / nullif(ref.salario, 0), 1),
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
                 + (case when pe.con_hijos then round(v_asig, 2) else 0 end)
                 + round(coalesce(h.dias, 0) * v_movilidad * (case when pe.en_planilla then 1 else 0 end), 2)              -- CAMBIO 0110
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
        'tipo_vinculo', pe.tipo_vinculo,
        'en_planilla', pe.en_planilla,
        -- true cuando el piso fue lo que decidió la base, o sea cuando la persona
        -- devengó MENOS que la RMV. Sirve para que la boleta pueda explicarlo en
        -- vez de mostrar un número que no cuadra con el sueldo del mes.
        'essalud_es_piso',
          (coalesce(pb.basica, 0) + (case when pe.con_hijos then v_asig else 0 end)) < v_rmv
      ) as fila
    from pers pe
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
                   else pe.sueldo_base_legal
                        + (tt.salario - pe.sueldo_base_legal)
                          * coalesce(rmp.porcentaje, 100) / 100.0
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
                     + 7.5 * h.horas_mes / v_base) * tt.salario / v_base end), 0) as monto,
             count(*) filter (where tt.salario is null and f.fecha >= pe.fecha_ingreso) as sin_tramo,
             count(*) filter (where f.fecha < pe.fecha_ingreso) as no_corresponde,
             count(*) filter (where ds.otorgado) as compensados,
             coalesce(jsonb_agg(jsonb_build_object(
               'fecha', f.fecha,
               'horas_trabajadas', coalesce(hf.h, 0),
               'proporcional_horas', case when f.fecha >= pe.fecha_ingreso
                                          then round(7.5 * h.horas_mes / v_base, 2) else 0 end,
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
               when om.cumplidos::numeric / om.total >= 1 then 0.21 * ref.salario
               when om.cumplidos::numeric / om.total >= 0.6 then 0.126 * ref.salario
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





$$;


insert into migraciones_aplicadas (numero, nombre)
values (118, 'la_tarifa_de_movilidad_con_vigencia_y_sustento')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_tarifa numeric;
  v_config numeric;
begin
  select pl.valor into v_tarifa from parametros_laborales pl
   where pl.clave = 'movilidad_diaria' and pl.vigente_hasta is null
   order by pl.vigente_desde desc limit 1;

  select (valor->>'monto')::numeric into v_config
   from configuracion where clave = 'movilidad_diaria';

  raise notice '0118 · tarifa de movilidad vigente: % (la funcion ya la lee de parametros_laborales)', coalesce(v_tarifa, 0);
  raise notice '0118 · el valor viejo de configuracion (%) queda solo como respaldo', coalesce(v_config, 0);

  if coalesce(v_tarifa, 0) = 0 then
    raise notice '0118 · la movilidad esta APAGADA. Aplicar esta migracion no movio ningun pago.';
    raise notice '0118 · para encenderla, ver la sentencia lista en la cabecera de este archivo.';
    raise notice '0118 · ANTES de encenderla: los 26 convenios individuales firmados.';
  else
    raise notice '0118 · ATENCION: la movilidad esta ENCENDIDA en % por dia.', v_tarifa;
  end if;
end
$mig$;
