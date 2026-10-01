-- ============================================================================
-- 0502 — Los practicantes llegan al piso de la RMV nueva (S/ 1,230)
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que desde el 2026-10-01 —y solo desde ahí— cada practicante ACTIVO cuya
--   subvención vigente esté POR DEBAJO de su piso legal cobre ese piso:
--
--     · piso = la RMV vigente el 1-oct (S/ 1,230, leída de `parametros_laborales`,
--       no escrita a mano) para un profesional y para un preprofesional de
--       jornada completa;
--     · piso proporcional —RMV × horas / 30, redondeado a céntimos— para un
--       preprofesional cuyo convenio fije MENOS de 30 h semanales. Es la misma
--       cuenta que ya hace el generador de convenios en Contratos (Ley 28518,
--       art. 45) y el script de comprobación de la 0501.
--
--   La alcanzada se identifica POR REGLA (practicante activo, no cuenta de
--   servicio, subvención < piso), nunca por rango ni por nombre. Y la migración
--   SOLO SUBE: nadie queda con menos subvención ni con menos base declarada que
--   antes, y a nadie se le sube por encima de su piso.
--
--   Todo en UNA transacción (begin … commit) con foto de antes, foto de después
--   y una guardia final que aborta en voz alta si algo no quedó como se
--   prometió. O queda todo o no queda nada.
--
-- POR QUÉ LA 0501 NO LOS ALCANZÓ
--
--   La 0501 sube la base por rango con `fn_fijar_base_declarada` (0128), que
--   exige `en_planilla`; un practicante tiene `en_planilla = false` (columna
--   generada, 0085). Y aunque la alcanzara, esa función iguala a TODOS los de
--   un rango al monto pedido: cada practicante lleva uno de los seis rangos de
--   `asignaciones_salario` (no existe un rango «practicante»), así que subir
--   «por rango» habría barrido también a quien pactó menos horas —y subirle de
--   más a quien trabaja menos no se puede deshacer, porque sería BAJARLE una
--   subvención ya pagada.
--
-- ⚠️ LA SUPOSICIÓN «JORNADA COMPLETA» — escrita acá a propósito
--
--   El único dato de las horas pactadas es `contratos_generados.horas_semanales`
--   del convenio de prácticas vigente. En producción hoy hay cinco practicantes
--   activos (tres profesionales y dos preprofesionales) y NINGUNO tiene un
--   convenio con horas pactadas cargado en el sistema. El generador solo guarda
--   las horas de un PREPROFESIONAL (al profesional se le deja `null`), y el
--   sistema entero —el generador, el texto del convenio, el script de la
--   0501— lee «sin horas» como JORNADA COMPLETA de la modalidad: 30 h el
--   preprofesional, 48 h el profesional.
--
--   Esta migración hace lo mismo: a quien no tiene horas pactadas en un
--   convenio le aplica la jornada completa de su modalidad y, por tanto, el
--   piso entero. ESO ES UNA SUPOSICIÓN, no un dato. La confirmó Felipe el
--   2026-10-01 leyendo la fila 6 de `scripts/sql-manual/antes_de_pegar_la_rmv_1230.sql`
--   (la de la 0501), donde cada practicante figura con «horas completas»; y la
--   LEE DE NUEVO, ya con las horas SUPUESTAS marcadas una por una, en la fila 6
--   de `scripts/sql-manual/antes_de_pegar_los_practicantes_1230.sql` ANTES de
--   pegar esta migración: esa fila dice, persona por persona, qué horas se
--   conocen y cuáles se SUPONEN, y qué hará esta migración con cada una.
--
--   Si alguno trabaja en verdad menos horas, esta migración le sube de más y
--   NO hay vuelta atrás sin reducirle una subvención ya pagada. Por eso:
--     1 · quien tenga horas en un convenio queda protegido por el piso
--         proporcional (nunca se le sube a 1,230 si pactó 20 h);
--     2 · quien ingresó DESPUÉS del 2026-10-01 y no tiene horas pactadas queda
--         FUERA: la suposición la confirmó Felipe sobre las personas que tenía
--         delante ese día, no sobre las que lleguen después;
--     3 · la migración DICE en voz alta, con conteos y sin nombres, a cuántos
--         subió por suposición (RAISE NOTICE 0502, más abajo).
--
-- QUÉ ASUME
--
--   · Que la 0501 ya está pegada: la RMV vigente el 2026-10-01 es S/ 1,230. Si
--     la fila no está o dice otra cosa, la migración se detiene sin tocar nada
--     (con la RMV vieja el piso saldría 1,130 y no subiría a nadie, en
--     silencio).
--   · Que existe al menos un admin activo con usuario (`auth_user_id`):
--     `fn_set_salario` exige sesión de administrador y el SQL Editor no la
--     trae. Se PRESTA la identidad del admin activo más antiguo (mismo patrón
--     que la 0501 y la 0462) solo durante esta transacción; el guard de las
--     funciones NO se debilita ni se toca. Si no hay ninguno y hay a quién
--     subir, se detiene sin tocar nada.
--   · Que el periodo 2026-09-28 → 2026-10-28 (31 días; medido en producción el
--     2026-10-01, ver la corrección de la 0501 en docs/estado.md) sigue SIN
--     PAGARSE para el grupo practicante: el candado de periodo pagado de
--     `fn_set_salario` (por grupo, desde la 0327) se negaría si no.
--
-- POR QUÉ ASÍ
--
--   1 · Un tramo nuevo desde el 1-oct, no desde el inicio del periodo. La
--       planilla paga POR DÍA con el tramo que contiene cada jornada (0495):
--       el 28, 29 y 30 de septiembre —tres días, no dos— caen dentro del
--       periodo abierto y siguen al sueldo viejo. La RMV nueva rige desde el
--       1-oct por decreto; pagar septiembre a la escala nueva sería regalarlo.
--   2 · `fn_set_salario` por persona, con el rango que ya tiene. No se usa
--       `fn_fijar_base_declarada` (ver arriba) ni un UPDATE: `fn_set_salario`
--       versiona (cierra el tramo el 30-sep, abre el nuevo el 1-oct) y lleva
--       el candado de periodo pagado. El rango NO cambia: solo sirve de rótulo
--       y para el techo de educación, y no se mueve en silencio.
--   3 · La regla vive en UNA vista temporal (`pg_temp.v0502`) que lee la foto
--       de antes, el cálculo de quién sube y la guardia de después. Se muere
--       con la sesión; no deja ningún objeto permanente en el esquema ni
--       reescribe ninguna función. La misma regla —palabra por palabra— está en
--       la prueba 396 y en el script de comprobación, y
--       `tests/practicantes-piso-misma-regla.test.ts` las compara: el script
--       que Felipe lee ANTES de pegar tiene que ser la regla que de verdad se
--       ejecuta, y no una copia que fue envejeciendo.
--   4 · `personas.sueldo_base_legal` SUBE con la subvención, solo si ya tenía
--       un valor menor al nuevo (nulo se queda nulo: es «sin confirmar»). No
--       mueve el pago de un practicante —su pago sale del tramo, y la base de
--       pensión vale cero porque no está en planilla—, pero la constancia de
--       subvención que se le entrega imprime «Subvención pactada (mes
--       completo)» leyendo ESA columna: sin subirla, el papel diría S/ 1,130
--       al lado de un pago calculado sobre S/ 1,230. Va por
--       `fn_set_sueldo_base_legal` (campo sensible, función guardián) y deja
--       el valor anterior en `correcciones_auditoria`, que es lo que permite
--       revertirla (el tramo se revierte por su nota; la base no tiene fechas).
--       Límite heredado de la 0128: como la base no tiene fechas, reimprimir
--       una constancia ya pagada mostrará el «mes completo» nuevo; no afecta
--       totales (foto 0096).
--   5 · Casos que DETIENEN en vez de resolverse solos (mismo criterio que la
--       0501): un practicante a quien se le subiría con `base_provision`
--       propia (`fn_set_salario` no la copia al tramo nuevo), con sueldo fijo
--       (su pago no depende de las horas), con un tramo de sueldo ya
--       programado DESPUÉS del 1-oct (`fn_set_salario` lo borraría) o con un
--       cambio de sueldo programado que todavía cubre el 1-oct (lo que cobrará
--       ese día no es su tramo abierto y la regla lo leería mal).
--   6 · Casos que se OMITEN y se cuentan: sin modalidad (no se sabe si es
--       preprofesional, y por tanto si su piso podría ser proporcional; el
--       generador de Contratos también la exige), sin tramo de subvención
--       cargado (no se inventa un monto) e ingreso posterior al 1-oct sin
--       horas pactadas (ver la suposición).
--
-- LO QUE MUEVE EN PLATA
--
--   · Subvención: de S/ 1,130 a S/ 1,230 por practicante alcanzado desde el
--     1-oct. La planilla paga por horas sobre una base de 6.5 h por día
--     calendario: lo que sube cada mes es (horas marcadas desde el 1-oct) ×
--     S/ 100 / (6.5 × días del periodo). Con asistencia completa de 6.5 h los
--     31 días, el periodo 28-sep → 28-oct paga ≈ S/ 1,220.32 en vez de
--     S/ 1,130.00 (3/31 × 1,130 + 28/31 × 1,230), o sea +S/ 90.32; el periodo
--     siguiente, completo, +S/ 100. Con jornadas reales el aumento es MENOR
--     (ver docs/estado.md: medido, por modalidad y jornada).
--   · EsSalud: NO lo mueve esta migración. El aporte de un practicante es el
--     piso puro (9 % de la RMV al último día del periodo) y ya subió de
--     S/ 101.70 a S/ 110.70 con la 0501, con o sin esta.
--   · Media subvención semestral y descanso de 15 días (Ley 28518, art. 42):
--     `fn_subvenciones_practicante` (0467; la lee Provisiones) y
--     `fn_mis_subvenciones_practicante` (0485; la lee el propio practicante)
--     devengan sobre la subvención VIGENTE a la fecha de corte, sin versionar
--     el pasado. Al subir el tramo, TODO lo ya devengado se revalúa de golpe en
--     un 8.85 % (1,230 / 1,130) y, de ahí en adelante, cada hito de seis meses
--     y el descanso valen S/ 50 más. Es costo real y no un error: avisa a
--     quien mire Provisiones el día de la pegada. (La 0465 que describía una
--     fórmula continua dentro de `fn_provisiones` fue RETIRADA por la 0471:
--     esas dos funciones son hoy la única fuente.)
--   · Contratos lee el tramo abierto: desde que esto se pegue, deja de bloquear
--     generar un convenio con subvención bajo el piso (bloqueaba desde el 1-oct).
--     Los convenios YA firmados siguen diciendo 1,130 en el papel: pagar más es
--     favorable, pero el papel queda viejo (adenda o próxima renovación; consulta
--     al laboralista, anotada en docs/estado.md).
--
-- ⚠️ NO SE PUEDE BAJAR DESPUÉS DE PAGAR UN PERIODO CON ELLA
--
--   Mientras el grupo practicante del periodo 28-sep → 28-oct siga sin pagarse,
--   se revierte (ver CÓMO SE REVIERTE). Una vez pagado con la subvención nueva,
--   volver a la vieja es reducir unilateralmente lo pactado y pagado, y la
--   media subvención y el descanso ya devengados a la tasa nueva dejarían de
--   cuadrar con lo que se les dijo.
--
-- CÓMO Y CUÁNDO SE PEGA
--
--   Después de la 0501 (ya pegada) y ANTES de pagar el grupo practicante del
--   periodo 28-sep → 28-oct. Es solo datos: no cambia ninguna pantalla ni
--   ninguna función, así que no depende del orden respecto de ningún PR. El SQL
--   se pide con ./scripts/dame-el-sql.sh 0502 (no se abre el archivo), y ANTES
--   se corre scripts/sql-manual/antes_de_pegar_los_practicantes_1230.sql y se
--   lee su fila 6: es la confirmación de la suposición «jornada completa».
--   Como no reescribe ninguna función, no hay md5 de partida.
--
-- LO QUE NO HACE
--
--   · NO toca a nadie que no sea practicante activo: ni integrantes en planilla,
--     ni locadores (RxH), ni personal de dirección, ni cuentas de servicio, ni
--     inactivos.
--   · NO toca la RMV, la asignación familiar, la Política salarial, el DEFAULT
--     de la base legal ni la escala de rangos: todo eso fue la 0501.
--   · NO reescribe ninguna función SQL ni crea ningún objeto permanente.
--   · NO evita un efecto colateral heredado: cada tramo de sueldo nuevo dispara
--     `fn_educacion_realinear` (0281), que corrige la asignación por educación
--     de quien tenga una que no cuadre con el 75 % de su costo declarado y deja
--     en la auditoría el motivo «Cambió el rango» aunque el rango no cambió.
--     Medido en el ensayo: pasa con una asignación de S/ 80.00 y costo S/ 107
--     (sube a S/ 80.25 desde el 1-oct) y NO pasa con una que ya cuadra. La
--     migración lo cuenta y lo dice en voz alta (RAISE NOTICE «AVISO»); el
--     script de comprobación lista de antemano a quién le puede pasar.
--   · NO garantiza que la BOLETA llegue a S/ 1,230: la planilla paga a un
--     practicante por las horas marcadas (6.5 h por día calendario = la
--     subvención entera), así que un preprofesional que cumple 30 h semanales
--     cobra del orden de dos tercios del tramo. Que eso satisfaga el art. 45
--     de la Ley 28518 («no inferior a una RMV a jornada máxima») es una
--     consulta al laboralista, anotada en docs/estado.md; esta migración sube
--     el TRAMO —lo pactado y lo que el sistema exige—, no resuelve esa
--     pregunta.
--   · NO siembra el segundo tramo de la RMV (S/ 1,300, primer semestre de
--     2027): cuando salga, el piso vuelve a quedar por encima y hay que rehacer
--     esta migración con los números de ese día.
--
-- CÓMO SE REVIERTE
--
--   Solo mientras el grupo practicante de ese periodo siga sin pagarse, y
--   marcando por la nota («Migración 0502.») para no tocar nada más:
--
--     with borradas as (
--       delete from asignaciones_salario
--        where nota like '%Migración 0502.' and vigente_desde = date '2026-10-01'
--       returning persona_id)
--     update asignaciones_salario a
--        set vigente_hasta = null
--       from borradas b
--      where a.persona_id = b.persona_id and a.vigente_hasta = date '2026-09-30';
--
--   y la base legal, con el valor que dejó en `correcciones_auditoria`:
--
--     update personas p
--        set sueldo_base_legal = replace(c.valor_anterior, 'S/', '')::numeric
--       from correcciones_auditoria c
--      where c.persona_id = p.id and c.campo_modificado = 'personas.sueldo_base_legal'
--        and c.motivo like 'Migración 0502:%';
--
--   (el tramo se ensayó contra la cadena completa: devuelve la tabla EXACTAMENTE
--   como estaba antes). Después de pagar ese periodo: NO se revierte.
--
-- IDEMPOTENTE: pegarla dos veces no abre tramos nuevos ni falla. La segunda
-- vez la regla no encuentra a nadie bajo su piso y solo lo dice.
-- ============================================================================

begin;

-- ── 0 · La regla: quién sube, y a cuánto ────────────────────────────────────
-- LA MISMA REGLA, palabra por palabra, está en supabase/tests/396_*.test.sql y
-- en scripts/sql-manual/antes_de_pegar_los_practicantes_1230.sql. Si se toca
-- aquí, se toca allá: tests/practicantes-piso-misma-regla.test.ts lo exige.
create temporary view v0502 as
-- >>> REGLA 0502
with
conv as (
  -- El convenio de prácticas que manda por persona: el más reciente sin anular.
  -- El orden es el de fn_contratos_tablero (0386), que contesta esta misma
  -- pregunta en otra pantalla: generado_at, inicio, fin y id como ancla.
  select distinct on (c.persona_id) c.persona_id, c.horas_semanales
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
   order by c.persona_id, c.generado_at desc, c.fecha_inicio desc,
            c.fecha_fin desc, c.id desc
),
rmv as (
  -- La RMV tal como la lee la planilla: la fila vigente en esa fecha.
  select pl.valor
    from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null
     and pl.vigente_desde <= date '2026-10-01'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-01')
   order by pl.vigente_desde desc
   limit 1
),
base as (
  select p.id as persona_id,
         a.rango,
         a.salario_mensual_soles as sal,
         p.sueldo_base_legal     as base,
         a.base_provision        as bp,
         p.sueldo_fijo           as sfijo,
         p.fecha_ingreso         as ingreso,
         p.practicante_modalidad as modalidad,
         cv.horas_semanales      as horas,
         (cv.horas_semanales is null) as asumida,
         (select r.valor from rmv r)  as rmv,
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde > date '2026-10-01') as futuro,
         -- Un cambio de sueldo ya programado: un tramo CERRADO que todavía cubre
         -- el 1-oct. Lo que se pagará ese día no es el tramo abierto que lee la
         -- regla sino ese, y no se resuelve a ciegas.
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde <= date '2026-10-01'
                    and f.vigente_hasta >= date '2026-10-01') as programado
    from personas p
    left join asignaciones_salario a
      on a.persona_id = p.id and a.vigente_hasta is null
    left join conv cv on cv.persona_id = p.id
   where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
     and coalesce(p.cuenta_de_servicio, false) = false
),
con_piso as (
  select b.*,
         case when b.modalidad = 'preprofesional' and b.horas is not null
              then round(b.rmv * least(b.horas, 30) / 30, 2)
              else b.rmv end as piso
    from base b
)
select c.persona_id, c.rango, c.modalidad, c.horas, c.asumida,
       c.sal, c.base, c.bp, c.sfijo, c.futuro, c.programado, c.rmv, c.piso,
       case
         when c.modalidad is null then 'omitida_sin_modalidad'
         when c.rango is null then 'omitida_sin_tramo'
         when c.asumida and c.ingreso > date '2026-10-01' then 'omitida_ingreso_posterior'
         when c.sal >= c.piso
           then case when c.piso < c.rmv then 'cumple_jornada_reducida' else 'cumple' end
         when c.sal < c.piso then 'sube'
         else 'sin_dato'
       end as accion
  from con_piso c
-- <<< REGLA 0502
;

-- ── 1 · Quién sube, qué frena la migración, y la subida ─────────────────────
do $mig$
declare
  c_desde   constant date    := date '2026-10-01';
  c_rmv     constant numeric := 1230;

  v_antes   jsonb;
  v_c       record;
  v_fila    record;
  v_admin   uuid;
  v_auth    uuid;
  v_tocados uuid[] := '{}';
  v_nota    text;

  v_total int;      v_suben int;     v_s_prof int;    v_s_pre int;    v_s_conv int;
  v_cumplen int;    v_reducida int;  v_sin_mod int;   v_sin_tramo int; v_ingreso int;
  v_sin_dato int;
  v_total_d int;    v_suben_d int;   v_cumplen_d int; v_reducida_d int;
  v_sin_mod_d int;  v_sin_tramo_d int; v_ingreso_d int; v_sin_dato_d int;

  v_edu_a   int;     v_edu_d int;
  v_sal_a   numeric; v_base_a numeric; v_tramos_a int; v_rango_a text;
  v_piso    numeric; v_base_esperada numeric; v_desde_tramo date;
begin
  -- ── 1.0 · La RMV que lee la regla tiene que ser la de la 0501 ─────────────
  -- Si falta la fila, `rmv` sale nulo y nadie «está bajo su piso»: la migración
  -- se vería ejecutada y no habría subido a nadie. Mejor que grite.
  if exists (select 1 from pg_temp.v0502 where rmv is distinct from c_rmv) then
    raise exception '0502 · la RMV vigente el 2026-10-01 no es S/ % (o no hay ninguna). La 0501 tiene que estar pegada antes que esta. No se toca nada.', c_rmv;
  end if;

  -- ── 1.1 · La foto de ANTES: de todos, no solo de los practicantes ─────────
  select coalesce(jsonb_object_agg(x.persona_id::text,
           jsonb_build_object('salario', x.salario, 'base', x.base,
                              'tramos', x.tramos, 'rango', x.rango)),
           '{}'::jsonb)
    into v_antes
    from (select p.id as persona_id,
                 (select a.salario_mensual_soles from asignaciones_salario a
                   where a.persona_id = p.id and a.vigente_hasta is null) as salario,
                 (select a.rango from asignaciones_salario a
                   where a.persona_id = p.id and a.vigente_hasta is null) as rango,
                 p.sueldo_base_legal as base,
                 (select count(*) from asignaciones_salario a
                   where a.persona_id = p.id) as tramos
            from personas p) x;

  -- ── 1.2 · Los conteos, que se DICEN (sin nombres) ─────────────────────────
  select count(*),
         count(*) filter (where accion = 'sube'),
         count(*) filter (where accion = 'sube' and asumida and modalidad = 'profesional'),
         count(*) filter (where accion = 'sube' and asumida and modalidad = 'preprofesional'),
         count(*) filter (where accion = 'sube' and not asumida),
         count(*) filter (where accion = 'cumple'),
         count(*) filter (where accion = 'cumple_jornada_reducida'),
         count(*) filter (where accion = 'omitida_sin_modalidad'),
         count(*) filter (where accion = 'omitida_sin_tramo'),
         count(*) filter (where accion = 'omitida_ingreso_posterior'),
         count(*) filter (where accion = 'sin_dato')
    into v_total, v_suben, v_s_prof, v_s_pre, v_s_conv,
         v_cumplen, v_reducida, v_sin_mod, v_sin_tramo, v_ingreso, v_sin_dato
    from pg_temp.v0502;

  if v_sin_dato > 0 then
    raise exception '0502 · % practicante(s) no cayeron en ningún caso de la regla. No se toca nada.', v_sin_dato;
  end if;

  raise notice '0502 · practicantes activos: % · SUBEN: % (de ellos, con jornada completa SUPUESTA por no haber horas pactadas en un convenio: % profesional(es) y % preprofesional(es); con las horas leídas de su convenio: %) · ya cumplían su piso: % · quedan como están por jornada reducida pactada: % · quedan FUERA por falta de dato (sin modalidad: %, sin subvención cargada: %, ingreso posterior al 1-oct sin horas pactadas: %).',
    v_total, v_suben, v_s_prof, v_s_pre, v_s_conv,
    v_cumplen, v_reducida, v_sin_mod, v_sin_tramo, v_ingreso;

  -- ── 1.3 · Lo que frena: no se resuelve a ciegas ───────────────────────────
  if exists (select 1 from pg_temp.v0502 where accion = 'sube' and bp is not null) then
    raise exception '0502 · hay un practicante con base_provision propia en su tramo abierto. fn_set_salario no la copia al tramo nuevo y sus provisiones cambiarían en silencio. No se toca nada.';
  end if;
  if exists (select 1 from pg_temp.v0502 where accion = 'sube' and sfijo is true) then
    raise exception '0502 · hay un practicante con sueldo fijo: su pago no depende de las horas y no se resuelve a ciegas. No se toca nada.';
  end if;
  if exists (select 1 from pg_temp.v0502 where accion = 'sube' and futuro) then
    raise exception '0502 · hay un practicante con un tramo de sueldo ya programado DESPUÉS del 2026-10-01. fn_set_salario lo borraría. No se toca nada.';
  end if;
  if exists (select 1 from pg_temp.v0502
              where programado and accion in ('sube', 'cumple', 'cumple_jornada_reducida')) then
    raise exception '0502 · hay un practicante con un cambio de sueldo programado después del 2026-10-01: lo que cobrará el 1-oct no es su tramo abierto y la regla lo leería mal. No se toca nada.';
  end if;

  -- ── 1.4 · Presta la identidad de un admin (solo si hay a quién subir) ─────
  select p.id, p.auth_user_id into v_admin, v_auth
    from personas p
   where p.rol = 'admin' and p.estado = 'activo' and p.auth_user_id is not null
   order by p.fecha_ingreso nulls last, p.id
   limit 1;

  if v_suben > 0 then
    if v_admin is null then
      raise exception '0502 · hay % practicante(s) a quien subirle la subvención pero ningún admin activo con usuario que firme el cambio. No se toca nada.', v_suben;
    end if;
    perform set_config('request.jwt.claim.sub', v_auth::text, true);
    if fn_es_admin_o_lider() is not true then
      raise exception '0502 · la identidad prestada no dio sesión de administrador. No se toca nada.';
    end if;
    raise notice '0502 · subiendo % practicante(s); el rastro queda a nombre del admin activo más antiguo.', v_suben;
  else
    raise notice '0502 · ningún practicante está bajo su piso (o ya estaban subidos): no hay nada que subir.';
  end if;

  -- ── 1.5 · La subida, persona por persona, SOLO hasta su piso ──────────────
  -- Cada tramo nuevo dispara `fn_educacion_realinear` (0281), que puede mover la
  -- asignación por educación de quien ya tenía una que no cuadra con el 75 % de
  -- su costo declarado. Se cuenta antes y después para decirlo, no para frenar.
  select count(*) into v_edu_a
    from correcciones_auditoria
   where campo_modificado = 'educacion_realineada'
     and persona_id in (select persona_id from pg_temp.v0502);

  for v_c in
    select * from pg_temp.v0502 where accion = 'sube' order by persona_id
  loop
    v_nota := 'Piso de la subvención de prácticas (Ley 28518, art. 45) con la RMV de S/ '
              || to_char(v_c.rmv, 'FM999990.00') || ' vigente desde el 2026-10-01 '
              || '(D.S. 015-2026-TR): subvención S/ ' || to_char(v_c.piso, 'FM999990.00') || ', '
              || case when v_c.asumida
                      then 'jornada completa de su modalidad SUPUESTA (sin horas pactadas en un convenio del sistema)'
                      else 'sobre las ' || v_c.horas::text || ' h semanales de su convenio' end
              || '. Decidido por Felipe el 2026-10-01. Migración 0502.';

    begin
      perform fn_set_salario(v_c.persona_id, v_c.rango, v_c.piso, c_desde, v_nota);
    exception when others then
      raise exception '0502 · se detuvo al subir la subvención de un practicante: %', sqlerrm;
    end;
    v_tocados := v_tocados || v_c.persona_id;

    -- La base legal solo sube si ya tenía un valor menor; nulo se queda nulo.
    if v_c.base is not null and v_c.base < v_c.piso then
      begin
        perform fn_set_sueldo_base_legal(v_c.persona_id, v_c.piso);
      exception when others then
        raise exception '0502 · se detuvo al subir la base legal de un practicante: %', sqlerrm;
      end;
      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (v_c.persona_id, 'personas.sueldo_base_legal',
         'S/' || to_char(v_c.base, 'FM999990.00'),
         'S/' || to_char(v_c.piso, 'FM999990.00'),
         v_admin,
         'Migración 0502: la subvención del practicante sube al piso de la RMV de S/ '
         || to_char(v_c.rmv, 'FM999990.00') || ' desde el 2026-10-01 y la constancia debe decir lo que se paga.');
    end if;
  end loop;

  select count(*) into v_edu_d
    from correcciones_auditoria
   where campo_modificado = 'educacion_realineada'
     and persona_id in (select persona_id from pg_temp.v0502);
  if v_edu_d > v_edu_a then
    raise notice '0502 · AVISO: abrir el tramo nuevo realineó % asignación(es) de educación de practicantes (0281: la asignación se corrige al 75 %% de su costo declarado; la auditoría la deja con el motivo «Cambió el rango»). Revisar en Equipo.', v_edu_d - v_edu_a;
  end if;

  -- ── 1.6 · Guardia: nadie baja, nadie más se movió, los tocados quedaron ───
  for v_fila in
    select p.id,
           p.sueldo_base_legal as base,
           a.salario_mensual_soles as sal,
           a.rango,
           a.vigente_desde as desde_tramo,
           (select count(*) from asignaciones_salario x where x.persona_id = p.id) as tramos
      from personas p
      left join asignaciones_salario a
        on a.persona_id = p.id and a.vigente_hasta is null
  loop
    if (v_antes -> v_fila.id::text) is not null then
      v_sal_a    := (v_antes -> v_fila.id::text ->> 'salario')::numeric;
      v_base_a   := (v_antes -> v_fila.id::text ->> 'base')::numeric;
      v_tramos_a := (v_antes -> v_fila.id::text ->> 'tramos')::int;
      v_rango_a  := (v_antes -> v_fila.id::text ->> 'rango');

      if v_fila.sal < v_sal_a or v_fila.base < v_base_a then
        raise exception '0502 · GUARDIA: alguien habría quedado con MENOS subvención o base que antes. Esta migración solo sube. Se anula todo.';
      end if;

      if not (v_fila.id = any (v_tocados)) then
        if v_fila.sal is distinct from v_sal_a
           or v_fila.base is distinct from v_base_a
           or v_fila.tramos is distinct from v_tramos_a then
          raise exception '0502 · GUARDIA: se movió el sueldo, la base o los tramos de alguien que esta migración no debía tocar (integrantes en planilla, locadores, dirección, cuentas de servicio, inactivos, practicantes que ya cumplían, con jornada reducida u omitidos). Se anula todo.';
        end if;
      else
        select c.piso into v_piso from pg_temp.v0502 c where c.persona_id = v_fila.id;
        v_base_esperada := case when v_base_a is not null and v_base_a < v_piso then v_piso else v_base_a end;
        if v_fila.sal is distinct from v_piso
           or v_fila.base is distinct from v_base_esperada
           or v_fila.rango is distinct from v_rango_a
           or v_fila.desde_tramo is distinct from c_desde then
          raise exception '0502 · GUARDIA: alguien que se subió no quedó en su piso, con su rango, su base legal y su tramo desde el 2026-10-01 (subvención %, piso %, base %, base esperada %). Se anula todo.',
            v_fila.sal, v_piso, v_fila.base, v_base_esperada;
        end if;
      end if;
    end if;
  end loop;

  -- Y la regla, vuelta a preguntar DESPUÉS: nadie sigue bajo su piso, y lo que
  -- se omitió o se dejó como estaba es EXACTAMENTE lo que se dijo al principio.
  select count(*),
         count(*) filter (where accion = 'sube'),
         count(*) filter (where accion = 'cumple'),
         count(*) filter (where accion = 'cumple_jornada_reducida'),
         count(*) filter (where accion = 'omitida_sin_modalidad'),
         count(*) filter (where accion = 'omitida_sin_tramo'),
         count(*) filter (where accion = 'omitida_ingreso_posterior'),
         count(*) filter (where accion = 'sin_dato')
    into v_total_d, v_suben_d, v_cumplen_d, v_reducida_d,
         v_sin_mod_d, v_sin_tramo_d, v_ingreso_d, v_sin_dato_d
    from pg_temp.v0502;

  if v_suben_d > 0 or v_sin_dato_d > 0 then
    raise exception '0502 · GUARDIA: quedan % practicante(s) bajo su piso después de subir. Se anula todo.', v_suben_d + v_sin_dato_d;
  end if;
  -- «cumple» y «jornada reducida» se miran JUNTOS: quien subió hasta su piso
  -- proporcional (menos que la RMV entera) pasa de «sube» a «jornada reducida».
  if v_total_d is distinct from v_total
     or v_cumplen_d + v_reducida_d is distinct from v_cumplen + v_reducida + v_suben
     or v_sin_mod_d is distinct from v_sin_mod
     or v_sin_tramo_d is distinct from v_sin_tramo
     or v_ingreso_d is distinct from v_ingreso then
    raise exception '0502 · GUARDIA: los conteos de DESPUÉS no cuadran con los de antes (cumplen %, jornada reducida %, sin modalidad %, sin subvención %, ingreso posterior %). Se anula todo.',
      v_cumplen_d, v_reducida_d, v_sin_mod_d, v_sin_tramo_d, v_ingreso_d;
  end if;
end
$mig$;

drop view pg_temp.v0502;

-- ── 2 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (502, 'los_practicantes_llegan_al_piso_de_1230')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

commit;

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Una sola fila. Esperado, en este orden:
--   tramos_0502        · cuántos practicantes subió esta pegada (los que dijo la
--                        fila 6 del script como «SUBE»; 0 si es la segunda vez
--                        y se leen los de la primera: cuenta los tramos con su
--                        nota, no los de esta ejecución)
--   practicantes_bajo  · practicantes activos con la subvención vigente bajo
--                        1,230: solo pueden ser los de jornada reducida o los
--                        omitidos que la fila 6 ya listó (hoy: 0)
--   registro           · «502 los_practicantes_llegan_al_piso_de_1230»
select
  (select count(*) from asignaciones_salario a
    where a.nota like '%Migración 0502.' and a.vigente_desde = date '2026-10-01'
      and a.vigente_hasta is null)                                  as tramos_0502,
  (select count(*) from personas p
     join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
    where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
      and coalesce(p.cuenta_de_servicio, false) = false
      and a.salario_mensual_soles < 1230)                           as practicantes_bajo,
  (select m.numero || ' ' || m.nombre from migraciones_aplicadas m
    where m.numero = 502)                                           as registro;
