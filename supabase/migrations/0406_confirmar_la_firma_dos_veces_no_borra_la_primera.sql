-- ============================================================================
-- 0406 — Confirmar la firma dos veces ya no borra la primera
-- ============================================================================
--
-- QUÉ PROMETE
--   Cada vez que alguien confirma su firma en su contrato queda una fila
--   propia, con la imagen que confirmó y el instante en que lo hizo.
--   `contratos_generados.firma_persona` / `firma_persona_confirmada_at` siguen
--   siendo LA VIGENTE —nadie tiene que cambiar cómo se lee el contrato— pero
--   dejan de ser lo único que existe.
--
-- EL DEFECTO QUE CIERRA
--   La 0402 confirma con un `update` a secas: no mira si ya había una
--   confirmación y no guarda la anterior en ningún lado. Como la imagen sale de
--   `firmas_escaneadas` —que cualquiera puede cambiar desde Mi perfil → Firma
--   (0398)— basta con cambiar la firma y volver a confirmar para que la
--   confirmación anterior desaparezca sin dejar rastro: ni qué imagen era ni de
--   qué día. Para un campo cuyo único propósito es servir de prueba de
--   aceptación, eso es estado y no constancia.
--
--   Es el mismo criterio que la 0404 aplicó al consentimiento de datos, y el
--   que este repositorio usa con los marcajes: lo que sirve de prueba se
--   agrega, no se pisa.
--
-- POR QUÉ SE SIGUE PERMITIENDO RECONFIRMAR
--   La otra salida era negar la segunda confirmación. Se descartó: quien
--   confirmó con una firma mal escaneada quedaría atrapado para siempre, sin
--   forma de corregirlo salvo pidiendo un contrato nuevo. Permitirlo y
--   guardarlo entero da las dos cosas — se puede corregir, y se sabe qué hubo
--   antes.
--
-- QUÉ NO HACE
--   No impide confirmar un contrato que ya tiene `fecha_firma` (el escaneado
--   físico ya registrado) ni uno que dejó de ser el vigente. Las dos cosas se
--   evaluaron y se dejan fuera a propósito: son decisiones sobre el trámite —
--   en qué orden ocurren la confirmación en pantalla y la firma en papel— y
--   esa política la define Desarrollo Organizacional, no una migración. Si se
--   decide, son dos `if` sobre esta misma función.
--
--   Tampoco rellena el historial de las confirmaciones que ya existan cuando
--   se pegue esto: de esas solo se sabe la última, que es exactamente el dato
--   que se estaba perdiendo. Las nuevas quedan completas desde el primer día.
--
-- QUÉ ASUME
--   0402 aplicada (`firma_persona`, `firma_persona_confirmada_at` y su
--   constraint). `firmas_escaneadas` (0076/0395), `fn_persona_actual_id`,
--   `fn_es_admin_o_lider`.
--
-- CÓMO SE REVIERTE
--   -- recrear fn_confirmar_mi_firma_contrato con el cuerpo de la 0402, y:
--   drop table if exists confirmaciones_firma_contrato;
--
-- md5 de partida de fn_confirmar_mi_firma_contrato: NO MEDIDO, y se dice en vez
-- de inventarlo. La 0402 no está pegada en producción ni aplicada en el
-- Postgres local de esta máquina (`donde-vive.sh` lo confirma: «La función no
-- existe en el Postgres local»), así que no hay de dónde sacar un md5 real. El
-- cuerpo del que parte esta migración es el de
-- supabase/migrations/0402_el_colaborador_confirma_su_firma_en_el_contrato.sql.
-- Si para cuando se pegue esto la 0402 ya está en producción, correr
-- donde-vive.sh y confirmar antes.
-- ============================================================================


-- ── A · El historial: una fila por confirmación ─────────────────────────────
create table if not exists confirmaciones_firma_contrato (
  id            uuid primary key default gen_random_uuid(),
  contrato_id   uuid not null references contratos_generados(id),
  persona_id    uuid not null references personas(id),
  imagen        text not null,
  confirmada_at timestamptz not null default now()
);

comment on table confirmaciones_firma_contrato is
  'Cada vez que alguien confirmó su firma en un contrato, con la imagen que '
  'confirmó ese día. Append-only: nunca se actualiza ni se borra. La vigente '
  'se sigue leyendo de contratos_generados.firma_persona; esta tabla es la que '
  'permite responder «¿con qué firma lo confirmó, y cuándo?» más de una vez.';

create index if not exists idx_confirmaciones_firma_contrato
  on confirmaciones_firma_contrato (contrato_id, confirmada_at desc);

alter table confirmaciones_firma_contrato enable row level security;

drop policy if exists confirmaciones_firma_select_propia on confirmaciones_firma_contrato;
create policy confirmaciones_firma_select_propia on confirmaciones_firma_contrato
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists confirmaciones_firma_select_admin on confirmaciones_firma_contrato;
create policy confirmaciones_firma_select_admin on confirmaciones_firma_contrato
  for select to authenticated using (fn_es_admin_o_lider() is true);

grant select on confirmaciones_firma_contrato to authenticated;
revoke all on confirmaciones_firma_contrato from anon, public;
-- Sin insert/update/delete: solo escribe la función de abajo.


-- ── B · Confirmar, dejando constancia de cada vez ───────────────────────────
-- Mismo cuerpo que la 0402 con el insert nuevo antes del update. El orden
-- importa poco —las dos escrituras van en la misma transacción, o entran las
-- dos o ninguna— pero se pone el historial primero para que se lea como lo que
-- es: lo que se guarda, y después el atajo para leerlo rápido.
create or replace function fn_confirmar_mi_firma_contrato(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo     uuid;
  v_imagen text;
  v_dueno  uuid;
  v_anulado timestamptz;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select persona_id, anulado_at into v_dueno, v_anulado
    from contratos_generados where id = p_contrato_id;
  if v_dueno is null then raise exception 'No se encontró ese contrato.'; end if;
  if v_dueno <> v_yo then raise exception 'Ese contrato no es tuyo.'; end if;
  if v_anulado is not null then raise exception 'Ese contrato está anulado.'; end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a Mi perfil → Firma antes de confirmar.';
  end if;

  -- CAMBIO 0406: la constancia primero. Sin esto, reconfirmar con otra firma
  -- borraba la anterior sin dejar rastro de qué imagen era ni de qué día.
  insert into confirmaciones_firma_contrato (contrato_id, persona_id, imagen)
  values (p_contrato_id, v_yo, v_imagen);

  update contratos_generados
     set firma_persona = v_imagen, firma_persona_confirmada_at = now()
   where id = p_contrato_id;
end;
$$;
grant execute on function fn_confirmar_mi_firma_contrato(uuid) to authenticated;
revoke execute on function fn_confirmar_mi_firma_contrato(uuid) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (406, 'confirmar_la_firma_dos_veces_no_borra_la_primera')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*)::int from information_schema.tables
     where table_name = 'confirmaciones_firma_contrato') = 1 as tabla_puesta,
  (select prosrc like '%CAMBIO 0406%' from pg_proc where proname = 'fn_confirmar_mi_firma_contrato')
    as funcion_al_dia,
  (select count(*)::int from pg_policies where tablename = 'confirmaciones_firma_contrato') = 2
    as las_dos_politicas;
