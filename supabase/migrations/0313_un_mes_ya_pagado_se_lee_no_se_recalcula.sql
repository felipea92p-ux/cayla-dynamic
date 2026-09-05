-- ============================================================================
-- 0313 · UN MES YA PAGADO SE LEE, NO SE RECALCULA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la boleta de un periodo ya pagado muestre lo que se pagó —la foto
--   congelada de `planilla_pagada_detalle`— en vez de recalcularlo con las
--   reglas de hoy.
--
-- EL DEFECTO
--   `fn_proyeccion_periodo` es lo que llaman las dos pantallas de planilla, y
--   hace exactamente tres cosas: comprueba el rol, busca el periodo, y llama a
--   `fn_planilla_calcular`. No hay ninguna rama que pregunte si el mes ya se
--   pagó, y `planilla_pagada_detalle` no aparece por ningún lado.
--
--   O sea que la boleta de un mes cerrado se recalcula con las reglas de hoy y
--   los datos de hoy. Y `fn_planilla_calcular` se reescribió muchas veces desde
--   junio — solo el 2026-08-26 entraron cinco: 0293, 0302, 0306, 0308 y 0310.
--
--   El sistema guarda lo que pagó, y luego imprime otra cosa.
--
-- MEDIDO EN PRODUCCIÓN el 2026-08-26 con
-- `scripts/sql-manual/la_boleta_dice_lo_que_se_pago.sql`:
--
--     periodo 28/06/26 – 28/07/26 · 17 personas cuya boleta diría hoy otro
--     número del que cobraron · S/1 534,07 de diferencia sumada
--
--   Y va en las dos direcciones, que es lo que impide leer esa suma como una
--   deuda: a nueve la boleta les diría MENOS de lo que cobraron —el papel de la
--   empresa contradice el depósito— y a ocho les diría MÁS, que es peor: el
--   propio documento de CAYLA diciendo que se les debía más de lo que
--   recibieron.
--
--   La más grande, Felipe Alvarez: cobró S/2 156,15 y hoy la boleta diría
--   S/1 078,07. La mitad exacta.
--
-- Y HAY UN SEGUNDO DAÑO, QUE NO ES UN NÚMERO SINO UNA AUSENCIA
--   Quien CESÓ no puede obtener la boleta del mes que sí le pagaron. No es que
--   salga otro número: es que no sale nada. `fn_planilla_calcular` arma la
--   planilla de la gente que trabajó ese rango, así que una cesada sin jornadas
--   dentro del periodo simplemente no aparece — aunque su fila esté congelada en
--   la foto porque se le pagó.
--
--   Medido en el laboratorio de la prueba 247: con la función de hoy, la
--   persona que cesó devuelve CERO filas; con esta migración, una. Y es
--   precisamente la persona que más veces pide sus boletas, porque las necesita
--   para su siguiente trabajo.
--
-- POR QUÉ IMPORTA SI EL MES YA PASÓ
--   Porque la boleta se sigue emitiendo hacia atrás: cuando una integrante la
--   pide para un préstamo o un alquiler, cuando alguien cesa y pide las de su
--   último año, cuando hay un reclamo, y cuando fiscaliza SUNAFIL. En todos
--   esos momentos sale un número distinto del que se depositó, y la pantalla no
--   avisa porque no sabe que está recalculando.
--
--   Lo que NO es: no se pagó mal. Los depósitos están bien y la foto los guarda,
--   con `chk_foto_cuadra` exigiendo que el desglose sume el total. Lo que está
--   roto es que nadie la lee.
--
-- QUÉ ASUME
--   · md5 DE PARTIDA de `fn_proyeccion_periodo` (la 0105, tres definiciones,
--     cuerpo sin comentarios así que los dos md5 coinciden):
--
--         fad72eefc30b5b2de9dd81460cf87dd9   ·   536 caracteres
--
--     ⚠ ESE md5 NO SE PIDIÓ A PRODUCCIÓN ANTES DE ESCRIBIR, que es lo que manda
--     la casa. Se declara el del Postgres local, y por eso el bloque 1 de abajo
--     LO COMPRUEBA SOLO: si producción tiene otra versión, esta migración no
--     aplica nada y lo dice. Es el mismo patrón de la 0309 —comprobar antes de
--     tocar— y aquí sustituye a la pregunta previa en vez de saltársela.
--
--   · md5 DE LLEGADA, medido en local DESPUÉS de fijar el número (los
--     marcadores «CAMBIO 0313» del cuerpo cambian con él, y eso mueve el md5
--     sin mover la longitud — la firma más desconcertante que hay en este
--     repositorio):
--
--         0c9718e51240a97b809495c28a68ce93   ·   2 272 caracteres
--
--     La comprobación del final lo devuelve para cotejarlo al pegar.
--
--   · Que `planilla_pagada_detalle.fila` guarda la fila ENTERA tal como salió
--     el día del pago. Lo hace desde la 0096 y `fn_planilla_congelar` mete ahí
--     el jsonb completo (`f`), no un resumen.
--
-- LA TRAMPA DE LAS VERSIONES, Y POR QUÉ NO SE TOMA EL max DEL PERIODO
--   La foto es de solo-agregar y su `version` es del PERIODO entero
--   (`fn_planilla_congelar`, 0201), no de la persona: un repago crea una versión
--   nueva y deja vivas las viejas.
--
--   `fn_liquidacion` ya dejó escrito por qué eso importa, y se le hace caso:
--   quien no sale en el recálculo —una cesada sin jornadas dentro del rango—
--   tiene su fila pagada en una versión ANTERIOR. Tomar el `max(version)` del
--   periodo la haría DESAPARECER de la boleta, que es peor que el defecto que
--   se viene a arreglar.
--
--   Por eso el `distinct on (persona_id) … order by version desc`: la última
--   versión DE CADA PERSONA.
--
-- POR QUÉ SIGUE LLAMANDO A `fn_planilla_calcular`
--   Porque el sobre que devuelve —`dias`, `base_horas`, `feriados`,
--   `factores_provision`, `asignacion_monto`, las etiquetas de mes y año— es
--   metadato del periodo que las dos pantallas consumen, y NO es lo que se pagó
--   mal. Reconstruirlo desde la foto obligaría a copiar cinco reglas más que se
--   desincronizarían a la primera migración, que es exactamente lo que este
--   repositorio lleva pagando cinco veces con el par boleta/reserva.
--
--   Se cambia UNA sola clave, `filas`, que es de donde salen las cifras de cada
--   persona. Cuesta el recálculo que ya costaba antes: ni más lento ni más
--   frágil que hoy.
--
-- LO QUE NO SE TOCA, Y ES DELIBERADO
--   · `fn_planilla_foto_diferencias` sigue recalculando: su trabajo es
--     comparar la foto contra el cálculo de hoy, así que necesita las dos.
--   · `fn_simular_planilla` sigue recalculando: una simulación es, por
--     definición, con las reglas de hoy.
--   · `fn_liquidacion` no se toca en este lote. Recalcula el periodo del cese y
--     le resta la foto, y si ese periodo ya estaba pagado la resta se hace
--     entre dos números que no son comparables. Es un defecto real, más
--     estrecho, y merece su propia medición.
--
-- UN PERIODO PAGADO SIN FOTO
--   Son los anteriores a que existiera el registro congelado. Ahí no hay de
--   dónde leer, así que se sigue recalculando — pero la respuesta lo DICE, con
--   `fuente = 'recalculo_sin_foto'`, para que la pantalla pueda avisar en vez de
--   dar un recálculo disfrazado de original. Medido el 2026-08-26: hoy son 0.
--
-- CÓMO SE REVIERTE
--   Volviendo a crear `fn_proyeccion_periodo` con el cuerpo de la 0105. No toca
--   datos: es una función de solo lectura y `stable`.
-- ============================================================================


-- ── 1 · Comprobar ANTES de tocar nada ───────────────────────────────────────
--
-- Si producción no está en la 0105, esta migración no aplica NADA. Es el
-- sustituto del md5 preguntado a mano, no un adorno: reescribir una función
-- partiendo de un cuerpo que no es el vigente revierte en silencio todo lo que
-- se arregló entre medias, y eso ya casi pasa dos veces en este repositorio
-- (la 0262 y la 0276).

do $$
declare
  v_md5 text;
  v_len int;
begin
  select md5(p.prosrc), length(p.prosrc)
    into v_md5, v_len
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo';

  if v_md5 is null then
    raise exception '0313 · `fn_proyeccion_periodo` no existe en esta base. No se aplica nada.';
  end if;

  if v_md5 <> 'fad72eefc30b5b2de9dd81460cf87dd9' then
    raise exception
      '0313 · PARA. `fn_proyeccion_periodo` en esta base es % (% caracteres), y esta migración se escribió partiendo de fad72eefc30b5b2de9dd81460cf87dd9 (536), que es la de la 0105. NO se aplica nada. Producción tiene otra versión: hay que mirarla antes de escribir encima, porque pegar esto revertiría en silencio lo que la separe. Compruébalo con ./scripts/donde-vive.sh fn_proyeccion_periodo.',
      v_md5, v_len;
  end if;
end
$$;


-- ── 2 · La función ──────────────────────────────────────────────────────────

create or replace function fn_proyeccion_periodo(p_periodo_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_p record;
  v_out jsonb;
  v_filas jsonb;
  v_congelada_at timestamptz;
  v_personas int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la planilla.';
  end if;
  select * into v_p from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_out := fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, v_p.id);

  -- ⇩⇩⇩ CAMBIO 0313 ⇩⇩⇩ UN MES YA PAGADO SE LEE DE SU FOTO.
  if v_p.estado = 'pagado' then

    -- `distinct on (persona_id) … order by version desc`: la última versión DE
    -- CADA PERSONA, no la del periodo. Ver la cabecera — con el max del periodo
    -- desaparecería de la boleta quien cobró en una versión anterior.
    select jsonb_agg(u.fila order by u.fila->>'nombre'),
           max(u.congelada_at),
           count(*)::int
      into v_filas, v_congelada_at, v_personas
      from (
        select distinct on (d.persona_id)
               d.persona_id, d.fila, d.congelada_at
          from planilla_pagada_detalle d
         where d.periodo_id = v_p.id
         order by d.persona_id, d.version desc
      ) u;

    if v_filas is not null then
      return v_out
          || jsonb_build_object(
               'filas',             v_filas,
               'periodo_id',        v_p.id,
               'estado',            v_p.estado,
               'pagado_at',         v_p.pagado_at,
               'simulacion',        false,
               'fuente',            'foto',
               'foto_congelada_at', v_congelada_at,
               'foto_personas',     v_personas);
    end if;

    -- Pagado y sin foto: se sigue recalculando porque no hay de dónde leer,
    -- pero se DICE. Una boleta recalculada que se presenta como la original es
    -- justo el silencio que esta migración viene a cerrar.
    return v_out || jsonb_build_object(
      'periodo_id', v_p.id,
      'estado',     v_p.estado,
      'pagado_at',  v_p.pagado_at,
      'simulacion', false,
      'fuente',     'recalculo_sin_foto');
  end if;

  return v_out || jsonb_build_object(
    'periodo_id', v_p.id,
    'estado',     v_p.estado,
    'pagado_at',  v_p.pagado_at,
    'simulacion', false,
    'fuente',     'calculo');
end;
$function$;

comment on function fn_proyeccion_periodo(uuid) is
  'La planilla de un periodo. Si el periodo ya está PAGADO y tiene foto '
  'congelada, devuelve lo que se pagó (`fuente = foto`) en vez de recalcularlo '
  'con las reglas de hoy — CAMBIO 0313. El resto del sobre (dias, feriados, '
  'factores) sigue viniendo del cálculo: es metadato del periodo, no la cifra '
  'de nadie.';

grant execute on function fn_proyeccion_periodo(uuid) to authenticated;
revoke execute on function fn_proyeccion_periodo(uuid) from public, anon;


-- ── 3 · El rastro ───────────────────────────────────────────────────────────
-- La prueba 122 lo exige en cada push: sin esta fila, `que_falta_pegar.sh` no
-- sabría si esta migración llegó a producción.

insert into migraciones_aplicadas (numero, nombre)
values (313, 'un_mes_ya_pagado_se_lee_no_se_recalcula')
on conflict (numero) do nothing;


-- ── 4 · Comprobación ────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado del último
-- select. Las cinco columnas tienen que salir en `true`.

select
  '0313 · OK'                                                as migracion,
  position('CAMBIO 0313' in (select p.prosrc from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo')) > 0
                                                             as la_boleta_lee_la_foto,
  position('distinct on (d.persona_id)' in (select p.prosrc from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo')) > 0
                                                             as toma_la_ultima_de_cada_persona,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo') = 1
                                                             as sin_sobrecargas_duplicadas,
  md5((select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo'))
                                                             as md5_de_llegada,
  (select count(*) from migraciones_aplicadas where numero = 313) = 1
                                                             as quedo_el_rastro;
