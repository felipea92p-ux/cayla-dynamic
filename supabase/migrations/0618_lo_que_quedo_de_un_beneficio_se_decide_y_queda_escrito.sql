-- ============================================================================
-- 0618 · Lo que quedó de un beneficio se decide, y queda escrito
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cuando una ventana de beneficio ya pasó y Provisiones todavía le ve
--   saldo, la dirección pueda decir CUÁNTO reconoce la empresa que correspondía
--   en esa ventana, con su motivo, y que eso quede escrito con autor y fecha.
--   La pantalla deja entonces de mostrar «por decidir» el cálculo del sistema y
--   muestra lo decidido menos lo ya depositado.
--
-- POR QUÉ HIZO FALTA (2026-11-14)
--   La CTS de mayo de 2026 (nov-2025 a abr-2026) es anterior a la planilla del
--   sistema: se pagó por Excel y la depositó el contador sobre la remuneración
--   DECLARADA de entonces (S/ 1,130). `fn_provisiones` reconstruye ese semestre
--   con la fórmula de hoy —horas reales sobre el rango completo— y por eso veía
--   S/ 434.28 «pendientes» en cuatro personas. Felipe decidió ese día regularizar
--   sobre lo declarado: S/ 164.79 a una persona y S/ 2.16 a otra, nada a las
--   otras dos. Sin un lugar donde escribir esa decisión, la pantalla habría
--   seguido diciendo «por decidir» para siempre, y la siguiente persona que la
--   leyera habría vuelto a abrir una cuenta ya cerrada —o a pagarla dos veces—.
--
-- QUÉ GUARDA
--   `monto_reconocido` es el TOTAL que la empresa reconoce para esa persona en
--   esa ventana de ese año (no «lo que falta»). Lo que falta lo deriva la
--   pantalla: reconocido − lo depositado según el libro (`desembolsos_beneficios`).
--   Así un depósito posterior no obliga a tocar la decisión, y una decisión no
--   puede contradecir al libro.
--
-- QUÉ ASUME
--   · Que `fn_es_admin()` (0562) existe: solo la dirección decide plata ya vencida.
--   · Que `desembolsos_beneficios` (0155) sigue siendo dónde se anota lo pagado.
--
-- POR QUÉ ASÍ Y NO DE OTRA FORMA
--   DECIDÍ: una bitácora que solo crece (`secuencia`), donde vale la fila más
--     nueva de cada persona + ventana + año. Cambiar de opinión es escribir otra
--     fila con su motivo; la anterior queda como historia.
--   DESCARTÉ: una columna «saldo decidido» en `desembolsos_beneficios`, porque
--     una decisión existe ANTES de cualquier pago y puede ser «no se debe nada»,
--     y el libro exige monto > 0 y fecha de pago. Y descarté reescribir
--     `fn_provisiones` para que reste la decisión: es la función que alimenta el
--     pago real de gratificación y CTS, pesa 900 líneas y tiene 28 versiones;
--     meterle una regla de un semestre histórico no pasa la prueba del núcleo
--     mínimo.
--   SE ROMPE SI alguien lee el pendiente de una ventana vencida desde otro lugar
--     que no sea la pantalla de Provisiones (un reporte nuevo, una liquidación
--     que sume ventanas pasadas): esa lectura no conoce la decisión. Hoy nadie
--     más la lee; si aparece, debe pasar por `fn_beneficio_decision_vigente`.
--
-- LOS ESTADOS QUE NO DEBEN EXISTIR, Y CÓMO SE IMPIDEN
--   · Una decisión sin motivo → check de longitud.
--   · Una decisión sobre una ventana que todavía no vence → la función la
--     rechaza (antes de la fecha de pago no hay nada que «decidir»: se acumula).
--   · Una decisión escrita o corregida por debajo → sin insert/update/delete
--     para `authenticated`; la única puerta es `fn_beneficio_decidir`, y un
--     trigger rechaza update y delete incluso desde esa puerta.
--   · Dos decisiones «vigentes» → no hay bandera de vigencia que mantener: la
--     vigente es la de mayor `secuencia`, que no empata nunca.
--
-- CÓMO SE REVIERTE
--   drop function fn_beneficio_decidir(uuid, text, int, numeric, text);
--   drop function fn_beneficio_decision_vigente(int);
--   drop table beneficios_decisiones;
--   La pantalla vuelve sola a «por decidir»: si no puede leer la tabla, no aplica
--   ninguna decisión. No toca ningún dato de otra tabla.
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================

create table if not exists beneficios_decisiones (
  id               uuid primary key default gen_random_uuid(),
  secuencia        bigint generated always as identity,
  persona_id       uuid not null references personas(id),
  ventana          text not null check (ventana = any (array['grati_s1','grati_s2','cts_may','cts_nov'])),
  anio             integer not null check (anio >= 2020 and anio <= 2100),
  monto_reconocido numeric(10,2) not null check (monto_reconocido >= 0),
  motivo           text not null check (length(trim(motivo)) >= 10),
  decidido_por     uuid references personas(id),
  created_at       timestamptz not null default now()
);

create index if not exists beneficios_decisiones_vigente_idx
  on beneficios_decisiones (anio, persona_id, ventana, secuencia desc);

comment on table beneficios_decisiones is
  'Lo que la dirección reconoce que correspondía en una ventana de beneficio ya vencida '
  '(0618). Bitácora que solo crece: vale la fila de mayor secuencia por persona + ventana '
  '+ año. monto_reconocido es el TOTAL de la ventana, no lo que falta: lo que falta es '
  'reconocido − lo depositado según desembolsos_beneficios. Solo se escribe por '
  'fn_beneficio_decidir.';

alter table beneficios_decisiones enable row level security;
revoke all on beneficios_decisiones from authenticated, anon;
drop policy if exists beneficios_decisiones_lectura on beneficios_decisiones;
create policy beneficios_decisiones_lectura on beneficios_decisiones
  for select using (fn_es_admin_o_lider());
grant select on beneficios_decisiones to authenticated;

-- La historia no se corrige: se escribe otra fila.
create or replace function fn_beneficios_decisiones_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Una decisión sobre un beneficio no se edita ni se borra: se registra otra con su motivo.'
    using errcode = 'P0001';
end;
$$;

drop trigger if exists beneficios_decisiones_inmutable on beneficios_decisiones;
create trigger beneficios_decisiones_inmutable
  before update or delete on beneficios_decisiones
  for each row execute function fn_beneficios_decisiones_inmutable();

-- ── La única puerta de escritura ─────────────────────────────────────────────
create or replace function fn_beneficio_decidir(
  p_persona_id uuid,
  p_ventana    text,
  p_anio       int,
  p_monto      numeric,
  p_motivo     text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pago date;
  v_id   uuid;
begin
  if fn_es_admin() is not true then
    raise exception 'Solo la dirección puede decidir sobre un beneficio vencido.' using errcode = '42501';
  end if;
  if p_persona_id is null or not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'No existe esa persona.' using errcode = 'P0001';
  end if;
  if p_monto is null or p_monto < 0 then
    raise exception 'El monto reconocido no puede ser negativo.' using errcode = 'P0001';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 10 then
    raise exception 'Falta el motivo de la decisión (al menos 10 caracteres).' using errcode = 'P0001';
  end if;

  -- La fecha legal de cada ventana, la misma que usa fn_provisiones.
  v_pago := case p_ventana
    when 'cts_may'  then make_date(p_anio, 5, 15)
    when 'grati_s1' then make_date(p_anio, 7, 15)
    when 'cts_nov'  then make_date(p_anio, 11, 15)
    when 'grati_s2' then make_date(p_anio, 12, 15)
  end;
  if v_pago is null then
    raise exception 'Ventana desconocida: %.', p_ventana using errcode = 'P0001';
  end if;
  if fn_hoy_lima() <= v_pago then
    raise exception 'Esa ventana todavía no vence (%): se sigue acumulando, no hay nada que decidir.', v_pago
      using errcode = 'P0001';
  end if;

  insert into beneficios_decisiones (persona_id, ventana, anio, monto_reconocido, motivo, decidido_por)
  values (p_persona_id, p_ventana, p_anio, round(p_monto, 2), trim(p_motivo), fn_persona_actual_id())
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function fn_beneficio_decidir(uuid, text, int, numeric, text) from public, anon;
grant execute on function fn_beneficio_decidir(uuid, text, int, numeric, text) to authenticated;

comment on function fn_beneficio_decidir(uuid, text, int, numeric, text) is
  'Registra cuánto reconoce la empresa que correspondía en una ventana de beneficio ya '
  'vencida (0618). Solo admin. Exige motivo. No edita: cada llamada agrega una fila y vale '
  'la más nueva.';

-- ── La lectura: la decisión que vale hoy, por persona y ventana ──────────────
create or replace function fn_beneficio_decision_vigente(p_anio int)
returns table (
  persona_id       uuid,
  ventana          text,
  anio             int,
  monto_reconocido numeric,
  motivo           text,
  decidido_por     uuid,
  created_at       timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (d.persona_id, d.ventana)
         d.persona_id, d.ventana, d.anio, d.monto_reconocido, d.motivo, d.decidido_por, d.created_at
    from beneficios_decisiones d
   where d.anio = p_anio
     and fn_es_admin_o_lider() is true
   order by d.persona_id, d.ventana, d.secuencia desc;
$$;

revoke all on function fn_beneficio_decision_vigente(int) from public, anon;
grant execute on function fn_beneficio_decision_vigente(int) to authenticated;

comment on function fn_beneficio_decision_vigente(int) is
  'La decisión vigente de cada persona + ventana en un año (0618): la de mayor secuencia. '
  'Devuelve vacío a quien no es admin o líder.';

insert into migraciones_aplicadas (numero, nombre) values (618, 'lo_que_quedo_de_un_beneficio_se_decide_y_queda_escrito')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
