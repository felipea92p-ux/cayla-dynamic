-- ============================================================================
-- 0056_expediente_disciplinario.sql — El LEGAJO disciplinario (Capa 1)
-- ============================================================================
-- PROMETE: un único lugar donde vive cada documento disciplinario emitido a una
--   persona (acta verbal, amonestación, suspensión, imputación, despido), con su
--   lugar en la cadena, sus hechos y su estado. Hace IMPOSIBLES los estados
--   inválidos vía constraints, no vía validaciones en el código.
-- ASUME: existen personas, sedes y los helpers RLS (fn_es_admin_o_lider,
--   fn_rol_actual, fn_sede_actual_persona, fn_persona_actual_id).
--
-- Por qué UN solo legajo (no uno por causal): el día de una medida grave, la ley
-- mira el historial COMPLETO de la persona (tardanzas + faltas + conducta juntas)
-- para probar reincidencia y proporcionalidad. Ver docs/disciplina-tardanzas-faltas/.
--
-- Esta migración crea SOLO la tabla + correlativo + RLS de lectura. La generación
-- de borradores y las funciones de firma/entrega van en la siguiente (0057), para
-- que este cimiento se revise aislado.

-- ── Correlativo formal por año y prefijo (T/F/R) ─────────────────────────────
-- Un contador atómico por (año, prefijo) evita el race de max()+1 si dos sedes
-- generan un documento en el mismo instante (concurrencia — Jim Gray).
create table if not exists expediente_correlativo_seq (
  anio     int  not null,
  prefijo  text not null,
  ultimo   int  not null default 0,
  primary key (anio, prefijo)
);
-- RLS sin políticas = acceso directo denegado. Es un contador interno: nadie debe
-- tocarlo por la API. Las funciones security definer lo actualizan igual (bypass).
alter table expediente_correlativo_seq enable row level security;

create or replace function fn_expediente_correlativo(p_prefijo text)
returns text
language plpgsql security definer set search_path = public
as $$
declare v_anio int := extract(year from current_date)::int; v_n int;
begin
  insert into expediente_correlativo_seq (anio, prefijo, ultimo)
  values (v_anio, p_prefijo, 1)
  on conflict (anio, prefijo) do update set ultimo = expediente_correlativo_seq.ultimo + 1
  returning ultimo into v_n;
  -- ej. 'T-02/0007-2026-CAYLA'
  return p_prefijo || '/' || lpad(v_n::text, 4, '0') || '-' || v_anio || '-CAYLA';
end;
$$;

-- ── La tabla del legajo ──────────────────────────────────────────────────────
create table if not exists expediente_disciplinario (
  id            uuid primary key default gen_random_uuid(),
  correlativo   text unique,                       -- se asigna al firmar (fn de 0057)
  persona_id    uuid not null references personas(id),
  tipo_causal   text not null check (tipo_causal in ('tardanza','falta','conducta')),
  nivel         text not null check (nivel in ('verbal','amonestacion','suspension','imputacion','despido')),
  estado        text not null default 'borrador'
                  check (estado in ('borrador','firmado','entregado','anulado')),
  -- rango de hechos que motiva el documento (para non bis in idem: la próxima
  -- sanción solo puede contar hechos POSTERIORES a periodo_hasta del último firmado)
  periodo_desde date,
  periodo_hasta date,
  hechos        jsonb not null default '[]'::jsonb, -- [{fecha, hora_prog, hora_marca, minutos} | {fecha, tipo}]
  -- solo nivel 'suspension'
  suspension_dias  int,
  suspension_desde date,
  suspension_hasta date,
  -- la cadena: amonestación → suspensión → imputación → despido
  doc_previo_id uuid references expediente_disciplinario(id),
  -- firma y entrega
  firmante_id   uuid references personas(id),
  firmado_at    timestamptz,
  medio_entrega text check (medio_entrega in ('fisico','correo','notarial')),
  entregado_at  timestamptz,
  observacion   text,
  creado_por    uuid not null references personas(id),
  creado_at     timestamptz not null default now(),

  -- ── ESTADOS IMPOSIBLES hechos imposibles (Lamport) ──
  -- una suspensión sin días/fechas no debe existir
  constraint chk_susp_completa check (
    nivel <> 'suspension'
    or (suspension_dias is not null and suspension_dias > 0
        and suspension_desde is not null and suspension_hasta is not null
        and suspension_hasta >= suspension_desde)),
  -- un documento firmado/entregado sin firmante+correlativo no debe existir
  constraint chk_firmado_completo check (
    estado = 'borrador' or estado = 'anulado'
    or (firmante_id is not null and firmado_at is not null and correlativo is not null)),
  -- un documento entregado sin medio+fecha de entrega no debe existir
  constraint chk_entregado_completo check (
    estado <> 'entregado' or (medio_entrega is not null and entregado_at is not null)),
  -- rango de hechos coherente
  constraint chk_periodo check (periodo_desde is null or periodo_hasta is null or periodo_hasta >= periodo_desde)
);

create index if not exists idx_expediente_persona on expediente_disciplinario (persona_id, creado_at desc);
create index if not exists idx_expediente_estado  on expediente_disciplinario (estado) where estado = 'borrador';

-- ── RLS: mismo criterio que justificaciones_asistencia (0051) ────────────────
alter table expediente_disciplinario enable row level security;

drop policy if exists exp_select_admin_lider on expediente_disciplinario;
create policy exp_select_admin_lider on expediente_disciplinario
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists exp_select_supervisor on expediente_disciplinario;
create policy exp_select_supervisor on expediente_disciplinario
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists exp_select_propia on expediente_disciplinario;
create policy exp_select_propia on expediente_disciplinario
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- Sin políticas de INSERT/UPDATE/DELETE: toda escritura pasa por las funciones
-- security definer de 0058 (generar borrador, firmar, entregar, anular), que
-- validan permiso y la cadena. Nada se escribe directo desde el cliente.

-- fn_expediente_correlativo NO se otorga a authenticated a propósito: solo la
-- deben llamar las funciones definer al firmar, para que nadie queme números de
-- correlativo desde el cliente. Corre igual dentro de esas funciones (definer).
