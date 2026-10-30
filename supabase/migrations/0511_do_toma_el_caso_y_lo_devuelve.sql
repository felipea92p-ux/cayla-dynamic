-- ============================================================================
-- 0511 — DO toma el caso de una líder, y se lo puede devolver
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que Desarrollo Organizacional pueda TOMAR un caso disciplinario que inició
-- una líder de equipo —con un motivo escrito— y que, mientras lo tenga, la
-- líder lo siga viendo pero ya no pueda tocarlo. Y que DO se lo pueda
-- DEVOLVER, también con motivo. Cada traspaso queda en un historial que no se
-- edita.
--
-- ── DE QUIÉN ES LA DECISIÓN ─────────────────────────────────────────────────
--
-- De la usuaria, el 2026-10-06: DO recibe aviso de lo que registran las
-- líderes «pero solo visualiza; si es algo que no le parece a DO, ella toma el
-- rol de encargarse del asunto, pero también le puede regresar el liderazgo
-- del caso a la líder que hizo la amonestación». Y, con las opciones a la
-- vista:
--
--   · Toman el caso la líder DO y quienes tienen rol admin: la misma regla con
--     la que hoy se anula un documento (`puedeAnularDocumentoDisciplinario`).
--     Tomar es tramitar, no imponer: firmar sigue exigiendo contrato de
--     trabajo (0510), así que la practicante de DO puede tomar un caso pero
--     no firmarlo.
--   · Se puede tomar en cualquier estado salvo anulado. Si ya se entregó, lo
--     que DO puede hacer con él es anularlo (`fn_expediente_anular`, solo DO,
--     0058): un documento que la persona ya recibió no se edita, porque el
--     legajo diría algo distinto del papel que ella tiene en la mano.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- EL CANDADO ES UN TRIGGER, NO UNA LÍNEA EN CADA FUNCIÓN. Un caso se trabaja
-- por más de una docena de funciones —editar, comunicar cargos, valorar el
-- descargo, firmar, entregar, enviar a Info, reabrir— y todas escriben en
-- solo dos tablas: el documento (UPDATE) y sus adjuntos (INSERT). Medido el
-- 2026-10-06 sobre todas las migraciones: no hay una tercera. Un trigger en
-- cada una las cubre a todas sin reescribir ninguna; reescribirlas habría sido
-- pedir el md5 de cada una y arriesgar revertir en silencio el trabajo de
-- otra sesión, que es el accidente de la 0261.
--
-- LA PERSONA SANCIONADA NO QUEDA ATRAPADA. Tres funciones las ejecuta ella
-- sobre su propio documento: recibirlo por Info, firmarlo y negarse a firmar
-- (0408, 0486). Un candado que mirara solo el rol bloquearía a una líder que
-- recibe su propio memo. Por eso el candado alcanza a la líder que TRAMITA,
-- nunca a la persona del documento.
--
-- LA COLUMNA Y EL HISTORIAL DICEN LO MISMO, Y LOS ESCRIBE UNA SOLA FUNCIÓN.
-- `tomado_por` es la respuesta rápida que necesita el candado; los traspasos
-- son el porqué. Los dos se escriben en la misma transacción, con la fila del
-- documento bloqueada (FOR UPDATE): si dos personas de DO pulsan «Tomar» en el
-- mismo segundo, la segunda encuentra el caso ya tomado y recibe el nombre de
-- quien lo tomó.
--
-- DEVOLVER SOLO SI QUIEN LO INICIÓ PUEDE RECIBIRLO. Si la líder ya no está
-- activa, ya no tiene el rol o dejó de estar en planilla, devolverle el caso
-- lo dejaría en manos de nadie. Entonces se queda con DO, y la función lo dice.
--
-- ── QUÉ NO HACE ─────────────────────────────────────────────────────────────
--
--   · No cambia QUIÉN puede tramitar cuando el caso no está tomado: siguen
--     pudiendo las líderes de la sede (0510), no solo la que lo inició.
--     «Devolver» lo devuelve a la sede, con quien lo inició como referencia.
--   · No avisa a nadie: el aviso a la líder DO es pantalla (entrega 3).
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que la 0510 ya está pegada: el candado y estas funciones conviven con su
--     trigger de firma sin pisarse (los dos son BEFORE UPDATE e independientes).
--   · Que `fn_rol_actual()` devuelve el rol de quien tiene la sesión, y null
--     sin sesión: un proceso del sistema (pg_cron) no queda bloqueado.
--
-- No reescribe ninguna función existente: no hay md5 de partida que declarar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop trigger if exists trg_expediente_candado_caso_tomado on expediente_disciplinario;
--   drop trigger if exists trg_adjuntos_candado_caso_tomado on expediente_adjuntos;
--   drop function if exists fn_expediente_candado_caso_tomado();
--   drop function if exists fn_adjuntos_candado_caso_tomado();
--   drop function if exists fn_expediente_tomar_caso(uuid, text);
--   drop function if exists fn_expediente_devolver_caso(uuid, text);
-- Las columnas y `expediente_traspasos` se conservan: son historia de casos
-- reales. Sin el trigger, la columna deja de bloquear y no hace daño.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · Quién tiene el caso, y desde cuándo
-- ════════════════════════════════════════════════════════════════════════════
alter table expediente_disciplinario add column if not exists tomado_por uuid references personas(id);
alter table expediente_disciplinario add column if not exists tomado_at  timestamptz;

comment on column expediente_disciplinario.tomado_por is
  'Quién de DO tomó este caso, que inició una líder de equipo. Null = el caso está con la sede. Lo escriben solo fn_expediente_tomar_caso y fn_expediente_devolver_caso.';

do $mig$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_tomado_completo') then
    alter table expediente_disciplinario
      add constraint chk_tomado_completo check ((tomado_por is null) = (tomado_at is null));
  end if;
end;
$mig$;

-- El porqué de cada traspaso. Solo se agrega: nadie lo edita ni lo borra.
create table if not exists expediente_traspasos (
  id            uuid primary key default gen_random_uuid(),
  expediente_id uuid not null references expediente_disciplinario(id),
  accion        text not null check (accion in ('tomar', 'devolver')),
  por           uuid not null references personas(id),
  motivo        text not null check (length(btrim(motivo)) >= 10),
  hecho_at      timestamptz not null default now()
);

create index if not exists idx_expediente_traspasos_doc on expediente_traspasos (expediente_id, hecho_at desc);

alter table expediente_traspasos enable row level security;

-- Lo ve DO, y la líder que puede ver el documento: el motivo es justamente lo
-- que ella necesita leer cuando un caso suyo deja de ser suyo. NO lo ve la
-- persona sancionada: es una conversación interna sobre cómo tramitar, no
-- parte de su legajo.
drop policy if exists expediente_traspasos_select on expediente_traspasos;
create policy expediente_traspasos_select on expediente_traspasos
  for select to authenticated using (
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede'
        and exists (select 1 from expediente_disciplinario d
                     where d.id = expediente_traspasos.expediente_id
                       and d.persona_id <> fn_persona_actual_id())));
grant select on expediente_traspasos to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Tomar y devolver
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_expediente_tomar_caso(p_id uuid, p_motivo text)
returns void language plpgsql volatile security definer set search_path = public as $$
declare
  r         expediente_disciplinario%rowtype;
  v_creador personas%rowtype;
  v_quien   text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional o Gerencia toman un caso.';
  end if;

  select * into r from expediente_disciplinario where id = p_id for update;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado = 'anulado' then
    raise exception 'Este documento está anulado: no hay caso que tomar.';
  end if;
  if r.tomado_por is not null then
    select nombres || ' ' || apellidos into v_quien from personas where id = r.tomado_por;
    raise exception 'Este caso ya lo tomó %.', coalesce(v_quien, 'Desarrollo Organizacional');
  end if;

  select * into v_creador from personas where id = r.creado_por;
  if v_creador.rol is distinct from 'supervisor_sede' then
    raise exception 'Este caso no lo inició una líder de equipo: ya está con Desarrollo Organizacional.';
  end if;

  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Escribe por qué tomas el caso: es lo que va a leer la líder que lo inició.';
  end if;

  update expediente_disciplinario
     set tomado_por = fn_persona_actual_id(), tomado_at = now()
   where id = p_id;
  insert into expediente_traspasos (expediente_id, accion, por, motivo)
  values (p_id, 'tomar', fn_persona_actual_id(), btrim(p_motivo));
end;
$$;

grant execute on function fn_expediente_tomar_caso(uuid, text) to authenticated;
revoke execute on function fn_expediente_tomar_caso(uuid, text) from public, anon;

create or replace function fn_expediente_devolver_caso(p_id uuid, p_motivo text)
returns void language plpgsql volatile security definer set search_path = public as $$
declare
  r         expediente_disciplinario%rowtype;
  v_creador personas%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional o Gerencia devuelven un caso.';
  end if;

  select * into r from expediente_disciplinario where id = p_id for update;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.tomado_por is null then
    raise exception 'Este caso no lo tiene Desarrollo Organizacional: no hay nada que devolver.';
  end if;
  if r.estado = 'anulado' then
    raise exception 'Este documento está anulado: ya no hay caso que devolver.';
  end if;

  -- Devolverlo a quien ya no puede tramitarlo lo dejaría en manos de nadie.
  select * into v_creador from personas where id = r.creado_por;
  if v_creador.estado is distinct from 'activo'
     or v_creador.rol is distinct from 'supervisor_sede'
     or v_creador.en_planilla is not true then
    raise exception 'Quien inició este caso ya no puede tramitarlo (no está activa, no tiene el rol de líder o no está en planilla): el caso se queda con Desarrollo Organizacional.';
  end if;

  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Escribe por qué devuelves el caso: es lo que va a leer la líder.';
  end if;

  update expediente_disciplinario
     set tomado_por = null, tomado_at = null
   where id = p_id;
  insert into expediente_traspasos (expediente_id, accion, por, motivo)
  values (p_id, 'devolver', fn_persona_actual_id(), btrim(p_motivo));
end;
$$;

grant execute on function fn_expediente_devolver_caso(uuid, text) to authenticated;
revoke execute on function fn_expediente_devolver_caso(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · El candado
-- ════════════════════════════════════════════════════════════════════════════
-- Alcanza a quien TRAMITA con rol de líder, sobre un documento que no es suyo.
-- `fn_rol_actual() = 'supervisor_sede'` es null sin sesión, y un IF con null no
-- entra: un proceso del sistema no queda bloqueado.
create or replace function fn_expediente_candado_caso_tomado()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_quien text;
begin
  if old.tomado_por is not null
     and fn_rol_actual() = 'supervisor_sede'
     and old.persona_id is distinct from fn_persona_actual_id() then
    select nombres || ' ' || apellidos into v_quien from personas where id = old.tomado_por;
    raise exception 'Este caso lo tomó % (Desarrollo Organizacional): lo puedes ver, pero ya no modificar. Si crees que debe volver a ti, habla con DO.',
      coalesce(v_quien, 'DO');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_expediente_candado_caso_tomado on expediente_disciplinario;
create trigger trg_expediente_candado_caso_tomado
  before update on expediente_disciplinario
  for each row execute function fn_expediente_candado_caso_tomado();

create or replace function fn_adjuntos_candado_caso_tomado()
returns trigger language plpgsql security definer set search_path = public as $$
declare d expediente_disciplinario%rowtype;
begin
  select * into d from expediente_disciplinario where id = new.documento_id;
  if d.tomado_por is not null
     and fn_rol_actual() = 'supervisor_sede'
     and d.persona_id is distinct from fn_persona_actual_id() then
    raise exception 'Este caso lo tomó Desarrollo Organizacional: ya no le puedes agregar documentos.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_adjuntos_candado_caso_tomado on expediente_adjuntos;
create trigger trg_adjuntos_candado_caso_tomado
  before insert on expediente_adjuntos
  for each row execute function fn_adjuntos_candado_caso_tomado();


insert into migraciones_aplicadas (numero, nombre) values (511, 'do_toma_el_caso_y_lo_devuelve')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
