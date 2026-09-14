-- ============================================================================
-- 0435_una_persona_le_escribe_a_su_encargada.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que cualquier persona escriba, desde "Lo mío", un mensaje libre —sin
--   categoría fija, a diferencia de "pedir vacaciones" o "pedir revisión de
--   un día"— y que su encargada (o Desarrollo Organizacional, que ya ve todo
--   lo demás) lo lea y le responda. Nace del hallazgo 1 de
--   docs/auditoria-pantalla-info-resumen-2026-09-13.md: hoy esa conversación
--   solo existe por WhatsApp, porque las cuatro puertas que ya tiene esta
--   pantalla (anuncios, acuses, vacaciones, revisión de un día) son todas de
--   un tema fijo.
--
-- QUÉ ASUME
--   Nada nuevo. Tabla nueva, dos funciones nuevas. No toca `personas`,
--   `solicitudes_cambio_perfil` ni ninguna función existente.
--
-- ── POR QUÉ UNA TABLA APARTE, Y NO UN TIPO NUEVO EN `solicitudes_cambio_perfil` ─
--
-- Esa tabla exige un `campo` que exista en `catalogo_campos_perfil` y compara
-- un `valor_anterior` contra un `valor_propuesto` — está hecha para "cambia
-- este dato de mi ficha por este otro", no para "quiero decirte algo". Meter
-- un mensaje libre ahí habría sido forzar una forma en la otra, el mismo
-- error que esta migración existe para no repetir con
-- `solicitudes_vacaciones` (ver su propio encabezado, 0330).
--
-- ── POR QUÉ NO HAY "PARA QUIÉN", Y POR QUÉ NO HACE FALTA UN JEFE DIRECTO ────
--
-- Este esquema no tiene, en ningún lado, una columna `jefe_directo` — "quién
-- es la encargada de una sede" ya se resuelve hoy sin ella:
-- `rol = 'supervisor_sede' and sede_base_id = X` (mismo criterio que
-- `personas_select_supervisor`). Inventar un destinatario explícito habría
-- sido meter un concepto de organización que el resto del sistema no tiene —
-- justo lo que el informe de comparación con Workday/Oracle nombra como la
-- complejidad que Dynamic no necesita pagar a esta escala. El mensaje se
-- guarda con la SEDE de quien lo escribe, y lo ve quien esa sede ya reconoce
-- como su encargada, más DO/admin, que ya ven todo lo demás en este sistema.
--
-- ── POR QUÉ LA SEDE SE GUARDA, Y NO SE LEE EN VIVO DE `personas` ────────────
--
-- Misma razón que `planilla_pagada_detalle.sede_codigo` (0096): es una foto
-- de dónde estaba la persona CUANDO escribió, no de dónde está ahora. Si la
-- transfieren de sede después de escribir y antes de que le respondan, el
-- mensaje se lo sigue viendo su encargada de entonces, no una que nunca lo
-- vio llegar.
--
-- ── QUÉ PASA SI NADIE RESPONDE (Vogels) ──────────────────────────────────────
--
-- Nada automático, a propósito: este repositorio ya decidió, mirando
-- Workday/Oracle, no construir un motor de escalamiento genérico a esta
-- escala (ver la sección 2 del informe de comparación). Un mensaje
-- `pendiente` simplemente no caduca — mismo criterio que ya usa
-- `lib/bandeja-mia.ts` para lo que depende de alguien más ("un contrato sin
-- firmar sigue contando el día 90 igual que el día 1"). Sigue apareciendo
-- como pendiente, para las dos partes, hasta que se responda.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_responder_mensaje_encargada(uuid, text);
--   drop function if exists fn_enviar_mensaje_encargada(text);
--   drop table if exists mensajes_encargada;
--   Revertir vuelve a dejar esa conversación fuera del sistema — ningún otro
--   dato depende de esta tabla.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final.
-- ============================================================================

-- ── 1 · El mensaje ───────────────────────────────────────────────────────────
create table if not exists mensajes_encargada (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id),
  -- La sede de quien escribe, AL MOMENTO de escribir. Ver el porqué arriba.
  sede_id        uuid not null references sedes(id),
  mensaje        text not null,
  estado         text not null default 'pendiente'
                   check (estado in ('pendiente', 'respondido')),
  creada_at      timestamptz not null default now(),
  respuesta      text,
  respondida_at  timestamptz,
  respondida_por uuid references personas(id),
  constraint chk_mensaje_encargada_no_vacio check (length(trim(mensaje)) > 0),
  constraint chk_mensaje_encargada_respondido_completo check (
    (estado = 'respondido') = (
      respuesta is not null and respondida_at is not null and respondida_por is not null
    )
  )
);

comment on table mensajes_encargada is
  'Un mensaje libre de una persona hacia su encargada (o DO). Sin categoría fija, a diferencia de solicitudes_vacaciones/revisiones_pedidas — es la puerta para lo que no encaja en esas otras.';
comment on column mensajes_encargada.sede_id is
  'La sede de quien escribe AL ESCRIBIR, no la de ahora — igual que planilla_pagada_detalle.sede_codigo. Si la transfieren después, el mensaje se queda con su encargada de entonces.';

create index if not exists idx_mensajes_encargada_persona
  on mensajes_encargada (persona_id, creada_at desc);
create index if not exists idx_mensajes_encargada_sede_pendientes
  on mensajes_encargada (sede_id, creada_at) where estado = 'pendiente';

alter table mensajes_encargada enable row level security;

drop policy if exists mensajes_encargada_select_propia on mensajes_encargada;
create policy mensajes_encargada_select_propia on mensajes_encargada
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists mensajes_encargada_select_supervisor on mensajes_encargada;
create policy mensajes_encargada_select_supervisor on mensajes_encargada
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona()
  );

drop policy if exists mensajes_encargada_select_admin_lider on mensajes_encargada;
create policy mensajes_encargada_select_admin_lider on mensajes_encargada
  for select to authenticated using (fn_es_admin_o_lider() is true);

-- Sin policies de insert/update: toda escritura pasa por las RPC security
-- definer de abajo — mismo patrón que solicitudes_vacaciones (0330).
grant select on mensajes_encargada to authenticated;
revoke all on mensajes_encargada from anon, public;

-- ── 2 · Escribir ──────────────────────────────────────────────────────────
create or replace function fn_enviar_mensaje_encargada(p_mensaje text)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
  v_sede    uuid;
  v_id      uuid;
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.';
  end if;

  if length(trim(coalesce(p_mensaje, ''))) = 0 then
    raise exception 'Escribe algo antes de enviarlo.';
  end if;

  select sede_base_id into v_sede from personas where id = v_persona;

  insert into mensajes_encargada (persona_id, sede_id, mensaje)
  values (v_persona, v_sede, trim(p_mensaje))
  returning id into v_id;

  return v_id;
end;
$fn$;
grant execute on function fn_enviar_mensaje_encargada(text) to authenticated;
revoke execute on function fn_enviar_mensaje_encargada(text) from public, anon;

-- ── 3 · Responder — la encargada de esa sede, o DO/admin ────────────────────
create or replace function fn_responder_mensaje_encargada(p_id uuid, p_respuesta text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_m mensajes_encargada%rowtype;
begin
  select * into v_m from mensajes_encargada where id = p_id;
  if not found then
    raise exception 'Ese mensaje ya no existe.';
  end if;

  if fn_es_admin_o_lider() is not true
     and not (fn_rol_actual() = 'supervisor_sede' and v_m.sede_id = fn_sede_actual_persona())
  then
    raise exception 'No puedes responder este mensaje.';
  end if;

  if v_m.estado = 'respondido' then
    raise exception 'Este mensaje ya fue respondido.';
  end if;

  if length(trim(coalesce(p_respuesta, ''))) = 0 then
    raise exception 'Escribe una respuesta antes de enviarla.';
  end if;

  update mensajes_encargada
  set estado = 'respondido',
      respuesta = trim(p_respuesta),
      respondida_at = now(),
      respondida_por = fn_persona_actual_id()
  where id = p_id;
end;
$fn$;
grant execute on function fn_responder_mensaje_encargada(uuid, text) to authenticated;
revoke execute on function fn_responder_mensaje_encargada(uuid, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (435, 'una_persona_le_escribe_a_su_encargada')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables where table_name = 'mensajes_encargada') as tabla_creada,
  (select count(*) from pg_proc where proname = 'fn_enviar_mensaje_encargada') as fn_enviar,
  (select count(*) from pg_proc where proname = 'fn_responder_mensaje_encargada') as fn_responder;
