-- ============================================================================
-- aplicar_0491.sql — la 0491 SIN el tablero de documentos, para pegar DESPUÉS
-- de la 0492. Preparado el 2026-09-28.
-- ============================================================================
--
-- POR QUÉ EXISTE
--
--   La 0492 (la declaración de ruta se renueva) se pegó en producción ANTES
--   que la 0491, que no había llegado a aplicarse: su freno la detuvo porque
--   a producción le faltaba la 0484 (fn_planilla_calcular_nucleo seguía en la
--   0463, 115 851 caracteres, y la 0491 parte de la 0484, 116 120).
--
--   Con la 0492 ya puesta, la 0491 original ya no se puede pegar:
--     · su freno espera el tablero anterior (21ddd118…) y encuentra el de la
--       0492 (05b59757…), así que aborta;
--     · y aunque pasara, su CREATE OR REPLACE del tablero no trae la columna
--       ruta_por_renovar: Postgres lo rechazaría («cannot change return
--       type»), o se perdería lo de la 0492.
--
-- QUÉ CAMBIA RESPECTO DE LA 0491 — solo dos cosas, lo demás es idéntico
--
--   1. El freno espera, para fn_documentos_tablero, el md5 de la 0492
--      (05b59757… tal cual, 92f3a7f7… sin comentarios, 4134 caracteres) en
--      vez del de antes de la 0491.
--   2. No reescribe fn_documentos_tablero: el de la 0492 ya lleva la única
--      línea que la 0491 le agregaba (`and not p.cuenta_de_servicio`).
--
--   Las otras 8 funciones, el registro de la 491 y la comprobación final
--   son exactamente los de la 0491. En una base nueva nada de esto aplica:
--   la 0491 y la 0492 corren en su orden, sin este archivo.
--
-- ORDEN: 0484 → este archivo. Si la 0484 no está, el freno se detiene en
-- fn_planilla_calcular_nucleo sin tocar nada, que es lo correcto.
-- ============================================================================

-- ============================================================================
-- 0491 — La planilla y las listas del equipo dejan fuera a las cuentas de servicio
-- ============================================================================
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
-- Que una fila de `personas` marcada con `cuenta_de_servicio` (0490) —las
-- estaciones de caja y almacén de cayla-retail— no aparezca en nada de lo que
-- Dynamic calcula en la base:
--
--   fn_planilla_calcular_nucleo   la planilla del periodo (y con ella todo lo
--                                 que la lee: congelar, variación, boletas).
--                                 ES LA QUE TOCA PLATA: cada estación sumaba
--                                 S/ 101.70 de EsSalud por el piso sobre la
--                                 RMV (medido en local, ver la 0490).
--   fn_provisiones                su fila y el contador «sin salario vigente».
--   fn_vacaciones_resumen         una estación no gana días de vacaciones.
--   fn_poblacion_obligada         a quién hay que entregarle el Reglamento.
--   fn_politica_salarial_vigente  el «N de M acusaron recibo».
--   fn_documentos_tablero         Documentación.
--   fn_contratos_tablero          Contratos («sin contrato»).
--   fn_educacion_candidatos       a quién se le puede asignar apoyo educativo.
--   fn_boletas_tablero            las boletas del periodo.
--
-- En cada una el cambio es UNA condición, `not p.cuenta_de_servicio`, junto al
-- `estado = 'activo'` que ya decidía quién entra. Nada más cambia: se buscan
-- con «CAMBIO 0491». Con todas las filas en false (el default) cada función
-- devuelve exactamente lo mismo que antes.
--
-- ── POR QUÉ ESTAS Y NO OTRAS ────────────────────────────────────────────────
--
-- Se revisaron las 55 funciones que filtran `personas` por estado. Las demás
-- piden algo que una estación no tiene: marcajes o jornadas (faltas,
-- tardanzas, «sin horario vigente»), un contrato con fecha de fin, una
-- asignación de sueldo, un cese, o el vínculo «prueba». Y si una estación
-- llegara a tener marcajes, la puerta de la 0490 se niega a marcarla.
--
-- Las pantallas que leen `personas` directo se filtran en el código, con la
-- misma columna.
--
-- ── POR QUÉ SE COPIA EL CUERPO ENTERO ───────────────────────────────────────
--
-- Es la regla de la casa: una migración que cambia una función la reescribe
-- entera. Los cuerpos de abajo salen de `pg_get_functiondef` sobre un Postgres
-- construido desde `supabase/migrations` el 2026-09-28 (la última aplicada era
-- la 0487); cada uno es la versión vigente según `donde-vive.sh`:
--
--   fn_planilla_calcular_nucleo    0484_el_periodo_de_prueba_deja_de_generar_essalud.sql
--   fn_provisiones                 0471_se_retira_la_implementacion_paralela_de_la_0465.sql
--   fn_vacaciones_resumen          0091_la_hora_de_lima_en_todo_el_sistema.sql
--   fn_poblacion_obligada          0270_los_dias_de_seleccion_pagados_no_piden_el_reglamento.sql
--   fn_politica_salarial_vigente   0141_la_politica_salarial_y_su_acuse.sql
--   fn_documentos_tablero          0424_una_practicante_tambien_declara_su_ruta.sql
--   fn_contratos_tablero           0470_el_mtpe_ya_no_es_tramite_para_nadie.sql
--   fn_educacion_candidatos        0281_el_techo_de_educacion_se_reparte_y_sigue_al_rango.sql
--   fn_boletas_tablero             0482_las_boletas_oficiales_se_suben_y_se_publican.sql
--
-- ── MD5 DE PARTIDA ──────────────────────────────────────────────────────────
--
-- Esta migración NO SE FÍA de que producción tenga esos cuerpos: lo comprueba
-- abajo y ABORTA sin tocar nada si alguna función es otra — el accidente de
-- la 0276 y de la 0293, que revirtieron en silencio lo que había entre medias.
-- Acepta, para cada una, el md5 tal cual, el md5 sin comentarios (la mitad de
-- las funciones de producción se pegaron sin ellos) y los dos anteriores
-- quitando los retornos de carro que mete pegar desde Windows (la 0401). Todo
-- eso es benigno y está documentado en CLAUDE.md; cualquier otra diferencia es
-- otra versión, y entonces hay que parar y reconstruir desde la de producción.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- · La 0490: existe `personas.cuenta_de_servicio`. Se comprueba abajo.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   Volver a pegar cada función desde la migración de la lista de arriba. No
--   hay datos que restaurar: ninguna guarda nada. (O, sin tocar funciones,
--   desmarcar las cuentas con fn_set_cuenta_de_servicio: con todo en false,
--   esta migración no cambia ningún resultado.)
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================


-- ── 0 · EL FRENO ────────────────────────────────────────────────────────────
do $freno$
declare
  v_fn    text;
  v_tal   text;
  v_sin   text;
  v_falla text := '';
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'personas'
                    and column_name = 'cuenta_de_servicio') then
    raise exception 'FALTA LA 0490. personas.cuenta_de_servicio no existe; pégala antes que esta.';
  end if;

  if exists (select 1 from migraciones_aplicadas
              where numero = 491
                and nombre = 'la_planilla_y_las_listas_dejan_fuera_a_las_cuentas_de_servicio') then
    raise notice '0491 ya estaba aplicada: no se comprueban los md5 de partida.';
    return;
  end if;

  for v_fn, v_tal, v_sin in
    select * from (values
      ('fn_planilla_calcular_nucleo',   '706301b8092d191a533ac54d143d2058', 'bc267bf46a383186f5505973d78a58f6'),   -- 116120 caracteres
      ('fn_provisiones',                '51b69875b258b8c7d6812a8d64019f7b', 'a89483d1f63933d7064550b9ccb441e9'),   -- 50256 caracteres
      ('fn_vacaciones_resumen',         '9d15efaec6147c3fbd1357ec7e7020d4', '88126a67572be9616cf2c77a9ee58cc2'),   -- 5212 caracteres
      ('fn_poblacion_obligada',         'a45afd50398609857354ff6dbaf7bc8c', 'a45afd50398609857354ff6dbaf7bc8c'),   -- 84 caracteres
      ('fn_politica_salarial_vigente',  '4c099d907033aa874acecb98ca5ceb87', '257da704fcb5c0f3d7d71cccf96b583a'),   -- 1600 caracteres
      ('fn_documentos_tablero',         '05b59757df2ad4477cadf7a62bcfb428', '92f3a7f764ed0f545cd3c2ea8fde1fe8'),   -- 4134 caracteres: el de la 0492 (aplicar_0491)
      ('fn_contratos_tablero',          '85d99e5aafcfdc5737f7f142284e1a8a', 'b80494c389a7f6227ec8073462ad323b'),   -- 4288 caracteres
      ('fn_educacion_candidatos',       'af7b330b91cdc3f57b6c9a94f2e234f9', '0984866b2885cc6d8817fb1a444aeab7'),   -- 601 caracteres
      ('fn_boletas_tablero',            'fcea69eef430c53a8361c37b5fc6c873', 'fcea69eef430c53a8361c37b5fc6c873')    -- 1404 caracteres
    ) as t(fn, tal_cual, sin_comentarios)
  loop
    if not exists (
      select 1
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
             lateral (values (p.prosrc), (replace(p.prosrc, chr(13), ''))) as v(src)
       where n.nspname = 'public' and p.proname = v_fn
         and (md5(v.src) = v_tal
              or md5(array_to_string(array(
                   select regexp_replace(l, '[[:space:]]*--.*$', '')
                   from unnest(string_to_array(v.src, chr(10))) as l
                   where btrim(l) not like '--%'
                 ), chr(10))) = v_sin))
    then
      v_falla := v_falla || '  · ' || v_fn || chr(10);
    end if;
  end loop;

  if v_falla <> '' then
    raise exception E'PARA. Producción no tiene el cuerpo del que se copió esta migración:\n%\nPegarla revertiría en silencio lo que haya entre medias. Corre ./scripts/donde-vive.sh sobre cada una y reconstrúyela desde la versión de producción. (Nada se ha modificado: esto abortó antes de tocar nada.)', v_falla;
  end if;
end
$freno$;


-- ── fn_planilla_calcular_nucleo ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_planilla_calcular_nucleo(p_ini date, p_fin date, p_periodo_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dias int; v_base numeric;
  v_dias_periodo int;                        -- CAMBIO 0239
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_f_be numeric;   -- CAMBIO 0134: tasa de la bonificacion extraordinaria
  v_asig numeric; v_anio int; v_mes int;
  v_movilidad numeric; v_tasa_afp numeric;   -- CAMBIO 0110
  v_tope_dm int;   -- CAMBIO 0254
  v_exige_decl numeric;                      -- CAMBIO 0159
  v_sexto_cts numeric;                       -- CAMBIO 0112
  v_rmv numeric; v_tasa_essalud numeric;     -- CAMBIO 0116
  v_tasa_4ta numeric; v_tope_4ta numeric;    -- CAMBIO 0245
begin
  -- SIN guard de identidad acá, A PROPÓSITO — y comprobado antes de dejarlo
  -- así, no supuesto. Se probó (docker exec, Postgres local) que dentro de
  -- una función SECURITY DEFINER `current_user` es SIEMPRE el dueño
  -- (postgres), la llame quien la llame, directo o anidado: un guard tipo
  -- "current_user <> 'postgres'" —que el primer diseño de esta migración
  -- copiaba del idioma de la 0296— NUNCA dispara aquí, porque esta función
  -- ES SECURITY DEFINER (0296 protegía un TRIGGER, que no lo es). Ponerlo
  -- habría sido un cinturón decorativo: parece que protege y no protege nada.
  --
  -- La defensa real es la misma que ya usa `fn_planilla_congelar` (0096)
  -- para el mismo problema — nunca conceder EXECUTE a `authenticated`, sin
  -- necesitar un chequeo interno: el dueño de la función (y quien ya está
  -- corriendo como el dueño, por venir de OTRA función SECURITY DEFINER)
  -- siempre puede llamarla sin permiso explícito; `authenticated` sin grant
  -- no puede ni intentarlo — Postgres se lo niega antes de entrar acá. Ver
  -- el revoke y la lista negra en la sección siguiente de esta migración.

  -- ── CAMBIO 0239 ──────────────────────────────────────────────────────────
  -- El rango decide QUÉ entra (marcas, feriados). El periodo decide CUÁNTO vale
  -- una hora. Estaban conflatados en una sola variable, así que un rango corto
  -- encarecía la hora en vez de cobrar menos días.
  --
  -- Solo se corrige cuando la llamada declara a qué periodo pertenece el rango.
  -- `fn_simular_planilla` pasa null a propósito —simula un rango libre, que no
  -- es el trozo de ningún periodo— y ahí el divisor sigue siendo el del rango.
  v_dias := (p_fin - p_ini) + 1;

  if p_periodo_id is not null then
    select (pp.fecha_fin - pp.fecha_ini) + 1
      into v_dias_periodo
      from periodos_planilla pp
     where pp.id = p_periodo_id;

    if v_dias_periodo is not null and v_dias_periodo > 0 then
      v_dias := v_dias_periodo;
    end if;
  end if;

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

  -- CAMBIO 0254 · El tope del RIT art. 31 f): CAYLA asume los primeros 20 dias
  -- de incapacidad del ANO CALENDARIO; del 21 en adelante subsidia EsSalud. Se
  -- lee de la misma clave que ya usa el aviso de la 0197, para que no haya dos
  -- numeros distintos diciendo lo mismo.
  select coalesce((valor->>'umbral_essalud')::int, 20) into v_tope_dm
  from configuracion where clave = 'descanso_medico_aviso_dias';
  if v_tope_dm is null then v_tope_dm := 20; end if;

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

  -- ⇩⇩⇩ CAMBIO 0245 ⇩⇩⇩ LA RETENCIÓN DE RENTA DE CUARTA CATEGORÍA.
  --
  -- Las dos van a parametros_laborales y no clavadas en el código, por el
  -- mismo motivo que la RMV (0116) y la asignación familiar (0122): son
  -- cifras que SUNAT mueve, y el día que se muevan los periodos ya pagados
  -- no pueden recalcularse solos. Se lee la fila vigente al FIN del periodo.
  --
  -- LA TASA ARRANCA EN 0 SI LA FILA NO EXISTE, igual que la movilidad y la
  -- AFP de la 0110: una base sin las filas se comporta EXACTAMENTE como
  -- antes de esta migración.
  select pl.valor into v_tasa_4ta
  from parametros_laborales pl
  where pl.clave = 'retencion_4ta_tasa'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_tasa_4ta is null then v_tasa_4ta := 0; end if;

  -- El tope arranca ALTÍSIMO si la fila no existe, y no en 0: un tope en 0
  -- haría que la regla automática retuviera a todo el mundo. El respaldo de
  -- un parámetro que EXCLUYE tiene que caer del lado que no cobra de más.
  select pl.valor into v_tope_4ta
  from parametros_laborales pl
  where pl.clave = 'retencion_4ta_tope'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_tope_4ta is null then v_tope_4ta := 9999999; end if;

  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_feriados
  from feriados f
  where f.fecha between p_ini and p_fin;

  with pers as (
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, p.fecha_ingreso, p.fecha_cese, p.sueldo_fijo,
           p.sueldo_base_legal,   -- CAMBIO 0105
           -- ⇩⇩⇩ CAMBIO 0261 ⇩⇩⇩ EL RÉGIMEN QUE TENÍA EN **ESE** PERIODO.
           --
           -- Antes decía `p.regimen_pension` a secas: el valor de HOY aplicado a
           -- cualquier periodo. La TASA sí estaba versionada por fecha desde la
           -- 0114/0115; la PERTENENCIA de la persona a un régimen, no. Así que
           -- recalcular un mes viejo mezclaba el régimen de hoy con la tasa de
           -- entonces, y el resultado no era ninguno de los dos.
           --
           -- Es el mismo defecto que la 0116 evitó para la RMV y la 0118 para la
           -- movilidad, una capa más arriba: allá el valor global no tenía fecha,
           -- aquí la tenía el valor y no la pertenencia.
           --
           -- SE ANCLA AL CIERRE DEL PERIODO, exactamente igual que la tasa mil
           -- líneas más abajo, y eso es a propósito: leer el régimen en una fecha
           -- y su tasa en otra puede emparejar un régimen con una tasa que nunca
           -- coexistieron.
           --
           -- EL COALESCE ES EL RESPALDO Y NO SOBRA: quien no tenga historial se
           -- comporta EXACTAMENTE igual que antes de esta migración. Por eso
           -- aplicarla no mueve un céntimo de nadie el día que se pega.
           coalesce(
             (select h.regimen
                from asignaciones_regimen_pension h
               where h.persona_id = p.id
                 and h.vigente_desde <= p_fin
                 and (h.vigente_hasta is null or h.vigente_hasta >= p_fin)
               order by h.vigente_desde desc
               limit 1),
             p.regimen_pension) as regimen_pension,   -- CAMBIO 0114 · 0261
           p.tipo_vinculo, p.en_planilla,   -- CAMBIO 0117
           p.personal_direccion,  -- CAMBIO 0187 · art. 5 D.S. 007-2002-TR
           p.retencion_4ta, p.constancia_4ta_hasta,   -- CAMBIO 0245
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
     and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona (0490):
                                    -- sin esto cada estación sumaba S/ 101.70 de EsSalud (piso sobre la RMV).
    left join sedes sf on sf.id = p.sede_fisica_id
    -- ⇩ CAMBIO 0463 ⇩ Activa NO basta: si ingresó DESPUÉS de que este
    -- periodo terminó, todavía no existía para la empresa en esas fechas.
    -- Sin este freno, cualquier persona activa hoy se cuela como fila en
    -- CUALQUIER periodo histórico que se recalcule en vivo — y eso pasa cada
    -- vez que ese periodo tiene un grupo que nunca se llegó a congelar
    -- (ver `fn_proyeccion_periodo`: sin foto en `planilla_pagada_detalle`
    -- para ese grupo, la pantalla sigue pidiendo el cálculo en vivo). Así
    -- aparecían en julio y agosto las practicantes que recién ingresaron en
    -- septiembre: el grupo «practicante» no tuvo a nadie que congelar antes
    -- de que ellas existieran, así que julio y agosto seguían en vivo, y
    -- «vivo» leía su fecha_ingreso de HOY, no la del periodo que se mira.
    where (p.estado = 'activo' and p.fecha_ingreso <= p_fin)
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between p_ini and p_fin)
       or (p_periodo_id is not null and exists (
             select 1 from movimientos_planilla m
             where m.persona_id = p.id and m.periodo_id = p_periodo_id))
       -- ⇩ CAMBIO 0416 ⇩ Quien cesó DENTRO de este rango no puede depender de
       -- tener una jornada o un movimiento ya escrito: es justo lo que le
       -- falta a quien se fue sin marcar. Sin esto, la fila entera desaparece
       -- —no sale con S/0, no sale con nada— y con ella cualquier vacación,
       -- descanso médico o subsidio que sí le tocaba antes de irse.
       or (p.fecha_cese is not null and p.fecha_cese between p_ini and p_fin)
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
  -- Se lee desde ANTES de p_ini a propósito: un ciclo que empezó en el periodo
  -- anterior tiene que medirse entero o el exceso desaparece. Solo se PAGA lo
  -- que cae dentro del periodo — el filtro está más abajo, en `sobret`.
  --
  -- Se filtran las horas <= 0: el auto-cierre puede dejar jornadas negativas
  -- cuando la salida sintética queda antes de la entrada, y una negativa dentro
  -- de un ciclo bajaría el acumulado y escondería un exceso real.
  --
  -- ⇩ CAMBIO 0418 ⇩ SIETE días no alcanzaba. `isla`/`bloque` (abajo) agrupan
  -- por row_number() sobre lo que este CTE deja ver — si la racha real empezó
  -- MÁS de 7 días antes de p_ini, el corte a los 7 días le inventa un inicio de
  -- racha que no es el real, y el ciclo de 7 días que de verdad se completó
  -- dentro de esos días perdidos desaparece sin pagar su exceso. Medido: una
  -- racha de 14 días (10 antes de p_ini, 4 dentro) debía 8 h de exceso el
  -- cuarto día del periodo — con el corte a 7 días salía en cero.
  --
  -- El corte se mueve a 28 días (cuatro ciclos) porque es la racha más larga
  -- que se puede armar SIN que ya sea, por su cuenta, una racha detectable por
  -- otra vía (jornadas de 45 h/semana excedidas cuatro semanas seguidas es algo
  -- que ya debería haber saltado en Incidencias). No es una prueba matemática
  -- de que no puede volver a pasar — es una constante, y toda constante tiene
  -- un límite — pero multiplica por cuatro el margen del defecto medido.
  -- SE ROMPE SI: alguien trabaja una racha real de más de 28 días consecutivos
  -- sin ni un descanso, cruzando el borde del periodo.
  ot_dias as (
    select j.persona_id, j.fecha, j.horas_trabajadas as h
    from jornadas j
    where j.fecha between p_ini - 28 and p_fin
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
           min(fecha) as desde, max(fecha) as hasta,
           -- ⇩ CAMBIO 0349 ⇩ el mismo cálculo de arriba, partido en sus dos
           -- tramos — para que la boleta pueda declarar el 25 % (0105 PLAME)
           -- y el 35 % (0106 PLAME) por separado sin rehacer esta cuenta.
           sum(least(h_exceso, 2)) as horas_25,
           sum(greatest(h_exceso - 2, 0)) as horas_35,
           sum(least(h_exceso, 2) * 0.25) as horas_recargo_25,
           sum(greatest(h_exceso - 2, 0) * 0.35) as horas_recargo_35
           -- ⇧ CAMBIO 0349 ⇧
    from ot_exceso
    where h_exceso > 0 and fecha between p_ini and p_fin
    group by persona_id
  ),
  -- ⇧⇧⇧ CAMBIO 0185 ⇧⇧⇧
  --
  -- ⇩⇩⇩ CAMBIO 0280 ⇩⇩⇩ EL DESCANSO SEMANAL TRABAJADO (art. 3, D. Leg. 713)
  --
  -- Se reaprovecha `ot_islas` a propósito: la racha de días consecutivos ya
  -- está calculada para el sobretiempo, y dos formas distintas de contar los
  -- mismos días es como se empieza a tener dos verdades.
  --
  -- QUÉ DÍA DISPARA. El SÉPTIMO de cada ciclo completo — el que se trabajó en
  -- lugar de descansar. Ocho días seguidos pagan UNA sobretasa, no dos: el
  -- octavo abre un ciclo nuevo que todavía no se ha cerrado sin descanso.
  -- Catorce pagan dos. Los ciclos NO se solapan, igual que en el sobretiempo,
  -- porque una ventana móvil cobraría el mismo día siete veces.
  --
  -- Y ESTO ES LO QUE HACE QUE NO HAGA FALTA REGISTRAR NADA. El art. 3 paga la
  -- sobretasa cuando se trabaja el descanso «sin sustituirlo por otro día en la
  -- misma semana». Si de verdad se sustituyó, ese día libre CORTA la racha y no
  -- hay séptimo día. La racha misma es la prueba de que no hubo sustitución —
  -- por eso esto no necesita el aparato de actas que sí necesitó el feriado
  -- (0069/0093/0238), donde el día libre puede caer semanas después.
  dsem_dias as (
    select persona_id, fecha, h,
           row_number() over (partition by persona_id, isla order by fecha) as dia_n
    from ot_islas
  ),
  -- LA SOBRETASA VIVE EN `parametros_laborales`, CON SU VIGENCIA, y no escrita
  -- acá. Es lo que hace que «rige desde el 29/07 y no hacia atrás» sea un dato
  -- y no una línea de código: sin fila vigente ese día, no se paga. Mover la
  -- fecha o apagarla es un INSERT, no una migración. Mismo patrón que la RMV
  -- (0116), la asignación familiar (0122) y la movilidad (0118).
  dsem as (
    select d.persona_id,
           sum(d.h * pl.valor / 100.0) as horas_recargo,
           count(*)::int               as dias,
           min(d.fecha)                as desde,
           max(d.fecha)                as hasta
    from dsem_dias d
    join parametros_laborales pl
      on pl.clave = 'sobretasa_descanso_semanal'
     and pl.vigente_desde <= d.fecha
     and (pl.vigente_hasta is null or pl.vigente_hasta >= d.fecha)
    where d.dia_n % 7 = 0
      and d.fecha between p_ini and p_fin
    group by d.persona_id
  ),
  -- ⇧⇧⇧ CAMBIO 0280 ⇧⇧⇧
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
        -- CAMBIO 0397: un practicante también puede cobrarla, si Felipe le
        -- carga tarifa y `cobra_movilidad` — antes salía siempre en S/0.
        'monto_movilidad', round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla or pe.tipo_vinculo = 'practicante' then 1 else 0 end)
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
          round(bri.base_pension * coalesce(tpen.tasa, v_tasa_afp), 2),
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
        -- ⇩ CAMBIO 0242 ⇩ `and pe.en_planilla is true`. La Ley 25129 da la
        -- asignación familiar a trabajadores del régimen laboral privado. Un
        -- locador no lo es, y cobrarla no solo es plata que no le toca: es un
        -- indicio de laboralidad, igual que la movilidad de la 0117.
        'asignacion_familiar',
          case when pe.con_hijos and pe.en_planilla is true
               then round(v_asig, 2) else 0 end,
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
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * dev.f_grati, 2),
        -- CAMBIO 0134 — se calcula del MISMO numero que la gratificacion, nunca
        -- de una base propia: si manana cambia la formula de la grati, esta la
        -- sigue sola. Es la linea 0312 del PLAME.
        'provision_bonif_extraordinaria',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * dev.f_grati * v_f_be, 2),
        'provision_cts',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * dev.f_cts * (1 + v_sexto_cts), 2),
        'provision_vacaciones',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * dev.f_vacas, 2),
        'provision_total',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * (dev.f_grati * (1 + v_f_be) + dev.f_cts * (1 + v_sexto_cts) + dev.f_vacas), 2),   -- CAMBIO 0134
        -- Para que la pantalla pueda mostrar sobre qué base se provisionó.
        'base_provision', ref.base_provision,
        'factor_provision', coalesce(ref.base_provision / nullif(ref.salario, 0), 1),
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
                 -- CAMBIO 0242 · el pago, con la misma condición que el concepto
                 -- de arriba. Van por separado en el JSON y hay que tocar los dos:
                 -- arreglar solo uno deja la boleta diciendo 0 y el total cobrándolo.
                 + (case when pe.con_hijos and pe.en_planilla is true
                         then round(v_asig, 2) else 0 end)
                 -- CAMBIO 0252 · EL MISMO FILTRO QUE LA LINEA DE LA BOLETA.
                 -- Faltaba `cobra_movilidad`, que el concepto `monto_movilidad`
                 -- tiene desde la 0166. El concepto salia 0.00 y el total la
                 -- cobraba igual: chk_foto_cuadra rechazaba la fila y, como
                 -- fn_planilla_congelar inserta las ~30 en UNA sentencia, no se
                 -- congelaba NINGUNA. El cierre entero se caia por una persona.
                 -- CAMBIO 0397 · MISMO FILTRO QUE EL CONCEPTO, otra vez: un
                 -- practicante que sí cobra movilidad tiene que sumarla aquí
                 -- también, o vuelve el descuadre de la 0252 pero al revés.
                 + round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla or pe.tipo_vinculo = 'practicante' then 1 else 0 end)
          -- CAMBIO 0166: quien no devenga movilidad (se cubre por viaticos) no la devenga
          * (case when pe.cobra_movilidad then 1 else 0 end)
          -- CAMBIO 0159: sin declaracion firmada no devenga, si el candado esta encendido
          * (case when v_exige_decl > 0 and not decl.tiene_declaracion then 0 else 1 end), 2)              -- CAMBIO 0142
                 -- CAMBIO 0397: mismo filtro que `monto_educacion` más abajo.
                 + round(coalesce(edu.monto, 0) * (case when pe.en_planilla or pe.tipo_vinculo = 'practicante' then 1 else 0 end), 2)   -- CAMBIO 0120
                 - round((bri.base_pension)
                         * coalesce(tpen.tasa, v_tasa_afp), 2)                                    -- CAMBIO 0110
                 + round(mov.bonos, 2) - round(mov.descuentos, 2)
                 -- CAMBIO 0245 · la retención sale del pago, como manda el
                 -- art. 71 de la Ley del Impuesto a la Renta. No se queda en
                 -- CAYLA: se declara en la PLAME y se paga a SUNAT a nombre
                 -- de la persona. Va en DOS sitios del JSON —el concepto y
                 -- este término— y hay que tocar los dos, que es la lección
                 -- que dejó la asignación familiar en la 0242.
                 - r4.monto
                 -- CAMBIO 0185 · el recargo del sobretiempo. Solo el RECARGO:
                 -- las horas ya están dentro de pago_base.
                 + round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2)
                 -- CAMBIO 0280 · el recargo del descanso semanal trabajado.
                 -- Solo el RECARGO: las horas de ese día ya están en pago_base.
                 -- Es el error que la 0173 tuvo que corregir con el feriado.
                 + round(coalesce(dsw.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2)
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
        -- maternidad). CAMBIO 0254: el descanso médico SÍ se modela desde
        -- entonces —los 20 días del RIT art. 31 f) entran en pago_base—.
        -- CAMBIO 0262: la maternidad también, y por eso el piso RMV de esta
        -- línea NO se le aplica: el subsidio entra en `pago_base` pero no en
        -- `pb.basica`, así que no llega a `bri.base` y no infla la base de
        -- EsSalud. Es exactamente lo que manda el reglamento.
        --
        -- Consecuencia de gestión: el costo de EsSalud lo manda el número de
        -- personas, no el monto de la planilla. Calcularlo como «9% del total de
        -- la planilla» subestima el aporte real cuando hay gente de pocas horas.
        'base_essalud',
          round(greatest(bri.base, pb.piso_essalud), 2),
        'aporte_essalud',
          -- CAMBIO 0484 ⇩ el período de prueba deja de generar EsSalud — decisión
          -- explícita de Felipe (2026-09-27), pese a que el D.S. 009-97-SA no hace esa
          -- excepción por ley. Ver «QUÉ ASUME» en el encabezado de esta migración.
          -- CAMBIO 0322 ⇩ un practicante también genera EsSalud, aunque
          -- `en_planilla` sea false: CAYLA se acoge voluntariamente al
          -- régimen de EsSalud para su beneficiario (art. 47, Ley 28518). La
          -- base sigue siendo `greatest(bri.base, pb.piso_essalud)` — para un
          -- practicante `bri.base` es 0, así que esto siempre es el piso RMV
          -- prorrateado, nunca su subvención real si pagara por encima de la
          -- RMV. Ver «QUÉ NO TOCA» en el encabezado de esta migración.
          round(greatest(bri.base, pb.piso_essalud) * v_tasa_essalud
                * (case when pe.tipo_vinculo = 'planilla' or pe.tipo_vinculo = 'practicante' then 1 else 0 end), 2),
        'essalud_tasa', v_tasa_essalud,
        -- ⇩⇩⇩ CAMBIO 0117 ⇩⇩⇩ Qué es esta persona para el sistema. Sin este dato
        -- la boleta no puede explicar por qué a alguien no le aparece movilidad ni
        -- EsSalud, y la pantalla de Planilla no puede advertir que un locador con
        -- conceptos laborales encima es un problema.
        -- ⇩ CAMBIO 0120 ⇩ Condicionada a en_planilla igual que la movilidad: un
        -- locador no recibe asignaciones laborales. Y el monto NO se prorratea por
        -- asistencia — es el costo de un estudio, no una compensación por venir.
        -- CAMBIO 0397: un practicante también puede cobrarla, si Felipe le
        -- carga una asignación vigente con comprobante — antes salía siempre
        -- en S/0, igual que la movilidad, por el mismo `en_planilla` false.
        'monto_educacion',
          round(coalesce(edu.monto, 0) * (case when pe.en_planilla or pe.tipo_vinculo = 'practicante' then 1 else 0 end), 2),
        -- ⇩ CAMBIO 0150 ⇩ Para que la boleta pueda decir de qué institución sale
        -- ese dinero. Una línea que dice sólo «S/270» no le permite a la persona
        -- cuadrar su propio pago, y un concepto no remunerativo que no se
        -- identifica es el que se reclasifica como sueldo.
        -- CAMBIO 0397: mismo criterio que `monto_educacion` de arriba.
        'instituciones_educacion',
          case when pe.en_planilla or pe.tipo_vinculo = 'practicante' then edu.instituciones else null end,
        -- ⇩ CAMBIO 0236 ⇩ Los dos datos con los que la boleta explica un cero.
        -- Condicionados a `en_planilla` como todo lo demás de educación: a un
        -- locador no se le explica por qué no cobra un concepto laboral, no le
        -- corresponde y punto.
        -- CAMBIO 0397: un practicante SÍ puede tener el concepto, así que
        -- entra a la misma condición — un locador sigue excluido.
        'educacion_registrada',
          case when pe.en_planilla or pe.tipo_vinculo = 'practicante' then coalesce(edudiag.hay, false) else false end,
        'educacion_sin_comprobante',
          case when pe.en_planilla or pe.tipo_vinculo = 'practicante' then coalesce(edudiag.sin_papel, false) else false end,
        'tipo_vinculo', pe.tipo_vinculo,
        'en_planilla', pe.en_planilla,
        -- true cuando el piso fue lo que decidió la base, o sea cuando la persona
        -- devengó MENOS que la RMV. Sirve para que la boleta pueda explicarlo en
        -- vez de mostrar un número que no cuadra con el sueldo del mes.
        'essalud_es_piso',
          (bri.base) < pb.piso_essalud
      )
      -- ⇩ CAMBIO 0177 ⇩ Se CONCATENA en vez de ampliar el jsonb_build_object de
      -- arriba: ese ya tiene 57 pares y Postgres corta a 100 ARGUMENTOS. Agregar
      -- dos claves más ahí revienta con «cannot pass more than 100 arguments to
      -- a function», y no al escribirla sino al EJECUTARLA. Quien agregue el
      -- siguiente campo del JSON tiene que hacerlo acá.
      || jsonb_build_object(
        -- ⇩⇩⇩ CAMBIO 0286 ⇩⇩⇩ EL AVISO, que importa mas que el arreglo.
        --
        -- Cuenta los dias en que la persona FICHO estando dentro de una ausencia
        -- registrada —vacaciones, descanso medico o maternidad—. Desde esta
        -- migracion ese dia se paga UNA vez, como trabajado, asi que ya no
        -- cuesta plata; pero sigue significando algo raro que alguien tiene que
        -- mirar: o el parte se registro sobre dias que ya tenian marcas, o la
        -- persona vino a trabajar durante un descanso que la ley obliga a gozar
        -- (D. Leg. 713 art. 14). El sistema no puede decidir cual de las dos es.
        --
        -- LA MATERNIDAD SE CUENTA PERO NO SE TOCA SU PAGO: su subsidio lo paga
        -- EsSalud por dia calendario y tiene la casuistica propia de la 0262.
        -- Que aparezca en el aviso es justo lo que hace falta para enterarse si
        -- alguna vez ocurre.
        'dias_solapados', (
          select count(*)::int
          from ausencias a
          join lateral generate_series(greatest(a.fecha_inicio, p_ini),
                                       least(a.fecha_fin, p_fin),
                                       interval '1 day') as dd(d) on true
          join jornadas j on j.persona_id = pe.id and j.fecha = dd.d::date
                         and j.horas_trabajadas is not null and j.horas_trabajadas > 0
          where a.persona_id = pe.id and a.anulada_at is null
        ),
        'monto_vacaciones', round(pb.monto_vacaciones, 2),
        'dias_vacaciones_pagados', pb.dias_vacaciones_pagados,
        -- CAMBIO 0254 · para que la boleta lo diga con su nombre en vez de
        -- esconderlo dentro del sueldo. Informativos: el monto YA esta en
        -- pago_base, asi que no se suma otra vez en ningun sitio.
        'monto_descanso_medico', round(pb.monto_descanso_medico, 2),
        'dias_descanso_medico_pagados', pb.dias_descanso_medico_pagados,
        -- CAMBIO 0314 · para que la boleta pueda decirlo con su nombre, igual
        -- que hace con el descanso medico y con el subsidio de maternidad.
        'monto_licencia_con_goce', round(pb.monto_licencia_con_goce, 2),
        'dias_licencia_con_goce', pb.dias_licencia_con_goce,
        -- CAMBIO 0262 · el subsidio, con su nombre. Informativos: el monto YA
        -- esta dentro de pago_base, asi que no se suma otra vez en ningun sitio.
        'monto_subsidio_maternidad', round(pb.monto_subsidio_maternidad, 2),
        'dias_subsidio_maternidad', pb.dias_subsidio_maternidad,
        -- ⇩ LA ALARMA ⇩ dias de licencia registrados a los que nadie les puso
        -- monto. Es lo unico de este cambio que la pantalla TIENE que mirar: sin
        -- esto, una licencia sin monto se paga 0.00 y se lee igual que un mes
        -- normal de alguien que no vino.
        'dias_maternidad_sin_monto', pb.dias_maternidad_sin_monto,
        -- CAMBIO 0185 · las tres piezas que la boleta necesita para explicarse:
        -- cuánto, cuántas horas y cuándo. Un monto pelado no se puede verificar
        -- contra el registro de asistencia, que es lo que lo sostiene.
        'monto_sobretiempo', round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2),
        -- ⇩ CAMBIO 0349 ⇩ el mismo recargo, partido en 25 % / 35 % — lo pidió
        -- el contador para conciliar contra los códigos 0105/0106 de la
        -- PLAME. `_35` sale de restar el total menos el `_25` ya redondeado,
        -- no de su propia fórmula: así las dos líneas de la boleta siempre
        -- suman EXACTO lo que ya imprime la línea del total, sin que un
        -- redondeo de centavo entre las dos partes las descuadre.
        'monto_sobretiempo_25', round(coalesce(ot.horas_recargo_25, 0) * coalesce(ref.salario, 0) / v_base, 2),
        'monto_sobretiempo_35', round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2)
                               - round(coalesce(ot.horas_recargo_25, 0) * coalesce(ref.salario, 0) / v_base, 2),
        'horas_sobretiempo_25', round(coalesce(ot.horas_25, 0), 2),
        'horas_sobretiempo_35', round(coalesce(ot.horas_35, 0), 2),
        -- ⇧ CAMBIO 0349 ⇧
        -- CAMBIO 0280 · Va con sus días y sus fechas, no solo con el monto: un
        -- recargo del 100 % sin decir qué día se trabajó es un número que nadie
        -- puede comprobar, y este se le explica a una persona.
        'monto_descanso_semanal', round(coalesce(dsw.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2),
        'descanso_semanal_dias', coalesce(dsw.dias, 0),
        'descanso_semanal_desde', dsw.desde,
        'descanso_semanal_hasta', dsw.hasta,
        'horas_sobretiempo', round(coalesce(ot.horas, 0), 2),
        'sobretiempo_desde', ot.desde,
        'sobretiempo_hasta', ot.hasta,
        -- CAMBIO 0245 · los cuatro que necesita la boleta de un locador para
        -- explicarse. El monto pelado no se puede verificar contra su recibo:
        -- hace falta sobre qué base salió y bajo qué regla.
        'retencion_4ta', r4.monto,
        'retencion_4ta_base', r4.base,
        'retencion_4ta_modo', pe.retencion_4ta,
        'retencion_4ta_constancia_hasta', pe.constancia_4ta_hasta,
        'retencion_4ta_sin_configurar', r4.sin_configurar,
        -- CAMBIO 0250 · ¿su pago depende de las horas que registre?
        --
        -- Es un campo de PRESENTACIÓN y no mueve un céntimo: `pago_base` ya
        -- se calcula distinto para quien lo tiene desde la 0047. Viaja porque
        -- sin él la boleta no puede distinguir dos locadores que cobran de
        -- formas opuestas, y les ponía a los dos la misma etiqueta: «Honorarios
        -- por las horas prestadas (0 h) …… S/ 652.17». Cero horas y un monto,
        -- en el papel que se le entrega a alguien externo — y describiendo el
        -- acuerdo al revés, porque lo pactado con él es un monto fijo.
        --
        -- Va en el ÚLTIMO jsonb_build_object, el que abrió la 0177: el primero
        -- está a 57 pares y Postgres corta a 100 ARGUMENTOS al EJECUTAR.
        'sueldo_fijo', pe.sueldo_fijo
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
      select case when pe.sueldo_fijo
                  -- ⇩ CAMBIO 0417 ⇩ Antes: el salario completo, sin mirar si
                  -- la persona entro o ceso a mitad de ESTE rango. `v_dias`
                  -- es el largo del PERIODO completo (0239: cuando hay
                  -- p_periodo_id), no del rango truncado que le pasa
                  -- fn_liquidacion con "ni un dia mas" -- asi que un cese a
                  -- mitad de mes prorratea aqui, no alla.
                  then round(coalesce(sf.salario, 0) * coalesce(sf.dias_activo, v_dias) / v_dias, 2)
                  else coalesce(hh.pago, 0)
                       -- CAMBIO 0275 · LA MISMA TARIFA DE RESPALDO QUE LA 0254.
                       -- Lo normal sigue siendo el promedio de lo que se le pago
                       -- por dia trabajado (art. 15 del D. Leg. 713, la 0177).
                       -- Pero quien pasa el periodo ENTERO de vacaciones no tiene
                       -- dias marcados: el promedio es 0/0 y cobra CERO el mes de
                       -- su descanso. La 0254 ya resolvio exactamente esto para el
                       -- descanso medico y la 0262 para la maternidad; vacaciones
                       -- —que es el caso MAS probable de los tres, porque son 30
                       -- dias calendario contra un periodo de 31— se quedo sin el.
                       + coalesce(
                           hh.pago / nullif(hh.dias_marcados, 0),
                           coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                           0
                         ) * coalesce(vacd.dias, 0)
                       -- CAMBIO 0254 · los dias de descanso medico que asume CAYLA.
                       -- Van DENTRO de pago_base, igual que los de vacaciones desde
                       -- la 0177, y por la misma razon practica: chk_foto_cuadra
                       -- compara el total contra pago_base, asi que un concepto
                       -- nuevo por fuera obligaria a tocar la tabla congelada, la
                       -- restriccion y fn_planilla_congelar. Aqui los dos lados se
                       -- mueven juntos y no hay nada que descuadrar.
                       --
                       -- LA TARIFA DEL DIA, con respaldo. Lo normal es el promedio
                       -- de lo que se le pago por dia trabajado, que es lo que hace
                       -- la 0177. Pero quien pasa el periodo ENTERO de descanso
                       -- medico no tiene dias marcados: el promedio seria 0/0 y
                       -- cobraria cero, que es justo el defecto que esta migracion
                       -- viene a quitar. Por eso el respaldo con su tarifa de
                       -- contrato: salario del tramo entre sus dias laborables.
                       + coalesce(
                           hh.pago / nullif(hh.dias_marcados, 0),
                           coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                           0
                         ) * coalesce(dmd.dias, 0)
                       -- CAMBIO 0314 · las demas licencias con goce. Misma
                       -- tarifa y mismo respaldo que el descanso medico, y
                       -- DENTRO de pago_base por el mismo motivo que escribio
                       -- la 0254: un concepto por fuera obliga a tocar la tabla
                       -- congelada, fn_planilla_congelar y chk_foto_cuadra, y
                       -- olvidar uno de los tres aborta el cierre del equipo.
                       + coalesce(
                           hh.pago / nullif(hh.dias_marcados, 0),
                           coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                           0
                         ) * coalesce(lic.dias, 0)
                       -- CAMBIO 0262 · el subsidio por maternidad, DENTRO de
                       -- pago_base por el mismo argumento que la 0254 escribio
                       -- para el descanso medico: un concepto por fuera obliga a
                       -- columna nueva, a tocar fn_planilla_congelar y a
                       -- reescribir chk_foto_cuadra, y olvidar uno de los tres
                       -- aborta el cierre para todo el equipo. Aqui los dos lados
                       -- se mueven juntos y no hay nada que descuadrar.
                       + round(coalesce(mat.monto, 0), 2)
                  end as pago_base,
             -- Informativos, para que la boleta pueda decirlo con su nombre.
             case when pe.sueldo_fijo then 0
                  else coalesce(
                         hh.pago / nullif(hh.dias_marcados, 0),
                         coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                         0
                       ) * coalesce(dmd.dias, 0) end as monto_descanso_medico,
             coalesce(dmd.dias, 0) as dias_descanso_medico_pagados,
             -- CAMBIO 0314 · informativos. El monto YA esta en pago_base.
             case when pe.sueldo_fijo then 0
                  else coalesce(
                         hh.pago / nullif(hh.dias_marcados, 0),
                         coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                         0
                       ) * coalesce(lic.dias, 0) end as monto_licencia_con_goce,
             coalesce(lic.dias, 0) as dias_licencia_con_goce,
             -- CAMBIO 0262 · informativos. El monto YA esta en pago_base.
             case when pe.sueldo_fijo then 0
                  else round(coalesce(mat.monto, 0), 2) end as monto_subsidio_maternidad,
             coalesce(mat.dias, 0) as dias_subsidio_maternidad,
             coalesce(mat.dias_sin_monto, 0) as dias_maternidad_sin_monto,
             -- CAMBIO 0262 · EL PISO DE ESSALUD, PRORRATEADO.
             --
             -- El art. 33 del D.S. 009-97-SA dice que la base minima RMV se
             -- aplica «independientemente de las horas y dias laborados» —de ahi
             -- el piso de la 0116— PERO agrega una excepcion expresa: cuando la
             -- persona percibe SUBSIDIOS, la base minima «se determinara de forma
             -- proporcional a los dias no subsidiados del mes».
             --
             -- Sin esto, por alguien de licencia todo el mes CAYLA declararia la
             -- RMV entera y aportaria 9% sobre ella, cuando la ley le pide 9%
             -- sobre la parte no subsidiada. No perjudica a la persona: es plata
             -- de la empresa y una declaracion que no corresponde.
             --
             -- El divisor es el PERIODO (29 al 28), no el mes calendario, porque
             -- es el tramo que esta planilla liquida. La norma dice «del mes»;
             -- aqui el mes de pago es el periodo.
             round(v_rmv * ((p_fin - p_ini + 1)
                            - (case when pe.sueldo_fijo then 0
                                    else coalesce(mat.dias, 0) end))::numeric
                         / (p_fin - p_ini + 1), 2) as piso_essalud,
             case when pe.sueldo_fijo then 0
                  else coalesce(                       -- CAMBIO 0275
                         hh.pago / nullif(hh.dias_marcados, 0),
                         coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                         0
                       ) * coalesce(vacd.dias, 0) end as monto_vacaciones,
             -- ⇩ CAMBIO 0276 ⇩ `horas_vacaciones` y `horas_descanso_medico`
             -- vivían acá y las usaba UN solo consumidor: el prorrateo del
             -- feriado. Ese se mudó a `fn_feriado_devengado`, que las calcula
             -- con la MISMA fórmula —respaldo de la 0275 incluido— y por eso
             -- estas dos columnas se retiran en vez de quedarse sin lector.
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
        select t.salario,
               -- ⇩ CAMBIO 0417 ⇩ Dias de ESTE rango en que la persona estuvo
               -- de verdad empleada: desde que entro (o el inicio del rango,
               -- lo que sea mas tarde) hasta que ceso (o el fin del rango, lo
               -- que sea mas temprano). Fuera de ese tramo no cobra, aunque
               -- el rango completo tenga v_dias dias.
               greatest(0, least(p_fin, coalesce(pe.fecha_cese, p_fin))
                          - greatest(p_ini, pe.fecha_ingreso) + 1) as dias_activo
        from tramos t
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
          -- ⇩⇩⇩ CAMBIO 0286 ⇩⇩⇩ UN DIA FICHADO NO SE PAGA TAMBIEN COMO AUSENCIA.
          -- `fn_provisiones` excluye este dia desde la 0135; la boleta nunca se
          -- entero, y como la boleta es el camino automatico, eso salia del
          -- banco cada mes. Medido: S/337,93 por una semana solapada.
          and not exists (
                select 1 from jornadas j
                where j.persona_id = pe.id and j.fecha = d.d::date
                  and j.horas_trabajadas is not null and j.horas_trabajadas > 0)
          and case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                else extract(dow from d.d)::int = any(hv.dias_laborables)
              end
          -- ⇩ CAMBIO 0418 ⇩ NI UN DÍA DESPUÉS DEL CESE. `fn_cesar_persona`
          -- (0327) cierra `asignaciones_salario` y `horarios_asignados` en la
          -- fecha de cese, pero un periodo de vacaciones registrado ANTES de
          -- cesar puede seguir corriendo después — y sin este filtro, esos
          -- días de más se seguían pagando como si la persona siguiera activa.
          -- Medido: S/273,50 por 5 días de vacaciones posteriores al cese.
          and (pe.fecha_cese is null or d.d::date <= pe.fecha_cese)
      ) vacd on true
      -- ⇧⇧⇧ CAMBIO 0177 ⇧⇧⇧

      -- ⇩⇩⇩ CAMBIO 0254 ⇩⇩⇩ Dias de descanso medico que CAYLA paga
      --
      -- DOS CUENTAS DISTINTAS QUE NO SE MEZCLAN, y mezclarlas da mal las dos:
      --   · el TOPE se cuenta en dias CALENDARIO del ano, porque asi lo cuenta
      --     EsSalud y asi lo escribe el RIT art. 31 f);
      --   · lo que se PAGA son los dias que le tocaba trabajar, porque pagar un
      --     domingo que no habria trabajado seria pagar de mas. Es el mismo
      --     cuidado que se tomo la 0177 con las vacaciones.
      --
      -- La numeracion va PARTIDA POR ANO y sobre el rango entero de la ausencia,
      -- no recortada al periodo: un descanso del 28/12 al 05/01 aporta 4 dias a
      -- un ano y 5 al siguiente, que es como lo cuenta la 0197.
      --
      -- Y UN DIA QUE YA PAGA POR OTRA VIA NO SE PAGA DOS VECES. El caso salio
      -- solo: el descanso medico del 29/07 al 03/08 de 2026 empieza en Fiestas
      -- Patrias, que la planilla ya paga en su propia linea. Sin este filtro ese
      -- dia se cobraria dos veces, y el descuadre no lo caza nadie porque las dos
      -- lineas estarian "bien" cada una por su lado.
      left join lateral (
        select count(*)::int as dias
        from (
          select dd.d::date as dia,
                 row_number() over (partition by extract(year from dd.d)
                                    order by dd.d) as n
          from ausencias a
          join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
          where a.persona_id = pe.id
            and a.tipo = 'descanso_medico'
            and a.anulada_at is null
            -- ⇩⇩⇩ CAMBIO 0306 ⇩⇩⇩ SOLO LO QUE DO APROBÓ SE PAGA. Antes de esto,
            -- el filtro miraba anulada_at y nada más: un descanso médico
            -- registrado por la encargada de sede pagaba igual que uno
            -- aprobado por Desarrollo Organizacional, aunque
            -- fn_aprobar_ausencia exista justo para que DO sea quien decide
            -- qué convierte días en plata (ver el guard de esa función).
            and a.aprobada_at is not null
        ) dm
        join lateral (
          select ha.dias_laborables, ha.horario_por_dia
          from horarios_asignados ha
          where ha.persona_id = pe.id and ha.vigente_desde <= dm.dia
          order by ha.vigente_desde desc limit 1
        ) hv on true
        where pe.en_planilla
          and dm.n <= v_tope_dm
          and dm.dia between p_ini and p_fin
        -- ⇩⇩⇩ CAMBIO 0293 ⇩⇩⇩ EL FERIADO DENTRO DE UN DESCANSO MEDICO SI SE
        -- PAGA, Y ESTO REVIERTE UNA DECISION DE LA 0254.
        --
        -- Aqui decia `and not exists (select 1 from feriados f where f.fecha =
        -- dm.dia)`. La 0254 lo puso con este argumento, escrito en su cabecera:
        -- «el descanso medico del 29/07 al 03/08 empieza en Fiestas Patrias,
        -- QUE LA PLANILLA YA PAGA EN SU PROPIA LINEA. Sin este filtro ese dia se
        -- cobraria dos veces».
        --
        -- LA PREMISA NO SE SOSTIENE, y se ve midiendo: el feriado NO es una
        -- linea que pague un dia entero, es un PRORRATEO. Quien trabajo el mes
        -- completo cobra S/350,26 de feriados y quien falto una semana cobra
        -- S/252,24. No cubre ese dia: se reparte. Asi que no habia doble pago
        -- que evitar — habia un dia que no pagaba nadie.
        --
        -- Y LA NORMA LO DICE EXPRESAMENTE. La cadena son tres articulos:
        --   · art. 8 del D. Leg. 713: el feriado se paga «la remuneracion
        --     ordinaria correspondiente a un dia de trabajo» y «su abono se
        --     rige por lo dispuesto en el ARTICULO 4»;
        --   · art. 4: «se abonara en forma directamente proporcional al numero
        --     de DIAS EFECTIVAMENTE TRABAJADOS»;
        --   · art. 3 del D.S. 012-92-TR: «por excepcion (...) se consideran
        --     dias efectivamente trabajados: a) las inasistencias por (...)
        --     ENFERMEDADES DEBIDAMENTE COMPROBADAS, hasta que la Seguridad
        --     Social asuma la cobertura».
        --
        -- Ese «hasta que la Seguridad Social asuma la cobertura» son justo los
        -- primeros 20 dias que paga CAYLA, que es el tope que `v_tope_dm` ya
        -- aplica. Un dia de descanso medico documentado CUENTA como trabajado.
        --
        -- LO QUE COSTABA: S/62,90 por cada feriado caido dentro de un parte
        -- medico, y solo a quien esta enfermo — a quien esta de vacaciones no,
        -- porque `vacd` nunca tuvo esta exclusion. Medido con dos personas
        -- identicas, mismo tramo de cinco dias y mismo feriado dentro: descanso
        -- medico S/1.664,20 contra vacaciones S/1.734,13.
        --
        -- NO SE TOCA EL PRORRATEO GENERAL, que es decision de Felipe y esta
        -- confirmada en docs/planilla-anexo-tecnico.md: «que un part-time cobre
        -- menos feriado no es un bug». Esto es otra cosa: es que un dia que la
        -- norma manda contar como trabajado no se estaba contando.
          and not exists (select 1 from vacaciones v
                           where v.persona_id = pe.id
                             and dm.dia between v.fecha_inicio and v.fecha_fin)
          -- ⇩⇩⇩ CAMBIO 0286 ⇩⇩⇩ UN DIA FICHADO NO SE PAGA TAMBIEN COMO AUSENCIA.
          -- `fn_provisiones` excluye este dia desde la 0135; la boleta nunca se
          -- entero, y como la boleta es el camino automatico, eso salia del
          -- banco cada mes. Medido: S/337,93 por una semana solapada.
          and not exists (
                select 1 from jornadas j
                where j.persona_id = pe.id and j.fecha = dm.dia
                  and j.horas_trabajadas is not null and j.horas_trabajadas > 0)
          and case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from dm.dia)::int::text)
                else extract(dow from dm.dia)::int = any(hv.dias_laborables)
              end
          -- ⇩ CAMBIO 0418 ⇩ mismo criterio que `vacd`, dos laterales arriba:
          -- ni un día de descanso médico posterior al cese.
          and (pe.fecha_cese is null or dm.dia <= pe.fecha_cese)
      ) dmd on true

      -- ⇩⇩⇩ CAMBIO 0314 ⇩⇩⇩ LAS DEMAS LICENCIAS QUE EL CATALOGO DICE QUE PAGAN
      --
      -- Hasta aqui esta funcion conocia DOS tipos de ausencia por su nombre:
      -- `descanso_medico` y `maternidad`. Cualquier otro que el catalogo
      -- marcara `paga = true` se ignoraba en silencio.
      --
      -- Eso dejaba una trampa: `licencia_con_goce` esta activa, sale en el
      -- desplegable, y la pantalla avisa al aprobarla que «esos dias entran en
      -- su planilla». No entraban. Cero usos en la historia, asi que no le
      -- costo un sol a nadie — pero el dia que alguien la usara, no cobraba.
      --
      -- Y el art. 23.4 del Reglamento Interno lo manda expresamente: se computa
      -- como tiempo laborado, ademas de las horas registradas, «c) las
      -- licencias y los permisos con goce de haber previstos por la ley y por
      -- este Reglamento, incluidos los de los articulos 22, 31 y 33».
      --
      -- POR TIPO Y NO POR NOMBRE, que es lo que evita que vuelva a pasar. En
      -- vez de agregar un lateral cada vez que nace un tipo, este mira
      -- `tipos_ausencia.paga` y excluye los tres que YA tienen tratamiento
      -- propio. El proximo tipo que se cree marcado como que paga, se paga.
      --
      -- LAS CINCO EXCLUSIONES SON LAS DE `dmd`, copiadas a proposito. Cada una
      -- costo dinero aprenderla y no hay motivo para que aqui valgan otras:
      --   · solo lo que DO aprobo (0306);
      --   · nada anulado;
      --   · nada fuera del periodo;
      --   · ni un dia que ya paga `vacd` — se cobraria dos veces;
      --   · ni un dia FICHADO (0286: costaba S/337,93 por semana solapada);
      --   · y solo dias que le tocaba trabajar.
      --
      -- SIN TOPE, a diferencia del descanso medico. El de 20 dias es de la Ley
      -- 26790 y solo aplica a la incapacidad temporal; una licencia por
      -- fallecimiento o por enfermedad grave de un familiar dura lo que la ley
      -- de cada caso diga, y quien la aprueba ya decidio cuantos dias son.
      left join lateral (
        select count(*)::int as dias
        from ausencias a
        join tipos_ausencia t on t.codigo = a.tipo and t.paga
        join lateral generate_series(a.fecha_inicio, a.fecha_fin,
                                     interval '1 day') as dd(d) on true
        join lateral (
          select ha.dias_laborables, ha.horario_por_dia
          from horarios_asignados ha
          where ha.persona_id = pe.id and ha.vigente_desde <= dd.d::date
          order by ha.vigente_desde desc limit 1
        ) hv on true
        where a.persona_id = pe.id
          -- Los tres que ya tienen su propio lateral, con sus propias reglas:
          -- el tope de la 26790, el subsidio por dia calendario y `vacd`.
          and a.tipo not in ('descanso_medico', 'maternidad', 'vacaciones')
          and a.anulada_at is null
          and a.aprobada_at is not null
          and pe.en_planilla
          and dd.d::date between p_ini and p_fin
          and not exists (select 1 from vacaciones v
                           where v.persona_id = pe.id
                             and dd.d::date between v.fecha_inicio and v.fecha_fin)
          and not exists (
                select 1 from jornadas j
                where j.persona_id = pe.id and j.fecha = dd.d::date
                  and j.horas_trabajadas is not null and j.horas_trabajadas > 0)
          and case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from dd.d)::int::text)
                else extract(dow from dd.d)::int = any(hv.dias_laborables)
              end
          -- ⇩ CAMBIO 0418 ⇩ mismo criterio que `vacd` y `dmd`: ni un día de
          -- licencia con goce posterior al cese.
          and (pe.fecha_cese is null or dd.d::date <= pe.fecha_cese)
      ) lic on true

      -- ⇩⇩⇩ CAMBIO 0262 ⇩⇩⇩ EL SUBSIDIO POR MATERNIDAD.
      --
      -- CUENTA DIAS CALENDARIO, no dias laborables, y esa es la diferencia de
      -- fondo con el lateral `dmd` de arriba. El descanso medico que asume CAYLA
      -- es SUELDO: se paga por los dias que a esa persona le tocaba trabajar. El
      -- subsidio de maternidad no es sueldo — es una prestacion economica de
      -- EsSalud que cubre los 98 dias corridos de la licencia, domingos
      -- incluidos. Contarlo por dias laborables le quitaria a una integrante de
      -- Lima (5 dias) dos septimos de lo que le corresponde.
      --
      -- EL MONTO NO SE CALCULA AQUI, Y ES DELIBERADO. El promedio diario sale de
      -- los 12 meses anteriores a la contingencia, y esos 12 meses pueden incluir
      -- empleadores anteriores a CAYLA: una persona con ocho meses de casa tiene
      -- cuatro meses de historia que esta base NO CONTIENE. Calcularlo con lo que
      -- hay adentro produciria un numero mas bajo que el legal, con toda la
      -- apariencia de estar bien. Lo entra DO en `ausencias.subsidio_diario`,
      -- tomandolo del calculo de EsSalud, y aqui solo se multiplica.
      --
      -- EL FERIADO DE DENTRO SI SE CUENTA, y aqui esta la diferencia con el
      -- lateral `dmd`. Medido el 2026-08-15: quien pasa el periodo entero de
      -- licencia devenga S/0.00 de feriados —`fer` los paga en proporcion a las
      -- horas del mes, y no marco ninguna—, asi que excluir el feriado no evitaba
      -- una duplicacion: le quitaba el dia. Diez dias de licencia le pagaban
      -- nueve.
      --
      -- La duplicacion se evita por el OTRO lado, que es donde corresponde: el
      -- lateral `fer` deja de devengar los feriados que caen dentro de una
      -- licencia subsidiada. Durante el descanso el contrato esta suspendido y
      -- el feriado no genera concepto propio (D. Leg. 713 art. 8, que remite al
      -- art. 4: se abona «en forma directamente proporcional al numero de dias
      -- efectivamente trabajados»). El dia lo cubre el subsidio, entero.
      left join lateral (
        select coalesce(sum(case when x.subsidio_diario is not null
                                 then x.dias else 0 end), 0)::int          as dias,
               coalesce(sum(case when x.subsidio_diario is not null
                                 then x.dias * x.subsidio_diario
                                 else 0 end), 0)                           as monto,
               -- Los dias de licencia SIN monto entrado. No se pagan —no hay con
               -- que— pero viajan al JSON para que la pantalla pueda gritarlo. Un
               -- cero mudo aqui es exactamente el defecto que la 0254 vino a
               -- quitar del descanso medico.
               coalesce(sum(case when x.subsidio_diario is null
                                 then x.dias else 0 end), 0)::int          as dias_sin_monto
        from (
          select a.id, a.subsidio_diario, count(*)::int as dias
          from ausencias a
          join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
          where a.persona_id = pe.id
            and a.tipo = 'maternidad'
            and a.anulada_at is null
            -- ⇩⇩⇩ CAMBIO 0306 ⇩⇩⇩ Misma regla que `dmd`: sin aprobación de DO
            -- no se paga. Ver el comentario de `dmd`, dos laterales más arriba.
            and a.aprobada_at is not null
            and pe.en_planilla
            and dd.d::date between p_ini and p_fin
            -- Las vacaciones si se descuentan: viven en otra tabla, pueden
            -- solaparse con la licencia y `vacd` ya las paga por su cuenta.
            and not exists (select 1 from vacaciones v
                             where v.persona_id = pe.id
                               and dd.d::date between v.fecha_inicio and v.fecha_fin)
            -- ⇩ CAMBIO 0418 ⇩ mismo criterio que `vacd`, `dmd` y `lic`: ni un
            -- día de subsidio por maternidad posterior al cese.
            and (pe.fecha_cese is null or dd.d::date <= pe.fecha_cese)
          group by a.id, a.subsidio_diario
        ) x
      ) mat on true

      -- Sus dias laborables del periodo. Solo alimenta el respaldo de la tarifa
      -- de arriba, para quien no marco ni un dia. No entra en ningun otro pago.
      left join lateral (
        select count(*)::int as dias
        from generate_series(p_ini, p_fin, interval '1 day') d
        join lateral (
          select ha.dias_laborables, ha.horario_por_dia
          from horarios_asignados ha
          where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
          order by ha.vigente_desde desc limit 1
        ) hv on true
        where case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                else extract(dow from d.d)::int = any(hv.dias_laborables)
              end
      ) labp on true
      -- ⇧⇧⇧ CAMBIO 0254 ⇧⇧⇧
    ) pb on true
    -- ⇩⇩⇩ CAMBIO 0199 ⇩⇩⇩ EL FACTOR SE APAGA EN ORIGEN, igual que en la 0196.
    --
    -- LA BOLETA TIENE SUS PROPIAS PROVISIONES. No salen de `fn_provisiones`:
    -- salen de acá. La 0196 conectó el interruptor por persona allá y dejó esta
    -- función sin tocar, así que la boleta de un locador seguía imprimiendo
    -- «Gratificación — la parte de este mes» con su monto al lado. Lo destapó la
    -- boleta en pantalla, no ninguna prueba: dos funciones calculaban lo mismo y
    -- solo una se enteró del cambio.
    --
    -- Cinco expresiones usan estos factores. Apagarlos acá las apaga las cinco;
    -- ponerle un `case` a cada una sería pedir que alguien olvide la quinta.
    cross join lateral (
      select case when fn_devenga(pe.id, 'grati')      then v_f_grati else 0 end as f_grati,
             case when fn_devenga(pe.id, 'cts')        then v_f_cts   else 0 end as f_cts,
             case when fn_devenga(pe.id, 'vacaciones') then v_f_vacas else 0 end as f_vacas
    ) dev
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
      -- CAMBIO 0349 · horas_25/horas_35/horas_recargo_25/horas_recargo_35:
      -- el mismo desglose que trae `sobret`, para que el JSON de salida
      -- pueda declarar el 25 % y el 35 % por separado.
      select s.horas, s.horas_recargo, s.desde, s.hasta,
             s.horas_25, s.horas_35, s.horas_recargo_25, s.horas_recargo_35
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
    -- ⇩ CAMBIO 0280 ⇩ El descanso semanal trabajado de esta persona, si lo hubo.
    --
    -- DOS EXCLUSIONES, NO TRES, y la que falta es la decisión:
    --   · RxH: un locador no tiene descanso remunerado que respetarle. Mismo
    --     criterio que la 0199 le aplicó a los feriados.
    --   · Sueldo fijo: su pago no depende de horas, así que un recargo por
    --     horas no significaría nada — la 0173 ya tuvo que arreglar justo eso
    --     en el feriado.
    --
    -- AL PERSONAL DE DIRECCIÓN SÍ SE LE PAGA, y es lo que lo diferencia del
    -- sobretiempo. La 0187 lo excluye de aquél por el art. 5 del D.S.
    -- 007-2002-TR — pero ese artículo excluye de la JORNADA MÁXIMA, y el
    -- descanso semanal obligatorio es otra norma (D. Leg. 713), que no tiene
    -- esa exclusión. Decisión de Felipe el 2026-08-20, sobre su propio pago.
    -- Para revertirla basta añadir `and pe.personal_direccion is not true`.
    left join lateral (
      select s.horas_recargo, s.dias, s.desde, s.hasta
      from dsem s
      where s.persona_id = pe.id
        and pe.en_planilla is true
        and pe.sueldo_fijo is not true
    ) dsw on true
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
      select tp.aporte + tp.comision + tp.prima as tasa,
             -- CAMBIO 0262 · si este regimen grava el subsidio de EsSalud.
             tp.grava_subsidio
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
      -- ⇩⇩⇩ CAMBIO 0233 ⇩⇩⇩ El día de referencia, no el primer día del periodo.
      --
      -- La regla «vigente al iniciar» de arriba dejaba en CERO a todo el equipo:
      -- el periodo empieza el 29 del mes anterior y DO registra con fecha del
      -- día 1, así que `01/08 <= 29/07` era falso para las siete filas vigentes.
      -- Con periodos del 29 al 28, el día 1 ya es «a mitad de periodo»: el borde
      -- que la 0150 dejó abierto a propósito resultó ser el caso normal.
      --
      -- La 0150 anotó el arreglo como «cambiar p_ini por p_fin, una línea». Esa
      -- línea sola paga DOBLE, medido: una renovación que corta dentro del
      -- periodo —ciclo I hasta el 20/08, ciclo II desde el 21/08— se solapa por
      -- los dos lados y `sum()` cobra los dos ciclos. Con los datos de hoy no es
      -- hipotético: seis de las siete filas vencen entre el 31/08 y el 15/09 y
      -- renuevan al día siguiente.
      --
      -- Así que el filtro se parte en dos. `dref` busca el primer día del periodo
      -- en que la persona tiene ALGUNA asignación vigente; el `where` cobra las
      -- que estén vigentes ESE día. Un solo instante —nunca dos ciclos seguidos
      -- en el mismo mes— y un instante que se corre hacia adelante —quien
      -- empieza a mitad ya cobra—.
      --
      -- Las otras tres reglas siguen intactas y están medidas: dos cursos de
      -- verdad simultáneos suman igual, sin comprobante sigue sin pagar, y un
      -- ciclo que termina el día 5 sigue cobrando el mes completo.
      from asignaciones_educacion ae
      cross join lateral (
        select min(greatest(a2.vigente_desde, p_ini)) as dia
        from asignaciones_educacion a2
        where a2.persona_id = pe.id
          and a2.comprobante_url is not null
          and a2.vigente_desde <= p_fin
          and a2.vigente_hasta >= p_ini
      ) dref
      where ae.persona_id = pe.id
        and ae.comprobante_url is not null
        and ae.vigente_desde <= dref.dia
        and ae.vigente_hasta >= dref.dia
    ) edu on true
    -- ⇩⇩⇩ CAMBIO 0236 ⇩⇩⇩ Por qué la educación vale cero, para que la boleta
    -- pueda decirlo en vez de borrar la línea.
    --
    -- Hasta hoy la boleta pintaba el concepto bajo `educacion > 0`, así que un
    -- monto en cero no salía en el documento: no salía «S/0.00», no salía nada.
    -- Es la razón de que el defecto que arregló la 0233 estuviera un mes entero
    -- a la vista de todo el equipo sin que nadie pudiera verlo — siete personas
    -- con su asignación vigente y su comprobante cargado, cobrando cero, y siete
    -- boletas que no mencionaban la educación por ninguna parte.
    --
    -- Un concepto que desaparece cuando falla es peor que uno que sale mal: el
    -- que sale mal se reclama. Con estos dos datos la boleta escribe la línea en
    -- cero y dice cuál de las dos cosas pasó.
    --
    -- Mira TODAS las asignaciones que se solapan con el periodo, con papel o sin
    -- él: la pregunta no es «cuánto se paga» —eso ya lo contestó `edu`— sino «hay
    -- algo que explicar». Por eso no filtra por comprobante ni por día de
    -- referencia. Si no hay ninguna, la persona no estudia y la boleta no dibuja
    -- nada, que es lo correcto: una línea en cero para quien no estudia sería
    -- ruido, no transparencia.
    left join lateral (
      select count(*) > 0 as hay,
             count(*) filter (where ae.comprobante_url is null) > 0 as sin_papel
      from asignaciones_educacion ae
      where ae.persona_id = pe.id
        and ae.vigente_desde <= p_fin
        and ae.vigente_hasta >= p_ini
    ) edudiag on true
    -- CAMBIO 0276 - EL FERIADO YA NO SE CALCULA ACA: SE PREGUNTA.
    left join lateral (
      select (fd.j->>'monto')::numeric      as monto,
             (fd.j->>'sin_tramo')::int      as sin_tramo,
             (fd.j->>'no_corresponde')::int as no_corresponde,
             (fd.j->>'compensados')::int    as compensados,
             fd.j->'detalle'                as detalle
      from (select fn_feriado_devengado_nucleo(pe.id, p_ini, p_fin, v_dias) as j) fd
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
      -- ⇩⇩⇩ CAMBIO 0242 ⇩⇩⇩ QUIEN NO ES TRABAJADORA NO TIENE BASE IMPONIBLE.
      --
      -- El descuento de pensión es `bri.base × tasa` y era el ÚNICO concepto sin
      -- guarda de vínculo: EsSalud y movilidad la llevan desde la 0117, la
      -- educación desde la 0120, las sobretasas desde la 0193. Este descansaba en
      -- que la base de un locador fuera 0 «porque su básica es 0» — y eso lo
      -- decide el DEFAULT 1130.00 de `personas.sueldo_base_legal` (0103), no una
      -- decisión. Medido el 2026-08-13: con el default puesto se le retenían
      -- S/154.02 al mes, y S/168.62 si además cobraba asignación familiar.
      --
      -- Se guarda la base COMPLETA y no cada término suyo a propósito: así el día
      -- que alguien agregue un concepto nuevo a la base, queda excluido sin que
      -- tenga que acordarse. Es la lección de los tres términos que sí llevaban
      -- su condición y del que no.
      -- ⇩⇩⇩ CAMBIO 0262 ⇩⇩⇩ DOS BASES, PORQUE LA LEY LAS SEPARA.
      --
      -- El subsidio por maternidad NO es remuneracion: no entra a EsSalud (el
      -- 9% de la Ley 26790 grava remuneracion, y por eso mismo el propio
      -- reglamento excluye los subsidios del piso RMV) ni a renta de 5ta. Pero
      -- SI esta afecto al aporte a la AFP — asimetria conocida del sistema
      -- peruano: el TUO de la Ley del SPP lo cuenta como remuneracion
      -- asegurable, y la ONP no. Por eso el termino extra va condicionado a
      -- `grava_subsidio`, que vive en `tasas_pension` y no en una lista escrita
      -- aqui: el dia que cambie el criterio es un UPDATE, no una migracion.
      --
      -- `base_pension` se DERIVA de `base` por nombre, no repitiendo la suma.
      -- Es la regla de la 0192: la base imponible se dice una sola vez. Un
      -- envoltorio de mas cuesta una linea; dos copias de la misma suma cuestan
      -- el dia que alguien agregue un concepto a una y no a la otra.
      -- SE RETIENE SOBRE LO QUE SE PAGO, y por eso el termino se toma de
      -- `pb.monto_subsidio_maternidad` y no del lateral `mat`. Los dos valen lo
      -- mismo casi siempre, pero no para quien cobra monto fijo: `pb` ya lleva
      -- dentro el `case when pe.sueldo_fijo then 0`, porque a esa persona el
      -- subsidio no se le suma al pago. Leyendo `mat` en crudo se le retendria
      -- AFP sobre dinero que nunca entro. Una sola fuente para «cuanto cobro» y
      -- para «sobre cuanto se retiene» es lo que impide que se separen.
      select b.base,
             b.base + (case when coalesce(tpen.grava_subsidio, true)
                            then round(coalesce(pb.monto_subsidio_maternidad, 0), 2)
                            else 0 end) as base_pension
      from (
      select (case when pe.en_planilla is not true then 0 else
             coalesce(pb.basica, 0)
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
                          -- CAMBIO 0280 · la sobretasa del descanso semanal
                          -- entra a la base por lo mismo que el feriado y el
                          -- sobretiempo (0193): el art. 19 del D.S. 001-97-TR
                          -- no la lista como no remunerativa. Y va DENTRO del
                          -- mismo `case`, para que complete una base declarada
                          -- y no cree una donde no la hay — sin eso, a un RxH
                          -- le aparecería pensión de la nada.
                          + round(coalesce(dsw.horas_recargo, 0)
                                  * coalesce(ref.salario, 0) / v_base, 2)
                     else 0 end)
             -- ⇩⇩⇩ CAMBIO 0263 ⇩⇩⇩ LOS 20 DIAS DE DESCANSO MEDICO SON SUELDO.
             --
             -- La 0254 los metio en `pago_base` pero no en `pb.basica`, asi que
             -- no llegaban aqui: se pagaban y no se declaraban. Y no son un
             -- subsidio — el subsidio de EsSalud recien nace el dia 21. Lo que
             -- CAYLA asume del 1 al 20 es REMUNERACION (art. 15 del D.S.
             -- 009-97-SA; criterio de los Informes SUNAT 259-2004 y 003-2007), y
             -- por tanto entra a la base de EsSalud y a la de pension igual que
             -- cualquier dia trabajado.
             --
             -- EL CODIGO DE LA PLAME ES DONDE SE COMETE EL ERROR: el 0916
             -- «Subsidios de incapacidad por enfermedad» es SOLO para lo que
             -- paga EsSalud desde el dia 21. Estos 20 dias no van ahi.
             --
             -- OJO CON LA CONFUSION FACIL: esto es lo CONTRARIO del subsidio por
             -- maternidad de la 0262. Aquel NO entra a EsSalud (no es
             -- remuneracion) y ademas prorratea el piso RMV; este entra a las
             -- dos bases y no toca el piso. Se parecen en la pantalla y son
             -- opuestos en la ley. Por eso el termino va aparte y con su nombre.
             --
             -- Se lee de `pb.monto_descanso_medico` —lo efectivamente pagado— y
             -- no del lateral `dmd`, por la misma razon que la 0262: `pb` ya
             -- lleva dentro la guarda de sueldo fijo, y una sola fuente para
             -- «cuanto cobro» y para «sobre cuanto se declara» es lo que impide
             -- que se separen.
             + (case when pe.en_planilla is true and pe.sueldo_fijo is not true
                     then round(coalesce(pb.monto_descanso_medico, 0), 2)
                     else 0 end)
             -- ⇩⇩⇩ CAMBIO 0316 ⇩⇩⇩ LA LICENCIA CON GOCE TAMBIEN ES SUELDO.
             --
             -- Mismo defecto que arreglo la 0263, y por el mismo camino: la
             -- 0314 metio la licencia con goce y el duelo de familiar directo
             -- en `pago_base` pero no en `pb.basica`, asi que no llegaban aqui.
             -- Se pagaban y no se declaraban.
             --
             -- POR QUE ENTRA. Estos dias los paga CAYLA, no EsSalud. No hay
             -- subsidio de por medio: es remuneracion por un dia en que una
             -- norma dispensa de asistir sin dejar de pagar. El art. 31.4 del
             -- Reglamento Interno lista NUEVE licencias asi, cada una con la
             -- suya; el fallecimiento es la letra a) y viene de la Ley 31602.
             --
             -- El art. 19 del D.S. 001-97-TR ENUMERA lo que no es remunerativo
             -- y esto no esta en esa lista, asi que entra a la base de EsSalud
             -- y a la de pension igual que cualquier dia trabajado. Y el propio
             -- Reglamento lo dice dos veces de frente: el art. 31.3.a —«se
             -- computan como tiempo laborado para el calculo del pago del
             -- articulo 23, AUNQUE NO EXISTA REGISTRO DE MARCAJE»— y el art.
             -- 23.4, que lo repite desde el otro lado.
             --
             -- NO CONFUNDIR CON LA MATERNIDAD (0262), que es el caso opuesto y
             -- esta doce lineas mas arriba: aquel es un subsidio de EsSalud que
             -- el empleador adelanta, NO entra a la base y ademas prorratea el
             -- piso RMV. Se parecen en la pantalla y son contrarios en la ley.
             --
             -- SE LEE DE `pb`, no del lateral `lic`, por la razon de la 0262 y
             -- la 0263: `pb` ya lleva dentro la guarda de sueldo fijo, y una
             -- sola fuente para «cuanto cobro» y para «sobre cuanto se declara»
             -- es lo que impide que las dos respuestas se separen.
             --
             -- CUANTO MUEVE HOY: NADA. Medido en produccion el 2026-08-26,
             -- `licencias_total = 0` y `duelo_familiar_directo` lo creo la 0314
             -- ese mismo dia. Esto entra antes de que haya poblacion, que es
             -- justo cuando sale gratis.
             + (case when pe.en_planilla is true and pe.sueldo_fijo is not true
                     then round(coalesce(pb.monto_licencia_con_goce, 0), 2)
                     else 0 end)
             -- ⇩⇩⇩ CAMBIO 0317 ⇩⇩⇩ LA REMUNERACION VACACIONAL, QUE ERA LA QUE
             -- FALTABA. Tercera vez el mismo defecto, y la ultima de la familia.
             --
             -- MEDIDO. Cuatro personas identicas que faltan los mismos cinco
             -- dias, cambiando solo el TIPO de la ausencia. Las tres que pagan,
             -- pagan exactamente S/483,87:
             --
             --     descanso medico (0263)     la base sube  519,89
             --     licencia con goce (0316)   la base sube  483,87
             --     VACACIONES                 la base sube   36,02
             --
             -- Y esos 36,02 ni siquiera son por las vacaciones: son el feriado
             -- del mes, que si las cuenta en su prorrateo.
             --
             -- POR QUE SE CAIA. `pb.basica` —la basica legal, que es la parte
             -- del sueldo que SI se declara— se prorratea por las HORAS
             -- MARCADAS. Quien esta de vacaciones no marca, asi que sus dias se
             -- pagaban integros como complemento variable, que no es
             -- remunerativo. Medido: quien pasa el periodo ENTERO de vacaciones
             -- acaba con basica legal S/0,00 y se le declara el piso RMV de
             -- S/1.130 habiendo cobrado S/3.000.
             --
             -- POR QUE ENTRA. La remuneracion vacacional es remuneracion, y no
             -- de forma discutible: el art. 15 del D. Leg. 713 la define como
             -- «la que hubiera correspondido percibir habitualmente» en caso de
             -- seguir trabajando. El art. 19 del D.S. 001-97-TR enumera lo que
             -- NO es remunerativo y no la lista. Y el art. 23.4 b) del
             -- Reglamento Interno lo dice directo: los dias de descanso
             -- vacacional gozado se computan como tiempo laborado.
             --
             -- LO QUE LA PERSONA GANA CON ESTO, y conviene decirlo bien: su
             -- LIQUIDO baja, porque sube su descuento de pension. Pero ese sol
             -- no se pierde — va a su fondo de AFP o a su record de ONP, que es
             -- donde tenia que estar. Lo que hoy pasa es que se le paga una
             -- remuneracion que no se le acredita en ninguna parte.
             --
             -- CUANTO MUEVE HOY: NADA. Medido en produccion el 2026-08-26:
             -- CERO personas con vacaciones en el periodo abierto y CERO
             -- periodos ya pagados afectados. Como la 0316, entra en la ventana
             -- en que sale gratis.
             + (case when pe.en_planilla is true and pe.sueldo_fijo is not true
                     then round(coalesce(pb.monto_vacaciones, 0), 2)
                     else 0 end)
             end)                                             -- CAMBIO 0242
             as base
      ) b
    ) bri on true
    -- ⇧⇧⇧ CAMBIO 0192 ⇧⇧⇧
    -- ⇩⇩⇩ CAMBIO 0245 ⇩⇩⇩ LA RETENCIÓN DE 4TA, DICHA UNA SOLA VEZ.
    --
    -- Va en un lateral y no escrita dos veces por la lección de la 0192: el
    -- monto lo usan el concepto del JSON y el término del `total`, y dos
    -- copias de una regla de dinero es como se empieza a tener dos verdades.
    --
    -- LA BASE. Es lo que CAYLA le paga por su servicio ese mes: su pago por
    -- horas más los bonos más el incentivo por metas. NO se le restan los
    -- descuentos: un descuento de planilla es casi siempre «esto ya se te
    -- transfirió por fuera», y restarlo bajaría la retención de un recibo que
    -- se emitió por el monto completo. `obj.monto` vale 0 desde la 0171 y se
    -- suma igual, para que el día que el incentivo vuelva no haya que
    -- acordarse de esta línea.
    --
    -- LAS TRES PUERTAS, y ninguna se abre sola:
    --   · `retencion_4ta` en NULL —como nace todo el mundo— NO retiene nada.
    --     Por eso pegar esta migración no mueve un céntimo de nadie.
    --   · 'automatica' es la regla del art. 74 de la Ley del Impuesto a la
    --     Renta: 8 % solo si el recibo del mes SUPERA el tope (R.S.
    --     013-2007/SUNAT, hoy S/1,500). Igual o por debajo, cero.
    --   · 'siempre' retiene sea cual sea el monto. No es un capricho: lo pide
    --     el prestador al emitir el recibo, cuando sabe que sus ingresos del
    --     año lo dejan fuera de la suspensión y prefiere adelantar el pago en
    --     vez de que le caiga entero en la regularización de marzo.
    --
    -- Y LA CONSTANCIA MANDA SOBRE LAS TRES. Con el Formulario Virtual 1609
    -- vigente, SUNAT prohíbe retener. Se compara contra el FIN del periodo
    -- porque la constancia cubre el mes en que se paga, no el que se calcula.
    -- Cuando vence, el modo vuelve a mandar — que es lo que SUNAT llama
    -- «reinicio de retenciones» — y por eso el modo lo escribe una persona.
    --
    -- EL GUARDA DE VÍNCULO ES `tipo_vinculo = 'rxh'` Y NO `not en_planilla`.
    -- La renta de cuarta es del trabajador independiente; un accionista que
    -- no presta servicios ('no_trabajador') tampoco emite recibo. Nombrar la
    -- condición exacta evita que el día que aparezca un quinto vínculo herede
    -- una retención que nadie decidió darle.
    cross join lateral (
      select b.base,
             case when pe.tipo_vinculo <> 'rxh' then 0
                  when pe.retencion_4ta is null then 0
                  when pe.constancia_4ta_hasta is not null
                   and pe.constancia_4ta_hasta >= p_fin then 0
                  when pe.retencion_4ta = 'siempre' then round(b.base * v_tasa_4ta, 2)
                  when b.base > v_tope_4ta then round(b.base * v_tasa_4ta, 2)
                  else 0 end as monto,
             -- El aviso, que es la otra mitad del trabajo: un locador cuyo
             -- recibo pasa el tope y a quien nadie le configuró el modo. No
             -- retiene por su cuenta —Dynamic avisa, nunca sanciona solo—,
             -- pero deja de ser invisible en la pantalla de planilla.
             (pe.tipo_vinculo = 'rxh'
              and pe.retencion_4ta is null
              and b.base > v_tope_4ta) as sin_configurar
      from (select round(pb.pago_base, 2) + round(obj.monto, 2)
                   + round(mov.bonos, 2) as base) b
    ) r4
  ) sub;

  return v_out;
end;
$function$
;

-- ── fn_provisiones ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_provisiones(p_as_of date DEFAULT NULL::date, p_salario_asof date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

declare
  v_as_of date; v_y int;
  v_prov jsonb; v_f_grati numeric; v_f_cts numeric; v_f_vac numeric;
  v_f_be numeric;   -- CAMBIO 0134
  -- ⇩ CAMBIO 0372 ⇩ El día en que el 9% dejó de viajar DENTRO de la
  -- gratificación y pasó a tener movimiento propio (la 0346, pegada en
  -- producción ese día). Es un hecho histórico, no una configuración: por eso
  -- va como constante a la vista y no en una tabla que alguien pueda mover sin
  -- darse cuenta de que reinterpreta meses de pagos ya hechos.
  v_be_aparte_desde constant date := '2026-09-03';
  v_sexto_cts numeric;   -- CAMBIO 0112
  v_asig numeric;        -- CAMBIO 0113
  g1_ini date; g1_fin date; g1_pago date;
  g2_ini date; g2_fin date; g2_pago date;
  c1_ini date; c1_fin date; c1_pago date;
  c2_ini date; c2_fin date; c2_pago date;
  v_prox_fecha date; v_prox_tipo text; v_prox_ref text;
  v_out jsonb;
  v_sin_salario int;   -- CAMBIO 0365
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver las provisiones.';
  end if;
  v_as_of := coalesce(p_as_of, fn_hoy_lima());
  v_y := extract(year from v_as_of)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion":0.08333,"cts":0.04167,"vacaciones":0.04167,"sexto_cts":0}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts   := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vac   := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- CAMBIO 0134 — la bonificacion extraordinaria (Ley 30334), versionada.
  select pl.valor into v_f_be
  from parametros_laborales pl
  where pl.clave = 'bonificacion_extraordinaria'
    and pl.vigente_desde <= v_as_of
    and (pl.vigente_hasta is null or pl.vigente_hasta >= v_as_of)
  order by pl.vigente_desde desc
  limit 1;
  if v_f_be is null then v_f_be := 0.09; end if;
  -- ⇩⇩⇩ CAMBIO 0112 ⇩⇩⇩ EL SEXTO DE LA GRATIFICACIÓN EN LA BASE DE LA CTS.
  --
  -- El Art. 16 del D.S. 001-97-TR manda que la remuneración computable de la CTS
  -- incluya «un sexto de lo percibido» por gratificación en el semestre. Hasta
  -- ahora la CTS se calculaba solo sobre el sueldo, así que faltaba ese sexto.
  --
  -- En pequeña empresa la gratificación es MEDIA remuneración, así que el sexto
  -- vale (0.5 / 6) = 0.083333 del sueldo, y la base correcta es sueldo × 13/12.
  -- Comprobado: 1,130 × 13/12 × 15/30 = S/612.08 al año, contra los S/565 de hoy.
  -- Faltaban S/47.08 al año por persona.
  --
  -- ARRANCA EN CERO: si la clave no está en configuracion, el multiplicador es 1
  -- y la CTS sale exactamente como hoy. Se activa con un UPDATE:
  --
  --   update configuracion
  --      set valor = valor || '{"sexto_cts": 0.083333}'::jsonb
  --    where clave = 'planilla_provisiones' (sin punto y coma al final a
  --    propósito: ver la nota de blindaje al pie del archivo)
  --
  -- POR QUÉ ES UN MULTIPLICADOR Y NO UN FACTOR NUEVO. Subir el factor de la CTS
  -- de 4.167% a 4.514% daría el mismo número HOY, pero se rompería en cuanto la
  -- base incluya otro concepto remunerativo (la asignación familiar, por ejemplo),
  -- porque el sexto tiene que salir de la gratificación real y no del sueldo pelado.
  -- Multiplicando la base, el sexto sigue siendo un sexto de lo que sea.
  --
  -- SI CAYLA PASARA AL RÉGIMEN GENERAL, donde la gratificación es una remuneración
  -- completa, el valor correcto sería (1 / 6) = 0.166667 y la base sueldo × 7/6.
  v_sexto_cts := coalesce((v_prov->>'sexto_cts')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0113 ⇩⇩⇩ LA ASIGNACIÓN FAMILIAR ENTRA EN LA BASE.
  -- Los S/113 de la Ley 25129 SON remuneración, así que integran la remuneración
  -- computable de gratificación, CTS y vacaciones. Hasta ahora fn_provisiones no
  -- sabía que existían: se pagaban como línea aparte en la boleta y quedaban fuera
  -- de la base. El monto sale de la misma clave que usa la planilla.
  -- ⇩ CAMBIO 0122 ⇩ Esta lectura queda solo como RESPALDO. El valor que de verdad
  -- se usa se busca DÍA POR DÍA más abajo, en la rama de la 0113: esta función
  -- acumula sobre años de historia, y aplicar el monto de hoy a un periodo de 2025
  -- reescribiría lo que ya se pagó. Ver el comentario de esa rama.
  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
  from configuracion where clave = 'asignacion_familiar';
  if v_asig is null then v_asig := 113.00; end if;

  -- Ventanas del ano (periodos legales)
  g1_ini := make_date(v_y,1,1);    g1_fin := make_date(v_y,6,30);  g1_pago := make_date(v_y,7,15);
  g2_ini := make_date(v_y,7,1);    g2_fin := make_date(v_y,12,31); g2_pago := make_date(v_y,12,15);
  c1_ini := make_date(v_y-1,11,1); c1_fin := make_date(v_y,4,30);  c1_pago := make_date(v_y,5,15);
  c2_ini := make_date(v_y,5,1);    c2_fin := make_date(v_y,10,31); c2_pago := make_date(v_y,11,15);

  -- Proximo desembolso: la fecha de pago mas cercana que aun no pasa.
  -- Incluye tambien las ventanas del ANO SIGUIENTE: entre el 16 y el 31 de dic,
  -- tras el ultimo pago del ano (grati_s2, 15-dic), el proximo desembolso cae en
  -- el ano v_y+1 (CTS may). Sin estas filas, 'proximo' quedaria NULL esas dos
  -- semanas de cada diciembre.
  select fecha, tipo, ref into v_prox_fecha, v_prox_tipo, v_prox_ref
  from (values
    (c1_pago, 'CTS',           'cts_may'),
    (g1_pago, 'Gratificacion', 'grati_s1'),
    (c2_pago, 'CTS',           'cts_nov'),
    (g2_pago, 'Gratificacion', 'grati_s2'),
    (make_date(v_y+1, 5,15), 'CTS',           'cts_may'),
    (make_date(v_y+1, 7,15), 'Gratificacion', 'grati_s1'),
    (make_date(v_y+1,11,15), 'CTS',           'cts_nov'),
    (make_date(v_y+1,12,15), 'Gratificacion', 'grati_s2')
  ) t(fecha, tipo, ref)
  where fecha >= v_as_of
  order by fecha
  limit 1;

  with base_cruda as (
    -- 1) Sueldo regular ganado por HORAS (base mensual correcta). Excluye a quien
    --    cobra sueldo fijo: ese va por la rama 2, para no contar dos veces.
    select j.persona_id, j.fecha,
           j.horas_trabajadas * tt.salario
             / (6.5 * extract(day from (date_trunc('month', j.fecha) + interval '1 month - 1 day'))::numeric) as pago_dia
    from jornadas j
    -- ⇩ CAMBIO 0160 ⇩ Quien no devenga beneficios no aporta días a la base.
    join personas pp on pp.id = j.persona_id and not pp.sueldo_fijo
                    and fn_devenga_algo(pp.id)   -- CAMBIO 0196
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = j.persona_id
        -- ⇩⇩⇩ CAMBIO 0338 ⇩⇩⇩ p_salario_asof, si se pasa, congela la fecha
        -- de referencia del sueldo en vez de usar el día de la jornada.
        and coalesce(p_salario_asof, j.fecha) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, j.fecha) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where j.horas_trabajadas is not null and j.horas_trabajadas > 0

    union all

    -- ⇩⇩⇩ CAMBIO 0276 ⇩⇩⇩ 5) EL FERIADO, EL MISMO QUE PAGA LA BOLETA.
    --
    -- Las dos mitades entran: el dia prorrateado (art. 8 del D. Leg. 713) y la
    -- sobretasa por haberlo trabajado (art. 9). Ninguna se calcula aca: se
    -- pregunta a `fn_feriado_devengado`, que es el MISMO sitio del que sale la
    -- linea de feriados de la boleta. Una regla, un sitio.
    --
    -- CADA FERIADO ENTRA POR SU FECHA, no por la ventana. Por eso basta UNA
    -- llamada por persona sobre el tramo mas ancho que alguna ventana pueda
    -- pedir: las cinco ventanas se reparten solas con el `between` que ya
    -- existe abajo. Una llamada por persona en vez de cinco: preguntar ventana
    -- por ventana multiplicaria por cinco un recorrido de `jornadas` que ya es
    -- lo mas caro que hace esta funcion.
    --
    -- SIN p_dias: en ese modo la funcion cobra cada feriado con el bloque del
    -- PERIODO DE PLANILLA en que cayo — o sea, exactamente lo que su boleta
    -- pago ese mes.
    select p.id as persona_id, (e->>'fecha')::date as fecha,
           (e->>'monto')::numeric as pago_dia
    from personas p
    cross join lateral jsonb_array_elements(
      -- ⇩ CAMBIO 0338 ⇩ Se propaga p_salario_asof: el feriado tiene el
      -- mismo defecto de sueldo día por día, por su propia búsqueda interna.
      fn_feriado_devengado(p.id,
        greatest(p.fecha_ingreso, least(c1_ini, g1_ini, v_as_of - 366)),
        v_as_of, null::int, p_salario_asof) -> 'detalle') e
    where fn_devenga_algo(p.id)

    union all

    -- ⇩⇩⇩ CAMBIO 0113 ⇩⇩⇩ 3) ASIGNACIÓN FAMILIAR de quien tiene hijos.
    --
    -- Es remuneración (Ley 25129), así que entra en la base de gratificación, CTS
    -- y vacaciones. La doctrina lo dice con este mismo ejemplo: «si ganas S/1,130
    -- + S/113, tu gratificación será S/1,243, no S/1,130».
    --
    -- Va por día de CALENDARIO y no por jornada marcada, igual que el sueldo fijo:
    -- la asignación se paga completa cada mes, no se recorta por asistencia. Al
    -- sumar un mes entero da los S/113 exactos, y en los bordes del periodo (mes
    -- de ingreso, primer mes de la ventana) prorratea por días, que es el mismo
    -- criterio que ya usaba la rama 2.
    --
    -- Aplica a TODOS los que tienen hijos, con sueldo fijo o por horas: la rama 1
    -- excluye a los de sueldo fijo para no contarlos dos veces, pero la asignación
    -- les corresponde igual, y esta rama no los excluye a propósito.
    -- ⇩⇩⇩ CAMBIO 0122 ⇩⇩⇩ EL MONTO SE BUSCA POR DÍA, no una vez para toda la
    -- historia. La asignación es el 10% de la RMV y sube cuando sube la RMV: si
    -- se aplicara el monto de hoy a los días de 2025, la provisión de un periodo
    -- ya pagado cambiaría al publicarse el decreto. Con la búsqueda por día, cada
    -- día aporta el monto que estaba vigente ESE día y el pasado queda fijo.
    --
    -- Es una subconsulta correlacionada por día y sí cuesta más que leer un
    -- escalar. Se acepta a propósito: la función es 'stable' y se llama a demanda,
    -- y la alternativa es un cálculo que se mueve solo. Si el volumen molesta, el
    -- arreglo es un lateral contra un rango de fechas, no volver al escalar.
    select p.id as persona_id, gs::date as fecha,
           coalesce(
             (select pl.valor
                from parametros_laborales pl
               where pl.clave = 'asignacion_familiar'
                 and pl.vigente_desde <= gs::date
                 and (pl.vigente_hasta is null or pl.vigente_hasta >= gs::date)
               order by pl.vigente_desde desc
               limit 1),
             v_asig)
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from personas p
    cross join lateral generate_series(p.fecha_ingreso::timestamp, v_as_of::timestamp, interval '1 day') gs
    where p.con_hijos

    union all

    -- ⇩⇩⇩ CAMBIO 0135 ⇩⇩⇩ 4) LOS DÍAS QUE LA LEY MANDA CONTAR AUNQUE NADIE MARQUE.
    --
    -- EL PROBLEMA QUE ARREGLA. La rama 1 exige `horas_trabajadas > 0`. Quien está
    -- de vacaciones no marca, así que esos días aportaban CERO a su gratificación:
    -- tomarse las vacaciones le bajaba la gratificación del semestre. Un mes entero
    -- de vacaciones costaba un sexto de la gratificación, a quien ejerció un derecho.
    --
    -- LO QUE MANDA LA NORMA. El D.S. 005-2002-TR art. 2 considera tiempo
    -- efectivamente laborado, para efectos de la gratificación:
    --   a) el descanso vacacional
    --   b) la licencia con goce de remuneraciones
    --   c) los descansos o licencias de la seguridad social que originan subsidio
    --      (descanso médico, maternidad)
    --   d) el descanso por accidente de trabajo remunerado o subsidiado
    --
    -- POR QUÉ `ta.paga` Y NO UNA LISTA DE CÓDIGOS ESCRITA A MANO. El catálogo
    -- `tipos_ausencia` ya distingue cuáles pagan (columna `paga`), y ese es
    -- exactamente el criterio de la norma. Con una lista escrita acá, el día que
    -- Felipe agregue un tipo pagado desde la pantalla habría que acordarse de
    -- tocar esta función — y nadie se va a acordar. Hoy `paga` es true para
    -- vacaciones, descanso_medico y maternidad, y false para duelo, permiso
    -- personal, estudios, cumpleaños, salud-sin-documento y otro. Esos seis NO
    -- deben sumar, y no suman.
    --
    -- POR QUÉ NO EXIGE APROBACIÓN. Una ausencia registrada y no anulada es un
    -- hecho. Exigir `aprobada_at` haría que un descanso médico pendiente de firma
    -- le baje la gratificación a la persona, y la regla de la casa es clara: el
    -- error que más cuesta es el que va contra quien no debía. Si la ausencia
    -- resulta falsa, se anula y deja de contar sola.
    --
    -- CUÁNTO APORTA UN DÍA. Lo mismo que aporta un día de sueldo fijo:
    -- salario / días del mes. Es el día estándar de esa persona a su salario
    -- vigente ESE día, no un promedio — mismo criterio que ya usa la rama 2.
    --
    -- SOLO PARA QUIEN COBRA POR HORAS. Quien tiene sueldo fijo ya devenga todos
    -- los días de calendario por la rama 2; sumarlo acá lo contaría dos veces.
    -- ⇩⇩⇩ CAMBIO 0302 ⇩⇩⇩ DÍAS LABORABLES, NO DÍAS DE CALENDARIO.
    --
    -- Acá decía `salario / días del mes` por cada día de CALENDARIO de la
    -- ausencia. La boleta hace otra cosa: paga la ausencia como si la persona
    -- hubiera trabajado, o sea sus días LABORABLES del tramo. Contar los de
    -- calendario mete los sábados y domingos dos veces —una dentro del sueldo
    -- mensual y otra como día de ausencia—.
    --
    -- Medido con periodo = mes calendario, para aislar esto del divisor:
    -- alguien con 19 días de vacaciones en marzo reservaba S/136,28 de
    -- gratificación mientras la boleta le apuntaba S/115,32. Y ahí está la
    -- prueba de que el equivocado era éste y no la boleta: la reserva le daba
    -- MÁS gratificación a quien estuvo de vacaciones que a quien trabajó el mes
    -- entero. No se devenga más beneficio por no venir.
    --
    -- Y como `fn_grati_cts_periodo` autocompleta el depósito desde acá, ese
    -- exceso salía del banco el 15/05, 15/07, 15/11 y 15/12.
    --
    -- LO QUE NO SE TOCA, Y ES EL CUIDADO DE ESTA RAMA. Existe desde la 0135
    -- porque sin ella tomarse las vacaciones te BAJABA la gratificación —el
    -- error contrario, y ése sí contra la persona—. Sigue contando la ausencia:
    -- lo que cambia es cuántos días y a cuánto el día.
    select p.id as persona_id, gs::date as fecha,
           -- EL DÍA VALE LO MISMO QUE UN DÍA TRABAJADO, y esa es la mitad
           -- que hay que NO tocar. La rama 1 paga cada día marcado a
           -- `salario / días del mes`; si acá se pusiera `salario / días
           -- laborables` —que suena más fino— el día de ausencia valdría MÁS
           -- que el día trabajado. Medido al intentarlo: la diferencia contra
           -- la boleta subía de S/20,96 a S/32,16 en vez de bajar a cero.
           tt.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from ausencias au
    join tipos_ausencia ta on ta.codigo = au.tipo and ta.paga
    -- ⇩⇩⇩ CAMBIO 0308 ⇩⇩⇩ SIN LA FIRMA DE DO NO SE DEVENGA, IGUAL QUE EN LA
    -- BOLETA. La 0306 hizo que `fn_planilla_calcular` dejara de pagar el
    -- descanso médico y la maternidad sin aprobar, y esta función se quedó sin
    -- enterarse: seguía devengando el mes completo. Un descanso médico
    -- registrado y sin firmar pagaba S/0 de sueldo y reservaba como si se
    -- hubiera pagado entero — y de acá sale el depósito, porque
    -- `fn_grati_cts_periodo` es la única que llama a esta función.
    --
    -- Medido (marzo 2026, S/1.950, 19 días del 02 al 20): la reserva se pasaba
    -- S/78,63 de gratificación y S/164,34 sumando CTS, vacaciones y la
    -- bonificación extraordinaria.
    --
    -- SE PREGUNTA AL CATÁLOGO, NO SE ESCRIBE LA LISTA DE TIPOS. La boleta
    -- nombra `descanso_medico` y `maternidad` uno por uno porque tiene un
    -- lateral para cada uno; acá hay una sola rama para los cuatro tipos que
    -- pagan, así que la lista escrita a mano sería exactamente lo que prohíbe
    -- la tercera regla de la casa. `tipos_ausencia.requiere_aprobacion` ya dice
    -- quién necesita firma, y dice lo correcto: descanso médico, maternidad y
    -- licencia con goce sí; vacaciones NO — que es lo que impide que este
    -- cambio le quite las vacaciones a nadie.
    --
    -- `is not true` y no `not`: la guarda tiene que negar también el null, por
    -- la misma razón que los guards SECURITY DEFINER de toda la casa.
    and (ta.requiere_aprobacion is not true or au.aprobada_at is not null)
    -- ⇩ CAMBIO 0160 ⇩
    join personas p on p.id = au.persona_id and not p.sueldo_fijo
                   and fn_devenga_algo(p.id)   -- CAMBIO 0196
    cross join lateral generate_series(
      greatest(au.fecha_inicio, p.fecha_ingreso)::timestamp,
      least(au.fecha_fin, v_as_of)::timestamp,
      interval '1 day') gs
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        -- ⇩ CAMBIO 0338 ⇩
        and coalesce(p_salario_asof, gs::date) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, gs::date) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    -- ⇩ CAMBIO 0302 ⇩ El horario vigente ESE día, y cuántos días laborables
    -- tiene su mes. Se busca por día y no una vez, por lo mismo que la 0122
    -- hizo con la asignación familiar: un cambio de horario no puede reescribir
    -- lo que ya se devengó.
    join lateral (
      select ha.dias_laborables, ha.horario_por_dia
      from horarios_asignados ha
      where ha.persona_id = p.id and ha.vigente_desde <= gs::date
      order by ha.vigente_desde desc limit 1
    ) hor on true
    where au.anulada_at is null
      -- ⇩ CAMBIO 0302 ⇩ Solo los días que le tocaba trabajar. Un domingo dentro
      -- de unas vacaciones no es un día de vacaciones: ya era descanso.
      and case when hor.horario_por_dia is not null
               then hor.horario_por_dia ? (extract(dow from gs)::int::text)
               else extract(dow from gs)::int = any(hor.dias_laborables) end
      -- Si ese día SÍ marcó, la rama 1 ya lo contó. Puede pasar: media jornada
      -- trabajada y media de permiso, o una ausencia registrada tarde sobre un
      -- día que ya tenía marcas.
      and not exists (
        select 1 from jornadas j
        where j.persona_id = p.id and j.fecha = gs::date
          and j.horas_trabajadas is not null and j.horas_trabajadas > 0
      )
      -- ⇩⇩⇩ CAMBIO 0276 ⇩⇩⇩ UN FERIADO DENTRO DE UN DESCANSO MÉDICO NO SE
      -- CUENTA DOS VECES.
      --
      -- Esta línea nace de esta misma migración y arregla algo que ella misma
      -- rompía. Al aparecer la rama 5 —el feriado, que antes no estaba en esta
      -- base—, un feriado caído dentro de un descanso médico entraba DOS veces:
      -- una como día de ausencia pagada acá, y otra como feriado allá.
      --
      -- SE ESPEJA A LA BOLETA, TIPO POR TIPO, y no se aplica a los tres por
      -- igual, porque la boleta no los trata igual:
      --   · descanso médico → su lateral `dmd` EXCLUYE el feriado desde la
      --     0254 («un día que ya paga por otra vía no se paga dos veces»), así
      --     que acá también hay que excluirlo. Es esta línea.
      --   · vacaciones      → su lateral `vacd` NO lo excluye: el feriado se
      --     cuenta como día de vacaciones. Simétrico, no se toca.
      --   · maternidad      → la 0262 lo dejó decidido y medido al revés: el
      --     feriado lo excluye `fn_feriado_devengado` y lo cuenta el lateral
      --     `mat`. Si se quitara de los dos lados el día no lo pagaría nadie,
      --     que fue el primer intento de aquella migración. No se toca.
      --
      -- Medido: descanso médico del 27/04 al 08/05/2026, que contiene el 01/05.
      -- Sin esta línea la base de mayo salía S/169.33 por encima de la boleta;
      -- con ella sale S/102.48, que es exactamente lo que vale el feriado y lo
      -- mismo que sube su gemela con vacaciones en el mismo rango.
      -- ⇩⇩⇩ CAMBIO 0310 ⇩⇩⇩ Y ESTA LÍNEA YA NO VA. Decía:
      --
      --     and not (au.tipo = 'descanso_medico'
      --              and exists (select 1 from feriados f where f.fecha = gs::date))
      --
      -- Se escribió bien y su razón está tres párrafos más arriba: «su lateral
      -- `dmd` EXCLUYE el feriado desde la 0254, así que acá también hay que
      -- excluirlo». Era verdad el día que se escribió.
      --
      -- La 0293 —«el feriado dentro de un descanso médico se paga»— quitó esa
      -- exclusión de `dmd`. La premisa de esta línea quedó falsa y nadie lo
      -- notó, porque la línea sigue corriendo igual de bien: no falla, solo
      -- deja de tener razón.
      --
      -- Resultado: el feriado dentro de un descanso médico **no lo contaba
      -- nadie**. Acá se excluía «porque ya lo cuenta el feriado», y
      -- `fn_feriado_devengado` lo excluye por su cuenta. El día caía entre dos
      -- sillas — exactamente lo que la cabecera de la 0262 advertía que pasaría
      -- si se quitaba de los dos lados, y lo que la 0306 volvió a advertir.
      --
      -- Medido: S/5,24 de gratificación por feriado — un día a salario/31 —
      -- y en la dirección que esta casa considera la más cara, contra la
      -- persona. Con la línea fuera, los tres escenarios que lo tocan cuadran
      -- al céntimo con la boleta (prueba 244).

    union all

    -- 2) SUELDO FIJO: provisiona su salario completo cada mes, marque o no. Se
    --    genera un aporte diario = salario / días del mes para cada día de
    --    calendario desde su ingreso; al sumar un mes entero da el salario, y en
    --    los bordes prorratea por días. Mismo criterio que ya usa planilla.
    select p.id as persona_id, gs::date as fecha,
           sal.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from personas p
    cross join lateral generate_series(p.fecha_ingreso::timestamp, v_as_of::timestamp, interval '1 day') gs
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        -- ⇩ CAMBIO 0338 ⇩
        and coalesce(p_salario_asof, gs::date) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, gs::date) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) sal on true
    -- ⇩ CAMBIO 0160 ⇩ También el sueldo fijo: un socio con sueldo fijo que no
    -- está en planilla tampoco devenga CTS, gratificación ni vacaciones.
    where p.sueldo_fijo and fn_devenga_algo(p.id)   -- CAMBIO 0196
  ),
  -- ⇩⇩⇩ CAMBIO 0276 ⇩⇩⇩ EL FACTOR DE LA 0111, QUE AQUÍ NUNCA ESTUVO.
  --
  -- ESTA ERA LA SEGUNDA DIFERENCIA ENTRE LAS DOS BASES. La 0111 agregó
  -- `asignaciones_salario.base_provision` para que bajar el rango a la básica
  -- legal —lo que la 0110 permite, para que el Rendimiento Extraordinario se
  -- anule solo— no le recortara a nadie la gratificación, la CTS ni las
  -- vacaciones. La boleta multiplica su base por
  -- `base_provision / salario` en cinco sitios. `fn_provisiones` no lo hacía en
  -- ninguno: la palabra `base_provision` aparecía 10 veces en
  -- `fn_planilla_calcular` y CERO acá.
  --
  -- El efecto era el que la 0111 vino a evitar, pero solo en la reserva: con el
  -- rango bajado a 1,130 y `base_provision` en 1,320, la boleta provisionaba
  -- sobre 1,320 y la pantalla de Provisiones —la que dice cuánto hay que tener
  -- guardado, y de la que `fn_grati_cts_periodo` AUTOCOMPLETA el depósito— lo
  -- hacía sobre 1,130. Un 14.4 % menos, en silencio.
  --
  -- SE ESCRIBE UNA VEZ, ENVOLVIENDO LA BASE ENTERA, no cinco veces dentro de
  -- las ramas. Es exactamente el mismo motivo por el que la 0196 apagó los
  -- factores en origen y la 0273 dejó `devengado`/`cobrado` en un solo sitio:
  -- una expresión repetida en cinco ramas es un olvido pedido, y el olvido no
  -- daría error — daría un número.
  --
  -- EL FACTOR SE BUSCA POR DÍA, no una vez por persona. `base` ya es un flujo
  -- diario y cada día trae su propio tramo salarial; aplicar el factor de hoy a
  -- los días de un tramo anterior movería una reserva ya devengada. La boleta,
  -- que solo mira un periodo, se conforma con el ÚLTIMO tramo del periodo
  -- (`ref`); acá se acumula sobre años y esa simplificación no vale. En el caso
  -- normal —un solo tramo, o varios con el mismo factor— las dos dan el mismo
  -- número, que es lo que la prueba 213 comprueba.
  --
  -- ARRANCA INERTE: `base_provision` nace en NULL, el factor sale 1 y ninguna
  -- reserva se mueve al pegar esto. Medido contra la misma función SIN este
  -- envoltorio, celda por celda: 0 distintas. Y encendida, boleta y reserva se
  -- mueven exactamente lo mismo — S/119,42 → S/143,30 en las dos, con
  -- `base_provision` = 2.340 sobre un salario de 1.950.
  base as (
    select bc.persona_id, bc.fecha, bc.pago_dia * coalesce(fac.factor, 1) as pago_dia
    from base_cruda bc
    left join lateral (
      select coalesce(a.base_provision / nullif(a.salario_mensual_soles, 0), 1) as factor
      from asignaciones_salario a
      where a.persona_id = bc.persona_id
        -- ⇩⇩⇩ CAMBIO 0338 ⇩⇩⇩ El factor base_provision/salario también se
        -- congela al sueldo del cierre cuando p_salario_asof se pasa.
        and coalesce(p_salario_asof, bc.fecha) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, bc.fecha) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) fac on true
  )
  select coalesce(jsonb_agg(sub.fila order by sub.nombre), '[]'::jsonb) into v_out
  from (
    select (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id', p.id,
        'nombre', p.nombres || ' ' || p.apellidos,
        'sede', s.codigo,
        'fecha_ingreso', p.fecha_ingreso,
        -- CAMBIO 0428 -- para que la pantalla distinga "aun no devengo" de
        -- "no devenga por su tipo de vinculo" y no repita la ambiguedad que la
        -- 0274 vino a cerrar.
        'tipo_vinculo', p.tipo_vinculo,
        -- ⇩ CAMBIO 0123 · REESCRITO POR LA 0273 ⇩ Lo que FALTA, no un sí/no.
        --
        -- Cada celda es la misma resta: lo devengado menos lo ya cobrado. Las
        -- dos mitades se calculan una sola vez, abajo, en `devengado` y
        -- `cobrado`. Antes cada una de estas líneas repetía la fórmula entera y
        -- la gratificación se quedó sin la resta del libro durante meses.
        --
        -- El negativo SE MUESTRA. Si se depositó de más, aparece en negativo en
        -- vez de esconderse en un cero: decisión de la 0158, defendida por la
        -- prueba 124.
        'grati_s1', round(devengado.g1 - cobrado.g1, 2),
        'grati_s1_pagada', (cobrado.g1 > 0),
        'grati_s1_monto_pagado', nullif(round(cobrado.g1, 2), 0),
        'grati_s2', round(devengado.g2 - cobrado.g2, 2),
        'grati_s2_pagada', (cobrado.g2 > 0),
        'grati_s2_monto_pagado', nullif(round(cobrado.g2, 2), 0),
        'grati_total', col.grati_total,
        -- ⇩ CAMBIO 0134 · AJUSTADO POR LA 0273 ⇩ La bonificación extraordinaria
        -- sale del MISMO número que la gratificación, así que sigue lo que
        -- quede de ella. Antes era todo-o-nada («si la ventana se pagó, la
        -- bonificación se fue con ella»), y con un depósito PARCIAL eso dejaba
        -- de ser cierto: sobre media gratificación pendiente queda media
        -- bonificación pendiente, no la entera ni cero.
        -- ⇩ CAMBIO 0372 ⇩ El 9% deja de derivarse de lo que quede de la
        -- gratificación: tiene devengado propio (9% de lo devengado por
        -- gratificación) y cobrado propio. Ver el lateral `cobrado_be`.
        'be_s1', round(devengado.g1 * v_f_be - cobrado_be.g1, 2),
        'be_s2', round(devengado.g2 * v_f_be - cobrado_be.g2, 2),
        'be_total', col.be_total,
        'tasa_be', v_f_be,
        -- ⇩ CAMBIO 0158 ⇩ Lo que FALTA, no un sí/no. Ver la cabecera.
        'cts_may', round(devengado.cm - cobrado.cm, 2),
        'cts_may_pagada', (cobrado.cm > 0),
        'cts_may_monto_pagado', nullif(round(cobrado.cm, 2), 0),
        'cts_nov', round(devengado.cn - cobrado.cn, 2),
        'cts_nov_pagada', (cobrado.cn > 0),
        'cts_nov_monto_pagado', nullif(round(cobrado.cn, 2), 0),
        -- ⇩ CAMBIO 0271 ⇩ El total resta EXACTAMENTE lo mismo que sus dos
        -- ventanas. Ahora eso ya no hay que cuidarlo a mano: las tres líneas
        -- leen las mismas dos columnas.
        'cts_total', col.cts_total,
        -- para que la pantalla pueda mostrar qué multiplicador se usó
        'sexto_cts', v_sexto_cts,
        -- ⇩ CAMBIO 0273 ⇩ Las vacaciones también descuentan lo depositado. Es la
        -- quinta ventana del libro y era la única que nunca se restaba.
        'vac', col.vac,
        'vac_pagada', (cobrado.vac > 0),
        'vac_monto_pagado', nullif(round(cobrado.vac, 2), 0),
        -- Los días también, no solo el monto: mostrarle «12.4 días acumulados» a
        -- quien no devenga vacaciones es prometer por escrito algo que no
        -- existe, y esa pantalla la lee una persona.
        'vac_dias', case when dev.hay_vac
                         then round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1)
                         else 0 end,
        'proximo_aniversario', va.aniv_next,
        -- El gran total es la suma de las cuatro columnas que la pantalla
        -- muestra —grati + bonificación + CTS + vacaciones— y nada más. Desde
        -- el 2026-08-19 la pantalla lo LEE de aquí en vez de rehacerlo, así que
        -- esta línea es la única definición que existe del número.
        --
        -- Suma las columnas YA REDONDEADAS, a propósito: así el total cuadra
        -- con lo que se ve, hasta el céntimo. Ver el comentario del lateral
        -- `col` para por qué eso importa más de lo que parece.
        -- ⇩⇩⇩ CAMBIO 0365 ⇩⇩⇩ Esta línea era la última del objeto y decía:
        --     'gran_total', col.grati_total + col.be_total + col.cts_total + col.vac
        -- Sigue diciendo lo mismo; solo gana la coma para las dos claves de abajo.
        'gran_total', col.grati_total + col.be_total + col.cts_total + col.vac,
        -- ⇩⇩⇩ CAMBIO 0365 ⇩⇩⇩ DOS CEROS QUE SE VEÍAN IGUALES.
        --
        -- Todas las ramas de `base_cruda` hacen `join lateral` —inner— contra
        -- `asignaciones_salario`: un día sin tramo vigente no aporta nada, y la
        -- fila sale igual (0274) con S/ 0.00 en todo. Ese cero era idéntico al
        -- de quien entró esta semana y al de quien no devenga. Estas dos claves
        -- AVISAN; no cambian ni un céntimo de lo de arriba. Ver el lateral `ssv`.
        -- CAMBIO 0428 -- un practicante nunca tiene reserva por su tramo
        -- de salario (los tres factores ya estan en cero): avisarle "asignale
        -- el salario para que la reserva se calcule" seria mentirle otra vez,
        -- la misma familia de error que esta migracion vino a cerrar.
        'sin_salario_vigente', fn_devenga_algo(p.id) and ssv.sin_salario_vigente,
        'dias_sin_salario', case when fn_devenga_algo(p.id) then ssv.dias_sin_salario else 0 end
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    -- ⇩⇩⇩ CAMBIO 0196 ⇩⇩⇩ EL FACTOR SE APAGA EN ORIGEN.
    --
    -- Los tres factores se leen una vez arriba y se usan QUINCE veces en el
    -- bloque de la fila: en cada ventana, en cada total y en el gran total.
    -- Poner un `case when devenga…` en cada una de las quince es pedir un
    -- olvido — y el olvido no daría error: daría un número.
    --
    -- Acá el factor de quien no devenga ese beneficio vale CERO, y las quince
    -- expresiones dan cero solas. Una regla, un sitio, nada que sincronizar.
    cross join lateral (
      select case when fn_devenga(p.id, 'grati')      then v_f_grati else 0 end as f_grati,
             case when fn_devenga(p.id, 'cts')        then v_f_cts   else 0 end as f_cts,
             case when fn_devenga(p.id, 'vacaciones') then v_f_vac   else 0 end as f_vac,
             fn_devenga(p.id, 'vacaciones')                                     as hay_vac
    ) dev
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    -- ⇩ CAMBIO 0158 · AMPLIADO POR LA 0273 ⇩ Lo que dice el LIBRO de desembolsos.
    -- La 0123 pregunta si hubo movimiento de planilla; eso solo ve lo que pasó
    -- POR la planilla. La CTS de mayo 2026 salió por PLAME —al banco, a la
    -- cuenta CTS de cada persona— y de eso la planilla no sabe nada.
    --
    -- ⇩⇩⇩ CAMBIO 0273 ⇩⇩⇩ LAS CINCO VENTANAS, Y POR LA PUERTA DE LA 0163.
    --
    -- La 0158 solo leyó las dos de CTS. El libro admite cinco —su `check` lista
    -- grati_s1, grati_s2, cts_may, cts_nov y vacaciones— así que una grati
    -- pagada por transferencia se anotaba y NADIE la restaba: la pantalla la
    -- seguía mostrando pendiente. Medido el 2026-08-19 con un depósito de S/700
    -- de grati_s1: `grati_s1` no se movió de S/749.97 y `pagada` siguió en
    -- false.
    --
    -- Y eso no se quedaba en la reserva: `fn_grati_cts_periodo` lee estos
    -- mismos campos para proponer el bono al cerrar el mes, así que proponía
    -- pagar otra vez lo ya pagado. La CTS no tenía el problema desde la 0158;
    -- la gratificación y las vacaciones sí.
    --
    -- SE PREGUNTA CON `fn_beneficio_ya_depositado`, no con un `sum` propio.
    -- Esa función es de la 0163 y ya era la respuesta a esta misma pregunta
    -- para `fn_cts_trunca` y `fn_grati_trunca`. Tener aquí un segundo `sum`
    -- equivalente es exactamente la forma en que nació el defecto que arregló
    -- la 0271: dos copias de una regla, una se corrige y la otra no.
    --
    -- EL AÑO ES EL DEL DEPÓSITO, no el del devengo. Lo dice el comentario de la
    -- 0163 y vale para las cuatro ventanas fijas: grati_s1 se paga el 15/07 de
    -- v_y, grati_s2 el 15/12 de v_y, cts_may el 15/05 de v_y (cubriendo desde
    -- noviembre anterior) y cts_nov el 15/11 de v_y.
    cross join lateral (
      select
        fn_beneficio_ya_depositado(p.id, 'grati_s1',   v_y) as grati_s1,
        fn_beneficio_ya_depositado(p.id, 'grati_s2',   v_y) as grati_s2,
        fn_beneficio_ya_depositado(p.id, 'cts_may',    v_y) as cts_may,
        fn_beneficio_ya_depositado(p.id, 'cts_nov',    v_y) as cts_nov,
        fn_beneficio_ya_depositado(p.id, 'vacaciones', v_y) as vacaciones
    ) lib
    -- ⇩ CAMBIO 0123 ⇩ ¿Ya se desembolsó cada ventana?
    cross join lateral (
      select
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g1_pago between pp.fecha_ini and pp.fecha_fin) as g1,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g2_pago between pp.fecha_ini and pp.fecha_fin) as g2,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'cts'
                   and c1_pago between pp.fecha_ini and pp.fecha_fin) as cm,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'cts'
                   and c2_pago between pp.fecha_ini and pp.fecha_fin) as cn
    ) pag
    -- ⇩⇩⇩ CAMBIO 0372 ⇩⇩⇩ ¿Y EL 9%? LA PREGUNTA QUE NADIE HACÍA.
    --
    -- Hasta la 0346 el 9% de la Ley 30334 no tenía movimiento propio: quien lo
    -- pagaba lo sumaba a mano DENTRO del monto de «Gratificación». Por eso
    -- bastaba con mirar `pag.g1` — si la gratificación estaba pagada, el 9% se
    -- había ido con ella, y la convención era cierta.
    --
    -- La 0346 rompió esa convención a propósito, porque lo pidió el contador:
    -- ahora son dos movimientos separados. Pero se puede registrar solo el
    -- primero —el desplegable no obliga a nada— y entonces el 9% queda
    -- debiéndose sin que ninguna pantalla lo diga.
    --
    -- Las dos preguntas que faltaban:
    --   be1/be2   · ¿existe el movimiento propio del 9% de esa ventana?
    --   mez1/mez2 · ¿la gratificación de esa ventana se registró cuando el 9%
    --               todavía viajaba dentro? Entonces ya se pagó, y NO se
    --               reclama hacia atrás: es la decisión de Felipe del
    --               2026-09-03 —«no se corrige lo ya pagado; lo que importa es
    --               que quede separado de acá en adelante»—. Sin esta segunda
    --               pregunta, esta migración le inventaría al sistema una deuda
    --               del 9% sobre TODAS las gratificaciones del historial.
    cross join lateral (
      select
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'bonificacion_extraordinaria'
                   and g1_pago between pp.fecha_ini and pp.fecha_fin) as be1,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'bonificacion_extraordinaria'
                   and g2_pago between pp.fecha_ini and pp.fecha_fin) as be2,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g1_pago between pp.fecha_ini and pp.fecha_fin
                   and (m.created_at at time zone 'America/Lima')::date
                       < v_be_aparte_desde) as mez1,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g2_pago between pp.fecha_ini and pp.fecha_fin
                   and (m.created_at at time zone 'America/Lima')::date
                       < v_be_aparte_desde) as mez2
    ) pag_be
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g1_ini,p.fecha_ingreso) and least(v_as_of,g1_fin)) g1 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g2_ini,p.fecha_ingreso) and least(v_as_of,g2_fin)) g2 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c1_ini,p.fecha_ingreso) and least(v_as_of,c1_fin)) cm on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c2_ini,p.fecha_ingreso) and least(v_as_of,c2_fin)) cn on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between va.aniv_ini and v_as_of) vv on true
    -- ⇩⇩⇩ CAMBIO 0273 ⇩⇩⇩ CADA REGLA, UNA SOLA VEZ.
    --
    -- El bloque de arriba usaba la misma expresión hasta CINCO veces por
    -- ventana: en la celda, en la bandera `pagada`, en el monto pagado, en el
    -- total y en el gran total. Así nació el defecto de la 0271 — `cts_total`
    -- se quedó con la fórmula anterior a la 0158 mientras sus celdas ya
    -- restaban, y durante meses nadie pudo verlo porque había que comparar dos
    -- expresiones largas escritas en sitios distintos.
    --
    -- Acá se calcula UNA vez lo devengado y UNA vez lo ya cobrado, y todo lo de
    -- arriba es una resta. Si mañana cambia la regla, cambia en un solo sitio y
    -- no hay una segunda copia que se pueda quedar vieja.
    cross join lateral (
      select dev.f_grati * coalesce(g1.pago, 0)                     as g1,
             dev.f_grati * coalesce(g2.pago, 0)                     as g2,
             dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago, 0)   as cm,
             dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago, 0)   as cn,
             dev.f_vac * coalesce(vv.pago, 0)                       as vac
    ) devengado
    -- Lo YA COBRADO por cada ventana, por cualquiera de las dos vías.
    --
    -- SE TOMA LA MAYOR, NUNCA LA SUMA. Es la decisión de la 0158 y su prueba
    -- 124 la defiende: si un pago quedó anotado en los dos sitios —la planilla
    -- y el libro— sumarlos descontaría el doble y dejaría la provisión corta.
    -- La planilla, cuando detecta el pago, asume la ventana COMPLETA; el libro
    -- sabe el monto exacto. La mayor de las dos es la respuesta prudente.
    --
    -- Las vacaciones no tienen vía de planilla que mirar (`pag` no las trae),
    -- así que su única fuente es el libro.
    cross join lateral (
      select greatest(case when pag.g1 then devengado.g1 else 0 end, lib.grati_s1) as g1,
             greatest(case when pag.g2 then devengado.g2 else 0 end, lib.grati_s2) as g2,
             greatest(case when pag.cm then devengado.cm else 0 end, lib.cts_may)  as cm,
             greatest(case when pag.cn then devengado.cn else 0 end, lib.cts_nov)  as cn,
             lib.vacaciones                                                        as vac
    ) cobrado
    -- ⇩⇩⇩ CAMBIO 0372 ⇩⇩⇩ LO YA COBRADO DEL 9%, CON SU PROPIA CUENTA.
    --
    -- Misma forma que `cobrado` de arriba y por la misma razón: se toma la
    -- MAYOR de las dos fuentes, nunca la suma (decisión de la 0158, prueba 124).
    --
    --   · la planilla, cuando ve el movimiento del 9% —o una gratificación de
    --     las de antes, con el 9% dentro—, asume la ventana COMPLETA;
    --   · el libro de desembolsos no tiene ventana propia para el 9%, así que
    --     su parte se deriva de lo anotado para la gratificación: si allí se
    --     registró medio depósito, con él se fue medio 9%. Es exactamente lo
    --     que esta función ya hacía, y se conserva.
    --
    -- LA PROPIEDAD QUE ESTO CONSERVA, y que la prueba 295 fija: cuando el 9%
    -- está saldado por cualquiera de las dos vías, este lateral vale
    -- EXACTAMENTE `cobrado.gX * v_f_be` — el mismo número que daba la fórmula
    -- anterior. Lo único que cambia es el caso que nadie miraba: gratificación
    -- registrada por separado y 9% nunca registrado.
    cross join lateral (
      select greatest(case when pag_be.be1 or pag_be.mez1 then devengado.g1 else 0 end,
                      lib.grati_s1) * v_f_be as g1,
             greatest(case when pag_be.be2 or pag_be.mez2 then devengado.g2 else 0 end,
                      lib.grati_s2) * v_f_be as g2
    ) cobrado_be
    -- ⇩⇩⇩ CAMBIO 0273 ⇩⇩⇩ LAS CUATRO COLUMNAS QUE SE VEN, REDONDEADAS UNA VEZ.
    --
    -- El gran total se arma sumando ESTAS, no repitiendo el cálculo con más
    -- decimales. Parece un detalle y es la queja con la que empezó todo esto:
    -- redondear la suma da un resultado distinto de sumar los redondeos, y la
    -- diferencia —un céntimo— cae justo en la celda que la persona compara con
    -- las de al lado. Medido: columnas 1232.76 contra un total de 1232.77.
    --
    -- Un céntimo no es plata, pero un total que no cuadra con lo que se ve
    -- enseña a desconfiar de la pantalla entera. Y esta pantalla existe para
    -- que alguien pueda revisarla.
    cross join lateral (
      select round((devengado.g1 - cobrado.g1) + (devengado.g2 - cobrado.g2), 2)            as grati_total,
             -- CAMBIO 0372 — suma las dos ventanas del 9%, cada una con su
             -- propia resta. Antes era el 9% de la gratificación pendiente.
             round((devengado.g1 * v_f_be - cobrado_be.g1)
                 + (devengado.g2 * v_f_be - cobrado_be.g2), 2)                     as be_total,
             round((devengado.cm - cobrado.cm) + (devengado.cn - cobrado.cn), 2)            as cts_total,
             round(devengado.vac - cobrado.vac, 2)                                          as vac
    ) col
    -- ⇩⇩⇩ CAMBIO 0365 ⇩⇩⇩ ¿FALTA EL TRAMO DE SALARIO? (hallazgo 23 de la
    -- auditoría del 2026-09-03/04)
    --
    -- `sin_salario_vigente` pregunta por la FECHA DE CORTE con la MISMA
    -- expresión de vigencia que usan los laterales `tt`, `sal` y `fac` de
    -- arriba —`coalesce(p_salario_asof, día)`—, para que la bandera diga lo
    -- mismo que el cálculo también en el modo «piso» de la 0338.
    --
    -- `dias_sin_salario` cuenta DÍAS DE CALENDARIO, no jornadas marcadas, y
    -- es a propósito: la rama 2 (sueldo fijo) y la rama 3 (asignación
    -- familiar) ya devengan por calendario, y la persona que más necesita
    -- este aviso —recién ingresada, sin tramo— puede no haber marcado
    -- todavía. Contar jornadas le diría «0 días» a quien lleva un mes sin
    -- salario cargado. Es la medida honesta de «cuánto tiempo lleva sin
    -- salario» sin depender de que haya marcado.
    --
    -- El tramo que se mira es el más ancho que alguna ventana pide, desde el
    -- ingreso: la CTS de mayo arranca en noviembre del año anterior (el
    -- criterio de la rama del feriado) y las VACACIONES arrancan en el
    -- último aniversario de ingreso (`va.aniv_ini`, el mismo que usa el
    -- lateral `vv`), que para quien entró entre enero y octubre cae antes de
    -- ese noviembre. Sin `va.aniv_ini` un hueco de tramo dentro de la
    -- ventana de vacaciones y anterior al 01/11 restaba reserva con 0 días
    -- avisados (medido en la revisión: S/ 89,19). Un día sin tramo fuera de
    -- este rango no le falta a ninguna reserva de este año. `generate_series`
    -- sobre ~350 días contra un `exists` en `asignaciones_salario` es barato
    -- y no vuelve a tocar `jornadas`, que es lo caro de esta función.
    --
    -- En modo «piso» (`p_salario_asof` dado) el conteo es todo-o-nada —0 o
    -- el rango entero— porque `coalesce` congela la fecha y cada día pregunta
    -- lo mismo. Es lo que el cálculo hace en ese modo; la pantalla llama sin
    -- ese argumento.
    cross join lateral (
      select
        not exists (
          select 1 from asignaciones_salario a
           where a.persona_id = p.id
             and coalesce(p_salario_asof, v_as_of) >= a.vigente_desde
             and (a.vigente_hasta is null or coalesce(p_salario_asof, v_as_of) <= a.vigente_hasta)
        ) as sin_salario_vigente,
        (select count(*)::int
           from generate_series(greatest(p.fecha_ingreso, least(c1_ini, g1_ini, va.aniv_ini))::timestamp,
                                v_as_of::timestamp, interval '1 day') gs
          where not exists (
            select 1 from asignaciones_salario a
             where a.persona_id = p.id
               and coalesce(p_salario_asof, gs::date) >= a.vigente_desde
               and (a.vigente_hasta is null or coalesce(p_salario_asof, gs::date) <= a.vigente_hasta)
          )
        ) as dias_sin_salario
    ) ssv
    -- ⇩⇩⇩ CAMBIO 0274 ⇩⇩⇩ ESTA PANTALLA ES UNA RESERVA, NO UN CENSO.
    --
    -- Hasta hoy la única condición era «activo», así que la tabla listaba a
    -- TODO el equipo: locadoras, gente en días de prueba y accionistas salían
    -- con cinco columnas en S/ 0.00. Los ceros no eran un error de cálculo
    -- —la 0196 ya apagaba sus factores en origen y esa parte sigue igual—,
    -- pero llenaban la pantalla de filas que no reservan nada y obligaban a
    -- leerlas una por una para comprobar que, en efecto, no reservan nada.
    --
    -- LA CONDICIÓN NO ES EL TIPO DE VÍNCULO, ES SI DEVENGA. Sería más corto
    -- escribir `tipo_vinculo = 'planilla'`, y estaría mal: desde la 0196 el
    -- devengo se decide POR PERSONA y POR BENEFICIO, y ese interruptor existe
    -- justo para los casos que el tipo de vínculo no sabe expresar. Filtrar
    -- por el tipo escondería a quien tenga un beneficio encendido a mano —y
    -- esconder a alguien de la pantalla de reservas es dejar de reservar su
    -- plata sin que nadie lo vea. `fn_devenga_algo` pregunta por los tres
    -- beneficios; quien no devenga ninguno es quien no tiene nada que reservar.
    --
    -- QUIEN DEVENGA Y HOY SUMA CERO SIGUE SALIENDO, a propósito: alguien que
    -- entró esta semana reserva S/ 0.00 porque aún no devengó, no porque no le
    -- corresponda. Ese cero sí significa algo y tiene que verse.
    -- CAMBIO 0428 -- el practicante entra por su tipo de vinculo, no por
    -- fn_devenga_algo: nunca va a devengar nada por definicion legal, y sin
    -- esta segunda puerta nunca iba a tener fila. Es una puerta que SUMA
    -- filas, nunca las quita: a quien ya entraba por fn_devenga_algo esto no
    -- lo toca.
    where p.estado = 'activo'
      and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
      and (fn_devenga_algo(p.id) or p.tipo_vinculo = 'practicante')   -- CAMBIO 0274 + 0428
  ) sub;

  -- ⇩⇩⇩ CAMBIO 0365 ⇩⇩⇩ Cuántas filas llevan la bandera. Se cuenta sobre el
  -- jsonb ya armado —no hay un segundo recorrido de `jornadas`— para que la
  -- pantalla lo diga una vez arriba de la tabla sin tener que recorrerla.
  select count(*)::int into v_sin_salario
  from jsonb_array_elements(v_out) e
  where (e ->> 'sin_salario_vigente')::boolean is true;

  return jsonb_build_object(
    'as_of', v_as_of,
    'factores', v_prov,
    'proximo', jsonb_build_object('fecha', v_prox_fecha, 'tipo', v_prox_tipo, 'ref', v_prox_ref),
    'grati_s1_pago', g1_pago, 'grati_s2_pago', g2_pago,
    'cts_may_pago', c1_pago, 'cts_nov_pago', c2_pago,
    'grati_s1_periodo', 'ene-jun', 'grati_s2_periodo', 'jul-dic',
    'cts_may_periodo', 'nov-abr', 'cts_nov_periodo', 'may-oct',
    -- ⇩⇩⇩ CAMBIO 0365 ⇩⇩⇩ Decía:  'personas', v_out
    'personas', v_out,
    'personas_sin_salario', v_sin_salario
  );
end;


$function$
;

-- ── fn_vacaciones_resumen ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vacaciones_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_as_of date;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver el resumen de vacaciones.';
  end if;
  v_as_of := coalesce(p_as_of, fn_hoy_lima());

  select coalesce(jsonb_agg(s.fila order by s.nombre), '[]'::jsonb) into v_out
  from (
    select
      (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id',          p.id,
        'nombre',              p.nombres || ' ' || p.apellidos,
        'fecha_ingreso',       p.fecha_ingreso,
        'aniversario_ini',     av.aniv_ini,
        'aniversario_next',    av.aniv_next,
        'dias_transcurridos',  gd.dias_transcurridos,
        'dias_ganados',        gd.dias_ganados,
        'dias_tomados',        gd.dias_tomados,
        'dias_saldo',          round(gd.dias_ganados - gd.dias_tomados, 1),
        'dias_con_marca',      coalesce(hm.dias_con_marca, 0),
        'horas_marcadas',      round(coalesce(hm.horas, 0), 2),
        'feriados_en_periodo', coalesce(fe.n, 0),
        'horas_feriados',      round(gd.horas_feriados, 2),
        'horas_base',          round(gd.base_horas, 2),
        'factor',              gd.factor,
        'salario',             sal.salario,
        -- Lo que le toca por sus días PENDIENTES. Topado en 0: no hay pago negativo.
        'monto_estimado',      case when sal.salario is not null
                                 then round(greatest(0,
                                        (sal.salario / 2) * gd.factor
                                        * (gd.dias_ganados - gd.dias_tomados) / 15.0
                                      ), 2)
                                 else null end
      ) as fila
    from personas p
    -- aniversario (solo informativo: el saldo ya NO depende de esta ventana)
    join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) av on true
    -- horas marcadas en el AÑO EN CURSO (desde su último aniversario): es la
    -- referencia del ritmo de trabajo con que se paga el descanso.
    left join lateral (
      select sum(j.horas_trabajadas) as horas,
             count(*) filter (where j.horas_trabajadas > 0) as dias_con_marca
      from jornadas j
      where j.persona_id = p.id
        and j.fecha between av.aniv_ini and v_as_of
        and j.horas_trabajadas is not null and j.horas_trabajadas > 0
    ) hm on true
    left join lateral (
      select count(*) as n
      from feriados f
      where f.fecha between av.aniv_ini and v_as_of
        and not exists (
          select 1 from jornadas j2
          where j2.persona_id = p.id and j2.fecha = f.fecha
            and j2.horas_trabajadas is not null and j2.horas_trabajadas > 0
        )
    ) fe on true
    -- Días tomados en TODA su historia (no recortado a la ventana del aniversario):
    -- ésta es la corrección de fondo respecto de 0043.
    left join lateral (
      select coalesce(sum(
               greatest(0, (least(v.fecha_fin, v_as_of) - v.fecha_inicio) + 1)
             ), 0)::numeric as dias
      from vacaciones v
      where v.persona_id = p.id and v.fecha_inicio <= v_as_of
    ) vt on true
    -- días tomados dentro del año en curso: solo para descontarlos de la BASE de
    -- horas (esos días no se le pueden exigir trabajados)
    left join lateral (
      select coalesce(sum(
               greatest(0, (least(v.fecha_fin, v_as_of) - greatest(v.fecha_inicio, av.aniv_ini)) + 1)
             ), 0)::numeric as dias
      from vacaciones v
      where v.persona_id = p.id
        and v.fecha_inicio <= v_as_of and v.fecha_fin >= av.aniv_ini
    ) vv on true
    left join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and a.vigente_desde <= v_as_of
        and (a.vigente_hasta is null or a.vigente_hasta >= v_as_of)
      order by a.vigente_desde desc limit 1
    ) sal on true
    join lateral (
      select
        (v_as_of - av.aniv_ini) as dias_transcurridos,
        -- ACUMULADO desde el ingreso, sin tope: 2 años de servicio = 30 días
        round(15.0 * greatest(0, (v_as_of - p.fecha_ingreso))::numeric / 365.0, 1) as dias_ganados,
        vt.dias as dias_tomados,
        (45.0 * greatest(0, (v_as_of - av.aniv_ini) - vv.dias)::numeric / 7.0) as base_horas,
        coalesce(
          coalesce(fe.n, 0)::numeric
            * coalesce(hm.horas, 0) / nullif(coalesce(hm.dias_con_marca, 0), 0)
        , 0) as horas_feriados
    ) g0 on true
    join lateral (
      select g0.dias_transcurridos, g0.dias_ganados, g0.dias_tomados,
             g0.base_horas, g0.horas_feriados,
             case when p.sueldo_fijo then 1.0
                  when g0.base_horas > 0
                    then round((coalesce(hm.horas, 0) + g0.horas_feriados) / g0.base_horas, 4)
                  else 0 end as factor
    ) gd on true
    where p.estado = 'activo' and p.fecha_ingreso is not null
      and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
  ) s;

  return coalesce(v_out, '[]'::jsonb);
end;
$function$
;

-- ── fn_poblacion_obligada ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_poblacion_obligada()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id from personas
  where estado = 'activo' and tipo_vinculo = 'planilla'
    and not cuenta_de_servicio;   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
$function$
;

-- ── fn_politica_salarial_vigente ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_politica_salarial_vigente()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_yo   uuid;
  v_row  politica_salarial%rowtype;
  v_hoy  text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'Inicia sesion para ver la politica salarial.';
  end if;

  select * into v_row from politica_salarial order by version desc limit 1;

  if not found then
    return jsonb_build_object(
      'publicada',    false,
      'desactualizada', false,
      'mi_acuse',     null,
      'aviso', 'Todavia no se ha publicado ninguna version. Mientras tanto CAYLA sigue incursa en el numeral 25.23 del RLGIT.'
    );
  end if;

  v_hoy := md5(fn_cuadro_categorias()::text);

  return jsonb_build_object(
    'publicada',      true,
    'version',        v_row.version,
    'documento',      v_row.documento,
    'publicada_at',   v_row.publicada_at,
    'notas',          v_row.notas,
    -- Si el cuadro cambio despues de publicar, el documento que la gente acuso
    -- ya no describe la realidad. Hay que publicar de nuevo.
    'desactualizada', v_row.huella_cuadro <> v_hoy,
    'mi_acuse', (
      select jsonb_build_object('acusado_at', a.acusado_at, 'nombre', a.nombre_declarado)
      from politica_salarial_acuses a
      where a.persona_id = v_yo and a.version = v_row.version
    ),
    'total_personas', (
      select count(*)::int from personas
      where estado = 'activo' and en_planilla is true
        and not cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    ),
    'total_acuses', (
      select count(*)::int from politica_salarial_acuses a
      join personas p on p.id = a.persona_id
      where a.version = v_row.version and p.estado = 'activo' and p.en_planilla is true
        and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    )
  );
end;
$function$
;

-- ── fn_documentos_tablero: NO se reescribe acá (aplicar_0491) ─────────────
-- Ya lo dejó la 0492, con la línea de la 0491 adentro. Ver la cabecera.

-- ── fn_contratos_tablero ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_contratos_tablero()
 RETURNS TABLE(persona_id uuid, persona text, sede text, fecha_fin_contrato date, dias_restantes integer, contrato_id uuid, tipo text, fecha_firma date, copia_entregada_at date, comunicado_mtpe_at date, copia_vence date, mtpe_vence date, dias_marcados_despues integer, estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ultimo as (
    -- El contrato que manda por persona: el más reciente sin anular.
    select distinct on (c.persona_id)
           c.persona_id, c.id, c.tipo, c.fecha_firma, c.fecha_inicio,
           c.copia_entregada_at, c.comunicado_mtpe_at
      from contratos_generados c
     where c.anulado_at is null
     order by c.persona_id, c.generado_at desc,
              c.fecha_inicio desc, c.fecha_fin desc, c.id desc
  ),
  -- Marcó días DESPUÉS de su fecha de fin: el riesgo del art. 77 que la 0231
  -- ya sabe calcular y que hasta hoy no miraba ninguna pantalla.
  desn as (select * from fn_contratos_desnaturalizados()),
  -- La fecha que gobierna, para una practicante, nunca pasa del tope legal de
  -- 12 meses desde que ingresó — aunque su convenio diga otra cosa o no tenga
  -- fecha puesta (0336).
  gobierna as (
    select p.id as persona_id,
           case
             when p.tipo_vinculo <> 'practicante' then p.fecha_fin_contrato
             when p.fecha_fin_contrato is null
               then (p.fecha_ingreso + interval '12 months')::date
             else least(p.fecha_fin_contrato, (p.fecha_ingreso + interval '12 months')::date)
           end as fecha_efectiva
      from personas p
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '—'),
    g.fecha_efectiva,
    (g.fecha_efectiva - fn_hoy_lima())::int,
    u.id, u.tipo, u.fecha_firma,
    u.copia_entregada_at, u.comunicado_mtpe_at,
    -- Los dos plazos de la cláusula décima octava. El de la copia corre desde
    -- el inicio de la prestación y es en días HÁBILES; se aproxima con días
    -- calendario + 2, que es lo que puede hacer una consulta sin calendario de
    -- feriados delante — y para avisar con tiempo basta.
    (u.fecha_inicio + 5)::date,
    (u.fecha_firma + 15)::date,
    coalesce(d.dias_marcados_despues, 0),
    case
      when d.persona_id is not null                     then 'desnaturalizado'
      when u.id is null                                 then 'sin_contrato'
      when u.fecha_firma is null                        then 'sin_firmar'
      -- Un indefinido se resuelve ACÁ, antes del chequeo genérico de
      -- vencimiento: su fecha efectiva es SIEMPRE null (no tiene fecha de
      -- término), así que si se dejara caer al chequeo de abajo quedaría en
      -- 'sin_vencimiento' para siempre — un falso positivo permanente.
      when u.tipo = 'indefinido' and u.copia_entregada_at is null then 'tramite_pendiente'
      when u.tipo = 'indefinido'                        then 'ok'
      when g.fecha_efectiva is null                      then 'sin_vencimiento'
      when g.fecha_efectiva < fn_hoy_lima()               then 'vencido'
      when g.fecha_efectiva - fn_hoy_lima() <= 60         then 'por_vencer'
      -- ⇩⇩⇩ CAMBIO 0470 ⇩⇩⇩ ya no exige `comunicado_mtpe_at`: el Decreto
      -- Legislativo N.° 1246 (vigente desde 2016-11-11) eliminó esa
      -- comunicación a la Autoridad Administrativa de Trabajo tanto para
      -- contratos sujetos a modalidad (modificó el art. 73, D.S. 003-97-TR)
      -- como para convenios de modalidad formativa (derogó el último párrafo
      -- del art. 46, Ley 28518). No queda ningún tipo de contrato al que
      -- este trámite le corresponda — la columna sigue existiendo por si se
      -- quiere anotar algo ahí, pero ya no bloquea 'ok'.
      when u.copia_entregada_at is null                 then 'tramite_pendiente'
      else 'ok'
    end
  from personas p
  join gobierna g on g.persona_id = p.id
  left join sedes s on s.id = p.sede_base_id
  left join ultimo u on u.persona_id = p.id
  left join desn d on d.persona_id = p.id
  where p.estado = 'activo'
    and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    -- Una practicante también entra al tablero (0333). El guarda es
    -- `tipo_vinculo = 'practicante'` y NO `not en_planilla`: un locador RxH no
    -- tiene contrato ni convenio que generar y sigue fuera, igual que antes.
    and (p.en_planilla or p.tipo_vinculo = 'practicante')
    and fn_es_admin_o_lider() is true
  -- Lo que urge primero: quien ya está en riesgo, y después por vencimiento.
  order by
    case
      when d.persona_id is not null then 0
      when u.id is null then 1
      when u.fecha_firma is null then 2
      else 3
    end,
    g.fecha_efectiva nulls last,
    p.apellidos;
$function$
;

-- ── fn_educacion_candidatos ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_educacion_candidatos()
 RETURNS TABLE(persona_id uuid, persona text, sede text, rango text, tope numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    t.tope_mensual      -- null = rango sin techo cargado; la pantalla lo dice
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = p.id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  left join topes_educacion_rango t on t.rango = sal.rango
  where p.estado = 'activo'
    and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    and fn_es_admin_o_lider() is true
  order by p.apellidos, p.nombres;
$function$
;

-- ── fn_boletas_tablero ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_boletas_tablero(p_periodo_id uuid)
 RETURNS TABLE(persona_id uuid, nombre text, cargo text, sede_codigo text, tipo_vinculo text, tiene_cuenta boolean, grupo_pagado boolean, boleta_id uuid, estado text, version_id uuid, version_n integer, tipo text, n_partes integer, bytes bigint, actualizada boolean, publicada_at timestamp with time zone, vista_at timestamp with time zone, recibida_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve las boletas de todos.';
  end if;

  return query
  select pe.id,
         btrim(pe.nombres || ' ' || pe.apellidos),
         pe.cargo,
         s.codigo,
         pe.tipo_vinculo,
         (pe.auth_user_id is not null),
         exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = p_periodo_id and g.grupo = pe.tipo_vinculo and g.estado = 'pagado'),
         b.id,
         coalesce(b.estado, 'falta'),
         v.id, v.n, v.tipo,
         coalesce(x.n_partes, 0)::int,
         coalesce(x.bytes, 0)::bigint,
         coalesce(v.n > 1 and v.avisar and a.recibida_at is null, false),
         b.publicada_at, a.vista_at, a.recibida_at
    from personas pe
    join sedes s on s.id = pe.sede_base_id
    left join boletas b on b.periodo_id = p_periodo_id and b.persona_id = pe.id
    left join lateral (
      select vv.id, vv.n, vv.tipo, vv.avisar
        from boletas_versiones vv where vv.boleta_id = b.id
       order by vv.n desc limit 1
    ) v on true
    left join boletas_acuses a on a.version_id = v.id
    left join lateral (
      select count(*) as n_partes, sum(pt.bytes) as bytes
        from boletas_partes pt where pt.version_id = v.id
    ) x on true
   where (pe.estado = 'activo' and not pe.cuenta_de_servicio)   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
      or b.id is not null
   order by pe.nombres, pe.apellidos, pe.id;
end;
$function$
;

insert into migraciones_aplicadas (numero, nombre)
values (491, 'la_planilla_y_las_listas_dejan_fuera_a_las_cuentas_de_servicio')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación ────────────────────────────────────────────────────────────
-- Las nueve tienen que decir `true`, y el registro tiene que ser el de esta
-- migración (si dice otro nombre, alguien más tenía el 491).
select p.proname::text                                 as que,
       position('cuenta_de_servicio' in p.prosrc) > 0 as excluye_cuentas_de_servicio,
       length(p.prosrc)                               as caracteres
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('fn_planilla_calcular_nucleo', 'fn_provisiones', 'fn_vacaciones_resumen',
                     'fn_poblacion_obligada', 'fn_politica_salarial_vigente', 'fn_documentos_tablero',
                     'fn_contratos_tablero', 'fn_educacion_candidatos', 'fn_boletas_tablero')
union all
select 'registro: ' || coalesce((select nombre from migraciones_aplicadas where numero = 491), '(falta)'),
       null, null
 order by 1;
