-- ============================================================================
-- 0513 · El alta pide el documento, y cada documento dice de qué tipo es
-- ============================================================================
--
-- ── QUÉ PASÓ ────────────────────────────────────────────────────────────────
--
-- El 2026-10-06 una integrante apareció en todas las listas con su DNI escrito
-- en el lugar del apellido (lo limpió la 0512). Ningún código lo pegó: el alta
-- no tenía dónde poner el DNI. Y era el único dato que impide registrar dos
-- veces a la misma persona: el índice único de documento (0125) existe en
-- producción, pero el alta nunca lo llenaba, así que nunca frenaba nada. La
-- 0506 tapó el hueco comparando NOMBRES, que es una heurística; el documento
-- es la respuesta exacta.
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
--   1. `personas.tipo_documento`: 'dni' · 'ce' (carné de extranjería) ·
--      'pasaporte' (pasaporte o PTP). Decidido con Felipe el 2026-10-06.
--   2. `fn_documento_forma_valida(tipo, numero)`: LA regla, una sola vez.
--        dni        exactamente 8 dígitos
--        ce         de 9 a 12 letras o números
--        pasaporte  de 6 a 12 letras o números
--      La usan el candado de la tabla, el alta y la corrección. La pantalla
--      tiene la misma en packages/shared/src/documento.ts; tests/documento.test.ts
--      compara las dos.
--   3. A los documentos que ya existen se les asigna el tipo por su forma
--      (medido en producción el 2026-10-06: 40 con forma de DNI, 0 de carné,
--      0 que no encajen, 0 repetidos). Lo que no encaje NO se toca: se nombra.
--   4. `personas_documento_coherente`: tipo y número van juntos —los dos
--      vacíos o los dos llenos— y el número tiene la forma de su tipo.
--   5. `fn_crear_persona` EXIGE tipo y número, salvo para una estación de
--      retail (p_es_estacion), y se niega si el documento ya lo tiene alguien,
--      diciendo quién es (hint 'documento_repetido', detail = su id). El aviso
--      de nombre parecido (0506) se queda como segunda red: caza el documento
--      mal tecleado por un dígito.
--   6. `fn_set_documento` (la corrección de Datos personales) recibe también el
--      tipo —opcional y al final; sin él usa el que la persona ya tiene— y usa
--      la misma regla. La llama además `fn_aplicar_cambio_perfil` (0401) cuando
--      DO aprueba una corrección pedida desde «Lo mío», con tres argumentos:
--      por eso el orden no cambia y esa función no se toca.
--   7. «Lo mío»: quien NO tiene documento lo propone —tipo y número— y lo aprueba
--      DO (nueva fila `documento` del catálogo de propuestas, `solo_do`). Reescribe
--      `fn_crear_solicitud_perfil` (valida, y si el número ya es de otra persona
--      lo dice sin nombrarla) y `fn_aplicar_cambio_perfil` (lo aplica por
--      `fn_set_documento`, y se niega si DO ya se lo cargó mientras tanto).
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- md5 de partida, pedidos a PRODUCCIÓN el 2026-10-06 ANTES de escribir esto, y
-- comprobados idénticos al cuerpo de su migración en el repositorio:
--   fn_crear_persona   50c42522550d7827969efbbdc7472268 (3499 caracteres) · 0506
--   fn_set_documento   5f0863e081de5d0749478da24dbc297e (2616 caracteres) · 0344
-- Y la 0490 (cuenta_de_servicio + fn_set_cuenta_de_servicio), la 0507 (el
-- INSERT a personas solo entra por fn_crear_persona), la 0512 y la 0405
-- (`solo_do`). Los md5 de partida de las dos funciones de «Lo mío» están en la
-- sección 8.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- La OBLIGACIÓN vive en fn_crear_persona y no en un NOT NULL de la tabla. Desde
-- la 0507 esa función es la única puerta por la que entra una persona, así que
-- la base lo exige igual. Un NOT NULL (o un CHECK «not valid») dejaría a las 2
-- personas activas que hoy no tienen documento con la ficha trabada: no se les
-- podría ni corregir el nombre ni registrar su salida hasta cargarlo. La FORMA
-- sí va en la tabla, porque vale para todas las filas sin excepción.
--
-- La estación de retail nace como persona y se marca por fn_set_cuenta_de_servicio
-- en la misma transacción. No se escribe la columna en el INSERT: la 0490
-- decidió que «una persona nace como persona» y que marcarla pasa por su
-- función, con sus comprobaciones y su rastro. Así se mantiene.
--
-- El número se guarda sin espacios, puntos ni guiones y en mayúsculas, en la
-- base y no solo en la pantalla: así «ab-123 456» y «AB123456» chocan en el
-- índice único, que es lo que tienen que hacer.
--
-- Las firmas cambian (fn_crear_persona 8 → 11 argumentos, fn_set_documento
-- 3 → 4, los nuevos al final y con valor por defecto): `drop function` de la
-- vieja y luego `create`, o quedarían dos y la llamada sería ambigua (la
-- 0297/0299 y la 0367). Se comprueba al final.
--
-- ⚠ ORDEN. Entre pegar esto y fusionar el PR de la pantalla, Equipo no puede
-- dar de alta: la pantalla vieja no manda el documento y la base lo exige.
-- Falla en voz alta, sin escribir nada. Pegar y fusionar seguidos. (Datos
-- personales y la aprobación de «Lo mío» siguen funcionando en ese rato.)
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Repegar la 0506 y la 0344 (vuelven las firmas viejas; hay que hacer antes
-- `drop function` de las nuevas) y:
--   alter table personas drop constraint if exists personas_documento_coherente;
--   alter table personas drop constraint if exists personas_tipo_documento_valido;
-- La columna tipo_documento se puede dejar: nadie la lee si se revierte.
-- ============================================================================

-- ── 1 · La columna ──────────────────────────────────────────────────────────
alter table personas add column if not exists tipo_documento text;

comment on column personas.tipo_documento is
  'dni · ce (carné de extranjería) · pasaporte (pasaporte o PTP). Decide la forma de '
  'personas.documento (fn_documento_forma_valida). Null solo si documento también es null. 0513.';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'personas_tipo_documento_valido'
                    and conrelid = 'public.personas'::regclass) then
    alter table personas add constraint personas_tipo_documento_valido
      check (tipo_documento in ('dni', 'ce', 'pasaporte'));
  end if;
end $$;

-- ── 2 · La regla, una sola vez ──────────────────────────────────────────────
-- `immutable` porque la usa un CHECK. Recibe el número YA normalizado: quien
-- escribe (las dos funciones) normaliza antes de preguntar.
create or replace function fn_documento_forma_valida(p_tipo text, p_numero text)
returns boolean
language sql
immutable
as $$
  -- coalesce: un número null da «no» y no «no sé». Un CHECK deja pasar el
  -- «no sé», y por ahí entraba un tipo sin número (lo cazó la prueba 407).
  select coalesce(case p_tipo
           when 'dni'       then p_numero ~ '^[0-9]{8}$'
           when 'ce'        then p_numero ~ '^[0-9A-Z]{9,12}$'
           when 'pasaporte' then p_numero ~ '^[0-9A-Z]{6,12}$'
           else false
         end, false);
$$;

comment on function fn_documento_forma_valida(text, text) is
  'La forma de cada tipo de documento: dni 8 dígitos · ce 9-12 letras o números · pasaporte '
  '6-12 letras o números. Recibe el número normalizado (sin espacios, en mayúsculas). La '
  'pantalla tiene la misma regla en packages/shared/src/documento.ts. 0513.';

-- El mensaje de «forma inválida», una sola vez. Lo usan el alta, la corrección y
-- «Lo mío»: antes estaba escrito dos veces, y una tercera copia habría sido la
-- forma de que dijeran cosas distintas. Mismas palabras que AYUDA_DOCUMENTO en
-- packages/shared/src/documento.ts. Null = está bien.
create or replace function fn_documento_error(p_tipo text, p_numero text)
returns text
language sql
immutable
as $$
  select case
           when fn_documento_forma_valida(p_tipo, p_numero) then null
           when p_tipo = 'dni' then 'El DNI tiene exactamente 8 dígitos.'
           when p_tipo = 'ce'  then 'El carné de extranjería tiene de 9 a 12 letras o números.'
           else                     'El pasaporte o PTP tiene de 6 a 12 letras o números.'
         end;
$$;

revoke execute on function fn_documento_error(text, text) from public, anon, authenticated;

-- ── 3 · Los que ya existen ──────────────────────────────────────────────────
-- Solo se les pone tipo; el número no se toca. Primero DNI (8 dígitos), después
-- carné (9 a 12). Lo que no encaje en ninguna se queda sin tipo y se nombra:
-- el candado del paso 4 no se podrá validar hasta que alguien lo corrija.
do $$
declare
  v_dni int;
  v_ce  int;
  v_raros text;
begin
  update personas set tipo_documento = 'dni'
   where tipo_documento is null and documento ~ '^[0-9]{8}$';
  get diagnostics v_dni = row_count;

  update personas set tipo_documento = 'ce', documento = upper(documento)
   where tipo_documento is null and upper(documento) ~ '^[0-9A-Z]{9,12}$';
  get diagnostics v_ce = row_count;

  raise notice '0513: % documento(s) marcado(s) como DNI y % como carné de extranjería.', v_dni, v_ce;

  select string_agg(id::text, ', ') into v_raros
    from personas where documento is not null and tipo_documento is null;
  if v_raros is not null then
    raise exception '0513: estos documentos no tienen forma de DNI ni de carné y hay que corregirlos a mano en Datos personales antes de pegar esto: %', v_raros;
  end if;
end $$;

-- ── 4 · El candado ──────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'personas_documento_coherente'
                    and conrelid = 'public.personas'::regclass) then
    alter table personas add constraint personas_documento_coherente check (
      (documento is null and tipo_documento is null)
      or (documento is not null and tipo_documento is not null
          and fn_documento_forma_valida(tipo_documento, documento))
    ) not valid;
  end if;
  alter table personas validate constraint personas_documento_coherente;
end $$;

-- ── 5 · El alta ─────────────────────────────────────────────────────────────
drop function if exists fn_crear_persona(text, text, uuid, text, text, text, text, boolean);

create or replace function fn_crear_persona(
  p_nombres text,
  p_apellidos text,
  p_sede_base_id uuid,
  p_rol text,
  p_funcion text,
  p_email text,
  p_pin_hash text,
  p_confirmo_distinta boolean default false,
  p_tipo_documento text default null,
  p_documento text default null,
  p_es_estacion boolean default false
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_yo_rol rol_usuario;
  v_yo_rango int;
  v_nuevo_rango int;
  v_parecidas text;
  v_documento text;
  v_duena record;
  v_error text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede crear personas.';
  end if;
  if trim(coalesce(p_nombres, '')) = '' or trim(coalesce(p_apellidos, '')) = '' then
    raise exception 'Nombres y apellidos son obligatorios.';
  end if;
  if not exists (select 1 from sedes where id = p_sede_base_id) then
    raise exception 'Sede inválida.';
  end if;
  if p_rol is null or p_rol not in ('integrante', 'supervisor_sede', 'lider_do', 'admin') then
    raise exception 'Rol inválido: %', coalesce(p_rol, '(vacío)');
  end if;

  -- CAMBIO 0300 · el mismo escalafón que ya rige cambiar el rol de alguien
  -- que ya existe (fn_set_rol, 0295). Sin esto, un lider_do podía crear una
  -- cuenta NUEVA directamente como Admin, sin pasar por ninguna de las dos
  -- puertas que la 0295/0296 ya cerraron para una persona ya existente.
  select rol into v_yo_rol from personas where auth_user_id = auth.uid();
  v_yo_rango := case v_yo_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  v_nuevo_rango := case p_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  if v_yo_rol <> 'admin' and v_nuevo_rango >= v_yo_rango then
    raise exception 'No puedes crear una persona con un rol igual o superior al tuyo.';
  end if;

  if p_funcion is null or not exists (select 1 from areas where codigo = p_funcion and activa) then
    raise exception 'Área inválida o inactiva: %', coalesce(p_funcion, '(vacía)');
  end if;
  if p_pin_hash is null or p_pin_hash = '' then
    raise exception 'Falta el PIN.';
  end if;

  -- CAMBIO 0513 · el documento. Una persona entra con su documento; una
  -- estación de retail no tiene, y entra sin él. Mismas palabras que la
  -- pantalla (AYUDA_DOCUMENTO), para que diga lo mismo venga de donde venga.
  if p_es_estacion is true then
    if nullif(btrim(coalesce(p_documento, '')), '') is not null then
      raise exception 'Una estación de retail no lleva documento: no es una persona.';
    end if;
    if p_rol <> 'integrante' then
      raise exception 'Una estación de retail no puede tener rol de líder ni de administración.';
    end if;
  else
    if p_tipo_documento is null or p_tipo_documento not in ('dni', 'ce', 'pasaporte') then
      raise exception 'Falta el tipo de documento: DNI, carné de extranjería o pasaporte / PTP.';
    end if;
    v_documento := upper(regexp_replace(coalesce(p_documento, ''), '[[:space:].-]', '', 'g'));
    if v_documento = '' then
      raise exception 'Falta el número de documento. Es lo que impide registrar dos veces a la misma persona.';
    end if;
    v_error := fn_documento_error(p_tipo_documento, v_documento);
    if v_error is not null then
      raise exception '%', v_error;
    end if;
  end if;

  -- CAMBIO 0506 · si el nombre se parece al de alguien que ya existe, se pide
  -- confirmar que es OTRA persona. Se hace después de todas las validaciones de
  -- arriba para que un error de siempre siga dando su mensaje de siempre, y
  -- dentro de un candado para que dos altas simultáneas del mismo nombre no
  -- pasen las dos la comprobación antes de que alguna inserte.
  perform pg_advisory_xact_lock(hashtext('fn_crear_persona'));

  -- CAMBIO 0513 · el documento repetido va ANTES que el nombre parecido y NO
  -- se puede confirmar: dos personas con el mismo documento no existen. Dentro
  -- del mismo candado, así dos altas simultáneas con el mismo número no pasan
  -- las dos (y si pasaran, el índice único de la 0125 detiene a la segunda).
  -- `detail` lleva el id para que la pantalla ofrezca «Ver en la lista».
  if v_documento is not null then
    select p.id, p.nombres, p.apellidos, p.estado, s.codigo as sede_codigo, p.fecha_ingreso
      into v_duena
      from personas p left join sedes s on s.id = p.sede_base_id
     where p.documento = v_documento
     limit 1;
    if found then
      raise exception 'Ese documento ya lo tiene «% %» (% · % · ingresó %). No la registres otra vez: ábrela en Equipo%.',
        v_duena.nombres, v_duena.apellidos,
        case when v_duena.estado = 'activo' then 'está en el equipo' else 'ya salió' end,
        coalesce(v_duena.sede_codigo, 'sin sede'),
        to_char(v_duena.fecha_ingreso, 'DD/MM/YYYY'),
        case when v_duena.estado = 'activo' then '' else ' y reactívala desde su menú «•••»' end
        using hint = 'documento_repetido', detail = v_duena.id::text;
    end if;
  end if;

  if p_confirmo_distinta is not true then
    select string_agg(
             format('«%s %s» (%s · %s · ingresó %s)',
                    q.nombres, q.apellidos,
                    case when q.estado = 'activo' then 'está en el equipo' else 'ya salió' end,
                    coalesce(q.sede_codigo, 'sin sede'),
                    to_char(q.fecha_ingreso, 'DD/MM/YYYY')),
             '; ')
      into v_parecidas
      from (select * from fn_personas_parecidas(p_nombres, p_apellidos) limit 3) q;
    if v_parecidas is not null then
      -- El `hint` es el marcador estable con el que la pantalla distingue este
      -- caso de cualquier otro error, sin leer el texto.
      raise exception 'Ya hay alguien registrado que se parece: %. Si es la misma persona, no la registres otra vez: ábrela en Equipo y complétala ahí (si ya salió, se reactiva). Si es otra persona, confirma que es distinta.',
        v_parecidas
        using hint = 'persona_parecida';
    end if;
  end if;

  -- CAMBIO 0513 · tipo_documento y documento entran con la persona.
  insert into personas (nombres, apellidos, sede_base_id, rol, funcion, email, pin_hash,
                        tipo_documento, documento)
  values (
    trim(p_nombres), trim(p_apellidos), p_sede_base_id,
    p_rol::rol_usuario, p_funcion, nullif(trim(coalesce(p_email, '')), ''), p_pin_hash,
    case when v_documento is null then null else p_tipo_documento end, v_documento
  )
  returning id into v_id;

  -- CAMBIO 0513 · la estación nace como persona y se marca por su puerta (0490),
  -- en esta misma transacción: si la marca falla, el alta tampoco queda.
  if p_es_estacion is true then
    perform fn_set_cuenta_de_servicio(v_id, true,
      'Nace como estación de retail desde el alta de Equipo: no es una persona y no lleva documento.');
  end if;

  return jsonb_build_object('id', v_id);
end;
$$;

-- ── 6 · La corrección ───────────────────────────────────────────────────────
drop function if exists fn_set_documento(uuid, text, text);

-- CAMBIO 0513 · el tipo va AL FINAL y es opcional: los tres primeros argumentos
-- siguen en su sitio. Así `fn_aplicar_cambio_perfil` (0401) —que la llama con
-- tres cuando DO aprueba una corrección pedida desde «Lo mío»— no se toca, y la
-- pantalla vieja de Datos personales sigue corrigiendo entre pegar y fusionar.
-- Sin tipo, se usa el que la persona ya tiene.
create or replace function fn_set_documento(p_persona_id uuid, p_documento text, p_motivo text, p_tipo_documento text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes text;
  v_tipo_antes text;
  v_nuevo text;
  v_quien uuid;
  v_otro  text;
  v_tipo  text;
  v_error text;
begin
  -- Guard null-safe, como manda el estándar del repo: un null no pasa como
  -- autorizado. Se exige admin o líder: el DNI se imprime en papeles legales, así
  -- que no lo edita la encargada ni la propia persona.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el número de documento.';
  end if;

  select documento, tipo_documento into v_antes, v_tipo_antes from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  -- CAMBIO 0513 · normalizado igual que el alta (sin espacios, puntos ni
  -- guiones, en mayúsculas), y con la forma de su tipo en vez de «8 a 12
  -- caracteres de lo que sea».
  v_nuevo := nullif(upper(regexp_replace(coalesce(p_documento, ''), '[[:space:].-]', '', 'g')), '');

  if v_nuevo is null then
    raise exception 'El número de documento no puede quedar vacío. Si está mal, se corrige; no se borra.';
  end if;

  v_tipo := coalesce(p_tipo_documento, v_tipo_antes);
  if v_tipo is null or v_tipo not in ('dni', 'ce', 'pasaporte') then
    raise exception 'Falta el tipo de documento: DNI, carné de extranjería o pasaporte / PTP.';
  end if;

  v_error := fn_documento_error(v_tipo, v_nuevo);
  if v_error is not null then
    raise exception '%', v_error;
  end if;

  -- CAMBIO 0344 — antes se exigía el motivo siempre, incluso cuando `v_antes`
  -- era null (la persona nunca tuvo DNI). Ahora solo se exige cuando de
  -- verdad reemplaza un valor anterior.
  if v_antes is not null and (p_motivo is null or btrim(p_motivo) = '') then
    raise exception 'El motivo es obligatorio: este número se imprime en memos y contratos.';
  end if;

  -- CAMBIO 0513 · cambiar solo el tipo (un 8 dígitos que era carné) también
  -- es un cambio.
  if v_antes = v_nuevo and v_tipo_antes = v_tipo then
    return;   -- nada que hacer, y así no se ensucia la auditoría
  end if;

  -- Dos personas con el mismo DNI es un error de dedo, no un caso de negocio.
  select nombres || ' ' || apellidos into v_otro
  from personas where documento = v_nuevo and id <> p_persona_id
  limit 1;
  if v_otro is not null then
    raise exception 'Ese documento ya lo tiene %. Abortado para no dejar dos personas con el mismo DNI.', v_otro;
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  update personas set documento = v_nuevo, tipo_documento = v_tipo where id = p_persona_id;

  -- CAMBIO 0513 · el rastro dice también el tipo: «DNI 12345678».
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.documento',
          coalesce(upper(v_tipo_antes) || ' ' || v_antes, v_antes, '(vacío)'),
          upper(v_tipo) || ' ' || v_nuevo,
          coalesce(nullif(btrim(p_motivo), ''), '(primera carga, sin DNI previo)'), v_quien);
end;
$$;

comment on function fn_set_documento(uuid, text, text, text) is
  'Corrige o carga por primera vez el documento de una persona, con su tipo (dni · ce · '
  'pasaporte; si no llega, el que ya tenía) y la forma de ese tipo (fn_documento_forma_valida). Solo admin o líder; motivo '
  'obligatorio solo cuando reemplaza uno que ya existía, con rastro en correcciones_auditoria '
  'siempre — porque se imprime en memos disciplinarios y en contratos. 0513.';

-- Una sola firma de cada una. Si quedaran dos, la llamada de la pantalla sería
-- ambigua y no fallaría al pegar, sino al abrir Equipo: se deshace todo aquí.
do $$
begin
  if (select count(*) from pg_proc
       where proname = 'fn_crear_persona' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'fn_crear_persona quedó con más de una firma: la pantalla de Equipo no podría dar de alta a nadie. Se deshace la migración.';
  end if;
  if (select count(*) from pg_proc
       where proname = 'fn_set_documento' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'fn_set_documento quedó con más de una firma: Datos personales no podría corregir un documento. Se deshace la migración.';
  end if;
end $$;


-- ── 8 · Lo mío: quien no tiene documento lo propone, y DO lo aprueba ─────────
-- Un campo MÁS del catálogo de propuestas (0399), no un mecanismo nuevo: hereda
-- la bandeja, el «pendiente de aprobación» y el historial. `solo_do` (0405): lo
-- aprueba DO y no la líder de equipo, porque es el número que va en el contrato.
-- Sin adjunto: «Lo mío» ya pide las dos caras del DNI y DO compara contra ellas.
--
-- md5 de partida, pedidos a PRODUCCIÓN el 2026-10-06 ANTES de escribir esto. Los
-- dos llegan con un `\r` por línea (119 y 68) —la 0401 se pegó desde Windows,
-- ver CLAUDE.md—, y MEDIDO: el cuerpo del repo con `\n` → `\r\n` da el md5 de
-- producción exacto (largo 6553 y 2941). Mismo código, sin cambios de fondo:
--   fn_aplicar_cambio_perfil   fbcf2ac89327383bf81edc6474f85fdd (6553)  ← 0401
--   fn_crear_solicitud_perfil  7a2f1dfe636110748bcb3d155685b6d7 (2941)  ← 0401
-- Pegada desde la misma máquina, la 0513 los dejará con `\r` otra vez: el md5
-- de llegada no coincidirá con el del repo, y esa es la firma conocida.
--
-- ⚠ Si la 0405 no está pegada, esta migración se detiene: `solo_do` no existe.
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'catalogo_campos_perfil' and column_name = 'solo_do') then
    raise exception '0513: falta la 0405 (catalogo_campos_perfil.solo_do). Pégala antes.';
  end if;
end $$;

insert into catalogo_campos_perfil
  (campo, etiqueta, requiere_documento, documento_sugerido, columnas, solo_do)
values
  ('documento', 'Documento de identidad', false, null,
   array['tipo_documento','documento'], true)
on conflict (campo) do update set
  etiqueta           = excluded.etiqueta,
  requiere_documento = excluded.requiere_documento,
  documento_sugerido = excluded.documento_sugerido,
  columnas           = excluded.columnas,
  solo_do            = excluded.solo_do;

create or replace function fn_crear_solicitud_perfil(
  p_campo           text,
  p_valor_propuesto jsonb,
  p_rutas_adjuntas  text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
  v_requiere_doc boolean;
  v_ruta text;
  v_id uuid;
  v_anverso text;   -- CAMBIO 0401
  v_reverso text;   -- CAMBIO 0401
  v_valor jsonb := p_valor_propuesto;   -- CAMBIO 0513 · lo que se guarda (normalizado)
  v_doc text;       -- CAMBIO 0513
  v_error text;     -- CAMBIO 0513
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.';
  end if;

  select requiere_documento into v_requiere_doc from catalogo_campos_perfil where campo = p_campo;
  if v_requiere_doc is null then
    raise exception 'Campo de perfil desconocido: %', p_campo;
  end if;

  perform fn_validar_valor_propuesto(p_campo, p_valor_propuesto);

  -- CAMBIO 0513 · el documento de quien todavía no tiene ninguno. Lo propone la
  -- persona y lo aprueba DO. Corregir uno que ya existe NO va por aquí: es de
  -- DO (`correccion_identidad`). Y si el número ya es de otra persona se dice
  -- SIN nombrarla: a una integrante no se le revela de quién es un DNI, y quien
  -- sí puede actuar —DO— lo ve completo en el alta.
  if p_campo = 'documento' then
    if exists (select 1 from personas where id = v_persona and documento is not null) then
      raise exception 'Tu documento ya está cargado. Si hay un error, solo Desarrollo Organizacional lo puede corregir.';
    end if;
    if coalesce(p_valor_propuesto->>'tipo_documento', '') not in ('dni', 'ce', 'pasaporte') then
      raise exception 'Falta el tipo de documento: DNI, carné de extranjería o pasaporte / PTP.';
    end if;
    v_doc := upper(regexp_replace(coalesce(p_valor_propuesto->>'documento', ''), '[[:space:].-]', '', 'g'));
    if v_doc = '' then
      raise exception 'Falta el número de documento.';
    end if;
    v_error := fn_documento_error(p_valor_propuesto->>'tipo_documento', v_doc);
    if v_error is not null then
      raise exception '%', v_error;
    end if;
    if exists (select 1 from personas where documento = v_doc) then
      raise exception 'Ese número ya está registrado. Avisa a Desarrollo Organizacional para que lo revise.';
    end if;
    -- Lo que DO va a ver, y lo que se aplica, es el número ya normalizado.
    v_valor := jsonb_build_object('tipo_documento', p_valor_propuesto->>'tipo_documento', 'documento', v_doc);
  end if;

  if v_requiere_doc and coalesce(array_length(p_rutas_adjuntas, 1), 0) = 0 then
    raise exception 'Este cambio exige adjuntar al menos un documento de sustento.';
  end if;

  foreach v_ruta in array p_rutas_adjuntas loop
    if v_ruta !~ ('^solicitud/' || v_persona::text || '/') then
      raise exception 'Uno de los archivos adjuntos no pertenece a tu carpeta.';
    end if;
  end loop;

  -- CAMBIO 0401: el DNI son DOS caras, y las dos tienen que venir además como
  -- adjuntos — que es lo que las hace visibles en /admin/bandeja para quien va
  -- a aprobarlas, y lo que ya las validó como "de tu carpeta" en el bucle de
  -- arriba. Sin este bloque se podría proponer como DNI la ruta del DNI de
  -- otra persona: el valor propuesto es jsonb libre y nadie más lo mira.
  if p_campo = 'foto_dni' then
    v_anverso := nullif(trim(coalesce(p_valor_propuesto->>'foto_dni_anverso_ruta', '')), '');
    v_reverso := nullif(trim(coalesce(p_valor_propuesto->>'foto_dni_reverso_ruta', '')), '');
    if v_anverso is null or v_reverso is null then
      raise exception 'Hacen falta las dos caras del DNI: el anverso y el reverso.';
    end if;
    if v_anverso = v_reverso then
      raise exception 'El anverso y el reverso no pueden ser la misma imagen.';
    end if;
    if not (p_rutas_adjuntas @> array[v_anverso, v_reverso]) then
      raise exception 'Las dos caras del DNI tienen que ir también como archivos adjuntos.';
    end if;
  end if;

  -- Reemplaza cualquier pendiente anterior sobre el mismo campo — nunca para
  -- familiar_nuevo (ver el índice único parcial, admite varias en paralelo).
  if p_campo <> 'familiar_nuevo' then
    update solicitudes_cambio_perfil
    set estado = 'reemplazada', resuelta_at = now(), resuelta_por = v_persona
    where persona_id = v_persona and campo = p_campo and estado = 'pendiente';
  end if;

  insert into solicitudes_cambio_perfil
    (persona_id, campo, valor_anterior, valor_propuesto, rutas_adjuntas)
  values
    (v_persona, p_campo, fn_snapshot_valor_actual(v_persona, p_campo), v_valor, p_rutas_adjuntas)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Ya tienes una solicitud pendiente sobre ese campo. Espera a que se resuelva.';
end;
$fn$;

create or replace function fn_aplicar_cambio_perfil(p_solicitud_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s solicitudes_cambio_perfil%rowtype;
  v_quien uuid := fn_persona_actual_id();
  v_motivo text;
begin
  select * into v_s from solicitudes_cambio_perfil where id = p_solicitud_id;
  if not found then
    raise exception 'Esa solicitud no existe.';
  end if;

  v_motivo := 'Aprobado por solicitud de perfil — ver solicitudes_cambio_perfil.id=' || v_s.id;

  case v_s.campo
    when 'celular' then
      insert into datos_personales (persona_id, celular) values (v_s.persona_id, v_s.valor_propuesto->>'celular')
      on conflict (persona_id) do update set celular = excluded.celular;

    when 'direccion' then
      insert into datos_personales (persona_id, direccion) values (v_s.persona_id, v_s.valor_propuesto->>'direccion')
      on conflict (persona_id) do update set direccion = excluded.direccion;

    when 'contacto_emergencia' then
      insert into datos_personales (persona_id, emergencia_nombre, emergencia_vinculo, emergencia_telefono)
      values (v_s.persona_id, v_s.valor_propuesto->>'emergencia_nombre',
              v_s.valor_propuesto->>'emergencia_vinculo', v_s.valor_propuesto->>'emergencia_telefono')
      on conflict (persona_id) do update set
        emergencia_nombre = excluded.emergencia_nombre,
        emergencia_vinculo = excluded.emergencia_vinculo,
        emergencia_telefono = excluded.emergencia_telefono;

    when 'estado_civil' then
      insert into datos_personales (persona_id, estado_civil) values (v_s.persona_id, v_s.valor_propuesto->>'estado_civil')
      on conflict (persona_id) do update set estado_civil = excluded.estado_civil;

    when 'hijos_menores' then
      insert into datos_personales (persona_id, hijos_menores)
      values (v_s.persona_id, (v_s.valor_propuesto->>'hijos_menores')::boolean)
      on conflict (persona_id) do update set hijos_menores = excluded.hijos_menores;

    when 'grado_instruccion' then
      insert into datos_personales (persona_id, grado_instruccion)
      values (v_s.persona_id, v_s.valor_propuesto->>'grado_instruccion')
      on conflict (persona_id) do update set grado_instruccion = excluded.grado_instruccion;

    when 'discapacidad' then
      insert into datos_personales (persona_id, discapacidad, discapacidad_conadis)
      values (v_s.persona_id, (v_s.valor_propuesto->>'discapacidad')::boolean, v_s.valor_propuesto->>'discapacidad_conadis')
      on conflict (persona_id) do update set
        discapacidad = excluded.discapacidad, discapacidad_conadis = excluded.discapacidad_conadis;

    when 'cuenta_bancaria' then
      insert into datos_personales (persona_id, entidad_bancaria, numero_cuenta)
      values (v_s.persona_id, v_s.valor_propuesto->>'entidad_bancaria', v_s.valor_propuesto->>'numero_cuenta')
      on conflict (persona_id) do update set
        entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta;

    when 'cuspp' then
      insert into datos_personales (persona_id, cuspp)
      values (v_s.persona_id, nullif(upper(trim(v_s.valor_propuesto->>'cuspp')), ''))
      on conflict (persona_id) do update set cuspp = excluded.cuspp;

    -- CAMBIO 0401: las dos caras entran juntas. Deja fila en la auditoría igual
    -- que correccion_identidad, y por lo mismo: es un documento de identidad, y
    -- «quién aprobó qué DNI y cuándo» tiene que poder responderse sin abrir el
    -- almacén de archivos.
    when 'foto_dni' then
      insert into datos_personales (persona_id, foto_dni_anverso_ruta, foto_dni_reverso_ruta)
      values (v_s.persona_id,
              v_s.valor_propuesto->>'foto_dni_anverso_ruta',
              v_s.valor_propuesto->>'foto_dni_reverso_ruta')
      on conflict (persona_id) do update set
        foto_dni_anverso_ruta = excluded.foto_dni_anverso_ruta,
        foto_dni_reverso_ruta = excluded.foto_dni_reverso_ruta;

      insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
      values (v_s.persona_id, 'datos_personales.foto_dni',
              v_s.valor_anterior::text, v_s.valor_propuesto::text, v_motivo, v_quien);

    when 'correccion_identidad' then
      if v_s.valor_propuesto ? 'documento' then
        perform fn_set_documento(v_s.persona_id, v_s.valor_propuesto->>'documento', v_motivo);
      end if;
      if (v_s.valor_propuesto ? 'nombre_dni') or (v_s.valor_propuesto ? 'fecha_nacimiento') or (v_s.valor_propuesto ? 'genero') then
        insert into datos_personales (persona_id, nombre_dni, fecha_nacimiento, genero)
        values (v_s.persona_id,
                coalesce(v_s.valor_propuesto->>'nombre_dni', (select nombre_dni from datos_personales where persona_id = v_s.persona_id)),
                coalesce((v_s.valor_propuesto->>'fecha_nacimiento')::date, (select fecha_nacimiento from datos_personales where persona_id = v_s.persona_id)),
                coalesce(v_s.valor_propuesto->>'genero', (select genero from datos_personales where persona_id = v_s.persona_id)))
        on conflict (persona_id) do update set
          nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento, genero = excluded.genero;

        insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
        values (v_s.persona_id, 'datos_personales.correccion_identidad',
                v_s.valor_anterior::text, v_s.valor_propuesto::text, v_motivo, v_quien);
      end if;

    -- CAMBIO 0513 · el documento que la persona propuso por primera vez. Pasa por
    -- `fn_set_documento`, la misma puerta de Datos personales: misma regla de
    -- forma, mismo rastro. Si mientras tanto DO ya se lo cargó, la propuesta
    -- quedó vieja y NO se aplica: pisaría un documento que alguien ya revisó.
    when 'documento' then
      if exists (select 1 from personas where id = v_s.persona_id and documento is not null) then
        raise exception 'Esta persona ya tiene su documento cargado: la propuesta quedó vieja. Recházala; si hay un error, se corrige en Datos personales.';
      end if;
      perform fn_set_documento(v_s.persona_id, v_s.valor_propuesto->>'documento', v_motivo,
                               v_s.valor_propuesto->>'tipo_documento');

    when 'familiar_nuevo' then
      perform fn_set_derechohabiente(
        null, v_s.persona_id,
        v_s.valor_propuesto->>'nombres', v_s.valor_propuesto->>'apellidos', v_s.valor_propuesto->>'vinculo',
        v_s.valor_propuesto->>'documento', (v_s.valor_propuesto->>'fecha_nacimiento')::date,
        false, false, v_motivo);

    else
      raise exception 'No sé cómo aplicar el campo: %', v_s.campo;
  end case;

  -- Tarea de seguimiento a planilla — solo para estos dos, y solo aquí (al
  -- aprobar), nunca al crear la solicitud.
  if v_s.campo in ('estado_civil', 'hijos_menores') then
    insert into seguimiento_planilla_por_solicitud (solicitud_id, persona_id, campo, descripcion)
    select v_s.id, v_s.persona_id, v_s.campo,
           'Revisar planilla — ' || pe.nombres || ' ' || pe.apellidos || ' — ' || c.etiqueta
    from personas pe, catalogo_campos_perfil c
    where pe.id = v_s.persona_id and c.campo = v_s.campo
    on conflict (solicitud_id) do nothing;
  end if;
end;
$fn$;

revoke all on function fn_aplicar_cambio_perfil(uuid) from public, anon, authenticated;

-- ── 7 · Permisos ────────────────────────────────────────────────────────────
grant execute on function fn_crear_persona(text, text, uuid, text, text, text, text, boolean, text, text, boolean) to authenticated;
revoke execute on function fn_crear_persona(text, text, uuid, text, text, text, text, boolean, text, text, boolean) from public, anon;

grant execute on function fn_crear_solicitud_perfil(text, jsonb, text[]) to authenticated;
revoke execute on function fn_crear_solicitud_perfil(text, jsonb, text[]) from public, anon;

grant execute on function fn_set_documento(uuid, text, text, text) to authenticated;
revoke execute on function fn_set_documento(uuid, text, text, text) from public, anon;

-- La regla se ABRE a propósito a quien escribe en personas (medido: authenticated
-- y service_role). El CHECK de la tabla la evalúa con los permisos de QUIEN
-- ESCRIBE, no de su dueño, y desde la 0076 toda función nace cerrada: sin este
-- grant, cualquier UPDATE directo a personas desde la pantalla —«Guardar
-- cambios» en Equipo— fallaría con «permission denied for function». Lo cazó
-- el control de la prueba 401. Es una función pura: no lee ninguna tabla ni
-- revela nada. A anon no: anon no escribe en personas.
grant execute on function fn_documento_forma_valida(text, text) to authenticated, service_role;

-- PostgREST guarda en memoria las firmas de las funciones.
notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre) values (513, 'el_alta_pide_el_documento')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
-- Las booleanas deben dar `true`; `registro` debe decir 513 · el_alta_pide_el_documento.
select
  (select count(*) = 0 from personas where documento is not null and tipo_documento is null)
    as todo_documento_tiene_tipo,
  (select convalidated from pg_constraint
    where conname = 'personas_documento_coherente' and conrelid = 'public.personas'::regclass)
    as candado_validado,
  (select count(*) = 1 and bool_and(prosrc like '%CAMBIO 0513%') from pg_proc
    where proname = 'fn_crear_persona' and pronamespace = 'public'::regnamespace)
    as alta_nueva_una_sola_firma,
  (select count(*) = 1 and bool_and(prosrc like '%CAMBIO 0513%') from pg_proc
    where proname = 'fn_set_documento' and pronamespace = 'public'::regnamespace)
    as correccion_nueva_una_sola_firma,
  not has_function_privilege('anon', 'fn_crear_persona(text,text,uuid,text,text,text,text,boolean,text,text,boolean)', 'execute')
    as anon_no_da_de_alta,
  (select count(*) = 1 and bool_and(solo_do) from catalogo_campos_perfil where campo = 'documento')
    as lo_mio_puede_proponer_el_documento,
  (select count(*) = 1 and bool_and(prosrc like '%CAMBIO 0513%') from pg_proc
    where proname in ('fn_crear_solicitud_perfil') and pronamespace = 'public'::regnamespace)
    as solicitud_nueva_una_sola_firma,
  (select count(*) = 1 and bool_and(prosrc like '%CAMBIO 0513%') from pg_proc
    where proname in ('fn_aplicar_cambio_perfil') and pronamespace = 'public'::regnamespace)
    as aprobacion_nueva_una_sola_firma,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 513)
    as registro,
  (select string_agg(proname || '=' || md5(prosrc), ' | ' order by proname) from pg_proc
    where proname in ('fn_crear_persona', 'fn_set_documento', 'fn_crear_solicitud_perfil', 'fn_aplicar_cambio_perfil')
      and pronamespace = 'public'::regnamespace)
    as md5_llegada;
