-- ============================================================================
-- 0549 — Un estudio de PAGO ÚNICO que ya sustentó su pago deja de pedir calendario
-- ============================================================================
--
-- ESTADO: SIN PEGAR (2026-10-25). Reescribe UNA función (`fn_educacion_situacion`)
-- y comparte versión de partida con la 0526, que está sin pegar en otra rama.
-- LEE EL PÁRRAFO «ORDEN CON LA 0526» ANTES DE PEGAR.
--
-- IDEMPOTENTE Y CON FRENO: va entera en `begin … commit`, y la sección 0 PARA si la
-- función de esta base no es un cuerpo que la migración conoce (la 0450 o ella
-- misma; ver «LA GUARDIA»). Pegarla dos veces sobre su propio resultado no cambia
-- nada; pegarla sobre cualquier otra cosa no pega NADA.
--
-- QUÉ PROMETE
--   Que un estudio de frecuencia 'unico' cuyo pago ya tiene una constancia
--   APROBADA figure 'al_dia' —sin fecha ni plazo de constancia, sin aviso de
--   «pago próximo», fuera del número rojo del menú y de la Bandeja—, en vez de
--   volver a pedirle a Desarrollo Organizacional un «calendario de pagos» que
--   para un pago único no existe.
--
-- EL DEFECTO, CON EL CASO QUE LO DESTAPÓ
--   Medido el 2026-10-25 en el panel: un estudio de pago único, vigencia 10/10 al
--   31/10, con su constancia del 01/10 ya aprobada, figuraba «Sin calendario de
--   pagos» y sumaba al contador rojo del menú. Y el formulario de DO mostraba
--   «Pago único» + 25/10/2026 SIN guardar: guardar eso tal cual lo EMPEORABA
--   (pasaba a «falta enviar» y le pedía una constancia de un pago ya sustentado).
--
--   La causa está en `fn_educacion_situacion` (0450, línea ~1127):
--       when f.proxima_fecha_pago is null  then 'sin_calendario'
--   sin mirar `frecuencia_pago` ni si la familia ya tiene una constancia aprobada
--   (`apr.n`). Y ese NULL significa TRES cosas distintas que el sistema lee siempre
--   como «falta el calendario»:
--     1. nadie dijo todavía cuándo paga;
--     2. la integrante dijo «este fue mi último pago» (la constancia aprobada
--        copia su `proxima_fecha_pago` = NULL a la asignación:
--        `fn_educacion_avanzar_calendario`, 0450/0527);
--     3. el pago único ya se pagó y se sustentó (el caso de arriba: una constancia
--        de un pago único declara NULL, porque no hay otro).
--   Para 'unico' la 2 y la 3 son lo mismo y se resuelven aquí. Para mensual, por
--   ciclo y otra, el NULL SIGUE siendo ambiguo y NO se toca (ver «Lo que no
--   arregla»).
--
--   La constancia de ese caso entró como comprobante inicial
--   (`fn_educacion_registrar` → `educacion_comprobantes` → trigger de la 0450 →
--   entrega aprobada), sin pasar por `fn_educacion_avanzar_calendario`, y con
--   `fecha_pago` = primer día del mes de la vigencia (01/10), no la del voucher.
--
-- PLANILLA: NO LA TOCA. Medido con grep sobre el repositorio el 2026-10-25: ni
--   `fn_planilla_calcular` ni ninguna función de planilla mencionan
--   `fn_educacion_situacion`, `estado_constancia` ni `proxima_fecha_pago`; las
--   leen solo 0450, 0461, 0525, 0527 y 0529 (todas de Educación) y la pantalla. La
--   planilla lee `comprobante_url`. Esto cambia ALERTAS, no plata.
--
-- LA REGLA
--   Un estudio está «sustentado» si frecuencia_pago = 'unico' Y su familia tiene
--   una constancia con estado 'aprobada' (`apr.n > 0`, que ya existía). Entonces:
--     · estado_constancia = 'al_dia', fecha_pago_constancia y plazo = NULL;
--     · pago_proximo = false aunque haya una `proxima_fecha_pago` guardada —pero
--       SOLO cuando el estado es ese 'al_dia': con una constancia pendiente de
--       revisión o rechazada, DO sigue viendo «Pago de estudios en camino» como
--       hoy (el aviso se apaga siguiendo la rama del estado, no por encima de ella);
--     · la columna `proxima_fecha_pago` se devuelve tal cual está (no se reescribe
--       nada: la función sigue siendo de lectura).
--   La rama va DESPUÉS de 'pendiente_revision' y de 'rechazada' (una constancia que
--   espera revisión o que se rechazó es lo que DO tiene que ver primero) y ANTES de
--   'sin_calendario'. Un pago único SIN constancia aprobada sigue la escalera de
--   siempre: sin fecha → 'sin_calendario' (sigue pidiendo); con fecha futura →
--   'al_dia'; con fecha pasada → 'falta_enviar' / 'por_vencer' / 'vencida'.
--
--   Sin columna nueva y sin estado nuevo, a propósito: un estado nuevo rompería los
--   Records cerrados `ESTADO_CONSTANCIA` y `ESTADOS_VALIDOS` del frontend, y esta
--   migración se pega ANTES de fusionar el PR que lo adapta.
--
--   Se deriva en vivo, sin guardar marca. Si DO revierte la aprobación (0525), la
--   constancia pasa a 'rechazada' y el estudio deja de estar sustentado solo, sin
--   que esta función se entere de nada.
--
-- «LA CONSTANCIA APROBADA DE LA VIGENCIA ACTUAL»: EL CRITERIO, CON LA EVIDENCIA
--   La pregunta era si la constancia tiene que ser de la vigencia más reciente o
--   basta con que la familia tenga una (`apr.n` cuenta las de TODA la familia, con
--   las de vigencias anteriores y los pagos adelantados de la 0529). Se leyó cómo
--   nacen las vigencias de una familia:
--     · `fn_educacion_registrar` solo reutiliza la familia AL CORREGIR una
--       asignación que mueve plata: cierra la fila y abre otra con el mismo
--       `familia_id` (0450, líneas ~1480-1530). Una RENOVACIÓN (ciclo II, otro año)
--       es una fila NUEVA con familia nueva (0524, «por qué no solo familia_id»).
--     · Las constancias no se copian a la vigencia nueva: «la familia las comparte»
--       (0450, comentario de `familia_id`: la vigencia nueva no nace sin sustento).
--     · `fn_educacion_enviar_entrega` valida la fecha de pago contra el
--       `min(vigente_desde)` de la FAMILIA, con 62 días de holgura hacia atrás: el
--       propio sistema ya trata a la familia como «el mismo estudio».
--   Conclusión: dentro de una familia, una vigencia nueva es el MISMO pago único
--   con sus datos corregidos, no un pago nuevo; exigir la constancia en la fila
--   más reciente volvería a pedir un sustento que la 0450 se esforzó en no perder
--   (un error en el costo corregido a mitad de ciclo reabriría la alerta). Y un
--   pago único de una vigencia DE VERDAD nueva —la renovación— es otra familia, así
--   que NO queda callado por la constancia de la anterior. Se probó con las dos
--   (supabase/tests/441, casos U8 y U9).
--   Si algún día hace falta distinguir un segundo pago dentro de la misma familia,
--   la frecuencia correcta ya existe: 'otra' o 'mensual', no 'unico'.
--
-- LO QUE NO ARREGLA (decisiones abiertas de Felipe)
--   · FRECUENCIA EN BLANCO CON UNA CONSTANCIA APROBADA. La regla solo ayuda cuando
--     la frecuencia guardada es 'unico'. Si DO nunca la fijó (NULL), el estudio
--     sigue 'sin_calendario' antes y después, y el contador rojo no baja. PUEDE SER
--     EL CASO REAL de Sandra Ramírez: no se sabe cuál es su frecuencia guardada
--     hasta mirar producción (consulta de residuo, abajo). Si es NULL, un clic de
--     DO lo resuelve: abrir el estudio, elegir «Pago único» y guardar con la fecha
--     VACÍA (medido con las funciones reales: pasa a 'al_dia' y el contador baja).
--     Ojo: guardarlo con la fecha de hoy que muestra el formulario también queda
--     'al_dia' desde esta migración, pero SIN ella lo empeoraba (pedía constancia
--     de un pago ya sustentado).
--   · MENSUAL, por CICLO y OTRA con «último pago». Una constancia aprobada con
--     «último pago» deja NULL y el estudio sigue 'sin_calendario' (la prueba lo
--     fija a propósito, M7–M9). Su NULL sigue siendo ambiguo entre «nadie dijo
--     cuándo» y «ya no hay más pagos»; arreglarlo pide un dato nuevo (una columna
--     `es_ultimo_pago`) que no es de esta migración. DECISIÓN ABIERTA.
--   · PAGO ÚNICO CON FECHA FUTURA. Un pago único con constancia aprobada Y una
--     `proxima_fecha_pago` posterior a hoy queda callado: antes pedía la constancia
--     de esa fecha cuando llegaba su plazo, ahora no la pide nunca (en el barrido,
--     33 de los 72 estudios que cambian son de esta clase: pasan de 'al_dia' a
--     'al_dia' perdiendo la fecha y el plazo). Es un falso negativo de ALERTA, no
--     de plata. Es lo decidido —el comprobante inicial de un alta de pago único
--     cuenta como prueba del pago— pero FELIPE tiene que confirmarlo: si ese
--     comprobante puede ser una proforma ANTES de pagar, la regla correcta es
--     callar solo cuando la fecha guardada ya llegó (`proxima_fecha_pago <= hoy`)
--     y dejar que una fecha futura siga pidiendo.
--   · Un pago único con constancia aprobada Y otra rechazada más reciente figura
--     'rechazada': es lo que DO tiene que ver (la rama va después de rechazada, por
--     lo decidido).
--   · Si DO fija a mano una próxima fecha en un pago único ya sustentado porque
--     espera un SEGUNDO pago, esa fecha no vuelve a pedir nada: un pago único es
--     uno. Para un segundo pago, cambiar la frecuencia a «Otra» o «Mensual».
--
-- QUÉ ASUME
--   · La 0450 (`fn_educacion_situacion`, familia, entregas) y que `apr.n` ya cuenta
--     las constancias aprobadas de la familia.
--   · Misma firma y mismas columnas que la 0450: `create or replace` conserva los
--     permisos y quien la llama (`fn_educacion_por_atender`, la Bandeja) no se
--     entera. No hay `drop function`.
--   · `fn_educacion_por_atender` (0461) cuenta 'vencida' y 'sin_calendario', no
--     'al_dia': un pago único sustentado sale solo del número rojo, sin tocarla.
--     La regla de QUIÉN cuenta sigue viviendo en la base (ADR 0003, decisión 8).
--
-- ORDEN CON LA 0526 (importante: es la forma exacta del accidente de la 0261)
--   La 0526 (borrador SIN PEGAR en la rama claude/agitated-nightingale-7e118e,
--   «la constancia mensual se pide desde el día 1») reescribe LA MISMA función
--   partiendo del MISMO cuerpo de la 0450, y NO tiene ninguna guardia ejecutable
--   (su md5 de partida es solo un comentario). Si las dos se pegan tal cual, la que
--   va DESPUÉS revierte a la otra sin ningún error.
--   · RECOMENDADO: la 0549 PRIMERO. Resuelve el contador rojo de hoy, y la 0526 viaja
--     con su propio frontend y su propia novedad, así que no hay por qué atarlas en
--     una sola migración. Después la 0526 se REHACE sobre el cuerpo que deja esta
--     (sus tres bloques «CAMBIO 0526» se aplican encima de los míos) y lleva SU
--     PROPIA guardia por md5, que acepte solo el cuerpo de la 0549 de abajo (md5
--     de llegada). La fusión de tres vías 0450 / 0549 / 0526 se midió el 2026-10-25
--     y dio 0 conflictos: los cuatro bloques de esta migración no tocan el CTE `par`
--     ni el lateral `mes` de la 0526. Sobre el cuerpo fusionado, la prueba 420 de
--     la 0526 da 45/45 y la 441 de esta, 29/29.
--   · SI LA 0526 SE PEGA PRIMERO, ESTA MIGRACIÓN PARA (la guardia no reconoce su
--     cuerpo: ni con comentarios ni sin ellos) y hay que rehacerla sobre el cuerpo
--     que dejó la 0526: aplicar los cuatro bloques «CAMBIO 0549» a ese cuerpo y
--     medir su md5 nuevo.
--   · EL ORDEN PELIGROSO es 0549 y luego la 0526 TAL COMO ESTÁ: la 0526 no PARA, la
--     función queda de 6 112 caracteres sin el marcador «CAMBIO 0549», y
--     `migraciones_aplicadas` sigue diciendo que la 549 está pegada. No es de esta
--     migración arreglarlo (la 0526 es de otra rama y no se edita aquí). Se
--     reconoce así: `position('CAMBIO 0549' in prosrc) = 0` con la 549 registrada
--     —y la prueba 441 se pone roja—. Quien pegue la segunda, mide antes
--     `length(prosrc)` y `position('CAMBIO 05' in prosrc)`: tienen que aparecer los
--     marcadores de las DOS migraciones.
--
-- LA GUARDIA (sección 0), POR QUÉ ES UNA LISTA BLANCA DE MD5 Y NO UN MARCADOR
--   La primera versión PARABA si veía el texto «CAMBIO» de otra migración, y se
--   saltaba de tres maneras, todas medidas el 2026-10-25: (a) repegar la 0549 con la
--   549 ya registrada salía antes de mirar nada y revertía lo que hubiera encima;
--   (b) la 0526 pegada SIN comentarios no trae el texto «CAMBIO» y pasaba (el 49 %
--   de las funciones de producción no tienen comentarios, ver CLAUDE.md); (c) un
--   cliente que ejecuta sentencia por sentencia dejaba correr el `create or replace`
--   y el registro después del error. Ahora: solo se reescribe sobre un cuerpo
--   conocido por md5 —la 0450 o esta misma—, midiendo con los retornos de carro
--   quitados (pegar desde Windows mete un `\r` por línea y no cambia el
--   comportamiento), y todo el archivo va en `begin … commit`. Comprobado en un
--   Postgres 17 desechable: la 0450 pasa; la 0450 con `\r\n` pasa; la 0549
--   repegada pasa; la 0526, la 0526 sin comentarios, la 0549 seguida de la 0526
--   con la 549 registrada, y una fusión de las dos PARAN con el mensaje claro y
--   sin dejar nada a medias (ni con ON_ERROR_STOP ni sentencia por sentencia).
--   No se probó en el SQL Editor real de Supabase.
--
-- DE QUÉ VERSIÓN PARTE
--   De la 0450, extraída del archivo y parcheada con un script, no retipeada a
--   mano: el resto del cuerpo es byte por byte lo que ya estaba.
--
--   md5 de partida del repositorio (la 0450, 4 006 caracteres, 0 retornos de carro,
--   tal cual = sin comentarios porque el cuerpo no trae `--`):
--     f0ddaf5bdd6a9b998a75a1fcdcaa2ab6
--   md5 de partida de PRODUCCIÓN: PENDIENTE de confirmar contra producción antes
--   de pegar. Solo Felipe lo obtiene, en el SQL Editor, con:
--
--     select length(prosrc) as largo,
--            md5(prosrc) as tal_cual,
--            md5(regexp_replace(prosrc, '--[^\n]*', '', 'g')) as sin_comentarios,
--            length(prosrc) - length(replace(prosrc, chr(13), '')) as retornos,
--            position('CAMBIO' in prosrc) as marcadores
--       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'fn_educacion_situacion';
--
--   (`./scripts/donde-vive.sh fn_educacion_situacion` imprime esa consulta y los
--   desenlaces.) Esperado si producción sigue en la 0450: largo 4006, retornos 0,
--   marcadores 0. Otra rama midió ese mismo md5 en producción el 2026-10-17; es
--   un dato viejo y de otra sesión: un md5 es una foto y caduca, se vuelve a pedir
--   en el mensaje en que se entrega el SQL.
--
--   md5 de llegada, medido aplicando este archivo (con el número 0549 ya
--   definitivo y el cuerpo FINAL) sobre las migraciones 0001–0544 en un
--   Postgres 17.10 desechable, no en la imagen de Supabase:
--     tal_cual            faba3345a7f7d9231832559c4d4feab5   · 4 959 caracteres
--     sin comentarios     2b4fba7e220d89ab96c8cf5885fbeaf1
--     position('CAMBIO 0549' in prosrc) = 1320 · 0 retornos de carro
--   Este md5 es el segundo de la lista blanca de la sección 0 (el que deja repegar
--   la migración). SI SE RENUMERA, o si se toca el cuerpo de la función, hay que
--   volver a MEDIRLO después del cambio y actualizar la sección 0: los marcadores
--   «CAMBIO 0549» cambian el md5 y NO el largo (misma longitud, distinto hash).
--   Si producción da otro con la misma longitud, mira `position('CAMBIO 0549' in
--   prosrc)`; si la diferencia es el número de líneas, es el `\r` de pegar desde
--   Windows y no hay nada roto (ver CLAUDE.md): la guardia ya lo normaliza.
--
-- CÓMO SE VERIFICA DESPUÉS DE PEGAR
--   select length(prosrc), md5(prosrc), position('CAMBIO 0549' in prosrc)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_educacion_situacion';
--   y que `migraciones_aplicadas` traiga numero 549 CON su nombre. Se esperan largo
--   4959, md5 faba3345a7f7d9231832559c4d4feab5 (5 061 si se pegó desde Windows, con
--   102 retornos) y posición 1320.
--   Con la 0526 también pegada, `position('CAMBIO 0526' in prosrc)` debe ser > 0.
--
-- CÓMO SE REVIERTE
--   Volver a pegar `fn_educacion_situacion` tal como la dejó la 0450 (líneas
--   1015–1141 de esa migración, sin el `drop function`) o la versión fusionada con
--   la 0526 sin los cuatro bloques «CAMBIO 0549». No hay cambio de esquema ni de
--   datos.
--
-- ANTES DE PEGAR: DOS CONSULTAS DE SOLO LECTURA (para el SQL Editor)
--   Van directo a las tablas, sin `fn_es_admin_o_lider` (en el SQL Editor esa
--   función no es verdadera y `fn_educacion_situacion` devolvería cero filas).
--   Se contrastaron contra `fn_educacion_situacion` sobre 1 080 estudios sembrados
--   (4 vigencias × 5 frecuencias × 6 fechas × 9 combinaciones de constancias): 0
--   discrepancias con el estado real de hoy y 0 con el de esta migración.
--
--   (1) IMPACTO · qué estudios cambian de estado. Las filas con
--   `cuenta_hoy_en_el_menu` verdadero y `cuenta_con_0549` falso son las que SALEN
--   del número rojo. En el barrido: 39 cambian de estado, 24 salen del contador
--   (la cuenta del menú baja de 440 a 416 en total).
--
--     -- SOLO LECTURA. Qué estudios cambiarían de estado con la 0549 (solo pago único con constancia aprobada).
--     -- 'cuenta_*_en_el_menu' replica fn_educacion_por_atender: vencida (cualquier vigencia) o sin_calendario vigente/por terminar.
--     -- Va directo a las tablas (no por fn_educacion_situacion, que en el SQL Editor
--     -- no ve filas porque fn_es_admin_o_lider() no es verdadero).
--     with par as (
--       select fn_hoy_lima() as hoy,
--              fn_educacion_parametro('educacion_dias_aviso_colaboradora', 7) as av_col
--     ),
--     fam as (
--       select distinct on (a.familia_id)
--              a.*, min(a.vigente_desde) over (partition by a.familia_id) as desde_familia
--         from asignaciones_educacion a
--        order by a.familia_id, a.vigente_desde desc, a.id desc
--     ),
--     x as (
--       select f.familia_id, f.persona_id, f.institucion, f.frecuencia_pago, f.proxima_fecha_pago,
--              f.vigente_hasta, f.desde_familia, par.hoy, par.av_col,
--              exists (select 1 from educacion_entregas e join asignaciones_educacion s on s.id = e.asignacion_id
--                       where s.familia_id = f.familia_id and e.estado = 'pendiente') as hay_pendiente,
--              (select e.estado from educacion_entregas e join asignaciones_educacion s on s.id = e.asignacion_id
--                where s.familia_id = f.familia_id and e.estado <> 'retirada'
--                order by e.fecha_pago desc, e.enviada_at desc, e.id desc limit 1) as ultima,
--              (select count(*) from educacion_entregas e join asignaciones_educacion s on s.id = e.asignacion_id
--                where s.familia_id = f.familia_id and e.estado = 'aprobada') as aprobadas
--         from fam f cross join par
--     ),
--     y as (
--       select x.*,
--         case when x.hay_pendiente then 'pendiente_revision'
--              when x.ultima = 'rechazada' then 'rechazada'
--              when x.proxima_fecha_pago is null then 'sin_calendario'
--              when x.proxima_fecha_pago > x.hoy or x.proxima_fecha_pago > x.vigente_hasta then 'al_dia'
--              when fn_educacion_plazo(x.proxima_fecha_pago) < x.hoy then 'vencida'
--              when fn_educacion_plazo(x.proxima_fecha_pago) - x.hoy <= x.av_col then 'por_vencer'
--              else 'falta_enviar' end as estado_hoy,
--         case when x.hay_pendiente then 'pendiente_revision'
--              when x.ultima = 'rechazada' then 'rechazada'
--              when x.frecuencia_pago = 'unico' and x.aprobadas > 0 then 'al_dia'
--              when x.proxima_fecha_pago is null then 'sin_calendario'
--              when x.proxima_fecha_pago > x.hoy or x.proxima_fecha_pago > x.vigente_hasta then 'al_dia'
--              when fn_educacion_plazo(x.proxima_fecha_pago) < x.hoy then 'vencida'
--              when fn_educacion_plazo(x.proxima_fecha_pago) - x.hoy <= x.av_col then 'por_vencer'
--              else 'falta_enviar' end as estado_con_0549,
--         case when x.desde_familia > x.hoy then 'futura'
--              when x.vigente_hasta < x.hoy then 'terminada'
--              when x.vigente_hasta <= x.hoy + 30 then 'por_terminar'
--              else 'vigente' end as vigencia
--       from x
--     )
--     select p.nombres || ' ' || p.apellidos as persona, y.institucion, y.vigencia,
--            y.proxima_fecha_pago as fecha_guardada, y.aprobadas,
--            y.estado_hoy, y.estado_con_0549,
--            (y.estado_hoy = 'vencida' or (y.estado_hoy = 'sin_calendario' and y.vigencia in ('vigente','por_terminar'))) as cuenta_hoy_en_el_menu,
--            (y.estado_con_0549 = 'vencida' or (y.estado_con_0549 = 'sin_calendario' and y.vigencia in ('vigente','por_terminar'))) as cuenta_con_0549
--       from y join personas p on p.id = y.persona_id
--      where y.estado_hoy <> y.estado_con_0549
--      order by cuenta_hoy_en_el_menu desc, p.apellidos, p.nombres, y.institucion;
--
--   (2) RESIDUO · lo que la 0549 NO resuelve: estudios que seguirán pidiendo
--   calendario por frecuencia en blanco o mensual/ciclo/otra con constancia
--   aprobada. Si la fila `unico` da 0 y la de «(sin decir)» da algo, ahí puede estar
--   el caso de Sandra y se resuelve con un clic de DO (ver «Lo que no arregla»).
--
--     -- SOLO LECTURA. Qué estudios cambiarían de estado con la 0549 (solo pago único con constancia aprobada).
--     -- 'cuenta_*_en_el_menu' replica fn_educacion_por_atender: vencida (cualquier vigencia) o sin_calendario vigente/por terminar.
--     -- Va directo a las tablas (no por fn_educacion_situacion, que en el SQL Editor
--     -- no ve filas porque fn_es_admin_o_lider() no es verdadero).
--     with par as (
--       select fn_hoy_lima() as hoy,
--              fn_educacion_parametro('educacion_dias_aviso_colaboradora', 7) as av_col
--     ),
--     fam as (
--       select distinct on (a.familia_id)
--              a.*, min(a.vigente_desde) over (partition by a.familia_id) as desde_familia
--         from asignaciones_educacion a
--        order by a.familia_id, a.vigente_desde desc, a.id desc
--     ),
--     x as (
--       select f.familia_id, f.persona_id, f.institucion, f.frecuencia_pago, f.proxima_fecha_pago,
--              f.vigente_hasta, f.desde_familia, par.hoy, par.av_col,
--              exists (select 1 from educacion_entregas e join asignaciones_educacion s on s.id = e.asignacion_id
--                       where s.familia_id = f.familia_id and e.estado = 'pendiente') as hay_pendiente,
--              (select e.estado from educacion_entregas e join asignaciones_educacion s on s.id = e.asignacion_id
--                where s.familia_id = f.familia_id and e.estado <> 'retirada'
--                order by e.fecha_pago desc, e.enviada_at desc, e.id desc limit 1) as ultima,
--              (select count(*) from educacion_entregas e join asignaciones_educacion s on s.id = e.asignacion_id
--                where s.familia_id = f.familia_id and e.estado = 'aprobada') as aprobadas
--         from fam f cross join par
--     ),
--     y as (
--       select x.*,
--         case when x.hay_pendiente then 'pendiente_revision'
--              when x.ultima = 'rechazada' then 'rechazada'
--              when x.proxima_fecha_pago is null then 'sin_calendario'
--              when x.proxima_fecha_pago > x.hoy or x.proxima_fecha_pago > x.vigente_hasta then 'al_dia'
--              when fn_educacion_plazo(x.proxima_fecha_pago) < x.hoy then 'vencida'
--              when fn_educacion_plazo(x.proxima_fecha_pago) - x.hoy <= x.av_col then 'por_vencer'
--              else 'falta_enviar' end as estado_hoy,
--         case when x.hay_pendiente then 'pendiente_revision'
--              when x.ultima = 'rechazada' then 'rechazada'
--              when x.frecuencia_pago = 'unico' and x.aprobadas > 0 then 'al_dia'
--              when x.proxima_fecha_pago is null then 'sin_calendario'
--              when x.proxima_fecha_pago > x.hoy or x.proxima_fecha_pago > x.vigente_hasta then 'al_dia'
--              when fn_educacion_plazo(x.proxima_fecha_pago) < x.hoy then 'vencida'
--              when fn_educacion_plazo(x.proxima_fecha_pago) - x.hoy <= x.av_col then 'por_vencer'
--              else 'falta_enviar' end as estado_con_0549,
--         case when x.desde_familia > x.hoy then 'futura'
--              when x.vigente_hasta < x.hoy then 'terminada'
--              when x.vigente_hasta <= x.hoy + 30 then 'por_terminar'
--              else 'vigente' end as vigencia
--       from x
--     )
--     select coalesce(y.frecuencia_pago, '(sin decir)') as frecuencia,
--            count(*) filter (where y.aprobadas > 0) as sin_calendario_con_constancia_aprobada,
--            count(*) filter (where y.aprobadas = 0) as sin_calendario_sin_constancia
--       from y
--      where y.estado_con_0549 = 'sin_calendario' and y.vigencia in ('vigente', 'por_terminar')
--      group by 1 order by 1;
-- ============================================================================


begin;

-- ── 0 · Comprobar ANTES de tocar nada: lista blanca de cuerpos conocidos ────
-- Esta función la reescriben dos migraciones sin pegar. Solo se reescribe sobre un
-- cuerpo CONOCIDO, identificado por md5 y no por un marcador de texto: la 0450 (el
-- de partida) o esta misma migración (repegarla no hace daño). Cualquier otro —la
-- 0526, la 0526 pegada sin comentarios (el 49 % de las funciones de producción no
-- los trae), una fusión— se revertiría en silencio, así que se PARA. El `\r` de
-- pegar desde Windows no cuenta: se quita antes de medir.
-- Repegar la 0549 con la 549 ya registrada NO salta la guardia: si encima se pegó
-- otra cosa, también se para (antes la salvaguarda se apagaba con el registro).
-- Todo el archivo va en begin … commit: si esta guardia falla, no queda ni la
-- función ni el registro a medias, ni siquiera en un cliente que ejecuta sentencia
-- por sentencia.
do $$
declare v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_educacion_situacion';
  if v_src is null then
    raise exception '0549 · PARA. fn_educacion_situacion no existe en esta base: falta la 0450.';
  end if;
  if md5(replace(v_src, chr(13), '')) not in (
       'f0ddaf5bdd6a9b998a75a1fcdcaa2ab6',   -- la 0450 (4 006 caracteres)
       'faba3345a7f7d9231832559c4d4feab5')   -- esta misma 0549 (4 959 caracteres; repegar)
  then
    raise exception '0549 · PARA. fn_educacion_situacion no es un cuerpo que esta migración conozca (largo %, md5 %, marcador CAMBIO en la posición %): pegar esto revertiría lo que tenga. NO se pegó nada. Rehaz la 0549 sobre ese cuerpo (¿la 0526?) y compara con el encabezado.',
      length(v_src), md5(v_src), position('CAMBIO' in v_src);
  end if;
  raise notice '0549 · se reescribe fn_educacion_situacion de largo % y md5 %.', length(v_src), md5(v_src);
end $$;


create or replace function fn_educacion_situacion()
returns table (
  familia_id           uuid,
  asignacion_id        uuid,
  persona_id           uuid,
  persona              text,
  sede                 text,
  rango                text,
  institucion          text,
  beneficiario         text,
  beneficiario_nombre  text,
  monto                numeric,
  vigente_desde        date,
  vigente_hasta        date,
  vigencia             text,
  paga                 boolean,
  frecuencia_pago      text,
  proxima_fecha_pago   date,
  dias_para_pago       int,
  pago_proximo         boolean,
  estado_constancia    text,
  fecha_pago_constancia date,
  plazo                date,
  dias_para_plazo      int,
  entrega_id           uuid,
  entrega_estado       text,
  entrega_enviada_at   timestamptz,
  entrega_archivos     int,
  motivo_categoria     text,
  motivo_comentario    text,
  aprobadas            int,
  aviso_fin_id         uuid,
  aviso_fin_motivo     text
)
language sql
stable
security definer
set search_path = public
as $$
  with par as (
    select fn_hoy_lima() as hoy,
           fn_educacion_parametro('educacion_dias_aviso_colaboradora', 7) as av_col,
           fn_educacion_parametro('educacion_dias_aviso_do', 7)           as av_do
  ),
  fam as (
    select distinct on (a.familia_id)
           a.*, min(a.vigente_desde) over (partition by a.familia_id) as desde_familia
      from asignaciones_educacion a
     where fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id()
     order by a.familia_id, a.vigente_desde desc, a.id desc
  )
  select
    f.familia_id, f.id, f.persona_id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    f.institucion, f.beneficiario, f.beneficiario_nombre, f.monto,
    f.desde_familia, f.vigente_hasta,
    case when f.desde_familia > par.hoy          then 'futura'
         when f.vigente_hasta < par.hoy          then 'terminada'
         when f.vigente_hasta <= par.hoy + 30    then 'por_terminar'
         else 'vigente' end,
    (f.comprobante_url is not null and f.vigente_hasta >= par.hoy),
    f.frecuencia_pago, f.proxima_fecha_pago,
    (f.proxima_fecha_pago - par.hoy)::int,
    coalesce(f.proxima_fecha_pago between par.hoy and par.hoy + par.av_do
             and f.proxima_fecha_pago <= f.vigente_hasta
             -- CAMBIO 0549: se apaga solo cuando el estado es el 'al_dia' de la rama nueva;
             -- con una constancia pendiente o rechazada DO sigue viendo «pago en camino».
             and not (uni.sustentado and pe.id is null
                      and ul.estado is distinct from 'rechazada'), false),
    est.estado,
    est.fecha,
    fn_educacion_plazo(est.fecha),
    (fn_educacion_plazo(est.fecha) - par.hoy)::int,
    ul.id, ul.estado, ul.enviada_at, ul.archivos, ul.motivo_categoria, ul.motivo_comentario,
    apr.n,
    av.id, av.motivo
  from fam f
  cross join par
  join personas p on p.id = f.persona_id
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select x.rango from asignaciones_salario x
     where x.persona_id = f.persona_id and x.vigente_hasta is null
     order by x.vigente_desde desc, x.id desc limit 1
  ) sal on true
  left join lateral (
    select e.id, e.fecha_pago
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado = 'pendiente'
     order by e.enviada_at desc, e.id desc limit 1
  ) pe on true
  left join lateral (
    select e.id, e.estado, e.fecha_pago, e.enviada_at, e.motivo_categoria, e.motivo_comentario,
           (select count(*)::int from educacion_entrega_archivos ar where ar.entrega_id = e.id) as archivos
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado <> 'retirada'
     order by e.fecha_pago desc, e.enviada_at desc, e.id desc limit 1
  ) ul on true
  left join lateral (
    select count(*)::int as n
      from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
     where x.familia_id = f.familia_id and e.estado = 'aprobada'
  ) apr on true
  -- ⇩ CAMBIO 0549 ⇩ ¿Es un estudio de PAGO ÚNICO cuyo único pago ya está sustentado?
  -- Sí, si la frecuencia es 'unico' y la familia tiene una constancia APROBADA. Se
  -- deriva en vivo, sin guardar marca: si DO revierte la aprobación (0525), `apr.n`
  -- baja y el estudio vuelve solo a la escalera de siempre. `is true`: una
  -- frecuencia sin decir (null) no es 'unico'.
  cross join lateral (
    select (f.frecuencia_pago = 'unico' and apr.n > 0) is true as sustentado
  ) uni
  left join lateral (
    select v.id, v.motivo
      from educacion_avisos_fin v join asignaciones_educacion x on x.id = v.asignacion_id
     where x.familia_id = f.familia_id and v.atendido_at is null
     order by v.creado_at desc, v.id desc limit 1
  ) av on true
  cross join lateral (
    select
      case
        when pe.id is not null                                   then 'pendiente_revision'
        when ul.estado = 'rechazada'                             then 'rechazada'
        when uni.sustentado                                      then 'al_dia'   -- CAMBIO 0549
        when f.proxima_fecha_pago is null                        then 'sin_calendario'
        when f.proxima_fecha_pago > par.hoy
          or f.proxima_fecha_pago > f.vigente_hasta              then 'al_dia'
        when fn_educacion_plazo(f.proxima_fecha_pago) < par.hoy  then 'vencida'
        when fn_educacion_plazo(f.proxima_fecha_pago) - par.hoy <= par.av_col then 'por_vencer'
        else 'falta_enviar'
      end as estado,
      case
        when pe.id is not null        then pe.fecha_pago
        when ul.estado = 'rechazada'  then ul.fecha_pago
        when uni.sustentado           then null   -- CAMBIO 0549
        else f.proxima_fecha_pago
      end as fecha
  ) est
  order by p.apellidos, p.nombres, f.institucion, f.familia_id;
$$;


-- Misma firma que la 0450: `create or replace` conserva el permiso; se repite
-- porque pegar a mano no debe depender de lo que haya quedado de antes.
grant execute on function fn_educacion_situacion() to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (549, 'un_pago_unico_ya_sustentado_no_pide_calendario')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

commit;
