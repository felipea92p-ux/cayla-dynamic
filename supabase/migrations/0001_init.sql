-- CAYLA Dynamic — Sprint 0 schema
-- Zona horaria fija de todos los cálculos de negocio (tardanza, auto-cierre, "hoy"): America/Lima.
-- Ver docs/plan.md para el contexto completo.

create extension if not exists pgcrypto;

-- ============================================================================
-- Tipos
-- ============================================================================

create type rol_usuario as enum ('integrante', 'supervisor_sede', 'lider_do', 'admin');

create type tipo_marca as enum (
  'entrada',
  'salida_final',
  'salida_almuerzo', 'retorno_almuerzo',
  'salida_personal', 'retorno_personal',
  'salida_tramite', 'retorno_tramite',
  'salida_medico', 'retorno_medico',
  'salida_otro', 'retorno_otro'
);

create type origen_marca as enum ('terminal', 'admin_correccion', 'auto_cierre', 'import_historico');

create type estado_jornada as enum ('abierta', 'en_pausa', 'cerrada', 'auto_cerrada_pendiente', 'revisada');

create type estado_revision as enum ('normal', 'pendiente_revision', 'revisada');

-- ============================================================================
-- Función utilitaria: updated_at automático
-- ============================================================================

create or replace function fn_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ============================================================================
-- sedes
-- ============================================================================

create table sedes (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique check (codigo in ('TRU', 'LIM', 'AQP')),
  nombre text not null,
  activa boolean not null default true
);

insert into sedes (codigo, nombre) values
  ('TRU', 'Trujillo'),
  ('LIM', 'Lima'),
  ('AQP', 'Arequipa');

-- ============================================================================
-- personas
-- ============================================================================

create table personas (
  id uuid primary key default gen_random_uuid(),
  nombres text not null,
  apellidos text not null,
  documento text,
  sede_base_id uuid not null references sedes(id),
  rol rol_usuario not null default 'integrante',
  estado text not null default 'activo' check (estado in ('activo', 'inactivo')),
  pin_hash text not null,
  fecha_ingreso date not null default current_date,
  fecha_estado_cambio timestamptz,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_personas_sede_base on personas(sede_base_id);
create index idx_personas_estado on personas(estado);

create trigger trg_personas_updated_at
  before update on personas
  for each row execute function fn_set_updated_at();

-- ============================================================================
-- horarios_asignados — versionado, solo un horario "vigente" (vigente_hasta null) por persona
-- ============================================================================

create table horarios_asignados (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  vigente_desde date not null,
  vigente_hasta date,
  hora_entrada time not null,
  hora_salida time not null,
  almuerzo_min_minutos int not null default 45,
  almuerzo_max_minutos int not null default 75,
  dias_laborables int[] not null default '{1,2,3,4,5}', -- 0=domingo … 6=sábado
  horas_semana_objetivo numeric(5,2) not null default 45,
  created_at timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  check (almuerzo_min_minutos <= almuerzo_max_minutos)
);

create unique index idx_horario_vigente_unico on horarios_asignados(persona_id) where vigente_hasta is null;
create index idx_horarios_persona on horarios_asignados(persona_id, vigente_desde);

-- ============================================================================
-- tarifas_hora — versionado, solo una tarifa "vigente" por persona. Fase 1: solo dato, sin cálculo de pago.
-- ============================================================================

create table tarifas_hora (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  vigente_desde date not null,
  vigente_hasta date,
  tarifa_hora_soles numeric(10,2) not null check (tarifa_hora_soles > 0),
  creado_por uuid references personas(id),
  nota text,
  created_at timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde)
);

create unique index idx_tarifa_vigente_unica on tarifas_hora(persona_id) where vigente_hasta is null;
create index idx_tarifas_persona on tarifas_hora(persona_id, vigente_desde);

-- ============================================================================
-- terminales — un dispositivo fijo por sede, con su propia identidad de Supabase Auth
-- ============================================================================

create table terminales (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references sedes(id),
  nombre_dispositivo text not null,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  activo boolean not null default true,
  ultimo_visto_at timestamptz
);

create index idx_terminales_sede on terminales(sede_id);

-- ============================================================================
-- marcajes — log crudo append-only, fuente de verdad real
-- ============================================================================

create table marcajes (
  id uuid primary key default gen_random_uuid(),
  client_uuid uuid not null unique,
  persona_id uuid not null references personas(id),
  sede_id uuid not null references sedes(id),
  terminal_id uuid references terminales(id),
  tipo tipo_marca not null,
  motivo_otro text,
  timestamp_marca timestamptz not null,
  server_received_at timestamptz not null default now(),
  origen origen_marca not null default 'terminal',
  estado_revision estado_revision not null default 'normal',
  check (tipo <> 'salida_otro' or (motivo_otro is not null and length(trim(motivo_otro)) >= 3))
);

create index idx_marcajes_persona_dia on marcajes(persona_id, timestamp_marca);
create index idx_marcajes_sede on marcajes(sede_id, timestamp_marca);
create index idx_marcajes_estado_revision on marcajes(estado_revision) where estado_revision <> 'normal';

-- ============================================================================
-- jornadas — resumen derivado por persona/día, mantenido por trigger sobre marcajes
-- ============================================================================

create table jornadas (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  fecha date not null,
  sede_id uuid references sedes(id),
  entrada_ts timestamptz,
  salida_final_ts timestamptz,
  minutos_tarde int,
  horas_trabajadas numeric(6,2),
  horas_extra_detectadas numeric(6,2) not null default 0,
  estado estado_jornada not null default 'abierta',
  tiene_salida_no_retornada boolean not null default false,
  updated_at timestamptz not null default now(),
  unique(persona_id, fecha)
);

create index idx_jornadas_fecha on jornadas(fecha);
create index idx_jornadas_sede on jornadas(sede_id, fecha);
create index idx_jornadas_pendientes on jornadas(estado) where estado in ('auto_cerrada_pendiente');

-- ============================================================================
-- correcciones_auditoria
-- ============================================================================

create table correcciones_auditoria (
  id uuid primary key default gen_random_uuid(),
  marcaje_id uuid references marcajes(id),
  persona_id uuid not null references personas(id),
  campo_modificado text not null,
  valor_anterior text,
  valor_nuevo text,
  corregido_por uuid not null references personas(id),
  corregido_at timestamptz not null default now(),
  motivo text not null check (length(trim(motivo)) >= 3)
);

create index idx_auditoria_persona on correcciones_auditoria(persona_id, corregido_at);

-- ============================================================================
-- push_tokens / alertas
-- ============================================================================

create table push_tokens (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  expo_push_token text not null,
  plataforma text not null check (plataforma in ('ios', 'android')),
  activo boolean not null default true,
  last_seen_at timestamptz not null default now(),
  unique(persona_id, expo_push_token)
);

create table alertas (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid references personas(id),
  tipo text not null check (tipo in ('olvido_salida', 'tardanza', 'salida_no_retornada', 'auto_cierre', 'digest_diario')),
  canal text not null check (canal in ('push', 'email')),
  payload jsonb not null default '{}'::jsonb,
  enviado_at timestamptz,
  leido_at timestamptz,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'enviado', 'fallido')),
  created_at timestamptz not null default now()
);

create index idx_alertas_pendientes on alertas(estado) where estado = 'pendiente';

-- ============================================================================
-- google_sheets_sync_queue
-- ============================================================================

create table google_sheets_sync_queue (
  id uuid primary key default gen_random_uuid(),
  marcaje_id uuid references marcajes(id),
  jornada_id uuid references jornadas(id),
  payload jsonb not null,
  intentos int not null default 0,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'sincronizado', 'fallido')),
  last_error text,
  created_at timestamptz not null default now()
);

create index idx_sheets_queue_pendiente on google_sheets_sync_queue(estado) where estado = 'pendiente';
