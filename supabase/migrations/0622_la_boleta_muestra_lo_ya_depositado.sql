-- ============================================================================
-- 0622 · La boleta muestra lo que ya se depositó, debajo y fuera del total
-- ============================================================================
--
-- QUÉ PROMETE
--   Una función de solo lectura, `fn_boleta_depositos(persona, desde, hasta)`,
--   que devuelve las filas del libro de desembolsos (0155) de UNA persona cuya
--   fecha de pago cae dentro del periodo de la boleta: ventana, año, monto,
--   fecha y vía. La boleta las imprime en un bloque propio, debajo del total,
--   que NO se suma al pago del mes.
--
-- POR QUÉ
--   Pedido de Felipe el 2026-11-25: «¿y dónde aparece la CTS que ya pagué, de
--   cada uno?». La CTS de noviembre se depositó el 14-nov (transferencia BCP),
--   se anotó en el libro, y desde ese momento solo se veía en Provisiones,
--   abriendo la fila de cada persona. La boleta —el papel que la persona lee—
--   no decía nada: ni que se le depositó, ni cuánto. Y el día que la CTS se
--   registró por error como movimiento de planilla, lo único que la boleta
--   SÍ mostraba era el error: un «bono» sumado al total.
--
--   Lo que un pago por fuera de planilla tiene que decir en la boleta es
--   justo lo contrario de un movimiento: que existió, cuánto fue y cuándo,
--   SIN entrar en «Total a recibir este mes», porque esa plata ya salió.
--
-- QUÉ ASUME
--   · Que `desembolsos_beneficios` es el registro de lo pagado FUERA de la
--     planilla (su comentario lo dice; `fn_registrar_desembolso` es «ya se
--     pagó por fuera»). Por eso nada de lo que devuelve esta función puede
--     estar también en los movimientos del periodo: no hay doble conteo.
--   · Que la persona puede ver lo que se le depositó a ella. La tabla sigue
--     cerrada (solo admin y líder la leen, 0153): esta función es la puerta,
--     y deja pasar a admin/líder para cualquiera, y a cada persona solo para
--     sí misma. No devuelve la `nota` (texto interno de DO, puede citar a
--     otras personas) ni quién lo registró.
--
-- POR QUÉ ASÍ
--   DECIDÍ: una función con rango de fechas, que sirve igual a «Lo mío» (su
--     periodo abierto) y al panel (cualquier periodo, también los pagados), y
--     un bloque en la boleta en vez de una fila más de la tabla del pago.
--   DESCARTÉ: leer el libro dentro de `fn_planilla_calcular_persona` /
--     `fn_proyeccion_periodo`. Son las funciones de plata más grandes del
--     sistema, la foto del pago depende de ellas, y esto no cambia ni un
--     céntimo: no justifica reescribirlas. Es el mismo criterio con el que la
--     subvención de practicantes (0467/0485) vive en su propia función.
--
-- CÓMO SE REVIERTE
--   drop function fn_boleta_depositos(uuid, date, date);
--   La boleta, sin la función, deja de dibujar el bloque y nada más.
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================

create or replace function public.fn_boleta_depositos(
  p_persona_id uuid,
  p_desde      date,
  p_hasta      date
)
returns table (
  ventana    text,
  anio       int,
  monto      numeric,
  fecha_pago date,
  origen     text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  -- `is not true` en las dos mitades: una comparación de uuid contra
  -- fn_persona_actual_id() da null sin sesión, y un null no autoriza.
  if fn_es_admin_o_lider() is not true
     and (p_persona_id = fn_persona_actual_id()) is not true then
    raise exception 'Solo puedes ver lo depositado a tu nombre.';
  end if;

  return query
  select d.ventana, d.anio, d.monto, d.fecha_pago, d.origen
    from desembolsos_beneficios d
   where d.persona_id = p_persona_id
     and d.fecha_pago between p_desde and p_hasta
   -- Desempate explícito (ver CLAUDE.md, los empates de `now()`): dos pagos
   -- del mismo día y la misma ventana salen siempre en el mismo orden.
   order by d.fecha_pago, d.ventana, d.anio, d.created_at, d.id;
end;
$fn$;

comment on function fn_boleta_depositos(uuid, date, date) is
  'Lo pagado FUERA de planilla (libro de desembolsos, 0155) a una persona '
  'entre dos fechas, para el bloque informativo de la boleta. No se suma al '
  'total del mes. Admin/líder: cualquiera; cada persona: solo a sí misma (0622).';

grant  execute on function fn_boleta_depositos(uuid, date, date) to authenticated;
revoke execute on function fn_boleta_depositos(uuid, date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (622, 'la_boleta_muestra_lo_ya_depositado')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
