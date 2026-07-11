-- CAYLA Dynamic — Row Level Security
-- Identidades: cada `persona` con rol integrante/supervisor_sede/lider_do/admin tiene
-- un auth_user_id (login personal, para el panel admin o la app personal). Cada
-- `terminal` tiene su propio auth_user_id (una sesión persistente por dispositivo fijo
-- de sede, no ligada a ninguna persona en particular).

-- ============================================================================
-- Helpers
-- ============================================================================

create or replace function fn_rol_actual()
returns rol_usuario
language sql stable
as $$
  select rol from personas where auth_user_id = auth.uid();
$$;

create or replace function fn_persona_actual_id()
returns uuid
language sql stable
as $$
  select id from personas where auth_user_id = auth.uid();
$$;

create or replace function fn_sede_actual_persona()
returns uuid
language sql stable
as $$
  select sede_base_id from personas where auth_user_id = auth.uid();
$$;

create or replace function fn_sede_actual_terminal()
returns uuid
language sql stable
as $$
  select sede_id from terminales where auth_user_id = auth.uid() and activo;
$$;

create or replace function fn_es_admin_o_lider()
returns boolean
language sql stable
as $$
  select fn_rol_actual() in ('admin', 'lider_do');
$$;

-- ============================================================================
-- sedes — catálogo fijo, lectura para cualquier identidad autenticada (persona o terminal)
-- ============================================================================

alter table sedes enable row level security;

create policy sedes_select_autenticados on sedes
  for select to authenticated
  using (true);

-- ============================================================================
-- personas
-- ============================================================================

alter table personas enable row level security;

create policy personas_select_admin_lider on personas
  for select to authenticated
  using (fn_es_admin_o_lider());

create policy personas_select_supervisor on personas
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and sede_base_id = fn_sede_actual_persona());

create policy personas_select_propia on personas
  for select to authenticated
  using (auth_user_id = auth.uid());

create policy personas_select_terminal_roster on personas
  for select to authenticated
  using (estado = 'activo' and sede_base_id = fn_sede_actual_terminal());

create policy personas_insert_admin_lider on personas
  for insert to authenticated
  with check (fn_es_admin_o_lider());

create policy personas_update_admin_lider on personas
  for update to authenticated
  using (fn_es_admin_o_lider())
  with check (fn_es_admin_o_lider());

-- ============================================================================
-- horarios_asignados
-- ============================================================================

alter table horarios_asignados enable row level security;

create policy horarios_select_admin_lider on horarios_asignados
  for select to authenticated
  using (fn_es_admin_o_lider());

create policy horarios_select_supervisor on horarios_asignados
  for select to authenticated
  using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona())
  );

create policy horarios_select_propia on horarios_asignados
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

create policy horarios_select_terminal on horarios_asignados
  for select to authenticated
  using (persona_id in (select id from personas where sede_base_id = fn_sede_actual_terminal()));

create policy horarios_write_admin_lider on horarios_asignados
  for all to authenticated
  using (fn_es_admin_o_lider())
  with check (fn_es_admin_o_lider());

-- ============================================================================
-- tarifas_hora — solo admin/lider_do (dato sensible de remuneración)
-- ============================================================================

alter table tarifas_hora enable row level security;

create policy tarifas_admin_lider on tarifas_hora
  for all to authenticated
  using (fn_es_admin_o_lider())
  with check (fn_es_admin_o_lider());

-- ============================================================================
-- terminales
-- ============================================================================

alter table terminales enable row level security;

create policy terminales_select_admin_lider on terminales
  for select to authenticated
  using (fn_es_admin_o_lider());

create policy terminales_select_propio on terminales
  for select to authenticated
  using (auth_user_id = auth.uid());

create policy terminales_write_admin_lider on terminales
  for all to authenticated
  using (fn_es_admin_o_lider())
  with check (fn_es_admin_o_lider());

-- ============================================================================
-- marcajes — la escritura real SIEMPRE pasa por fn_registrar_marcaje (security
-- definer); por eso no hay policy de insert para roles autenticados normales.
-- ============================================================================

alter table marcajes enable row level security;

create policy marcajes_select_admin_lider on marcajes
  for select to authenticated
  using (fn_es_admin_o_lider());

create policy marcajes_select_supervisor on marcajes
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona());

create policy marcajes_select_propia on marcajes
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

create policy marcajes_select_terminal on marcajes
  for select to authenticated
  using (sede_id = fn_sede_actual_terminal());

-- Corrección manual directa (Sprint de panel admin): el registro en
-- correcciones_auditoria debe insertarse en la misma operación desde la
-- aplicación — no se fuerza aún a nivel de base de datos en este Sprint 0.
create policy marcajes_update_admin_lider on marcajes
  for update to authenticated
  using (fn_es_admin_o_lider())
  with check (fn_es_admin_o_lider());

create policy marcajes_update_supervisor on marcajes
  for update to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona())
  with check (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona());

-- ============================================================================
-- jornadas — solo lectura vía RLS; el trigger que las mantiene corre como
-- dueño de la función (postgres), que tiene bypassrls, así que no necesita policy de escritura.
-- ============================================================================

alter table jornadas enable row level security;

create policy jornadas_select_admin_lider on jornadas
  for select to authenticated
  using (fn_es_admin_o_lider());

create policy jornadas_select_supervisor on jornadas
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona());

create policy jornadas_select_propia on jornadas
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

create policy jornadas_select_terminal on jornadas
  for select to authenticated
  using (sede_id = fn_sede_actual_terminal());

-- ============================================================================
-- correcciones_auditoria
-- ============================================================================

alter table correcciones_auditoria enable row level security;

create policy auditoria_select_admin_lider on correcciones_auditoria
  for select to authenticated
  using (fn_es_admin_o_lider());

create policy auditoria_select_supervisor on correcciones_auditoria
  for select to authenticated
  using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona())
  );

create policy auditoria_select_propia on correcciones_auditoria
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

create policy auditoria_insert_admin_lider on correcciones_auditoria
  for insert to authenticated
  with check (fn_es_admin_o_lider());

create policy auditoria_insert_supervisor on correcciones_auditoria
  for insert to authenticated
  with check (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona())
  );

-- ============================================================================
-- push_tokens
-- ============================================================================

alter table push_tokens enable row level security;

create policy push_tokens_propio on push_tokens
  for all to authenticated
  using (persona_id = fn_persona_actual_id())
  with check (persona_id = fn_persona_actual_id());

create policy push_tokens_admin_lider on push_tokens
  for select to authenticated
  using (fn_es_admin_o_lider());

-- ============================================================================
-- alertas
-- ============================================================================

alter table alertas enable row level security;

create policy alertas_select_admin_lider on alertas
  for select to authenticated
  using (fn_es_admin_o_lider());

create policy alertas_select_supervisor on alertas
  for select to authenticated
  using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona())
  );

create policy alertas_select_propia on alertas
  for select to authenticated
  using (persona_id = fn_persona_actual_id());

create policy alertas_marcar_leida_propia on alertas
  for update to authenticated
  using (persona_id = fn_persona_actual_id())
  with check (persona_id = fn_persona_actual_id());

-- google_sheets_sync_queue: sin policies para `authenticated` — solo accesible vía
-- service role desde las Edge Functions (auto-cierre-cron, sheets-sync).
alter table google_sheets_sync_queue enable row level security;
