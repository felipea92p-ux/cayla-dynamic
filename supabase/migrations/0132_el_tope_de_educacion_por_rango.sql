-- ============================================================================
-- 0132 — El tope de la asignación por educación, por rango.
--
-- QUÉ AGREGA. El «tope por rango» que la 0120 dio por acordado en su cabecera
-- («CAYLA cubre el 75% de la pensión … con un tope por rango») y que nunca se
-- llegó a implementar: quedó solo el candado del comprobante.
--
-- ── POR QUÉ UN TOPE Y NO UN MONTO FIJO ──────────────────────────────────────
--
-- Felipe trajo el 2026-08-04 una escala de educación por rango
-- (90 · 180 · 270 · 360 · 420 · 480) y la primera idea fue pagar ese monto a
-- todos los del rango, sin excepción. No se hizo así, y la razón es la misma que
-- sostiene todo el concepto:
--
--   · El art. 19 f) del D.S. 001-97-TR exige que la asignación esté «debidamente
--     sustentada». Un monto idéntico para todos los del rango no sale de un
--     comprobante: sale de una resta para cuadrar el neto. En la RTF
--     07222-3-2018 (Albis) SUNAT aceptó que los montos eran razonables y aun así
--     el concepto se cayó por falta de sustento — de 33 trabajadores sobrevivió 1.
--
--   · El CHECK `educacion_no_excede_el_comprobante` de la 0120 ya lo impedía a
--     nivel de dato: sin `institucion` y `costo_declarado` la fila no entra.
--     Pagar un fijo por rango habría exigido desarmar ese candado o inventar
--     comprobantes, que es peor que el problema que resolvía.
--
-- Entonces la escala se guarda como lo que legalmente puede ser: un TECHO. Cada
-- persona cobra el 75% de la pensión que sostiene SU comprobante, y nunca más
-- que el techo de su rango. Quien no estudia no cobra educación — y ese es el
-- punto: el concepto distingue, y por eso es defendible.
--
-- ── LO QUE ESTE TOPE NO HACE ────────────────────────────────────────────────
--
-- No se dispara cuando alguien CAMBIA de rango: el trigger vive en
-- asignaciones_educacion, así que si a una persona la bajan de rango con una
-- asignación ya vigente, esa asignación queda por encima del techo nuevo hasta
-- que se la toque. Es un techo de política, no una regla de integridad: el
-- candado legal sigue siendo el del comprobante, que sí es inviolable.
--
-- Y falla ABIERTO a propósito: si la persona no tiene rango vigente, o el rango
-- no tiene techo cargado, la fila pasa. Un techo de política que bloquea por
-- falta de configuración deja a alguien sin cobrar lo que ya justificó.
--
-- SE PUEDE PEGAR SIN MOVER NINGÚN PAGO. Crea la tabla, la llena y engancha el
-- trigger; no toca ninguna asignación existente ni ningún cálculo.
--
-- CÓMO SE REVIERTE:
--   drop trigger trg_educacion_respeta_el_tope on asignaciones_educacion;
--   drop function fn_educacion_respeta_el_tope();
--   drop table topes_educacion_rango;
-- ============================================================================

create table if not exists topes_educacion_rango (
  rango          text primary key
                   check (rango in ('colibri','cayla','caylo','support','aurora','oraculo','archicaylo')),
  tope_mensual   numeric(10,2) not null check (tope_mensual >= 0),
  actualizado_at timestamptz   not null default now()
);

comment on table topes_educacion_rango is
  'Techo mensual de la asignación por educación de cada rango. NO es un monto a pagar: '
  'cada persona cobra el 75% de lo que sostiene su comprobante (0120) y nunca más que '
  'este techo. Espejo de RANGOS.topeEducacion en apps/web/lib/rangos.ts.';

-- Escala del 2026-08-04. Idempotente: repetir la migración no duplica ni pisa
-- con valores viejos.
insert into topes_educacion_rango (rango, tope_mensual) values
  ('colibri',     90),
  ('cayla',      180),
  ('caylo',      180),
  ('support',    270),
  ('aurora',     360),
  ('oraculo',    420),
  ('archicaylo', 480)
on conflict (rango) do update
  set tope_mensual   = excluded.tope_mensual,
      actualizado_at = now();

-- ── El candado ──────────────────────────────────────────────────────────────
create or replace function fn_educacion_respeta_el_tope()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_rango text;
  v_tope  numeric;
begin
  select a.rango into v_rango
    from asignaciones_salario a
   where a.persona_id = new.persona_id
     and a.vigente_hasta is null
   order by a.vigente_desde desc
   limit 1;

  if v_rango is null then
    return new;  -- sin rango vigente no hay techo que aplicar
  end if;

  select t.tope_mensual into v_tope
    from topes_educacion_rango t
   where t.rango = v_rango;

  if v_tope is null then
    return new;  -- rango sin techo cargado: falla abierto a propósito
  end if;

  if new.monto > v_tope then
    raise exception
      'La asignación por educación (S/%) supera el tope del rango % (S/%). '
      'Sube el tope en topes_educacion_rango si la política cambió, o ajusta el monto.',
      new.monto, v_rango, v_tope;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_educacion_respeta_el_tope on asignaciones_educacion;
create trigger trg_educacion_respeta_el_tope
  before insert or update of monto, persona_id on asignaciones_educacion
  for each row execute function fn_educacion_respeta_el_tope();

notify pgrst, 'reload schema';
