-- ============================================================================
-- 0581_los_cargos_llegan_a_su_info.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que la comunicación de cargos del RIT 55.2 llegue a la colaboradora POR EL
--   SISTEMA, a su Info en «Lo mío», sin papel:
--     · la ve desde el momento en que se le comunican los cargos;
--     · confirma que la recibió con un clic, después de abrirla;
--     · si quiere, escribe ahí su descargo mientras corre el plazo;
--     · quien tramita ve en Disciplina si la abrió, si la recibió y qué dijo.
--   Y reabre, UNA sola vez, el plazo de los borradores cuyos cargos se
--   «comunicaron» antes de que este camino existiera: a esas personas nunca les
--   llegó nada por el sistema.
--
-- POR QUÉ, CON EL CASO QUE LO DISPARÓ
--   El 2026-11-02 una amonestación por conducta quedó en borrador —correcto:
--   desde la 0566 el 55.2 no deja firmar antes de que venza el plazo de
--   descargo—, y a la colaboradora se le entregó el BORRADOR DEL MEMO para que
--   lo firmara. Ella no veía nada en su Info porque Dynamic no tenía cómo
--   mostrarle los cargos: `fn_mi_disciplina` (0516) solo entrega documentos ya
--   firmados y enviados, y «Comunicar cargos» (0212/0228) guardaba una fecha y
--   le dejaba a la líder «el documento lo entregas tú».
--
--   Felipe decidió el 2026-11-03: «no usaremos hojas o imprimir, tiene que verlo
--   en su sistema» · «solo confirmar que lo recibió» · «para los 2 borradores
--   actuales y los futuros».
--
-- DE QUIÉN ES CADA DECISIÓN
--   · El plazo de descargo CORRE DESDE QUE SE COMUNICAN los cargos, no desde
--     que ella confirma (Felipe, 2026-11-03, eligiendo entre las dos con el
--     riesgo dicho: si no entra a Dynamic en dos días hábiles, el plazo vence
--     sin que lo sepa). Por eso esta migración NO toca
--     `fn_expediente_comunicar_cargos`: comunicar ya fija el plazo desde ahora,
--     y desde ahora también la hace visible en su Info.
--   · Lo que la persona hace es CONFIRMAR QUE LO RECIBIÓ. Firmar no se le pide.
--     La confirmación es constancia, no requisito: no cambia el plazo ni
--     destraba nada. Lo que sí deja es la prueba de que le llegó, que con el
--     plazo corriendo desde el envío es la que importa si alguien lo discute.
--   · El descargo escrito es opcional (Felipe, 2026-11-03: «sí, lo escribe
--     ahí»). Lo que se presenta, presentado queda: no se edita ni se borra.
--
-- ── QUÉ HACE ────────────────────────────────────────────────────────────────
--   1. `recepciones_cargos`: cuándo ABRIÓ los cargos y cuándo CONFIRMÓ que los
--      recibió. El molde de `lecturas_memo` (0516): la confirmación exige la
--      apertura previa, y una constancia dada no se toca.
--   2. `descargos_presentados`: lo que escribió, con fecha y hora. Solo se
--      agrega.
--   3. `cargos_recomunicados`: el rastro del reinicio del punto 7 —qué fechas
--      tenía cada borrador antes—. También es lo que lo hace idempotente.
--   4. `fn_cargos_detalle(id)`: TODO lo que dice la comunicación de cargos, en
--      un solo sitio, para las dos pantallas que la muestran —la Info de ella y
--      Disciplina—. Un documento legal armado dos veces termina diciendo dos
--      cosas. Si quien la abre es ella, registra la apertura.
--   5. `fn_mis_cargos()`: la lista de ella, para su Info y su Resumen.
--   6. `fn_recibir_cargos(id)` y `fn_presentar_descargo(id, texto)`.
--   7. El reinicio único de los borradores ya comunicados (ver abajo).
--
-- ── LOS ANTECEDENTES SE ELIGEN COMO LOS ELIGE LA BASE ───────────────────────
--   La primera versión de la comunicación (PR #641) los buscaba en la pantalla
--   por causal y estado, y podía citar como «antecedente vigente» una llamada
--   verbal (54.2: «no produce efecto agravante»), una imputación, o en
--   conducta una falta distinta (56.5: «Solo agravan los antecedentes que
--   guarden relación con la conducta que se evalúa»). Aquí se copia el criterio
--   de la función hermana, `fn_conducta_antecedentes` (0510): entregados, de
--   amonestación o suspensión, en los doce meses anteriores al hecho, y en
--   conducta del mismo numeral y literal.
--
-- ── EL REINICIO ÚNICO (punto 7) ─────────────────────────────────────────────
--   Alcanza a los borradores de amonestación o suspensión con cargos
--   comunicados y SIN descargo valorado al pegar esta migración. Hoy son los
--   dos de la colaboradora del caso del 2026-11-02, pero la condición no los
--   nombra: no hay datos personales en el repositorio, y cualquier otro en la
--   misma situación tampoco recibió nada por el sistema.
--   Su plazo vuelve a empezar AHORA, con los mismos dos días hábiles. Es siempre
--   a favor de la persona —nunca acorta un plazo—, y las fechas viejas quedan en
--   `cargos_recomunicados` y en `observacion` con la marca [RECOMUNICADO …].
--   No se toca el memo: hechos, relato y falta citada siguen como los dejó la
--   líder. No hay que volver a registrar nada.
--   Repegar no lo repite: un borrador ya reiniciado está en
--   `cargos_recomunicados`, y uno comunicado DESPUÉS de la primera pegada queda
--   fuera por fecha.
--
-- ── QUÉ NO HACE ─────────────────────────────────────────────────────────────
--   · No reescribe ninguna función existente: no hay md5 de partida que pedir.
--   · No cambia quién puede comunicar, valorar ni firmar, ni cuándo.
--   · No avisa por correo ni por mensaje: la pantalla ofrece un aviso para
--     copiar. Si ella no entra a Dynamic, el plazo corre igual (decisión de
--     arriba), y la pantalla de Disciplina dice que todavía no los abrió.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--   · Que la 0516 está pegada (`lecturas_memo`, molde de esto) y la 0514
--     (`faltas_rotulos`). Se comprueba abajo.
--   · `exp_select_propia` (0056) ya le deja a la persona LEER sus propias filas
--     del expediente, borradores incluidos. La pantalla nunca los pidió; esta
--     migración no abre nada nuevo de lectura sobre esa tabla.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists fn_presentar_descargo(uuid, text);
--   drop function if exists fn_recibir_cargos(uuid);
--   drop function if exists fn_mis_cargos();
--   drop function if exists fn_cargos_detalle(uuid);
--   drop function if exists fn_cargos_reabrir_plazo_sin_info(timestamptz);
--   Las tablas se conservan si tienen filas: son constancias y descargos de
--   personas reales. El reinicio del plazo no se deshace: deshacerlo acortaría
--   el plazo de alguien a quien ya se le comunicó por el sistema.
-- ============================================================================

do $$
begin
  if not exists (select 1 from migraciones_aplicadas where numero = 516)
     or not exists (select 1 from migraciones_aplicadas where numero = 514) then
    raise exception 'Faltan la 0514 o la 0516 (los rótulos de faltas y la constancia de lectura). Pégalas primero.';
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · La constancia de que le llegaron
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists recepciones_cargos (
  expediente_id uuid primary key references expediente_disciplinario(id),
  abierto_at    timestamptz not null default now(),
  recibido_at   timestamptz,
  constraint chk_recibio_despues_de_abrir check (recibido_at is null or recibido_at >= abierto_at)
);

comment on table recepciones_cargos is
  'Cuándo la persona abrió la comunicación de cargos en su Info (abierto_at) y cuándo confirmó que la recibió (recibido_at). Constancia, no requisito: el plazo de descargo corre desde que se comunican (0581). Solo se agrega.';

alter table recepciones_cargos enable row level security;

-- La misma lectura que `lecturas_memo` (0516): ella la suya; DO y Gerencia
-- todas; la líder, las de integrantes de su sede.
drop policy if exists recepciones_cargos_select on recepciones_cargos;
create policy recepciones_cargos_select on recepciones_cargos
  for select to authenticated using (
    fn_es_admin_o_lider()
    or exists (select 1 from expediente_disciplinario d
                where d.id = recepciones_cargos.expediente_id
                  and d.persona_id = fn_persona_actual_id())
    or (fn_rol_actual() = 'supervisor_sede'
        and exists (select 1 from expediente_disciplinario d
                      join personas p on p.id = d.persona_id
                     where d.id = recepciones_cargos.expediente_id
                       and p.sede_base_id = fn_sede_actual_persona()
                       and p.rol = 'integrante')));
grant select on recepciones_cargos to authenticated;

create or replace function fn_recepciones_cargos_solo_se_agrega()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una constancia de recepción no se borra.';
  end if;
  if old.recibido_at is not null then
    raise exception 'Esta constancia ya está dada y no se modifica.';
  end if;
  if new.expediente_id is distinct from old.expediente_id or new.abierto_at is distinct from old.abierto_at then
    raise exception 'De esta constancia solo se puede dar la recepción; no se cambia el documento ni cuándo se abrió.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_recepciones_cargos_solo_se_agrega on recepciones_cargos;
create trigger trg_recepciones_cargos_solo_se_agrega
  before update or delete on recepciones_cargos
  for each row execute function fn_recepciones_cargos_solo_se_agrega();


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Su descargo, escrito en el sistema
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists descargos_presentados (
  id            uuid primary key default gen_random_uuid(),
  expediente_id uuid not null references expediente_disciplinario(id),
  texto         text not null check (length(btrim(texto)) between 10 and 4000),
  presentado_at timestamptz not null default now()
);

create index if not exists ix_descargos_presentados_expediente
  on descargos_presentados (expediente_id, presentado_at);

comment on table descargos_presentados is
  'El descargo escrito que la persona presenta desde su Info mientras corre el plazo del RIT 55.2 (0581). Se puede presentar más de uno; ninguno se edita ni se borra.';

alter table descargos_presentados enable row level security;

drop policy if exists descargos_presentados_select on descargos_presentados;
create policy descargos_presentados_select on descargos_presentados
  for select to authenticated using (
    fn_es_admin_o_lider()
    or exists (select 1 from expediente_disciplinario d
                where d.id = descargos_presentados.expediente_id
                  and d.persona_id = fn_persona_actual_id())
    or (fn_rol_actual() = 'supervisor_sede'
        and exists (select 1 from expediente_disciplinario d
                      join personas p on p.id = d.persona_id
                     where d.id = descargos_presentados.expediente_id
                       and p.sede_base_id = fn_sede_actual_persona()
                       and p.rol = 'integrante')));
grant select on descargos_presentados to authenticated;

create or replace function fn_descargos_presentados_inmutables()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'Un descargo presentado no se modifica ni se borra. Si quieres agregar algo, presenta otro.';
end;
$$;

drop trigger if exists trg_descargos_presentados_inmutables on descargos_presentados;
create trigger trg_descargos_presentados_inmutables
  before update or delete on descargos_presentados
  for each row execute function fn_descargos_presentados_inmutables();


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · El rastro del reinicio único
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists cargos_recomunicados (
  expediente_id        uuid primary key references expediente_disciplinario(id),
  antes_comunicados_at timestamptz not null,
  antes_vence_at       timestamptz not null,
  recomunicado_at      timestamptz not null default now(),
  motivo               text not null
);

comment on table cargos_recomunicados is
  'Borradores a los que la 0581 les reabrió el plazo de descargo, una sola vez, porque sus cargos se comunicaron antes de que pudieran llegar a la Info de la persona. Guarda las fechas que tenían.';

alter table cargos_recomunicados enable row level security;
drop policy if exists cargos_recomunicados_select on cargos_recomunicados;
create policy cargos_recomunicados_select on cargos_recomunicados
  for select to authenticated using (fn_es_admin_o_lider());
grant select on cargos_recomunicados to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 4 · La comunicación de cargos, armada en un solo sitio
-- ════════════════════════════════════════════════════════════════════════════
-- La leen DOS pantallas: la Info de la persona y Disciplina. Volátil porque, si
-- quien la abre es la persona, deja la apertura registrada: es lo que hace que
-- su «Confirmo que los recibí» valga algo.
create or replace function fn_cargos_detalle(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_yo   uuid := fn_persona_actual_id();
  d      expediente_disciplinario%rowtype;
  v_ella boolean;
  v_ts   timestamptz;
begin
  select * into d from expediente_disciplinario where id = p_id;
  if not found then raise exception 'No se encontró ese documento.'; end if;

  v_ella := d.persona_id = v_yo;

  if v_ella then
    -- Ella ve los cargos desde que se le comunican. Antes, o de un documento
    -- anulado, no hay nada que mostrarle: para ella no existen.
    if d.cargos_comunicados_at is null or d.estado = 'anulado'
       or d.nivel not in ('amonestacion', 'suspension') then
      raise exception 'No se encontró ese documento.';
    end if;
  elsif not (
    coalesce(fn_es_admin_o_lider(), false)
    or coalesce(fn_rol_actual() = 'supervisor_sede'
                and exists (select 1 from personas p
                             where p.id = d.persona_id
                               and p.sede_base_id = fn_sede_actual_persona()
                               and p.rol = 'integrante'), false)
  ) then
    raise exception 'Sin permiso para ver este documento.';
  end if;

  if v_ella then
    -- La PRIMERA apertura es la que cuenta.
    insert into recepciones_cargos (expediente_id) values (p_id) on conflict (expediente_id) do nothing;
  end if;

  -- Los antecedentes se cuentan hasta el cierre del día del hecho, como en
  -- `fn_conducta_antecedentes` (0510).
  v_ts := fn_cierre_lima(coalesce(d.periodo_hasta, d.periodo_desde, fn_hoy_lima()));

  return jsonb_build_object(
    'id', d.id,
    'tipo_causal', d.tipo_causal,
    'nivel', d.nivel,
    'estado', d.estado,
    'periodo_desde', d.periodo_desde,
    'periodo_hasta', d.periodo_hasta,
    'hechos', coalesce(d.hechos, '[]'::jsonb),
    'suspension_dias', d.suspension_dias,
    'cargos_comunicados_at', d.cargos_comunicados_at,
    'descargo_vence_at', d.descargo_vence_at,
    'plazo_vigente', d.descargo_vence_at is not null and now() <= d.descargo_vence_at,
    'conocido_el', d.conocido_el,
    'falta', (select jsonb_build_object('numeral', c.numeral, 'literal', c.literal,
                                        'texto', c.texto, 'gravedad', c.gravedad)
                from faltas_catalogo c
               where c.rit_version = d.falta_rit_version
                 and c.numeral = d.falta_numeral and c.literal = d.falta_literal),
    'persona', (select jsonb_build_object('nombres', p.nombres, 'apellidos', p.apellidos,
                                          'documento', p.documento, 'funcion', p.funcion,
                                          'sede_codigo', s.codigo)
                  from personas p left join sedes s on s.id = p.sede_base_id
                 where p.id = d.persona_id),
    -- 56.1, 56.4, 56.5 y 54.2: entregados, de amonestación o suspensión, en los
    -- doce meses anteriores al hecho, y en conducta de la misma falta.
    'previas', (select coalesce(jsonb_agg(jsonb_build_object(
                         'correlativo', e.correlativo, 'nivel', e.nivel,
                         'firmado_at', e.firmado_at, 'entregado_at', e.entregado_at)
                       order by e.entregado_at, e.id), '[]'::jsonb)
                  from expediente_disciplinario e
                 where e.persona_id = d.persona_id
                   and e.id <> d.id
                   and e.tipo_causal = d.tipo_causal
                   and e.estado = 'entregado'
                   and e.nivel in ('amonestacion', 'suspension')
                   and e.entregado_at <= v_ts
                   and e.entregado_at >= v_ts - interval '12 months'
                   and (d.tipo_causal <> 'conducta'
                        or (e.falta_numeral = d.falta_numeral and e.falta_literal = d.falta_literal))),
    -- 56.6: «La Empresa deja constancia expresa de ese corte en cada documento
    -- que emite». Como el corte de `fn_tardanza_escalon_al` (0311): la fecha
    -- final del último documento ENTREGADO por la misma causa, sin la llamada
    -- verbal (19.2 a), y sin caducar —el agravante caduca; el non bis in idem no—.
    'corte', (select max(e.periodo_hasta)
                from expediente_disciplinario e
               where e.persona_id = d.persona_id
                 and e.id <> d.id
                 and e.tipo_causal = d.tipo_causal
                 and e.estado = 'entregado'
                 and e.nivel <> 'verbal'
                 and e.entregado_at <= v_ts
                 and (d.tipo_causal <> 'conducta'
                      or (e.falta_numeral = d.falta_numeral and e.falta_literal = d.falta_literal))),
    -- 19.3: «el detalle de las fechas, horas y minutos computados». La hora
    -- programada sale de la foto del horario con que se midió (0446).
    'medicion', (select coalesce(jsonb_agg(jsonb_build_object(
                          'fecha', j.fecha,
                          'entrada_ts', j.entrada_ts,
                          'minutos_tarde', j.minutos_tarde,
                          'entrada_programada', j.horario_aplicado ->> 'entrada',
                          'es_descanso', (j.horario_aplicado ->> 'es_descanso')::boolean)
                        order by j.fecha), '[]'::jsonb)
                   from jornadas j
                  where d.tipo_causal in ('tardanza', 'falta')
                    and j.persona_id = d.persona_id
                    and j.fecha in (select (h ->> 'fecha')::date
                                      from jsonb_array_elements(coalesce(d.hechos, '[]'::jsonb)) h)),
    'recepcion', (select jsonb_build_object('abierto_at', r.abierto_at, 'recibido_at', r.recibido_at)
                    from recepciones_cargos r where r.expediente_id = d.id),
    'descargos', (select coalesce(jsonb_agg(jsonb_build_object('texto', x.texto, 'presentado_at', x.presentado_at)
                                            order by x.presentado_at, x.id), '[]'::jsonb)
                    from descargos_presentados x where x.expediente_id = d.id),
    'recomunicado', (select jsonb_build_object('antes_comunicados_at', rc.antes_comunicados_at,
                                               'antes_vence_at', rc.antes_vence_at,
                                               'recomunicado_at', rc.recomunicado_at)
                       from cargos_recomunicados rc where rc.expediente_id = d.id)
  );
end;
$$;

grant execute on function fn_cargos_detalle(uuid) to authenticated;
revoke execute on function fn_cargos_detalle(uuid) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 5 · Lo que ella tiene en su Info
-- ════════════════════════════════════════════════════════════════════════════
-- Solo lo que está en curso: un borrador con cargos comunicados. Cuando se
-- firma, el documento sigue su camino de siempre (enviar a su Info, 0486) y
-- deja de ser «cargos». Sin el relato: se ve de reojo, como en la 0516.
create or replace function fn_mis_cargos()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_yo uuid := fn_persona_actual_id();
begin
  if v_yo is null then return jsonb_build_object('cargos', '[]'::jsonb); end if;

  return jsonb_build_object('cargos', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', d.id,
             'nivel', d.nivel,
             'tipo_causal', d.tipo_causal,
             'cargos_comunicados_at', d.cargos_comunicados_at,
             'descargo_vence_at', d.descargo_vence_at,
             'plazo_vigente', d.descargo_vence_at is not null and now() <= d.descargo_vence_at,
             'abierto_at', r.abierto_at,
             'recibido_at', r.recibido_at,
             'descargos', (select count(*) from descargos_presentados x where x.expediente_id = d.id),
             'falta', (select jsonb_build_object('numeral', c.numeral, 'literal', c.literal,
                                                 'rotulo', fr.rotulo, 'gravedad', c.gravedad)
                         from faltas_catalogo c
                         left join faltas_rotulos fr using (rit_version, numeral, literal)
                        where c.rit_version = d.falta_rit_version
                          and c.numeral = d.falta_numeral and c.literal = d.falta_literal))
           order by d.cargos_comunicados_at desc, d.id), '[]'::jsonb)
      from expediente_disciplinario d
      left join recepciones_cargos r on r.expediente_id = d.id
     where d.persona_id = v_yo
       and d.estado = 'borrador'
       and d.nivel in ('amonestacion', 'suspension')
       and d.cargos_comunicados_at is not null));
end;
$$;

grant execute on function fn_mis_cargos() to authenticated;
revoke execute on function fn_mis_cargos() from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 6 · Confirmar que los recibió, y presentar su descargo
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_recibir_cargos(p_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = public as $$
declare
  v_yo uuid := fn_persona_actual_id();
  d    expediente_disciplinario%rowtype;
  r    recepciones_cargos%rowtype;
begin
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select * into d from expediente_disciplinario where id = p_id and persona_id = v_yo;
  if not found or d.cargos_comunicados_at is null or d.estado = 'anulado'
     or d.nivel not in ('amonestacion', 'suspension') then
    raise exception 'No se encontró ese documento.';
  end if;

  -- `for update`: si el clic llega dos veces a la vez, el segundo espera al
  -- primero y encuentra la constancia dada, en vez de chocar con el trigger.
  select * into r from recepciones_cargos where expediente_id = p_id for update;
  if not found then
    raise exception 'Ábrelos primero: la constancia es de haberlos recibido y visto.';
  end if;
  if r.recibido_at is not null then return r.recibido_at; end if;

  update recepciones_cargos set recibido_at = now() where expediente_id = p_id
  returning recibido_at into r.recibido_at;
  return r.recibido_at;
end;
$$;

grant execute on function fn_recibir_cargos(uuid) to authenticated;
revoke execute on function fn_recibir_cargos(uuid) from public, anon;

create or replace function fn_presentar_descargo(p_id uuid, p_texto text)
returns timestamptz language plpgsql volatile security definer set search_path = public as $$
declare
  v_yo    uuid := fn_persona_actual_id();
  d       expediente_disciplinario%rowtype;
  v_texto text := btrim(coalesce(p_texto, ''));
  v_at    timestamptz;
begin
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select * into d from expediente_disciplinario where id = p_id and persona_id = v_yo;
  if not found or d.cargos_comunicados_at is null or d.estado = 'anulado'
     or d.nivel not in ('amonestacion', 'suspension') then
    raise exception 'No se encontró ese documento.';
  end if;

  if d.estado <> 'borrador' then
    raise exception 'Este documento ya se resolvió: su plazo de descargo terminó.';
  end if;
  if now() > d.descargo_vence_at then
    raise exception 'Tu plazo para presentar el descargo venció el % h. Si necesitas decir algo, habla con tu líder de equipo o con Desarrollo Organizacional.',
      to_char(d.descargo_vence_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI');
  end if;
  if not exists (select 1 from recepciones_cargos where expediente_id = p_id and recibido_at is not null) then
    raise exception 'Primero confirma que recibiste los cargos.';
  end if;
  if length(v_texto) < 10 then
    raise exception 'Escribe tu descargo con un poco más de detalle: es lo que se va a leer al decidir.';
  end if;
  if length(v_texto) > 4000 then
    raise exception 'Tu descargo es muy largo (máximo 4000 caracteres). Puedes dividirlo y presentar otro a continuación.';
  end if;

  insert into descargos_presentados (expediente_id, texto) values (p_id, v_texto)
  returning presentado_at into v_at;
  return v_at;
end;
$$;

grant execute on function fn_presentar_descargo(uuid, text) to authenticated;
revoke execute on function fn_presentar_descargo(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 7 · El reinicio único de los borradores ya comunicados
-- ════════════════════════════════════════════════════════════════════════════
-- Es una función y no un bloque suelto por una sola razón: que la prueba 471
-- pueda ejecutarlo de verdad. No se le da a nadie: solo la llama esta
-- migración, como dueña de la base.
create or replace function fn_cargos_reabrir_plazo_sin_info(p_corte timestamptz)
returns integer language plpgsql volatile set search_path = public as $$
declare v_n int;
begin
  with afectados as (
    select e.id, e.cargos_comunicados_at, e.descargo_vence_at
      from expediente_disciplinario e
     where e.estado = 'borrador'
       and e.nivel in ('amonestacion', 'suspension')
       and e.cargos_comunicados_at is not null
       and e.cargos_comunicados_at < p_corte
       and e.descargo_acogido is null
       and not exists (select 1 from cargos_recomunicados rc where rc.expediente_id = e.id)
       and not exists (select 1 from recepciones_cargos r where r.expediente_id = e.id)
     for update
  ), rastro as (
    insert into cargos_recomunicados (expediente_id, antes_comunicados_at, antes_vence_at, motivo)
    select a.id, a.cargos_comunicados_at, a.descargo_vence_at,
           'Sus cargos se comunicaron antes de que pudieran llegar a su Info en Dynamic (0581).'
      from afectados a
    returning expediente_id
  )
  update expediente_disciplinario e
     set cargos_comunicados_at = now(),
         descargo_vence_at     = fn_sumar_dias_habiles(now(), 2),
         observacion = coalesce(e.observacion || E'\n', '')
                       || '[RECOMUNICADO ' || to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD')
                       || ': los cargos se le comunican por su Info en Dynamic y su plazo de descargo vuelve a empezar. '
                       || 'Antes: comunicados el '
                       || to_char(a.cargos_comunicados_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI')
                       || ', vencía el '
                       || to_char(a.descargo_vence_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI') || ']'
    from afectados a
   where e.id = a.id
     and e.id in (select expediente_id from rastro);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function fn_cargos_reabrir_plazo_sin_info(timestamptz) from public, anon, authenticated;

-- El corte: lo comunicado ANTES de la primera pegada de esta migración. En la
-- primera pegada no hay registro de la 581 y el corte es ahora; en una repegada
-- es el momento del primer reinicio (o, si no reinició nada, el de la primera
-- pegada). Así, un borrador comunicado por el camino nuevo nunca se reinicia.
do $$
declare v_n int;
begin
  v_n := fn_cargos_reabrir_plazo_sin_info(coalesce(
    (select min(recomunicado_at) from cargos_recomunicados),
    (select aplicada_at from migraciones_aplicadas where numero = 581),
    now()));
  raise notice '0581: % borrador(es) con el plazo de descargo reiniciado y visibles en la Info de la persona.', v_n;
end $$;


insert into migraciones_aplicadas (numero, nombre) values (581, 'los_cargos_llegan_a_su_info')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
-- Cada fila: un borrador cuyo plazo se reinició, con sus fechas viejas y nuevas.
-- Tiene que salir el caso del 2026-11-02 (dos borradores de la misma persona).
select rc.expediente_id,
       to_char(rc.antes_vence_at at time zone 'America/Lima', 'DD/MM HH24:MI') as vencia,
       to_char(e.descargo_vence_at at time zone 'America/Lima', 'DD/MM HH24:MI') as vence_ahora,
       (select nombre from migraciones_aplicadas where numero = 581) as registro
  from cargos_recomunicados rc
  join expediente_disciplinario e on e.id = rc.expediente_id;
