-- ============================================================================
-- 0255 — Marcar una liquidación como pagada deja de reventar por una nota corta
-- ============================================================================
--
-- QUÉ PROMETE
--   Que escribir «ok» en el campo «nota» de la pantalla de Liquidaciones y
--   pulsar «Marcar como pagada» congele la liquidación, en vez de fallar con el
--   nombre de un constraint de Postgres. Y que una liquidación legítima de
--   S/0.00 quede escrita en la auditoría como «S/0.00» y no como «S/.00».
--
-- QUÉ ASUME
--   La 0167: `fn_liquidacion_pagar` es su única definición vigente —comprobado
--   con ./scripts/donde-vive.sh, una sola migración la define— y deja rastro en
--   `correcciones_auditoria`.
--   Esa tabla tiene `correcciones_auditoria_motivo_check`, que hoy es
--   literalmente `CHECK ((length(TRIM(BOTH FROM motivo)) >= 3))`.
--
-- ── LOS DOS DEFECTOS, MEDIDOS ───────────────────────────────────────────────
--
-- Medidos el 2026-08-14 contra el Postgres local, dentro de BEGIN … ROLLBACK.
-- Los dos son PREVIOS a la 0251 y no tienen nada que ver con anular: viven en
-- `fn_liquidacion_pagar` desde la 0167. Se arreglan acá porque son la otra
-- mitad del mismo trámite y porque la 0251 ya se blindó contra el primero en su
-- lado, dejando el de su función hermana sin tocar.
--
-- (1) UNA NOTA DE 1 O 2 CARACTERES TIRA LA OPERACIÓN, Y SE LLEGA DESDE LA
--     PANTALLA. La nota es un campo libre y OPCIONAL —«nota (ej. transferencia
--     BCP)»— que `apps/web/app/(admin)/admin/liquidaciones/page.tsx:139-141`
--     manda tal cual: `p_nota: nota.trim() || null`. La función la usa para dos
--     cosas: la guarda en `liquidacion_pagada.nota` y la reutiliza como `motivo`
--     de la fila de auditoría. Para el motivo hace
--     `coalesce(nullif(trim(coalesce(p_nota, '')), ''), 'Liquidación marcada como pagada')`,
--     que cubre el vacío y el nulo pero NO el corto: «ok» sobrevive al nullif,
--     llega al insert con dos caracteres y choca contra el CHECK. Medido:
--
--       select fn_liquidacion_pagar('…','ok');
--       ERROR 23514: new row for relation "correcciones_auditoria" violates
--                    check constraint "correcciones_auditoria_motivo_check"
--
--     Sin nota funciona, y con «transferencia BCP» funciona: falla solo la
--     franja de 1 a 2 caracteres, que es justo lo que alguien teclea con prisa.
--     Y lo que ve no es una frase en español: es el nombre de un constraint, en
--     la pantalla que mueve el último pago de una persona que ya se fue.
--
--     Es EXACTAMENTE el modo de fallo que la 0251 identificó y blindó para
--     `fn_liquidacion_anular` (0251:243-248, «sin esta comprobación el usuario
--     vería un error crudo de Postgres en vez de una frase en español»). Ahí el
--     motivo es OBLIGATORIO y por eso se rechaza; acá la nota es OPCIONAL, así
--     que rechazar sería absurdo —una nota vacía sí se acepta— y lo correcto es
--     no perderla ni romper por ella.
--
-- (2) UNA LIQUIDACIÓN LEGÍTIMA DE S/0.00 SE REGISTRA COMO «S/.00». La máscara
--     es `FM999999.00`, y `to_char(0, 'FM999999.00')` devuelve «.00» — medido,
--     al lado de `to_char(0, 'FM999999990.00')`, que devuelve «0.00». La 0251 ya
--     usa la máscara con el cero delante en su fila de auditoría y deja escrito
--     por qué; la de `pagar` se quedó con la vieja.
--
--     No es cosmético del todo: la 0251 existe porque una liquidación de S/0.00
--     puede ser legítima y hay que poder distinguirla de una anulada. La fila
--     que documenta ese cero es justo la que lo escribe ilegible.
--
-- ── POR QUÉ COMPONER Y NO SUSTITUIR ─────────────────────────────────────────
--
-- La salida fácil sería mandar el motivo por defecto cuando la nota es corta.
-- Se descartó: la nota que alguien escribió es un dato suyo, y la auditoría es
-- el sitio donde se va a buscar. Se compone —«Liquidación marcada como pagada ·
-- nota: ok»— así que no se pierde nada, el CHECK se cumple siempre y la fila se
-- lee igual de bien que antes. La nota, además, sigue guardándose entera y sin
-- tocar en `liquidacion_pagada.nota`, como hasta ahora.
--
-- ── QUÉ NO CAMBIA ───────────────────────────────────────────────────────────
--   · Sin nota, el motivo sigue siendo «Liquidación marcada como pagada», con
--     esas palabras. Una nota de 3 o más caracteres sigue yendo tal cual.
--   · No se toca el cálculo: `fn_liquidacion` se sigue llamando igual y se
--     congela lo que devuelve AHORA. Ni un céntimo se mueve.
--   · No se tocan las columnas, los CHECK ni los lectores de la 0251, ni la
--     0244, ni `fn_liquidacion_anular`.
--
-- ── EL md5 DE PARTIDA SE LE PIDE A PRODUCCIÓN, NO A ESTA MAC ────────────────
--
-- Antes de pegar esto, corre en el SQL Editor de Supabase:
--
--   select md5(prosrc) from pg_proc where proname = 'fn_liquidacion_pagar';
--
-- Tiene que devolver   0f54650a4fd955b83e937486cfe8e7eb
-- que es el de la 0167 sin tocar. Si devuelve otra cosa, PARA: alguien la
-- reescribió por otro camino y copiar esto encima revertiría ese cambio en
-- silencio. Ese md5 de arriba se leyó en el Postgres local; vale como aviso de
-- que algo no cuadra, no como comprobación. La comprobación es la de producción.
--
-- Después de pegar, el mismo select tiene que devolver otra cosa. En local queda
-- en   0e5b1a1d4c3d3e75d0ba1e160d450d79
-- igual pegando esta migración encima de la 0167 que reconstruyendo desde cero.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--   Un solo `create or replace`. Se puede pegar dos veces.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Volver a pegar `fn_liquidacion_pagar` tal cual está en la 0167. Nada de lo
--   que escribe esta migración cambia una cifra: revertirla no mueve un céntimo,
--   solo devuelve el error crudo y el «S/.00».
-- ============================================================================


-- ── Marcar como pagada, sin romper por la nota ──────────────────────────────
-- Copiada de la 0167 —su única definición, comprobado con ./scripts/donde-vive.sh—
-- con DOS cambios, los dos marcados abajo. El guard, el cálculo, el insert de la
-- foto y el valor de retorno quedan palabra por palabra como estaban.
create or replace function fn_liquidacion_pagar(p_persona_id uuid, p_nota text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_l    jsonb;
  v_ver  int;
  -- CAMBIO 0255 · la nota limpia se calcula UNA vez. Antes la misma expresión
  -- estaba escrita dos veces, y solo una de las dos tenía que cumplir el CHECK.
  v_nota text := nullif(trim(coalesce(p_nota, '')), '');
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder marca una liquidación como pagada.';
  end if;

  -- Se congela lo que la función calcula AHORA, no un número que venga de la
  -- pantalla: si el monto viajara desde el navegador, la foto podría guardar algo
  -- que el sistema nunca calculó — y sería indistinguible de un cálculo real.
  v_l := fn_liquidacion(p_persona_id, null);

  select coalesce(max(version), 0) + 1 into v_ver
  from liquidacion_pagada where persona_id = p_persona_id;

  insert into liquidacion_pagada (
    persona_id, version, congelada_por, nota,
    persona, fecha_ingreso, fecha_cese,
    monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle
  ) values (
    p_persona_id, v_ver, fn_persona_actual_id(), v_nota,
    v_l->>'persona',
    (v_l->>'fecha_ingreso')::date,
    (v_l->>'fecha_cese')::date,
    coalesce((v_l->'periodo'->>'monto')::numeric, 0),
    coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0),
    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0),
    coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0),
    (v_l->>'total')::numeric,
    v_l
  );

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'liquidacion_pagada', null,
     -- ── CAMBIO 0255 · la máscara lleva el cero delante ───────────────────
     -- `to_char(0, 'FM999999.00')` devuelve «.00». Una liquidación legítima de
     -- S/0.00 existe —es la razón de ser de la columna `anulada` de la 0251— y
     -- su fila de auditoría tiene que poder leerse.
     'S/' || to_char((v_l->>'total')::numeric, 'FM999999990.00') || ' · version ' || v_ver,
     fn_persona_actual_id(),
     -- ── CAMBIO 0255 · una nota corta ya no tira la operación ─────────────
     -- El CHECK de `correcciones_auditoria` exige 3 caracteres. La nota es
     -- opcional, así que no se rechaza: se compone, y así no se pierde lo que
     -- alguien escribió. Sin nota, el texto por defecto es el de siempre.
     case
       when v_nota is null        then 'Liquidación marcada como pagada'
       when length(v_nota) >= 3   then v_nota
       else 'Liquidación marcada como pagada · nota: ' || v_nota
     end);

  return jsonb_build_object('version', v_ver, 'total', (v_l->>'total')::numeric);
end;
$fn$;

comment on function fn_liquidacion_pagar(uuid, text) is
  'Congela la liquidación de una persona cesada tal como se calcula ahora, y '
  'deja rastro. La nota es opcional; una nota corta ya no tira la operación '
  '(0255). Ver 0167.';

revoke execute on function fn_liquidacion_pagar(uuid, text) from public, anon;
grant  execute on function fn_liquidacion_pagar(uuid, text) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (255, 'marcar_una_liquidacion_pagada_no_revienta_por_una_nota_corta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── Comprobación posterior ──────────────────────────────────────────────────
-- Que la migración diga en voz alta que quedó como prometió. Se pega a mano, y
-- una mano se equivoca. Se comprueba lo que se puede comprobar sin datos: que la
-- máscara nueva escribe el cero, y que la composición del motivo cumple el CHECK
-- en las tres franjas (sin nota, nota corta, nota normal).
do $mig$
declare
  v_nota text;
  v_out  text;
begin
  if to_char(0::numeric, 'FM999999990.00') <> '0.00' then
    raise exception '0255 · la máscara nueva no escribe el cero delante.';
  end if;

  foreach v_nota in array array[null, '', '  ', 'o', 'ok', ' a ', 'transferencia BCP']
  loop
    v_nota := nullif(trim(coalesce(v_nota, '')), '');
    v_out := case
               when v_nota is null      then 'Liquidación marcada como pagada'
               when length(v_nota) >= 3 then v_nota
               else 'Liquidación marcada como pagada · nota: ' || v_nota
             end;
    if length(trim(v_out)) < 3 then
      raise exception '0255 · el motivo compuesto sigue sin cumplir el CHECK para la nota %', coalesce(v_nota, '(nula)');
    end if;
  end loop;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_liquidacion_pagar'
  ) then
    raise exception '0255 · falta fn_liquidacion_pagar.';
  end if;

  if has_function_privilege('anon', 'fn_liquidacion_pagar(uuid, text)', 'execute') then
    raise exception '0255 · anon puede marcar liquidaciones como pagadas, y no debe.';
  end if;

  -- LO QUE ESTA MIGRACIÓN NO PUEDE HABER TOCADO. Si al copiar el cuerpo se
  -- hubiera arrastrado algo de la 0251, el daño no se vería hasta el próximo
  -- cierre del mes.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'liquidacion_pagada'::regclass
      and conname  = 'liquidacion_anulada_en_cero'
  ) then
    raise exception '0255 · se perdió el CHECK liquidacion_anulada_en_cero de la 0251.';
  end if;

  raise notice '0255 · listo. Una nota corta ya no tira la operación, y un cero se escribe «S/0.00».';
end
$mig$;
