-- ============================================================================
-- 0535 · EL CESE SEPARA «QUIÉN PUEDE PEDIRLO» DE «CÓMO SE HACE»
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_cesar_persona` siga haciendo EXACTAMENTE lo mismo para quien la
--   llama hoy —misma firma, mismos permisos, mismos mensajes de error en el
--   mismo orden, mismo rastro en `correcciones_auditoria`— y que el cese en sí
--   (candado de fila, fechas posibles, periodo pagado, tramos de salario y
--   horario, el `update` de `personas` y su rastro) viva en una función
--   interna, `fn_cese_aplicar`, que recibe QUIÉN lo hace en vez de averiguarlo.
--
--   No cambia ni un comportamiento. Es el primer paso de dos: este deja el
--   terreno listo, y el siguiente (0536, «la prueba de tres días») es el que
--   usa la puerta nueva.
--
-- POR QUÉ HACE FALTA (Kent Beck: primero se facilita el cambio, luego se hace)
--   La 0536 deja que la líder de equipo (`supervisor_sede`) dé de baja a quien
--   está de prueba en su sede. `fn_cesar_persona` empieza con
--   `if fn_es_admin_o_lider() is not true` y esa función solo reconoce a
--   `admin` y `lider_do`, así que una líder de equipo siempre rebotaría ahí. No
--   se arregla aflojando esa guardia —abriría el cese de cualquier persona a
--   cualquier líder— ni copiando el cuerpo del cese en otra función (dos
--   formas de cesar es justo lo que la 0174, la 0176 y la 0415 vinieron a
--   cerrar). Se arregla separando las dos cosas que la función hacía juntas:
--   decidir si QUIEN LLAMA puede, y hacer el cese. La primera queda donde
--   estaba; la segunda pasa a una función que solo otras funciones de la base
--   pueden llamar.
--
-- QUÉ ASUME
--   · El cuerpo de partida es el de la 0415. Medido en PRODUCCIÓN el
--     2026-10-19 (SQL Editor): una sola versión de 4 argumentos,
--         md5 tal cual      c069848683a331a0f1acb133e2e10932
--         md5 sin comentarios  a9fc0f201618060b8a34901b9141c908 (el de la 0415)
--         4 503 caracteres, 0 retornos de carro
--     — idéntica a la del Postgres local. Se vuelve a pedir a producción en el
--     mismo mensaje en que se entregue este SQL (regla de la casa: un md5 es
--     una foto, no una garantía).
--   · `fn_cese_aplicar` la llaman únicamente funciones `security definer`
--     dueñas del esquema (esta y, desde la 0536, `fn_prueba_cerrar`). Por eso se
--     le quita el permiso de ejecución a `public`, `anon` y `authenticated`: una
--     sesión del navegador que la llamara directo se saltaría la guardia.
--   · El trigger de la 0432 (que impide cambiar `estado`, `fecha_cese`,
--     `motivo_cese` y `tipo_vinculo` con un `UPDATE` directo) compara
--     `current_user`. Dentro de una función `security definer` dueña de la tabla
--     eso es `postgres`, también cuando se llega por `fn_cese_aplicar`, así que
--     el cese sigue pasando por la puerta y el candado sigue cerrado para todo lo
--     demás.
--
-- QUÉ NO CAMBIA (y por qué importa decirlo)
--   · El orden de las comprobaciones: guardia → quién soy → `for update` de la
--     persona → estado → fechas → periodo pagado → tramos → `update` → rastro.
--     La prueba 135 vigila que el `for update` vaya antes de mirar el estado;
--     esa línea se mudó a `fn_cese_aplicar` y la prueba se mudó con ella.
--   · Los permisos: quien no era admin ni líder DO sigue sin poder cesar a
--     nadie por esta puerta.
--
-- CÓMO SE REVIERTE
--   Pegar de nuevo el cuerpo de `fn_cesar_persona` de
--   `0415_el_cese_tambien_deja_rastro.sql` con `create or replace function` y
--   después `drop function fn_cese_aplicar(uuid, date, text, text, uuid);`.
--   Hacerlo ANTES de pegar la 0536 o la 0536 dejaría de poder cerrar pruebas.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final: las dos funciones existen, el wrapper llama al núcleo,
--   y `authenticated` NO puede ejecutar el núcleo.
-- ============================================================================

create or replace function fn_cesar_persona(
  p_persona_id uuid,
  p_fecha_cese date,
  p_motivo text,
  p_tipo_vinculo text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_actor uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un cese.';
  end if;

  -- Se pide temprano, antes de tocar nada: si no se puede auditar, no se cesa.
  -- Ver "QUÉ ASUME" de la 0415 — en la práctica nunca debería disparar esta rama.
  v_actor := fn_persona_actual_id();
  if v_actor is null then
    raise exception 'No puedo identificar quién hace el cese, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  perform fn_cese_aplicar(p_persona_id, p_fecha_cese, p_motivo, p_tipo_vinculo, v_actor);
end;
$function$;

grant  execute on function fn_cesar_persona(uuid, date, text, text) to authenticated;
revoke execute on function fn_cesar_persona(uuid, date, text, text) from public, anon;

comment on function fn_cesar_persona(uuid, date, text, text) is
  'Única forma de cesar a una persona para quien llama desde el panel: solo admin y líder DO. '
  'Comprueba quién es y a quién auditar, y delega el cese en `fn_cese_aplicar` (0535). '
  'Antes de la 0535 el cese entero vivía aquí; se separó para que otra puerta con SU PROPIA '
  'regla de quién puede (la prueba de tres días, 0536) no tenga que copiar el cese.';


-- El cese en sí. NO comprueba quién llama: eso lo hace quien la llama, y por
-- eso nadie más que otra función de la base puede llamarla (ver el `revoke`).
create or replace function fn_cese_aplicar(
  p_persona_id uuid,
  p_fecha_cese date,
  p_motivo text,
  p_tipo_vinculo text,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_p personas%rowtype; v_hoy date := (now() at time zone 'America/Lima')::date;
        v_desde date;
begin
  -- 0174: toma el candado de la fila ANTES de mirar el estado, para que un
  -- segundo cese simultáneo espere aquí, relea la fila ya cesada y rebote.
  select * into v_p from personas where id = p_persona_id for update;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva (cesó el %).', to_char(v_p.fecha_cese, 'DD/MM/YYYY');
  end if;

  -- La fecha tiene que ser posible.
  if p_fecha_cese > v_hoy then
    raise exception 'El último día trabajado no puede ser futuro (pusiste %).', to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;
  if p_fecha_cese < v_p.fecha_ingreso then
    raise exception 'El último día trabajado (%) no puede ser anterior a su ingreso (%).',
      to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_p.fecha_ingreso, 'DD/MM/YYYY');
  end if;

  -- No se cesa dentro de un periodo ya pagado: eso cambiaría el cálculo de una
  -- planilla cerrada. Mismo criterio que fn_set_fecha_ingreso (0037), acotado a
  -- esta persona para no congelar al equipo entero.
  if fn_fecha_en_periodo_pagado(p_fecha_cese, p_persona_id) then
    raise exception 'El % cae dentro de un periodo de planilla ya PAGADO. Reabre ese periodo primero (queda rastro) o corrige la fecha.',
      to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;

  -- 0176: no se puede cerrar un tramo que todavía no empezó. Se avisa acá, con
  -- la fecha concreta y qué hacer, en vez de dejar que reviente el constraint.
  select min(vigente_desde) into v_desde from asignaciones_salario
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un salario que empieza el %, después del último día que pusiste (%). Corrige ese salario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  select min(vigente_desde) into v_desde from horarios_asignados
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un horario que empieza el %, después del último día que pusiste (%). Corrige ese horario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  -- Sus tramos se cierran. Hoy quedan abiertos para siempre y eso hace que un
  -- salario "vigente" siga apareciendo años después de que la persona se fue.
  update asignaciones_salario set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;
  update horarios_asignados  set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;

  update personas
     set estado = 'inactivo',
         fecha_cese = p_fecha_cese,
         motivo_cese = p_motivo,
         tipo_vinculo = coalesce(p_tipo_vinculo, tipo_vinculo),
         fecha_estado_cambio = now()
   where id = p_persona_id;

  -- El rastro que faltaba. p_motivo no es texto libre: son los códigos fijos
  -- de `personas_motivo_cese_valido` (0086/0143/0325, p. ej. 'despido'), así
  -- que el texto sale corto — sigue siendo más de lo que había, que era nada.
  -- `||` propaga NULL, así que cuando no vino p_tipo_vinculo el `coalesce` de
  -- afuera cae en '.' — sin `if` aparte.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'personas.estado', 'activo', 'inactivo',
     p_actor,
     'Cese con último día trabajado el ' || to_char(p_fecha_cese, 'DD/MM/YYYY')
       || '. Motivo: ' || p_motivo
       || coalesce('. Vínculo pasa a ' || p_tipo_vinculo || '.', '.'));
end;
$function$;

revoke execute on function fn_cese_aplicar(uuid, date, text, text, uuid) from public, anon, authenticated;

comment on function fn_cese_aplicar(uuid, date, text, text, uuid) is
  'El cese de una persona, sin comprobar quién lo pide (0535). Interna: solo la llaman funciones '
  '`security definer` que ya decidieron que su llamador puede — `fn_cesar_persona` y, desde la 0536, '
  '`fn_prueba_cerrar`. Candado de fila, fechas posibles, periodo pagado, cierre de tramos y rastro '
  'en `correcciones_auditoria`, con `p_actor` como autor.';

-- ── Cómo se comprueba que entró ──────────────────────────────────────────────
select
  case
    when (select prosrc from pg_proc where proname = 'fn_cesar_persona') like '%fn_cese_aplicar%'
     and exists (select 1 from pg_proc where proname = 'fn_cese_aplicar')
     and has_function_privilege('authenticated', 'fn_cese_aplicar(uuid, date, text, text, uuid)', 'execute') is not true
      then '✅ el cese quedó separado y el núcleo no es llamable desde el navegador'
    else '❌ no entró completo'
  end as resultado;

insert into migraciones_aplicadas (numero, nombre) values (535, 'el_cese_separa_quien_puede_pedirlo_de_como_se_hace')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
