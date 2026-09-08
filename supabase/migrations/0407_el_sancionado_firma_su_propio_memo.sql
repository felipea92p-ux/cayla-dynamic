-- QUÉ PROMETE: la persona sancionada puede, sobre su PROPIO memo ya
-- entregado (nunca un borrador), dejar una constancia digital: firmarlo con
-- la misma firma que ya configura en Mi perfil → Firma, o marcar
-- explícitamente que prefiere no firmar digitalmente. Ninguna de las dos
-- cosas reemplaza el trámite físico que ya existe (cargo firmado escaneado,
-- o acta de negativa con testigos) — es evidencia adicional, con su propia
-- fecha y hora, nunca un sustituto.
--
-- QUÉ ASUME:
--   1. Que "Nivel 4" (imputación, despido) queda fuera, con el mismo criterio
--      que ya aplica `fn_firma_de_memo` (0076/0148) para la firma del EMISOR:
--      esos niveles exigen firma manuscrita o certificada, nunca un trazo
--      digital. Se repite el mismo filtro `nivel in ('verbal','amonestacion',
--      'suspension')`, no se generaliza a una función compartida porque una es
--      "leer la firma de quien emite" y esta es "escribir la constancia de
--      quien recibe" — preguntas y permisos distintos.
--   2. Que un memo en 'borrador' o 'firmado' (firmado por el emisor, pero
--      TODAVÍA NO ENTREGADO) no es visible para el sancionado. Ya está escrito
--      en `/mio/page.tsx` (comentario de cabecera): `exp_select_propia` no
--      filtra por estado, así que cualquier lectura nueva desde `/mio` tiene
--      que imponer ese filtro ella misma. Por eso `fn_mis_memos()` es
--      `security definer` y no una simple consulta a la tabla: garantiza el
--      filtro `estado = 'entregado'` del lado del servidor, no confiado al
--      cliente.
--
-- POR QUÉ ASÍ: se guarda una COPIA de la imagen al momento de firmar
-- (`firma_sancionado`), igual que ya se decidió para la firma propia en el
-- contrato (0402, en otra rama): si la persona cambia su firma general
-- después, este memo — un hecho puntual y ya cerrado — sigue mostrando la que
-- usó al firmar. Firmar y "preferir no firmar" son mutuamente excluyentes
-- (un constraint lo hace imposible a nivel de esquema, no una validación que
-- alguien podría olvidar en el código): si ya firmó y por error cambia de
-- opinión, `fn_rechazar_firma_memo` limpia la firma anterior; si ya rechazó y
-- decide firmar, `fn_firmar_memo_como_sancionado` limpia el rechazo.
--
-- CÓMO SE REVIERTE:
--   drop function if exists fn_firmar_memo_como_sancionado(uuid);
--   drop function if exists fn_rechazar_firma_memo(uuid);
--   drop function if exists fn_mis_memos();
--   drop function if exists fn_memos_recientes_respuesta_sancionado(int);
--   alter table expediente_disciplinario
--     drop constraint if exists chk_memo_firma_o_rechazo_no_ambos,
--     drop constraint if exists chk_memo_firma_sancionado,
--     drop column if exists sancionado_rechazo_firma_at,
--     drop column if exists firma_sancionado_confirmada_at,
--     drop column if exists firma_sancionado;
--
-- md5 de partida (LOCAL) de fn_firma_de_memo, que esta migración NO toca pero
-- usa como referencia de criterio (nivel in ('verbal','amonestacion',
-- 'suspension')) — declarado para que quien pegue esto confirme que sigue
-- siendo la misma regla: pedir a producción con donde-vive.sh antes de pegar.

-- ── La constancia del sancionado, congelada al momento de darla ────────────
alter table expediente_disciplinario
  add column if not exists firma_sancionado text,
  add column if not exists firma_sancionado_confirmada_at timestamptz,
  add column if not exists sancionado_rechazo_firma_at timestamptz;

alter table expediente_disciplinario drop constraint if exists chk_memo_firma_sancionado;
alter table expediente_disciplinario add constraint chk_memo_firma_sancionado check (
  (firma_sancionado is null and firma_sancionado_confirmada_at is null)
  or (firma_sancionado is not null and firma_sancionado_confirmada_at is not null
      and firma_sancionado ~ '^data:image/(png|jpeg);base64,')
);

-- Estado imposible: no se puede haber firmado Y haberse negado a firmar el
-- mismo memo al mismo tiempo — son dos respuestas mutuamente excluyentes a la
-- misma pregunta.
alter table expediente_disciplinario drop constraint if exists chk_memo_firma_o_rechazo_no_ambos;
alter table expediente_disciplinario add constraint chk_memo_firma_o_rechazo_no_ambos check (
  not (firma_sancionado_confirmada_at is not null and sancionado_rechazo_firma_at is not null)
);

-- ── Mis memos (el sancionado, mirando los suyos) ────────────────────────────
-- Nunca un borrador, nunca uno firmado-pero-no-entregado: si el emisor
-- todavía no decidió entregarlo, el sancionado no tiene por qué saber que
-- existe. `security definer` para que este filtro sea una garantía del
-- servidor, no una promesa del cliente.
create or replace function fn_mis_memos()
returns table (
  id                            uuid,
  correlativo                   text,
  tipo_causal                   text,
  nivel                         text,
  entregado_at                  timestamptz,
  medio_entrega                 text,
  firma_sancionado_confirmada_at timestamptz,
  sancionado_rechazo_firma_at    timestamptz
)
language sql stable security definer set search_path = public as $$
  select d.id, d.correlativo, d.tipo_causal, d.nivel, d.entregado_at, d.medio_entrega,
         d.firma_sancionado_confirmada_at, d.sancionado_rechazo_firma_at
    from expediente_disciplinario d
   where d.persona_id = fn_persona_actual_id()
     and d.estado = 'entregado'
   order by d.entregado_at desc nulls last, d.id desc;
$$;
grant execute on function fn_mis_memos() to authenticated;
revoke execute on function fn_mis_memos() from public, anon;

-- ── Firmar MI memo ───────────────────────────────────────────────────────────
create or replace function fn_firmar_memo_como_sancionado(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo     uuid;
  v_imagen text;
  v_dueno  uuid;
  v_estado text;
  v_nivel  text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select persona_id, estado, nivel into v_dueno, v_estado, v_nivel
    from expediente_disciplinario where id = p_id;
  if v_dueno is null then raise exception 'No se encontró ese memo.'; end if;
  if v_dueno <> v_yo then raise exception 'Ese memo no es tuyo.'; end if;
  if v_estado <> 'entregado' then raise exception 'Este memo no está disponible para firmar.'; end if;
  if v_nivel not in ('verbal', 'amonestacion', 'suspension') then
    raise exception 'Este documento no admite firma digital — se firma en físico o vía notarial.';
  end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a Mi perfil → Firma antes de firmar.';
  end if;

  update expediente_disciplinario
     set firma_sancionado = v_imagen,
         firma_sancionado_confirmada_at = now(),
         sancionado_rechazo_firma_at = null
   where id = p_id;
end;
$$;
grant execute on function fn_firmar_memo_como_sancionado(uuid) to authenticated;
revoke execute on function fn_firmar_memo_como_sancionado(uuid) from public, anon;

-- ── Preferir no firmar digitalmente ──────────────────────────────────────────
-- Distinta del acta de negativa con testigos (0303): esa la registra el
-- ADMIN en persona, con evidencia física. Esta es una constancia digital de
-- que la propia persona vio el documento y decidió no firmarlo ahí mismo —
-- útil, pero sin el peso probatorio de un acta con testigos. No reemplaza esa
-- vía; conviven.
create or replace function fn_rechazar_firma_memo(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo    uuid;
  v_dueno uuid;
  v_estado text;
  v_nivel  text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select persona_id, estado, nivel into v_dueno, v_estado, v_nivel
    from expediente_disciplinario where id = p_id;
  if v_dueno is null then raise exception 'No se encontró ese memo.'; end if;
  if v_dueno <> v_yo then raise exception 'Ese memo no es tuyo.'; end if;
  if v_estado <> 'entregado' then raise exception 'Este memo no está disponible.'; end if;
  if v_nivel not in ('verbal', 'amonestacion', 'suspension') then
    raise exception 'Este documento no admite esta acción.';
  end if;

  update expediente_disciplinario
     set sancionado_rechazo_firma_at = now(),
         firma_sancionado = null,
         firma_sancionado_confirmada_at = null
   where id = p_id;
end;
$$;
grant execute on function fn_rechazar_firma_memo(uuid) to authenticated;
revoke execute on function fn_rechazar_firma_memo(uuid) from public, anon;

-- ── Para el aviso del admin: quién respondió su memo hace poco ──────────────
-- Mismo alcance que ya usa el resto de Disciplina: admin/líder ven todo,
-- supervisor_sede solo lo de su propia sede — igual que
-- `fn_expediente_puede_actuar` (0058).
create or replace function fn_memos_recientes_respuesta_sancionado(p_dias int default 14)
returns table (
  id           uuid,
  persona      text,
  correlativo  text,
  tipo_causal  text,
  nivel        text,
  firmado_at   timestamptz,
  rechazado_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select d.id, p.nombres || ' ' || p.apellidos, d.correlativo, d.tipo_causal, d.nivel,
         d.firma_sancionado_confirmada_at, d.sancionado_rechazo_firma_at
    from expediente_disciplinario d
    join personas p on p.id = d.persona_id
   where (d.firma_sancionado_confirmada_at is not null or d.sancionado_rechazo_firma_at is not null)
     and coalesce(d.firma_sancionado_confirmada_at, d.sancionado_rechazo_firma_at) >= now() - make_interval(days => p_dias)
     and (
       fn_es_admin_o_lider() is true
       or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
     )
   order by coalesce(d.firma_sancionado_confirmada_at, d.sancionado_rechazo_firma_at) desc;
$$;
grant execute on function fn_memos_recientes_respuesta_sancionado(int) to authenticated;
revoke execute on function fn_memos_recientes_respuesta_sancionado(int) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (407, 'el_sancionado_firma_su_propio_memo')
on conflict (numero) do nothing;
