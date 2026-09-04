-- ============================================================================
-- 0355 — Agregar de un clic la gratificación, la CTS y la bonificación
--         pendientes de todo el equipo, en vez de persona por persona.
--
-- QUÉ PROMETE
--
--   Una función nueva, `fn_grati_cts_agregar_pendientes(p_periodo_id)`, que
--   recorre a TODO el equipo de un periodo y, para quien todavía tenga algo
--   pendiente de gratificación, bonificación 9% o CTS, le registra el
--   movimiento — usando el MISMO monto que ya propone `fn_grati_cts_periodo`
--   y la MISMA puerta de siempre, `fn_agregar_movimiento`. No calcula nada
--   nuevo: solo repite, de una vez, el clic que hasta hoy había que dar
--   persona por persona.
--
-- POR QUÉ AHORA
--
--   Lo pidió Felipe después de ver la 0346 en la pantalla real: "esto es
--   mejor que salga automático en cada fecha correspondiente" — y el mismo
--   pedido aplica a Gratificación y CTS, que llevan meses siendo 100% manual.
--
--   Se descartó automatizarlo del todo (que el sistema escriba solo, sin que
--   nadie lo mire, el día 15). La razón salió de la propia prueba en
--   pantalla: al probar con Janis Revilla, su bonificación propuesta dio
--   S/0.00 — correcto, porque su gratificación de ese semestre ya estaba
--   pagada, así que no le quedaba nada pendiente — pero un proceso que
--   escribe solo no distingue "correctamente cero" de "algo salió mal": las
--   dos se ven idénticas. Con un ser humano confirmando antes de que el
--   número se vuelva plata, ese distingo lo sigue haciendo una persona.
--
--   Por eso esta función NO inserta nada por su cuenta al llegar la fecha:
--   sigue haciendo falta que alguien la invoque. Lo que cambia es que ya no
--   hace falta invocarla una vez por persona.
--
-- CÓMO SE REVISA ANTES DE QUE SEA PLATA
--
--   La función no escribe nada que un admin no vea antes: la pantalla (en el
--   PR de la interfaz, aparte de esta migración) pide una confirmación con el
--   total antes de llamarla, y después de llamarla muestra a quién se le
--   agregó y a quién no, y por qué.
--
-- POR QUÉ UN INTENTO POR PERSONA, Y NO TODO O NADA
--
--   La tentación es envolver el lote entero en una sola operación atómica —
--   es el principio de este repositorio para dinero (ninguna operación debe
--   quedar a medias). Pero acá la unidad de negocio no es "el lote": es CADA
--   PERSONA. Pagarle a Nicole no depende de que también se le pueda pagar a
--   alguien de una sede que sigue bloqueada. Envolver el lote entero en una
--   sola transacción haría que UN solo caso problemático (un periodo cerrado
--   en otra sede, un dato inconsistente) le impidiera a TODO el equipo cobrar
--   automáticamente, obligando a volver al camino manual para todos.
--
--   Por eso cada intento va en su propio bloque `begin … exception`, que en
--   Postgres crea un SAVEPOINT implícito: si uno falla, solo se deshace ESE
--   intento — el resto de la función sigue, y el que falló queda listado en
--   `fallidos` con el motivo exacto que dio `fn_agregar_movimiento`.
--
-- QUÉ ASUME
--
--   · Que `fn_grati_cts_periodo` ya decide correctamente quién no tiene nada
--     pendiente (deja el monto en 0) — no repite esa lógica, la reutiliza.
--     Alguien con grati=0 (porque ya se le pagó, porque es RxH y no aparece
--     en la lista, o porque el periodo no es su ventana) simplemente no se
--     intenta: ni se agrega, ni se reporta como fallido.
--   · Que el `p_concepto` de cada movimiento es el mismo texto que la
--     pantalla ya usa al agregar uno a mano (`grati_concepto`, `be_concepto`,
--     `cts_concepto`), para que una boleta generada por el botón se lea
--     exactamente igual que una escrita a mano.
--
-- QUÉ NO TOCA
--
--   · `fn_grati_cts_periodo`, `fn_provisiones` ni `fn_agregar_movimiento`:
--     esta función solo los ORQUESTA, no cambia lo que cada una decide.
--   · El candado de "una vez por periodo" de `fn_agregar_movimiento` (0049),
--     que sigue siendo el que de verdad impide un duplicado — esta función
--     no reimplementa esa comprobación, confía en que la puerta única la haga.
--
-- CÓMO SE REVIERTE
--   drop function fn_grati_cts_agregar_pendientes(uuid);
--
-- AUDITADO EN LABORATORIO (local, BEGIN … ROLLBACK, antes de entregarla):
--   caso normal (dos personas con gratificación y bonificación pendientes),
--   caso "ya pagada" (grati=0 → no se intenta, no aparece en ningún lado),
--   caso "periodo bloqueado" (el intento falla y queda en `fallidos` con el
--   mensaje exacto de fn_agregar_movimiento, sin tumbar a los demás), y
--   ejecutar la función DOS VECES seguidas (la segunda no agrega nada, porque
--   la primera ya dejó todo en cero). Los cuatro, en verde.
-- ============================================================================

create or replace function public.fn_grati_cts_agregar_pendientes(p_periodo_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_gc jsonb;
  v_fila record;
  v_nombre text;
  v_agregados jsonb := '[]'::jsonb;
  v_fallidos jsonb := '[]'::jsonb;
  v_total numeric := 0;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar movimientos.';
  end if;
  if not exists (select 1 from periodos_planilla where id = p_periodo_id) then
    raise exception 'Periodo inexistente.';
  end if;

  -- La MISMA función que ya autocompleta el monto al elegir una categoría a
  -- mano en Planilla: cero lógica de cálculo nueva, solo se reutiliza.
  v_gc := fn_grati_cts_periodo(p_periodo_id);

  for v_fila in
    select (per->>'persona_id')::uuid as persona_id,
           coalesce((per->>'grati')::numeric, 0) as grati,
           coalesce((per->>'cts')::numeric, 0) as cts,
           coalesce((per->>'be')::numeric, 0) as be
    from jsonb_array_elements(v_gc->'personas') per
  loop
    select (p.nombres || ' ' || p.apellidos) into v_nombre
    from personas p where p.id = v_fila.persona_id;

    if v_fila.grati > 0 then
      begin
        perform fn_agregar_movimiento(p_periodo_id, v_fila.persona_id, 'bono',
          v_gc->>'grati_concepto', v_fila.grati, 'gratificacion');
        v_agregados := v_agregados || jsonb_build_object(
          'persona_id', v_fila.persona_id, 'nombre', v_nombre,
          'categoria', 'gratificacion', 'monto', v_fila.grati);
        v_total := v_total + v_fila.grati;
      exception when others then
        v_fallidos := v_fallidos || jsonb_build_object(
          'persona_id', v_fila.persona_id, 'nombre', v_nombre,
          'categoria', 'gratificacion', 'motivo', sqlerrm);
      end;
    end if;

    if v_fila.be > 0 then
      begin
        perform fn_agregar_movimiento(p_periodo_id, v_fila.persona_id, 'bono',
          v_gc->>'be_concepto', v_fila.be, 'bonificacion_extraordinaria');
        v_agregados := v_agregados || jsonb_build_object(
          'persona_id', v_fila.persona_id, 'nombre', v_nombre,
          'categoria', 'bonificacion_extraordinaria', 'monto', v_fila.be);
        v_total := v_total + v_fila.be;
      exception when others then
        v_fallidos := v_fallidos || jsonb_build_object(
          'persona_id', v_fila.persona_id, 'nombre', v_nombre,
          'categoria', 'bonificacion_extraordinaria', 'motivo', sqlerrm);
      end;
    end if;

    if v_fila.cts > 0 then
      begin
        perform fn_agregar_movimiento(p_periodo_id, v_fila.persona_id, 'bono',
          v_gc->>'cts_concepto', v_fila.cts, 'cts');
        v_agregados := v_agregados || jsonb_build_object(
          'persona_id', v_fila.persona_id, 'nombre', v_nombre,
          'categoria', 'cts', 'monto', v_fila.cts);
        v_total := v_total + v_fila.cts;
      exception when others then
        v_fallidos := v_fallidos || jsonb_build_object(
          'persona_id', v_fila.persona_id, 'nombre', v_nombre,
          'categoria', 'cts', 'motivo', sqlerrm);
      end;
    end if;
  end loop;

  return jsonb_build_object(
    'agregados', v_agregados,
    'fallidos', v_fallidos,
    'total_agregado', round(v_total, 2)
  );
end;
$fn$;

comment on function fn_grati_cts_agregar_pendientes(uuid) is
  'Registra de un clic la gratificacion, la bonificacion 9% y la CTS pendientes '
  'de todo el periodo, reusando fn_grati_cts_periodo para el monto y '
  'fn_agregar_movimiento (la unica puerta de escritura) para cada intento. Un '
  'fallo por persona no tumba al resto: cada intento es su propio SAVEPOINT.';

revoke all on function fn_grati_cts_agregar_pendientes(uuid) from public, anon;
grant execute on function fn_grati_cts_agregar_pendientes(uuid) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (355, 'agregar_de_un_clic_la_gratificacion_cts_y_bonificacion_pendientes')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
do $$
begin
  if (select count(*) from pg_proc where proname = 'fn_grati_cts_agregar_pendientes') <> 1 then
    raise exception 'fn_grati_cts_agregar_pendientes no quedó creada.';
  end if;
end $$;
