-- ============================================================================
-- 0498 · Las vacaciones descuentan la licencia sin goce
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el contador de vacaciones lea lo que la 0497 permite registrar. Con el
--   interruptor de `licencia_sin_goce` ENCENDIDO, los días de vacaciones —el saldo,
--   la liquidación al cesar, la pantalla de Vacaciones y la de Provisiones— restan
--   los días que la persona estuvo fuera del servicio. Con el interruptor APAGADO,
--   que es como nace, NADA cambia: ni un día ni un sol.
--
-- QUÉ ASUME
--   · Que la 0497 está pegada (la guardia de abajo lo comprueba y para si no).
--   · Que el laboralista responde que los días de una licencia sin goce NO cuentan
--     como servicio para ganar vacaciones. Mientras no responda, el interruptor
--     sigue apagado y esta migración es inerte. Es lo que la hace segura de pegar
--     ANTES de tener la respuesta: pegarla no decide nada, encender el interruptor sí.
--
-- ── LAS CUATRO FUNCIONES, Y QUÉ LE CAMBIA A CADA UNA ─────────────────────────
--
--   fn_vacaciones_saldo_interno   LA QUE MUEVE PLATA. Los años completos, el trunco
--   (0357)                        y el vencimiento del récord se cuentan desde el
--                                 ingreso EFECTIVO. De aquí leen el saldo, la
--                                 liquidación al cesar y el aviso de vencimiento.
--                                 Devuelve dos claves nuevas —`fecha_ingreso_efectiva`
--                                 y `dias_fuera_del_servicio`— para que quien lea el
--                                 número vea de dónde sale.
--   fn_vacaciones_truncas         La hoja de liquidación. El dinero YA seguía a la
--   (0341)                        de arriba (paga `días pendientes`, que salen del
--                                 saldo); lo que cambia son los campos que la hoja
--                                 MUESTRA —aniversario, meses, días sueltos y días
--                                 del trunco—, para que no diga un trunco y pague
--                                 otro. Dos líneas.
--   fn_vacaciones_resumen         La pantalla de Vacaciones. `dias_ganados` resta los
--   (0491)                        días fuera y la BASE DE HORAS esperadas también:
--                                 sin eso, quien vuelve de una licencia salía con un
--                                 «ritmo» castigado por una ausencia que se pactó.
--   fn_provisiones                SOLO el número de días que muestra (`vac_dias`).
--   (0491)                        La reserva en soles no necesita cambio: un día
--                                 fuera no tiene `pago_dia`, así que ya no devengaba.
--
--   Cada cambio es UNA expresión: `fecha_ingreso` pasa a `fn_fecha_ingreso_efectiva`,
--   o se resta `fn_dias_suspendidos`. Cuando no hay ninguna interrupción esas dos
--   funciones devuelven `fecha_ingreso` y cero, así que el resultado es el de siempre.
--
-- ── POR QUÉ UN INGRESO EFECTIVO Y NO «OTRA CUENTA» ───────────────────────────
--   La pregunta al laboralista parecía tener dos respuestas —¿se restan los días o se
--   corre el aniversario?— y son la MISMA cuenta. Si la persona estuvo fuera 71 días,
--   correr su fecha de ingreso 71 días hacia adelante da el mismo saldo que restarle
--   71 días al calendario, y da el mismo vencimiento. Por eso hay una sola regla en una
--   sola función y las cuatro la leen: dos copias de la misma cuenta es como nacieron
--   el defecto de la 0283 y la duplicada de la 0297/0299.
--   La única pregunta legal que queda es binaria: ¿la licencia sin goce cuenta como
--   servicio, sí o no? Y su respuesta es un interruptor, no código.
--
-- ── MEDIDO, NO RAZONADO (Postgres desechable, fechas inventadas) ──────────────
--   Dos personas idénticas —ingreso 15/01/2025, sueldo S/1,950— y Ana estuvo 71 días
--   fuera. Preguntadas el 10/01/2026:
--
--                                   APAGADO       ENCENDIDO
--     saldo de vacaciones · Ana      14.88 días    11.88 días     (Beto: 14.88 siempre)
--     liquidación al cesar · Ana     S/967.20      S/772.20       (Beto: S/967.20 siempre)
--     reserva en soles · Ana         igual         igual
--
--   La diferencia son 3.00 días y S/195.00, que es exactamente 3 × (1,950 ÷ 2 ÷ 15).
--   `fn_meses_y_dias` cuenta los días contando ambos extremos, por eso 27 y no 26.
--
--   Sin cambio con el interruptor apagado: las 44 pruebas que ya existían sobre estas
--   funciones —565 aserciones— dan EXACTAMENTE lo mismo antes y después. Y la prueba 392
--   se comprobó que puede fallar: devolviendo cada función a su cuerpo original, se
--   ponen en rojo las aserciones de esa función y de ninguna otra.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, A PROPÓSITO ───────────────────────────────
--   1 · NO le descuenta sueldo a nadie. La planilla no lee `ausencias` (medido en la
--       0247): para quien cobra por horas marcadas, un día sin marca ya pagaba cero;
--       para un SUELDO FIJO una licencia sin goce no le baja el sueldo, y esta
--       migración no lo cambia —solo cambia los días de vacaciones—. Si se registra una
--       licencia sin goce a alguien con sueldo fijo, el descuento hay que hacerlo aparte.
--   2 · NO toca la ventana de la reserva. `fn_provisiones` y `fn_vacaciones_resumen`
--       siguen midiendo «el año» desde el último aniversario de CALENDARIO, y ahí la
--       reserva vuelve a cero el día del aniversario aunque los días ganados sigan sin
--       gozar. Es un defecto aparte y anterior a esto; con una licencia registrada solo
--       se nota más. Se dice acá para que nadie lo atribuya a esta migración.
--   3 · NO cambia el mínimo de «un mes de servicios» de la liquidación ni los años del
--       libro de desembolsos: hablan de fechas de calendario, y siguen con el ingreso REAL.
--
-- ── LA GUARDIA (sección 0) ───────────────────────────────────────────────────
--   La regla de la casa pide el md5 de PRODUCCIÓN antes de escribir una migración que
--   reescribe una función. Esta se escribió sin acceso a producción, así que la
--   verificación se movió al único momento en que no caduca: AL PEGAR. La sección 0
--   compara cada cuerpo que hay en la base contra el que se leyó para escribir esto
--   (los del REPOSITORIO al 2026-09-29, árbol en 9416b4a3) y PARA sin aplicar nada si
--   no coincide, antes del primer `create or replace`. Acepta tal cual, sin comentarios,
--   y cualquiera de las dos con `\r` por línea; cualquier otra cosa es otra versión.
--   Probado con tres casos: una versión distinta (aborta y no deja nada aplicado), el
--   mismo código con `\r` (pasa) y repegarla sobre sí misma (aborta).
--
--   Aun así, antes de pegar: `./scripts/donde-vive.sh` de cada una, y mira si entre tanto
--   otra sesión fusionó una migración que las reescribe. La guardia protege de pegar
--   sobre una versión desconocida; no de que la desconocida sea más nueva que ésta.
--
-- ── CÓMO SE PEGA ─────────────────────────────────────────────────────────────
--   UNA sola vez, y después de la 0497. Repegarla PARA con un mensaje —la guardia ve el
--   cuerpo ya cambiado—, y es lo que se quiere: una migración que reescribe cuerpos
--   enteros no debe pegarse dos veces sobre una versión posterior que la haya cambiado.
--   Para comprobar que quedó:
--
--     select proname, (prosrc like '%CAMBIO 0498%') as cambiada
--       from pg_proc
--      where proname in ('fn_vacaciones_saldo_interno', 'fn_vacaciones_truncas',
--                        'fn_vacaciones_resumen', 'fn_provisiones');   -- cuatro true
--
-- ── CÓMO SE ENCIENDE Y SE APAGA ──────────────────────────────────────────────
--   Cuando el laboralista confirme, SIN migración y con efecto inmediato sobre todo lo ya
--   registrado:
--     update tipos_ausencia set suspende_record = true  where codigo = 'licencia_sin_goce';
--   y para apagarlo, la misma línea con `false`.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   Lo barato: apagar el interruptor (arriba); las cuatro funciones vuelven a dar lo de
--   siempre sin tocar nada más. Lo completo: volver a pegar el cuerpo que cada función
--   tenía ANTES —`./scripts/donde-vive.sh` dice de qué migración— y borrar las dos
--   claves nuevas que devuelve el saldo, que nadie más lee.
--
-- SE ROMPE SI
--   · Alguien aprueba por error una licencia sin goce: los días de esa persona bajan.
--     Se anula con motivo (como cualquier ausencia) y vuelven; queda el rastro.
--   · Se registra la licencia a alguien con sueldo fijo esperando que también le baje el
--     sueldo: baja el saldo de vacaciones y el sueldo sigue igual (ver 1 arriba).
--   · El laboralista responde lo contrario: se apaga el interruptor y esta migración
--     queda como estaba antes, sin efecto.
-- ============================================================================

-- ── 0 · La guardia: esta migración no se pega sobre un cuerpo que no reconoce ─
-- Reescribe cuatro funciones enteras. Si producción tiene una versión que el
-- repositorio no conoce, pegar encima la borraría en silencio (así se perdieron
-- las 0275 y 0257 en otra ocasión). Por eso la migración se revisa a sí misma:
-- compara el cuerpo que HAY en esta base contra el que se leyó para escribirla y,
-- si no coincide, PARA sin aplicar nada — antes del primer `create or replace`.
--
-- Acepta cuatro formas del MISMO código, porque las cuatro se han visto en
-- producción y ninguna es un accidente: tal cual; sin comentarios (la mitad de
-- las funciones se pegaron sin ellos); y cualquiera de las dos con `\r` por
-- línea (pegar desde Windows). Cualquier otra cosa es OTRA versión: parar.
do $guardia$
declare
  r   record;
  v_src text;
  v_h1 text; v_h2 text; v_h3 text; v_h4 text;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'tipos_ausencia'
                    and column_name = 'suspende_record')
     or to_regprocedure('public.fn_dias_suspendidos(uuid,date,date)') is null
     or to_regprocedure('public.fn_fecha_ingreso_efectiva(uuid,date)') is null then
    raise exception '0498 · PARA. Falta la 0497 (la columna suspende_record o sus dos funciones). Pégala primero. No se aplicó nada.';
  end if;

  for r in
    select * from (values
      ('fn_vacaciones_saldo_interno(uuid,date)', '3986616e29da26458b43035eae6139d3', '3986616e29da26458b43035eae6139d3', 2062),
      ('fn_vacaciones_truncas(uuid,date)', 'f4b999990f36f2471dce7ba8f053b27f', '1ac4f5f78e9870390ea12f0be7f9f62e', 11932),
      ('fn_vacaciones_resumen(date)', '7b4ee901b5ae36d1897daf2c970aee9a', 'ef2b94afec51c0c22ed2a6e9a63b236c', 5327),
      ('fn_provisiones(date,date)', 'e36c150c5db587354d48d6b0916273bb', '62a7146b113b6a061710b79bf9d038ef', 50371)
    ) as t(firma, tal_cual, sin_comentarios, largo)
  loop
    select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.' || r.firma);
    if v_src is null then
      raise exception '0498 · PARA. % no existe en esta base. No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh.', r.firma;
    end if;

    select md5(v_src),
           md5(array_to_string(array(
             select regexp_replace(l, '[[:space:]]*--.*$', '')
               from unnest(string_to_array(v_src, chr(10))) as l
              where btrim(l) not like '--%'), chr(10))),
           md5(replace(v_src, chr(13), '')),
           md5(array_to_string(array(
             select regexp_replace(l, '[[:space:]]*--.*$', '')
               from unnest(string_to_array(replace(v_src, chr(13), ''), chr(10))) as l
              where btrim(l) not like '--%'), chr(10)))
      into v_h1, v_h2, v_h3, v_h4;

    if not (r.tal_cual in (v_h1, v_h2, v_h3, v_h4) or r.sin_comentarios in (v_h1, v_h2, v_h3, v_h4)) then
      raise exception '0498 · PARA. % en esta base es % (% caracteres) y se esperaba % o % (% caracteres). Es OTRA versión: pegar esto la borraría. No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh y rehaz la migración sobre la versión vigente.',
        r.firma, v_h1, length(v_src), r.tal_cual, r.sin_comentarios, r.largo;
    end if;
    raise notice '0498 · ok: % coincide con el repositorio.', r.firma;
  end loop;
end
$guardia$;

-- ── 1 · fn_vacaciones_saldo_interno ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vacaciones_saldo_interno(p_persona_id uuid, p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_p        personas%rowtype;
  v_as_of    date;
  v_anios    int;
  v_m int; v_d int;
  v_trunco   numeric;
  v_ganados  numeric;
  v_tomados  numeric;
  v_pend     numeric;
  v_k        int;
  v_vencidos int;
  v_vence    date;
  v_ing      date;   -- CAMBIO 0498: desde cuándo corre el servicio EFECTIVO
  v_fuera    integer; -- CAMBIO 0498: días fuera del servicio hasta p_as_of
begin
  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  v_as_of := coalesce(p_as_of, fn_hoy_lima());

  if not fn_devenga(p_persona_id, 'vacaciones') then
    return jsonb_build_object('aplica', false,
      'motivo', 'No devenga vacaciones: su vínculo es ' || v_p.tipo_vinculo || '.');
  end if;

  if v_as_of < v_p.fecha_ingreso then
    return jsonb_build_object('aplica', false, 'motivo', 'Todavía no había ingresado.');
  end if;

  -- ⇩⇩⇩ CAMBIO 0498 ⇩⇩⇩ Los años y el trunco se cuentan desde el ingreso EFECTIVO:
  -- el ingreso real corrido tantos días como la persona estuvo fuera del servicio
  -- (licencia sin goce APROBADA, con el interruptor encendido en el catálogo).
  -- Sin ninguna interrupción —o con el interruptor apagado, que es como nace—
  -- `fn_fecha_ingreso_efectiva` devuelve EXACTAMENTE `fecha_ingreso`, y esta cuenta
  -- da lo mismo que antes, al día. Decía:
  --     v_anios := floor(extract(year from age(v_as_of, v_p.fecha_ingreso)))::int;
  --     ... fn_meses_y_dias((v_p.fecha_ingreso + make_interval(years => v_anios))::date, v_as_of);
  v_ing   := fn_fecha_ingreso_efectiva(p_persona_id, v_as_of);
  v_fuera := fn_dias_suspendidos(p_persona_id, v_p.fecha_ingreso, v_as_of);
  v_anios := floor(extract(year from age(v_as_of, v_ing)))::int;
  select meses, dias into v_m, v_d
    from fn_meses_y_dias((v_ing + make_interval(years => v_anios))::date, v_as_of);
  v_trunco  := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);
  v_ganados := round(15.0 * v_anios + v_trunco, 2);

  select coalesce(sum(least(v.fecha_fin, v_as_of) - greatest(v.fecha_inicio, v_p.fecha_ingreso) + 1), 0)
    into v_tomados
    from vacaciones v
   where v.persona_id = p_persona_id
     and v.fecha_fin >= v_p.fecha_ingreso and v.fecha_inicio <= v_as_of;

  v_pend := greatest(0, v_ganados - v_tomados);

  v_k        := floor(v_pend / 15.0)::int;
  v_vencidos := greatest(v_k - 1, 0);

  if v_k > 0 then
    -- CAMBIO 0498: el récord cierra —y por tanto vence— desde el ingreso efectivo.
    v_vence := (v_ing + make_interval(years => v_anios + 1))::date;
  end if;

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequeña empresa: 15 días por año',
    'as_of', v_as_of,
    'fecha_ingreso', v_p.fecha_ingreso,
    -- CAMBIO 0498: para que quien lea el saldo vea de dónde sale el número.
    'fecha_ingreso_efectiva', v_ing,
    'dias_fuera_del_servicio', v_fuera,
    'anios_completos', v_anios,
    'dias_ganados', v_ganados,
    'dias_gozados', v_tomados,
    'dias_pendientes', v_pend,
    'records_sin_gozar', v_k,
    'records_vencidos', v_vencidos,
    'vence_el', v_vence,
    'dias_para_vencer', case when v_vence is null then null else (v_vence - v_as_of) end
  );
end;
$function$
;

-- ── 2 · fn_vacaciones_truncas ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vacaciones_truncas(p_persona_id uuid, p_fecha_cese date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_p personas%rowtype; v_rc jsonb; v_base numeric;
  v_aniv date; v_m int; v_d int;
  v_ing date;   -- CAMBIO 0498: ingreso efectivo al cese
  v_ganados numeric; v_tomados numeric; v_pend numeric; v_monto numeric;
  v_anios int; v_trunco numeric; v_ya_pagado numeric := 0; v_a int;
  v_vencidos int := 0; v_saldo jsonb;
  v_regimen_pension text; v_tasa_afp numeric; v_descuento_afp numeric;   -- CAMBIO 0341
  v_monto_bruto numeric;                                                -- CAMBIO 0341
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
  -- ⇩⇩⇩ CAMBIO 0498 ⇩⇩⇩ Desde el ingreso EFECTIVO, el mismo que usa
  -- `fn_vacaciones_saldo_interno` para los días pendientes: la hoja de liquidación
  -- no puede decir un trunco (meses y días) y pagar otro. Con el interruptor
  -- apagado o sin interrupciones, `v_ing` = `fecha_ingreso` y nada cambia. Decía:
  --     v_aniv := (v_p.fecha_ingreso + make_interval(years => age(p_fecha_cese, v_p.fecha_ingreso) ...
  -- Lo demás sigue con el ingreso REAL a propósito: el mínimo de «un mes de
  -- servicios» y los años del libro de desembolsos hablan de fechas de calendario.
  v_ing  := fn_fecha_ingreso_efectiva(p_persona_id, p_fecha_cese);
  v_aniv := (v_ing
             + (make_interval(years => (extract(year from age(p_fecha_cese, v_ing))::int))))::date;
  select meses, dias into v_m, v_d from fn_meses_y_dias(v_aniv, p_fecha_cese);

  -- ⇩ CAMBIO 0278 ⇩ Pide SU ventana. Antes recibía la de la gratificación
  -- (ene-jun / jul-dic) y la suya va de noviembre a abril y de mayo a octubre.
  v_rc := fn_remuneracion_computable(p_persona_id, p_fecha_cese, 'vacaciones');
  if v_rc ? 'error' then return jsonb_build_object('aplica', false, 'monto', 0, 'motivo', v_rc->>'error'); end if;
  v_base := (v_rc->>'total')::numeric;

  -- ⇩⇩⇩ CAMBIO 0283 ⇩⇩⇩ SE CUENTA TODA SU VIDA, NO SOLO EL RECORD EN CURSO.
  --
  -- Antes esta cuenta empezaba en el ultimo aniversario y miraba solo el
  -- trunco. Dos cosas se caian por ese borde:
  --
  --   1 · LOS RECORDS COMPLETOS SIN GOZAR no aparecian en ninguna linea de la
  --       hoja. Quien tenia dos anios sin tomar vacaciones cobraba el trunco y
  --       nada mas: 30 dias se evaporaban.
  --
  --   2 · Y al reves, el que mas dolia: los dias que gano en el record ANTERIOR
  --       y se tomo DESPUES de su aniversario -que es cuando la ley manda
  --       tomarlos- caian dentro de la ventana y se le restaban del record
  --       NUEVO. Medido el 2026-08-22 con dos personas identicas: la que gozo
  --       sus 15 dias cobraba S/0,00 y la que nunca gozo, S/812,50. Se le
  --       cobraba el mismo descanso dos veces, y solo a quien lo tomo.
  --
  -- LA CUENTA ACUMULADA NO PUEDE PAGAR DOS VECES, y esa es la razon de que sea
  -- esta y no un reparto por records. Cada dia que la persona se tomo en su
  -- vida se resta UNA vez del total que gano en su vida. No hay ventana donde
  -- un dia pueda caer fuera y quedar sin descontar, ni donde pueda caer dos
  -- veces. Es la misma cuenta que la pantalla de Vacaciones usa desde julio de
  -- 2026; lo que faltaba era que la liquidacion preguntara igual.
  --
  -- LO QUE ASUME, Y SE COMPROBO ANTES DE ESCRIBIRLO: que el historial de goces
  -- esta completo. Si alguien se tomo vacaciones y no estan registradas, esta
  -- cuenta se las pagaria como si nunca las hubiera gozado. Medido en
  -- produccion el 2026-08-22: de las 20 personas activas, las cuatro que han
  -- cumplido un anio se tomaron EXACTAMENTE sus 15 dias -15 ganados, 15
  -- gozados, saldo cero las cuatro- y las 16 restantes no han cumplido el
  -- primer anio. Nadie tiene saldo pendiente. El historial cuadra.
  -- ⇩⇩⇩ CAMBIO 0297 ⇩⇩⇩ El saldo se PREGUNTA, no se recalcula acá.
  --
  -- El cuerpo que estaba en estas lineas se mudo entero a fn_vacaciones_saldo,
  -- sin cambiarle una coma: los mismos dias ganados sobre toda la vida, los
  -- mismos gozados contados desde el ingreso sobre la vista `vacaciones`.
  --
  -- Se mudo porque el aviso preventivo necesita exactamente esta cuenta, y una
  -- segunda copia es como nacio el defecto que la 0283 vino a arreglar: la
  -- pantalla y la liquidacion contando distinto, S/905,38 medidos entre tres
  -- personas.
  v_saldo   := fn_vacaciones_saldo(p_persona_id, p_fecha_cese);
  v_anios   := (v_saldo->>'anios_completos')::int;
  v_ganados := (v_saldo->>'dias_ganados')::numeric;
  v_tomados := (v_saldo->>'dias_gozados')::numeric;
  v_pend    := (v_saldo->>'dias_pendientes')::numeric;
  v_trunco  := round(15.0 * v_m / 12.0 + 15.0 * v_d / 360.0, 2);
  v_monto := round((v_base / 2.0) * v_pend / 15.0, 2);

  -- ⇩⇩⇩ CAMBIO 0283 ⇩⇩⇩ LO QUE EL LIBRO DICE QUE YA SE PAGO.
  --
  -- `fn_grati_trunca` y `fn_cts_trunca` descuentan el libro de desembolsos
  -- desde la 0163. Esta no, aunque el libro TIENE ventana 'vacaciones' en su
  -- check desde la 0121. Hoy no cuesta nada -no hay ninguna anotada- pero
  -- dejarlo asi mientras esta migracion empieza a pagar records completos es
  -- abrir la puerta al doble pago justo cuando hay algo que duplicar.
  --
  -- El anio es el del PAGO, mismo criterio que las otras dos. Se recorren los
  -- anios que la persona pudo cobrar vacaciones, desde su ingreso hasta el cese.
  for v_a in extract(year from v_p.fecha_ingreso)::int .. extract(year from p_fecha_cese)::int loop
    v_ya_pagado := v_ya_pagado + fn_beneficio_ya_depositado(p_persona_id, 'vacaciones', v_a);
  end loop;
  v_monto := greatest(0, round(v_monto - v_ya_pagado, 2));

  -- ⇩⇩⇩ CAMBIO 0341 ⇩⇩⇩ LAS VACACIONES TRUNCAS SÍ LLEVAN APORTE A PENSIÓN.
  --
  -- Sustituyen el sueldo del descanso que no se llegó a gozar, y el art. 19
  -- del D.S. 001-97-TR no las lista entre los conceptos no remunerativos: son
  -- remuneración computable para pensión igual que cualquier mes trabajado.
  -- (`fn_grati_trunca` y `fn_cts_trunca` correctamente NO descuentan — la
  -- gratificación está inafecta por la Ley 29351/30334 y la CTS por el art. 9
  -- del mismo D.S. — así que de las tres truncas, esta era la única que sí
  -- debía llevar el descuento y no lo llevaba.)
  --
  -- Se descuenta sobre lo que queda DESPUÉS de restar lo ya pagado por el
  -- libro, no antes: lo ya pagado es una transferencia que ya ocurrió, con
  -- cualquier tratamiento que haya tenido en su momento, y el aporte de HOY
  -- corresponde solo a la plata que se está desembolsando en ESTA liquidación.
  --
  -- La tasa se busca exactamente como en fn_planilla_calcular (0339): régimen
  -- vigente en la fecha (acá, el cese) vía asignaciones_regimen_pension con
  -- personas.regimen_pension de respaldo, y sobre ese régimen, la tasa
  -- vigente en esa misma fecha en tasas_pension, con configuracion.tasa_afp
  -- como último respaldo. Nadie se queda sin descuento por un dato faltante,
  -- y quien no tenga régimen asignado resuelve a la tasa global (hoy 0, por
  -- eso ninguna prueba existente de esta función se mueve con este cambio).
  v_monto_bruto := v_monto;

  select coalesce(
           (select h.regimen
              from asignaciones_regimen_pension h
             where h.persona_id = p_persona_id
               and h.vigente_desde <= p_fecha_cese
               and (h.vigente_hasta is null or h.vigente_hasta >= p_fecha_cese)
             order by h.vigente_desde desc
             limit 1),
           v_p.regimen_pension)
    into v_regimen_pension;

  select tp.aporte + tp.comision + tp.prima
    into v_tasa_afp
  from tasas_pension tp
  where tp.regimen = v_regimen_pension
    and tp.vigente_desde <= p_fecha_cese
    and (tp.vigente_hasta is null or tp.vigente_hasta >= p_fecha_cese)
  order by tp.vigente_desde desc
  limit 1;

  if v_tasa_afp is null then
    select coalesce((valor->>'tasa')::numeric, 0) into v_tasa_afp
    from configuracion where clave = 'tasa_afp';
    if v_tasa_afp is null then v_tasa_afp := 0; end if;
  end if;

  v_descuento_afp := round(v_monto_bruto * v_tasa_afp, 2);
  v_monto := greatest(0, round(v_monto_bruto - v_descuento_afp, 2));
  -- ⇩⇩⇩ fin CAMBIO 0341 ⇩⇩⇩

  -- ⇩⇩⇩ CAMBIO 0283 ⇩⇩⇩ AVISA DE UN RECORD VENCIDO, NO LO INDEMNIZA.
  --
  -- El art. 23 del D. Leg. 713 manda una indemnizacion -otra remuneracion
  -- entera- cuando un record vence sin gozarse. El sistema NO la calcula, por
  -- decision de Felipe del 2026-08-22, y con razon: tiene excepciones que el
  -- sistema no sabe distinguir -el personal de direccion queda fuera- y
  -- calcularla mal cuesta mucho en cualquiera de los dos sentidos.
  --
  -- Lo que hace es DECIRLO, con la norma al lado, para que quien arma la
  -- liquidacion lo vea y decida. Y hay algo mas importante que eso: si esto
  -- aparece el dia del cese, ya es tarde. La forma de que no exista nunca es
  -- avisar ANTES de que el record venza, no en la hoja final.
  --
  -- ⇩⇩⇩ CAMBIO 0297 ⇩⇩⇩ VENCIDOS, no «sin gozar». Contaba de mas.
  --
  -- `floor(saldo / 15)` son los records COMPLETOS SIN GOZAR. El ultimo de ellos
  -- todavia tiene un anio por delante para gozarse, asi que no esta vencido.
  -- Medido: catorce dias despues de cerrar su primer record, esta hoja decia que
  -- la empresa podia deberle una remuneracion entera de indemnizacion. No la
  -- debe. La resta de 1 es toda la correccion, y ahora vive en el saldo.
  v_vencidos := (v_saldo->>'records_vencidos')::int;

  return jsonb_build_object(
    'aplica', true,
    'regimen', 'MYPE pequena empresa: 15 dias por anio',
    'aniversario', v_aniv, 'hasta', p_fecha_cese,
    'meses_completos', v_m, 'dias_sueltos', v_d,
    'remuneracion_computable', v_rc,
    'anios_completos', v_anios, 'dias_del_trunco', v_trunco,
    'dias_ganados', v_ganados, 'dias_gozados', v_tomados, 'dias_pendientes', v_pend,
    'ya_pagado_libro', v_ya_pagado,
    'records_vencidos', v_vencidos,
    'records_sin_gozar', (v_saldo->>'records_sin_gozar')::int,
    'vence_el', (v_saldo->>'vence_el')::date,
    'aviso_vencidos', case when v_vencidos > 0 then
      'ATENCION: ' || v_vencidos || ' record(s) de vacaciones VENCIDOS -cerrados hace mas de un anio '
      || 'sin gozarse-. El art. 23 del D. Leg. 713 manda ademas una indemnizacion de una remuneracion '
      || 'por cada uno, que este sistema NO calcula (tiene excepciones: el personal de direccion queda '
      || 'fuera). Revisalo con el contador.'
      else null end,
    -- Lo que de verdad evita la indemnizacion es esto, y por eso va aun sin
    -- vencidos: el dia del cese ya es tarde para programar unas vacaciones.
    'aviso_por_vencer', case when v_vencidos = 0 and (v_saldo->>'records_sin_gozar')::int > 0 then
      'Tiene un record completo sin gozar que vence el ' || (v_saldo->>'vence_el')
      || '. Todavia no genera indemnizacion; la genera si llega esa fecha sin haberse tomado.'
      else null end,
    'valor_dia', round(v_base / 30.0, 2),
    'formula', '(RC / 2) x dias_pendientes / 15, menos lo ya pagado del libro y el aporte a pension',   -- CAMBIO 0341
    'monto_bruto', v_monto_bruto,       -- CAMBIO 0341
    'descuento_afp', v_descuento_afp,   -- CAMBIO 0341
    'tasa_afp', v_tasa_afp,             -- CAMBIO 0341
    'monto', v_monto
  );
end;
$function$
;

-- ── 3 · fn_vacaciones_resumen ────────────────────────────────────────
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
        -- CAMBIO 0498: menos los días fuera del servicio (licencia sin goce aprobada,
        -- con el interruptor encendido). Sin ninguno resta cero y da lo de siempre.
        round(15.0 * greatest(0, (v_as_of - p.fecha_ingreso)
                                 - fn_dias_suspendidos(p.id, p.fecha_ingreso, v_as_of))::numeric / 365.0, 1) as dias_ganados,
        vt.dias as dias_tomados,
        -- CAMBIO 0498: la base de horas esperadas tampoco exige trabajar los días que
        -- estuvo fuera: con ellos adentro, el «ritmo» de quien vuelve de una licencia
        -- salía castigado por una ausencia que se pactó. No se solapan con las
        -- vacaciones de `vv.dias` (ausencias_sin_solape), así que no se resta dos veces.
        (45.0 * greatest(0, (v_as_of - av.aniv_ini) - vv.dias
                            - fn_dias_suspendidos(p.id, av.aniv_ini, v_as_of))::numeric / 7.0) as base_horas,
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

-- ── 4 · fn_provisiones ───────────────────────────────────────────────
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
        -- ⇩ CAMBIO 0498 ⇩ Menos los días fuera del servicio dentro de este año
        -- (licencia sin goce aprobada, con el interruptor encendido). SOLO cambia el
        -- número de días que se muestra: el monto de `vac` no necesita cambio porque
        -- un día fuera no tiene `pago_dia`, así que ya no devengaba nada. Sin ninguna
        -- interrupción resta cero y da lo de siempre.
        'vac_dias', case when dev.hay_vac
                         then round(15.0 * greatest(0, (v_as_of - va.aniv_ini)
                                                       - fn_dias_suspendidos(p.id, va.aniv_ini, v_as_of))::numeric / 365.0, 1)
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

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (498, 'las_vacaciones_descuentan_la_licencia_sin_goce')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
