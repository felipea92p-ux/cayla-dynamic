-- ============================================================================
-- 0606 · Anular la constancia del bono de cumpleaños lo saca de la boleta
-- ============================================================================
--
-- QUÉ PROMETE
--   · Anular en Documentación la constancia de un bono que ya va en la boleta
--     (0479) retira su línea «Asignación por cumpleaños» en el MISMO paso, con
--     rastro de qué se quitó, de quién y por cuánto.
--   · Si esa línea está en un periodo ya PAGADO para el grupo de la persona,
--     anular se rechaza con un aviso: la plata pagada y su papel no se separan
--     sin que alguien lo decida (Felipe, 2026-11-08).
--   · Quitar un bono o descuento desde Planilla (fn_quitar_movimiento) deja,
--     por fin, rastro en la auditoría. Antes borraba la fila y no quedaba nada.
--   · Nada más cambia: anular cualquier otro documento, o un bono sin línea en
--     la boleta (pedido o transferido), funciona igual que antes.
--
-- EL DEFECTO (tarea 2 de la semana del 9-nov; estado.md, 2026-10-13)
--   Firmar el bono crea su línea en la boleta y ata la constancia a ella
--   (`documentos_firmados.movimiento_id`). fn_documento_anular (0157) solo
--   marcaba la constancia: la línea seguía sumando S/ 180 sin papel detrás. Y
--   como el índice de «un bono por año» excluye a las anuladas, si la persona
--   volvía a firmar, aparecía una SEGUNDA línea en el mismo periodo.
--   Medido en local con la prueba 493 antes de esta migración: dos líneas de
--   cumpleaños en la misma boleta. En producción, el 2026-11-08: 0 constancias
--   anuladas con su línea viva (Felipe lo consultó). Es latente: no costó plata,
--   pero nada lo impedía; hasta hoy DO lo evitaba quitando la línea a mano ANTES.
--
-- POR QUÉ ASÍ (decidido entre tres opciones)
--   · La regla vive en la función que anula, atómica: o se anula y sale la
--     línea, o no pasa nada. Se descartó un trigger sobre documentos_firmados
--     (efecto escondido, y no sabe explicar un periodo pagado) y arreglarlo solo
--     en la pantalla (dos llamadas que pueden quedar a medias).
--   · «Quitar una línea de la boleta con rastro» queda en UNA función interna,
--     fn_retirar_movimiento, que usan las dos puertas: Planilla y la anulación.
--     No es una puerta para la app: sin execute para nadie.
--   · El periodo se toma con `for share` antes de preguntar si está pagado, el
--     mismo cuidado que la 0479 al crear la línea: o la anulación entra antes del
--     pago, o ve el periodo pagado y se niega.
--
-- QUÉ ASUME
--   · Que en producción fn_documento_anular es la de la 0157 y
--     fn_quitar_movimiento la de la 0327. Se comprueba AL PEGAR, abajo, con md5
--     sobre el cuerpo sin \r (así también pasa lo pegado desde Windows): si no
--     coincide, PARA sin aplicar nada.
--   · El vínculo `documentos_firmados.movimiento_id` es `on delete set null`
--     (0479): al borrarse la línea, la constancia queda suelta sola.
--
-- CÓMO SE REVIERTE
--   Volver a pegar fn_documento_anular de la 0157 y fn_quitar_movimiento de la
--   0327, y `drop function fn_retirar_movimiento(uuid, text)`. Las líneas que esta
--   migración haya quitado no vuelven solas: el rastro dice cuáles eran.
--
-- md5 de partida, medidos en el Postgres local con main (8744eee) y la 0605:
--   fn_documento_anular(uuid, text)     00886261f578409234a58fea30fb7c3e · 1063 caracteres
--   fn_quitar_movimiento(uuid)          942d196468bde44159f9686c50ef07f4 ·  655 caracteres
-- (ninguna de las dos tiene comentarios: el md5 «sin comentarios» es el mismo).
-- ============================================================================

-- ── 1 · Guarda: producción tiene que tener las versiones de la 0157 y la 0327 ─
do $$
declare
  r record;
begin
  if to_regprocedure('public.fn_retirar_movimiento(uuid, text)') is not null then
    raise notice '0606 · ya estaba aplicada: se vuelve a pegar sin comprobar las versiones de partida.';
    return;
  end if;

  for r in
    select e.nombre, e.args, e.esperado,
           (select md5(replace(p.prosrc, chr(13), ''))
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = e.nombre
               and pg_get_function_identity_arguments(p.oid) = e.args) as actual,
           (select count(*)
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = e.nombre) as versiones
      from (values
        ('fn_documento_anular',  'p_id uuid, p_motivo text',  '00886261f578409234a58fea30fb7c3e'),
        ('fn_quitar_movimiento', 'p_movimiento_id uuid',      '942d196468bde44159f9686c50ef07f4')
      ) as e(nombre, args, esperado)
  loop
    if r.versiones <> 1 then
      raise exception '0606 · PARA. Hay % funciones llamadas % (se esperaba una sola). No se aplicó nada.', r.versiones, r.nombre;
    end if;
    if r.actual is distinct from r.esperado then
      raise exception '0606 · PARA. % en esta base es % y se esperaba %. Producción tiene otra versión: no se aplicó nada. Compruébalo con ./scripts/donde-vive.sh %.',
        r.nombre, r.actual, r.esperado, r.nombre;
    end if;
  end loop;
end
$$;

-- ── 2 · fn_retirar_movimiento: quitar una línea de la boleta, con rastro ──────
-- Una sola forma de quitar una línea de `movimientos_planilla`: toma su periodo
-- con `for share`, se niega si ya está pagado para el grupo de la persona, anota
-- qué se quita y recién ahí la borra. Los permisos los pone quien la llama.
create or replace function public.fn_retirar_movimiento(p_movimiento_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_mov movimientos_planilla;
  v_ini date;
  v_fin date;
begin
  select * into v_mov from movimientos_planilla where id = p_movimiento_id for update;
  if not found then raise exception 'Movimiento inexistente.'; end if;

  select fecha_ini, fecha_fin into v_ini, v_fin
    from periodos_planilla where id = v_mov.periodo_id for share;

  if fn_fecha_en_periodo_pagado(v_ini, v_mov.persona_id) then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_mov.persona_id, 'movimiento_quitado',
     v_mov.tipo || ' · ' || v_mov.concepto || ' · S/ ' || to_char(v_mov.monto, 'FM999999990.00'),
     'quitado de la boleta del ' || to_char(v_ini, 'DD/MM/YYYY') || ' al ' || to_char(v_fin, 'DD/MM/YYYY'),
     fn_persona_actual_id(),
     coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Quitado de la boleta.'));

  delete from movimientos_planilla where id = p_movimiento_id;
end;
$function$;

-- Escribe la auditoría (por eso security definer: desde la 0508 solo lo hacen
-- funciones que corren como su dueño; la prueba 402 lo vigila) y borra plata de
-- una boleta: no es una puerta para la app.
revoke execute on function public.fn_retirar_movimiento(uuid, text) from public, anon, authenticated;

-- ── 3 · fn_quitar_movimiento (0327): lo mismo de siempre, ahora con rastro ────
create or replace function public.fn_quitar_movimiento(p_movimiento_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar bonos o descuentos.';
  end if;
  -- CAMBIO 0606 · el candado de periodo pagado y el borrado viven en
  -- fn_retirar_movimiento, que además deja el rastro que aquí faltaba.
  perform fn_retirar_movimiento(p_movimiento_id, 'Quitado desde Planilla.');
end;
$function$;

-- ── 4 · fn_documento_anular (0157 + CAMBIO 0606) ───────────────────────────────
create or replace function public.fn_documento_anular(p_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare r documentos_firmados%rowtype;
        v_fin date;  -- CAMBIO 0606
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional anula documentos firmados.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se anula. Si el archivo era de otra persona, eso tiene que quedar dicho.';
  end if;

  -- CAMBIO 0606: `for update`, para que dos anulaciones a la vez no se crucen.
  select * into r from documentos_firmados where id = p_id for update;
  if not found then raise exception 'Ese documento no existe.'; end if;
  if r.anulado_at is not null then raise exception 'Ese documento ya estaba anulado.'; end if;

  -- ⇩⇩⇩ CAMBIO 0606 ⇩⇩⇩ UN BONO EN BOLETA SALE DE LA BOLETA AL ANULARSE.
  -- Sin esto la línea de S/ 180 seguía sumando sin papel detrás, y si la persona
  -- volvía a firmar quedaban dos. Si su periodo ya se pagó, no se anula: se dice
  -- en qué planilla se pagó y qué hacer.
  if r.tipo = 'bono' and r.movimiento_id is not null then
    select pp.fecha_fin into v_fin
      from movimientos_planilla m join periodos_planilla pp on pp.id = m.periodo_id
     where m.id = r.movimiento_id
       for share of pp;
    if fn_fecha_en_periodo_pagado(
         (select pp.fecha_ini from movimientos_planilla m join periodos_planilla pp on pp.id = m.periodo_id
           where m.id = r.movimiento_id),
         r.persona_id) then
      raise exception 'Este bono ya se PAGÓ con la planilla del periodo que cerró el %: anular la constancia dejaría un pago sin papel. Reabre el periodo, o corrígelo con un descuento en el siguiente.',
        to_char(v_fin, 'DD/MM/YYYY');
    end if;
    perform fn_retirar_movimiento(r.movimiento_id, 'Se anuló su constancia del bono: ' || trim(p_motivo));
  end if;

  update documentos_firmados
     set anulado_at = now(), anulado_por = fn_persona_actual_id(), anulado_motivo = trim(p_motivo)
   where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (coalesce(r.persona_id, fn_persona_actual_id()), 'documento_anulado',
     r.tipo || ' · firmado el ' || r.fecha_firma::text, 'anulado',
     fn_persona_actual_id(), trim(p_motivo));
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (606, 'anular_el_bono_lo_saca_de_la_boleta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- Lo que se ve en el SQL Editor al terminar: las tres en true.
select to_regprocedure('public.fn_retirar_movimiento(uuid, text)') is not null as retirar_existe,
       position('CAMBIO 0606' in (select prosrc from pg_proc where proname = 'fn_documento_anular')) > 0 as anular_es_0606,
       position('CAMBIO 0606' in (select prosrc from pg_proc where proname = 'fn_quitar_movimiento')) > 0 as quitar_es_0606,
       (select nombre from migraciones_aplicadas where numero = 606) as registro;
