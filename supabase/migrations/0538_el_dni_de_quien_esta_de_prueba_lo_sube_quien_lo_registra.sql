-- ============================================================================
-- 0538 · EL DNI DE QUIEN ESTÁ DE PRUEBA LO SUBE QUIEN LO REGISTRA
-- ============================================================================
--
-- QUÉ PROMETE (el contrato, en tres líneas)
--   1. DO, administración y la líder de equipo (de la sede de la persona) pueden
--      subir las DOS caras del DNI de alguien que está de prueba: la persona no
--      tiene cuenta, así que no puede hacerlo ella desde «Lo mío».
--   2. Esas fotos entran por la MISMA puerta que cualquier DNI (la solicitud de
--      perfil `foto_dni`, 0401): mismo bucket privado, mismo congelado de lo
--      aprobado, mismo historial y misma fila de auditoría. No hay una segunda
--      forma de guardar un DNI.
--   3. Y se ve quién cerró pruebas hace poco: `fn_pruebas_cierres_recientes`
--      alimenta la Bandeja, que es la mitigación de que una líder decida sola.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-19)
--   «Los únicos datos que se le piden son su DNI de ambos lados, nombres,
--   apellidos y número.» Nombres, apellidos y número ya se piden en el alta de
--   Equipo (0513); faltan las dos fotos. Y: «DO, líder o los que tienen más cargo
--   pueden subir el DNI por su cuenta».
--
-- QUÉ ASUME
--   · La 0536 pegada (`fn_prueba_puede_actuar`, `pruebas`).
--   · `fn_solicitud_perfil_puede_escribir` es la de la 0399. Se COMPRUEBA abajo
--     (md5 del cuerpo, tal cual o con \r\n) y la migración se niega a entrar sobre
--     otra cosa: es una función chica, pero decide quién escribe en el bucket
--     donde viven los DNI.
--   · `fn_resolver_solicitud_perfil` ya deja resolver una solicitud a la líder de
--     la sede de la persona (salvo las `solo_do`, y `foto_dni` no lo es), así que
--     la puerta nueva no necesita aflojar ninguna aprobación: solo CREAR la
--     solicitud a nombre de otra persona, que `fn_crear_solicitud_perfil` no hace
--     (siempre crea para quien llama).
--
-- POR QUÉ ASÍ
--   · La alternativa era escribir las columnas `foto_dni_*_ruta` directo desde una
--     función nueva. Habría sido más corta y una segunda forma de guardar un DNI,
--     sin el congelado de lo aprobado ni el historial. Esta crea la solicitud y la
--     aprueba en el acto (con `fn_resolver_solicitud_perfil`): quien sube es
--     también quien aprueba, y por eso queda dicho en el motivo.
--   · El permiso del bucket (`fn_solicitud_perfil_puede_escribir`) gana UNA rama:
--     quien puede actuar sobre la prueba de esa persona, y solo mientras la persona
--     siga activa y en vínculo «Prueba». La lectura NO se toca
--     (`fn_solicitud_perfil_puede_leer`): la líder ya lee los archivos de la gente
--     de su sede —para poder aprobar una solicitud— y sigue sin leer los de otra.
--
-- QUÉ NO HACE
--   · No toca `fn_crear_solicitud_perfil` ni `fn_resolver_solicitud_perfil`.
--   · No sustituye la constancia de consentimiento: la GUARDA. «Lo mío» registra la
--     aceptación de quien sube su propio DNI; aquí sube otra persona, así que la
--     constancia se guarda a nombre de la persona de prueba y dice quién declaró
--     que se la dieron y con qué texto exacto (`consentimientos_datos_personales`,
--     0404). Sin ese texto —50 letras como mínimo, la misma regla de la 0404— la
--     función se niega: un DNI recolectado sin constancia es justo lo que la Ley
--     N.° 29733 no admite. Es una DECLARACIÓN de quien registra, no la firma de la
--     persona; si algún día hace falta la firma, es otra pieza.
--   · No cambia el DNI de quien no está de prueba: esos siguen por «Lo mío» y la
--     aprobación de siempre.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_prueba_cargar_dni(uuid, text, text, text);
--   drop function if exists fn_pruebas_cierres_recientes(integer);
--   Y pegar de nuevo el cuerpo de `fn_solicitud_perfil_puede_escribir` de
--   `0399_el_colaborador_propone_do_aprueba.sql`. Las fotos ya cargadas quedan
--   (son solicitudes aprobadas normales).
-- ============================================================================

-- ── Guardia ─────────────────────────────────────────────────────────────────
do $guardia$
declare
  v_n   int;
  v_src text;
begin
  if to_regprocedure('fn_prueba_puede_actuar(uuid)') is null then
    raise exception 'PARA. Falta la 0536: fn_prueba_puede_actuar no existe. Pega primero la 0536.';
  end if;

  select count(*) into v_n from pg_proc
   where proname = 'fn_solicitud_perfil_puede_escribir' and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then
    raise exception 'PARA. fn_solicitud_perfil_puede_escribir tiene % versiones (se esperaba 1). Reconstruir desde la vigente con donde-vive.sh.', v_n;
  end if;

  select prosrc into v_src from pg_proc
   where proname = 'fn_solicitud_perfil_puede_escribir' and pronamespace = 'public'::regnamespace;

  if position('CAMBIO 0538' in v_src) > 0 then
    return;   -- ya pegada: repegar es seguro
  end if;

  if md5(v_src) not in ('6a37a709aa1aaf929a4b92b28f2a452c', 'f1a28aacf9d9f52751f44cbc6332e8ab') then
    raise exception 'PARA. fn_solicitud_perfil_puede_escribir de esta base no es la de la 0399 (md5 %, % caracteres). Esta migración copia la 0399: pegarla revertiría en silencio lo que se hizo después. Pide el md5 a producción.',
      md5(v_src), length(v_src);
  end if;
end
$guardia$;

-- ── 1 · Quién escribe en la carpeta de quién ────────────────────────────────
create or replace function fn_solicitud_perfil_puede_escribir(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_persona text;
begin
  if split_part(p_path, '/', 1) <> 'solicitud' then return false; end if;
  v_persona := split_part(p_path, '/', 2);
  if v_persona !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  if fn_es_admin_o_lider() is true then return true; end if;
  if v_persona::uuid = fn_persona_actual_id() then return true; end if;

  -- CAMBIO 0538 · quien registra a alguien que está de prueba (DO, administración
  -- o la líder de SU sede) sube el DNI por esa persona, que no tiene cuenta. Solo
  -- mientras siga activa y en vínculo «Prueba»: pasado eso, el DNI vuelve a ser de
  -- cada quien. Escribir no es leer: no abre la lectura de DNI ajenos.
  return coalesce(
    fn_prueba_puede_actuar(v_persona::uuid) is true
    and exists (select 1 from personas p
                 where p.id = v_persona::uuid
                   and p.estado = 'activo'
                   and p.tipo_vinculo = 'prueba'),
    false);
end;
$function$;

-- ── 2 · Cargar el DNI de otra persona, por la misma puerta ──────────────────
create or replace function fn_prueba_cargar_dni(p_persona_id uuid, p_anverso text, p_reverso text, p_consentimiento text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor    uuid;
  v_p        personas%rowtype;
  v_anverso  text := nullif(btrim(coalesce(p_anverso, '')), '');
  v_reverso  text := nullif(btrim(coalesce(p_reverso, '')), '');
  v_prefijo  text;
  v_id       uuid;
  v_quien    text;
begin
  if fn_prueba_puede_actuar(p_persona_id) is not true then
    raise exception 'No puedes cargar el DNI de esta persona.';
  end if;
  v_actor := fn_persona_actual_id();
  if v_actor is null then
    raise exception 'No puedo identificar quién carga el DNI, así que no puedo dejarlo registrado. Inicia sesión con tu usuario.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva.';
  end if;
  if v_p.tipo_vinculo <> 'prueba' then
    raise exception 'Esta puerta es solo para quien está de prueba (su vínculo es «%»): el DNI del resto lo sube cada quien desde «Lo mío».', v_p.tipo_vinculo;
  end if;

  if v_anverso is null or v_reverso is null then
    raise exception 'Hacen falta las dos caras del DNI: el anverso y el reverso.';
  end if;
  if v_anverso = v_reverso then
    raise exception 'El anverso y el reverso no pueden ser la misma imagen.';
  end if;
  v_prefijo := 'solicitud/' || p_persona_id::text || '/';
  if left(v_anverso, length(v_prefijo)) <> v_prefijo or left(v_reverso, length(v_prefijo)) <> v_prefijo then
    raise exception 'Los archivos no están en la carpeta de esa persona.';
  end if;

  -- LA CONSTANCIA DE CONSENTIMIENTO, ANTES DE LA SOLICITUD (Ley N.° 29733, art. 5:
  -- se pide al recolectar el dato). «Lo mío» la guarda a nombre de quien sube su
  -- propio DNI; aquí sube OTRA persona, así que la constancia se guarda a nombre de
  -- la persona de prueba y dice QUIÉN declaró que se la dieron, con el texto exacto.
  -- Mismo mínimo que `fn_registrar_mi_consentimiento` (0404): no puede ser vacía.
  if length(btrim(coalesce(p_consentimiento, ''))) < 50 then
    raise exception 'Falta la constancia de que la persona autorizó el tratamiento de su DNI: el texto llegó vacío o incompleto.';
  end if;
  select nombres || ' ' || apellidos into v_quien from personas where id = v_actor;
  insert into consentimientos_datos_personales (persona_id, finalidad, texto)
  values (p_persona_id, 'foto_dni',
          'Constancia declarada por ' || coalesce(v_quien, 'quien registra') || ' al registrar la prueba, '
          || 'en presencia de la persona: ' || btrim(p_consentimiento));

  -- Reemplaza la pendiente anterior del mismo campo, como la puerta de siempre.
  update solicitudes_cambio_perfil
     set estado = 'reemplazada', resuelta_at = now(), resuelta_por = v_actor
   where persona_id = p_persona_id and campo = 'foto_dni' and estado = 'pendiente';

  insert into solicitudes_cambio_perfil (persona_id, campo, valor_anterior, valor_propuesto, rutas_adjuntas)
  values (p_persona_id, 'foto_dni',
          fn_snapshot_valor_actual(p_persona_id, 'foto_dni'),
          jsonb_build_object('foto_dni_anverso_ruta', v_anverso, 'foto_dni_reverso_ruta', v_reverso),
          array[v_anverso, v_reverso])
  returning id into v_id;

  -- Se aprueba en el acto, por la misma función que usa DO: congela los archivos,
  -- escribe `datos_personales` y deja la fila de auditoría.
  perform fn_resolver_solicitud_perfil(v_id, true, 'Cargado por quien registra la prueba');

  return v_id;
end;
$$;

revoke execute on function fn_prueba_cargar_dni(uuid, text, text, text) from public, anon;
grant  execute on function fn_prueba_cargar_dni(uuid, text, text, text) to authenticated;

comment on function fn_prueba_cargar_dni(uuid, text, text, text) is
  'Sube las dos caras del DNI de alguien que está de prueba y no tiene cuenta (0538). Crea la solicitud foto_dni a su nombre y la aprueba en el acto '
  'con fn_resolver_solicitud_perfil: mismo bucket, mismo congelado y mismo historial que un DNI de «Lo mío». Puede DO, administración y la líder de SU sede. '
  'Guarda además la constancia de consentimiento (Ley 29733) a nombre de la persona, diciendo quién la declaró.';

-- ── 3 · Quién cerró pruebas hace poco ───────────────────────────────────────
-- La mitigación de que una líder decida sola: DO ve cada «no apto» y cada «se
-- retiró» de las últimas horas, con quién lo decidió, el motivo y cuántas horas
-- quedaron marcadas (las de «se retiró» no se pagan).
create or replace function fn_pruebas_cierres_recientes(p_horas integer default 48)
returns table (
  prueba_id       uuid,
  persona_id      uuid,
  nombres         text,
  apellidos       text,
  sede_codigo     text,
  resultado       text,
  motivo          text,
  decidida_por    text,
  cerrada_at      timestamptz,
  cerrada_fecha   date,
  dias_trabajados integer,
  horas_marcadas  numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select pr.id,
         p.id,
         p.nombres,
         p.apellidos,
         s.codigo,
         pr.resultado,
         pr.motivo,
         d.nombres || ' ' || d.apellidos,
         pr.cerrada_at,
         pr.cerrada_fecha,
         fn_prueba_dias_trabajados(p.id, pr.inicio, pr.cerrada_fecha),
         coalesce((select sum(j.horas_trabajadas) from jornadas j
                    where j.persona_id = p.id and j.fecha >= pr.inicio and j.fecha <= pr.cerrada_fecha), 0)
    from pruebas pr
    join personas p on p.id = pr.persona_id
    left join personas d on d.id = pr.cerrada_por
    left join sedes s on s.id = p.sede_base_id
   where pr.resultado in ('no_apto', 'retirado')
     and pr.cerrada_at >= now() - make_interval(hours => least(greatest(coalesce(p_horas, 48), 1), 720))
     and fn_prueba_puede_actuar(p.id) is true
   order by pr.cerrada_at desc, pr.id;
$$;

revoke execute on function fn_pruebas_cierres_recientes(integer) from public, anon;
grant  execute on function fn_pruebas_cierres_recientes(integer) to authenticated;

comment on function fn_pruebas_cierres_recientes(integer) is
  'Pruebas cerradas como «no apto» o «se retiró» en las últimas N horas (1 a 720, por defecto 48), con quién decidió, el motivo y las horas marcadas (0538). '
  'Las ve DO (todas) y la líder (las de su sede).';

-- ── Cómo se comprueba que entró ──────────────────────────────────────────────
select
  case
    when (select prosrc from pg_proc where proname = 'fn_solicitud_perfil_puede_escribir') like '%CAMBIO 0538%'
     and to_regprocedure('fn_prueba_cargar_dni(uuid, text, text, text)') is not null
     and to_regprocedure('fn_pruebas_cierres_recientes(integer)') is not null
     and has_function_privilege('authenticated', 'fn_prueba_cargar_dni(uuid, text, text, text)', 'execute')
      then '✅ quien registra la prueba puede subir el DNI, y se ven los cierres recientes'
    else '❌ no entró completo'
  end as resultado;

insert into migraciones_aplicadas (numero, nombre)
values (538, 'el_dni_de_quien_esta_de_prueba_lo_sube_quien_lo_registra')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
