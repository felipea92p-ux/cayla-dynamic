-- ============================================================================
-- 0499 · «Liquidada» quiere decir: la liquidación cubre su cese ACTUAL
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_persona_liquidada(persona)` conteste «sí» solo cuando la ÚLTIMA
--   liquidación de esa persona no está anulada Y corresponde al cese que la persona
--   tiene hoy. Para quien está activa, o para quien cesó otra vez después de una
--   liquidación anterior, contesta «no».
--
-- QUÉ ASUME
--   · Que `liquidacion_pagada` es inmutable y guarda, en cada versión, la fecha de
--     cese que se liquidó (`fecha_cese`). La anulación NO toca la fila original: agrega
--     una versión nueva con `anulada = true` (`fn_liquidacion_anular`, 0251).
--   · Que el único modo de cambiar `personas.fecha_cese` es `fn_cesar_persona` /
--     `fn_reactivar_persona` (el trigger `trg_personas_cese_solo_por_rpc` lo exige),
--     así que comparar las dos fechas no se rompe por una edición suelta.
--
-- ── EL PROBLEMA, EN DOS FORMAS ───────────────────────────────────────────────
--   La función decía «existe alguna fila de liquidación no anulada para esta persona».
--   Eso falla de dos maneras, y las dos son silenciosas:
--
--   1 · **Quien vuelve a trabajar después de ser liquidada queda «liquidada» para
--       siempre.** `fn_dias_por_revisar` y `fn_marcas_apartadas` excluyen a quien
--       `fn_persona_liquidada` dice que ya cobró («deja de aparecer para siempre en
--       esta cola», 0422). Una persona que se liquidó, regresó y sigue marcando deja de
--       aparecer en las dos colas donde se ven los marcajes que pueden pagarle de menos.
--       No falla nada, no hay error: simplemente sus problemas dejan de verse.
--       El sistema no tiene un flujo de reingreso —`fn_reactivar_persona` existe «porque
--       a veces la baja fue un error»—, así que esto no se notó hasta regularizar a la
--       primera persona que se fue y volvió.
--
--   2 · **Anular la liquidación no la deshace para esta función.** Anular agrega una
--       versión anulada y deja la original tal cual (anulada = false), así que
--       «existe una fila no anulada» seguía dando verdadero DESPUÉS de anular. La lista de
--       liquidaciones pendientes sí mira la última versión y vuelve a mostrar a la persona;
--       estas dos colas no. Medido en una base desechable antes de escribir esto.
--
-- ── POR QUÉ COMPARAR LA FECHA DE CESE, Y POR QUÉ LA ÚLTIMA VERSIÓN ───────────
--   «La última versión» arregla (2): es lo que ya hace la lista de pendientes, y deja
--   una sola definición de «está liquidada» en vez de dos que discrepan.
--   «La misma fecha de cese» arregla (1) y además algo que aún no ha pasado: una persona
--   que cesa por SEGUNDA vez. Con la definición vieja, su primera liquidación la daba por
--   liquidada de la segunda y nunca se le avisaba que la segunda estaba pendiente.
--   `fn_personas_funciones` ya escribía `fecha_cese is not null and fn_persona_liquidada(...)`
--   por este mismo miedo; ahora lo garantiza la función en vez de cada quien que la llama.
--
-- ── LO QUE NO CAMBIA ─────────────────────────────────────────────────────────
--   Para toda persona hoy cesada y liquidada (una sola liquidación, sin anular, con su
--   fecha de cese puesta) la respuesta sigue siendo «sí», igual que antes: las colas no se
--   mueven para nadie que esté en ese estado. Las 15 pruebas que ya tocaban esta función
--   (272 aserciones) dan lo mismo antes y después.
--
-- ── LA GUARDIA ───────────────────────────────────────────────────────────────
--   Reescribe una función entera, así que se revisa a sí misma: compara el cuerpo que hay
--   en la base contra el que se leyó para escribir esto y PARA sin aplicar nada si es otra
--   versión. El cuerpo no tiene comentarios, así que solo hay una huella; se aceptan la
--   tal cual y la del mismo texto con `\r` por línea (pegar desde Windows). Se pega UNA vez:
--   repegarla para con un mensaje, y es a propósito.
--
-- CÓMO SE REVIERTE
--   Volver a pegar el cuerpo anterior:
--     create or replace function public.fn_persona_liquidada(p_persona_id uuid)
--      returns boolean language sql stable security definer set search_path to 'public'
--     as $$ select exists (select 1 from liquidacion_pagada lp
--                           where lp.persona_id = p_persona_id and lp.anulada is not true); $$;
--
-- SE ROMPE SI
--   · Alguien cambia la fecha de cese de una persona ya liquidada por una vía que no sea
--     cesar/reactivar: dejaría de contar como liquidada y reaparecería en las colas y en
--     la lista de pendientes. Es el comportamiento buscado (la liquidación ya no describe
--     su cese) y se corrige anulando y volviendo a liquidar.
-- ============================================================================

-- ── 0 · La guardia ──────────────────────────────────────────────────────────
do $guardia$
declare
  v_src text;
  v_h1 text; v_h2 text;
begin
  select p.prosrc into v_src from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_persona_liquidada'
     and pg_get_function_identity_arguments(p.oid) = 'p_persona_id uuid';
  if v_src is null then
    raise exception '0499 · PARA. fn_persona_liquidada(uuid) no existe en esta base. No se aplicó nada.';
  end if;
  v_h1 := md5(v_src);
  v_h2 := md5(replace(v_src, chr(13), ''));
  if '81872be48022c6beea6825c8f9d4d871' not in (v_h1, v_h2) then
    raise exception '0499 · PARA. fn_persona_liquidada en esta base es % (% caracteres) y se esperaba 81872be48022c6beea6825c8f9d4d871 (130 caracteres). Es OTRA versión: pegar esto la borraría. No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_persona_liquidada.',
      v_h1, length(v_src);
  end if;
  raise notice '0499 · ok: fn_persona_liquidada coincide con el repositorio.';
end
$guardia$;

-- ── 1 · fn_persona_liquidada ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_persona_liquidada(p_persona_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- CAMBIO 0499 · La ÚLTIMA versión, no «alguna»: una versión anulada no deja
  -- atrás la original viva. Y solo si esa liquidación es del cese que la persona
  -- tiene HOY: quien volvió a trabajar, o cesó otra vez, no está liquidada.
  -- Sin ninguna liquidación el subselect no devuelve fila y el coalesce da false.
  select coalesce((
    select lp.anulada is not true
           and p.fecha_cese is not null
           and lp.fecha_cese = p.fecha_cese
      from liquidacion_pagada lp
      join personas p on p.id = lp.persona_id
     where lp.persona_id = p_persona_id
     order by lp.version desc
     limit 1
  ), false);
$function$
;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (499, 'liquidada_es_de_su_cese_actual')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
