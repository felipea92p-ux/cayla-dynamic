-- ============================================================================
-- 0277 — Ni los descuentos ni los beneficios del sistema inflan la liquidación
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la base de las tres truncas por cese —gratificación, CTS y vacaciones—
--   la construyan SOLO el sueldo, la asignación familiar y los BONOS de verdad.
--   Ni un adelanto, ni la gratificación que el sistema depositó en julio, ni la
--   CTS de noviembre, ni las vacaciones pagadas vuelven a entrar por la puerta
--   de los «conceptos variables».
--
--   Y promete la mitad contraria, que importa igual: un bono GENUINO percibido
--   en tres o más meses del semestre SIGUE entrando, porque el art. 16 del
--   D.S. 001-97-TR lo ordena. Esta migración no baja todo lo que se puede:
--   deja pasar lo que la ley manda pagar y cierra lo demás.
--
-- QUÉ ASUME
--   · Que la versión de partida de `fn_remuneracion_computable` es la **0129**,
--     confirmado con `./scripts/donde-vive.sh fn_remuneracion_computable`.
--   · md5 DE PARTIDA, medido en el Postgres LOCAL con las 256 migraciones
--     anteriores aplicadas (la 0276 incluida):
--
--       fn_remuneracion_computable  119fbcb6faca8c4a808e9ecf7b1f4838   4 034 chars
--       fn_cts_trunca               84e6226144339fef7eb1bee079f7de5b   3 129 chars
--       fn_vacaciones_truncas       0d411bdbc3edd858264f80d7a929ddc9   3 059 chars
--
--     LOS TRES SE PIDIERON AL SQL EDITOR DE PRODUCCIÓN EL 2026-08-22, ANTES de
--     escribir una sola línea, y los tres coincidieron con el local al byte. Es
--     la regla que dejó escrita la 0276 después de que una migración construida
--     sobre un cuerpo viejo estuviera a punto de devolver a S/0,00 el mes de
--     quien se toma sus vacaciones completas.
--
--     Los cuerpos de `fn_cts_trunca` y `fn_vacaciones_truncas` NO se copiaron de
--     ningún archivo: se extrajeron de la base con `pg_get_functiondef` y se les
--     cambió UNA línea cada uno.
--
--     Y el md5 DE LLEGADA, para comprobar que se pegó entero (medido tras
--     `npx supabase db reset` con esta migración incluida):
--
--       fn_remuneracion_computable  2ca12a678a49bbc0b79e9302826147e5   6 863 chars
--       fn_cts_trunca               18ad676646963e676cdf975536ed247a   3 291 chars
--       fn_vacaciones_truncas       1b33f8c67e102535aa785ce18debf3a2   3 228 chars
--       fn_ventanas_de_regularidad  a546419c9c0ba3275e76c79e90c9032c     913 chars  (nueva)
--       fn_permitir_bono_regular    1167032dc6cfa8ee4a0c4b3f75f4fecf     534 chars  (nueva)
--       fn_trg_bono_umbral          ee800cb9ca24ef7b8cf94ae317440521   2 180 chars  (nueva)
--
--     ⚠️ PÍDESELO A PRODUCCIÓN ANTES DE PEGAR ESTO, con la consulta que imprime
--     `./scripts/donde-vive.sh fn_remuneracion_computable`. Si producción
--     devuelve `c519cd6d26362dae15040def792e26d3` en la columna
--     `sin_comentarios`, es el mismo código sin los comentarios y se puede
--     seguir. Si no coincide ninguno de los dos, PARA.
--   · Que el cuerpo NO se copió a ojo: se extrajo del archivo de la 0129 por
--     reemplazo de cadena EXACTA y ÚNICA, con un script que aborta si el ancla
--     no aparece exactamente una vez. Fuera de la consulta de conceptos
--     variables y de dos comentarios, no cambió un solo carácter.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- La 0087 escribió, y la 0129 conservó intacta, esta consulta:
--
--     select count(distinct date_trunc('month', pp.fecha_fin)), sum(mp.monto)
--       from movimientos_planilla mp ...
--      where mp.persona_id = p_persona_id
--        and mp.monto > 0                       ← NO FILTRA NADA
--        and pp.fecha_fin between v_sem_ini and v_sem_fin;
--
-- `movimientos_planilla` tiene `CHECK (monto > 0)` desde la 0025. La condición
-- es siempre verdadera: no es un filtro, es una línea que parece un filtro. Ni
-- `tipo` (bono | descuento) ni `categoria` (vacaciones | otros | gratificacion
-- | cts | null) se consultaban nunca.
--
-- De ahí salen tres cosas, y las tres pagan de MÁS:
--
--   1 · UN DESCUENTO SUBE LA LIQUIDACIÓN. Un adelanto quincenal es dinero que
--       la persona DEBE; entraba con signo positivo. El art. 9 del D.S.
--       001-97-TR define la remuneración computable por lo que el trabajador
--       *percibe*: un adelanto no se percibe, se devuelve. Es un error de
--       signo, no un criterio discutible.
--
--   2 · EL SISTEMA SE ABRE LA PUERTA SOLO. La regla del art. 16 pide tres
--       meses distintos en el semestre. El propio sistema aporta dos sin que
--       nadie haga nada: la gratificación que se deposita el 15/07 (categoría
--       `gratificacion`) y la CTS del 15/11 (categoría `cts`), las dos
--       escritas como `tipo = 'bono'` por la 0049. Cualquier tercer movimiento
--       en un tercer mes —hasta un descuento— completaba el trío.
--
--   3 · LOS BENEFICIOS ENTRAN A SU PROPIA BASE. La gratificación de julio son
--       1,5 sueldos, y engordaba la base con la que se calcula la
--       gratificación trunca de diciembre. Un beneficio que se calcula sobre
--       sí mismo no tiene fondo.
--
-- ── POR QUÉ CADA EXCLUSIÓN, CON SU ARTÍCULO ─────────────────────────────────
--
--   · `tipo = 'descuento'` FUERA — art. 9 del D.S. 001-97-TR (TUO de la CTS):
--     computable es «la remuneración básica y todas las cantidades que
--     regularmente PERCIBA el trabajador». Un adelanto es lo contrario de
--     percibir: es un préstamo que se descuenta después.
--
--   · `categoria = 'gratificacion'` FUERA — la gratificación de Fiestas
--     Patrias y Navidad es un beneficio propio de la Ley 27735, no una
--     remuneración complementaria. Que es un concepto DISTINTO de la
--     remuneración ordinaria lo confirma la Ley 30334, que la exonera de
--     aportes y crea a cambio la bonificación extraordinaria del 9 % —esta
--     casa ya la paga desde la 0134—. Si además entrara a su propia base, la
--     grati de julio (art. 2 de la Ley 27735: «una remuneración») subiría la
--     base de la grati de diciembre, que es circular.
--
--   · `categoria = 'cts'` FUERA — art. 1 del D.S. 001-97-TR: la CTS es un
--     «beneficio social de previsión contra las contingencias del cese», no
--     remuneración. No es computable para nada, y menos para sí misma.
--
--   · `categoria = 'vacaciones'` FUERA, y es la más sutil: aquí no se excluye
--     porque no sea remunerativa —lo es—, sino porque YA ESTÁ CONTADA. El art.
--     15 del D. Leg. 713 dice que la remuneración vacacional «es equivalente a
--     la que el trabajador hubiera percibido habitualmente en caso de
--     continuar laborando»: son los mismos soles del sueldo, cobrados bajo
--     otra etiqueta. Y `sueldo_basico` ya mete el sueldo entero en la base.
--     Sumar el movimiento otra vez es contar dos veces el mismo mes.
--
--   · `tipo = 'bono'` con `categoria` nula u `otros` DENTRO — art. 16 del
--     D.S. 001-97-TR: «tratándose de remuneraciones complementarias de
--     naturaleza variable o imprecisa, se cumple el requisito de regularidad
--     si el trabajador las ha percibido cuando menos TRES meses en cada
--     periodo de seis», y se incorporan sumando los montos y dividiendo entre
--     seis. Es exactamente lo que ya hace el `/ 6.0` de abajo, y se conserva.
--
-- ── POR QUÉ LISTA BLANCA Y NO LISTA NEGRA ───────────────────────────────────
--
-- Se escribió `(mp.categoria is null or mp.categoria = 'otros')` y no «distinta
-- de gratificacion, cts y vacaciones». Las dos dan el mismo resultado HOY. La
-- diferencia es el día que alguien agregue una quinta categoría al `check` de
-- `movimientos_categoria_valida`: con lista negra entraría sola a la
-- liquidación sin que nadie lo decida, y este defecto se llama exactamente así.
-- Con lista blanca queda fuera hasta que alguien la meta a propósito.
--
-- El riesgo del otro lado —que una categoría nueva y sí remunerativa se caiga
-- en silencio y se pague de MENOS— es real y no se ignora: la prueba 214
-- compara la lista blanca contra el `check` de la tabla y se pone ROJA en
-- cuanto aparezca una categoría que esta función no conoce.
--
-- ── LO QUE NO CAMBIA ────────────────────────────────────────────────────────
--
-- · El interruptor `configuracion.liquidacion_incluye_variables` sigue vivo y
--   sigue en `true`, y esta migración recomienda dejarlo así. Apagarlo también
--   arreglaba el defecto, pero de más: se llevaba por delante el bono genuino
--   del art. 16 y pagaba por DEBAJO del mínimo legal. Medido abajo.
-- · El guard `fn_es_admin_o_lider() is not true` de la 0129, intacto.
-- · El divisor `/ 6.0` y el umbral `>= 3`, intactos: son la ley.
-- · No toca el DEPÓSITO de grati y CTS (`fn_grati_cts_periodo` → `fn_provisiones`,
--   que tiene su propia base desde la 0276), ni la boleta. Solo la liquidación
--   por cese, que es el camino sin campo editable: recalcula, congela y paga.
--
-- ── LO QUE SE MIDIÓ ─────────────────────────────────────────────────────────
--
-- Postgres local, 2026-08-22, dentro de BEGIN … ROLLBACK. Seis personas
-- idénticas: sueldo S/1.950, ingreso 01/01/2024, cese al 30/11/2026, semestre
-- jul–dic 2026. Cifra = `fn_liquidacion(persona, '2026-11-30') ->> 'total'`.
--
--   caso                                       meses  promedio     ANTES     DESPUÉS
--   ------------------------------------------ -----  --------  --------  ----------
--   A · solo grati (15/07) + CTS (15/11)           2      0,00   1 867,40    1 867,40
--   B · A + un bono de S/50 en un tercer mes       3    522,92   2 366,34    1 867,40
--   C · A + un ADELANTO de S/500                   3    597,92   2 437,91    1 867,40
--   D · un bono REGULAR de S/200 × 3 meses         5    614,58   2 453,81    1 962,82
--   E · SOLO adelantos de S/500 × 3 meses          3    250,00   3 304,94    2 930,15
--   F · SOLO vacaciones pagadas × 3 meses          3    325,00   3 417,38    2 930,15
--
--   (Los «meses» y el «promedio» de la tabla son los de ANTES. Después: A, C, E
--    y F quedan en 0 meses; B en 1, que no llega a 3; D en 3 meses y S/100,00.)
--
-- LEÍDO EN VOZ ALTA. Un bono de S/50 costaba S/498,94 el día del cese —diez
-- veces su valor— y ni siquiera debía entrar: un solo bono en un solo mes no
-- llega a tres. Un adelanto de S/500, que es plata que la persona DEBE, subía
-- la liquidación S/374,79. Y unas vacaciones ya cobradas, S/487,23.
--
-- CONTRA LA OPCIÓN DE APAGAR EL INTERRUPTOR. Con
-- `liquidacion_incluye_variables = false` los seis casos caen a la misma base
-- de S/1.950,00, y el caso D —el bono genuino y regular— pasa de S/1.962,82 a
-- S/1.867,40: S/95,42 MENOS de lo que manda el art. 16 del D.S. 001-97-TR, por
-- cese y por persona. Esa es una infracción laboral, no un ahorro. Por eso el
-- arreglo va en la consulta y el interruptor se queda en `true`.
--
-- CUÁNTAS PERSONAS TOCA HOY, EN PRODUCCIÓN: no se sabe desde acá y no se
-- inventa. La consulta de solo lectura que lo responde, para el SQL Editor:
--
--     select p.id, p.nombres, p.apellidos,
--            count(*) filter (where mp.tipo = 'descuento')                as descuentos,
--            count(*) filter (where mp.categoria in ('gratificacion','cts','vacaciones')) as beneficios,
--            count(distinct date_trunc('month', pp.fecha_fin))
--              filter (where mp.tipo = 'bono' and (mp.categoria is null or mp.categoria = 'otros')) as meses_bono_real
--       from movimientos_planilla mp
--       join periodos_planilla pp on pp.id = mp.periodo_id
--       join personas p on p.id = mp.persona_id
--      where pp.fecha_fin >= date_trunc('year', current_date)
--      group by 1, 2, 3
--      having count(distinct date_trunc('month', pp.fecha_fin)) >= 3
--      order by 3, 2;
--
-- Quien salga con `meses_bono_real < 3` estaba cobrando de más si cesaba hoy.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Volver a pegar el bloque `create or replace function
-- fn_remuneracion_computable(...)` de `0129_tres_agujeros_de_permiso_cerrados.sql`
-- tal cual. No toca datos: `fn_remuneracion_computable` es `stable` y no
-- escribe nada, así que revertir la función revierte el comportamiento entero.
--
-- ⚠️ Las liquidaciones YA PAGADAS no se recalculan solas: la 0164 las congela
-- al pagarlas y la 0243 las hace inmutables. Esta migración cambia lo que se
-- calcule a partir de ahora. Si hay una liquidación pagada de más, se corrige
-- por el camino de siempre (anular con `fn_liquidacion_anular` y rehacer), no
-- por debajo.
--
-- ── CÓMO SE COMPRUEBA ───────────────────────────────────────────────────────
--
--   1) `npx supabase test db` → la prueba
--      `214_la_base_de_la_liquidacion_solo_admite_bonos.test.sql` en verde.
--   2) Después de pegar esto en producción, el `raise notice` del final dice
--      si la función quedó con los dos filtros.
--   3) A mano, sobre una persona real que tenga un adelanto en el semestre:
--      `select fn_remuneracion_computable('<uuid>', current_date);`
--      `variables_total` no debe incluir el adelanto.
-- ============================================================================


-- ⚠ EL `drop` NO ES OPCIONAL, Y CUESTA UNA PANTALLA SI SE OLVIDA.
--
-- Esta migración le agrega un tercer parámetro a la función. `create or replace`
-- con una firma distinta NO reemplaza: crea una SOBRECARGA, y entonces conviven
-- la de dos argumentos y la de tres con defecto. Cualquier llamada con dos
-- argumentos —que son todas las que ya existen— pasa a ser ambigua y Postgres
-- se niega:
--
--     ERROR: function fn_remuneracion_computable(uuid, unknown) is not unique
--
-- No falla al aplicar la migración: falla al ABRIR la hoja de liquidación.
-- Reproducido en local antes de escribir esta línea. Es el mismo cuidado que la
-- 0161 tuvo que tener con las funciones que devuelven TABLE.
drop function if exists fn_remuneracion_computable(uuid, date);

create or replace function fn_remuneracion_computable(
  p_persona_id uuid,
  p_fecha_ref  date,
  -- ⇩⇩⇩ CAMBIO 0277 ⇩⇩⇩ CADA BENEFICIO MIRA SU PROPIA VENTANA.
  --
  -- Hasta hoy esta función usaba UNA ventana —enero-junio / julio-diciembre—
  -- para los tres beneficios. Es la de la gratificación, y para la CTS es la
  -- equivocada: sus periodos van de noviembre a abril y de mayo a octubre.
  --
  -- No es un detalle de calendario. El test de regularidad cuenta MESES
  -- DISTINTOS dentro de la ventana, así que con la ventana mal puesta el mismo
  -- bono cae en el grupo equivocado: dos bonos de noviembre y diciembre más
  -- dos de enero y febrero son 2+2 en las ventanas de gratificación —no entran—
  -- y CUATRO en la ventana nov-abr de la CTS, donde sí entrarían.
  --
  -- POR QUÉ EL DEFECTO ES 'grati' Y NO OBLIGATORIO. Los tres llamadores están
  -- localizados y son tres —fn_cts_trunca, fn_vacaciones_truncas y
  -- fn_grati_trunca_bruta—. El último ya usaba la ventana correcta, así que con
  -- este defecto sigue funcionando sin tocarlo: menos superficie reescrita, que
  -- después de lo del 2026-08-20 no es un lujo.
  p_beneficio  text default 'grati'
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p personas%rowtype;
  v_sueldo numeric; v_asig numeric := 0; v_asig_cfg numeric;
  v_sem_ini date; v_sem_fin date;
  v_meses_var int := 0; v_total_var numeric := 0; v_prom_var numeric := 0;
  v_incluir boolean;
begin
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El guard que faltaba desde la 0087.
  -- Estas cuatro funciones son SECURITY DEFINER y están concedidas a
  -- authenticated, y su cuerpo solo comprobaba que la persona exista. Reproducido
  -- contra Postgres local: desde una sesión de integrante devolvían el sueldo
  -- básico, la asignación familiar y los montos de liquidación de un colega.
  --
  -- Es el mismo agujero que la 0090 cerró para fn_planilla_calcular; estas se
  -- quedaron fuera. El guard va DENTRO y no como un revoke, por lo aprendido
  -- ahí: un revoke se deshace la próxima vez que alguien conceda en masa, y un
  -- guard no.
  --
  -- Si algún día se hace una pantalla «mi liquidación», acá se agrega
  -- «or p_persona_id = fn_persona_actual_id()» — con la forma is not true.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  -- Sueldo del tramo vigente en la fecha de referencia (el mes ANTERIOR al
  -- cese, art. 5.3 del D.S. 005-2002-TR).
  select a.salario_mensual_soles into v_sueldo
    from asignaciones_salario a
   where a.persona_id = p_persona_id
     and a.vigente_desde <= p_fecha_ref
     and (a.vigente_hasta is null or a.vigente_hasta >= p_fecha_ref)
   order by a.vigente_desde desc limit 1;

  if v_sueldo is null then
    return jsonb_build_object('error', 'Sin salario asignado vigente al ' || to_char(p_fecha_ref, 'DD/MM/YYYY'));
  end if;

  -- Se lee EXACTAMENTE como la lee el motor de planilla (0069): el valor vive
  -- como {"monto": 113.00}, no como número suelto. Si las dos formas de leerlo
  -- divergieran, la boleta del mes y la liquidación darían asignaciones
  -- distintas para la misma persona.
  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig_cfg
    from configuracion where clave = 'asignacion_familiar';
  if v_p.con_hijos then v_asig := coalesce(v_asig_cfg, 113.00); end if;

  -- ⇩⇩⇩ CAMBIO 0277 ⇩⇩⇩ LA VENTANA QUE CONTIENE LA FECHA, LA DE SU BENEFICIO.
  --
  -- Se rechaza un beneficio desconocido en vez de caer al defecto, por la misma
  -- razón que `fn_devenga` lo hace desde la 0196: si alguien escribe 'ctss', el
  -- error tiene que salir en el momento y no un año después, cuando alguien
  -- descubra que esa llamada llevaba doce meses mirando el semestre de otro.
  if p_beneficio not in ('grati', 'cts', 'vacaciones') then
    raise exception 'Beneficio desconocido: %. Son grati, cts o vacaciones.', p_beneficio;
  end if;

  -- ⇩ LAS VACACIONES SE QUEDAN CON LA VENTANA DE SIEMPRE, y es una corrección
  -- sobre la primera versión de esta migración, que las metió con la CTS.
  --
  -- El argumento para juntarlas era el art. 16 del D. Leg. 713: la remuneración
  -- computable de las vacaciones es «la computable para la CTS». Pero eso dice
  -- qué CONCEPTOS entran, no sobre qué SEIS MESES se mide su regularidad. El
  -- récord vacacional va de aniversario a aniversario y no tiene nada que ver
  -- con el calendario de depósitos de la CTS.
  --
  -- Medido: con la ventana de la CTS, una persona con bonos regulares en
  -- agosto, setiembre y octubre que cesa el 30/11 pierde S/50,00 de su
  -- liquidación, porque esos tres meses caen fuera de nov-abr. Es pagar de
  -- menos, que es justo el error que esta migración no puede cometer.
  --
  -- Así que la CTS estrena ventana y las vacaciones conservan la suya. Si algún
  -- día se decide medirlas contra su propio récord, ese es un cambio con su
  -- propio sustento y su propia migración.
  if p_beneficio in ('grati', 'vacaciones') then
    -- Ley 27735: semestres enero-junio y julio-diciembre.
    v_sem_ini := case when extract(month from p_fecha_ref) <= 6
                      then make_date(extract(year from p_fecha_ref)::int, 1, 1)
                      else make_date(extract(year from p_fecha_ref)::int, 7, 1) end;
    v_sem_fin := (v_sem_ini + interval '6 months' - interval '1 day')::date;
  else
    -- CTS: periodos noviembre-abril y mayo-octubre (D.S. 001-97-TR art. 21,
    -- los que se depositan el 15/05 y el 15/11).
    --
    if extract(month from p_fecha_ref) between 5 and 10 then
      v_sem_ini := make_date(extract(year from p_fecha_ref)::int, 5, 1);
    elsif extract(month from p_fecha_ref) >= 11 then
      v_sem_ini := make_date(extract(year from p_fecha_ref)::int, 11, 1);
    else
      v_sem_ini := make_date(extract(year from p_fecha_ref)::int - 1, 11, 1);
    end if;
    v_sem_fin := (v_sem_ini + interval '6 months' - interval '1 day')::date;
  end if;

  select coalesce((valor #>> '{}')::boolean, true) into v_incluir
    from configuracion where clave = 'liquidacion_incluye_variables';
  v_incluir := coalesce(v_incluir, true);

  if v_incluir then
    -- En cuántos MESES DISTINTOS del semestre percibió BONOS, y cuánto suman.
    -- Solo bonos: `tipo = 'bono'` deja fuera los descuentos, y la lista blanca
    -- de categorías deja fuera la gratificación, la CTS y las vacaciones, que
    -- son beneficios que el sistema deposita, no conceptos remunerativos que
    -- la persona «perciba» en el sentido del art. 16 del D.S. 001-97-TR.
    select count(distinct date_trunc('month', pp.fecha_fin)), coalesce(sum(mp.monto), 0)
      into v_meses_var, v_total_var
      from movimientos_planilla mp
      join periodos_planilla pp on pp.id = mp.periodo_id
     where mp.persona_id = p_persona_id
       -- ⇩⇩⇩ CAMBIO 0277 ⇩⇩⇩ Antes decía «and mp.monto > 0», que no filtra
       -- nada: la tabla tiene CHECK (monto > 0) desde la 0025. Entraban los
       -- descuentos con signo positivo y los tres beneficios que el propio
       -- sistema deposita. Los dos filtros de abajo son el arreglo entero.
       and mp.tipo = 'bono'
       and (mp.categoria is null or mp.categoria = 'otros')
       and pp.fecha_fin between v_sem_ini and v_sem_fin;

    -- La prueba de regularidad: menos de 3 meses, no suma nada.
    if v_meses_var >= 3 then
      v_prom_var := round(v_total_var / 6.0, 2);
    end if;
  end if;

  return jsonb_build_object(
    'sueldo_basico',       round(v_sueldo, 2),
    'asignacion_familiar', round(v_asig, 2),
    'variables_meses',     v_meses_var,
    'variables_total',     round(v_total_var, 2),
    'variables_promedio',  v_prom_var,
    'variables_entran',    (v_meses_var >= 3 and v_incluir),
    'beneficio',           p_beneficio,
    'semestre_desde',      v_sem_ini,
    'semestre_hasta',      v_sem_fin,
    'total',               round(v_sueldo + v_asig + v_prom_var, 2)
  );
end;
$$;


-- Los grants de la 0087 sobreviven a un `create or replace`, pero se vuelven a
-- decir por si esto se pega sobre una base donde alguien los movió. Idempotente.
grant  execute on function fn_remuneracion_computable(uuid, date, text) to authenticated;
revoke execute on function fn_remuneracion_computable(uuid, date, text) from public, anon;


-- ── El aviso de que quedó bien ───────────────────────────────────────────────
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_remuneracion_computable';

  if v_src like '%and mp.tipo = ''bono''%'
     and v_src like '%(mp.categoria is null or mp.categoria = ''otros'')%'
     and v_src like '%fn_es_admin_o_lider() is not true%'
     and v_src not like '%and mp.monto > 0%'
  then
    raise notice '0277 · OK · la base de la liquidacion ya solo admite bonos, y el guard de la 0129 sigue puesto.';
  else
    raise notice '0277 · ATENCION · la funcion NO quedo como esta migracion promete. Revisa que se haya pegado el bloque entero.';
  end if;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- LOS DOS LLAMADORES QUE PIDEN SU PROPIA VENTANA
-- ════════════════════════════════════════════════════════════════════════════
--
-- Los cuerpos de abajo NO se copiaron de ningún archivo: se extrajeron del
-- Postgres local con `pg_get_functiondef`, y ese local reproduce producción al
-- byte —los md5 se pidieron al SQL Editor ANTES de escribir esto, que es la
-- regla que dejó la 0276—:
--
--     fn_cts_trunca          84e6226144339fef7eb1bee079f7de5b   3 129 chars
--     fn_vacaciones_truncas  0d411bdbc3edd858264f80d7a929ddc9   3 059 chars
--
-- De cada uno cambia UNA línea: la llamada gana su beneficio. Todo lo demás es
-- idéntico al byte. `fn_grati_trunca_bruta`, el tercer llamador, NO se toca:
-- su ventana ya era la correcta y el defecto del parámetro se la conserva.

-- ── fn_cts_trunca: una línea, la de la ventana ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_cts_trunca(p_persona_id uuid, p_fecha_cese date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric; v_sexto numeric;
  v_per_ini date; v_desde date; v_m int; v_d int; v_cts numeric; v_anio int;
  v_ventana text; v_anio_pago int; v_ya numeric;   -- CAMBIO 0163
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  if not fn_devenga(p_persona_id, 'cts') then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'No corresponde: su vinculo es ' || v_p.tipo_vinculo || '.');
  end if;
  if p_fecha_cese < (v_p.fecha_ingreso + interval '1 month')::date then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'Menos de un mes de servicios.');
  end if;

  -- Periodo de CTS en curso al cesar.
  v_anio := extract(year from p_fecha_cese)::int;
  v_per_ini := case
    when p_fecha_cese >= make_date(v_anio, 11, 1) then make_date(v_anio, 11, 1)
    when p_fecha_cese >= make_date(v_anio,  5, 1) then make_date(v_anio,  5, 1)
    else make_date(v_anio - 1, 11, 1) end;
  v_desde := greatest(v_per_ini, v_p.fecha_ingreso);

  -- ⇩⇩⇩ CAMBIO 0163 ⇩⇩⇩ Qué ventana es esta, con el nombre que usa el libro.
  -- Una ventana que arranca el 1 de noviembre se deposita el 15 de mayo del año
  -- SIGUIENTE; una que arranca el 1 de mayo, el 15 de noviembre del mismo año.
  if extract(month from v_per_ini)::int = 11 then
    v_ventana := 'cts_may'; v_anio_pago := extract(year from v_per_ini)::int + 1;
  else
    v_ventana := 'cts_nov'; v_anio_pago := extract(year from v_per_ini)::int;
  end if;
  v_ya := fn_beneficio_ya_depositado(p_persona_id, v_ventana, v_anio_pago);

  select meses, dias into v_m, v_d from fn_meses_y_dias(v_desde, p_fecha_cese);

  -- ⇩ CAMBIO 0277 ⇩ Pide SU ventana. Antes recibía la de la gratificación
  -- (ene-jun / jul-dic) y la suya va de noviembre a abril y de mayo a octubre.
  v_rc := fn_remuneracion_computable(p_persona_id, p_fecha_cese, 'cts');
  if v_rc ? 'error' then return jsonb_build_object('aplica', false, 'monto', 0, 'motivo', v_rc->>'error'); end if;

  -- El sexto de la gratificación de MEDIA remuneración = sueldo / 12.
  v_sexto := round(((v_rc->>'sueldo_basico')::numeric / 2.0) / 6.0, 2);
  v_base  := (v_rc->>'total')::numeric + v_sexto;

  -- 15 remuneraciones diarias al año → RC/24 por mes, RC/720 por día.
  v_cts := round(v_base / 24.0 * v_m + v_base / 720.0 * v_d, 2);

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequena empresa: 15 remuneraciones diarias por anio',
    'periodo_desde', v_per_ini, 'contado_desde', v_desde, 'hasta', p_fecha_cese,
    'meses_completos', v_m, 'dias_sueltos', v_d,
    'remuneracion_computable', v_rc,
    'sexto_de_gratificacion', v_sexto,
    'base_de_calculo', round(v_base, 2),
    'formula', 'base/24 x meses + base/720 x dias',
    -- ⇩ CAMBIO 0163 ⇩ Lo devengado se conserva aparte para que la hoja de
    -- liquidación pueda mostrar la resta y no un número que nadie puede cuadrar.
    'devengado', v_cts,
    'ventana', v_ventana,
    'anio_ventana', v_anio_pago,
    'ya_depositado', v_ya,
    'monto', round(v_cts - v_ya, 2)
  );
end;
$function$;

-- ── fn_vacaciones_truncas: una línea, la de la ventana ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vacaciones_truncas(p_persona_id uuid, p_fecha_cese date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric;
  v_aniv date; v_m int; v_d int;
  v_ganados numeric; v_tomados numeric; v_pend numeric; v_monto numeric;
begin
  -- ⇩⇩⇩ CAMBIO 0129 ⇩⇩⇩ El guard que faltaba desde la 0087.
  -- Estas cuatro funciones son SECURITY DEFINER y están concedidas a
  -- authenticated, y su cuerpo solo comprobaba que la persona exista. Reproducido
  -- contra Postgres local: desde una sesión de integrante devolvían el sueldo
  -- básico, la asignación familiar y los montos de liquidación de un colega.
  --
  -- Es el mismo agujero que la 0090 cerró para fn_planilla_calcular; estas se
  -- quedaron fuera. El guard va DENTRO y no como un revoke, por lo aprendido
  -- ahí: un revoke se deshace la próxima vez que alguien conceda en masa, y un
  -- guard no.
  --
  -- Si algún día se hace una pantalla «mi liquidación», acá se agrega
  -- «or p_persona_id = fn_persona_actual_id()» — con la forma is not true.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  if not fn_devenga(p_persona_id, 'vacaciones') then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'No corresponde: su vinculo es ' || v_p.tipo_vinculo || '.');
  end if;
  if p_fecha_cese < (v_p.fecha_ingreso + interval '1 month')::date then
    return jsonb_build_object('aplica', false, 'monto', 0,
      'motivo', 'Menos de un mes de servicios (art. 23 D.S. 012-92-TR).');
  end if;

  -- Último aniversario de ingreso antes del cese: ahí arranca el récord trunco.
  v_aniv := (v_p.fecha_ingreso
             + (make_interval(years => (extract(year from age(p_fecha_cese, v_p.fecha_ingreso))::int))))::date;
  select meses, dias into v_m, v_d from fn_meses_y_dias(v_aniv, p_fecha_cese);

  -- ⇩ CAMBIO 0277 ⇩ Pide SU ventana. Antes recibía la de la gratificación
  -- (ene-jun / jul-dic) y la suya va de noviembre a abril y de mayo a octubre.
  v_rc := fn_remuneracion_computable(p_persona_id, p_fecha_cese, 'vacaciones');
  if v_rc ? 'error' then return jsonb_build_object('aplica', false, 'monto', 0, 'motivo', v_rc->>'error'); end if;
  v_base := (v_rc->>'total')::numeric;

  v_ganados := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);

  select coalesce(sum(least(v.fecha_fin, p_fecha_cese) - greatest(v.fecha_inicio, v_aniv) + 1), 0)
    into v_tomados
    from vacaciones v
   where v.persona_id = p_persona_id
     and v.fecha_fin >= v_aniv and v.fecha_inicio <= p_fecha_cese;

  v_pend  := greatest(0, v_ganados - v_tomados);   -- nunca negativo
  v_monto := round((v_base / 2.0) * v_pend / 15.0, 2);

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequena empresa: 15 dias por anio',
    'aniversario', v_aniv, 'hasta', p_fecha_cese,
    'meses_completos', v_m, 'dias_sueltos', v_d,
    'remuneracion_computable', v_rc,
    'dias_ganados', v_ganados, 'dias_gozados', v_tomados, 'dias_pendientes', v_pend,
    'valor_dia', round(v_base / 30.0, 2),
    'formula', '(RC / 2) x dias_pendientes / 15',
    'monto', v_monto
  );
end;
$function$;

-- ════════════════════════════════════════════════════════════════════════════
-- EL CANDADO: NINGÚN BONO CRUZA EL UMBRAL DE REGULARIDAD SIN QUE ALGUIEN LO DIGA
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUÉ HACE. Rechaza el bono que sería el TERCER MES DISTINTO con bono dentro de
-- cualquiera de las dos ventanas que contienen su fecha —la de la gratificación
-- y la de la CTS—. Tres meses es exactamente el umbral del art. 16 del D.S.
-- 001-97-TR: a partir de ahí ese bono entra en la base de la gratificación, la
-- CTS y las vacaciones, y multiplica su coste.
--
-- POR QUÉ BLOQUEA Y NO AVISA. Es la decisión de Felipe del 2026-08-22, tomada
-- sabiendo lo que cuesta: un candado que estorba se acaba desactivando. Se
-- construye bloqueante, y la salida NO es apagarlo para todos, sino pasar por
-- encima UNA VEZ dejando dicho por qué:
--
--     select fn_permitir_bono_regular('<uuid>', '<motivo>');
--
-- Es la misma forma que ya tiene reabrir un día cerrado: la puerta existe, pero
-- hay que empujarla a propósito y queda tu nombre en ella. Un candado sin
-- ninguna salida se desactiva entero el primer día que estorba, y entonces deja
-- de proteger para siempre en vez de por un caso.
--
-- POR QUÉ NO CUENTA LOS DESCUENTOS NI LOS BENEFICIOS DEL SISTEMA. Porque desde
-- esta misma migración tampoco los cuenta `fn_remuneracion_computable`. Si el
-- candado contara más cosas que el cálculo, frenaría movimientos que no cuestan
-- nada; si contara menos, dejaría pasar los que sí. Cuentan lo mismo, y esa es
-- la única forma de que no se separen.
--
-- LO QUE NO HACE, a propósito: no toca los movimientos que YA existen. Un
-- candado que rechaza al insertar no puede juzgar el pasado, y aplicarlo hacia
-- atrás dejaría a la pantalla de Planilla sin poder guardar nada en una persona
-- que ya cruzó el umbral.

create table if not exists bonos_umbral_permitido (
  id           uuid primary key default gen_random_uuid(),
  persona_id   uuid not null references personas(id),
  motivo       text not null,
  autorizado_por uuid references personas(id),
  created_at   timestamptz not null default now(),
  usado_at     timestamptz,
  constraint bonos_umbral_motivo_check check (length(trim(motivo)) >= 10)
);

comment on table bonos_umbral_permitido is
  'Permisos de un solo uso para que un bono cruce el umbral de 3 meses del art. 16 del D.S. 001-97-TR. Lo crea fn_permitir_bono_regular con motivo obligatorio; el trigger lo consume y lo marca usado.';

alter table bonos_umbral_permitido enable row level security;
drop policy if exists bonos_umbral_admin on bonos_umbral_permitido;
create policy bonos_umbral_admin on bonos_umbral_permitido
  for select to authenticated using (fn_es_admin_o_lider() is true);

-- ── Las dos ventanas que contienen una fecha ────────────────────────────────
-- Una sola definición, y la usan el candado y nadie más por ahora. Si mañana la
-- necesita otro sitio, se pregunta acá en vez de volver a escribirla.
create or replace function fn_ventanas_de_regularidad(p_fecha date)
returns table(nombre text, ini date, fin date)
language sql immutable as $$
  select 'gratificación'::text,
         case when extract(month from p_fecha) <= 6
              then make_date(extract(year from p_fecha)::int, 1, 1)
              else make_date(extract(year from p_fecha)::int, 7, 1) end,
         case when extract(month from p_fecha) <= 6
              then make_date(extract(year from p_fecha)::int, 6, 30)
              else make_date(extract(year from p_fecha)::int, 12, 31) end
  union all
  select 'CTS'::text, w.ini, (w.ini + interval '6 months' - interval '1 day')::date
  from (select case
                 when extract(month from p_fecha) between 5 and 10
                   then make_date(extract(year from p_fecha)::int, 5, 1)
                 when extract(month from p_fecha) >= 11
                   then make_date(extract(year from p_fecha)::int, 11, 1)
                 else make_date(extract(year from p_fecha)::int - 1, 11, 1)
               end as ini) w;
$$;

grant execute on function fn_ventanas_de_regularidad(date) to authenticated;

-- ── El permiso de un solo uso ───────────────────────────────────────────────
create or replace function fn_permitir_bono_regular(p_persona_id uuid, p_motivo text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede autorizar un bono que cruce el umbral.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 10 then
    raise exception 'El motivo es obligatorio y tiene que explicar por que este bono cruza el umbral.';
  end if;
  insert into bonos_umbral_permitido (persona_id, motivo, autorizado_por)
  values (p_persona_id, trim(p_motivo), fn_persona_actual_id())
  returning id into v_id;
  return v_id;
end;
$$;

grant  execute on function fn_permitir_bono_regular(uuid, text) to authenticated;
revoke execute on function fn_permitir_bono_regular(uuid, text) from public, anon;

-- ── El candado ──────────────────────────────────────────────────────────────
create or replace function fn_trg_bono_umbral()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_fin date; v_meses int; v_ventana text; v_ini date; v_ffin date; v_permiso uuid;
begin
  -- Solo los bonos que de verdad cuentan para la base. Los descuentos y los
  -- beneficios que deposita el sistema no cuentan en el cálculo desde esta
  -- misma migración, así que tampoco cuentan acá.
  if new.tipo <> 'bono' then return new; end if;
  if new.categoria is not null and new.categoria <> 'otros' then return new; end if;

  select pp.fecha_fin into v_fin from periodos_planilla pp where pp.id = new.periodo_id;
  if v_fin is null then return new; end if;

  for v_ventana, v_ini, v_ffin in select nombre, ini, fin from fn_ventanas_de_regularidad(v_fin) loop
    select count(distinct date_trunc('month', pp.fecha_fin)) into v_meses
      from movimientos_planilla mp
      join periodos_planilla pp on pp.id = mp.periodo_id
     where mp.persona_id = new.persona_id
       and mp.tipo = 'bono'
       and (mp.categoria is null or mp.categoria = 'otros')
       and pp.fecha_fin between v_ini and v_ffin
       and date_trunc('month', pp.fecha_fin) <> date_trunc('month', v_fin);

    -- +1 por el que se está insertando, si cae en un mes que aún no contaba.
    if v_meses + 1 >= 3 then
      select id into v_permiso from bonos_umbral_permitido
       where persona_id = new.persona_id and usado_at is null
       order by created_at limit 1;

      if v_permiso is null then
        raise exception using
          errcode = 'P0001',
          message = format(
            'Este bono seria el mes %s con bono en la ventana de %s (%s al %s). '
            || 'A partir del tercer mes la ley lo mete en la base de la gratificacion, '
            || 'la CTS y las vacaciones, y se paga muchas veces su valor al cesar.',
            v_meses + 1, v_ventana, to_char(v_ini,'DD/MM/YYYY'), to_char(v_ffin,'DD/MM/YYYY')),
          hint = 'Si aun asi corresponde pagarlo, autorizalo dejando el motivo escrito: '
                 || 'select fn_permitir_bono_regular(''' || new.persona_id || ''', ''por que...'');';
      end if;

      update bonos_umbral_permitido set usado_at = now() where id = v_permiso;
      return new;
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_bono_umbral on movimientos_planilla;
create trigger trg_bono_umbral
  before insert on movimientos_planilla
  for each row execute function fn_trg_bono_umbral();

insert into migraciones_aplicadas (numero, nombre)
values (277, 'ni_los_descuentos_ni_los_beneficios_inflan_la_liquidacion')
on conflict (numero) do nothing;
