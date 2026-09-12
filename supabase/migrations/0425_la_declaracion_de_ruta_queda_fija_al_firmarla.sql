-- ============================================================================
-- 0425 — La declaración de ruta queda fija al firmarla
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Tres cosas, decididas por Felipe el 2026-09-12, después de ver el
--   formulario funcionando en producción:
--
--   1. El formulario deja de pedir "costo de cada pasaje" y de calcular un
--      "gasto diario" propio. La declaración sigue contando CÓMO se traslada
--      (distrito, medios de transporte), pero el monto que aparece y que se
--      paga es SIEMPRE la tarifa oficial de la sede — nunca una cuenta que
--      la persona arme sola y que podría no coincidir.
--   2. Una vez firmada y vigente, la declaración queda fija: la persona ya
--      no puede volver a firmar sola cuando quiere ("Declarar de nuevo"
--      desaparece). Si algo cambió de verdad (se mudó, cambió de ruta), pide
--      una revisión con un motivo en vez de reemplazar su propia declaración.
--   3. Esa revisión le llega a quien puede operar como admin/líder — hoy,
--      en la práctica, a Felipe — con el mismo mecanismo que ya usa este
--      repositorio para "pedir que se revise un día" (0257): una tabla, tres
--      RPC, una fila en la Bandeja de admin.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   Sigue sin cambiar la tarifa fija por sede (S/10 Trujillo/Arequipa, S/12
--   Lima) ni cómo se calcula — eso no se toca, ver 0142/0166.
--
--   No bloquea la firma cuando la declaración está `sin_ruta`, `se_nego`, o
--   `ok` pero DESFASADA (la tarifa vigente cambió desde que firmó). En esos
--   tres casos SÍ puede seguir firmando sola: no hay ningún hecho suyo que
--   corregir, solo un papel que falta o una tarifa que se actualizó. El
--   bloqueo es únicamente para «ya tiene una declaración vigente y al día» —
--   ahí sí hace falta que alguien decida si lo que cambió amerita una
--   declaración nueva, y esa decisión pasa a ser de admin/líder.
--
--   No inventa una forma de dirigir el aviso a UNA persona en particular
--   (por ejemplo, solo a Felipe y a nadie más). Medido contra el patrón que
--   ya existe (`revisiones_pedidas`, 0257): ninguna función de este
--   repositorio dirige un aviso a un individuo — todas usan
--   `fn_es_admin_o_lider()`, visible a cualquier admin/líder, sin excepción.
--   Inventar un mecanismo nuevo solo para movilidad sería una segunda forma
--   de resolver la misma pregunta que esta migración ya tiene resuelta:
--   Felipe es admin, así que ya la va a ver.
--
-- QUÉ ASUME
--
--   `fn_confirmar_mi_declaracion_ruta` vigente es la 0424 — confirmado el
--   2026-09-12 con `./scripts/donde-vive.sh`. `revisiones_pedidas` (0257) como
--   el patrón a copiar: misma forma de tabla, mismos tres verbos (pedir,
--   listar, atender), mismo criterio de visibilidad.
--
-- CÓMO SE REVIERTE
--
--   drop table if exists movilidad_revisiones_pedidas;
--   drop function if exists fn_pedir_revision_movilidad(text);
--   drop function if exists fn_movilidad_revisiones_pedidas(boolean);
--   drop function if exists fn_atender_revision_movilidad(uuid, text);
--   drop function if exists fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,boolean);
--   -- recrear fn_confirmar_mi_declaracion_ruta con el cuerpo de la 0424
--   -- (firma de 8 parámetros, con costo de pasaje y de taxi).
--   Las declaraciones ya firmadas quedan intactas: esta migración no borra ni
--   modifica ninguna fila de documentos_firmados.
-- ============================================================================


-- ── A · Pedir revisión de movilidad — mismo molde que revisiones_pedidas ───
create table if not exists movilidad_revisiones_pedidas (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id),
  -- Obligatorio y con un mínimo, misma razón que 0257: sin texto, quien lo
  -- atiende tiene que adivinar, y lo que va a hacer es cerrarlo sin más.
  motivo         text not null check (length(trim(motivo)) >= 5),
  pedida_at      timestamptz not null default now(),
  atendida_at    timestamptz,
  atendida_por   uuid references personas(id),
  respuesta      text,
  constraint chk_movilidad_revision_atendida_completa
    check (atendida_at is null or atendida_por is not null)
);

comment on table movilidad_revisiones_pedidas is
  'Pedidos de revisión de una declaración de ruta ya firmada y vigente —la '
  'única puerta que le queda a la persona una vez que fn_confirmar_mi_declaracion_ruta '
  'la bloquea (0425). Mismo molde que revisiones_pedidas (0257): sin policies '
  'de insert/update, toda escritura pasa por las funciones de abajo.';

create index if not exists idx_movilidad_revisiones_pendientes
  on movilidad_revisiones_pedidas (persona_id) where atendida_at is null;

alter table movilidad_revisiones_pedidas enable row level security;

drop policy if exists movilidad_revisiones_select_propia on movilidad_revisiones_pedidas;
create policy movilidad_revisiones_select_propia on movilidad_revisiones_pedidas
  for select to authenticated using (persona_id = fn_persona_actual_id());

drop policy if exists movilidad_revisiones_select_admin_lider on movilidad_revisiones_pedidas;
create policy movilidad_revisiones_select_admin_lider on movilidad_revisiones_pedidas
  for select to authenticated using (fn_es_admin_o_lider() is true);

grant select on movilidad_revisiones_pedidas to authenticated;
revoke all on movilidad_revisiones_pedidas from anon, public;


-- Pedir (o reabrir la que ya tenía sin responder — no crea una segunda fila
-- mientras la primera siga pendiente; si ya se la habían respondido, esta sí
-- es una fila nueva, y la vieja queda de historial).
create or replace function fn_pedir_revision_movilidad(p_motivo text)
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
    raise exception 'Cuéntanos qué cambió, aunque sea en una línea.';
  end if;

  select id into v_pendiente
    from movilidad_revisiones_pedidas
   where persona_id = v_persona and atendida_at is null
   limit 1;

  if v_pendiente is not null then
    update movilidad_revisiones_pedidas
       set motivo = trim(p_motivo), pedida_at = now()
     where id = v_pendiente;
  else
    insert into movilidad_revisiones_pedidas (persona_id, motivo)
    values (v_persona, trim(p_motivo));
  end if;
end;
$$;

-- Lo que la Bandeja de admin necesita leer, con el nombre y la sede ya
-- resueltos — mismo criterio que fn_revisiones_pedidas (0257): jsonb y no
-- `returns table`, para no tener que tocar tipos generados por un cambio de
-- columnas, y la visibilidad se repite acá porque `security definer` no
-- hereda las policies de la tabla.
create or replace function fn_movilidad_revisiones_pedidas(p_solo_pendientes boolean default true)
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
  from movilidad_revisiones_pedidas r
  join personas p on p.id = r.persona_id
  left join sedes s on s.id = p.sede_base_id
  where (p_solo_pendientes is not true or r.atendida_at is null)
    and (fn_es_admin_o_lider() is true or r.persona_id = fn_persona_actual_id());
$$;

create or replace function fn_atender_revision_movilidad(p_id uuid, p_respuesta text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede atender una revisión de movilidad.';
  end if;

  update movilidad_revisiones_pedidas
     set atendida_at  = now(),
         atendida_por = fn_persona_actual_id(),
         respuesta    = nullif(trim(coalesce(p_respuesta, '')), '')
   where id = p_id;
end;
$$;

grant execute on function fn_pedir_revision_movilidad(text)              to authenticated;
grant execute on function fn_movilidad_revisiones_pedidas(boolean)       to authenticated;
grant execute on function fn_atender_revision_movilidad(uuid, text)      to authenticated;
revoke execute on function fn_pedir_revision_movilidad(text)             from public, anon;
revoke execute on function fn_movilidad_revisiones_pedidas(boolean)      from public, anon;
revoke execute on function fn_atender_revision_movilidad(uuid, text)     from public, anon;


-- ── B · fn_confirmar_mi_declaracion_ruta: sin costo propio, y con candado ──
-- Firma NUEVA (antes 8 parámetros, con costo de pasaje y de taxi; ahora 5).
-- Postgres no deja quitar parámetros con `create or replace` —hay que borrar
-- la función vieja primero—, mismo motivo por el que otras migraciones de
-- esta familia usan `drop function` cuando cambian la forma de una función.
drop function if exists fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,numeric,boolean,numeric,integer);

create function fn_confirmar_mi_declaracion_ruta(
  p_distrito         text,
  p_provincia        text,
  p_medios_ida       integer,
  p_medios_vuelta    integer,
  p_usa_taxi         boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo            uuid := fn_persona_actual_id();
  v_imagen        text;
  v_sede_codigo   text;
  v_tarifa        numeric;
  v_declarada     text;
  v_id            uuid;
  v_ip            text;
  v_ua            text;
  v_es_negativa   boolean;
  v_monto_anterior numeric;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  if not exists (select 1 from personas where id = v_yo and estado = 'activo')
     or not fn_persona_le_corresponde_movilidad(v_yo) then
    raise exception 'No estás en planilla ni eres practicante: no te corresponde declarar tu ruta.';
  end if;

  if p_distrito is null or length(trim(p_distrito)) = 0 then
    raise exception 'Falta el distrito donde resides.';
  end if;
  if p_provincia is null or length(trim(p_provincia)) = 0 then
    raise exception 'Falta la provincia donde resides.';
  end if;
  if p_medios_ida is null or p_medios_ida < 0 or p_medios_ida > 10 then
    raise exception 'Indica cuántos medios de transporte usas de ida (entre 0 y 10).';
  end if;
  if p_medios_vuelta is null or p_medios_vuelta < 0 or p_medios_vuelta > 10 then
    raise exception 'Indica cuántos medios de transporte usas de vuelta (entre 0 y 10).';
  end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  select s.codigo into v_sede_codigo
    from personas p join sedes s on s.id = p.sede_base_id
   where p.id = v_yo;

  select pl.valor into v_tarifa
    from parametros_laborales pl
   where pl.clave = 'movilidad_diaria'
     and pl.vigente_desde <= fn_hoy_lima()
     and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima())
     and (pl.sede_codigo = v_sede_codigo or pl.sede_codigo is null)
   order by (pl.sede_codigo is null), pl.vigente_desde desc
   limit 1;

  if v_tarifa is null then
    raise exception 'Tu sede todavía no tiene una tarifa de movilidad vigente. Avisa a Desarrollo Organizacional antes de firmar.';
  end if;

  -- ⇩⇩⇩ CANDADO (0425) ⇩⇩⇩ Mismo criterio de "vigente y al día" que usa
  -- fn_documentos_tablero para decidir `estado='ok'` y `ruta_desfasada=false`:
  -- existe una fila no anulada, no es una negativa, y su monto coincide con
  -- la tarifa de HOY. Si las tres se cumplen, ya está firmada y no hay nada
  -- que corregir sola — solo pedir revisión. `sin_ruta`, `se_nego` y
  -- `desfasada` (monto viejo, tarifa nueva) siguen firmando derecho.
  select d.es_negativa, d.monto_declarado into v_es_negativa, v_monto_anterior
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'ruta' and d.anulado_at is null
   order by d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;

  if v_es_negativa is not true and v_monto_anterior is not null and v_monto_anterior = v_tarifa then
    raise exception 'Ya tienes una declaración de ruta firmada y vigente. Si algo cambió, pide una revisión en vez de volver a firmar.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0425 ⇩⇩⇩ Sin costo de pasaje ni de taxi: el monto lo dice la
  -- tarifa oficial, nunca una cuenta propia. Ver el encabezado de esta
  -- migración.
  v_declarada :=
    'Reside en el distrito de ' || trim(p_distrito) || ', provincia de ' || trim(p_provincia) || '. '
    || 'Para llegar a su centro de labores utiliza ' || p_medios_ida || ' medio(s) de transporte por tramo, '
    || 'y de regreso ' || p_medios_vuelta || '. '
    || case when p_usa_taxi
         then 'En ocasiones utiliza taxi u otro medio particular. '
         else 'No reporta uso ocasional de taxi u otro medio particular. '
       end
    || 'CAYLA le otorga una asignación de movilidad de S/ ' || to_char(v_tarifa, 'FM999999990.00')
    || ' por día efectivamente asistido, conforme a la tarifa vigente para su sede.';

  begin
    v_ip := nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent
  ) values (
    'individual', v_yo, 'ruta', fn_hoy_lima(), v_declarada, v_tarifa,
    v_yo, v_imagen, now(), v_ip, v_ua
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'ruta · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la declaración de ruta (0423), reemplaza el escaneo físico.');

  return v_id;
end;
$$;

grant execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,boolean)
  to authenticated;
revoke execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,boolean)
  from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (425, 'la_declaracion_de_ruta_queda_fija_al_firmarla')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from information_schema.tables
     where table_name = 'movilidad_revisiones_pedidas') = 1
    as tabla_puesta,
  (select count(*) from pg_proc where proname = 'fn_pedir_revision_movilidad') = 1
    as pedir_puesta,
  (select count(*) from pg_proc where proname = 'fn_movilidad_revisiones_pedidas') = 1
    as listar_puesta,
  (select count(*) from pg_proc where proname = 'fn_atender_revision_movilidad') = 1
    as atender_puesta,
  (select prosrc like '%CANDADO (0425)%' from pg_proc
    where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 5)
    as firma_con_candado;
