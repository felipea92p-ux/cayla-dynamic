-- ============================================================================
-- 0253 — Anular deja de perder el descuento que el freno obligó a registrar
-- ============================================================================
--
-- QUÉ PROMETE
--   Que anular una liquidación NOMBRE en voz alta los descuentos que quedan
--   vivos en el periodo del cese. No los toca, no los borra y no los devuelve:
--   los dice, en el valor que devuelve la anulación y en el rastro de
--   auditoría, para que quien firma sepa que ahí queda dinero por decidir.
--   Y de paso hace alcanzable el mensaje «no hay sesión» de la 0251, que hoy
--   no se puede imprimir nunca.
--
-- QUÉ ASUME
--   La 0251: `fn_liquidacion_anular` escribe una versión más en cero, con
--   `anulada = true` y los dos CHECK que la sostienen. Esta migración NO toca
--   esa columna, ni esos CHECK, ni los tres lectores que la 0251 reescribió.
--   La 0244: el freno del cierre de `fn_planilla_congelar` manda registrar un
--   descuento por `monto_periodo` antes de dejar cerrar el mes.
--   La 0181: `fn_agregar_movimiento` rechaza tocar un periodo ya pagado.
--
-- ── EL DEFECTO, MEDIDO ──────────────────────────────────────────────────────
--
-- Medido el 2026-08-14 contra el Postgres local, dentro de BEGIN … ROLLBACK,
-- sobre una persona de S/1,500 que cesó el 10/08 dentro del periodo 29/07–28/08.
-- Los mismos hechos, cambiando SOLO el orden de dos acciones:
--
--   CAMINO A — se anula ANTES de tocar nada:
--     · el freno se levanta solo, el mes se cierra y le transfiere S/629.03
--     · la liquidación pendiente queda en S/1,637.94
--     · RECIBE S/2,266.97  ← correcto
--
--   CAMINO C — se hace lo que el freno MANDA, y se anula después:
--     · el freno muerde: «usa el botón Ya le pagué aparte por ESE importe»
--     · se registra el descuento de S/629.03 que el mensaje nombra
--     · el mes se cierra y le transfiere S/0.00
--     · se concilia con el banco, se descubre el error y se anula
--     · la liquidación pendiente queda en S/1,637.94
--     · RECIBE S/1,637.94  ← le faltan S/629.03
--
-- La pérdida es EXACTAMENTE el descuento. Comprobado también con saldo
-- positivo: con un bono de S/200 el descuento sube a S/829.03 y lo que falta
-- sube a S/829.03.
--
-- POR QUÉ PASA. El descuento se registró diciendo «ya le pagué aparte». Era
-- mentira, pero no la dijo nadie por su cuenta: la dictó el freno, con ese
-- importe y por ese concepto, calculado desde la liquidación que ahora se
-- anula. Anular corrige uno de los dos registros y deja el otro en pie.
--
-- Y ADEMÁS SE APAGA LA ÚNICA FRASE QUE LO SEÑALABA. La 0244 añadió al aviso de
-- la hoja una rama que existe, con sus palabras, «para poder EXPLICAR el cero»
-- que deja el descuento. Esa rama se enciende con `coalesce(v_liq, 0) > 0`, y
-- `v_liq` es el `monto_periodo` de la última versión — que anular pone en cero.
-- Medido, antes y después de anular sobre el mismo montaje:
--
--   antes:   periodo S/0.00 · aviso «Su liquidación ya se pagó el 14/08/2026 y
--            ahí se le abonaron S/629.03 por este periodo; si el sueldo del
--            periodo sale … en cero, es porque ese importe ya está descontado»
--   después: periodo S/0.00 · aviso NULO
--
-- El número no cambia. Lo que desaparece es la explicación. Y en la lista de
-- pendientes no se enciende nada: `pagada = f`, `descuadra = f`, sin badge.
-- Quien entra a pagar «la buena» ve S/1,637.94 y no tiene forma de saber que
-- faltan S/629.03, porque el sitio donde están es otra pantalla.
--
-- Cerrado el mes ya no hay marcha atrás cómoda: `fn_agregar_movimiento`
-- responde «Este periodo ya está PAGADO: reábrelo para modificarlo». Con el
-- periodo abierto el descuento aún se puede quitar.
--
-- ── POR QUÉ NOMBRAR Y NO RESOLVER ───────────────────────────────────────────
--
-- Lo primero que se pensó fue negarse a anular si hay un descuento vivo. Está
-- MEDIDO que eso rompería justo el caso que la 0251 vino a resolver: la persona
-- en periodo de prueba tiene un adelanto REAL de S/358.73 registrado como
-- descuento, y ese descuento tiene que sobrevivir a la anulación. Con él, su
-- liquidación tras anular queda en S/125.14, que es lo correcto. Negarse la
-- dejaría sin poder anular nada.
--
-- Lo segundo que se pensó fue sumar el descuento de vuelta al total pendiente.
-- Es peor: el sistema NO PUEDE SABER cuál de los dos descuentos está mirando.
-- Los dos se llaman «descuento», los dos viven en la misma tabla y el mismo
-- periodo, y distinguirlos por el texto del concepto es exactamente el error
-- que la 0244 dejó por escrito que no se vuelve a cometer — un freno atado a
-- una frase literal deja de morder el día que alguien reescribe el botón.
-- Devolver a ciegas pagaría dos veces el adelanto de arriba.
--
-- Así que se hace lo que hace este sistema cuando no puede decidir: lo dice.
-- «Dynamic avisa, nunca sanciona solo», y en la pantalla de Liquidaciones ya
-- está escrito con esas palabras — «el sistema la nombra, no la resuelve».
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, Y POR QUÉ ────────────────────────────────
--
--   · NO toca `fn_liquidacion`. Ahí es donde la frase llegaría a los ojos que
--     importan —el aviso de la hoja, que la pantalla ya pinta en page.tsx:355—
--     pero son 12.821 caracteres que se pegan a mano. La 0251 dejó escrito por
--     qué no se reescribe lo que ya funciona, y vale igual acá. Queda dicho
--     como deuda, con su sitio exacto: la rama del aviso que hoy se enciende
--     con `coalesce(v_liq, 0) > 0` necesita una hermana para cuando la última
--     versión está anulada y hay descuentos vivos. ES UNA DECISIÓN DE FELIPE,
--     no de esta migración.
--   · NO toca el freno de la 0244, ni los CHECK, ni los tres lectores de la
--     0251. El md5 de partida de `fn_liquidacion_anular` se pide a PRODUCCIÓN
--     antes de pegar esto: en esta Mac es 6f63c07ed9166fa187188f72702e323f, y
--     un md5 local no vale como comprobación.
--   · NO anula ni desanula nada, ni lleva dentro el id de nadie.
--
-- ── CÓMO SE MIRA LO QUE YA PASÓ ─────────────────────────────────────────────
--   Esta migración protege de aquí en adelante. Para saber si el agujero ya
--   mordió a alguien, la consulta está en
--   scripts/sql-manual/descuentos_vivos_de_una_liquidacion_anulada.sql
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists fn_liquidacion_descuentos_del_cese(uuid);
--   y volver a pegar `fn_liquidacion_anular` tal cual está en la 0251.
--   Nada de lo que escribe esta migración cambia una cifra: revertirla no mueve
--   ni un céntimo, solo deja de avisar.
-- ============================================================================


-- ── 1 · Qué descuentos quedan vivos en el periodo del cese ──────────────────
-- Los NOMBRA todos, sin filtrar por el texto del concepto. Cuál de ellos
-- correspondía a la liquidación anulada y cuál era un adelanto de verdad no lo
-- sabe ninguna tabla de este sistema; lo sabe quien mira la cuenta.
--
-- El periodo se busca por la fecha de cese de la ÚLTIMA versión guardada y no
-- por `personas.fecha_cese`, con el mismo respaldo que documenta la 0251: a
-- quien fue reactivada el CHECK `personas_cese_coherente` le vacía la fecha, y
-- sin este coalesce la consulta se quedaría muda justo con ella.
create or replace function fn_liquidacion_descuentos_del_cese(p_persona_id uuid)
returns table (
  periodo_id     uuid,
  periodo_ini    date,
  periodo_fin    date,
  periodo_estado text,
  concepto       text,
  monto          numeric,
  registrado_el  date
)
language sql
stable
security definer
set search_path = public
as $fn$
  select per.id, per.fecha_ini, per.fecha_fin, per.estado,
         m.concepto, m.monto,
         (m.created_at at time zone 'America/Lima')::date
  from personas p
  left join lateral (
    select lp.fecha_cese from liquidacion_pagada lp
    where lp.persona_id = p.id order by lp.version desc limit 1
  ) ult on true
  join periodos_planilla per
    on coalesce(ult.fecha_cese, p.fecha_cese) between per.fecha_ini and per.fecha_fin
  join movimientos_planilla m
    on m.persona_id = p.id and m.periodo_id = per.id and m.tipo = 'descuento'
  where p.id = p_persona_id
    -- `is true` y no `not (...)`: un null no pasa como autorizado. Estándar del
    -- repo desde la 0078.
    and fn_es_admin_o_lider() is true
  order by m.created_at;
$fn$;

comment on function fn_liquidacion_descuentos_del_cese(uuid) is
  'Qué descuentos siguen vivos en el periodo que contiene el cese de esta '
  'persona. Solo lee. Existe porque anular una liquidación NO quita el '
  'descuento que el freno del cierre obligó a registrar por ella. Ver 0253.';

revoke execute on function fn_liquidacion_descuentos_del_cese(uuid) from public, anon;
grant  execute on function fn_liquidacion_descuentos_del_cese(uuid) to authenticated;


-- ── 2 · Anular, diciendo lo que queda vivo ──────────────────────────────────
-- Copiada de la 0251 —su única definición, comprobado con ./scripts/donde-vive.sh—
-- con DOS cambios, los dos marcados abajo. Ni una línea más: el orden de los
-- guards, la salida de idempotencia, el insert de la versión en cero, el
-- `detalle` y la fila de auditoría quedan palabra por palabra como estaban.
create or replace function fn_liquidacion_anular(p_persona_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_f      liquidacion_pagada%rowtype;
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
  v_yo     uuid;
  v_ver    int;
  v_desc   jsonb;      -- CAMBIO 0253
  v_suma   numeric;    -- CAMBIO 0253
begin
  -- ── CAMBIO 0253 · el mensaje de sesión, ahora alcanzable ─────────────────
  -- En la 0251 este bloque vivía DESPUÉS del guard de permiso, y ahí no se
  -- podía imprimir nunca: `fn_rol_actual` y `fn_persona_actual_id` resuelven
  -- contra la MISMA fila de `personas` (por `auth_user_id`, que es UNIQUE), así
  -- que si el guard deja pasar, el id nunca es null. Sin sesión se caía por el
  -- otro lado y le decía «solo un administrador o líder» a un admin al que solo
  -- le faltaba la línea de arriba.
  --
  -- Va ANIDADO dentro del guard de permiso y no antes: el guard sigue siendo la
  -- puerta exterior y no se debilita ni un poco. Lo único que cambia es CUÁL de
  -- las dos frases se imprime cuando ya se decidió que no pasa.
  v_yo := fn_persona_actual_id();

  -- `is not true` y no `not (…)`: un null no pasa como autorizado. Estándar del
  -- repo desde la 0078.
  if fn_es_admin_o_lider() is not true then
    if v_yo is null then
      raise exception 'No hay sesión: la anulación tiene que quedar firmada. Desde el SQL Editor, ejecuta antes select set_config(''request.jwt.claim.sub'', ''TU-AUTH-USER-ID'', true);';
    end if;
    raise exception 'Solo un administrador o líder anula una liquidación marcada por error.';
  end if;
  -- ── fin CAMBIO 0253 ──────────────────────────────────────────────────────

  -- El motivo se exige ANTES de tocar nada. `correcciones_auditoria` tiene un
  -- CHECK de tres caracteres, así que sin esta comprobación el usuario vería un
  -- error crudo de Postgres en vez de una frase en español.
  if v_motivo is null or length(v_motivo) < 3 then
    raise exception 'Anular una liquidación exige un motivo escrito: qué se marcó por error y cómo se sabe. Sin eso, dentro de un año la fila en cero no se puede leer.';
  end if;

  select * into v_f from liquidacion_pagada
   where persona_id = p_persona_id
   order by version desc limit 1;

  if not found then
    raise exception 'Esa persona no tiene ninguna liquidación registrada como pagada: no hay nada que anular.';
  end if;

  -- ANULAR DOS VECES NO ESCRIBE DOS VECES. La PK es (persona_id, version) y la
  -- versión sale de max+1, así que sin esta salida la segunda llamada insertaría
  -- una v4 en cero anulando una v3 que ya estaba en cero: ruido que un año
  -- después se lee como si hubiera pasado algo dos veces. No es un error, así
  -- que no se levanta excepción: se devuelve lo que ya había.
  --
  -- CAMBIO 0253 · el aviso de los descuentos SÍ se recalcula acá. La llamada es
  -- de solo lectura y el descuento puede haber aparecido después de la primera
  -- anulación; callarlo en la segunda llamada haría que el aviso dependiera de
  -- cuántas veces se pulsó, que es justo lo que la idempotencia promete que no
  -- pasa.
  if v_f.anulada is true then
    select jsonb_agg(jsonb_build_object('concepto', d.concepto, 'monto', d.monto,
                                        'registrado_el', d.registrado_el,
                                        'periodo_estado', d.periodo_estado)),
           sum(d.monto)
      into v_desc, v_suma
      from fn_liquidacion_descuentos_del_cese(p_persona_id) d;

    return jsonb_build_object(
      'ya_estaba_anulada', true,
      'version',           v_f.version,
      'anula_version',     v_f.anula_version,
      'motivo',            v_f.motivo_anulacion,
      'anulada_el',        (v_f.congelada_at at time zone 'America/Lima')::date,
      'descuentos_vivos',      coalesce(v_desc, '[]'::jsonb),
      'descuentos_vivos_suma', coalesce(v_suma, 0)
    );
  end if;

  -- `v_f.version + 1` y no `max(version) + 1`: v_f ES la última versión, que es
  -- lo que acaba de leer el select de arriba. Pedir el max otra vez sería la
  -- misma cuenta hecha dos veces.
  v_ver := v_f.version + 1;

  -- LOS DATOS DE QUIÉN Y CUÁNDO SE COPIAN DE LA VERSIÓN ANULADA, NO SE
  -- RECALCULAN. Llamar a `fn_liquidacion` para rellenarlos abortaría con «esa
  -- persona no tiene fecha de cese» si fue reactivada —el CHECK
  -- `personas_cese_coherente` le vacía `fecha_cese` al volver a activo—, y
  -- entonces no se podría anular justamente a quien más falta hace. Es el mismo
  -- motivo del coalesce que la 0167 documenta en fn_liquidacion_diferencias.
  insert into liquidacion_pagada (
    persona_id, version, congelada_por, nota,
    persona, fecha_ingreso, fecha_cese,
    monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle,
    anulada, motivo_anulacion, anula_version
  ) values (
    p_persona_id, v_ver, v_yo,
    'ANULACIÓN de la versión ' || v_f.version,
    v_f.persona, v_f.fecha_ingreso, v_f.fecha_cese,
    0, 0, 0, 0, 0,
    -- `detalle` es NOT NULL y su promesa en la 0167 es poder REIMPRIMIR la hoja
    -- tal como se entregó. De una anulación no hay hoja que reimprimir, así que
    -- lo que se guarda es la explicación: qué se anuló y qué decía. Con esto la
    -- fila se cuenta sola, sin cruzarla con la anterior.
    jsonb_build_object(
      'anulada',       true,
      'anula_version', v_f.version,
      'motivo',        v_motivo,
      'anulada_at',    now(),
      'que_significa', 'Esta versión no es un pago de S/0.00: es la anulación de una liquidación que se marcó como pagada por error. La versión anulada sigue guardada, con su detalle intacto.',
      'lo_que_decia_la_version_anulada', jsonb_build_object(
        'total',            v_f.total,
        'monto_periodo',    v_f.monto_periodo,
        'monto_vacaciones', v_f.monto_vacaciones,
        'monto_grati',      v_f.monto_grati,
        'monto_cts',        v_f.monto_cts,
        'congelada_at',     v_f.congelada_at,
        'congelada_por',    v_f.congelada_por,
        'nota',             v_f.nota,
        'detalle',          v_f.detalle
      )
    ),
    true, v_motivo, v_f.version
  );

  -- El rastro, igual que hace fn_liquidacion_pagar (0167:157-163). Con una
  -- diferencia: acá `valor_anterior` SÍ se llena. La fila de auditoría de una
  -- anulación tiene que decir sola de cuánto a cuánto, sin ir a buscar nada.
  -- La máscara es `FM999999990.00` y no `FM999999.00`: sin el cero delante,
  -- `to_char(0, 'FM999999.00')` devuelve «.00» — medido.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'liquidacion_pagada',
     'S/' || to_char(v_f.total, 'FM999999990.00') || ' · version ' || v_f.version,
     'ANULADA · S/0.00 · version ' || v_ver,
     v_yo, v_motivo);

  -- ── CAMBIO 0253 · lo que queda vivo se dice, y queda escrito ─────────────
  -- Se lee DESPUÉS del insert a propósito: así el aviso describe el mundo tal
  -- como queda, no como estaba a mitad de la operación.
  select jsonb_agg(jsonb_build_object('concepto', d.concepto, 'monto', d.monto,
                                      'registrado_el', d.registrado_el,
                                      'periodo_estado', d.periodo_estado)),
         sum(d.monto)
    into v_desc, v_suma
    from fn_liquidacion_descuentos_del_cese(p_persona_id) d;

  -- Una fila de auditoría propia y no un texto pegado a la de arriba: la de
  -- arriba dice de cuánto a cuánto fue la anulación y su formato ya se lee en
  -- la pantalla de auditoría. Esto es otro hecho, sobre otra tabla.
  if coalesce(v_suma, 0) > 0 then
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (p_persona_id, 'descuentos_vivos_tras_anular',
       'S/' || to_char(v_suma, 'FM999999990.00') || ' en descuentos del periodo del cese',
       'SIGUEN VIVOS. Comprueba si alguno se registró por la liquidación anulada; si es así, ese importe todavía se le debe.',
       v_yo, v_motivo);
  end if;
  -- ── fin CAMBIO 0253 ──────────────────────────────────────────────────────

  return jsonb_build_object(
    'anulada',       true,
    'version',       v_ver,
    'anula_version', v_f.version,
    'total_anulado', v_f.total,
    'motivo',        v_motivo,
    -- CAMBIO 0253 · las dos claves son ADITIVAS: nada de lo que la 0251
    -- devolvía cambia de nombre ni de valor.
    'descuentos_vivos',      coalesce(v_desc, '[]'::jsonb),
    'descuentos_vivos_suma', coalesce(v_suma, 0),
    'descuentos_vivos_aviso',
      case when coalesce(v_suma, 0) > 0 then
        'OJO: en el periodo del cese quedan S/' || to_char(v_suma, 'FM999999990.00')
        || ' en descuentos, y anular NO los quita. Si alguno se registró porque el '
        || 'freno del cierre lo pidió por esta liquidación, ese importe se le sigue '
        || 'debiendo y NO aparece en el total pendiente. Con el periodo abierto se '
        || 'corrige quitando el descuento; con el periodo pagado hay que reabrirlo.'
      else null end
  );
end;
$fn$;

comment on function fn_liquidacion_anular(uuid, text) is
  'Anula una liquidación marcada como pagada por error: escribe una versión más '
  'en cero, con motivo obligatorio, y deja la anterior visible. No borra nada. '
  'Desde la 0253 avisa además de los descuentos que quedan vivos en el periodo '
  'del cese, que anular no quita. Ver 0251 y 0253.';

revoke execute on function fn_liquidacion_anular(uuid, text) from public, anon;
grant  execute on function fn_liquidacion_anular(uuid, text) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (253, 'anular_deja_de_perder_el_descuento_que_el_freno_obligo_a_poner')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── Comprobación posterior ──────────────────────────────────────────────────
-- Que la migración diga en voz alta que quedó como prometió. Se pega a mano, y
-- una mano se equivoca.
do $mig$
declare
  v_falta text;
begin
  select string_agg(c, ', ') into v_falta
  from unnest(array['fn_liquidacion_descuentos_del_cese', 'fn_liquidacion_anular']) c
  where not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = c
  );
  if v_falta is not null then
    raise exception '0253 · faltan funciones: %', v_falta;
  end if;

  -- Quién puede llamarlas. Las dos leen sueldos de una persona concreta.
  if has_function_privilege('anon', 'fn_liquidacion_descuentos_del_cese(uuid)', 'execute') then
    raise exception '0253 · anon puede leer los descuentos de una persona, y no debe.';
  end if;
  if has_function_privilege('anon', 'fn_liquidacion_anular(uuid, text)', 'execute') then
    raise exception '0253 · anon puede anular liquidaciones, y no debe.';
  end if;
  if not has_function_privilege('authenticated', 'fn_liquidacion_anular(uuid, text)', 'execute') then
    raise exception '0253 · authenticated NO puede anular, y la pantalla lo necesitará.';
  end if;

  -- LO QUE ESTA MIGRACIÓN NO PUEDE HABER TOCADO. Los dos CHECK de la 0251 son
  -- lo que permite que el freno de la 0244 no se reescriba; si esta migración
  -- se los llevara por delante, el daño no se vería hasta el próximo cierre.
  select string_agg(c, ', ') into v_falta
  from unnest(array['liquidacion_anulada_en_cero', 'liquidacion_anulada_se_explica']) c
  where not exists (
    select 1 from pg_constraint
    where conrelid = 'liquidacion_pagada'::regclass and conname = c
  );
  if v_falta is not null then
    raise exception '0253 · se perdieron los CHECK de la 0251: %', v_falta;
  end if;

  raise notice '0253 · listo. Anular sigue haciendo lo mismo y ahora nombra los descuentos que deja vivos.';
  raise notice '0253 · para ver si esto ya le pasó a alguien: scripts/sql-manual/descuentos_vivos_de_una_liquidacion_anulada.sql';
end
$mig$;
