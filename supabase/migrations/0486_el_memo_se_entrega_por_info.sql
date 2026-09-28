-- ============================================================================
-- 0486_el_memo_se_entrega_por_info.sql
-- ============================================================================
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
-- Un segundo camino, válido junto al del papel, para ENTREGAR un memo
-- disciplinario: quien lo emite lo «envía a su Info»; la persona lo abre, lo
-- lee y lo RECIBE con un acto explícito —firmándolo con la firma que ya tiene
-- guardada, o recibiéndolo sin firmar—. Ese acto es la entrega: el documento
-- pasa a `entregado`, con `medio_entrega = 'digital'` y la fecha y hora en que
-- ella lo confirmó.
--
-- Existe porque CAYLA trabaja en tres ciudades. Hasta hoy la única entrega era
-- física —imprimir, poner el papel en la mano, firmar, escanear el cargo—, y
-- eso obliga a que quien emite y quien recibe estén en el mismo sitio el mismo
-- día. El 56.2 dice que un documento firmado y no entregado no produce efecto,
-- así que cada día de viaje del papel es un día en que la sanción no existe.
--
-- El camino del papel NO se toca: sigue igual y sigue siendo el que se usa
-- cuando la persona está delante. Son dos opciones equivalentes.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   1. Que la 0408 ya está en producción: esta migración usa sus columnas
--      `firma_sancionado`, `firma_sancionado_confirmada_at` y
--      `sancionado_rechazo_firma_at`, y su regla «firmar y negarse son
--      mutuamente excluyentes».
--   2. Que la firma de «Mi firma» sirve como constancia de recibido. ESTA ES
--      UNA SUPOSICIÓN LEGAL, no técnica: puede ser una imagen, un trazo o el
--      nombre en una tipografía (0395), y lo único que la ata a la persona es
--      que entró con su sesión. Antes de usar este camino con una sanción
--      real conviene tener la respuesta del laboralista. Por eso el diseño
--      exige DOS cosas distintas y las guarda por separado: la entrega
--      (`entregado_at`, el clic de «recibir») y la respuesta a firmar o no.
--   3. Que Nivel 4 (imputación de cargos y carta de despido) queda fuera, con
--      el mismo criterio que ya fijó la 0408: esos documentos exigen firma
--      manuscrita, notarial o con testigos, nunca un trazo digital.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- LA ENTREGA ES EL CLIC, NO LA APERTURA NI EL ENVÍO. Enviar no entrega: ella
-- podría no haber entrado nunca. Abrir tampoco: quedaría en el registro que
-- «recibió» alguien que solo miró la pantalla y cerró. Se elige el acto
-- explícito porque es el que se sostiene delante de quien lo discuta, y porque
-- deja la misma huella que el papel: una fecha y una persona que respondió.
--
-- RECIBIR Y RESPONDER SON UNA SOLA OPERACIÓN. `fn_recibir_memo_digital`
-- marca la entrega y guarda su respuesta en el mismo UPDATE. Si fueran dos
-- llamadas, quedaría el estado intermedio «entregado y sin respuesta», que no
-- corresponde a nada que pueda pasar en el papel. Y un constraint lo hace
-- imposible: una entrega digital SIEMPRE lleva su respuesta.
--
-- NADIE PUEDE ENTREGAR «DIGITAL» EN NOMBRE DE OTRO. `fn_expediente_entregar`
-- no acepta ese medio (su lista es fija) y esta es la única función que lo
-- escribe, y solo sobre el documento de quien tiene la sesión. Quien emite
-- puede ENVIAR y puede RETIRAR el envío; recibir es solo de la persona.
--
-- NO SE REESCRIBE NINGUNA FUNCIÓN EXISTENTE. Todo lo nuevo son funciones y
-- columnas nuevas. Por eso esta migración no declara «md5 de partida»: no hay
-- función vigente de la que partir. Es deliberado: `fn_expediente_entregar`,
-- `fn_expediente_reabrir` y `fn_expediente_anular` son las que deciden qué
-- pasa con plata y con antecedentes, y ninguna se toca para agregar un canal.
--
-- LO QUE SE PAGA POR ESO: `fn_expediente_reabrir` («cambiar firmante») no sabe
-- del envío. Sobre un documento enviado, el constraint
-- `chk_envio_info_no_borrador` lo rechaza. El mensaje que ve quien lo intente
-- es el del constraint, poco amable; por eso la pantalla de Disciplina no le
-- ofrece «Cambiar firmante» mientras haya un envío pendiente: primero se
-- retira el envío. El constraint es la red, no la interfaz.
--
-- LA PERSONA ELIGE QUÉ VE. `fn_mi_memo` entrega el documento solo a su dueña y
-- solo cuando ya fue enviado o entregado. Un borrador, o un documento firmado
-- que nadie envió, sigue siendo invisible para ella (0408, `exp_select_propia`
-- no filtra por estado; por eso la lectura pasa por una función).
--
-- ── ESTADOS QUE NO PUEDEN EXISTIR (los hace imposibles el esquema) ──────────
--
--   · Enviado por alguien y sin fecha de envío, o al revés.
--   · Un borrador enviado.
--   · Un documento de Nivel 4 enviado.
--   · Una entrega digital sin envío previo, o anterior al envío.
--   · Una entrega digital sin respuesta de la persona (ni firmó ni se negó).
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop function if exists fn_recibir_memo_digital(uuid, boolean);
--   drop function if exists fn_mi_memo(uuid);
--   drop function if exists fn_mis_memos_por_recibir();
--   drop function if exists fn_expediente_retirar_de_info(uuid);
--   drop function if exists fn_expediente_enviar_a_info(uuid);
--   -- ANTES de soltar el medio: los documentos ya entregados por Info
--   -- perderían su medio. Se dejan como 'fisico' solo si el laboralista lo
--   -- acepta; si no, se conserva la columna y se quita solo la función.
--   alter table expediente_disciplinario
--     drop constraint if exists chk_entrega_digital_con_respuesta,
--     drop constraint if exists chk_entrega_digital_fue_enviada,
--     drop constraint if exists chk_envio_info_nivel,
--     drop constraint if exists chk_envio_info_no_borrador,
--     drop constraint if exists chk_envio_info_completo;
--   -- y devolver `expediente_disciplinario_medio_entrega_check` a sus cuatro
--   -- valores (fisico, correo, notarial, acta_negativa), y luego:
--   alter table expediente_disciplinario
--     drop column if exists enviado_a_info_por,
--     drop column if exists enviado_a_info_at;
--
-- ── TODO FALLA, TODO EL TIEMPO ──────────────────────────────────────────────
--
-- Esta migración no toca ninguna API externa: no hay correo, ni WhatsApp, ni
-- notificación push. La persona se entera cuando abre Info (la Bandeja y el
-- recuadro «Necesita que hagas algo» ya cuentan lo que le falta) o cuando
-- quien lo envió se lo dice. Si Info no abre, o ella no entra, el documento
-- queda firmado y sin entregar —que es exactamente donde estaba antes de
-- enviarlo— y quien lo emite lo ve en «Por entregar» y puede ir por el papel.
-- Nada se pierde y nada se da por entregado sin que ella haya respondido.
-- ============================================================================

-- ── El envío, con quién y cuándo ────────────────────────────────────────────
alter table expediente_disciplinario
  add column if not exists enviado_a_info_at  timestamptz,
  add column if not exists enviado_a_info_por uuid references personas(id);

comment on column expediente_disciplinario.enviado_a_info_at is
  'Cuándo se puso el documento firmado a disposición de la persona en su Info. NO es la entrega: la entrega es cuando ella lo confirma (entregado_at, medio digital).';

-- ── El medio nuevo ──────────────────────────────────────────────────────────
-- Se reescribe el check entero: `add constraint` sobre una columna que ya
-- tiene uno deja los dos vivos y el viejo seguiría rechazando el valor nuevo.
alter table expediente_disciplinario drop constraint if exists expediente_disciplinario_medio_entrega_check;
alter table expediente_disciplinario add constraint expediente_disciplinario_medio_entrega_check
  check (medio_entrega in ('fisico','correo','notarial','acta_negativa','digital'));

-- ── Los estados imposibles ──────────────────────────────────────────────────
alter table expediente_disciplinario drop constraint if exists chk_envio_info_completo;
alter table expediente_disciplinario add constraint chk_envio_info_completo
  check ((enviado_a_info_at is null) = (enviado_a_info_por is null));

alter table expediente_disciplinario drop constraint if exists chk_envio_info_no_borrador;
alter table expediente_disciplinario add constraint chk_envio_info_no_borrador
  check (enviado_a_info_at is null or estado <> 'borrador');

alter table expediente_disciplinario drop constraint if exists chk_envio_info_nivel;
alter table expediente_disciplinario add constraint chk_envio_info_nivel
  check (enviado_a_info_at is null or nivel in ('verbal', 'amonestacion', 'suspension'));

alter table expediente_disciplinario drop constraint if exists chk_entrega_digital_fue_enviada;
alter table expediente_disciplinario add constraint chk_entrega_digital_fue_enviada
  check (medio_entrega is distinct from 'digital'
         or (enviado_a_info_at is not null and entregado_at >= enviado_a_info_at));

alter table expediente_disciplinario drop constraint if exists chk_entrega_digital_con_respuesta;
alter table expediente_disciplinario add constraint chk_entrega_digital_con_respuesta
  check (medio_entrega is distinct from 'digital'
         or firma_sancionado_confirmada_at is not null
         or sancionado_rechazo_firma_at is not null);

-- ── Enviar a su Info (quien emite) ──────────────────────────────────────────
-- Mismo permiso que ENTREGAR: quien puede entregar el papel puede poner el
-- documento en Info. Un permiso distinto abriría una segunda regla de «quién
-- puede actuar» sobre el mismo documento, y esa ya está escrita una vez.
create or replace function fn_expediente_enviar_a_info(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r   expediente_disciplinario%rowtype;
  v_p personas%rowtype;
  v_yo uuid;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  -- for update: si al mismo tiempo la persona lo recibe o quien emite lo
  -- retira, uno de los dos espera al otro y ve el resultado ya escrito.
  select * into r from expediente_disciplinario where id = p_id for update;
  if not found then raise exception 'El documento no existe.'; end if;
  if fn_expediente_puede_actuar(r.persona_id, r.nivel) is not true then raise exception 'Sin permiso.'; end if;

  if r.estado <> 'firmado' then
    raise exception 'Solo se envía a Info un documento firmado que aún no se entrega (estado actual: %).', r.estado;
  end if;
  if r.nivel not in ('verbal', 'amonestacion', 'suspension') then
    raise exception 'Este documento no admite entrega digital: se entrega en físico o vía notarial.';
  end if;
  if r.enviado_a_info_at is not null then
    raise exception 'Este documento ya está enviado a su Info.';
  end if;

  select * into v_p from personas where id = r.persona_id;
  if v_p.estado <> 'activo' then
    raise exception '% ya no está activa: no tiene Info a la que enviarle nada.', v_p.nombres;
  end if;
  -- Sin cuenta no hay Info: el documento quedaría «enviado» a una pantalla que
  -- esa persona no puede abrir, y quien lo emitió creería que ya se entregó.
  if v_p.auth_user_id is null then
    raise exception '% todavía no tiene cuenta para entrar a su Info. Entrégale el documento en físico.', v_p.nombres;
  end if;

  update expediente_disciplinario
     set enviado_a_info_at  = now(),
         enviado_a_info_por = v_yo
   where id = p_id;
end;
$$;
grant execute on function fn_expediente_enviar_a_info(uuid) to authenticated;
revoke execute on function fn_expediente_enviar_a_info(uuid) from public, anon;

-- ── Retirar el envío (quien emite) ──────────────────────────────────────────
-- Para cambiar el firmante, corregir algo o pasar a entregarlo en físico.
-- Solo mientras la persona no lo haya recibido: una vez recibido es entrega, y
-- un documento entregado se anula, no se retira.
create or replace function fn_expediente_retirar_de_info(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id for update;
  if not found then raise exception 'El documento no existe.'; end if;
  if fn_expediente_puede_actuar(r.persona_id, r.nivel) is not true then raise exception 'Sin permiso.'; end if;

  if r.estado = 'entregado' then
    raise exception 'Este documento ya fue recibido: un documento entregado se anula, no se retira.';
  end if;
  if r.estado <> 'firmado' or r.enviado_a_info_at is null then
    raise exception 'Este documento no está enviado a su Info.';
  end if;

  update expediente_disciplinario
     set enviado_a_info_at = null,
         enviado_a_info_por = null
   where id = p_id;
end;
$$;
grant execute on function fn_expediente_retirar_de_info(uuid) to authenticated;
revoke execute on function fn_expediente_retirar_de_info(uuid) from public, anon;

-- ── Lo que le falta recibir (la persona) ────────────────────────────────────
-- Genérico a propósito: solo dice QUE hay algo y desde cuándo. Ni el nivel ni
-- el motivo viajan aquí — la Bandeja y el recuadro de Info lo pintan donde
-- cualquiera que pase cerca de la pantalla puede verlo de reojo. El detalle
-- recién existe al abrir el documento (`fn_mi_memo`).
create or replace function fn_mis_memos_por_recibir()
returns table (id uuid, enviado_a_info_at timestamptz)
language sql stable security definer set search_path = public as $$
  select d.id, d.enviado_a_info_at
    from expediente_disciplinario d
   where d.persona_id = fn_persona_actual_id()
     and d.estado = 'firmado'
     and d.enviado_a_info_at is not null
   order by d.enviado_a_info_at desc, d.id desc;
$$;
grant execute on function fn_mis_memos_por_recibir() to authenticated;
revoke execute on function fn_mis_memos_por_recibir() from public, anon;

-- ── El documento, tal como ella lo lee ──────────────────────────────────────
-- Devuelve TODO lo que hace falta para pintar el memo, en una sola llamada y
-- con quien lo firmó ya nombrado. No es un lujo: la pantalla del panel lee la
-- ficha de quien firma con la sesión de quien mira, y `personas_select_*` solo
-- deja ver la propia y la de la sede. Si una colaboradora abriera un memo
-- firmado por su líder de equipo con esa misma pantalla, no podría leer la
-- ficha de quien lo firmó y el papel saldría diciendo que lo firmó Gerencia
-- General. Un documento que miente sobre quién lo suscribe se cae al discutirlo.
--
-- Visible solo para su dueña, solo de los tres niveles con firma digital, y
-- solo si ya se envió o ya se entregó. Cualquier otra cosa devuelve null y la
-- pantalla dice «no se encontró»: no se distingue «no existe» de «no es tuyo».
create or replace function fn_mi_memo(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_yo uuid;
  d expediente_disciplinario%rowtype;
  p personas%rowtype;
  f personas%rowtype;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then return null; end if;

  select * into d from expediente_disciplinario where id = p_id and persona_id = v_yo;
  if not found then return null; end if;
  if d.nivel not in ('verbal', 'amonestacion', 'suspension') then return null; end if;
  if not ((d.estado = 'firmado' and d.enviado_a_info_at is not null) or d.estado = 'entregado') then
    return null;
  end if;

  select * into p from personas where id = d.persona_id;
  select * into f from personas where id = d.firmante_id;

  return jsonb_build_object(
    'id', d.id,
    'correlativo', d.correlativo,
    'tipo_causal', d.tipo_causal,
    'nivel', d.nivel,
    'estado', d.estado,
    'periodo_desde', d.periodo_desde,
    'periodo_hasta', d.periodo_hasta,
    'hechos', d.hechos,
    'suspension_dias', d.suspension_dias,
    'suspension_desde', d.suspension_desde,
    'suspension_hasta', d.suspension_hasta,
    'suspension_fechas', d.suspension_fechas,
    'firmado_at', d.firmado_at,
    'creado_at', d.creado_at,
    'entregado_at', d.entregado_at,
    'medio_entrega', d.medio_entrega,
    'enviado_a_info_at', d.enviado_a_info_at,
    'firma_sancionado', d.firma_sancionado,
    'firma_sancionado_confirmada_at', d.firma_sancionado_confirmada_at,
    'sancionado_rechazo_firma_at', d.sancionado_rechazo_firma_at,
    'persona', jsonb_build_object(
      'nombres', p.nombres,
      'apellidos', p.apellidos,
      'documento', p.documento,
      'funcion', p.funcion,
      'sede_codigo', (select s.codigo from sedes s where s.id = p.sede_base_id)
    ),
    'firmante', case when f.id is null then null else jsonb_build_object(
      'nombre', f.nombres || ' ' || f.apellidos,
      'cargo', fn_cargo_de_rol(f.rol)
    ) end,
    -- La regla de quién ve la firma de quien emite vive en fn_firma_de_memo
    -- (0148). Se llama a ella y no se copia: dos versiones de esa regla es
    -- exactamente lo que este repositorio ya pagó con el firmante de los memos.
    'firma_emisor', fn_firma_de_memo(d.id)
  );
end;
$$;
grant execute on function fn_mi_memo(uuid) to authenticated;
revoke execute on function fn_mi_memo(uuid) from public, anon;

-- ── Recibirlo (la persona) ──────────────────────────────────────────────────
-- p_firmar = true   → «Firmar y recibir»: copia su firma guardada.
-- p_firmar = false  → «Recibir sin firmar»: queda anotado que prefirió no
--                     firmarlo digitalmente (misma constancia que la 0408).
-- Las dos entregan. Lo que las distingue es solo la respuesta a firmar.
--
-- Una sola sentencia UPDATE: la entrega y la respuesta quedan juntas o no
-- queda ninguna. Si dos pestañas pulsan a la vez, `for update` hace que la
-- segunda espere y encuentre el documento ya entregado.
create or replace function fn_recibir_memo_digital(p_id uuid, p_firmar boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo     uuid;
  r        expediente_disciplinario%rowtype;
  v_imagen text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;
  if p_firmar is null then raise exception 'Indica si firmas o recibes sin firmar.'; end if;

  select * into r from expediente_disciplinario where id = p_id for update;
  if not found or r.persona_id <> v_yo then raise exception 'No se encontró ese documento.'; end if;

  if r.estado = 'entregado' then
    raise exception 'Este documento ya quedó recibido.';
  end if;
  if r.estado <> 'firmado' or r.enviado_a_info_at is null then
    raise exception 'Este documento no está disponible para recibir.';
  end if;
  if r.nivel not in ('verbal', 'amonestacion', 'suspension') then
    raise exception 'Este documento no admite entrega digital.';
  end if;

  if p_firmar then
    select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
    if v_imagen is null then
      raise exception 'Todavía no configuraste tu firma. Créala en «Mi firma» y vuelve a intentarlo.';
    end if;
  end if;

  update expediente_disciplinario
     set estado                         = 'entregado',
         medio_entrega                  = 'digital',
         entregado_at                   = now(),
         -- Quien entrega es quien lo puso en Info, no ella: el 55.4 pide saber
         -- quién entregó (0303), y ella es quien recibe.
         entregado_por                  = r.enviado_a_info_por,
         firma_sancionado               = case when p_firmar then v_imagen end,
         firma_sancionado_confirmada_at = case when p_firmar then now() end,
         sancionado_rechazo_firma_at    = case when p_firmar then null else now() end
   where id = p_id;
end;
$$;
grant execute on function fn_recibir_memo_digital(uuid, boolean) to authenticated;
revoke execute on function fn_recibir_memo_digital(uuid, boolean) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (486, 'el_memo_se_entrega_por_info')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
