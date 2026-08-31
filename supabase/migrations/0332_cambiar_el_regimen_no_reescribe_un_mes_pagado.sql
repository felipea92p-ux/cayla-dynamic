-- ============================================================================
-- 0332 — Cambiar el régimen de pensión deja de reescribir un mes ya pagado
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que cambiar el régimen de pensión desde la pantalla de Datos personales
--   no le mueva a nadie una boleta que ya se pagó.
--
--   Hoy se la mueve, pero solo a un tipo de persona: **la que no tiene
--   ninguna fila en `asignaciones_regimen_pension`**. A quien sí tiene
--   historial el mecanismo ya la protege desde la 0261, y la prueba 202 lo
--   fija. Esta migración cierra el caso que quedaba.
--
-- EL DEFECTO, MEDIDO
--
--   `fn_planilla_calcular` resuelve el régimen con la cascada que introdujo la
--   0261: el tramo vigente al CIERRE del periodo y, si no hay tramo, la
--   columna `personas.regimen_pension`. Los dos caminos son necesarios —el
--   respaldo es lo que permitió pegar la 0261 sin mover un céntimo— pero
--   juntos dejan una grieta.
--
--   `fn_cambiar_regimen_pension` abre el tramo nuevo desde la fecha pedida Y
--   ADEMÁS hace `update personas set regimen_pension = v_nuevo`. Para quien no
--   tenía tramo, un mes ya pagado queda ANTES del tramo nuevo: no encuentra
--   fila que lo cubra, cae a la columna, y la columna acaba de cambiar.
--
--   Medido el 2026-08-31 contra el Postgres local, dentro de BEGIN…ROLLBACK,
--   con un periodo pagado (marzo) y uno abierto (abril). Persona sin historial,
--   columna en `integra`, se le pide `integra_mixta` desde el 01/04/2026 —una
--   fecha que el freno de la 0203 acepta, porque cae en el periodo ABIERTO:
--
--       tasa_afp de MARZO, ya pagado    antes: 12.920 %
--                                      después: 11.370 %
--
--   El freno de la 0203 (`fn_fecha_en_periodo_pagado`) no lo evita, y no es
--   culpa suya: comprueba que la FECHA del cambio no caiga dentro de un
--   periodo pagado, y en este caso la fecha está bien. Lo que alcanza al
--   pasado es el `update` de la columna, que no tiene fecha ninguna.
--
-- QUÉ ASUME
--
--   · Que la cascada de la 0261 en `fn_planilla_calcular` sigue como está
--     —tramo que cubre el cierre, y si no, la columna—. No se toca.
--   · Que `personas.regimen_pension` y `asignaciones_regimen_pension.regimen`
--     aceptan exactamente los mismos códigos (0328), salvo que la columna
--     admite además `null`. Comprobado leyendo los dos CHECK: por eso todo
--     valor no-nulo de la columna se puede escribir como tramo sin que el
--     CHECK lo rechace.
--   · Que la firma de la función no cambia (uuid, text, date, text), así que
--     el `comment` / `revoke` / `grant` se conservan.
--
-- ── EL DISEÑO, EN UN PÁRRAFO ─────────────────────────────────────────────────
--
--   El cuerpo ya tenía un `if v_abierta is not null then … end if` que cierra
--   el tramo vigente. Le falta la otra mitad: qué hacer cuando NO hay tramo
--   que cerrar. Esta migración le agrega ese `else` — escribe el tramo del
--   PASADO con el régimen anterior, desde su ingreso (o desde el día siguiente
--   a su último tramo cerrado, lo que sea mayor) hasta el día antes del
--   cambio. Es exactamente lo que hace el paso «1 bis» de la 0331, que resolvió
--   el mismo problema para las 19 personas que movió; aquí entra por la puerta
--   de la pantalla, que es por donde va a volver a pasar.
--
--   Eso NO inventa historia: escribe el valor que la columna ya tenía y que la
--   planilla ya venía aplicando a esos meses. Ninguna cifra pagada cambia —
--   justamente por eso se escribe.
--
--   Ninguna otra línea del cuerpo se toca: mismos comentarios, mismas
--   variables, misma lógica. El único añadido fuera del `else` es la variable
--   `v_desde_pasado`.
--
-- ── EL BORDE QUE QUEDA, Y POR QUÉ NO SE CIERRA AQUÍ ─────────────────────────
--
--   Si la persona no tiene tramo Y su columna está en `null` («todavía no se
--   sabe»), no hay régimen anterior que escribir: `asignaciones_regimen_pension
--   .regimen` es NOT NULL, así que «sin régimen» no se puede representar como
--   tramo. A esa persona, cargarle un régimen por primera vez le sigue moviendo
--   un mes pagado —de la tasa genérica a la del régimen nuevo—.
--
--   No se cierra aquí a propósito: representar «sin régimen» como tramo es un
--   cambio de ESQUEMA (columna nullable o un código propio), con su efecto
--   sobre la cascada de la 0261 y sobre las 202/264. Merece su propia migración
--   y su propia decisión, no un añadido de contrabando en esta. Queda anotado
--   aquí y en la prueba 264.
--
-- MD5 DE PARTIDA
--
--   fn_cambiar_regimen_pension   c1bd45a47936af8c96ab72f0a1569785 · 4862
--
--   Es el cuerpo que dejó la 0327 (bloque 22) — confirmado byte a byte contra
--   el Postgres local: se extrajo el `prosrc` de la base, se reconstruyó desde
--   el archivo de la 0327 y los dos md5 coinciden. Ojo con la cabecera de la
--   0327: el `ed01ed0f… · 4848` que ella declara es su md5 de PARTIDA, o sea la
--   versión de la 0277 — no la que dejó.
--
--   El bloque 0 de abajo lo vuelve a comprobar EN PRODUCCIÓN antes de tocar
--   nada. Si no coincide, esta migración no aplica NADA.
--
-- CÓMO SE REVIERTE
--
--   Volver a pegar el bloque 22 de la 0327 tal cual. Esta migración no toca
--   datos ni tablas: solo reemplaza el cuerpo de una función. Las filas de
--   pasado que escriba a partir de ahora quedan, y deben quedar — son las que
--   sostienen las boletas ya pagadas.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final.
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ────────────────────────────────────────
-- Si producción no tiene el cuerpo que dejó la 0327, esta migración no aplica
-- NADA. Mismo patrón que la 0327/0323/0313.
do $$
declare v_md5 text; v_len int;
begin
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_cambiar_regimen_pension';

  if v_md5 is null then
    raise exception '0332 · PARA. fn_cambiar_regimen_pension no existe en esta base. No se aplicó nada.';
  end if;

  if v_md5 is distinct from 'c1bd45a47936af8c96ab72f0a1569785' then
    raise exception '0332 · PARA. fn_cambiar_regimen_pension en esta base es % (% caracteres), se esperaba c1bd45a47936af8c96ab72f0a1569785 (4862), que es el cuerpo de la 0327. No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_cambiar_regimen_pension.', v_md5, v_len;
  end if;
end
$$;


-- ── 1 · La función, con la rama que le faltaba ───────────────────────────────
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
  v_desde_pasado  date;   -- CAMBIO 0332
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
  if fn_fecha_en_periodo_pagado(p_desde, p_persona_id) is true then
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
  else
    -- CAMBIO 0332 · A quien NO tiene ningún tramo, abrirle uno nuevo no le
    -- protege el pasado: le REESCRIBE los meses ya pagados.
    --
    -- La cascada de la 0261 pregunta por el tramo que cubre el CIERRE del
    -- periodo y, si no encuentra ninguno, cae a `personas.regimen_pension`.
    -- Un mes ya pagado queda antes del tramo nuevo, así que no lo encuentra,
    -- así que cae a la columna — que el `update` de más abajo acaba de
    -- cambiar. Su boleta de un mes cerrado pasa a decir otra cifra y la
    -- planilla deja de cuadrar con lo que salió del banco.
    --
    -- El freno de la 0203 no lo ve, y no es culpa suya: comprueba que la
    -- FECHA del cambio no caiga en un periodo pagado, y en este caso la fecha
    -- está bien. Lo que alcanza al pasado no es la fecha: es el `update` de
    -- la columna, que no tiene fecha ninguna.
    --
    -- Se cierra escribiendo también el tramo del PASADO con el régimen
    -- anterior. No inventa historia: escribe el valor que la columna YA tenía
    -- y que la planilla YA venía aplicando a esos meses. Es lo mismo que hace
    -- el paso «1 bis» de la 0331, ahora por la puerta de la pantalla.
    --
    -- Arranca en su ingreso —antes de eso no se le pagaba nada— pero nunca
    -- antes del día siguiente a su último tramo cerrado, si tuviera alguno:
    -- el índice `asignacion_regimen_sin_solape` prohíbe que dos filas cubran
    -- el mismo día, y con razón — «¿en qué régimen estaba?» no puede tener
    -- dos respuestas.
    select greatest(
             coalesce(pe.fecha_ingreso, date '2000-01-01'),
             coalesce((select max(h2.vigente_hasta) + 1
                         from asignaciones_regimen_pension h2
                        where h2.persona_id = p_persona_id), date '2000-01-01')
           )
      into v_desde_pasado
      from personas pe
     where pe.id = p_persona_id;

    -- Dos condiciones, y las dos son necesarias:
    --   · `v_antes is not null` — si la columna estaba vacía no hay régimen
    --     anterior que escribir, y `regimen` es NOT NULL. Ese borde queda
    --     descrito en la cabecera: no se puede representar «sin régimen» como
    --     tramo sin cambiar el esquema.
    --   · `v_desde_pasado <= p_desde - 1` — a quien entró dentro del periodo
    --     abierto no hay pasado que protegerle, y un tramo que termina antes
    --     de empezar lo rechazaría el CHECK `rango_valido`.
    if v_antes is not null and v_desde_pasado <= p_desde - 1 then
      insert into asignaciones_regimen_pension
        (persona_id, regimen, vigente_desde, vigente_hasta, asignado_por, nota)
      values (p_persona_id, v_antes, v_desde_pasado, p_desde - 1, v_quien,
              '0332 · tramo del PASADO, escrito para que los periodos ya pagados '
              || 'sigan viendo el régimen con el que se pagaron. No se inventa '
              || 'nada: es el valor que `personas.regimen_pension` ya tenía y que '
              || 'la planilla ya venía aplicando a esos meses. Sin esta fila, la '
              || 'cascada de la 0261 caería a la columna —que este mismo cambio '
              || 'acaba de mover— y le reescribiría el pasado.');
    end if;
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
  'la fecha cae en un periodo ya pagado (0277). Y a quien no tenía ningún '
  'tramo le escribe además el del PASADO con su régimen anterior, para que un '
  'mes ya pagado no cambie de cifra al caer al respaldo de la columna (0332).';

revoke all on function fn_cambiar_regimen_pension(uuid,text,date,text) from public;
grant execute on function fn_cambiar_regimen_pension(uuid,text,date,text) to authenticated;


notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (332, 'cambiar_el_regimen_no_reescribe_un_mes_pagado')
on conflict (numero) do nothing;

-- ── La comprobación ─────────────────────────────────────────────────────────
--
-- Un solo SELECT porque el SQL Editor solo devuelve el último.
--
--   · `la_rama_nueva_esta` tiene que decir true. Si dice false, se pegó otra
--     cosa: el `else` no entró.
--   · `md5_ahora` es informativo — sirve para que la próxima migración que
--     reescriba esta función tenga su md5 de partida sin adivinarlo.
--   · `personas_sin_tramo_con_regimen` es a cuánta gente le aplicaba el
--     defecto: sin fila de historial y con la columna cargada. No cambia nada
--     al pegar esto; cambia la próxima vez que a alguna de ellas se le toque
--     el régimen desde la pantalla, que es cuando antes se le movía el pasado.
--   · `personas_sin_tramo_sin_regimen` es el borde que NO se cierra aquí (ver
--     la cabecera): sin tramo y sin columna, no hay régimen anterior que
--     escribir.

select (select position('CAMBIO 0332' in p.prosrc) > 0
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_cambiar_regimen_pension')
         as la_rama_nueva_esta,

       (select md5(p.prosrc) || ' · ' || length(p.prosrc) || ' caracteres'
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_cambiar_regimen_pension')
         as md5_ahora,

       (select count(*) from personas p
         where p.regimen_pension is not null
           and not exists (select 1 from asignaciones_regimen_pension h
                            where h.persona_id = p.id))
         as personas_sin_tramo_con_regimen,

       (select count(*) from personas p
         where p.regimen_pension is null
           and not exists (select 1 from asignaciones_regimen_pension h
                            where h.persona_id = p.id))
         as personas_sin_tramo_sin_regimen;
