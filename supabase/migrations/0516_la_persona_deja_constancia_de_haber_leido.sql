-- ============================================================================
-- 0516 — La persona deja constancia de haber leído lo que se le entregó
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que quien recibió un documento disciplinario EN PAPEL pueda dejar, desde
-- «Lo mío», una constancia de que lo abrió y lo leyó, con su fecha y hora. Y
-- que la pantalla tenga de dónde armar la lista de lo suyo: `fn_mi_disciplina`.
--
--   1. `lecturas_memo`: una fila por documento, con CUÁNDO se abrió y CUÁNDO se
--      leyó. Solo se agrega: lo que se leyó, leído queda.
--   2. `fn_registrar_apertura_memo`: se llama al abrir el documento. Es lo que
--      hace que «Lo leí» valga algo: sin apertura registrada, no se puede dar.
--   3. `fn_marcar_memo_leido`: «Lo leí». Pide la apertura previa.
--   4. `fn_mi_disciplina`: la lista de la persona, con todo lo que la pestaña
--      necesita para dibujar cada tarjeta, sin el relato (ese se lee al abrir).
--
-- ── DE QUIÉN ES LA DECISIÓN ─────────────────────────────────────────────────
--
-- De la usuaria, el 2026-10-06, mirando el prototipo
-- (`docs/disciplina-mio-prototipo-2026-10-06.html`):
--
--   · «Que tenga que leer y que tenga que dejar una constancia de lectura».
--   · RECIBIR YA ES LA CONSTANCIA cuando el memo se envía a su Info (0486): ese
--     clic es la entrega y ya dice que lo abrió. La constancia nueva es solo
--     para lo entregado en papel, donde hasta hoy no quedaba nada de que lo
--     hubiera leído. Dos clics por lo mismo, además, podrían confundirse con
--     la entrega y mover desde cuándo corren los doce meses (RIT 56.1).
--   · «Lo leí» se activa DESPUÉS de abrir el documento: lo básico se ve en la
--     lista y el detalle va detrás de «Leer», porque cualquiera puede mirar la
--     pantalla de reojo y el relato de una sanción no es para eso.
--
-- ── POR QUÉ LA APERTURA SE GUARDA EN LA BASE Y NO SOLO EN LA PANTALLA ───────
--
-- Si «Lo leí» solo se habilitara en la pantalla, bastaría llamar a la función
-- sin abrir nada, y la constancia diría «leyó» sobre algo que nunca se abrió:
-- una prueba que no prueba. Así que `fn_marcar_memo_leido` exige que exista la
-- apertura, y el esquema exige que la lectura no sea anterior a ella
-- (`chk_leyo_despues_de_abrir`). La constancia dice «abrió el 6 a las 10:41 y
-- confirmó que lo leyó a las 10:42».
--
-- LEER NO ES ACEPTAR. La constancia no cambia el estado del documento, ni su
-- fecha de entrega, ni desde cuándo cuenta como antecedente. Es un registro
-- aparte, y la pantalla lo dice en la propia constancia.
--
-- ── ESTADOS QUE NO PUEDEN EXISTIR (los hace imposibles el esquema) ──────────
--
--   · Leído sin apertura previa, o leído antes de abrir.
--   · Dos constancias del mismo documento (la clave es el documento).
--   · Una constancia que se edita o se borra una vez dada (trigger).
--   · Constancia sobre el documento de otra persona (la función solo mira los
--     de quien tiene la sesión).
--
-- ── QUÉ NO HACE ─────────────────────────────────────────────────────────────
--
--   · No se pide constancia de lectura de lo recibido por Info (lo cubre el
--     «Recibir») ni de las cartas de imputación y despido, que se entregan en
--     físico o por vía notarial y no se abren en pantalla (0486).
--   · No exige leer para nada: no bloquea ninguna otra pantalla. Un aviso que
--     secuestra «Lo mío» bloquearía a quien entra a ver su horario un domingo.
--
-- ── NÚMEROS (antes de decidir el índice) ────────────────────────────────────
--
-- ~30 personas, de 0 a ~10 documentos entregados cada una en tres años: menos
-- de 300 filas. La clave primaria alcanza; no hace falta otro índice.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que la 0514 está pegada (`faltas_rotulos`) — verificado en producción el
--     2026-10-06.
--   · Que `expediente_disciplinario.medio_entrega = 'digital'` es la entrega
--     por Info (0486) y que `firma_sancionado_confirmada_at` es la firma que la
--     persona estampa sobre su propio memo (0408).
--
-- No reescribe ninguna función existente: no hay md5 de partida que declarar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop function if exists fn_mi_disciplina();
--   drop function if exists fn_marcar_memo_leido(uuid);
--   drop function if exists fn_registrar_apertura_memo(uuid);
--   drop table if exists lecturas_memo;
-- Si ya hay constancias, la tabla se conserva: son constancias de personas
-- reales. Sin las funciones, la pantalla deja de ofrecerlas y no se rompe.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · La constancia
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists lecturas_memo (
  expediente_id uuid primary key references expediente_disciplinario(id),
  abierto_at    timestamptz not null default now(),
  leido_at      timestamptz,
  -- No hay columna de persona: sería una segunda forma de decir lo que el
  -- documento ya dice, y dos copias se separan solas. De quién es, lo dice
  -- `expediente_disciplinario.persona_id`.
  constraint chk_leyo_despues_de_abrir check (leido_at is null or leido_at >= abierto_at)
);

comment on table lecturas_memo is
  'Constancia de que la persona abrió (abierto_at) y leyó (leido_at) un documento disciplinario entregado en papel. Solo se agrega; no cambia el estado ni la fecha de entrega del documento: leer no es aceptar.';

alter table lecturas_memo enable row level security;

-- Sin políticas de escritura: solo las funciones de abajo. Lectura: la persona
-- ve la suya; DO y Gerencia todas; la líder, las de integrantes de su sede (la
-- misma regla que `exp_select_supervisor`, 0510) para saber a quién hay que
-- recordarle.
drop policy if exists lecturas_memo_select on lecturas_memo;
create policy lecturas_memo_select on lecturas_memo
  for select to authenticated using (
    fn_es_admin_o_lider()
    or exists (select 1 from expediente_disciplinario d
                where d.id = lecturas_memo.expediente_id
                  and d.persona_id = fn_persona_actual_id())
    or (fn_rol_actual() = 'supervisor_sede'
        and exists (select 1 from expediente_disciplinario d
                      join personas p on p.id = d.persona_id
                     where d.id = lecturas_memo.expediente_id
                       and p.sede_base_id = fn_sede_actual_persona()
                       and p.rol = 'integrante')));
grant select on lecturas_memo to authenticated;

-- Lo dado, dado: una constancia no se edita ni se borra. La única escritura
-- posible sobre una fila existente es poner `leido_at` UNA vez.
create or replace function fn_lecturas_memo_solo_se_agrega()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una constancia de lectura no se borra.';
  end if;
  if old.leido_at is not null then
    raise exception 'Esta constancia ya está dada y no se modifica.';
  end if;
  if new.expediente_id is distinct from old.expediente_id or new.abierto_at is distinct from old.abierto_at then
    raise exception 'De una constancia solo se puede dar la lectura; no se cambia el documento ni cuándo se abrió.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lecturas_memo_solo_se_agrega on lecturas_memo;
create trigger trg_lecturas_memo_solo_se_agrega
  before update or delete on lecturas_memo
  for each row execute function fn_lecturas_memo_solo_se_agrega();


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Abrir y leer
-- ════════════════════════════════════════════════════════════════════════════
-- Se llama al abrir el documento. Silenciosa a propósito con lo que no admite
-- constancia: la pantalla la llama siempre y no tiene que saber cuál sí.
create or replace function fn_registrar_apertura_memo(p_id uuid)
returns void language plpgsql volatile security definer set search_path = public as $$
declare
  v_yo uuid := fn_persona_actual_id();
  d    expediente_disciplinario%rowtype;
begin
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select * into d from expediente_disciplinario where id = p_id and persona_id = v_yo;
  if not found then raise exception 'No se encontró ese documento.'; end if;

  -- Los mismos que abre `fn_mi_memo` (0486): los tres niveles que se leen en
  -- pantalla, entregados o enviados a su Info.
  if d.nivel not in ('verbal', 'amonestacion', 'suspension') then return; end if;
  if not (d.estado = 'entregado' or (d.estado = 'firmado' and d.enviado_a_info_at is not null)) then return; end if;

  -- La PRIMERA apertura es la que cuenta: abrirlo otra vez no la mueve.
  insert into lecturas_memo (expediente_id) values (p_id) on conflict (expediente_id) do nothing;
end;
$$;

grant execute on function fn_registrar_apertura_memo(uuid) to authenticated;
revoke execute on function fn_registrar_apertura_memo(uuid) from public, anon;

create or replace function fn_marcar_memo_leido(p_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = public as $$
declare
  v_yo uuid := fn_persona_actual_id();
  d    expediente_disciplinario%rowtype;
  l    lecturas_memo%rowtype;
begin
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select * into d from expediente_disciplinario where id = p_id and persona_id = v_yo;
  if not found then raise exception 'No se encontró ese documento.'; end if;

  if d.nivel not in ('verbal', 'amonestacion', 'suspension') then
    raise exception 'Este documento se entrega en físico o por vía notarial: no admite constancia de lectura aquí.';
  end if;
  if d.estado <> 'entregado' then
    raise exception 'Todavía no te lo entregaron. Si te lo enviaron a tu Info, recibirlo es tu constancia.';
  end if;
  if d.medio_entrega = 'digital' then
    raise exception 'Lo recibiste por tu Info: esa confirmación ya es tu constancia.';
  end if;

  -- `for update`: si el mismo clic llega dos veces a la vez, el segundo espera
  -- al primero y encuentra la constancia dada, en vez de chocar con el trigger.
  select * into l from lecturas_memo where expediente_id = p_id for update;
  if not found then
    raise exception 'Ábrelo primero: la constancia es de haber leído el documento.';
  end if;
  if l.leido_at is not null then return l.leido_at; end if;

  update lecturas_memo set leido_at = now() where expediente_id = p_id
  returning leido_at into l.leido_at;
  return l.leido_at;
end;
$$;

grant execute on function fn_marcar_memo_leido(uuid) to authenticated;
revoke execute on function fn_marcar_memo_leido(uuid) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Lo que la persona ve de su disciplina
-- ════════════════════════════════════════════════════════════════════════════
-- Todo lo que la pestaña necesita para dibujar cada tarjeta, SIN el relato: ese
-- se lee al abrir el documento (`fn_mi_memo`). Lo que se ve de reojo es el
-- tipo, la fecha y la falta.
--
-- «Vigente» se mide como `fn_tardanza_escalon_al` (0311), la función hermana:
-- entregado y dentro de los doce meses. Dos mitades del sistema contestando
-- distinto a «¿esto sigue pesando?» es el defecto que la 0237 vino a cerrar.
-- La llamada verbal no es antecedente (54.2): no tiene vigencia que mostrar.
create or replace function fn_mi_disciplina()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_yo uuid := fn_persona_actual_id();
begin
  if v_yo is null then return jsonb_build_object('documentos', '[]'::jsonb); end if;

  return jsonb_build_object('documentos', (
    select coalesce(jsonb_agg(f.j order by f.orden desc, f.id), '[]'::jsonb)
      from (
        select d.id,
               coalesce(d.entregado_at, d.enviado_a_info_at) as orden,
               jsonb_build_object(
                 'id', d.id,
                 'correlativo', d.correlativo,
                 'nivel', d.nivel,
                 'tipo_causal', d.tipo_causal,
                 -- Enviado a su Info y sin recibir, o ya entregado.
                 'estado', case when d.estado = 'entregado' then 'entregado' else 'por_recibir' end,
                 'medio_entrega', d.medio_entrega,
                 'entregado_at', d.entregado_at,
                 'enviado_a_info_at', d.enviado_a_info_at,
                 'periodo_desde', d.periodo_desde,
                 'periodo_hasta', d.periodo_hasta,
                 'falta', (select jsonb_build_object('numeral', c.numeral, 'literal', c.literal,
                                                     'rotulo', r.rotulo, 'gravedad', c.gravedad)
                             from faltas_catalogo c
                             left join faltas_rotulos r using (rit_version, numeral, literal)
                            where c.rit_version = d.falta_rit_version
                              and c.numeral = d.falta_numeral and c.literal = d.falta_literal),
                 'abierto_at', l.abierto_at,
                 'leido_at', l.leido_at,
                 'firma_confirmada_at', d.firma_sancionado_confirmada_at,
                 'rechazo_firma_at', d.sancionado_rechazo_firma_at,
                 -- Pide «Lo leí» lo entregado en papel, de los tres niveles que
                 -- se leen en pantalla, que todavía pesa, y que ella no firmó
                 -- ya (firmar es un acto deliberado con su propia fecha).
                 'requiere_lectura', (d.estado = 'entregado'
                                      and d.medio_entrega is distinct from 'digital'
                                      and d.nivel in ('verbal', 'amonestacion', 'suspension')
                                      and d.firma_sancionado_confirmada_at is null
                                      and d.entregado_at >= now() - interval '12 months'),
                 'vigente_hasta', case when d.estado = 'entregado' and d.nivel in ('amonestacion', 'suspension')
                                       then ((d.entregado_at at time zone 'America/Lima')::date + interval '12 months')::date end,
                 'cancelado', (d.estado = 'entregado' and d.nivel in ('amonestacion', 'suspension')
                               and d.entregado_at < now() - interval '12 months')
               ) as j
          from expediente_disciplinario d
          left join lecturas_memo l on l.expediente_id = d.id
         where d.persona_id = v_yo
           and (d.estado = 'entregado' or (d.estado = 'firmado' and d.enviado_a_info_at is not null))
      ) f));
end;
$$;

grant execute on function fn_mi_disciplina() to authenticated;
revoke execute on function fn_mi_disciplina() from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (516, 'la_persona_deja_constancia_de_haber_leido')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
