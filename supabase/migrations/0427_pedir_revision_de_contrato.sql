-- ============================================================================
-- 0427 — Pedir revisión de contrato
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que quien firma su contrato desde /mio/contrato pueda avisar «algo de mi
--   contrato está mal» (una fecha, un sueldo, un cargo) y que ese aviso le
--   llegue a Desarrollo Organizacional — mismo mecanismo que ya usa este
--   repositorio dos veces para la misma idea: `revisiones_pedidas` (0257,
--   para un día de marcaje) y `movilidad_revisiones_pedidas` (0425, para la
--   declaración de ruta). Se copia el molde de la segunda, literal: misma
--   tabla, mismos tres verbos (pedir, listar, atender), mismo criterio de
--   visibilidad.
--
-- EL DEFECTO QUE ESTO NO ARREGLA, PORQUE NO ES UN DEFECTO
--
--   Por separado de esta migración: hoy /mio (pestaña «Contrato») dice
--   «Pendiente de firma» aunque la persona ya haya confirmado su firma
--   digital, porque ese texto solo mira `contratos_generados.fecha_firma` —
--   el escaneado FÍSICO— y nunca `firma_persona_confirmada_at` — la
--   confirmación digital (0402/0406). Eso es un cambio de PANTALLA, sin
--   ninguna fila nueva que escribir, y se corrige aparte, en
--   apps/web/app/(mio)/mio/page.tsx y apps/web/app/(mio)/mio/contrato/page.tsx.
--
--   Se anota acá para que quede claro que esta migración NO iguala la firma
--   digital del contrato con la del escaneo físico: decisión de Felipe,
--   2026-09-12 (ver el comentario de cabecera de /mio/movilidad/page.tsx) —
--   la firma digital de movilidad SÍ reemplaza el escaneo, la del contrato NO,
--   el trámite legal del contrato sigue dependiendo del papel. Pedir una
--   revisión es exactamente la puerta que le queda a la persona para avisar
--   de un error mientras ese papel no llega — no una forma de saltárselo.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No dirige el aviso a una persona en particular: usa `fn_es_admin_o_lider()`
--   sin excepción, mismo criterio que 0257 y 0425 — ver el razonamiento en el
--   encabezado de la 0425, que no se repite acá.
--
--   No exige que el motivo distinga «error en el contrato» de «cambié de
--   opinión sobre mi firma»: es un solo campo de texto libre, igual que en
--   0257 y 0425. Es Desarrollo Organizacional quien decide qué hacer al leerlo
--   — la migración solo abre el canal.
--
-- QUÉ ASUME
--
--   `contratos_generados` (0272), `fn_persona_actual_id`, `fn_es_admin_o_lider`
--   sin cambios. A diferencia de `fn_pedir_revision_movilidad` (que no exige
--   una declaración previa), esta función SÍ exige que la persona tenga hoy un
--   contrato no anulado: pedir revisar «mi contrato» sin ningún contrato
--   registrado no significa nada, y el error dice exactamente eso en vez de
--   dejar una fila huérfana.
--
-- CÓMO SE REVIERTE
--
--   drop table if exists contrato_revisiones_pedidas;
--   drop function if exists fn_pedir_revision_contrato(text);
--   drop function if exists fn_contrato_revisiones_pedidas(boolean);
--   drop function if exists fn_atender_revision_contrato(uuid, text);
--   No hay datos que deshacer: ningún contrato ni firma cambia al pegar esto.
-- ============================================================================


-- ── A · Pedir revisión de contrato — mismo molde que movilidad_revisiones_pedidas ──
create table if not exists contrato_revisiones_pedidas (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id),
  -- Obligatorio y con un mínimo, misma razón que 0257/0425: sin texto, quien
  -- lo atiende tiene que adivinar, y lo que va a hacer es cerrarlo sin más.
  motivo         text not null check (length(trim(motivo)) >= 5),
  pedida_at      timestamptz not null default now(),
  atendida_at    timestamptz,
  atendida_por   uuid references personas(id),
  respuesta      text,
  constraint chk_contrato_revision_atendida_completa
    check (atendida_at is null or atendida_por is not null)
);

comment on table contrato_revisiones_pedidas is
  'Pedidos de revisión de un contrato ya generado —"algo de mi contrato está '
  'mal", desde /mio/contrato. Mismo molde que movilidad_revisiones_pedidas '
  '(0425) y revisiones_pedidas (0257): sin policies de insert/update, toda '
  'escritura pasa por las funciones de abajo.';

create index if not exists idx_contrato_revisiones_pendientes
  on contrato_revisiones_pedidas (persona_id) where atendida_at is null;

alter table contrato_revisiones_pedidas enable row level security;

drop policy if exists contrato_revisiones_select_propia on contrato_revisiones_pedidas;
create policy contrato_revisiones_select_propia on contrato_revisiones_pedidas
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists contrato_revisiones_select_admin_lider on contrato_revisiones_pedidas;
create policy contrato_revisiones_select_admin_lider on contrato_revisiones_pedidas
  for select to authenticated using (fn_es_admin_o_lider() is true);

grant select on contrato_revisiones_pedidas to authenticated;
revoke all on contrato_revisiones_pedidas from anon, public;


-- Pedir (o reabrir la que ya tenía sin responder — no crea una segunda fila
-- mientras la primera siga pendiente; si ya se la habían respondido, esta sí
-- es una fila nueva, y la vieja queda de historial).
create or replace function fn_pedir_revision_contrato(p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_persona    uuid := fn_persona_actual_id();
  v_pendiente  uuid;
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.';
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Cuéntanos qué está mal, aunque sea en una línea.';
  end if;
  if not exists (
    select 1 from contratos_generados where persona_id = v_persona and anulado_at is null
  ) then
    raise exception 'Todavía no tienes un contrato registrado para pedir su revisión.';
  end if;

  select id into v_pendiente
    from contrato_revisiones_pedidas
   where persona_id = v_persona and atendida_at is null
   limit 1;

  if v_pendiente is not null then
    update contrato_revisiones_pedidas
       set motivo = trim(p_motivo), pedida_at = now()
     where id = v_pendiente;
  else
    insert into contrato_revisiones_pedidas (persona_id, motivo)
    values (v_persona, trim(p_motivo));
  end if;
end;
$$;

-- Lo que la Bandeja de admin necesita leer, con el nombre y la sede ya
-- resueltos — mismo criterio que fn_movilidad_revisiones_pedidas (0425): jsonb
-- y no `returns table`, y la visibilidad se repite acá porque `security
-- definer` no hereda las policies de la tabla.
create or replace function fn_contrato_revisiones_pedidas(p_solo_pendientes boolean default true)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'persona_id', r.persona_id,
           'nombre', p.nombres || ' ' || p.apellidos,
           'sede', s.codigo,
           'motivo', r.motivo,
           'pedida_at', r.pedida_at,
           'atendida_at', r.atendida_at,
           'respuesta', r.respuesta
         ) order by r.pedida_at desc), '[]'::jsonb)
  from contrato_revisiones_pedidas r
  join personas p on p.id = r.persona_id
  left join sedes s on s.id = p.sede_base_id
  where (p_solo_pendientes is not true or r.atendida_at is null)
    and (fn_es_admin_o_lider() is true or r.persona_id = fn_persona_actual_id());
$$;

create or replace function fn_atender_revision_contrato(p_id uuid, p_respuesta text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede atender una revisión de contrato.';
  end if;

  update contrato_revisiones_pedidas
     set atendida_at  = now(),
         atendida_por = fn_persona_actual_id(),
         respuesta    = nullif(trim(coalesce(p_respuesta, '')), '')
   where id = p_id;
end;
$$;

grant execute on function fn_pedir_revision_contrato(text)              to authenticated;
grant execute on function fn_contrato_revisiones_pedidas(boolean)       to authenticated;
grant execute on function fn_atender_revision_contrato(uuid, text)      to authenticated;
revoke execute on function fn_pedir_revision_contrato(text)             from public, anon;
revoke execute on function fn_contrato_revisiones_pedidas(boolean)      from public, anon;
revoke execute on function fn_atender_revision_contrato(uuid, text)     from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (427, 'pedir_revision_de_contrato')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from information_schema.tables
     where table_name = 'contrato_revisiones_pedidas') = 1
    as tabla_puesta,
  (select count(*) from pg_proc where proname = 'fn_pedir_revision_contrato') = 1
    as pedir_puesta,
  (select count(*) from pg_proc where proname = 'fn_contrato_revisiones_pedidas') = 1
    as listar_puesta,
  (select count(*) from pg_proc where proname = 'fn_atender_revision_contrato') = 1
    as atender_puesta;
