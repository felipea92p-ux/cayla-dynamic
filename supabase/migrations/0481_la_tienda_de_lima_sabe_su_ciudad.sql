-- ============================================================================
-- 0481 — La Tienda de Lima sabe su ciudad
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la sede `003` («Tienda LIM») tenga `ciudad = 'Lima'`, igual que su
--   hermana el Taller (`LIM`). Con eso `etiquetaDeSede` (packages/shared) la
--   rotula «Tienda · Lima» y al Taller «Taller · Lima»; sin ella la tienda
--   cae a su nombre y las dos sedes de Lima quedan con dos formatos.
--
-- POR QUÉ FALTABA
--   La 0279 rellenó la ciudad POR CÓDIGO de las cuatro sedes que existían
--   (TRU, LIM, AQP, CCO). La tienda de Lima nació después, con el código `003`
--   que le puso el ERP de tiendas (0216), y el formulario de /admin/sedes no
--   pide ciudad: solo código, nombre y tipo. Nadie la llenó porque no había
--   por dónde.
--
-- QUÉ ASUME
--   `sedes.ciudad` (0279). Medido en producción el 2026-09-19: la fila `003`
--   existe, es de tipo `tienda`, tiene `ciudad` en NULL y está inactiva.
--
-- QUÉ NO HACE, A PROPÓSITO
--   · NO activa la sede. Reactivarla es un clic en /admin/sedes («Reactivar»)
--     y es decisión de quien la abre, no de una migración.
--   · NO toca nada que retail lea. La vista `retail.sedes` expone
--     id, codigo, nombre, tipo, tienda_asociada_id y activo — `ciudad` no está
--     ahí — y la ubicación «Tienda LIM» que retail creó el 2026-09-18 enlaza
--     por `sede_dynamic_id`, que esta migración no cambia.
--   · NO infiere la ciudad de ninguna otra sede: un `where codigo = '003'` y
--     nada más. Adivinar por tipo o por nombre es lo que la 0282 corrigió con
--     Central.
--
-- IDEMPOTENTE
--   Solo rellena si está vacía: repegarla no pisa una corrección hecha a mano.
--   Si la sede `003` no existe (por ejemplo en una base local nueva) no hace
--   nada y no falla.
--
-- SE ROMPE SI
--   Alguien crea otra sede con código `003` en otra ciudad: el `where` lo
--   toma por código y le pondría Lima. El código no se cambia una vez creado
--   (0368), así que solo pasaría con una base reconstruida a mano.
--
-- CÓMO SE REVIERTE
--   update sedes set ciudad = null where codigo = '003';
-- ============================================================================

update sedes set ciudad = 'Lima' where codigo = '003' and ciudad is null;

insert into migraciones_aplicadas (numero, nombre)
values (481, 'la_tienda_de_lima_sabe_su_ciudad')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

do $mig$
declare
  r record;
begin
  select codigo, nombre, tipo, ciudad, activa into r from sedes where codigo = '003';
  if not found then
    raise notice '0481 · la sede 003 no existe en esta base: no había nada que llenar.';
  else
    raise notice '0481 · 003 (%): tipo=%, ciudad=%, activa=%',
      r.nombre, r.tipo, coalesce(r.ciudad, '(SIN CIUDAD)'), r.activa;
    if not r.activa then
      raise notice '0481 · sigue inactiva: reactívala en /admin/sedes para poder asignarle personas.';
    end if;
  end if;
end $mig$;
