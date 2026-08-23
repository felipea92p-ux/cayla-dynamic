-- ============================================================================
-- 0277 — Cambiar el régimen de pensión vuelve a mover el descuento
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cambiar el régimen de pensión de alguien desde la pantalla cambie de
--   verdad lo que se le descuenta, deje rastro en `correcciones_auditoria`, y
--   diga desde cuándo rige.
--
-- QUÉ ASUME
--   · Que `asignaciones_regimen_pension` y `fn_cambiar_regimen_pension` son las
--     de la **0261**, y que la 0261 sigue siendo el único escritor de tramos.
--   · Que `fn_set_regimen_pension` es la de la **0125**, confirmada con
--     `./scripts/donde-vive.sh fn_set_regimen_pension`. md5 de partida en la
--     base local: da460442eae9b94cbd189ea17b2b5652.
--   · Que `tasas_pension` (0114) sigue siendo la lista verdadera de regímenes.
--     Medido: trae los seis —onp, profuturo, prima, integra, habitat,
--     jubilada—, así que validar contra ella no rechaza ninguno de los que hoy
--     se pueden elegir.
--   · Que `fn_fecha_en_periodo_pagado` (0203) es el freno de periodo pagado.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- La 0261 hizo lo correcto: versionó a qué régimen pertenece cada persona, y
-- `fn_planilla_calcular` pasó a leer el tramo vigente a la fecha del periodo,
-- cayendo a `personas.regimen_pension` solo como respaldo para quien no tuviera
-- historial.
--
-- Lo que quedó suelto es quién escribe ese historial. La pantalla de datos
-- personales siguió llamando a `fn_set_regimen_pension`, que hace un `update
-- personas set regimen_pension` y nada más. Y `fn_cambiar_regimen_pension`, que
-- sí escribe el tramo, NO LA LLAMA NADIE — comprobado sobre `apps/` y
-- `packages/`, donde su nombre aparece solo en los tipos generados.
--
-- El resultado es un defecto partido en dos, y nada en pantalla dice quién es
-- quién:
--
--   · Quien YA tenía régimen cuando se pegó la 0261 tiene tramo abierto (el
--     relleno lo escribió con `where p.regimen_pension is not null`). El motor
--     lee el tramo, la pantalla escribe la columna, y el tramo gana:
--     **cambiar su régimen no mueve un céntimo de su descuento.**
--   · Quien no lo tenía, o ingresó después, no tiene tramo. El `coalesce` cae a
--     la columna y **la pantalla sí funciona.**
--
-- Y el aviso que la pantalla da al guardar —«Se aplicará desde el próximo
-- cálculo de planilla»— es falso para el primer grupo.
--
-- ── POR QUÉ NO BASTA CAMBIARLE EL NOMBRE A LA RPC ───────────────────────────
--
-- Porque las dos funciones no hacen lo mismo. Medido en `pg_proc`:
--
--     fn_set_regimen_pension       deja auditoría: SÍ    acepta null: SÍ
--     fn_cambiar_regimen_pension   deja auditoría: NO    acepta null: NO
--
-- Cambiar la llamada a secas cambiaría un no-op silencioso por un cambio de
-- descuento SIN RASTRO, y dejaría sin salida el «todavía no se sabe» que la
-- pantalla ofrece a propósito para quien ingresa sin declarar su AFP.
--
-- Así que esta migración le lleva a `fn_cambiar_regimen_pension` las dos cosas
-- que le faltaban, y recién entonces la pantalla puede llamarla.
--
-- ── QUÉ CAMBIA, Y POR QUÉ ASÍ ───────────────────────────────────────────────
--
-- 1 · `fn_cambiar_regimen_pension` gana la auditoría de la 0125, con el mismo
--     motivo: nombra la tasa que va a regir, para que el rastro diga cuánta
--     plata mueve el cambio y no solo el nombre del régimen.
--
-- 2 · Acepta `null` como «todavía no se sabe»: cierra el tramo abierto y NO
--     abre otro. La persona vuelve a la tasa genérica hasta que se sepa el
--     verdadero. Es el estado que la pantalla ya ofrecía y es real.
--
-- 3 · Valida contra `tasas_pension` en vez de contra una lista escrita a mano.
--     La 0261 la había cableado en un `array[...]`; es la tercera regla de
--     `CLAUDE.md` («nunca una lista escrita a mano de algo que vive en una
--     tabla») y el comentario de `enums.ts` ya prometía este comportamiento.
--     El día que entre una AFP nueva se agrega una fila y la función la acepta.
--
-- 4 · `valor_anterior` se toma del TRAMO, no de la columna — porque el tramo es
--     lo que la planilla venía usando. Para el primer grupo esa fila de
--     auditoría es, además, la prueba de qué se estaba descontando de verdad.
--
-- 5 · `fn_set_regimen_pension` deja de funcionar y explica por qué. No se borra
--     —hay un comentario en `enums.ts` que la nombra y puede haber una sesión
--     abierta con la pantalla vieja cargada—, pero se le quita el permiso a
--     `authenticated` y su cuerpo levanta excepción. Un llamador olvidado falla
--     RUIDOSO en vez de seguir escribiendo en la columna que ya no manda.
--
-- 6 · `fn_regimen_pension_divergentes()` dice a quién le quedó la columna
--     diciendo una cosa y el tramo otra, que es exactamente el grupo al que
--     alguien le cambió el régimen sin que le cambiara el descuento.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, A PROPÓSITO ──────────────────────────────
--
-- No arregla sola a quien esté divergente. Corregirlo exige decir DESDE CUÁNDO
-- rige el régimen bueno, y esa fecha cambia lo que calcula un periodo; si cae en
-- uno ya pagado, el freno de la 0203 tiene que seguir frenando. Inventar una
-- fecha sería justo lo que la 0261 vino a impedir. La divergencia se lista, se
-- mira caso por caso, y se corrige llamando a la función con su fecha.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   · `fn_cambiar_regimen_pension` → pegar su cuerpo de la 0261.
--   · `fn_set_regimen_pension`     → pegar su cuerpo de la 0125 y devolver
--                                     `grant execute ... to authenticated`.
--   · `fn_regimen_pension_divergentes` → `drop function if exists`.
--   Ninguna de las tres toca datos, así que revertir no pierde nada.
--
-- ============================================================================


-- ── 1 · Cambiar de régimen: con fecha, con rastro, y aceptando «no se sabe» ──

create or replace function fn_cambiar_regimen_pension(
  p_persona_id uuid,
  p_regimen    text,
  p_desde      date,
  p_nota       text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_nuevo         text;
  v_abierta       uuid;
  v_desde_abierta date;
  v_antes         text;
  v_quien         uuid;
  v_tasa          numeric;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el régimen de pensión.';
  end if;

  -- null y '' son el mismo estado: «todavía no se sabe».
  v_nuevo := nullif(btrim(lower(coalesce(p_regimen, ''))), '');

  -- La lista verdadera vive en `tasas_pension`, no acá. Ver punto 3 de la
  -- cabecera.
  if v_nuevo is not null and not exists (
       select 1 from tasas_pension where regimen = v_nuevo) then
    raise exception 'Régimen «%» desconocido. Los cargados son: %.',
      v_nuevo,
      (select string_agg(distinct regimen, ', ' order by regimen) from tasas_pension);
  end if;

  if p_desde is null then
    raise exception 'Hace falta decir desde cuándo rige el régimen nuevo.';
  end if;

  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;

  -- El freno de la 0203, intacto: un cambio con efecto dentro de un mes ya
  -- pagado cambiaría lo que ese mes calcula.
  if fn_fecha_en_periodo_pagado(p_desde) is true then
    raise exception 'El % cae dentro de un periodo YA PAGADO. Un cambio con esa fecha movería lo que ese mes calcula. Elige la primera fecha del periodo abierto.', to_char(p_desde,'DD/MM/YYYY');
  end if;

  select id, vigente_desde, regimen
    into v_abierta, v_desde_abierta, v_antes
    from asignaciones_regimen_pension
   where persona_id = p_persona_id and vigente_hasta is null;

  -- Sin tramo abierto, lo que la planilla venía usando es la columna: ese es el
  -- valor anterior honesto, y el que hay que escribir en la auditoría.
  if v_abierta is null then
    select regimen_pension into v_antes from personas where id = p_persona_id;
  end if;

  if v_abierta is not null and v_desde_abierta >= p_desde then
    raise exception 'Ya hay un régimen vigente desde el %, que es igual o posterior al % que pides.', to_char(v_desde_abierta,'DD/MM/YYYY'), to_char(p_desde,'DD/MM/YYYY');
  end if;

  -- Igual que en la 0125: un guardado que no cambia nada no ensucia la
  -- auditoría. Se compara contra el TRAMO, que es lo que la planilla lee — así
  -- que a quien tenga la columna divergente, esta llamada SÍ lo corrige.
  if coalesce(v_antes, '∅') = coalesce(v_nuevo, '∅') then
    return jsonb_build_object(
      'ok', true, 'regimen', v_nuevo, 'desde', p_desde, 'sin_cambios', true
    );
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  if v_abierta is not null then
    update asignaciones_regimen_pension
       set vigente_hasta = p_desde - 1
     where id = v_abierta;
  end if;

  -- Con `null` se cierra el tramo y no se abre otro: sin fila vigente, el
  -- respaldo de `fn_planilla_calcular` cae a la columna, que también queda en
  -- null, y de ahí a la tasa genérica. Ver punto 2 de la cabecera.
  if v_nuevo is not null then
    insert into asignaciones_regimen_pension
      (persona_id, regimen, vigente_desde, asignado_por, nota)
    values (p_persona_id, v_nuevo, p_desde, v_quien, p_nota);
  end if;

  update personas set regimen_pension = v_nuevo where id = p_persona_id;

  select tp.aporte + tp.comision + tp.prima into v_tasa
    from tasas_pension tp
   where tp.regimen = v_nuevo
     and tp.vigente_desde <= p_desde
     and (tp.vigente_hasta is null or tp.vigente_hasta >= p_desde)
   order by tp.vigente_desde desc
   limit 1;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'asignaciones_regimen_pension.regimen',
          coalesce(v_antes, '(sin régimen)'), coalesce(v_nuevo, '(sin régimen)'),
          case
            when v_nuevo is null
              then 'Se quita el régimen desde el ' || to_char(p_desde,'DD/MM/YYYY')
                   || ': el descuento vuelve a la tasa genérica hasta que se sepa el verdadero.'
            -- round()::text y NO to_char, por lo mismo que la 0125: 'FM99D99'
            -- deja el separador colgando y el símbolo depende del locale.
            else 'Régimen de pensión desde el ' || to_char(p_desde,'DD/MM/YYYY')
                 || '. Se le descuenta el ' || round(coalesce(v_tasa, 0) * 100, 2)::text
                 || ' por ciento de su remuneración asegurable.'
          end
          || coalesce(' · ' || nullif(btrim(p_nota), ''), ''),
          v_quien);

  return jsonb_build_object(
    'ok', true,
    'regimen', v_nuevo,
    'desde', p_desde,
    'tasa', coalesce(v_tasa, 0),
    'cerro_la_anterior', v_abierta is not null,
    'sin_cambios', false
  );
end;
$fn$;

comment on function fn_cambiar_regimen_pension(uuid, text, date, text) is
  'Única forma de cambiar el régimen de pensión. Cierra el tramo vigente, abre '
  'el nuevo desde la fecha dada, mantiene `personas.regimen_pension` en sintonía '
  'y deja fila en `correcciones_auditoria` nombrando la tasa que va a regir. Con '
  'regimen null cierra el tramo y no abre otro: «todavía no se sabe». Se niega si '
  'la fecha cae en un periodo ya pagado (0277).';

revoke all on function fn_cambiar_regimen_pension(uuid,text,date,text) from public;
grant execute on function fn_cambiar_regimen_pension(uuid,text,date,text) to authenticated;


-- ── 2 · La puerta vieja se cierra, y explica adónde ir ───────────────────────
--
-- No se borra: falla ruidoso. Ver punto 5 de la cabecera.

create or replace function fn_set_regimen_pension(p_persona_id uuid, p_regimen text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Esta función ya no cambia el descuento: solo escribía `personas.regimen_pension`, y la planilla lee el tramo vigente de `asignaciones_regimen_pension` desde la 0261. Usá fn_cambiar_regimen_pension(persona, régimen, desde, nota).';
end;
$$;

comment on function fn_set_regimen_pension(uuid, text) is
  'RETIRADA por la 0277. Escribía solo la columna, que la planilla ya no lee '
  'cuando hay tramo vigente, así que cambiaba el régimen en la ficha sin cambiar '
  'el descuento. Levanta excepción a propósito, para que un llamador olvidado se '
  'vea. Usar fn_cambiar_regimen_pension.';

revoke all on function fn_set_regimen_pension(uuid, text) from public;
revoke all on function fn_set_regimen_pension(uuid, text) from authenticated;


-- ── 3 · A quién le quedó la columna diciendo una cosa y el tramo otra ────────

create or replace function fn_regimen_pension_divergentes()
returns table (
  persona_id     uuid,
  nombre         text,
  estado         text,
  dice_la_ficha  text,
  paga_la_planilla text,
  tramo_desde    date
)
language sql
stable
-- SECURITY INVOKER a propósito —o sea, sin `security definer`—. Es un `select`
-- sobre `personas` y sobre el régimen de pensión de cada quien: con definer y
-- sin guard, cualquier sesión `authenticated` se saltaría la RLS y leería el
-- padrón entero. Dejándola invoker, cada quien ve lo que su RLS le deja, y en el
-- SQL Editor —donde se conecta como superusuario— se ve todo, que es justo donde
-- hace falta. Es también la razón por la que NO lleva guard de admin: un guard
-- devolvería cero filas en el Editor, y cero filas se lee igual que «no hay
-- nadie» (la lección está escrita en scripts/sql-manual/a_quien_le_pasa_hoy.sql).
set search_path = public
as $$
  select p.id,
         (p.nombres || ' ' || p.apellidos)::text,
         p.estado,
         coalesce(p.regimen_pension, '(sin régimen)')::text,
         coalesce(h.regimen, '(sin régimen)')::text,
         h.vigente_desde
    from personas p
    join asignaciones_regimen_pension h
      on h.persona_id = p.id and h.vigente_hasta is null
   where coalesce(p.regimen_pension, '∅') <> coalesce(h.regimen, '∅')
   order by p.estado, p.apellidos, p.nombres;
$$;

comment on function fn_regimen_pension_divergentes() is
  'Personas cuya ficha dice un régimen y cuyo tramo vigente dice otro — o sea, a '
  'quienes se les cambió el régimen por la puerta vieja y el descuento no se '
  'movió. Corregir cada caso llamando a fn_cambiar_regimen_pension con la fecha '
  'desde la que rige (0277).';

revoke all on function fn_regimen_pension_divergentes() from public;
grant execute on function fn_regimen_pension_divergentes() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (277, 'cambiar_el_regimen_de_pension_vuelve_a_mover_el_descuento')
on conflict (numero) do nothing;
