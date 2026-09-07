-- ============================================================================
-- 0388 · El motor de faltas desempata como el de tardanzas
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `fn_expediente_generar_falta` elija SIEMPRE el mismo «documento
--   anterior», aunque dos documentos entregados de esa persona compartan
--   `entregado_at`. Un solo cambio, de una línea:
--
--     antes:  order by entregado_at desc limit 1
--     ahora:  order by entregado_at desc, periodo_hasta desc nulls last,
--                      id desc limit 1
--
--   Nada más cambia. Mismas ramas, mismos umbrales, mismos mensajes.
--
-- QUÉ ASUME
--
--   Que la 0237 es la versión vigente de `fn_expediente_generar_falta`
--   —comprobado con `./scripts/donde-vive.sh` (5 versiones repartidas: 0060,
--   0091, 0092, 0213, 0237) y con `git grep` sobre todas las ramas—, y que la
--   0311 es la vigente de `fn_tardanza_escalon_al`, de donde sale el criterio.
--   El cuerpo de abajo es el de la 0237 íntegro, con esa línea cambiada y
--   marcada CAMBIO 0388.
--
--   md5 de partida, PEDIDO A PRODUCCIÓN en el SQL Editor (2026-09-07):
--     MD5_PENDIENTE
--
-- ⚠ ESTA MIGRACIÓN SÍ CAMBIA COMPORTAMIENTO REAL. NO ES COMO LA 0386 NI LA 0387
--
--   Las dos anteriores agregaban un desempate que producción no podía disparar:
--   allá el empate exigía dos filas nacidas en la misma transacción, y cada
--   escritura entra por su propia llamada RPC. Acá NO.
--
--   `entregado_at` no es `now()`: es un parámetro. Y cuando se marca una entrega
--   con FECHA PASADA, la pantalla manda el MEDIODÍA DE LIMA de ese día —
--   `instanteEntrega` en `apps/web/lib/admin/instante-entrega.ts`, que arma
--   `${dia}T12:00:00-05:00`. Los dos caminos de entrega con fecha elegida
--   (`fn_expediente_entregar` directo y `fn_expediente_adjuntar` al subir el
--   cargo firmado) pasan por ahí.
--
--   O sea: dos documentos de falta de la misma persona marcados entregados el
--   mismo día pasado quedan con `entregado_at` IDÉNTICO al microsegundo, en
--   transacciones distintas y sin nada raro de por medio. Es lo que ocurre
--   cuando Desarrollo Organizacional se pone al día con papeles atrasados.
--
--   ANTES DE PEGAR ESTA MIGRACIÓN, MIDE SI ESO EXISTE HOY. La consulta está al
--   final de este archivo, comentada: solo lee, y dice a quién afecta. Si
--   devuelve cero filas, esta migración es inerte y solo cierra el hueco hacia
--   adelante. Si devuelve alguna, esas personas pueden cambiar de escalón — y
--   esa es una conversación que se tiene antes, no después.
--
-- QUÉ SE ELIGE MAL HOY, Y QUÉ CUESTA
--
--   De esa única fila salen TRES cosas:
--     · `nivel`          → el escalón anterior, que decide el siguiente
--                          (amonestación → suspensión → imputación → despido)
--     · `periodo_hasta`  → el corte de non bis in idem (`v_cutoff`)
--     · `id`             → el antecedente que el borrador cita (`doc_previo_id`)
--
--   Medido con la prueba 308 contra el Postgres local, ANTES de esta migración:
--   dos personas con el MISMO expediente —una amonestación y una suspensión,
--   las dos entregadas el mismo día— reciben escalones DISTINTOS según el orden
--   en que se guardaron sus papeles. Una sale con 'suspension' y la otra con
--   'imputacion'. La imputación es la carta de preaviso de despido.
--
-- POR QUÉ ESTE CRITERIO Y NO OTRO
--
--   No se inventa acá. Es el que la otra mitad de este mismo sistema ya usa
--   para responder exactamente esta pregunta: `fn_tardanza_escalon_al` (0311)
--   ordena su `ultimo` con `entregado_at desc, periodo_hasta desc, id desc`.
--
--   Que el motor de tardanzas y el de faltas respondan distinto a la misma
--   pregunta es, literalmente, lo que la 0237 vino a cerrar — su cabecera lo
--   dice: «el motor de tardanzas ya lo respeta y el de faltas no, y dos mitades
--   del mismo sistema con reglas distintas es como se arregla una y se olvida
--   la otra». Esta es otra instancia de esa misma grieta, todavía abierta.
--
--   El criterio, en castellano: a igualdad de entrega manda el documento que
--   CUBRE HASTA MÁS TARDE. Es el más avanzado de la escalera y el que da el
--   corte de non bis in idem más protector — con él, ningún hecho ya reprochado
--   se vuelve a reprochar. Elegir el otro retrocede el corte y reabre hechos ya
--   sancionados, que es lo que el numeral 52.5 del RIT prohíbe.
--
-- POR QUÉ `nulls last` Y LA VERSIÓN DE TARDANZAS NO LO LLEVA
--
--   Es el mismo criterio, dicho completo para un motor que lo usa distinto.
--
--   `fn_tardanza_escalon_al` NO lee `periodo_hasta` de la fila ganadora: saca el
--   corte aparte, con `max(periodo_hasta)` sobre todos los documentos, que
--   ignora los nulos por su cuenta. Su `ultimo` solo aporta un `id`, así que
--   dónde caigan los nulos le da igual.
--
--   Este motor SÍ lo lee de la fila ganadora. Y en Postgres `desc` pone los NULL
--   PRIMERO: sin `nulls last`, un documento sin periodo ganaría, `v_cutoff` se
--   quedaría en 2000-01-01 y el borrador volvería a reprochar todo el histórico.
--   Escribir `desc` a secas no diría el criterio: dejaría entrar un default de
--   Postgres justo por el lado que perjudica a la persona.
--
-- LO QUE NO HACE
--
--   No toca `fn_tardanza_escalon_al` — ni una línea. No cambia umbrales, ni la
--   escalera, ni los mensajes. Y no rediseña este motor, aunque se vio de paso
--   que el de tardanzas es estructuralmente inmune porque AGREGA (`max`,
--   `count`) en vez de elegir una fila y leerle tres cosas. Cambiar eso es
--   rehacer el motor de faltas, y no es lo que se pidió.
--
--   Tampoco anota el número 213 en `migraciones_aplicadas`, por lo mismo que
--   explicó la 0237: la 0213 sigue sin aplicarse y el registro tiene que
--   seguir diciéndolo.
--
-- CÓMO SE REVIERTE
--   Correr de nuevo el cuerpo de `fn_expediente_generar_falta` tal como quedó en
--   `supabase/migrations/0237_la_mitad_de_la_0213_que_produccion_nunca_recibio.sql`.
--   No hay datos que deshacer: esta migración no escribe ninguna fila.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_expediente_generar_falta(p_persona_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prev     record; v_has_prev boolean := false; v_vigente boolean := false;
  v_cutoff   date := date '2000-01-01';
  v_full     record; v_new record;
  v_nivel    text; v_hechos jsonb; v_desde date; v_hasta date;
  v_id       uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de falta para esta persona.';
  end if;
  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'falta' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de falta pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- ART. 56 DEL RIT: solo agrava lo ENTREGADO, y los doce meses corren desde
  -- la entrega. Un documento firmado y guardado en un cajón no es antecedente.
  select id, nivel, periodo_hasta, entregado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'falta' and estado = 'entregado'
  -- ⇩⇩⇩ CAMBIO 0388 ⇩⇩⇩ `entregado_at` NO desempata solo: la pantalla marca una
  -- entrega con fecha pasada al MEDIODÍA DE LIMA (`instanteEntrega`), así que
  -- dos documentos entregados el mismo día pasado quedan idénticos al
  -- microsegundo — en producción, en transacciones distintas. Y de esta fila
  -- salen tres cosas: el escalón anterior, el corte de non bis in idem y el
  -- antecedente que se cita.
  --
  -- El criterio es el que `fn_tardanza_escalon_al` (0311) ya usa para esta misma
  -- pregunta en el motor de tardanzas: a igualdad de entrega manda el documento
  -- que CUBRE HASTA MÁS TARDE — el más avanzado de la escalera, y el que da el
  -- corte más protector, porque ningún hecho ya reprochado se vuelve a
  -- reprochar (numeral 52.5 del RIT).
  --
  -- `nulls last` no es una variante: es el mismo criterio dicho completo. Aquel
  -- motor saca su corte con `max(periodo_hasta)`, que ignora los nulos por su
  -- cuenta; este lo lee de la fila ganadora. Y `desc` en Postgres pone los NULL
  -- primero, así que sin `nulls last` un documento sin periodo ganaría, el corte
  -- se quedaría en 2000-01-01 y el borrador reabriría todo el histórico.
  order by entregado_at desc, periodo_hasta desc nulls last, id desc limit 1;
  v_has_prev := found;
  if v_has_prev then
    v_vigente := v_prev.entregado_at >= now() - interval '12 months';
    if v_vigente and v_prev.periodo_hasta is not null then v_cutoff := v_prev.periodo_hasta; end if;
  end if;

  -- art. 25-h sobre TODO el histórico (hayan sido o no sancionadas)
  select * into v_full from fn_falta_contadores(p_persona_id, fn_hoy_lima() - 180);

  if coalesce(v_full.consecutivas,0) >= 4 or coalesce(v_full.en_30,0) >= 6 or coalesce(v_full.en_180,0) >= 16 then
    -- NON BIS IN IDEM, también aquí.
    -- La ley deja MIRAR todo el histórico para probar que se alcanzó el umbral,
    -- pero no deja volver a reprochar un hecho ya reprochado. Sin esto, una vez
    -- superado el umbral cada pulsación de "Generar borrador" producía otra
    -- imputación idéntica sobre exactamente las mismas faltas — indefinidamente,
    -- porque esas faltas siguen dentro de la ventana de 180 días. El único freno
    -- era el chequeo de borrador pendiente, que se levanta al firmar el anterior.
    if (select count(*) from unnest(v_full.fechas) as f where f > v_cutoff) = 0 then
      raise exception 'No corresponde: todas esas faltas ya quedaron cubiertas por el documento anterior (hasta el %). Para volver a sancionar hace falta al menos una falta nueva.',
        to_char(v_cutoff, 'DD/MM/YYYY');
    end if;
    -- Y el candado que ya existía, que vivía solo en la rama de escalación y por
    -- eso esta nunca lo veía.
    if v_vigente and v_has_prev and v_prev.nivel = 'imputacion' then
      raise exception 'Ya hay una imputación vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
    end if;
    v_nivel  := 'imputacion';
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_full.fechas) as f);
    v_desde  := (select min(f) from unnest(v_full.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_full.fechas) as f);
  else
    -- escalación sobre faltas NUEVAS (non bis in idem)
    select * into v_new from fn_falta_contadores(p_persona_id, v_cutoff + 1);
    if coalesce(v_new.en_180,0) < 1 then
      raise exception 'No corresponde: sin faltas injustificadas nuevas.';
    end if;
    if v_vigente and v_prev.nivel = 'imputacion' then
      raise exception 'Ya hay una imputación vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
    elsif v_vigente and v_prev.nivel = 'suspension' then
      v_nivel := 'imputacion';                              -- reincidencia sobre suspensión
    elsif v_vigente and v_prev.nivel = 'amonestacion' then
      v_nivel := 'suspension';                              -- reincidencia sobre amonestación
    else
      v_nivel := 'amonestacion';                            -- 1ª falta injustificada
    end if;
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_new.fechas) as f);
    v_desde  := (select min(f) from unnest(v_new.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_new.fechas) as f);
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'falta', v_nivel, v_hechos, v_desde, v_hasta,
    case when v_has_prev then v_prev.id else null end,
    case when v_nivel = 'suspension' then 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    null);
  return v_id;
end;
$function$;

-- El `create or replace` conserva los permisos porque no hay `drop` y la firma
-- no cambia. Se re-declaran igual, que es la costumbre de la casa desde que un
-- drop sin grant dejó el semáforo disciplinario ciego dos días (0189 → 0204).
grant execute on function public.fn_expediente_generar_falta(uuid) to authenticated;
revoke execute on function public.fn_expediente_generar_falta(uuid) from public, anon;

comment on function public.fn_expediente_generar_falta(uuid) is
  'Genera el borrador de falta que corresponde (0060/0092/0237/0388). El '
  'documento anterior que manda se elige con desempate explicito (0388), el '
  'mismo que fn_tardanza_escalon_al usa en el motor de tardanzas: a igualdad de '
  'entregado_at manda el que cubre hasta mas tarde. Hace falta porque una '
  'entrega con fecha pasada se guarda al mediodia de Lima, asi que dos '
  'documentos entregados el mismo dia empatan de verdad — y de esa fila salen '
  'el escalon anterior, el corte de non bis in idem y el antecedente citado.';

insert into migraciones_aplicadas (numero, nombre)
values (388, 'el_motor_de_faltas_desempata_como_el_de_tardanzas')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0388 · fn_expediente_generar_falta desempata el documento anterior igual que fn_tardanza_escalon_al (0311).';
  raise notice '0388 · ojo: esta SI puede cambiar el escalon de alguien. Corre antes la consulta comentada al final de este archivo.';
end $mig$;

-- ── LA MEDICIÓN, ANTES DE PEGAR ─────────────────────────────────────────────
-- Solo lee. Dice si el empate existe hoy en producción y a quién afecta. Cero
-- filas = esta migración es inerte y solo cierra el hueco hacia adelante.
--
--   select p.nombres || ' ' || p.apellidos            as persona,
--          e.entregado_at,
--          count(*)                                   as documentos_empatados,
--          array_agg(e.nivel order by e.periodo_hasta desc nulls last)  as niveles,
--          array_agg(e.periodo_hasta order by e.periodo_hasta desc nulls last) as cubren_hasta
--     from expediente_disciplinario e
--     join personas p on p.id = e.persona_id
--    where e.tipo_causal = 'falta' and e.estado = 'entregado'
--    group by p.nombres, p.apellidos, e.persona_id, e.entregado_at
--   having count(*) > 1
--    order by e.entregado_at desc;
--
-- El primer elemento de `niveles` es el que esta migración va a elegir. Si
-- coincide con el escalón que Desarrollo Organizacional ya venía aplicando a esa
-- persona, no cambia nada para ella.
