-- ============================================================================
-- 0488_los_reportes_se_escriben_y_sus_plazos_corren.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que un reporte se pueda crear, conversar, reclasificar, escalar, cerrar y
--   enlazar con disciplina, SOLO por funciones guardián, y que cada plazo del
--   Reglamento corra solo desde que el reporte entra. Es el paso 2 de la Fase 1
--   de `docs/plan-reportes.md` (secciones 8 y 10). Sobre las tablas y la regla
--   de la 0483, que se pega ANTES que esta.
--
-- QUÉ ASUME
--   · La regla de acceso de la 0483 (`fn_reporte_acceso`, `fn_reporte_motivo`)
--     es la única respuesta a «quién puede». Ninguna función de aquí la
--     reescribe: preguntan el MOTIVO y deciden con él qué puede hacer cada una.
--   · `fn_sumar_dias_habiles` (0212) cuenta los días hábiles: salta sábados,
--     domingos y `feriados`, y vence a las 23:59 de Lima. No se escribe otra.
--   · Plan, decisión 14: en convivencia (43-A) la líder actúa, pero DO es dueña
--     del plazo y solo DO cierra. Decisión 16: en el Título X la líder no ve el
--     caso; solo recibe la instrucción de una medida.
--
-- ── QUIÉN HACE QUÉ ───────────────────────────────────────────────────────────
--
--                      reclamo 43-B        convivencia 43-A     Título X
--   escribir al hilo   quien gestiona      quien gestiona       quien gestiona
--   registrar acción   quien gestiona      quien gestiona       ✗ (48.14: sin mediación)
--   reclasificar       quien gestiona      quien gestiona       solo DO / Gerencia
--   escalar            líder → DO → Gerencia, si del otro lado hay alguien
--   medida             ✗                   DO / Gerencia        DO / Gerencia
--   cerrar             quien gestiona      DO / Gerencia        DO / Gerencia, con el informe
--   derivar a disc.    DO / Gerencia       DO / Gerencia        DO / Gerencia
--   informe            —                   —                    solo quien investiga
--
--   «DO / Gerencia» es el motivo que devuelve la regla, no el rol: sobre la
--   Gerencia General actúa DO; sobre DO, la Gerencia.
--
-- ── LOS PLAZOS ───────────────────────────────────────────────────────────────
--
--   Una tabla, `reporte_plazos`, para las tres vías: el Título X tiene nueve y
--   se encadenan (el informe abre la decisión; la decisión abre el aviso al
--   MTPE), cosa que dos columnas en `reportes` no podían expresar. Qué dice
--   cada plazo —norma, días, tipo de día, dueña— vive en UN solo sitio,
--   `fn_reporte_plazo_abrir`. Todos cuentan desde la RECEPCIÓN (`creado_at`),
--   salvo los que el 49.4 cuenta desde el informe o desde la decisión.
--
--   Reclasificar no borra plazos: los pendientes se ANULAN (queda cuándo) y
--   se abren los de la vía nueva, contados desde la misma recepción. Si ya
--   vencieron, se ven vencidos: es lo que pasó.
--
--   En el Título X, registrar el informe en Dynamic ES entregarlo a DO: el
--   plazo f) se cumple en el mismo acto, y el g) (decisión, 10 días
--   calendario) corre desde ahí.
--
-- ── SIN NADIE QUE LO RECIBA, NO SE GUARDA ────────────────────────────────────
--
--   `fn_reporte_crear` rechaza un reporte que ninguna persona activa puede
--   gestionar (por ejemplo, uno sobre la Gerencia General si la única DO está
--   inactiva). Guardarlo igual daría la falsa tranquilidad de haberlo
--   presentado, con plazos corriendo para nadie. El mensaje manda al sobre
--   cerrado (48.7) y a los canales externos (48.9). La pantalla del paso 3 lo
--   avisa antes, con `fn_reporte_quien_lo_leera`.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   drop function if exists fn_reporte_crear(text, text, uuid, date, text, uuid[], uuid[], text, boolean, boolean, text, text),
--     fn_reporte_mensaje(uuid, text, boolean, date), fn_reporte_en_revision(uuid),
--     fn_reporte_anotar_accion(uuid, text, text), fn_reporte_reclasificar(uuid, text, text),
--     fn_reporte_escalar(uuid, text), fn_reporte_cerrar(uuid, text, text),
--     fn_reporte_derivar(uuid, uuid), fn_reporte_medida(uuid, uuid, text, date),
--     fn_reporte_medida_cumplida(uuid), fn_reporte_adjuntar(uuid, text, boolean),
--     fn_reporte_abrir(uuid), fn_reporte_plazo_cumplir(uuid, text, text),
--     fn_reporte_indicios_delito(uuid, text), fn_reportes_bandeja(), fn_reportes_mios(),
--     fn_reporte_padron(), fn_reporte_detalle(uuid), fn_reporte_hilo(uuid), fn_reporte_adjuntos(uuid),
--     fn_ve_casos(), fn_reporte_plazos(uuid), fn_reporte_personas(uuid), fn_reporte_eventos(uuid),
--     fn_reporte_medidas(uuid), fn_mis_medidas(), fn_reporte_lideres(uuid), fn_reporte_expedientes(uuid),
--     fn_organos_titulo_x(),
--     fn_organo_titulo_x_guardar(uuid, uuid, text, date, text), fn_organo_titulo_x_cerrar(uuid, date, text),
--     fn_reporte_plazo_abrir(uuid, text, timestamptz, timestamptz), fn_reporte_plazos_de_via(uuid),
--     fn_reporte_gestora_inicial(uuid), fn_reporte_hay_quien(uuid, text),
--     fn_reporte_evento(uuid, text, jsonb) cascade;
--   drop table reporte_plazos;
--   drop trigger trg_reporte_medidas_guardian on reporte_medidas;
--   drop trigger trg_organos_titulo_x_guardian on organos_titulo_x;
--   drop function fn_reporte_medidas_guardian(), fn_organos_titulo_x_guardian(), fn_reporte_plazos_guardian();
--   Las tablas de la 0483 quedan; sin estas funciones nadie puede escribir en
--   ellas. Ojo: si ya hubo reportes, borrar `reporte_plazos` destruye la prueba
--   de que se cumplieron los plazos del Reglamento.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final.
-- ============================================================================


-- ── 1 · Los plazos ──────────────────────────────────────────────────────────
create table if not exists reporte_plazos (
  id            uuid primary key default gen_random_uuid(),
  reporte_id    uuid not null references reportes(id),
  clave         text not null check (clave in (
                  'respuesta', 'respuesta_prometida',              -- 43-B.2
                  'acuse', 'resolucion',                           -- 43-A.6
                  'salud', 'traslado', 'medidas', 'aviso_mtpe',    -- 49.4 a) a d)
                  'informe', 'traslado_informe', 'decision',       -- 49.4 e) a g)
                  'aviso_decision', 'delito')),                    -- 49.4 h) e i)
  norma         text not null,
  descripcion   text not null,
  -- Quién tiene que cumplirlo: 'do' (DO, o la Gerencia cuando el caso es
  -- sobre DO) o 'investigadora'.
  duena         text not null check (duena in ('do', 'investigadora')),
  desde         timestamptz not null,
  vence_at      timestamptz not null,
  cumplido_at   timestamptz,
  cumplido_por  uuid references personas(id),
  nota          text,
  anulado_at    timestamptz,
  creado_at     timestamptz not null default now(),
  constraint chk_plazo_cumplido_o_anulado check (cumplido_at is null or anulado_at is null)
);

create unique index if not exists uq_reporte_plazo_vivo
  on reporte_plazos(reporte_id, clave) where anulado_at is null;
create index if not exists idx_reporte_plazos_pendientes
  on reporte_plazos(vence_at) where cumplido_at is null and anulado_at is null;

-- Un plazo se cumple o se anula UNA vez, y nada más cambia. Es la prueba de que
-- el Reglamento se cumplió; correr una fecha la destruiría.
create or replace function fn_reporte_plazos_guardian()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un plazo no se borra: se cumple o se anula.';
  end if;
  if new.reporte_id is distinct from old.reporte_id
     or new.clave is distinct from old.clave
     or new.desde is distinct from old.desde
     or new.vence_at is distinct from old.vence_at then
    raise exception 'Un plazo no se corre: su vencimiento lo fija el Reglamento.';
  end if;
  if old.cumplido_at is not null and (new.cumplido_at is distinct from old.cumplido_at
                                      or new.nota is distinct from old.nota
                                      or new.cumplido_por is distinct from old.cumplido_por) then
    raise exception 'Un plazo cumplido no cambia: ni su fecha ni su nota.';
  end if;
  if old.anulado_at is not null and new.anulado_at is distinct from old.anulado_at then
    raise exception 'Un plazo anulado no se revive.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_reporte_plazos_guardian on reporte_plazos;
create trigger trg_reporte_plazos_guardian
  before update or delete on reporte_plazos
  for each row execute function fn_reporte_plazos_guardian();

alter table reporte_plazos enable row level security;
drop policy if exists reporte_plazos_select on reporte_plazos;
-- Quien reportó ve sus plazos: son sus derechos (43-B.2, 43-A.6, 49.4).
create policy reporte_plazos_select on reporte_plazos
  for select to authenticated
  using (fn_reporte_puede_ver(reporte_id));
revoke all on reporte_plazos from anon, authenticated, public;
grant select on reporte_plazos to authenticated;


-- ── 2 · Guardianes de medidas y órganos ─────────────────────────────────────
create or replace function fn_reporte_medidas_guardian()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una medida de protección no se borra.';
  end if;
  if new.instruccion is distinct from old.instruccion
     or new.para_persona_id is distinct from old.para_persona_id
     or new.reporte_id is distinct from old.reporte_id
     or new.creada_por is distinct from old.creada_por then
    raise exception 'Una medida no se reescribe: se dicta otra.';
  end if;
  if old.cumplida_at is not null and new.cumplida_at is distinct from old.cumplida_at then
    raise exception 'Una medida cumplida no cambia de fecha.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_reporte_medidas_guardian on reporte_medidas;
create trigger trg_reporte_medidas_guardian
  before update or delete on reporte_medidas
  for each row execute function fn_reporte_medidas_guardian();

create or replace function fn_organos_titulo_x_guardian()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un nombramiento del Título X no se borra: se cierra con fecha.';
  end if;
  if new.sede_id is distinct from old.sede_id
     or new.persona_id is distinct from old.persona_id
     or new.papel is distinct from old.papel
     or new.desde is distinct from old.desde then
    raise exception 'Un nombramiento no se reescribe: se cierra y se registra otro.';
  end if;
  if old.hasta is not null and new.hasta is distinct from old.hasta then
    raise exception 'Un nombramiento cerrado no se reabre.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_organos_titulo_x_guardian on organos_titulo_x;
create trigger trg_organos_titulo_x_guardian
  before update or delete on organos_titulo_x
  for each row execute function fn_organos_titulo_x_guardian();


-- ── 3 · Piezas internas ─────────────────────────────────────────────────────
create or replace function fn_reporte_evento(p_reporte uuid, p_tipo text, p_detalle jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = public
as $fn$
  insert into reporte_eventos (reporte_id, tipo, por, detalle)
  values (p_reporte, p_tipo, fn_persona_actual_id(), coalesce(p_detalle, '{}'::jsonb));
$fn$;

-- LA definición de cada plazo. `p_vence` solo lo usa `respuesta_prometida`,
-- cuya fecha la fija DO al avisar (43-B.2).
create or replace function fn_reporte_plazo_abrir(
  p_reporte uuid, p_clave text, p_desde timestamptz, p_vence timestamptz default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_norma text; v_desc text; v_n int; v_tipo text; v_duena text := 'do';
  v_vence timestamptz;
  v_id    uuid;
begin
  case p_clave
    when 'respuesta'           then v_norma := '43-B.2';     v_n := 10; v_tipo := 'habiles';
      v_desc := 'Respuesta escrita, o aviso de la fecha en que se responderá';
    when 'respuesta_prometida' then v_norma := '43-B.2';     v_n := 0;  v_tipo := 'fecha';
      v_desc := 'Respuesta escrita en la fecha avisada';
    when 'acuse'               then v_norma := '43-A.6';     v_n := 1;  v_tipo := 'habiles';
      v_desc := 'Acuse de recibo';
    when 'resolucion'          then v_norma := '43-A.6';     v_n := 15; v_tipo := 'habiles';
      v_desc := 'Resolución escrita';
    when 'salud'               then v_norma := '49.4 a), 50.1'; v_n := 1; v_tipo := 'habiles';
      v_desc := 'Poner a disposición la atención en salud, con constancia firmada';
    when 'traslado'            then v_norma := '49.4 b)';    v_n := 1;  v_tipo := 'habiles';
      v_desc := 'Trasladar a quien investiga y poner los hechos en conocimiento de la persona denunciada';
    when 'medidas'             then v_norma := '49.4 c), 50.3'; v_n := 3; v_tipo := 'habiles';
      v_desc := 'Dictar y ejecutar las medidas de protección';
    when 'aviso_mtpe'          then v_norma := '49.4 d)';    v_n := 6;  v_tipo := 'habiles';
      v_desc := 'Comunicar al MTPE la queja y las medidas de protección';
    when 'informe'             then v_norma := '49.4 e)';    v_n := 15; v_tipo := 'calendario';
      v_desc := 'Informe de quien investiga'; v_duena := 'investigadora';
    when 'traslado_informe'    then v_norma := '49.4 f)';    v_n := 1;  v_tipo := 'habiles';
      v_desc := 'Trasladar el informe a DO'; v_duena := 'investigadora';
    when 'decision'            then v_norma := '49.4 g)';    v_n := 10; v_tipo := 'calendario';
      v_desc := 'Decisión escrita de DO';
    when 'aviso_decision'      then v_norma := '49.4 h)';    v_n := 6;  v_tipo := 'habiles';
      v_desc := 'Informar la decisión al MTPE';
    when 'delito'              then v_norma := '49.4 i)';    v_n := 24; v_tipo := 'horas';
      v_desc := 'Poner los indicios de delito en conocimiento del Ministerio Público o la PNP';
    else
      raise exception 'Plazo desconocido: %.', p_clave;
  end case;

  v_vence := case v_tipo
    when 'habiles'    then fn_sumar_dias_habiles(p_desde, v_n)
    -- Días calendario: vence al final del día, igual que los hábiles.
    when 'calendario' then (((p_desde at time zone 'America/Lima')::date + v_n) + time '23:59:59') at time zone 'America/Lima'
    when 'horas'      then p_desde + make_interval(hours => v_n)
    when 'fecha'      then p_vence
  end;
  if v_vence is null then
    raise exception 'El plazo % necesita una fecha de vencimiento.', p_clave;
  end if;

  insert into reporte_plazos (reporte_id, clave, norma, descripcion, duena, desde, vence_at)
  values (p_reporte, p_clave, v_norma, v_desc, v_duena, p_desde, v_vence)
  returning id into v_id;
  return v_id;
end;
$fn$;

-- Los plazos con que nace cada vía, contados desde la recepción.
create or replace function fn_reporte_plazos_de_via(p_reporte uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_r record;
begin
  select id, via, creado_at into v_r from reportes where id = p_reporte;
  if v_r.via = 'reclamo' then
    perform fn_reporte_plazo_abrir(p_reporte, 'respuesta', v_r.creado_at);
  elsif v_r.via = 'convivencia' then
    perform fn_reporte_plazo_abrir(p_reporte, 'acuse', v_r.creado_at);
    perform fn_reporte_plazo_abrir(p_reporte, 'resolucion', v_r.creado_at);
    -- El acuse lo da el sistema, a nombre de DO, en el mismo acto (plan, decisión 14).
    update reporte_plazos
       set cumplido_at = now(), nota = 'Acuse automático de Dynamic, a nombre de Desarrollo Organizacional.'
     where reporte_id = p_reporte and clave = 'acuse' and anulado_at is null and cumplido_at is null;
  else
    perform fn_reporte_plazo_abrir(p_reporte, 'salud',      v_r.creado_at);
    perform fn_reporte_plazo_abrir(p_reporte, 'traslado',   v_r.creado_at);
    perform fn_reporte_plazo_abrir(p_reporte, 'medidas',    v_r.creado_at);
    perform fn_reporte_plazo_abrir(p_reporte, 'aviso_mtpe', v_r.creado_at);
    perform fn_reporte_plazo_abrir(p_reporte, 'informe',    v_r.creado_at);
  end if;
end;
$fn$;

-- ¿Hay alguna persona activa que gestione este reporte con este motivo? Dice
-- SI hay alguien, nunca QUIÉN. Mismo universo de candidatas que
-- `fn_reporte_quien_lo_leera`.
create or replace function fn_reporte_hay_quien(p_reporte uuid, p_motivo text)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (
    select 1
      from (select p.id from personas p
             where p.estado = 'activo' and p.rol in ('supervisor_sede', 'lider_do', 'admin')
            union
            select o.persona_id from organos_titulo_x o
             where o.sede_id = (select sede_id from reportes where id = p_reporte)) c
     where fn_reporte_motivo_de(p_reporte, c.id) = p_motivo);
$fn$;

-- Quién lleva un caso al entrar: el primer escalón de la cadena que tenga a
-- alguien para recibirlo (plan, decisiones 11 a 14 y tabla de la sección 7).
create or replace function fn_reporte_gestora_inicial(p_reporte uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_r      record;
  v_orden  text[];
  v_m      text;
begin
  select via, nivel into v_r from reportes where id = p_reporte;
  v_orden := case
    when v_r.via = 'titulo_x' then array['do', 'gerencia']
    when v_r.nivel = 0        then array['lider', 'do', 'gerencia']
    when v_r.nivel = 1        then array['do', 'gerencia']
    when v_r.nivel = 2        then array['gerencia', 'do']
    else                           array['do']
  end;
  foreach v_m in array v_orden loop
    if fn_reporte_hay_quien(p_reporte, v_m) then
      return v_m;
    end if;
  end loop;
  return null;
end;
$fn$;


-- ── 4 · Crear un reporte ────────────────────────────────────────────────────
create or replace function fn_reporte_crear(
  p_tipo           text,
  p_via            text,
  p_sede           uuid,
  p_fecha_hecho    date,
  p_relato         text,
  p_involucradas   uuid[]  default '{}',
  p_testigos       uuid[]  default '{}',
  p_espera         text    default null,
  p_urgente        boolean default false,
  p_primera_vez    boolean default null,
  p_ya_conversado  text    default null,
  p_ticket         text    default null
)
returns table (id uuid, codigo text)
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_inv     uuid[] := array(select distinct x from unnest(coalesce(p_involucradas, '{}'::uuid[])) x where x is not null);
  v_tes     uuid[] := array(select distinct x from unnest(coalesce(p_testigos, '{}'::uuid[])) x where x is not null);
  v_id      uuid;
  v_codigo  text;
  v_gestiona text;
begin
  if v_yo is null or not exists (select 1 from personas where personas.id = v_yo and estado = 'activo') then
    raise exception 'Tu usuario no está enlazado a una ficha activa.';
  end if;

  if p_via is null or p_via not in ('reclamo', 'convivencia', 'titulo_x') then
    raise exception 'Vía de reporte desconocida.';
  end if;
  if p_tipo is null or p_tipo not in ('persona', 'empresa', 'clienta', 'idea', 'consulta') then
    raise exception 'Tipo de reporte desconocido.';
  end if;
  -- El Título X alcanza también a clientas (47.7); la convivencia es entre personas.
  if p_via = 'titulo_x' and p_tipo not in ('persona', 'clienta') then
    raise exception 'Una queja de hostigamiento sexual es sobre una persona o una clienta.';
  end if;
  if p_via = 'convivencia' and p_tipo <> 'persona' then
    raise exception 'Un reporte de convivencia es sobre una persona del equipo.';
  end if;
  if p_tipo = 'persona' and p_via <> 'titulo_x' and cardinality(v_inv) = 0 then
    raise exception 'Elige a la persona sobre la que reportas.';
  end if;
  if p_tipo in ('empresa', 'idea', 'consulta') and cardinality(v_inv) > 0 then
    raise exception 'Un reporte sobre la empresa, una idea o una consulta no nombra a personas involucradas.';
  end if;
  -- Una consulta es del 43-B, siempre: la absorbida 0435 (plan, decisión 20).
  if p_tipo = 'consulta' and p_via <> 'reclamo' then
    raise exception 'Una consulta a tu líder va por el 43-B: consultas, reclamos y sugerencias.';
  end if;

  if v_yo = any(v_inv) or v_yo = any(v_tes) then
    raise exception 'No puedes nombrarte a ti misma como involucrada ni como testigo.';
  end if;
  if v_inv && v_tes then
    raise exception 'Una persona no puede ser involucrada y testigo a la vez.';
  end if;
  if exists (select 1 from unnest(v_inv || v_tes) x where not exists (select 1 from personas p where p.id = x)) then
    raise exception 'Una de las personas elegidas no existe.';
  end if;

  if not exists (select 1 from sedes s where s.id = p_sede and s.activa) then
    raise exception 'Sede inválida o inactiva.';
  end if;
  if p_fecha_hecho is null or p_fecha_hecho > fn_hoy_lima() then
    raise exception 'La fecha del hecho no puede estar vacía ni ser futura.';
  end if;
  if p_relato is null or length(trim(p_relato)) = 0 then
    raise exception 'Cuenta qué pasó.';
  end if;

  insert into reportes (autor_id, sede_id, tipo, via, urgente, fecha_hecho, relato,
                        espera, primera_vez, ya_conversado, ticket)
  values (v_yo, p_sede, p_tipo, p_via, coalesce(p_urgente, false), p_fecha_hecho, trim(p_relato),
          p_espera, p_primera_vez, nullif(trim(coalesce(p_ya_conversado, '')), ''),
          nullif(trim(coalesce(p_ticket, '')), ''))
  returning reportes.id, reportes.codigo into v_id, v_codigo;

  -- La foto del rol y el nivel la toma el trigger de reporte_personas (0483).
  insert into reporte_personas (reporte_id, persona_id, papel)
  select v_id, x, 'involucrada' from unnest(v_inv) x
  union all
  select v_id, x, 'testigo' from unnest(v_tes) x;

  v_gestiona := fn_reporte_gestora_inicial(v_id);
  if v_gestiona is null then
    -- La transacción entera se deshace: no queda un reporte que nadie leerá.
    raise exception 'Hoy no hay en Dynamic nadie que pueda recibir este reporte sin estar mencionado en él. Entrégalo en sobre cerrado a Desarrollo Organizacional o a la Gerencia General (numeral 48.7), o acude a SUNAFIL, al MTPE, al Ministerio Público o a la Policía (numeral 48.9).';
  end if;

  update reportes set gestiona = v_gestiona where reportes.id = v_id;

  perform fn_reporte_evento(v_id, 'creado', jsonb_build_object('via', p_via, 'tipo', p_tipo, 'urgente', coalesce(p_urgente, false)));
  perform fn_reporte_plazos_de_via(v_id);
  if p_via = 'convivencia' then
    insert into reporte_eventos (reporte_id, tipo, por, detalle)
    values (v_id, 'acuse', null, '{"automatico": true, "a_nombre_de": "Desarrollo Organizacional"}');
  end if;

  return query select v_id, v_codigo;
end;
$fn$;


-- ── 5 · El hilo, el estado y las acciones ───────────────────────────────────
-- `p_responde_para`: el aviso del 43-B.2 («responderemos el día X»). Cumple el
-- plazo de 10 días y abre uno nuevo que vence esa fecha.
create or replace function fn_reporte_mensaje(
  p_reporte uuid, p_texto text, p_interno boolean default false, p_responde_para date default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_motivo  text := fn_reporte_motivo(p_reporte);
  v_r       record;
  v_id      uuid;
begin
  select r.estado, r.via into v_r from reportes r where r.id = p_reporte;
  if not found then
    raise exception 'Ese reporte no existe.';
  end if;
  if p_texto is null or length(trim(p_texto)) = 0 then
    raise exception 'Escribe algo.';
  end if;

  if v_motivo is null then
    if fn_reporte_es_autor(p_reporte) is not true then
      raise exception 'No puedes escribir en este reporte.';
    end if;
    if coalesce(p_interno, false) or p_responde_para is not null then
      raise exception 'Solo quien gestiona el caso puede dejar notas internas o avisar una fecha.';
    end if;
    if v_r.estado = 'cerrado' then
      raise exception 'Este reporte ya se cerró. Si pasó algo nuevo, envía un reporte nuevo.';
    end if;
  end if;

  if p_responde_para is not null then
    if v_r.via <> 'reclamo' then
      raise exception 'El aviso de fecha es del 43-B.2: solo en reclamos y sugerencias.';
    end if;
    if coalesce(p_interno, false) then
      raise exception 'El aviso de fecha tiene que llegarle a quien reportó: no puede ser una nota interna.';
    end if;
    if p_responde_para <= fn_hoy_lima() then
      raise exception 'La fecha en que se responderá tiene que ser futura.';
    end if;
    if not exists (select 1 from reporte_plazos where reporte_id = p_reporte and clave = 'respuesta'
                     and cumplido_at is null and anulado_at is null) then
      raise exception 'Ya no hay un plazo de respuesta pendiente que avisar.';
    end if;
  end if;

  insert into reporte_mensajes (reporte_id, autor_id, texto, interno)
  values (p_reporte, v_yo, trim(p_texto), coalesce(p_interno, false))
  returning reporte_mensajes.id into v_id;

  if p_responde_para is not null then
    update reporte_plazos
       set cumplido_at = now(), cumplido_por = v_yo,
           nota = 'Aviso de fecha: se responderá el ' || to_char(p_responde_para, 'DD/MM/YYYY') || '.'
     where reporte_id = p_reporte and clave = 'respuesta' and cumplido_at is null and anulado_at is null;
    perform fn_reporte_plazo_abrir(p_reporte, 'respuesta_prometida', now(),
      ((p_responde_para + time '23:59:59') at time zone 'America/Lima'));
    perform fn_reporte_evento(p_reporte, 'plazo', jsonb_build_object('clave', 'respuesta', 'aviso_fecha', p_responde_para));
  end if;

  -- La primera palabra de quien gestiona hacia quien reportó pone el caso en revisión.
  if v_motivo is not null and not coalesce(p_interno, false) and v_r.estado = 'recibido' then
    update reportes set estado = 'en_revision' where reportes.id = p_reporte;
    perform fn_reporte_evento(p_reporte, 'estado', '{"a": "en_revision"}');
  end if;

  return v_id;
end;
$fn$;

create or replace function fn_reporte_en_revision(p_reporte uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
begin
  if fn_reporte_motivo(p_reporte) is null then
    raise exception 'No gestionas este reporte.';
  end if;
  update reportes set estado = 'en_revision' where id = p_reporte and estado = 'recibido';
  if found then
    perform fn_reporte_evento(p_reporte, 'estado', '{"a": "en_revision"}');
  end if;
end;
$fn$;

-- Lo que se hizo, para la línea de tiempo. En el Título X no hay mediación ni
-- conversación entre las partes: el 48.14 prohíbe la confrontación.
create or replace function fn_reporte_anotar_accion(p_reporte uuid, p_accion text, p_nota text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_via text;
begin
  if fn_reporte_motivo(p_reporte) is null then
    raise exception 'No gestionas este reporte.';
  end if;
  if p_accion is null or p_accion not in ('conversacion', 'mediacion', 'cambio_proceso', 'otra') then
    raise exception 'Acción desconocida.';
  end if;
  if p_nota is null or length(trim(p_nota)) < 3 then
    raise exception 'Anota qué se hizo.';
  end if;
  select via into v_via from reportes where id = p_reporte;
  if v_via = 'titulo_x' and p_accion in ('conversacion', 'mediacion') then
    raise exception 'En el Título X no se media ni se reúne a las partes: el numeral 48.14 prohíbe la confrontación.';
  end if;
  perform fn_reporte_evento(p_reporte, 'accion', jsonb_build_object('accion', p_accion, 'nota', trim(p_nota)));
end;
$fn$;


-- ── 6 · Reclasificar y escalar ──────────────────────────────────────────────
create or replace function fn_reporte_reclasificar(p_reporte uuid, p_via text, p_motivo text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_motivo   text := fn_reporte_motivo(p_reporte);
  v_r        record;
  v_gestiona text;
begin
  if v_motivo is null then
    raise exception 'No gestionas este reporte.';
  end if;
  select via, tipo, estado into v_r from reportes where id = p_reporte;
  if v_r.estado = 'cerrado' then
    raise exception 'Un reporte cerrado no se reclasifica.';
  end if;
  if p_via is null or p_via not in ('reclamo', 'convivencia', 'titulo_x') then
    raise exception 'Vía de reporte desconocida.';
  end if;
  if p_via = v_r.via then
    return;
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Explica por qué cambia de vía.';
  end if;
  -- Sacar un caso del Título X es decisión de quien lo recibe (48.1), no de
  -- quien investiga ni de la líder, que ni siquiera lo ve.
  if v_r.via = 'titulo_x' and v_motivo not in ('do', 'gerencia') then
    raise exception 'Solo Desarrollo Organizacional saca un caso del Título X.';
  end if;
  if p_via = 'titulo_x' and v_r.tipo not in ('persona', 'clienta') then
    raise exception 'Una queja de hostigamiento sexual es sobre una persona o una clienta.';
  end if;
  if p_via = 'convivencia' and v_r.tipo <> 'persona' then
    raise exception 'Un reporte de convivencia es sobre una persona del equipo.';
  end if;

  update reportes set via = p_via where id = p_reporte;

  v_gestiona := fn_reporte_gestora_inicial(p_reporte);
  if v_gestiona is null then
    raise exception 'Con esa vía nadie en Dynamic podría recibir este caso sin estar mencionado. No se cambió.';
  end if;
  update reportes set gestiona = v_gestiona where id = p_reporte;

  -- Los plazos pendientes se anulan (queda cuándo); se abren los de la vía nueva.
  update reporte_plazos set anulado_at = now()
   where reporte_id = p_reporte and cumplido_at is null and anulado_at is null;
  perform fn_reporte_plazos_de_via(p_reporte);

  perform fn_reporte_evento(p_reporte, 'reclasificado',
    jsonb_build_object('de', v_r.via, 'a', p_via, 'motivo', trim(p_motivo)));
end;
$fn$;

create or replace function fn_reporte_escalar(p_reporte uuid, p_motivo text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_motivo  text := fn_reporte_motivo(p_reporte);
  v_actual  text;
  v_estado  text;
  v_sig     text;
begin
  if v_motivo is null then
    raise exception 'No gestionas este reporte.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Explica por qué se escala.';
  end if;
  select gestiona, estado into v_actual, v_estado from reportes where id = p_reporte;
  if v_estado = 'cerrado' then
    raise exception 'Un reporte cerrado no se escala.';
  end if;
  v_sig := case v_actual when 'lider' then 'do' when 'do' then 'gerencia' end;
  if v_sig is null then
    raise exception 'Este caso ya está en el último escalón.';
  end if;
  if not fn_reporte_hay_quien(p_reporte, v_sig) then
    raise exception 'En el siguiente escalón no hay nadie que pueda recibir este caso sin estar mencionado.';
  end if;
  update reportes set gestiona = v_sig where id = p_reporte;
  perform fn_reporte_evento(p_reporte, 'escalado',
    jsonb_build_object('de', v_actual, 'a', v_sig, 'motivo', trim(p_motivo)));
end;
$fn$;


-- ── 7 · Plazos que se cumplen a mano ────────────────────────────────────────
-- Los del Título X que son actos de DO o de quien investiga. La nota es
-- obligatoria: toda actuación se documenta (48.12).
create or replace function fn_reporte_plazo_cumplir(p_reporte uuid, p_clave text, p_nota text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo     uuid := fn_persona_actual_id();
  v_motivo text := fn_reporte_motivo(p_reporte);
  v_duena  text;
begin
  if v_motivo is null then
    raise exception 'No gestionas este reporte.';
  end if;
  if p_nota is null or length(trim(p_nota)) < 3 then
    raise exception 'Anota qué se hizo: toda actuación se documenta (48.12).';
  end if;
  if p_clave in ('respuesta', 'respuesta_prometida', 'resolucion', 'decision', 'acuse') then
    raise exception 'Ese plazo se cumple al responder o al cerrar el caso, no a mano.';
  end if;

  select duena into v_duena from reporte_plazos
   where reporte_id = p_reporte and clave = p_clave and cumplido_at is null and anulado_at is null;
  if not found then
    raise exception 'No hay un plazo «%» pendiente en este reporte.', p_clave;
  end if;
  -- Ese plazo es de quien investiga (48.3). La única excepción es la persona
  -- EXTERNA del 48.2-bis b), que no tiene cuenta: si en Dynamic no hay
  -- investigadora para este caso, DO registra el informe que ella entregó.
  if v_duena = 'investigadora' and v_motivo <> 'investigadora'
     and (v_motivo not in ('do', 'gerencia') or fn_reporte_hay_quien(p_reporte, 'investigadora')) then
    raise exception 'Ese plazo es de quien investiga (48.3): quien decide no escribe el informe.';
  end if;
  if v_duena = 'do' and v_motivo not in ('do', 'gerencia') then
    raise exception 'Ese plazo es de Desarrollo Organizacional.';
  end if;

  update reporte_plazos set cumplido_at = now(), cumplido_por = v_yo, nota = trim(p_nota)
   where reporte_id = p_reporte and clave = p_clave and cumplido_at is null and anulado_at is null;

  -- Registrar el informe en Dynamic ES entregarlo a DO: f) se cumple en el
  -- mismo acto, y g) corre desde ahí.
  if p_clave = 'informe' then
    perform fn_reporte_plazo_abrir(p_reporte, 'traslado_informe', now());
    update reporte_plazos set cumplido_at = now(), cumplido_por = v_yo,
           nota = 'El informe quedó registrado en Dynamic, a la vista de Desarrollo Organizacional.'
     where reporte_id = p_reporte and clave = 'traslado_informe' and anulado_at is null;
    perform fn_reporte_plazo_abrir(p_reporte, 'decision', now());
  end if;

  perform fn_reporte_evento(p_reporte, 'plazo', jsonb_build_object('clave', p_clave, 'nota', trim(p_nota)));
end;
$fn$;

create or replace function fn_reporte_indicios_delito(p_reporte uuid, p_nota text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
begin
  if coalesce(fn_reporte_motivo(p_reporte), '') not in ('do', 'gerencia') then
    raise exception 'Solo Desarrollo Organizacional registra indicios de delito.';
  end if;
  if (select via from reportes where id = p_reporte) <> 'titulo_x' then
    raise exception 'El plazo de 24 horas del 49.4 i) es del Título X.';
  end if;
  if p_nota is null or length(trim(p_nota)) < 3 then
    raise exception 'Anota cuáles son los indicios.';
  end if;
  if exists (select 1 from reporte_plazos where reporte_id = p_reporte and clave = 'delito' and anulado_at is null) then
    raise exception 'Los indicios de delito de este caso ya están registrados.';
  end if;
  perform fn_reporte_plazo_abrir(p_reporte, 'delito', now());
  perform fn_reporte_evento(p_reporte, 'plazo', jsonb_build_object('clave', 'delito', 'nota', trim(p_nota)));
end;
$fn$;


-- ── 8 · Medidas ─────────────────────────────────────────────────────────────
-- DO dicta; la líder ejecuta sin conocer los hechos (plan, decisión 16).
create or replace function fn_reporte_medida(p_reporte uuid, p_para uuid, p_instruccion text, p_hasta date default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo  uuid := fn_persona_actual_id();
  v_via text;
  v_id  uuid;
begin
  if coalesce(fn_reporte_motivo(p_reporte), '') not in ('do', 'gerencia') then
    raise exception 'Solo Desarrollo Organizacional dicta medidas de protección.';
  end if;
  select via into v_via from reportes where id = p_reporte;
  if v_via = 'reclamo' then
    raise exception 'Las medidas de protección son de convivencia (43-A.6) y del Título X (50.3).';
  end if;
  if p_instruccion is null or length(trim(p_instruccion)) < 3 then
    raise exception 'Escribe la instrucción.';
  end if;
  if p_hasta is not null and p_hasta < fn_hoy_lima() then
    raise exception 'La medida no puede vencer en el pasado.';
  end if;
  if not exists (select 1 from personas where id = p_para and estado = 'activo' and rol = 'supervisor_sede') then
    raise exception 'La instrucción va a una líder de equipo activa.';
  end if;
  if exists (select 1 from reporte_personas where reporte_id = p_reporte and persona_id = p_para) then
    raise exception 'Esa líder está mencionada en el caso: la medida la ejecuta otra persona.';
  end if;

  insert into reporte_medidas (reporte_id, para_persona_id, instruccion, vigente_hasta, creada_por)
  values (p_reporte, p_para, trim(p_instruccion), p_hasta, v_yo)
  returning reporte_medidas.id into v_id;

  update reporte_plazos set cumplido_at = now(), cumplido_por = v_yo,
         nota = 'Medida dictada y encargada a la líder de equipo.'
   where reporte_id = p_reporte and clave = 'medidas' and cumplido_at is null and anulado_at is null;

  perform fn_reporte_evento(p_reporte, 'medida', jsonb_build_object('medida_id', v_id));
  return v_id;
end;
$fn$;

create or replace function fn_reporte_medida_cumplida(p_medida uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
begin
  update reporte_medidas set cumplida_at = now()
   where id = p_medida and para_persona_id = fn_persona_actual_id() and cumplida_at is null;
  if not found then
    raise exception 'Esa medida no te fue encargada, o ya la marcaste como cumplida.';
  end if;
end;
$fn$;


-- ── 9 · Cerrar y derivar ────────────────────────────────────────────────────
create or replace function fn_reporte_cerrar(p_reporte uuid, p_resultado text, p_texto text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo     uuid := fn_persona_actual_id();
  v_motivo text := fn_reporte_motivo(p_reporte);
  v_r      record;
begin
  if v_motivo is null then
    raise exception 'No gestionas este reporte.';
  end if;
  select via, estado, expediente_id into v_r from reportes where id = p_reporte;
  if v_r.estado = 'cerrado' then
    raise exception 'Este reporte ya está cerrado.';
  end if;
  -- Plan, decisión 14: en convivencia la líder actúa, pero cierra DO.
  if v_r.via in ('convivencia', 'titulo_x') and v_motivo not in ('do', 'gerencia') then
    raise exception 'Este caso lo cierra Desarrollo Organizacional, con la respuesta escrita del Reglamento.';
  end if;
  if v_r.via = 'titulo_x' and not exists (
       select 1 from reporte_plazos where reporte_id = p_reporte and clave = 'informe'
          and cumplido_at is not null and anulado_at is null) then
    raise exception 'DO decide con el informe de quien investiga (48.1, 49.7). Todavía no está registrado.';
  end if;
  if p_resultado is null or p_resultado not in
       ('resuelto', 'confirmado', 'no_confirmado', 'derivado_disciplinario', 'sin_accion') then
    raise exception 'Resultado desconocido.';
  end if;
  if p_resultado = 'derivado_disciplinario' and v_r.expediente_id is null then
    raise exception 'Para cerrar como derivado a disciplina, primero enlaza el expediente.';
  end if;
  if p_texto is null or length(trim(p_texto)) < 10 then
    raise exception 'Escribe la respuesta para quien reportó: es la respuesta escrita que exige el Reglamento.';
  end if;

  update reportes
     set estado = 'cerrado', cerrado_at = now(), cierre_resultado = p_resultado, cierre_texto = trim(p_texto)
   where id = p_reporte;

  update reporte_plazos set cumplido_at = now(), cumplido_por = v_yo, nota = 'Cierre con respuesta escrita.'
   where reporte_id = p_reporte and anulado_at is null and cumplido_at is null
     and clave in ('respuesta', 'respuesta_prometida', 'resolucion', 'decision');

  -- La decisión del Título X se informa al MTPE en 6 días hábiles (49.4 h).
  if v_r.via = 'titulo_x' then
    perform fn_reporte_plazo_abrir(p_reporte, 'aviso_decision', now());
  end if;

  perform fn_reporte_evento(p_reporte, 'cerrado', jsonb_build_object('resultado', p_resultado));
end;
$fn$;

-- Un reporte NO es una falta (plan, sección 11). Esto solo enlaza con un
-- expediente que DO ya abrió por el camino de siempre, sobre una involucrada.
create or replace function fn_reporte_derivar(p_reporte uuid, p_expediente uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_persona uuid;
begin
  if coalesce(fn_reporte_motivo(p_reporte), '') not in ('do', 'gerencia') then
    raise exception 'Solo Desarrollo Organizacional enlaza un reporte con disciplina.';
  end if;
  select persona_id into v_persona from expediente_disciplinario where id = p_expediente;
  if not found then
    raise exception 'Ese expediente no existe.';
  end if;
  if not exists (select 1 from reporte_personas where reporte_id = p_reporte
                   and persona_id = v_persona and papel = 'involucrada') then
    raise exception 'El expediente es de una persona que no está involucrada en este reporte.';
  end if;
  update reportes set expediente_id = p_expediente where id = p_reporte and expediente_id is null;
  if not found then
    raise exception 'Este reporte ya está enlazado con un expediente.';
  end if;
  perform fn_reporte_evento(p_reporte, 'derivado_expediente', jsonb_build_object('expediente_id', p_expediente));
end;
$fn$;


-- ── 10 · Adjuntos y lecturas ────────────────────────────────────────────────
-- El archivo se sube primero al bucket (como en la 0482) y aquí se registra:
-- desde ese momento es evidencia y no se pisa ni se borra.
create or replace function fn_reporte_adjuntar(p_reporte uuid, p_path text, p_interno boolean default false)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_gestora boolean := fn_reporte_puede_gestionar(p_reporte);
  v_obj     record;
  v_id      uuid;
begin
  if not v_gestora and fn_reporte_es_autor(p_reporte) is not true then
    raise exception 'No puedes adjuntar archivos a este reporte.';
  end if;
  if not v_gestora and coalesce(p_interno, false) then
    raise exception 'Solo quien gestiona el caso adjunta archivos internos.';
  end if;
  if not v_gestora and (select estado from reportes where id = p_reporte) = 'cerrado' then
    raise exception 'Este reporte ya se cerró.';
  end if;
  if fn_reporte_de_ruta(p_path) is distinct from p_reporte then
    raise exception 'La ruta del archivo no corresponde a este reporte.';
  end if;
  select o.metadata into v_obj from storage.objects o where o.bucket_id = 'reportes' and o.name = p_path;
  if not found then
    raise exception 'El archivo no llegó al almacenamiento. Vuelve a subirlo.';
  end if;

  insert into reporte_adjuntos (reporte_id, storage_path, subido_por, interno, mimetype, bytes)
  values (p_reporte, p_path, v_yo, coalesce(p_interno, false),
          v_obj.metadata ->> 'mimetype', nullif(v_obj.metadata ->> 'size', '')::bigint)
  on conflict (storage_path) do nothing
  returning reporte_adjuntos.id into v_id;
  return v_id;
end;
$fn$;

-- La pantalla la llama al abrir la ficha: cada apertura deja rastro. Desde el
-- panel es la trazabilidad del 44.13; la de quien reportó es lo que permite
-- saber qué respuestas todavía no leyó (`fn_reportes_mios.sin_leer`). Devuelve
-- el motivo, para que la pantalla sepa qué mostrar; quien reportó recibe
-- 'autora'.
create or replace function fn_reporte_abrir(p_reporte uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_motivo text := fn_reporte_motivo(p_reporte);
begin
  if v_motivo is not null then
    perform fn_reporte_evento(p_reporte, 'lectura', jsonb_build_object('motivo', v_motivo));
    return v_motivo;
  end if;
  if fn_reporte_es_autor(p_reporte) then
    perform fn_reporte_evento(p_reporte, 'lectura', '{"motivo": "autora"}');
    return 'autora';
  end if;
  raise exception 'No tienes acceso a este reporte.';
end;
$fn$;


-- ── 11 · Las dos listas ─────────────────────────────────────────────────────
-- El panel: lo que la regla deja ver a quien llama, con el plazo que más
-- aprieta. Los cerrados con un plazo pendiente (el aviso al MTPE) siguen aquí.
create or replace function fn_reportes_bandeja()
returns table (
  id               uuid,
  codigo           text,
  tipo             text,
  via              text,
  urgente          boolean,
  estado           text,
  gestiona         text,
  mi_motivo        text,
  sede_codigo      text,
  autora           text,
  creado_at        timestamptz,
  proximo_plazo    text,
  proximo_norma    text,
  proximo_vence_at timestamptz,
  semaforo         text,
  plazos_vencidos  int
)
language sql
stable
security definer
set search_path = public
as $fn$
  with mios as (
    select r.*, fn_reporte_motivo(r.id) as motivo
      from reportes r
  ), vivos as (
    select m.*
      from mios m
     where m.motivo is not null
  )
  select v.id, v.codigo, v.tipo, v.via, v.urgente, v.estado, v.gestiona, v.motivo,
         s.codigo,
         pa.apellidos || ' ' || pa.nombres,
         v.creado_at,
         pp.descripcion, pp.norma, pp.vence_at,
         case
           when pp.vence_at is null then null
           when pp.vence_at < now() then 'vencido'
           when pp.vence_at <= fn_sumar_dias_habiles(now(), 1) then 'por_vencer'
           else 'en_plazo'
         end,
         (select count(*)::int from reporte_plazos x
           where x.reporte_id = v.id and x.cumplido_at is null and x.anulado_at is null and x.vence_at < now())
    from vivos v
    join sedes s on s.id = v.sede_id
    join personas pa on pa.id = v.autor_id
    left join lateral (
      select p.descripcion, p.norma, p.vence_at
        from reporte_plazos p
       where p.reporte_id = v.id and p.cumplido_at is null and p.anulado_at is null
       order by p.vence_at, p.id
       limit 1
    ) pp on true
   where v.estado <> 'cerrado' or pp.vence_at is not null
   order by v.urgente desc, pp.vence_at nulls last, v.creado_at desc, v.id;
$fn$;

-- «Mis reportes»: sin el nombre de nadie, sin el resultado (que habla de otra
-- persona) y sin notas internas. El plazo que se le muestra es el que le
-- promete una respuesta.
create or replace function fn_reportes_mios()
returns table (
  id                uuid,
  codigo            text,
  tipo              text,
  via               text,
  estado            text,
  creado_at         timestamptz,
  cerrado_at        timestamptz,
  cierre_texto      text,
  respuesta_vence_at timestamptz,
  mensajes          int,
  ultimo_mensaje_at timestamptz,
  -- Lo que le escribieron (o el cierre) DESPUÉS de la última vez que ella
  -- abrió el reporte. Es el globito del menú y la fuente de su Bandeja.
  sin_leer          int
)
language sql
stable
security definer
set search_path = public
as $fn$
  with yo as (select fn_persona_actual_id() as id)
  select r.id, r.codigo, r.tipo, r.via, r.estado, r.creado_at, r.cerrado_at, r.cierre_texto,
         (select min(p.vence_at) from reporte_plazos p
           where p.reporte_id = r.id and p.cumplido_at is null and p.anulado_at is null
             and p.clave in ('respuesta', 'respuesta_prometida', 'resolucion', 'decision')),
         (select count(*)::int from reporte_mensajes m where m.reporte_id = r.id and not m.interno),
         (select max(m.creado_at) from reporte_mensajes m where m.reporte_id = r.id and not m.interno),
         (select count(*)::int from reporte_mensajes m
           where m.reporte_id = r.id and not m.interno and m.autor_id <> yo.id
             and m.creado_at > coalesce(lec.at, '-infinity'::timestamptz))
         + case when r.cerrado_at > coalesce(lec.at, '-infinity'::timestamptz) then 1 else 0 end
    from reportes r
    cross join yo
    left join lateral (
      select max(e.at) as at from reporte_eventos e
       where e.reporte_id = r.id and e.tipo = 'lectura' and e.por = yo.id
    ) lec on true
   where r.autor_id = yo.id
   order by r.creado_at desc, r.id;
$fn$;

-- ── 11b · Lo que leen las pantallas de un reporte ───────────────────────────
-- Todo por funciones y no por las tablas: así la pantalla de quien reportó
-- nunca recibe una columna que no le toca (el resultado, las notas internas,
-- los nombres de quienes gestionan).

-- El padrón para elegir a quién se reporta y quién lo vio. Una integrante no
-- puede leer `personas` (RLS de la 0003): esto le da solo nombre, cargo y sede
-- de las personas activas, que son datos que el equipo ya conoce.
create or replace function fn_reporte_padron()
returns table (id uuid, nombre text, cargo text, sede_codigo text)
language sql
stable
security definer
set search_path = public
as $fn$
  select p.id, p.nombres || ' ' || p.apellidos, p.cargo, s.codigo
    from personas p
    left join sedes s on s.id = p.sede_base_id
   where p.estado = 'activo'
     and fn_persona_actual_id() is not null
     and p.id <> fn_persona_actual_id()
   order by p.nombres, p.apellidos, p.id;
$fn$;

create or replace function fn_reporte_detalle(p_reporte uuid)
returns table (
  id                 uuid,
  codigo             text,
  tipo               text,
  via                text,
  estado             text,
  urgente            boolean,
  sede_codigo        text,
  fecha_hecho        date,
  relato             text,
  espera             text,
  creado_at          timestamptz,
  cerrado_at         timestamptz,
  cierre_texto       text,
  respuesta_vence_at timestamptz,
  mi_papel           text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_papel text := fn_reporte_motivo(p_reporte);
begin
  if v_papel is null then
    if fn_reporte_es_autor(p_reporte) is not true then
      raise exception 'No tienes acceso a este reporte.';
    end if;
    v_papel := 'autora';
  end if;
  return query
  select r.id, r.codigo, r.tipo, r.via, r.estado, r.urgente, s.codigo, r.fecha_hecho, r.relato,
         r.espera, r.creado_at, r.cerrado_at, r.cierre_texto,
         (select min(p.vence_at) from reporte_plazos p
           where p.reporte_id = r.id and p.cumplido_at is null and p.anulado_at is null
             and p.clave in ('respuesta', 'respuesta_prometida', 'resolucion', 'decision')),
         v_papel
    from reportes r
    join sedes s on s.id = r.sede_id
   where r.id = p_reporte;
end;
$fn$;

-- El hilo. Quien escribió se dice por su CARGO respecto de este caso («Tu
-- líder de equipo», «Desarrollo Organizacional»), no por su nombre: es lo
-- que la pantalla de quien reportó puede mostrar, y quien gestiona ya sabe
-- quién es quién. Las notas internas solo salen para quien gestiona.
create or replace function fn_reporte_hilo(p_reporte uuid)
returns table (id uuid, texto text, interno boolean, creado_at timestamptz, es_mio boolean, quien text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_gestora boolean := fn_reporte_puede_gestionar(p_reporte);
  v_autor   uuid;
begin
  if not v_gestora and fn_reporte_es_autor(p_reporte) is not true then
    raise exception 'No tienes acceso a este reporte.';
  end if;
  select autor_id into v_autor from reportes where reportes.id = p_reporte;
  return query
  select m.id, m.texto, m.interno, m.creado_at, m.autor_id = v_yo,
         case
           when m.autor_id = v_yo    then 'Tú'
           when m.autor_id = v_autor then 'Quien reportó'
           else coalesce(case fn_reporte_motivo_de(p_reporte, m.autor_id)
                  when 'lider'         then case when v_gestora then 'Líder de equipo' else 'Tu líder de equipo' end
                  when 'do'            then 'Desarrollo Organizacional'
                  when 'gerencia'      then 'Gerencia General'
                  when 'investigadora' then 'Quien investiga'
                end, 'Quien gestionó el caso')
         end
    from reporte_mensajes m
   where m.reporte_id = p_reporte
     and (v_gestora or not m.interno)
   order by m.creado_at, m.id;
end;
$fn$;

create or replace function fn_reporte_adjuntos(p_reporte uuid)
returns table (id uuid, storage_path text, mimetype text, bytes bigint, interno boolean, creado_at timestamptz, es_mio boolean)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_gestora boolean := fn_reporte_puede_gestionar(p_reporte);
begin
  if not v_gestora and fn_reporte_es_autor(p_reporte) is not true then
    raise exception 'No tienes acceso a este reporte.';
  end if;
  return query
  select a.id, a.storage_path, a.mimetype, a.bytes, a.interno, a.creado_at, a.subido_por = fn_persona_actual_id()
    from reporte_adjuntos a
   where a.reporte_id = p_reporte and (v_gestora or not a.interno)
   order by a.creado_at, a.id;
end;
$fn$;


-- ── 11c · Lo que lee el panel («Casos») ─────────────────────────────────────

-- ¿Le corresponde el ítem «Casos» del menú? A la líder de equipo, a DO y a la
-- Gerencia General: la MARCA, no el rol admin (decisión 19). Los otros admins
-- no ven el ítem, porque la regla nunca les va a mostrar un caso.
create or replace function fn_ve_casos()
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    fn_rol_actual() in ('supervisor_sede', 'lider_do')
    or fn_persona_actual_id() is not distinct from fn_gerencia_general_id(),
    false);
$fn$;

-- Los plazos de un caso, con su norma y su dueña. Quien reportó también los
-- ve: son sus derechos.
create or replace function fn_reporte_plazos(p_reporte uuid)
returns table (clave text, norma text, descripcion text, duena text, vence_at timestamptz,
               cumplido_at timestamptz, anulado_at timestamptz, nota text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if fn_reporte_puede_ver(p_reporte) is not true then
    raise exception 'No tienes acceso a este reporte.';
  end if;
  return query
  select p.clave, p.norma, p.descripcion, p.duena, p.vence_at, p.cumplido_at, p.anulado_at, p.nota
    from reporte_plazos p
   where p.reporte_id = p_reporte
   order by p.anulado_at nulls first, p.vence_at, p.id;
end;
$fn$;

-- A quién menciona el caso, con nombre: solo para quien lo gestiona.
create or replace function fn_reporte_personas(p_reporte uuid)
returns table (persona_id uuid, nombre text, papel text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if fn_reporte_puede_gestionar(p_reporte) is not true then
    raise exception 'No gestionas este reporte.';
  end if;
  return query
  select rp.persona_id, p.nombres || ' ' || p.apellidos, rp.papel
    from reporte_personas rp
    join personas p on p.id = rp.persona_id
   where rp.reporte_id = p_reporte
   order by rp.papel, p.nombres, rp.persona_id;
end;
$fn$;

-- La línea de tiempo, con quién hizo cada cosa. Las aperturas van aparte en
-- la pantalla; aquí vienen todas, y la pantalla decide cómo agruparlas.
create or replace function fn_reporte_eventos(p_reporte uuid)
returns table (id uuid, at timestamptz, tipo text, quien text, detalle jsonb)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if fn_reporte_puede_gestionar(p_reporte) is not true then
    raise exception 'No gestionas este reporte.';
  end if;
  return query
  select e.id, e.at, e.tipo,
         coalesce(p.nombres || ' ' || p.apellidos, 'Dynamic'),
         e.detalle
    from reporte_eventos e
    left join personas p on p.id = e.por
   where e.reporte_id = p_reporte
   order by e.at, e.id;
end;
$fn$;

create or replace function fn_reporte_medidas(p_reporte uuid)
returns table (id uuid, para text, instruccion text, vigente_hasta date, cumplida_at timestamptz, creado_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if fn_reporte_puede_gestionar(p_reporte) is not true then
    raise exception 'No gestionas este reporte.';
  end if;
  return query
  select m.id, p.nombres || ' ' || p.apellidos, m.instruccion, m.vigente_hasta, m.cumplida_at, m.creado_at
    from reporte_medidas m
    join personas p on p.id = m.para_persona_id
   where m.reporte_id = p_reporte
   order by m.creado_at, m.id;
end;
$fn$;

-- Lo que le encargaron a la líder que llama. Sin el caso: ni su código, ni
-- quién, ni por qué (plan, decisión 16).
create or replace function fn_mis_medidas()
returns table (id uuid, instruccion text, vigente_hasta date, cumplida_at timestamptz, creado_at timestamptz)
language sql
stable
security definer
set search_path = public
as $fn$
  select m.id, m.instruccion, m.vigente_hasta, m.cumplida_at, m.creado_at
    from reporte_medidas m
   where m.para_persona_id = fn_persona_actual_id()
   order by m.cumplida_at nulls first, m.creado_at desc, m.id;
$fn$;

-- A quién se le puede encargar una medida de este caso: líderes activas que
-- no están mencionadas. Solo DO o la Gerencia pregunta esto.
create or replace function fn_reporte_lideres(p_reporte uuid)
returns table (id uuid, nombre text, sede_codigo text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if coalesce(fn_reporte_motivo(p_reporte), '') not in ('do', 'gerencia') then
    raise exception 'Solo Desarrollo Organizacional dicta medidas de protección.';
  end if;
  return query
  select p.id, p.nombres || ' ' || p.apellidos, s.codigo
    from personas p
    left join sedes s on s.id = p.sede_base_id
   where p.estado = 'activo' and p.rol = 'supervisor_sede'
     and not exists (select 1 from reporte_personas rp where rp.reporte_id = p_reporte and rp.persona_id = p.id)
   order by s.codigo, p.nombres, p.id;
end;
$fn$;

-- Los expedientes que se pueden enlazar: los de las personas INVOLUCRADAS.
create or replace function fn_reporte_expedientes(p_reporte uuid)
returns table (id uuid, persona text, nivel text, estado text, correlativo text, creado_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if coalesce(fn_reporte_motivo(p_reporte), '') not in ('do', 'gerencia') then
    raise exception 'Solo Desarrollo Organizacional enlaza un reporte con disciplina.';
  end if;
  return query
  select x.id, p.nombres || ' ' || p.apellidos, x.nivel, x.estado, x.correlativo, x.creado_at
    from expediente_disciplinario x
    join personas p on p.id = x.persona_id
   where x.persona_id in (select rp.persona_id from reporte_personas rp
                           where rp.reporte_id = p_reporte and rp.papel = 'involucrada')
     and x.estado <> 'anulado'
   order by x.creado_at desc, x.id;
end;
$fn$;

-- Quién investiga en cada sede. Es información publicada (48.6).
create or replace function fn_organos_titulo_x()
returns table (id uuid, sede_codigo text, sede_nombre text, persona_id uuid, nombre text,
               papel text, desde date, hasta date, acta text)
language sql
stable
security definer
set search_path = public
as $fn$
  select o.id, s.codigo, s.nombre, o.persona_id, p.nombres || ' ' || p.apellidos,
         o.papel, o.desde, o.hasta, o.acta
    from organos_titulo_x o
    join sedes s on s.id = o.sede_id
    join personas p on p.id = o.persona_id
   where fn_persona_actual_id() is not null
   order by s.codigo, o.hasta nulls first, case o.papel when 'delegada' then 1 when 'suplente' then 2 else 3 end, o.desde desc, o.id;
$fn$;


-- ── 12 · Quién investiga en cada sede ───────────────────────────────────────
-- La designación consta en acta (48.3): sin acta no se registra.
create or replace function fn_organo_titulo_x_guardar(
  p_sede uuid, p_persona uuid, p_papel text, p_desde date, p_acta text)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo uuid := fn_persona_actual_id();
  v_id uuid;
begin
  -- Null-safe: con `not (a or b)`, un rol null dejaría pasar a cualquiera.
  if v_yo is null
     or (fn_rol_actual() is distinct from 'lider_do' and v_yo is distinct from fn_gerencia_general_id()) then
    raise exception 'Solo Desarrollo Organizacional o la Gerencia General registran a quien investiga.';
  end if;
  if not exists (select 1 from sedes where id = p_sede and activa) then
    raise exception 'Sede inválida o inactiva.';
  end if;
  if not exists (select 1 from personas where id = p_persona and estado = 'activo') then
    raise exception 'Esa persona no está activa.';
  end if;
  if p_papel is null or p_papel not in ('delegada', 'suplente', 'designada') then
    raise exception 'Papel desconocido.';
  end if;
  if p_desde is null then
    raise exception 'Falta la fecha desde la que ejerce.';
  end if;
  if p_acta is null or length(trim(p_acta)) < 3 then
    raise exception 'Indica el acta: la designación o la elección constan por escrito (48.3).';
  end if;
  -- 48.3: quien investiga no puede ser quien sanciona.
  if exists (select 1 from personas where id = p_persona and rol = 'lider_do') then
    raise exception 'Quien investiga no puede ser quien decide (48.3): Desarrollo Organizacional no se designa a sí misma.';
  end if;

  insert into organos_titulo_x (sede_id, persona_id, papel, desde, acta)
  values (p_sede, p_persona, p_papel, p_desde, trim(p_acta))
  returning organos_titulo_x.id into v_id;

  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona, 'organos_titulo_x', null,
          p_papel || ' en ' || (select codigo from sedes where id = p_sede) || ' desde ' || p_desde,
          trim(p_acta), v_yo);
  return v_id;
end;
$fn$;

create or replace function fn_organo_titulo_x_cerrar(p_id uuid, p_hasta date, p_motivo text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_yo uuid := fn_persona_actual_id();
  v_o  record;
begin
  if v_yo is null
     or (fn_rol_actual() is distinct from 'lider_do' and v_yo is distinct from fn_gerencia_general_id()) then
    raise exception 'Solo Desarrollo Organizacional o la Gerencia General cierran un nombramiento.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Explica por qué termina.';
  end if;
  select * into v_o from organos_titulo_x where id = p_id;
  if not found then
    raise exception 'Ese nombramiento no existe.';
  end if;
  if p_hasta is null or p_hasta < v_o.desde then
    raise exception 'La fecha de término no puede ser anterior al inicio.';
  end if;
  update organos_titulo_x set hasta = p_hasta where id = p_id and hasta is null;
  if not found then
    raise exception 'Ese nombramiento ya está cerrado.';
  end if;
  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (v_o.persona_id, 'organos_titulo_x', v_o.papel || ' desde ' || v_o.desde, 'hasta ' || p_hasta, trim(p_motivo), v_yo);
end;
$fn$;


-- ── 13 · Permisos de las funciones ──────────────────────────────────────────
grant execute on function
  fn_reporte_crear(text, text, uuid, date, text, uuid[], uuid[], text, boolean, boolean, text, text),
  fn_reporte_mensaje(uuid, text, boolean, date),
  fn_reporte_en_revision(uuid),
  fn_reporte_anotar_accion(uuid, text, text),
  fn_reporte_reclasificar(uuid, text, text),
  fn_reporte_escalar(uuid, text),
  fn_reporte_cerrar(uuid, text, text),
  fn_reporte_derivar(uuid, uuid),
  fn_reporte_medida(uuid, uuid, text, date),
  fn_reporte_medida_cumplida(uuid),
  fn_reporte_adjuntar(uuid, text, boolean),
  fn_reporte_abrir(uuid),
  fn_reporte_plazo_cumplir(uuid, text, text),
  fn_reporte_indicios_delito(uuid, text),
  fn_reportes_bandeja(),
  fn_reportes_mios(),
  fn_reporte_padron(),
  fn_reporte_detalle(uuid),
  fn_reporte_hilo(uuid),
  fn_reporte_adjuntos(uuid),
  fn_ve_casos(),
  fn_reporte_plazos(uuid),
  fn_reporte_personas(uuid),
  fn_reporte_eventos(uuid),
  fn_reporte_medidas(uuid),
  fn_mis_medidas(),
  fn_reporte_lideres(uuid),
  fn_reporte_expedientes(uuid),
  fn_organos_titulo_x(),
  fn_organo_titulo_x_guardar(uuid, uuid, text, date, text),
  fn_organo_titulo_x_cerrar(uuid, date, text)
to authenticated;

revoke execute on function
  fn_reporte_crear(text, text, uuid, date, text, uuid[], uuid[], text, boolean, boolean, text, text),
  fn_reporte_mensaje(uuid, text, boolean, date),
  fn_reporte_en_revision(uuid),
  fn_reporte_anotar_accion(uuid, text, text),
  fn_reporte_reclasificar(uuid, text, text),
  fn_reporte_escalar(uuid, text),
  fn_reporte_cerrar(uuid, text, text),
  fn_reporte_derivar(uuid, uuid),
  fn_reporte_medida(uuid, uuid, text, date),
  fn_reporte_medida_cumplida(uuid),
  fn_reporte_adjuntar(uuid, text, boolean),
  fn_reporte_abrir(uuid),
  fn_reporte_plazo_cumplir(uuid, text, text),
  fn_reporte_indicios_delito(uuid, text),
  fn_reportes_bandeja(),
  fn_reportes_mios(),
  fn_reporte_padron(),
  fn_reporte_detalle(uuid),
  fn_reporte_hilo(uuid),
  fn_reporte_adjuntos(uuid),
  fn_ve_casos(),
  fn_reporte_plazos(uuid),
  fn_reporte_personas(uuid),
  fn_reporte_eventos(uuid),
  fn_reporte_medidas(uuid),
  fn_mis_medidas(),
  fn_reporte_lideres(uuid),
  fn_reporte_expedientes(uuid),
  fn_organos_titulo_x(),
  fn_organo_titulo_x_guardar(uuid, uuid, text, date, text),
  fn_organo_titulo_x_cerrar(uuid, date, text)
from public, anon;

-- Las piezas internas no las llama nadie desde afuera: abrirían plazos o
-- escribirían eventos sin pasar por los guardianes.
revoke execute on function
  fn_reporte_evento(uuid, text, jsonb),
  fn_reporte_plazo_abrir(uuid, text, timestamptz, timestamptz),
  fn_reporte_plazos_de_via(uuid),
  fn_reporte_hay_quien(uuid, text),
  fn_reporte_gestora_inicial(uuid),
  fn_reporte_plazos_guardian(),
  fn_reporte_medidas_guardian(),
  fn_organos_titulo_x_guardian()
from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (488, 'los_reportes_se_escriben_y_sus_plazos_corren')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'reporte_plazos') as tabla_plazos,
  (select count(*) from pg_proc where proname in (
     'fn_reporte_crear','fn_reporte_mensaje','fn_reporte_en_revision','fn_reporte_anotar_accion',
     'fn_reporte_reclasificar','fn_reporte_escalar','fn_reporte_cerrar','fn_reporte_derivar',
     'fn_reporte_medida','fn_reporte_medida_cumplida','fn_reporte_adjuntar','fn_reporte_abrir',
     'fn_reporte_plazo_cumplir','fn_reporte_indicios_delito','fn_reportes_bandeja','fn_reportes_mios',
     'fn_organo_titulo_x_guardar','fn_organo_titulo_x_cerrar','fn_reporte_padron','fn_reporte_detalle',
     'fn_reporte_hilo','fn_reporte_adjuntos','fn_ve_casos','fn_reporte_plazos','fn_reporte_personas',
     'fn_reporte_eventos','fn_reporte_medidas','fn_mis_medidas','fn_reporte_lideres','fn_reporte_expedientes',
     'fn_organos_titulo_x')) as funciones_de_31,
  (select count(*) from migraciones_aplicadas where numero = 483) as la_0483_esta,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 488) as registro;
