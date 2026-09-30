-- ============================================================================
-- 0501 — La RMV sube a S/ 1,230 el 2026-10-01, la escala la sigue y la
--        asignación familiar sube a S/ 123
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que desde el 2026-10-01 —y solo desde ahí— el sistema pague y lea la
--   escala nueva, y que todo lo anterior a esa fecha siga leyendo la vieja:
--
--     · RMV                      S/ 1,130 → S/ 1,230   (parametros_laborales)
--     · asignación familiar      S/   113 → S/   123   (parametros_laborales
--                                                       y configuracion)
--     · base declarada colibrí   S/ 1,130 → S/ 1,230   (sueldo y base legal)
--     · base declarada cayla     S/ 1,185 → S/ 1,245   (sueldo y base legal)
--     · lo que publica la Política salarial (categorias_laborales) → lo mismo
--     · DEFAULT de personas.sueldo_base_legal: 1,130 → 1,230 (altas futuras)
--
--   Support (S/ 1,260), aurora (1,360), oráculo (1,440) y archicaylo (1,500) NO
--   se tocan: ni un tramo nuevo, ni una base. Y la migración SOLO SUBE: nadie
--   cobra menos después de pegarla que antes.
--
--   Todo en UNA transacción (begin … commit) y con una guardia al final que
--   aborta en voz alta si algo no quedó como se prometió. O queda todo o no
--   queda nada.
--
-- QUÉ ASUME
--
--   · La norma: D.S. 015-2026-TR, publicado el 2026-09-28 en El Peruano
--     (edición extraordinaria), art. 1. La RMV sube en dos tramos hasta
--     S/ 1,300: el primero (+S/ 100 = S/ 1,230) rige desde el 2026-10-01; el
--     segundo (+S/ 70) lo fijará OTRO decreto supremo «durante el primer
--     semestre de 2027». Ese segundo tramo NO está sembrado acá: no tiene
--     fecha ni monto publicado más allá del decreto.
--   · Que `parametros_laborales` (0116) y su índice único REAL —
--     `(clave, coalesce(sede_codigo,''), vigente_desde)`, el que dejó la 0142—
--     existen. El `on conflict` de abajo apunta a ese, no al de la 0116 (que la
--     0142 borró): usar el viejo hace fallar el insert DESPUÉS de haber cerrado
--     la fila vieja, y sin fila vigente el piso de EsSalud se lee como cero.
--   · Que existe al menos un admin activo con usuario (`auth_user_id`), porque
--     `fn_fijar_base_declarada` exige sesión de administrador y el SQL Editor
--     no la trae. Se PRESTA la identidad del admin activo más antiguo (mismo
--     criterio que la 0176 y la 0462) solo durante esta transacción; el guard
--     de las funciones NO se debilita ni se toca. Si no hay ninguno y hay a
--     quién subirle el sueldo, se detiene sin tocar nada.
--   · Que el periodo 2026-09-29 → 2026-10-28 sigue ABIERTO al pegarla (el
--     candado de periodo pagado de `fn_set_salario` se negaría si no).
--
-- POR QUÉ ASÍ
--
--   1 · La RMV se VERSIONA: se abre una fila nueva y se cierra la vieja; nunca
--       se edita el valor, porque editarlo reescribiría los periodos ya
--       pagados. Se abre PRIMERO y se cierra DESPUÉS: si el orden fuera el
--       inverso y el insert fallara, el periodo que cierra el 28-oct no
--       encontraría ninguna RMV y `fn_planilla_calcular` la leería como 0 (el
--       piso de EsSalud saldría en cero, sin error). Con este orden, aun a
--       medias, siempre hay una fila vigente.
--   2 · Los sueldos suben desde el 2026-10-01 y NO desde el 2026-09-29 (inicio
--       del periodo). La planilla paga POR DÍA y cada jornada usa el tramo que
--       la contiene, así que el 29 y el 30 de septiembre se pagan al sueldo
--       viejo. La RMV nueva rige desde el 1-oct por decreto: pagar dos días de
--       septiembre a la escala nueva sería regalarlos, y ninguna norma lo pide.
--       La pensión sigue igual de exacta: la básica declarada es
--       least(sueldo_base_legal, tramo del día), y para el 29 y 30 de septiembre
--       el tramo es el viejo. (`personas.sueldo_base_legal` no tiene fecha; se
--       sube hoy, el 1-oct, y ninguna jornada anterior lo nota por ese least.)
--   3 · La escala es «la más barata que mantiene el orden»: colibrí a la RMV
--       (1,230), cayla a 1,245 (un escalón de S/ 15 sobre colibrí) y support se
--       queda en 1,260 porque YA cumple la RMV. La educación NO se sube ni se
--       iguala «para compensar»: la base cumple sola. La cobertura de estudios
--       llega a S/ 270 al mes y la Política publica una «Referencia mensual» =
--       remuneración + movilidad (hasta S/ 288) + estudios; esa referencia es lo
--       que separa a los rangos, no la base declarada.
--       Alternativa descartada por ahora: cayla también en 1,230 (el mínimo
--       absoluto de ley). Ahorra S/ 75.40 al mes con cuatro cayla, pero deja a
--       colibrí y cayla con la MISMA base. Si Felipe la prefiere, es cambiar UN
--       número (v_montos, abajo) y el `salario_declarado` de cayla.
--   4 · Los sueldos pasan por `fn_fijar_base_declarada` (0128) y no por un
--       UPDATE: esa función escribe los DOS campos que intervienen en el pago
--       (`asignaciones_salario.salario_mensual_soles` paga y
--       `personas.sueldo_base_legal` declara) y versiona el tramo. Subir solo el
--       tramo dejaría la pensión declarándose sobre 1,130.
--   5 · La Política salarial se mueve en la MISMA transacción. Lo que publica
--       (tablas de escala y de «Referencia mensual») sale de
--       `categorias_laborales.salario_declarado`, no de los tramos. Si esta
--       migración pagara 1,230 y la Política siguiera diciendo 1,130, el papel
--       entregado al equipo contradiría la planilla. Es UPDATE directo de esa
--       columna (como la 0145) y NO `fn_set_categoria`: esa reescribe también
--       propósito, funciones, requisitos y criterio, y pasarle de vuelta los
--       textos actuales los recorta (btrim/nullif) — no se toca lo que la
--       migración no viene a cambiar. Desde este momento /admin/politica-salarial
--       mostrará «cambios sin publicar» (`documentoTieneCambios`) hasta que se
--       publique la versión nueva: es lo esperado y es lo que hay que hacer
--       mañana (ver CÓMO Y CUÁNDO SE PEGA).
--
-- LAS DOS VERDADES DE LA ASIGNACIÓN FAMILIAR (y por qué se actualizan las dos)
--
--   Medido contra las 480 migraciones en una base desechable: la asignación se
--   lee de DOS sitios.
--     · `parametros_laborales` (versionada, 0122): la leen el núcleo de la
--       planilla (al ÚLTIMO día del periodo) y `fn_provisiones` (día por día).
--     · `configuracion.asignacion_familiar` (0113, SIN fechas): es el RESPALDO
--       de esas dos y la ÚNICA fuente de `fn_remuneracion_computable`, de la que
--       cuelgan las liquidaciones por cese (fn_grati_trunca, fn_cts_trunca,
--       fn_vacaciones_truncas).
--   Subir solo la versionada dejaba a la boleta del mes diciendo 123 y a la
--   liquidación de quien cesa diciendo 113: dos números para la misma persona, y
--   el error siempre en contra de quien se va. Reescribir
--   `fn_remuneracion_computable` para que lea por fecha queda fuera de esta
--   migración (regla de la casa: no se reescribe una función por arrastre). Por
--   eso se elige la opción SEGURA: subir también `configuracion` a 123.
--     · Qué recalcula: solo lo NO pagado. `liquidacion_pagada` congela el total
--       al pagar (fn_liquidacion_pagar), así que ninguna liquidación ya pagada
--       cambia. Las pendientes se recalculan con 123 al abrirlas.
--     · Qué error deja, y en qué sentido: una liquidación cuya fecha de
--       referencia sea anterior al 2026-10-01 (un cese de octubre mira el mes
--       anterior) y se calcule con 123 en vez de 113 paga unos céntimos de más
--       —a favor de quien se va y acotado a esa ventana—; lo contrario, dejar
--       113, pagaba de menos a todo cese desde noviembre, sin límite.
--     · DEUDA que queda y se anota en estado.md: `fn_remuneracion_computable`
--       sigue leyendo sin fecha; la solución de fondo es que lea
--       `parametros_laborales` a p_fecha_ref, y es una migración propia.
--     · Los `coalesce(…, 113.00)` de respaldo escritos DENTRO de las funciones
--       (núcleo, fn_provisiones y fn_remuneracion_computable) no se tocan: solo
--       se usan si faltan las DOS tablas, y no faltan.
--
-- ⚠️ LA ASIGNACIÓN FAMILIAR NO SE PUEDE BAJAR DESPUÉS
--
--   Decidido por Felipe el 2026-09-30, «por ley» (10 % de la RMV, Ley 25129
--   art. 1), sabiendo que la nota de la 0122 sostiene que la pequeña empresa no
--   la tiene entre sus derechos. Una vez que un periodo se calcula y se paga
--   con 123, volver a 113 es una reducción unilateral de remuneración (art. 30
--   inc. b del D.S. 003-97-TR). Es la única parte de esta migración que no se
--   deshace: ver CÓMO SE REVIERTE.
--   Cuesta ~S/ 12.57 al mes por cada integrante que la cobra (S/ 10 de pago,
--   más EsSalud, gratificación y su bonificación, CTS y vacaciones, porque es
--   remuneración computable). Cuántos la cobran lo sabe la consulta (iv) de
--   `scripts/sql-manual/antes_de_pegar_la_rmv_1230.sql`.
--
-- LO QUE MUEVE EN PLATA
--
--   · Sueldos, a jornada completa y a régimen estable (30 días): colibrí +S/ 100
--     × 10 integrantes y cayla +S/ 60 × 4 → S/ 1,240 de sueldo, ≈ S/ 1,558.31 al
--     mes con EsSalud 9 %, gratificación 8.33 %, CTS 4.17 % y vacaciones 4.17 %
--     (factor 1.2567). ≈ S/ 18,700 al año. Es el mismo cálculo de referencia que
--     el resto de la casa; el número real sale de fn_simular_planilla.
--   · Referencias: cayla en 1,230 (el mínimo absoluto) costaría S/ 1,482.91; la
--     escala descartada 1,230 / 1,260 / 1,290 (support también sube), S/ 1,671.41.
--   · El primer periodo con el sueldo nuevo (29-sep → 28-oct, 30 días) paga 2 días
--     al viejo y 28 al nuevo: un colibrí con asistencia completa cobra
--     ≈ S/ 1,223.33 (2/30 × 1,130 + 28/30 × 1,230) y una cayla ≈ S/ 1,241.00.
--     ⚠️ PUEDE LEERSE COMO «MENOS QUE LA RMV» y NO LO ES: son dos días de
--     septiembre al sueldo de septiembre. Desde el periodo siguiente cobran el
--     sueldo completo. Conviene tener esta explicación a mano el día de pago.
--   · EsSalud: el piso se lee a la RMV del ÚLTIMO día del periodo, así que el
--     periodo que cierra el 28-oct usa S/ 1,230 completo —incluidos el 29 y 30
--     de septiembre—: 9 % × 1,230 = S/ 110.70 (antes S/ 101.70).
--   · El techo de la movilidad (4 % de la RMV, 0152) sube solo de S/ 45.20 a
--     S/ 49.20 para tarifas nuevas; las tarifas vigentes (S/ 10 a S/ 12) no se
--     acercan y las filas existentes no se revalidan.
--   · Contratos lee la RMV «hoy» para el piso de la subvención de prácticas (Ley
--     28518, art. 45): desde el 1-oct exige 1,230 (o su proporción a las horas
--     pactadas) para generar un convenio nuevo.
--
-- CÓMO Y CUÁNDO SE PEGA
--
--   MAÑANA, 2026-10-01 —no la noche del 30—, y SIEMPRE ANTES de fusionar el PR
--   que la acompaña. Las razones son dos y las dos ya costaron caro:
--     1 · La pantalla de Contratos leía la RMV con `vigente_hasta is null`
--         (ese código se corrige en el mismo PR): entre pegar y el 1-oct esa
--         pantalla no vería ninguna RMV vigente, y el convenio de prácticas
--         saldría con «[FALTA PUBLICAR LA RMV VIGENTE EN EL SISTEMA]».
--     2 · `main` se publica sola: fusionar el PR ES desplegar. Si el frontend
--         llega antes que esta migración, Equipo propone bases (1,230 / 1,245)
--         que el sistema todavía no paga, y la Política se puede publicar con
--         montos que la planilla contradice.
--   Orden exacto, con las consultas de comprobación, en docs/estado.md
--   («Guion de mañana»). El SQL se pide con ./scripts/dame-el-sql.sh 0501, no se
--   abre el archivo. Como no reescribe ninguna función, no hay md5 de partida.
--   Antes de pegar: scripts/sql-manual/antes_de_pegar_la_rmv_1230.sql.
--
-- LO QUE NO HACE
--
--   · NO toca a los PRACTICANTES. `fn_fijar_base_declarada` exige `en_planilla`
--     y un practicante tiene `en_planilla = false`; su subvención pactada bajo
--     1,230 (o su proporción a las horas pactadas) queda bajo el piso de la Ley
--     28518 art. 45 sin que el sistema lo marque. No se les sube a ciegas:
--     quien pactó menos horas tiene piso proporcional. La consulta (ii) del
--     script de comprobación muestra quiénes son, y se resuelve con sus datos.
--     Su EsSalud sí sube solo (piso puro: de S/ 101.70 a S/ 110.70).
--   · NO toca a locadores (RxH), personal de dirección, sueldo fijo ni cuentas
--     de servicio: quien caiga en un caso que la función cambiaría en silencio
--     (base sin confirmar, base de provisión propia, tramo ya programado,
--     sueldo fijo, un campo por encima y otro por debajo) DETIENE la migración
--     con un mensaje en vez de resolverlo por su cuenta.
--   · NO siembra el segundo tramo (S/ 1,300 y asignación de S/ 130): cuando el
--     decreto salga, colibrí, cayla Y support (1,260 < 1,300) volverán a quedar
--     bajo el piso y hay que rehacer esta misma migración con los números de
--     ese día. Nada en el sistema avisa cuando el decreto sale.
--   · NO reescribe ninguna función SQL (ni fn_planilla_calcular ni
--     fn_remuneracion_computable). Ver «LAS DOS VERDADES» para la deuda.
--   · NO publica la Política salarial: publicarla es un clic de Felipe en
--     /admin/politica-salarial porque el documento lo arma el navegador.
--
-- CÓMO SE REVIERTE
--
--   · Solo mientras el periodo 29-sep → 28-oct siga sin pagarse:
--       delete from parametros_laborales
--        where clave in ('rmv','asignacion_familiar') and vigente_desde = '2026-10-01';
--       update parametros_laborales set vigente_hasta = null
--        where clave in ('rmv','asignacion_familiar') and vigente_hasta = '2026-09-30';
--       update configuracion set valor = jsonb_set(valor,'{monto}','113.00')
--        where clave = 'asignacion_familiar';
--       alter table personas alter column sueldo_base_legal set default 1130.00;
--   · Los sueldos: volver a llamar `fn_fijar_base_declarada` con el monto viejo
--     del rango y la MISMA fecha (2026-10-01); deja el mismo dinero de antes (no
--     el mismo historial: queda el tramo viejo cerrado y otro igual abierto).
--     Y `categorias_laborales.salario_declarado` de vuelta a 1130 / 1185.
--   · Después de pagar ese periodo, NADA de esto se revierte sin reducir
--     unilateralmente una remuneración. En especial la asignación familiar.
--
-- ⚠️ SI OTRA MIGRACIÓN YA HIZO PARTE DE ESTO
--
--   La rama claude/salary-update-1230-bd7a09 (sin fusionar ni pegar, al escribir
--   esto) tiene una 0500 con la RMV en 1,230 y la asignación en 123. Esta 0501 no
--   depende de ella y sigue siendo correcta si se pegan las dos, en cualquier
--   orden: el insert usa `on conflict do nothing`, el cierre de la fila vieja no
--   hace nada si ya está cerrada, la asignación y el UPDATE de configuracion
--   solo suben, y la guardia comprueba lo que el sistema lee, no lo que esta
--   migración cree haber escrito.
--
-- IDEMPOTENTE: pegarla dos veces no abre tramos ni filas nuevas y no falla.
-- ============================================================================

begin;

-- ── 1 · RMV: se ABRE la nueva y DESPUÉS se cierra la vieja ──────────────────
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('rmv', 1230.00, date '2026-10-01',
  'Remuneración Mínima Vital: S/ 1,230.00 desde el 2026-10-01, primera etapa del '
  'alza a S/ 1,300 (D.S. 015-2026-TR, publicado el 2026-09-28 en El Peruano, edición '
  'extraordinaria, art. 1). La segunda etapa (+S/ 70) se fijará por otro decreto '
  'supremo durante el primer semestre de 2027 y NO está sembrada. Es la base '
  'imponible MÍNIMA del aporte a EsSalud (Ley 26790 art. 6) y de ella sale el techo '
  'de la movilidad (4 %, 0152). CUANDO SUBA OTRA VEZ: cerrar esta fila con '
  'vigente_hasta y abrir otra; NO editar este valor.')
on conflict (clave, (coalesce(sede_codigo, '')), vigente_desde) do nothing;

update parametros_laborales
   set vigente_hasta = date '2026-09-30'
 where clave = 'rmv'
   and sede_codigo is null
   and vigente_hasta is null
   and vigente_desde < date '2026-10-01';

-- ── 2 · Asignación familiar: 10 % de la RMV, en sus DOS lugares ─────────────
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('asignacion_familiar', 123.00, date '2026-10-01',
  'Asignación familiar: 10 % de la RMV (Ley 25129 art. 1 y D.S. 035-90-TR). Con la '
  'RMV de S/ 1,230 vigente desde el 2026-10-01 (D.S. 015-2026-TR), S/ 123.00. Monto '
  'ÚNICO por trabajador, no por hijo. Es remuneración computable para gratificación, '
  'CTS y vacaciones (art. 3 del D.S. 035-90-TR). Decidida por Felipe el 2026-09-30 '
  '«por ley», sabiendo que la nota de la 0122 sostiene que la pequeña empresa no la '
  'tiene entre sus derechos: una vez subida NO puede bajarse, sería reducción '
  'unilateral de remuneración (art. 30 inc. b, D.S. 003-97-TR). CUANDO SUBA LA RMV: '
  'cerrar esta fila con vigente_hasta y abrir otra, y subir también '
  'configuracion.asignacion_familiar (la lee fn_remuneracion_computable, sin fechas).')
on conflict (clave, (coalesce(sede_codigo, '')), vigente_desde) do nothing;

update parametros_laborales
   set vigente_hasta = date '2026-09-30'
 where clave = 'asignacion_familiar'
   and sede_codigo is null
   and vigente_hasta is null
   and vigente_desde < date '2026-10-01';

-- La segunda verdad (0113): sin fechas, la única que lee fn_remuneracion_computable.
-- Solo sube: si alguien ya la dejó en 123 o más, no se toca.
update configuracion
   set valor = jsonb_set(valor, '{monto}', to_jsonb(123.00::numeric))
 where clave = 'asignacion_familiar'
   and coalesce((valor ->> 'monto')::numeric, 0) < 123.00;

-- ── 3 · El DEFAULT de la base declarada: solo altas futuras ─────────────────
-- No cambia a nadie que ya exista. Quien se cree desde hoy sin fijar su base
-- (fn_crear_persona no la fija) nace en la RMV vigente y no por debajo de ella.
-- Envejece de nuevo con el segundo tramo de la RMV (S/ 1,300).
alter table personas alter column sueldo_base_legal set default 1230.00;

-- ── 4 · Sueldos y Política salarial ─────────────────────────────────────────
do $mig$
declare
  c_desde   constant date      := date '2026-10-01';
  v_rangos  constant text[]    := array['colibri', 'cayla'];
  v_montos  constant numeric[] := array[1230.00, 1245.00];
  v_declar  constant numeric[] := array[1230.00, 1245.00];  -- salario_declarado (Política)

  v_i       int;
  v_rango   text;
  v_monto   numeric;
  v_admin   uuid;
  v_auth    uuid;
  v_antes   jsonb;
  v_omitir_por_rango jsonb := '{}'::jsonb;
  v_omitir  uuid[];
  v_por_tocar int := 0;
  v_tocados uuid[];
  v_todos   uuid[] := '{}';
  v_fila    record;
  v_c       record;
  v_sal_a   numeric;
  v_base_a  numeric;
  v_tramos_a int;
begin
  -- ── 4.0 · La foto de ANTES: sueldo, base y número de tramos de todos ──────
  select coalesce(jsonb_object_agg(x.persona_id::text,
           jsonb_build_object('salario', x.salario, 'base', x.base, 'tramos', x.tramos)),
           '{}'::jsonb)
    into v_antes
    from (select p.id as persona_id,
                 (select a.salario_mensual_soles from asignaciones_salario a
                   where a.persona_id = p.id and a.vigente_hasta is null) as salario,
                 p.sueldo_base_legal as base,
                 (select count(*) from asignaciones_salario a
                   where a.persona_id = p.id) as tramos
            from personas p) x;

  -- ── 4.1 · Quién queda alcanzado, y qué casos frenan la migración ──────────
  -- Alcanzado = tiene ese rango en su tramo ABIERTO, está activo y en planilla
  -- (lo mismo que decide fn_fijar_base_declarada). Se calcula ANTES de llamarla
  -- para poder detenerse ante lo que ella cambiaría en silencio.
  for v_i in 1 .. array_length(v_rangos, 1) loop
    v_rango := v_rangos[v_i];
    v_monto := v_montos[v_i];

    select coalesce(array_agg(z.id) filter (where z.cuenta or z.encima), '{}'::uuid[])
      into v_omitir
      from (select p.id,
                   coalesce(p.cuenta_de_servicio, false) as cuenta,
                   (a.salario_mensual_soles > v_monto
                    or coalesce(p.sueldo_base_legal, 0) > v_monto) as encima
              from personas p
              join asignaciones_salario a
                on a.persona_id = p.id and a.vigente_hasta is null
             where a.rango = v_rango and p.estado = 'activo' and p.en_planilla is true) z;
    v_omitir_por_rango := v_omitir_por_rango
      || jsonb_build_object(v_rango, to_jsonb(v_omitir));

    for v_c in
      select p.id,
             a.salario_mensual_soles as sal,
             p.sueldo_base_legal as base,
             a.base_provision as bp,
             p.sueldo_fijo as sfijo,
             exists (select 1 from asignaciones_salario f
                      where f.persona_id = p.id and f.vigente_desde > c_desde) as futuro,
             (p.id = any (v_omitir)) as omitida
        from personas p
        join asignaciones_salario a
          on a.persona_id = p.id and a.vigente_hasta is null
       where a.rango = v_rango and p.estado = 'activo' and p.en_planilla is true
    loop
      -- Un campo por encima del monto y el otro por debajo: la función bajaría
      -- uno de los dos para igualar. No se resuelve solo.
      if (v_c.sal > v_monto and coalesce(v_c.base, v_monto) < v_monto)
         or (coalesce(v_c.base, 0) > v_monto and v_c.sal < v_monto) then
        raise exception '0501 · rango %: hay un integrante con el sueldo por encima de S/ % y la base declarada por debajo (o al revés). No se toca nada: decidirlo a mano (consulta (i) de scripts/sql-manual/antes_de_pegar_la_rmv_1230.sql).',
          v_rango, v_monto;
      end if;

      if not v_c.omitida and (v_c.sal is distinct from v_monto or v_c.base is distinct from v_monto) then
        v_por_tocar := v_por_tocar + 1;

        if v_c.base is null then
          raise exception '0501 · rango %: hay un integrante en planilla con la base declarada SIN CONFIRMAR (sueldo_base_legal nulo). La función la fijaría y empezaría a declarar pensión donde hoy no hay base. No se toca nada.', v_rango;
        end if;
        if v_c.bp is not null then
          raise exception '0501 · rango %: hay un integrante con base_provision propia en su tramo abierto. fn_set_salario no la copia al tramo nuevo y sus provisiones bajarían en silencio. No se toca nada.', v_rango;
        end if;
        if v_c.sfijo is true then
          raise exception '0501 · rango %: hay un integrante en planilla con sueldo fijo. Su pago no depende de las horas y no se resuelve a ciegas. No se toca nada.', v_rango;
        end if;
        if v_c.futuro then
          raise exception '0501 · rango %: hay un integrante con un tramo de sueldo ya programado DESPUÉS del 2026-10-01. fn_set_salario lo borraría. No se toca nada.', v_rango;
        end if;
      end if;
    end loop;
  end loop;

  -- ── 4.2 · Presta la identidad de un admin (solo si hay a quién subir) ─────
  select p.id, p.auth_user_id into v_admin, v_auth
    from personas p
   where p.rol = 'admin' and p.estado = 'activo' and p.auth_user_id is not null
   order by p.fecha_ingreso nulls last, p.id
   limit 1;

  if v_por_tocar > 0 then
    if v_admin is null then
      raise exception '0501 · hay % integrante(s) a quien subirle el sueldo pero ningún admin activo con usuario que firme el cambio. No se toca nada.', v_por_tocar;
    end if;
    perform set_config('request.jwt.claim.sub', v_auth::text, true);
    if fn_es_admin_o_lider() is not true then
      raise exception '0501 · la identidad prestada no dio sesión de administrador. No se toca nada.';
    end if;
    raise notice '0501 · subiendo % integrante(s); el rastro queda a nombre del admin activo más antiguo.', v_por_tocar;
  else
    raise notice '0501 · no hay ningún sueldo que subir (o ya estaban subidos): solo se aplican la RMV, la asignación y la Política.';
  end if;

  -- ── 4.3 · La base declarada, por rango, SOLO subiendo ─────────────────────
  if v_por_tocar > 0 then
    for v_i in 1 .. array_length(v_rangos, 1) loop
      v_rango := v_rangos[v_i];
      v_monto := v_montos[v_i];
      select coalesce(array_agg(x::uuid), '{}'::uuid[])
        into v_omitir
        from jsonb_array_elements_text(v_omitir_por_rango -> v_rango) x;

      v_tocados := '{}';
      begin
        for v_fila in
          select * from fn_fijar_base_declarada(v_rango, v_monto, c_desde, v_omitir)
        loop
          v_tocados := v_tocados || v_fila.persona_id;
        end loop;
      exception when others then
        raise exception '0501 · se detuvo al subir la base del rango %: %', v_rango, sqlerrm;
      end;

      -- La función deja una nota escrita para BAJAR («El salario baja al monto
      -- declarado…»): en una alza sería lo contrario de la verdad. Se corrige la
      -- nota de los tramos que ella misma abrió; solo cambia esa columna.
      update asignaciones_salario
         set nota = 'Reajuste por la RMV de S/ 1,230 (D.S. 015-2026-TR, en vigor desde el '
                    || '2026-10-01): la base declarada del rango ' || v_rango || ' pasa a S/ '
                    || v_monto::text || ', en el sueldo y en la base legal a la vez (0128). '
                    || 'Migración 0501.'
       where persona_id = any (v_tocados)
         and vigente_desde = c_desde
         and vigente_hasta is null;

      v_todos := v_todos || v_tocados;
    end loop;
  end if;

  -- ── 4.4 · Guardia: nadie baja, nadie más se movió, los tocados quedaron ───
  for v_fila in
    select p.id,
           p.sueldo_base_legal as base,
           a.salario_mensual_soles as sal,
           a.rango,
           (select count(*) from asignaciones_salario x where x.persona_id = p.id) as tramos
      from personas p
      left join asignaciones_salario a
        on a.persona_id = p.id and a.vigente_hasta is null
  loop
    if (v_antes -> v_fila.id::text) is not null then
      v_sal_a    := (v_antes -> v_fila.id::text ->> 'salario')::numeric;
      v_base_a   := (v_antes -> v_fila.id::text ->> 'base')::numeric;
      v_tramos_a := (v_antes -> v_fila.id::text ->> 'tramos')::int;

      if v_fila.sal < v_sal_a or v_fila.base < v_base_a then
        raise exception '0501 · GUARDIA: alguien habría quedado con MENOS sueldo o base que antes. Esta migración solo sube. Se anula todo.';
      end if;

      if not (v_fila.id = any (v_todos)) then
        if v_fila.sal is distinct from v_sal_a
           or v_fila.base is distinct from v_base_a
           or v_fila.tramos is distinct from v_tramos_a then
          raise exception '0501 · GUARDIA: se movió el sueldo, la base o los tramos de alguien que esta migración no debía tocar (support, aurora, oráculo, archicaylo, practicantes, locadores, inactivos u omitidos). Se anula todo.';
        end if;
      else
        v_i := array_position(v_rangos, v_fila.rango);
        if v_i is null or v_fila.sal is distinct from v_montos[v_i]
           or v_fila.base is distinct from v_montos[v_i] then
          raise exception '0501 · GUARDIA: alguien que se reajustó no quedó en el monto de su rango (sueldo % y base %). Se anula todo.', v_fila.sal, v_fila.base;
        end if;
      end if;
    end if;
  end loop;

  -- Y lo que queda debajo de su monto solo puede ser lo que se omitió a propósito.
  for v_i in 1 .. array_length(v_rangos, 1) loop
    select count(*) into v_por_tocar
      from personas p
      join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
     where a.rango = v_rangos[v_i] and p.estado = 'activo' and p.en_planilla is true
       and coalesce(p.cuenta_de_servicio, false) = false
       and (a.salario_mensual_soles < v_montos[v_i]
            or coalesce(p.sueldo_base_legal, v_montos[v_i]) < v_montos[v_i]);
    if v_por_tocar > 0 then
      raise exception '0501 · GUARDIA: quedan % integrante(s) del rango % por debajo de S/ %.', v_por_tocar, v_rangos[v_i], v_montos[v_i];
    end if;
  end loop;

  -- ── 4.5 · La Política salarial: lo que se publica dice lo que se paga ─────
  -- Solo sube (`<`): si alguien ya la dejó más arriba, no se toca. actualizado_por
  -- queda con el admin si hubo uno; si no (base sin personas), se conserva el que estaba.
  for v_i in 1 .. array_length(v_rangos, 1) loop
    update categorias_laborales
       set salario_declarado = v_declar[v_i],
           actualizado_por   = coalesce(v_admin, actualizado_por),
           actualizado_at    = now()
     where rango = v_rangos[v_i]
       and coalesce(salario_declarado, 0) < v_declar[v_i];
  end loop;

  for v_i in 1 .. array_length(v_rangos, 1) loop
    if exists (select 1 from categorias_laborales c
                where c.rango = v_rangos[v_i]
                  and coalesce(c.salario_declarado, 0) < v_declar[v_i]) then
      raise exception '0501 · GUARDIA: la Política salarial dejaría al rango % por debajo de S/ %.', v_rangos[v_i], v_declar[v_i];
    end if;
  end loop;
end
$mig$;

-- ── 5 · Guardia de lo que el SISTEMA LEE (no de lo que esta migración cree) ──
do $mig$
declare
  v_rmv_nueva numeric; v_rmv_vieja numeric; v_rmv_1oct numeric; v_rmv_30sep numeric;
  v_asig_nueva numeric; v_asig_vieja numeric; v_cfg numeric; v_cfg_existe boolean;
begin
  -- Exactamente como lo lee fn_planilla_calcular: la fila vigente AL ÚLTIMO DÍA del periodo.
  select pl.valor into v_rmv_vieja from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null and pl.vigente_desde <= date '2026-09-28'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-28')
   order by pl.vigente_desde desc limit 1;
  select pl.valor into v_rmv_nueva from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null and pl.vigente_desde <= date '2026-10-28'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-28')
   order by pl.vigente_desde desc limit 1;
  select pl.valor into v_rmv_30sep from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null and pl.vigente_desde <= date '2026-09-30'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-30')
   order by pl.vigente_desde desc limit 1;
  select pl.valor into v_rmv_1oct from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null and pl.vigente_desde <= date '2026-10-01'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-01')
   order by pl.vigente_desde desc limit 1;

  select pl.valor into v_asig_vieja from parametros_laborales pl
   where pl.clave = 'asignacion_familiar' and pl.sede_codigo is null and pl.vigente_desde <= date '2026-09-28'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-28')
   order by pl.vigente_desde desc limit 1;
  select pl.valor into v_asig_nueva from parametros_laborales pl
   where pl.clave = 'asignacion_familiar' and pl.sede_codigo is null and pl.vigente_desde <= date '2026-10-28'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-28')
   order by pl.vigente_desde desc limit 1;

  if v_rmv_nueva is distinct from 1230 or v_rmv_1oct is distinct from 1230 then
    raise exception '0501: el periodo que cierra el 2026-10-28 leería RMV % (y el 2026-10-01, %). Esperado 1230. Hay otra fila de RMV desde el 2026-10-01 en parametros_laborales: revisarla antes de seguir.',
      v_rmv_nueva, v_rmv_1oct;
  end if;
  if v_rmv_vieja is distinct from 1130 or v_rmv_30sep is distinct from 1130 then
    raise exception '0501: el periodo que cierra el 2026-09-28 leería RMV % (y el 2026-09-30, %). Esperado 1130: la migración habría reescrito un periodo ya pagado.',
      v_rmv_vieja, v_rmv_30sep;
  end if;
  if v_asig_nueva is distinct from 123 then
    raise exception '0501: el periodo que cierra el 2026-10-28 leería asignación familiar % (esperado 123). Hay otra fila desde el 2026-10-01: revisarla antes de seguir.', v_asig_nueva;
  end if;
  if v_asig_vieja is distinct from 113 then
    raise exception '0501: el periodo que cierra el 2026-09-28 leería asignación familiar % (esperado 113): habría reescrito un periodo ya pagado.', v_asig_vieja;
  end if;

  -- La segunda verdad: la que lee fn_remuneracion_computable.
  select true, coalesce((valor ->> 'monto')::numeric, 0) into v_cfg_existe, v_cfg
    from configuracion where clave = 'asignacion_familiar';
  if coalesce(v_cfg_existe, false) and v_cfg < 123 then
    raise exception '0501: configuracion.asignacion_familiar quedó en % y las liquidaciones leerían un número distinto al de la boleta del mes.', v_cfg;
  end if;
end
$mig$;

-- ── 6 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (501, 'la_rmv_sube_a_1230_y_la_escala_la_sigue')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

commit;

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Una sola fila. Esperado, en este orden: 1230 · 1130 · 123 · 113 · 123 ·
-- 1230.00 · 1230 / 1245 / 1260 · 501 con su nombre.
select
  (select pl.valor from parametros_laborales pl where pl.clave = 'rmv' and pl.sede_codigo is null
     and pl.vigente_desde <= date '2026-10-15'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-15')
   order by pl.vigente_desde desc limit 1)                          as rmv_15_oct,
  (select pl.valor from parametros_laborales pl where pl.clave = 'rmv' and pl.sede_codigo is null
     and pl.vigente_desde <= date '2026-09-30'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-30')
   order by pl.vigente_desde desc limit 1)                          as rmv_30_sep,
  (select pl.valor from parametros_laborales pl where pl.clave = 'asignacion_familiar'
     and pl.vigente_desde <= date '2026-10-15'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-15')
   order by pl.vigente_desde desc limit 1)                          as asignacion_15_oct,
  (select pl.valor from parametros_laborales pl where pl.clave = 'asignacion_familiar'
     and pl.vigente_desde <= date '2026-09-30'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-09-30')
   order by pl.vigente_desde desc limit 1)                          as asignacion_30_sep,
  (select (valor ->> 'monto')::numeric from configuracion
    where clave = 'asignacion_familiar')                            as asignacion_configuracion,
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'personas'
      and column_name = 'sueldo_base_legal')                        as default_base_legal,
  (select string_agg(c.rango || ' ' || c.salario_declarado::text, ' · ' order by c.orden)
     from categorias_laborales c
    where c.rango in ('colibri', 'cayla', 'support'))               as politica_declarada,
  (select m.numero || ' ' || m.nombre from migraciones_aplicadas m
    where m.numero = 501)                                           as registro;
