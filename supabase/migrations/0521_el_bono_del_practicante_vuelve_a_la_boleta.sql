-- ============================================================================
-- 0521 — El bono del practicante vuelve a la boleta, y se paga al cierre del periodo
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que el bono de cumpleaños de un practicante se pague igual que el de quien
--   está en planilla: al firmarlo entra como una línea de SU BOLETA del periodo
--   que corre (la 0479) y se paga al cierre, junto con el resto. Sin que
--   Desarrollo Organizacional (DO) tenga que transferirlo uno por uno.
--
--   Y que lo ya pedido por practicantes entre la 0520 y esta migración —que
--   quedó «por transferir» en la Bandeja— pase a la boleta del periodo abierto,
--   en vez de esperar una transferencia a mano. Hoy es un caso: Daniel Ruiz,
--   pedido el 2026-10-13 por S/ 180.00.
--
-- POR QUÉ SE REVIERTE LO QUE DECIDIERON LA 0519 Y LA 0520
--
--   La 0519 (PR #524) y su heredera, la 0520, mandaban al practicante por
--   transferencia: «nunca va a la boleta, porque su subvención no es
--   remuneración (Ley 28518, art. 47) y nadie auditó qué hace la planilla con un
--   bono de practicante». Felipe lo vio funcionando el 2026-10-13 —el pedido de
--   Daniel salió en la Bandeja «por transferir»— y lo rechazó: «no transferir a
--   cada rato, sino pagar al fin del periodo». Es decisión suya.
--
--   Lo que faltaba —auditar qué hace la planilla— se midió ANTES de escribir
--   esto, contra la planilla vigente, con un practicante y un integrante de
--   planilla en las mismas condiciones (S/ 1,800, mismas jornadas, mismo
--   periodo) y un bono de S/ 180 en cada boleta:
--
--     · el total sube EXACTAMENTE S/ 180.00 en los dos;
--     · EsSalud no cambia (110.70; su base sigue siendo el piso, 1,230);
--     · AFP/ONP no cambia (0.00);
--     · la RETENCIÓN de 4.ª sigue en 0: su guarda es `tipo_vinculo = 'rxh'` y un
--       practicante nunca la cumple. Lo único que cambia es el campo
--       informativo `retencion_4ta_base` (643.18 → 823.18), y cambia IGUAL en
--       el integrante de planilla — es un número que se muestra, no un
--       descuento. Este es el hallazgo que la 0520 temía («la planilla le arma
--       base de retención de cuarta con el bono dentro»): es cierto como campo
--       y no tiene efecto sobre lo que cobra.
--
--   La boleta ya pinta las líneas `bono` de cualquiera (boleta-hoja.tsx), así
--   que no se toca ninguna pantalla de la boleta.
--
-- QUÉ HACE
--
--   1. `fn_confirmar_mi_bono_cumpleanos()`: quita la excepción del practicante.
--      Cuerpo de la 0520, con UN bloque cambiado (marca CAMBIO 0521).
--   2. `fn_bono_pasar_pedidos_de_practicantes_a_boleta()`: pasa a la boleta del
--      periodo abierto los bonos de practicantes ya firmados que quedaron sin
--      línea. Solo ESOS: un practicante activo, con la constancia vigente,
--      firmada desde el sistema, sin transferencia confirmada (si ya se
--      transfirió, pagarlo otra vez sería pagarlo dos veces) y con un periodo
--      que no esté ya pagado para su grupo. Idempotente: pegar la migración dos
--      veces mueve cada bono una sola vez. No se concede a nadie: solo la
--      corre el dueño al pegar esto (es plata).
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   · No toca a los integrantes de planilla con un pedido «por transferir»: ese
--     es el respaldo legítimo de la 0478 (no había periodo al firmar) y lo
--     resuelve DO.
--   · No toca `fn_planilla_calcular` ni ninguna función de cálculo.
--   · No cambia quién puede recibir el bono (la regla de la 0520) ni el texto de
--     la constancia.
--   · Un bono ya transferido (`entrega_confirmada_el`) no se mueve.
--
-- QUÉ ASUME
--
--   · La 0520 pegada: `fn_confirmar_mi_bono_cumpleanos` es la suya (el freno de
--     abajo lo comprueba y aborta sin tocar nada si no).
--
-- MD5 DE PARTIDA — fn_confirmar_mi_bono_cumpleanos (0520, 5440 caracteres)
--
--   tal cual 4c1ce38099282648013dd7406563c007
--   sin comentarios 7d430c388a93c50dfadd98f1af5e0965
--   Calculados en el Postgres local con las migraciones aplicadas hasta la 0520.
--   El de PRODUCCIÓN se pide antes de entregar el SQL (CLAUDE.md).
--
-- CÓMO SE REVIERTE
--
--   Volver a pegar `fn_confirmar_mi_bono_cumpleanos` de la 0520 (`create or
--   replace`, misma firma) y
--     drop function if exists fn_bono_pasar_pedidos_de_practicantes_a_boleta();
--   Las líneas de boleta ya creadas NO se borran solas: son plata. Si alguna
--   no debe pagarse, DO la quita desde Planilla y la constancia vuelve a
--   «pedido» y a la lista por transferir (0479).
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================


-- ── 0 · EL FRENO ────────────────────────────────────────────────────────────
do $freno$
declare
  v_ok boolean;
begin
  if exists (select 1 from migraciones_aplicadas
              where numero = 521
                and nombre = 'el_bono_del_practicante_vuelve_a_la_boleta') then
    raise notice '0521 ya estaba aplicada: no se comprueban los md5 de partida.';
    return;
  end if;

  if not exists (select 1 from migraciones_aplicadas where numero = 520) then
    raise exception 'FALTA LA 0520. Esta migración parte de su fn_confirmar_mi_bono_cumpleanos; pégala antes.';
  end if;

  select exists (
    select 1
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
           lateral (values (p.prosrc), (replace(p.prosrc, chr(13), ''))) as v(src)
     where n.nspname = 'public' and p.proname = 'fn_confirmar_mi_bono_cumpleanos'
       and (md5(v.src) = '4c1ce38099282648013dd7406563c007'
            or md5(array_to_string(array(
                 select regexp_replace(l, '[[:space:]]*--.*$', '')
                 from unnest(string_to_array(v.src, chr(10))) as l
                 where btrim(l) not like '--%'
               ), chr(10))) = '7d430c388a93c50dfadd98f1af5e0965')
  ) into v_ok;

  if not v_ok then
    raise exception E'PARA. Producción no tiene el cuerpo de fn_confirmar_mi_bono_cumpleanos del que se copió esta migración (el de la 0520).\nPegarla revertiría en silencio lo que haya entre medias. Corre ./scripts/donde-vive.sh fn_confirmar_mi_bono_cumpleanos y reconstrúyela desde la versión de producción. (Nada se ha modificado: esto abortó antes de tocar nada.)';
  end if;
end
$freno$;


-- ── A · Pasar a la boleta lo que la 0520 dejó «por transferir» ─────────────
-- Devuelve cuántos bonos movió. NO se concede a `authenticated`: escribe
-- líneas de planilla, así que solo la corre el dueño (esta migración).
create or replace function fn_bono_pasar_pedidos_de_practicantes_a_boleta()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_periodo     uuid;
  v_periodo_ini date;
  v_periodo_fin date;
  v_mov         uuid;
  v_movidos     integer := 0;
  r             record;
begin
  -- El mismo periodo que elige `fn_confirmar_mi_bono_cumpleanos`: el último que
  -- ya empezó. `for share` lo pone en fila con `fn_periodo_pagado` (0479).
  select pp.id, pp.fecha_ini, pp.fecha_fin into v_periodo, v_periodo_ini, v_periodo_fin
    from periodos_planilla pp
   where pp.fecha_ini <= fn_hoy_lima()
   order by pp.fecha_ini desc
   limit 1
   for share;

  if v_periodo is null then
    return 0;
  end if;

  for r in
    select d.id as documento_id, d.persona_id, d.monto_declarado
      from documentos_firmados d
      join personas p on p.id = d.persona_id
     where d.tipo = 'bono'
       and d.anulado_at is null and not d.es_negativa
       and d.firma_persona_confirmada_at is not null
       and d.entrega_confirmada_el is null      -- ya transferido: pagarlo otra vez sería pagarlo dos veces
       and d.movimiento_id is null
       and d.monto_declarado > 0                -- la línea de boleta exige monto > 0
       and p.estado = 'activo'
       and p.tipo_vinculo = 'practicante'
     order by d.firma_persona_confirmada_at, d.id
       for update of d
  loop
    -- Periodo ya pagado para su grupo: no se escribe en una boleta cerrada.
    -- Se queda «pedido» y DO lo ve en la lista por transferir, como siempre.
    if fn_fecha_en_periodo_pagado(v_periodo_ini, r.persona_id) then
      continue;
    end if;

    insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
    values (v_periodo, r.persona_id, 'bono', 'Asignación por cumpleaños', r.monto_declarado, null)
    returning id into v_mov;

    update documentos_firmados set movimiento_id = v_mov where id = r.documento_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'bono_en_boleta', null,
       'S/ ' || r.monto_declarado::text || ' · boleta del periodo que cierra el ' || v_periodo_fin::text,
       r.persona_id,
       'El bono de un practicante, que había quedado «pedido» por transferencia (0519/0520), pasó a la boleta del periodo abierto (0521). Lo hizo el sistema al pegar la migración, no la persona.');

    v_movidos := v_movidos + 1;
  end loop;

  return v_movidos;
end;
$$;

revoke execute on function fn_bono_pasar_pedidos_de_practicantes_a_boleta() from public, anon, authenticated;


-- ── B · fn_confirmar_mi_bono_cumpleanos — sin excepción para el practicante ──
-- Cuerpo de la 0520; el ÚNICO cambio es el bloque marcado CAMBIO 0521.
create or replace function fn_confirmar_mi_bono_cumpleanos()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo          uuid := fn_persona_actual_id();
  v_imagen      text;
  v_monto       numeric;
  v_anio        integer := extract(year from fn_hoy_lima())::int;
  v_id          uuid;
  v_ip          text;
  v_ua          text;
  v_estado      text;
  -- CAMBIO 0479 (marcador: la comprobación del bloque 0 reconoce esta versión)
  -- CAMBIO 0521 (marcador): ya no hay excepción para el practicante; la línea
  -- de boleta se crea para quien firma, sea de planilla o practicante.
  v_periodo     uuid;
  v_periodo_ini date;
  v_periodo_fin date;
  v_mov         uuid;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  -- Firmar es pedir plata: solo en el mes de su cumpleaños, o después si se le
  -- pasó (0478).
  select b.estado into v_estado from fn_mi_bono_cumpleanos() b;

  if v_estado = 'pedido' then
    raise exception 'Ya pediste tu bono. Desarrollo Organizacional te avisa por aquí cuando lo transfiera.';
  elsif v_estado = 'en_boleta' then
    raise exception 'Tu bono ya está en tu boleta: se paga junto con tu planilla.';
  elsif v_estado = 'entregado' then
    raise exception 'Tu bono de cumpleaños de este año ya se entregó.';
  elsif v_estado = 'proximo' then
    raise exception 'Tu bono se pide en el mes de tu cumpleaños.';
  elsif v_estado = 'sin_fecha' then
    raise exception 'Falta tu fecha de nacimiento en tu ficha. Avisa a Desarrollo Organizacional.';
  elsif v_estado is distinct from 'este_mes' and v_estado is distinct from 'vencido' then
    raise exception 'Este año no te corresponde el bono de cumpleaños. Si crees que es un error, avisa a Desarrollo Organizacional.';
  end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  v_monto := fn_bono_monto_vigente();

  -- ⇩ CAMBIO 0479 ⇩ `<= 0` además de null: la línea de boleta exige monto > 0,
  -- y un bono «apagado» con valor 0 no debe llegar hasta un error de check.
  if v_monto is null or v_monto <= 0 then
    raise exception 'No hay un monto de bono de onomástico vigente. Avisa a Desarrollo Organizacional antes de firmar.';
  end if;

  begin
    v_ip := nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  -- ⇩⇩⇩ CAMBIO 0479 ⇩⇩⇩ LA LÍNEA DE BOLETA.
  -- El último periodo que ya empezó: el que contiene hoy o, entre el 29 y el
  -- día en que DO crea el siguiente, el que se está por cerrar. `for share` lo
  -- pone en fila con `fn_periodo_pagado`, que toma `for update` sobre la misma
  -- fila: después de esperar, la pregunta de abajo ya ve el pago.
  --
  -- ⇩ CAMBIO 0521 ⇩ LA EXCEPCIÓN DEL PRACTICANTE SE QUITA. Entre la 0519 y la
  -- 0520 su bono nunca iba a la boleta: quedaba «pedido» y DO lo transfería
  -- uno por uno. Felipe lo revirtió el 2026-10-13 («no transferir a cada rato,
  -- sino pagar al fin del periodo»): el bono del practicante se paga con el
  -- periodo, igual que el de planilla. Se midió antes que no mueve nada que no
  -- deba (ver el encabezado de la 0521).
  select pp.id, pp.fecha_ini, pp.fecha_fin into v_periodo, v_periodo_ini, v_periodo_fin
    from periodos_planilla pp
   where pp.fecha_ini <= fn_hoy_lima()
   order by pp.fecha_ini desc
   limit 1
   for share;

  -- Periodo pagado para su grupo, o ninguno: no se escribe en la boleta. La
  -- firma vale igual y la constancia queda `pedido` (respaldo de la 0478).
  if v_periodo is not null and not fn_fecha_en_periodo_pagado(v_periodo_ini, v_yo) then
    insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
    values (v_periodo, v_yo, 'bono', 'Asignación por cumpleaños', v_monto, v_yo)
    returning id into v_mov;
  end if;
  -- ⇧⇧⇧ CAMBIO 0479 ⇧⇧⇧

  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, monto_declarado, anio,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent, movimiento_id
  ) values (
    'individual', v_yo, 'bono', fn_hoy_lima(), v_monto, v_anio,
    v_yo, v_imagen, now(), v_ip, v_ua, v_mov
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'bono · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la constancia del bono de cumpleaños, reemplaza el escaneo físico.');

  if v_mov is not null then
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_yo, 'bono_en_boleta', null,
       'S/ ' || v_monto::text || ' · boleta del periodo que cierra el ' || v_periodo_fin::text, v_yo,
       'El bono de cumpleaños firmado desde el sistema entró a la boleta del periodo abierto (0479).');
  end if;

  return v_id;
end;
$$;

grant execute on function fn_confirmar_mi_bono_cumpleanos() to authenticated;
revoke execute on function fn_confirmar_mi_bono_cumpleanos() from public, anon;


-- ── C · Y se aplica a lo ya pedido ──────────────────────────────────────────
do $mover$
begin
  perform fn_bono_pasar_pedidos_de_practicantes_a_boleta();
end
$mover$;


insert into migraciones_aplicadas (numero, nombre)
values (521, 'el_bono_del_practicante_vuelve_a_la_boleta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select position('CAMBIO 0521' in prosrc) > 0 and position('v_practicante' in prosrc) = 0
     from pg_proc where proname = 'fn_confirmar_mi_bono_cumpleanos') as firma_sin_excepcion,
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_bono_cumpleanos') = 1 as sin_sobrecarga,
  (select count(*) from documentos_firmados d join personas p on p.id = d.persona_id
    where d.tipo = 'bono' and d.anulado_at is null and p.tipo_vinculo = 'practicante'
      and d.movimiento_id is not null) as practicantes_con_bono_en_boleta,
  (select count(*) from documentos_firmados d join personas p on p.id = d.persona_id
    where d.tipo = 'bono' and d.anulado_at is null and p.tipo_vinculo = 'practicante'
      and d.firma_persona_confirmada_at is not null
      and d.movimiento_id is null and d.entrega_confirmada_el is null) as practicantes_aun_por_transferir,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 521) as registro;
