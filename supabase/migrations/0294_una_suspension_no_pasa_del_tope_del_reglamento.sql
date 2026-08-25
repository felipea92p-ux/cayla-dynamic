-- ============================================================================
-- 0294 — Una suspensión no pasa del tope que el propio Reglamento le pone
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que `fn_expediente_set_suspension` deje de aceptar cualquier número de días.
-- Hoy acepta 10, 30 o 300: no mira el Reglamento ni el historial de la persona,
-- solo que el número sea >= 1 (eso lo pide `fn_dias_suspension`, y solo eso).
--
-- QUÉ ASUME
--
-- Nada nuevo. Ni una tabla, ni una columna, ni un permiso cambian. La regla que
-- se escribe acá ya estaba escrita —en el GENERADOR del borrador, migración
-- 0235— y lo único que se hace es que el editor la cumpla también.
--
-- ── EL CASO REAL QUE LO DESTAPÓ ─────────────────────────────────────────────
--
-- 2026-08-25, sede Arequipa. Un borrador de SEGUNDA suspensión por tardanzas,
-- generado por el sistema con 2 días (26 y 27 de agosto), apareció en pantalla
-- con **10 días**: 26, 27, 28, 29 y 31 de agosto, y del 1 al 5 de septiembre.
--
-- El generador nunca propuso ese número. Lo aceptó el editor:
--
--   · el panel ofrecía `<input type="number" min={1} max={15}>`, y el 15 no
--     sale de ninguna norma — es un número que quedó de cuando la suspensión
--     se escribía a mano;
--   · `fn_expediente_set_suspension` (0075) recibe `p_dias` y lo escribe sin
--     preguntar nada, porque cuando se escribió TODAS las suspensiones salían
--     de un día y no había qué topar;
--   · y un `<input type="number">` cambia de valor con la rueda del mouse
--     cuando el cursor pasa por encima al hacer scroll. Diez días de castigo
--     sin sueldo caben en un gesto que nadie nota.
--
-- Lo que se habría firmado: una suspensión que el propio memo declara fundada
-- en el numeral 19.2 d) del RIT, incumpliendo en su parte resolutiva el tope
-- del numeral 54.5 que ese mismo Reglamento fija. Nueve días de sueldo de más,
-- y —lo más caro— un antecedente que no sirve como sanción previa del literal
-- h) del artículo 25 de la LPCL el día que haga falta.
--
-- ── LA REGLA, Y DE DÓNDE SALE CADA NÚMERO ───────────────────────────────────
--
-- No se inventa nada acá. Son los tres límites que el RIT ya tiene escritos, y
-- son exactamente los que la 0235 le impuso al generador:
--
--   · NUMERAL 54.5 — ninguna suspensión pasa de TRES días. Es el techo
--     absoluto, valga la causal que valga.
--   · NUMERAL 19.2 c) — la PRIMERA suspensión es de uno a dos días. El tope de
--     dos existe justamente para que quepa una segunda mayor debajo del techo
--     de tres.
--   · NUMERAL 19.2 d) — la SEGUNDA es «en todo caso de mayor duración que la
--     primera». Igualarla no la agrava, y una escalera que no sube deja de ser
--     escalera.
--
-- ⚠️ EL TOPE ES DEL RIT DE CAYLA, NO DE LA LEY. La LPCL no fija número: exige
-- proporcionalidad y gradualidad, y la práctica privada peruana maneja techos
-- informales bastante más altos (~7 días). Subir el tope de CAYLA es una
-- decisión legítima de Gerencia — pero se toma REFORMANDO EL RIT y volviéndolo
-- a entregar con acuse, no aflojando este candado. Mientras el Reglamento diga
-- tres, un memo que imponga más se contradice a sí mismo, y es el memo el que
-- pierde.
--
-- ── POR QUÉ EN LA BASE Y NO SOLO EN LA PANTALLA ─────────────────────────────
--
-- Porque el `max={15}` de la pantalla ya era la única defensa y no defendió
-- nada: el atributo `max` de HTML no impide escribir ni enviar, solo pinta el
-- campo de rojo si el formulario se valida — y acá no hay formulario, hay un
-- `onBlur` que llama a la RPC. La pantalla se arregla igual (pasa a `max={3}`
-- y deja de responder a la rueda del mouse), pero es el aviso, no el candado.
--
-- Es la misma lección que la 0075 dejó escrita en su propia cabecera: «el
-- cálculo vive en la base, no en el panel: es lo que determina cuántos días
-- deja de cobrar una persona, y no puede depender de qué pantalla lo pida».
-- Se cumplió para el CÁLCULO de los días y se olvidó para su NÚMERO.
--
-- ── CÓMO SE MIDE «LA PRIMERA» Y «LA SEGUNDA» ────────────────────────────────
--
-- Igual que en `fn_tardanza_escalon`, y a propósito: si las dos contaran
-- distinto, el generador propondría un número que el editor rechaza.
--
--   · solo suspensiones ENTREGADAS (art. 56: firmada y no entregada no está
--     vigente, no agrava y no habilita el escalón siguiente);
--   · solo VIGENTES, doce meses desde la entrega;
--   · de la MISMA causal — la escalera del 19.2 es la de tardanzas, y una
--     suspensión por faltas no agrava una de tardanzas ni al revés;
--   · y nunca el propio borrador que se está editando, que no está entregado.
--
-- ── QUÉ NO CAMBIA ──────────────────────────────────────────────────────────
--
-- El cálculo de los días laborables (`fn_dias_suspension`), los permisos, el
-- guard de `fn_expediente_puede_actuar`, y la posibilidad de mover la fecha de
-- inicio. Solo se rechaza el NÚMERO cuando no cabe en el Reglamento.
--
-- Tampoco toca los documentos ya firmados o entregados: la función solo admite
-- borradores desde la 0075 y eso sigue igual. Si hay una suspensión mal puesta
-- ya firmada, se anula y se genera otra — no se corrige por debajo.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Restaurando `fn_expediente_set_suspension` de la 0075. No toca datos: ni una
-- fila de `expediente_disciplinario` se lee ni se escribe al aplicarla.
--
-- md5 de partida (pedirlo a PRODUCCIÓN, no al Postgres local):
--   fn_expediente_set_suspension  96f32dbd2ff1c41da38765ef1ec5bbf6  (0075)
-- ============================================================================

create or replace function fn_expediente_set_suspension(p_id uuid, p_dias int, p_desde date)
returns table (fecha date)
language plpgsql
security definer
set search_path = public
as $$
declare
  r        expediente_disciplinario%rowtype;
  v_fechas date[];
  v_previa int;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede ajustar la suspensión de un borrador (estado actual: %).', r.estado;
  end if;
  if r.nivel <> 'suspension' then
    raise exception 'Este documento no es una suspensión.';
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso sobre este documento.';
  end if;

  -- ── El tope del Reglamento ────────────────────────────────────────────────
  if p_dias is null or p_dias < 1 then
    raise exception 'Los días de suspensión deben ser al menos 1.';
  end if;

  -- NUMERAL 54.5: el techo absoluto, cualquiera sea la causal y el escalón.
  if p_dias > 3 then
    raise exception
      'El numeral 54.5 del Reglamento topa toda suspensión en TRES días, y se pidieron %. '
      'Si Gerencia quiere un tope mayor, eso se cambia reformando el Reglamento y volviéndolo '
      'a entregar con acuse — no en este campo: un memo que se funda en el Reglamento y lo '
      'incumple en su parte resolutiva no sirve como sanción previa el día que haga falta.',
      p_dias;
  end if;

  -- La suspensión anterior de la MISMA causal, entregada y vigente. Se mide
  -- igual que en `fn_tardanza_escalon` — si las dos contaran distinto, el
  -- generador propondría un número que esta función rechaza.
  select max(e.suspension_dias) into v_previa
  from expediente_disciplinario e
  where e.persona_id  = r.persona_id
    and e.tipo_causal = r.tipo_causal
    and e.nivel       = 'suspension'
    and e.estado      = 'entregado'
    and e.id         <> r.id
    and e.entregado_at >= now() - interval '12 months';

  if v_previa is null then
    -- NUMERAL 19.2 c): la primera es de uno a dos días. El tope de dos existe
    -- para que quepa una segunda mayor debajo del techo de tres.
    if p_dias > 2 then
      raise exception
        'Es la PRIMERA suspensión de esta persona, y el numeral 19.2 c) del Reglamento la topa '
        'en dos días. Se pidieron %. Si la conducta amerita más, el camino es la segunda '
        'suspensión del literal d) cuando corresponda, no alargar esta.',
        p_dias;
    end if;
  else
    -- NUMERAL 19.2 d): «en todo caso de mayor duración que la primera».
    if p_dias <= v_previa then
      raise exception
        'Su suspensión anterior fue de % día(s), y el numeral 19.2 d) exige que la siguiente sea '
        'de MAYOR duración. Se pidieron %. Con el techo de tres días del numeral 54.5, lo que '
        'cabe acá es entre % y 3.',
        v_previa, p_dias, v_previa + 1;
    end if;
  end if;

  select array_agg(d.fecha order by d.fecha) into v_fechas
  from fn_dias_suspension(r.persona_id, p_desde, p_dias) d;

  update expediente_disciplinario
    set suspension_dias = p_dias,
        suspension_fechas = v_fechas,
        suspension_desde = v_fechas[1],
        suspension_hasta = v_fechas[array_length(v_fechas, 1)]
    where id = p_id;

  return query select unnest(v_fechas) order by 1;
end;
$$;

comment on function fn_expediente_set_suspension(uuid, int, date) is
  'Fija los dias de una suspension en borrador. Topes del RIT: 3 dias como maximo (54.5), 1-2 la primera (19.2 c), y la segunda mayor que la primera (19.2 d).';

grant execute on function fn_expediente_set_suspension(uuid, int, date) to authenticated;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (294, 'una_suspension_no_pasa_del_tope_del_reglamento')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las tres deben decir true.
select
  (select prosrc ilike '%numeral 54.5 del Reglamento topa toda suspensión%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_set_suspension')
                                                        as topa_en_tres_dias,
  (select prosrc ilike '%numeral 19.2 c) del Reglamento la topa%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_set_suspension')
                                                        as la_primera_no_pasa_de_dos,
  (select prosrc ilike '%exige que la siguiente sea%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_set_suspension')
                                                        as la_segunda_tiene_que_ser_mayor;
