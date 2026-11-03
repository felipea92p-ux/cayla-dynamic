-- ============================================================================
-- 0589 — La líder de equipo registra la disponibilidad de su gente
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la líder de equipo pueda registrar la disponibilidad de una integrante
--   de SU sede —no solo DO y admin, como hasta la 0584—, y que todo registro
--   hecho por otra persona diga POR QUÉ se registró así: «Me lo dijo en
--   persona», «Está en preselección y todavía no tiene cuenta»…, o «Otro» con
--   el texto escrito. Lo registrado entra APROBADO, igual que cuando lo
--   registra DO.
--
-- DECIDIÓ FELIPE (2026-11-03)
--   1. La líder registra la de una integrante de su sede. Nunca la propia; la
--      de otra líder la registra DO.
--   2. Entra aprobada directamente.
--   3. Con un motivo del registro obligatorio, distinto del motivo de la
--      disponibilidad (estudios, hijos, salud…, que se queda). Lista de lo más
--      simple a lo más complejo, con «Otro» para escribir.
--   El riesgo de (2) —la líder registra y aprueba a la vez, sin otro par de
--   ojos— se discutió con Felipe: lo acotan el motivo obligatorio y que cada
--   registro queda en «Cambios de horario» con quién lo hizo y por qué.
--
-- QUÉ ASUME
--   · `fn_puede_resolver_disponibilidad` (0584) es la regla de «quién decide
--     sobre la disponibilidad de esta persona»: DO y admin sobre cualquiera, la
--     líder sobre las integrantes de su sede, nunca la propia. Registrar es la
--     misma pregunta, así que se usa la misma función. No se escribe otra.
--   · `fn_disponibilidad_guardar_interno` (0584) no cambia: se le pasan los
--     mismos datos y el motivo del registro se anota DESPUÉS sobre la fila que
--     devuelve, en la misma transacción.
--
-- LO QUE REESCRIBE
--   `fn_disponibilidad_registrar`, vigente en la 0584 (donde-vive.sh). Su
--   firma cambia —suma p_registro_motivo y p_registro_detalle—, así que se
--   borra la de 8 argumentos y se crea la de 10: dejar las dos sería una
--   sobrecarga, y con argumentos por defecto Postgres no sabría cuál llamar
--   («function is not unique», el accidente de la 0297/0299).
--   md5 de partida en PRODUCCIÓN, pedido antes de escribir (2026-11-03):
--   `6a553cab51679590a25291fae1510243`, 837 caracteres, sin `\r`, una sola
--   versión. Coincide con el Postgres local. Si al pegar producción devuelve
--   otro, PARAR.
--   `fn_puede_resolver_disponibilidad` NO se toca (md5 de producción
--   `76f2653c1a091036ad8a4eb3455fd030`, 686, igual al local).
--
-- ENTRE PEGAR Y FUSIONAR
--   La pantalla publicada todavía llama sin motivo del registro: la base lo
--   rechaza con «Elige por qué la registras» hasta que se fusione el PR. No
--   rompe nada: solo DO no puede registrar en esos minutos.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text);
--   Volver a pegar fn_disponibilidad_registrar de la 0584 (con su comment y grants).
--   alter table disponibilidades drop constraint if exists disponibilidad_registro_otro_con_texto;
--   alter table disponibilidades drop column if exists registro_detalle, drop column if exists registro_motivo;
--     (solo si no hay registros que conservar: es historia)
--   delete from migraciones_aplicadas where numero = 589;
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: todo en true, una sola versión de la función y
--   «589 · la_lider_registra_la_disponibilidad».
-- ============================================================================

-- ── 1 · El motivo del registro ───────────────────────────────────────────────

alter table disponibilidades add column if not exists registro_motivo text;
alter table disponibilidades add column if not exists registro_detalle text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'disponibilidad_registro_motivo_valido') then
    alter table disponibilidades add constraint disponibilidad_registro_motivo_valido check (
      registro_motivo is null or registro_motivo in (
        'en_persona', 'por_mensaje', 'preseleccion_sin_cuenta', 'sin_acceso',
        'conversacion_horario', 'documento', 'otro'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'disponibilidad_registro_otro_con_texto') then
    alter table disponibilidades add constraint disponibilidad_registro_otro_con_texto check (
      (registro_motivo is distinct from 'otro' or length(trim(coalesce(registro_detalle, ''))) >= 5)
      and (registro_detalle is null or length(registro_detalle) <= 300));
  end if;
end;
$$;

comment on column disponibilidades.registro_motivo is
  'Por qué la registró otra persona (líder o DO) y no ella misma. Null cuando la envió ella. 0589.';
comment on column disponibilidades.registro_detalle is
  'El texto de «Otro» (obligatorio en ese caso) o una aclaración del registro. 0589.';

-- ── 2 · La puerta ────────────────────────────────────────────────────────────

drop function if exists fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text);

create or replace function fn_disponibilidad_registrar(
  p_persona_id uuid, p_tipo text, p_motivo text, p_desde date, p_hasta date, p_bloques jsonb,
  p_horario_fijo boolean default false, p_nota text default null,
  p_registro_motivo text default null, p_registro_detalle text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  v_id uuid;
begin
  if v_yo is null or v_yo = p_persona_id then
    raise exception 'Tu propia disponibilidad la mandas desde «Lo mío», y la aprueba otra persona.';
  end if;
  -- ⇩ CAMBIO 0589 ⇩ antes: solo fn_es_admin_o_lider(). Ahora la misma regla que aprueba.
  if fn_puede_resolver_disponibilidad(p_persona_id) is not true then
    raise exception 'La registra su líder de equipo (si es de su sede) o Desarrollo Organizacional.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no está activa.';
  end if;
  -- ⇩ CAMBIO 0589 ⇩ el motivo del registro.
  if p_registro_motivo is null or p_registro_motivo not in (
       'en_persona', 'por_mensaje', 'preseleccion_sin_cuenta', 'sin_acceso',
       'conversacion_horario', 'documento', 'otro') then
    raise exception 'Elige por qué la registras tú y no ella.';
  end if;
  if p_registro_motivo = 'otro' and length(trim(coalesce(p_registro_detalle, ''))) < 5 then
    raise exception 'Escribe por qué la registras (al menos 5 caracteres).';
  end if;

  perform pg_advisory_xact_lock(hashtext('disponibilidad:' || p_persona_id::text));
  v_id := fn_disponibilidad_guardar_interno(p_persona_id, p_tipo, p_motivo, p_desde, p_hasta,
                                            coalesce(p_bloques, '[]'::jsonb), p_nota, 'aprobada', v_yo, p_horario_fijo);
  update disponibilidades
     set registro_motivo = p_registro_motivo, registro_detalle = nullif(trim(p_registro_detalle), '')
   where id = v_id;
  return v_id;
end;
$$;

comment on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text) is
  'Su líder de equipo (integrantes de su sede), DO o admin registra la disponibilidad de una persona por ella, '
  'con el motivo del registro; entra aprobada y reemplaza la que tenía pendiente. Nunca la propia. 0584, 0589.';

revoke all on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text) from public, anon;
grant execute on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text) to authenticated;

-- ── 3 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (589, 'la_lider_registra_la_disponibilidad')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  (select count(*) from pg_proc where proname = 'fn_disponibilidad_registrar') = 1              as una_sola_version,
  to_regprocedure('fn_disponibilidad_registrar(uuid,text,text,date,date,jsonb,boolean,text,text,text)') is not null as la_nueva_existe,
  exists (select 1 from information_schema.columns
           where table_name = 'disponibilidades' and column_name = 'registro_motivo')            as tiene_el_motivo,
  exists (select 1 from pg_constraint where conname = 'disponibilidad_registro_otro_con_texto') as otro_pide_texto,
  (select md5(prosrc) || ' · ' || length(prosrc) from pg_proc where proname = 'fn_disponibilidad_registrar') as md5_de_llegada,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 589)              as registro;
