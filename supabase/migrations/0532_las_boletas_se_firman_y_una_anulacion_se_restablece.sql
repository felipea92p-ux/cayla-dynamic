-- ============================================================================
-- 0532 — Las boletas se firman, DO ve la firma, y una anulación se restablece en 48 horas
-- ============================================================================
--
-- ── QUÉ PROMETE ──────────────────────────────────────────────────────────────
--
-- Tres cosas, sobre las boletas oficiales de la 0482:
--
--  1. LA PERSONA FIRMA SU BOLETA. «Confirmar que la recibí» deja de existir:
--     se da por recibida una boleta FIRMÁNDOLA, con la firma que la persona ya
--     tiene guardada en Mi perfil → Firma (`firmas_escaneadas`). La imagen se
--     COPIA en la boleta al firmar, igual que el memo (0408) y el contrato
--     (0398): si después cambia su firma, esta boleta conserva la que usó ese
--     día. Sigue exigiendo haberla abierto antes: firmar sin verla no dice nada.
--     Firmar es obligatorio (decisión de Felipe, 2026-10-17): la salida para
--     quien no tiene cuenta o no puede firmar es «Entregada en papel», que ya
--     existía.
--
--  2. DO VE LA BOLETA CON SU FIRMA. `fn_boleta_constancia` devuelve la imagen
--     de la firma, quién y cuándo, para mostrar la boleta con su constancia.
--
--  3. DO PUEDE ANULAR UNA BOLETA YA APROBADA Y RESTABLECERLA DURANTE 48 HORAS.
--     Anular ya existía (0482, con motivo de 5 letras y rastro en
--     `correcciones_auditoria`) pero era definitivo. Ahora guarda en qué estado
--     estaba (`estado_previo`) y deja una fila en `boletas_anulaciones`, el
--     historial de anulaciones. `fn_boleta_restablecer` devuelve la boleta
--     EXACTAMENTE como estaba —con su firma, porque el acuse cuelga de la versión
--     y anular no lo toca— mientras no hayan pasado 48 horas. Pasado el plazo
--     solo queda subir una boleta nueva.
--
-- ── QUÉ ASUME ────────────────────────────────────────────────────────────────
--
--  · La 0482 (boletas, versiones, partes, acuses) y la 0395 (firmas_escaneadas).
--  · `fn_es_admin_o_lider()` es «DO» (0078); `fn_persona_actual_id()` identifica
--    a quien llama.
--  · Que quien aún no firmó pueda hacerlo en la misma pantalla: si no tiene firma
--    guardada, la pantalla se la hace crear (FirmaEditor) y vuelve a llamar.
--
-- ── POR QUÉ ASÍ, Y NO DE OTRA FORMA ──────────────────────────────────────────
--
--  · LA FIRMA VA EN EL ACUSE, no en `boletas`. El acuse ya cuelga de la VERSIÓN
--    (0482): una firma sobre la versión 1 no cae sobre la 2 sin que la haya visto,
--    y la constancia de lo que sí firmó no se borra cuando cambian el documento.
--    Es el mismo razonamiento que la 0482 ya había escrito para «recibí».
--
--  · «RECIBIDA» EXIGE FIRMA, Y LO DICE UN TRIGGER, no un CHECK. Un CHECK
--    `recibida_at is null or firma is not null`, aunque sea NOT VALID, se vuelve a
--    evaluar cuando una fila vieja se actualiza (p. ej. `fn_boleta_partes` hace
--    `on conflict do update` sobre `vista_at`) y rompería a quien ya había
--    confirmado antes de esta migración. El trigger solo mira la TRANSICIÓN:
--    quien confirmó antes queda como estaba («Confirmada», sin firma) y nadie
--    puede dar una boleta por recibida sin firmarla desde ahora.
--
--  · LA ANULACIÓN SE RESTABLECE POR `estado_previo`, no por una «papelera». La
--    boleta no cambia de lugar ni se copia: solo cambia su estado y se acuerda
--    del anterior. Los archivos (Storage) y las versiones nunca se tocaron, y el
--    acuse tampoco, así que restablecer no puede perder nada.
--
--  · EL HISTORIAL ES UNA TABLA APARTE (`boletas_anulaciones`, solo se agrega).
--    `boletas.anulada_*` guarda solo la anulación VIGENTE y se pisa en la
--    siguiente; con anular → restablecer → anular, la primera se perdería.
--
--  · LAS 48 HORAS SE MIDEN DESDE `anulada_at`, con el reloj de la base. Pasado
--    el plazo `fn_boleta_restablecer` se niega con un mensaje que dice qué hacer.
--    Si entre tanto DO subió una versión nueva, la boleta ya volvió a «borrador»
--    (0482) y tampoco se puede restablecer: no hay nada que restablecer.
--
--  · LA PERSONA VE «EN REVISIÓN», sin el motivo. `fn_mis_boletas` ahora devuelve
--    también las anuladas, SIN versión ni archivos (`fn_boleta_puede_ver` ya
--    exigía `publicada`), para que la pantalla no diga «todavía no hay boleta»
--    sobre algo que sí existió. Sin aviso: se decidió no avisar.
--
--  · «CONFIRMAR QUE LA RECIBÍ» NO SE BORRA, SE RETIRA: la función sigue
--    existiendo y responde un error que dice qué hacer. Borrarla dejaría a un
--    navegador con la pantalla vieja abierta llamando a algo inexistente; así
--    ve un mensaje legible.
--
-- ── LO QUE ESTO NO ES ────────────────────────────────────────────────────────
--
--  No es firma digital certificada: es una constancia de recepción con fecha y
--  hora, del mismo valor que la del memo. Conviene que el contador confirme que
--  le basta para dejar el papel (ver docs/consulta-boletas-de-pago.md, PR #450).
--
-- ── MD5 DE PARTIDA ───────────────────────────────────────────────────────────
--
-- Esta migración reescribe seis funciones y NO SE FÍA de que producción tenga los
-- cuerpos de los que se copió: lo comprueba abajo y ABORTA sin tocar nada si
-- alguna es otra (el accidente de la 0276 y de la 0293). Acepta el md5 tal cual,
-- el md5 sin comentarios y los dos con los retornos de carro de pegar desde
-- Windows (la 0401). Las versiones vigentes, según donde-vive.sh el 2026-10-17:
--
--   fn_boleta_guardar_version     0482_las_boletas_oficiales_se_suben_y_se_publican.sql
--   fn_boleta_anular              0482_las_boletas_oficiales_se_suben_y_se_publican.sql
--   fn_boleta_confirmar_recibo    0482_las_boletas_oficiales_se_suben_y_se_publican.sql
--   fn_boletas_acuses_guardian    0482_las_boletas_oficiales_se_suben_y_se_publican.sql
--   fn_boletas_tablero            0491_la_planilla_y_las_listas_dejan_fuera_a_las_cuentas_de_servicio.sql
--   fn_mis_boletas                0482_las_boletas_oficiales_se_suben_y_se_publican.sql
--
-- OJO: el PR #450 modifica la propia 0482 (ya pegada en producción). Si se
-- fusiona antes que esta, hay que volver a medir con donde-vive.sh.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--
--   Volver a pegar cada función desde la migración de la lista de arriba, y:
--     drop function if exists fn_boleta_firmar(uuid), fn_boleta_constancia(uuid),
--       fn_boleta_restablecer(uuid), fn_boleta_anulaciones(uuid);
--     drop table if exists boletas_anulaciones;
--     alter table boletas drop column if exists estado_previo;
--     alter table boletas_acuses drop constraint if exists acuse_firma_formato,
--       drop constraint if exists acuse_firma_exige_recibida, drop column if exists firma;
--   Ojo: borrar `firma` destruye las firmas ya puestas.
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================


-- ── 0 · EL FRENO ─────────────────────────────────────────────────────────────
do $freno$
declare
  v_fn    text;
  v_tal   text;
  v_sin   text;
  v_falla text := '';
begin
  if to_regclass('public.boletas_acuses') is null then
    raise exception 'FALTA LA 0482. Las tablas de boletas no existen; pégala antes que esta.';
  end if;
  if to_regclass('public.firmas_escaneadas') is null then
    raise exception 'FALTA LA 0065/0395. firmas_escaneadas no existe; pégala antes que esta.';
  end if;

  if exists (select 1 from migraciones_aplicadas
              where numero = 532
                and nombre = 'las_boletas_se_firman_y_una_anulacion_se_restablece') then
    raise notice '0532 ya estaba aplicada: no se comprueban los md5 de partida.';
    return;
  end if;

  for v_fn, v_tal, v_sin in
    select * from (values
      ('fn_boleta_guardar_version',  '05d02abd3bf8ec3438fd3736329703d8', 'b9f566fd7bbf932178c301fb70ad6427'),   -- 5747 caracteres
      ('fn_boleta_anular',           '12bc97b0e8018c5e7570e8163aea193c', '12bc97b0e8018c5e7570e8163aea193c'),   -- 1115 caracteres
      ('fn_boleta_confirmar_recibo', '877fbf319a81f5c26f2cc9d58101c7b8', 'ad3e27ab15fe5a54d401ed076425b15c'),   -- 1514 caracteres
      ('fn_boletas_acuses_guardian', '13973f61ffb457aa6a54840941d61046', '13973f61ffb457aa6a54840941d61046'),   -- 637 caracteres
      ('fn_boletas_tablero',         '1a56fc4c414185c14fb4e505032dbea3', '9f15528113e9d04e89d5e7c2c128fb87'),   -- 1522 caracteres
      ('fn_mis_boletas',             'b61743722a2ca53f349941b3e7de6762', 'b61743722a2ca53f349941b3e7de6762')    -- 1263 caracteres
    ) as t(fn, tal_cual, sin_comentarios)
  loop
    if not exists (
      select 1
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
             lateral (values (p.prosrc), (replace(p.prosrc, chr(13), ''))) as v(src)
       where n.nspname = 'public' and p.proname = v_fn
         and (md5(v.src) = v_tal
              or md5(array_to_string(array(
                   select regexp_replace(l, '[[:space:]]*--.*$', '')
                   from unnest(string_to_array(v.src, chr(10))) as l
                   where btrim(l) not like '--%'
                 ), chr(10))) = v_sin))
    then
      v_falla := v_falla || '  · ' || v_fn || chr(10);
    end if;
  end loop;

  if v_falla <> '' then
    raise exception E'PARA. Producción no tiene el cuerpo del que se copió esta migración:\n%\nPegarla revertiría en silencio lo que haya entre medias. Corre ./scripts/donde-vive.sh sobre cada una, mide dónde está la diferencia y reconstruye desde la versión de producción.', v_falla;
  end if;
end
$freno$;


-- ── 1 · La firma, en el acuse ────────────────────────────────────────────────
alter table boletas_acuses add column if not exists firma text;

alter table boletas_acuses drop constraint if exists acuse_firma_formato;
alter table boletas_acuses add constraint acuse_firma_formato
  check (firma is null or firma ~ '^data:image/(png|jpeg);base64,');

-- Una firma sin «recibida» no existe: se escriben juntas, en la misma sentencia.
alter table boletas_acuses drop constraint if exists acuse_firma_exige_recibida;
alter table boletas_acuses add constraint acuse_firma_exige_recibida
  check (firma is null or recibida_at is not null);

comment on column boletas_acuses.firma is
  'Copia de la firma de la persona (data URL) al firmar la boleta. Fija desde que se escribe: si cambia su firma después, esta no cambia. NULL en las confirmaciones anteriores a la 0532.';


-- ── 2 · El guardián del acuse, ahora con la firma ────────────────────────────
-- Molde de campo sensible (0261, 0295, 0342): solo el sistema escribe. Se suma:
--  · dar una boleta por recibida exige la firma, en la misma escritura;
--  · la firma, una vez puesta, no se cambia ni se quita;
--  · a quien confirmó antes de la 0532 no se le agrega una firma después.
create or replace function fn_boletas_acuses_guardian()
returns trigger language plpgsql as $$
begin
  if current_user <> 'postgres' then
    raise exception 'Una confirmación de recepción solo se escribe desde el sistema.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Una confirmación de recepción no se borra.';
  end if;
  if tg_op = 'INSERT' or old.recibida_at is null then
    if new.recibida_at is not null and new.firma is null then
      raise exception 'Una boleta se da por recibida firmándola.';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    if old.vista_at is not null and new.vista_at is distinct from old.vista_at then
      raise exception 'La fecha de la primera apertura no se corre.';
    end if;
    if old.recibida_at is not null and new.recibida_at is distinct from old.recibida_at then
      raise exception 'La fecha de la confirmación no se corre.';
    end if;
    if old.firma is not null and new.firma is distinct from old.firma then
      raise exception 'La firma de una boleta no se cambia ni se quita.';
    end if;
    if old.firma is null and new.firma is not null and old.recibida_at is not null then
      raise exception 'Esa boleta se confirmó antes de que hubiera firma: no se le agrega después.';
    end if;
  end if;
  return new;
end;
$$;


-- ── 3 · Anular guarda en qué estado estaba ───────────────────────────────────
alter table boletas add column if not exists estado_previo text;

alter table boletas drop constraint if exists boleta_estado_previo_valido;
alter table boletas add constraint boleta_estado_previo_valido
  check (estado_previo is null or estado_previo in ('borrador', 'publicada', 'papel'));

comment on column boletas.estado_previo is
  'Solo mientras está anulada: el estado al que vuelve si DO la restablece dentro de las 48 horas.';

create table if not exists boletas_anulaciones (
  id               uuid primary key default gen_random_uuid(),
  boleta_id        uuid not null references boletas(id),
  anulada_at       timestamptz not null default now(),
  anulada_por      uuid not null references personas(id),
  motivo           text not null check (char_length(btrim(motivo)) >= 5),
  -- Null solo en las anulaciones anteriores a la 0532: no se sabe a qué volvería.
  estado_previo    text check (estado_previo is null or estado_previo in ('borrador', 'publicada', 'papel')),
  restablecida_at  timestamptz,
  restablecida_por uuid references personas(id),
  constraint anulacion_restablecida_completa check ((restablecida_at is null) = (restablecida_por is null)),
  constraint anulacion_restablecida_despues check (restablecida_at is null or restablecida_at >= anulada_at)
);

create index if not exists idx_boletas_anulaciones_boleta on boletas_anulaciones (boleta_id, anulada_at desc);

comment on table boletas_anulaciones is
  'Historial de anulaciones de una boleta: quién, cuándo y por qué, y si se restableció. Solo se agrega; lo único que cambia es restablecida_* (null → valor, una vez).';

-- Las boletas que ya estaban anuladas entran al historial (no se sabe a qué
-- volverían, así que no se podrán restablecer).
insert into boletas_anulaciones (boleta_id, anulada_at, anulada_por, motivo)
select b.id, b.anulada_at, b.anulada_por, b.anulada_motivo
  from boletas b
 where b.estado = 'anulada'
   and not exists (select 1 from boletas_anulaciones a where a.boleta_id = b.id);

create or replace function fn_boletas_anulaciones_guardian()
returns trigger language plpgsql as $$
begin
  if current_user <> 'postgres' then
    raise exception 'Una anulación solo se escribe desde el sistema.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Una anulación no se borra: queda en el historial.';
  end if;
  if tg_op = 'UPDATE' then
    if new.boleta_id is distinct from old.boleta_id
       or new.anulada_at is distinct from old.anulada_at
       or new.anulada_por is distinct from old.anulada_por
       or new.motivo is distinct from old.motivo
       or new.estado_previo is distinct from old.estado_previo then
      raise exception 'Una anulación no se edita.';
    end if;
    if old.restablecida_at is not null
       and (new.restablecida_at is distinct from old.restablecida_at
            or new.restablecida_por is distinct from old.restablecida_por) then
      raise exception 'Una anulación restablecida no se vuelve a cambiar.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists boletas_anulaciones_guardian on boletas_anulaciones;
create trigger boletas_anulaciones_guardian
  before insert or update or delete on boletas_anulaciones
  for each row execute function fn_boletas_anulaciones_guardian();

alter table boletas_anulaciones enable row level security;
drop policy if exists boletas_anulaciones_select_do on boletas_anulaciones;
create policy boletas_anulaciones_select_do on boletas_anulaciones
  for select to authenticated using (fn_es_admin_o_lider() is true);
revoke all on boletas_anulaciones from anon, authenticated, public;
grant select on boletas_anulaciones to authenticated;


-- ── 4 · DO anula (ahora se acuerda de cómo estaba) ───────────────────────────
-- El motivo sigue siendo obligatorio (5 letras) y queda en `correcciones_auditoria`
-- y en el historial. Los archivos y el acuse no se tocan.
create or replace function fn_boleta_anular(p_boleta_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_b     boletas%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede anular boletas.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado junto a la boleta.';
  end if;

  select * into v_b from boletas b where b.id = p_boleta_id for update;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;
  if v_b.estado = 'anulada' then
    raise exception 'Esa boleta ya está anulada.';
  end if;

  update boletas
     set estado = 'anulada', estado_previo = v_b.estado,   -- CAMBIO 0532
         anulada_at = now(), anulada_por = v_quien,
         anulada_motivo = btrim(p_motivo)
   where id = p_boleta_id;

  insert into boletas_anulaciones (boleta_id, anulada_at, anulada_por, motivo, estado_previo)   -- CAMBIO 0532
  values (p_boleta_id, now(), v_quien, btrim(p_motivo), v_b.estado);

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (v_b.persona_id, 'boletas.estado', v_b.estado, 'anulada', btrim(p_motivo), v_quien);
end;
$fn$;


-- ── 5 · DO restablece, dentro de las 48 horas ────────────────────────────────
create or replace function fn_boleta_restablecer(p_boleta_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_b     boletas%rowtype;
  v_grupo text;
  v_id    uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede restablecer una boleta.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select * into v_b from boletas b where b.id = p_boleta_id for update;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;
  if v_b.estado <> 'anulada' then
    raise exception 'Esa boleta no está anulada.';
  end if;
  if v_b.estado_previo is null then
    raise exception 'Esta anulación es anterior al plazo de restablecer: sube una boleta nueva.';
  end if;
  if now() >= v_b.anulada_at + interval '48 hours' then
    raise exception 'Pasaron más de 48 horas desde que se anuló: ya no se puede restablecer. Sube una boleta nueva.';
  end if;

  -- Lo mismo que exige publicar: si el grupo se reabrió entre tanto, el periodo
  -- dejó de estar cerrado y su boleta oficial no se vuelve a mostrar.
  select p.tipo_vinculo into v_grupo from personas p where p.id = v_b.persona_id;
  if not exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = v_b.periodo_id and g.grupo = v_grupo and g.estado = 'pagado') then
    raise exception 'El periodo de esa persona se reabrió: no se puede restablecer su boleta.';
  end if;
  if v_b.estado_previo in ('borrador', 'publicada')
     and not exists (select 1 from boletas_versiones v where v.boleta_id = v_b.id) then
    raise exception 'Esa boleta no tiene hojas: no hay nada que restablecer.';
  end if;

  update boletas
     set estado = v_b.estado_previo, estado_previo = null,
         anulada_at = null, anulada_por = null, anulada_motivo = null
   where id = p_boleta_id;

  select a.id into v_id from boletas_anulaciones a
   where a.boleta_id = p_boleta_id and a.restablecida_at is null
   order by a.anulada_at desc, a.id desc limit 1;
  if v_id is not null then
    update boletas_anulaciones set restablecida_at = now(), restablecida_por = v_quien where id = v_id;
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (v_b.persona_id, 'boletas.estado', 'anulada', v_b.estado_previo,
          'Anulación restablecida dentro de las 48 horas', v_quien);
end;
$fn$;


-- ── 6 · El historial de anulaciones de una boleta ────────────────────────────
create or replace function fn_boleta_anulaciones(p_boleta_id uuid)
returns table (
  id uuid, anulada_at timestamptz, anulada_por text, motivo text, estado_previo text,
  restablecida_at timestamptz, restablecida_por text, restablecible_hasta timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve el historial de una boleta.';
  end if;

  return query
  select a.id, a.anulada_at,
         btrim(pa.nombres || ' ' || pa.apellidos),
         a.motivo, a.estado_previo, a.restablecida_at,
         case when pr.id is null then null else btrim(pr.nombres || ' ' || pr.apellidos) end,
         -- Solo la anulación VIGENTE se puede restablecer, y mientras corre el plazo.
         case when b.estado = 'anulada' and b.estado_previo is not null
                   and a.restablecida_at is null and a.anulada_at = b.anulada_at
              then a.anulada_at + interval '48 hours' end
    from boletas_anulaciones a
    join boletas b on b.id = a.boleta_id
    join personas pa on pa.id = a.anulada_por
    left join personas pr on pr.id = a.restablecida_por
   where a.boleta_id = p_boleta_id
   order by a.anulada_at desc, a.id desc;
end;
$fn$;


-- ── 7 · La persona firma ─────────────────────────────────────────────────────
-- Solo la dueña, solo de la versión VIGENTE y publicada, solo si ya la abrió, y
-- con la firma que tiene guardada. Idempotente: si ya firmó, la firma y la fecha
-- de la primera vez no se mueven.
create or replace function fn_boleta_firmar(p_version_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_persona uuid;
  v_estado  text;
  v_vigente boolean;
  v_firma   text;
begin
  if v_yo is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select b.persona_id, b.estado,
         (v.n = (select max(v2.n) from boletas_versiones v2 where v2.boleta_id = b.id))
    into v_persona, v_estado, v_vigente
    from boletas_versiones v
    join boletas b on b.id = v.boleta_id
   where v.id = p_version_id;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;
  if v_persona <> v_yo then
    raise exception 'Esa boleta no es tuya.';
  end if;
  if v_estado <> 'publicada' then
    raise exception 'Esa boleta no está disponible.';
  end if;
  if not v_vigente then
    raise exception 'Tu boleta se actualizó: ábrela de nuevo antes de firmar.';
  end if;

  -- Firmar exige haberla ABIERTO: la primera apertura la escribe `fn_boleta_partes`.
  if not exists (select 1 from boletas_acuses a
                  where a.version_id = p_version_id and a.vista_at is not null) then
    raise exception 'Ábrela con «Ver» antes de firmarla.';
  end if;

  select f.imagen into v_firma from firmas_escaneadas f where f.persona_id = v_yo;
  if v_firma is null then
    raise exception 'Todavía no tienes una firma guardada: créala y vuelve a firmar.';
  end if;
  if v_firma !~ '^data:image/(png|jpeg);base64,' then
    raise exception 'Tu firma guardada no tiene un formato válido: vuelve a guardarla.';
  end if;

  update boletas_acuses
     set recibida_at = now(), firma = v_firma
   where version_id = p_version_id and recibida_at is null;
end;
$fn$;


-- «Confirmar que la recibí» se retira: ahora se firma. La función sigue
-- existiendo para que una pantalla vieja, abierta antes de publicar el cambio,
-- reciba un mensaje legible y no un error de «función inexistente».
create or replace function fn_boleta_confirmar_recibo(p_version_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
begin
  raise exception 'Las boletas ahora se firman: recarga la página y usa «Firmar».';
end;
$fn$;


-- ── 8 · La constancia: la firma, quién y cuándo ──────────────────────────────
-- DO ve la de cualquier boleta; la persona, solo la de su boleta publicada.
create or replace function fn_boleta_constancia(p_version_id uuid)
returns table (version_id uuid, vista_at timestamptz, recibida_at timestamptz, firma text)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_persona uuid;
  v_estado  text;
begin
  select b.persona_id, b.estado into v_persona, v_estado
    from boletas_versiones v join boletas b on b.id = v.boleta_id
   where v.id = p_version_id;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;
  if fn_es_admin_o_lider() is not true
     and not (v_yo is not null and v_persona = v_yo and v_estado = 'publicada') then
    raise exception 'Esa boleta no está disponible.';
  end if;

  return query
  select a.version_id, a.vista_at, a.recibida_at, a.firma
    from boletas_acuses a where a.version_id = p_version_id;
end;
$fn$;


-- ── 9 · DO mira el periodo (con la firma y las anulaciones) ──────────────────
-- Las columnas nuevas van al final. Cambia el tipo de lo que devuelve, así que
-- hay que borrar la función y crearla de nuevo (Postgres no deja agregarle
-- columnas con create or replace). Conserva la condición de la 0491.
drop function if exists fn_boletas_tablero(uuid);
create function fn_boletas_tablero(p_periodo_id uuid)
returns table (
  persona_id uuid, nombre text, cargo text, sede_codigo text, tipo_vinculo text,
  tiene_cuenta boolean, grupo_pagado boolean,
  boleta_id uuid, estado text,
  version_id uuid, version_n int, tipo text, n_partes int, bytes bigint, actualizada boolean,
  publicada_at timestamptz, vista_at timestamptz, recibida_at timestamptz,
  firmada boolean, anulada_at timestamptz, anulada_motivo text, restablecible_hasta timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve las boletas de todos.';
  end if;

  return query
  select pe.id,
         btrim(pe.nombres || ' ' || pe.apellidos),
         pe.cargo,
         s.codigo,
         pe.tipo_vinculo,
         (pe.auth_user_id is not null),
         exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = p_periodo_id and g.grupo = pe.tipo_vinculo and g.estado = 'pagado'),
         b.id,
         coalesce(b.estado, 'falta'),
         v.id, v.n, v.tipo,
         coalesce(x.n_partes, 0)::int,
         coalesce(x.bytes, 0)::bigint,
         coalesce(v.n > 1 and v.avisar and a.recibida_at is null, false),
         b.publicada_at, a.vista_at, a.recibida_at,
         (a.firma is not null),                                           -- CAMBIO 0532
         case when b.estado = 'anulada' then b.anulada_at end,            -- CAMBIO 0532
         case when b.estado = 'anulada' then b.anulada_motivo end,        -- CAMBIO 0532
         case when b.estado = 'anulada' and b.estado_previo is not null
              then b.anulada_at + interval '48 hours' end                 -- CAMBIO 0532
    from personas pe
    join sedes s on s.id = pe.sede_base_id
    left join boletas b on b.periodo_id = p_periodo_id and b.persona_id = pe.id
    left join lateral (
      select vv.id, vv.n, vv.tipo, vv.avisar
        from boletas_versiones vv where vv.boleta_id = b.id
       order by vv.n desc limit 1
    ) v on true
    left join boletas_acuses a on a.version_id = v.id
    left join lateral (
      select count(*) as n_partes, sum(pt.bytes) as bytes
        from boletas_partes pt where pt.version_id = v.id
    ) x on true
   where (pe.estado = 'activo' and not pe.cuenta_de_servicio)   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
      or b.id is not null
   order by pe.nombres, pe.apellidos, pe.id;
end;
$fn$;


-- ── 10 · Lo mío (con la firma, y la anulada como «en revisión») ──────────────
drop function if exists fn_mis_boletas();
create function fn_mis_boletas()
returns table (
  periodo_id uuid, fecha_ini date, fecha_fin date,
  boleta_id uuid, estado text,
  version_id uuid, version_n int, tipo text, n_partes int, bytes bigint, actualizada boolean,
  publicada_at timestamptz, vista_at timestamptz, recibida_at timestamptz,
  firmada boolean
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_yo    uuid := fn_persona_actual_id();
  v_grupo text;
begin
  if v_yo is null then
    return;
  end if;
  select p.tipo_vinculo into v_grupo from personas p where p.id = v_yo;

  -- Una boleta anulada sale como «anulada», SIN versión ni archivos ni fechas:
  -- la pantalla dice «en revisión». Los borradores siguen sin salir.
  return query
  select pe.id, pe.fecha_ini, pe.fecha_fin,
         b.id, b.estado,
         case when b.estado = 'anulada' then null else v.id end,
         case when b.estado = 'anulada' then null else v.n end,
         case when b.estado = 'anulada' then null else v.tipo end,
         case when b.estado = 'anulada' then 0 else coalesce(x.n_partes, 0)::int end,
         case when b.estado = 'anulada' then 0 else coalesce(x.bytes, 0)::bigint end,
         case when b.estado = 'anulada' then false
              else coalesce(v.n > 1 and v.avisar and a.recibida_at is null, false) end,
         case when b.estado = 'anulada' then null else b.publicada_at end,
         case when b.estado = 'anulada' then null else a.vista_at end,
         case when b.estado = 'anulada' then null else a.recibida_at end,
         (b.estado <> 'anulada' and a.firma is not null)                                  -- CAMBIO 0532
    from periodos_planilla pe
    left join boletas b
           on b.periodo_id = pe.id and b.persona_id = v_yo and b.estado in ('publicada', 'papel', 'anulada')
    left join lateral (
      select vv.id, vv.n, vv.tipo, vv.avisar
        from boletas_versiones vv where vv.boleta_id = b.id
       order by vv.n desc limit 1
    ) v on true
    left join boletas_acuses a on a.version_id = v.id
    left join lateral (
      select count(*) as n_partes, sum(pt.bytes) as bytes
        from boletas_partes pt where pt.version_id = v.id
    ) x on true
   where b.id is not null
      or exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = pe.id and g.grupo = v_grupo and g.estado = 'pagado')
   order by pe.fecha_ini desc, pe.id
   limit 36;
end;
$fn$;


-- ── 11 · Subir una versión (con la firma heredada) ───────────────────────────
-- El único cambio es de dos líneas, marcadas CAMBIO 0532: cuando solo se
-- reordenaron las hojas y DO decide no avisar, la versión nueva hereda la
-- constancia de la anterior, y ahora la constancia incluye la firma. Una
-- confirmación anterior a la 0532 (sin firma) NO se hereda como «recibida»: ya no
-- vale como recepción, y copiarla chocaría con el guardián.
create or replace function fn_boleta_guardar_version(
  p_periodo_id uuid,
  p_persona_id uuid,
  p_tipo       text,
  p_partes     jsonb,
  p_avisar     boolean default true,
  p_nota       text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien   uuid := fn_persona_actual_id();
  v_grupo   text;
  v_boleta  boletas%rowtype;
  v_vig     boletas_versiones%rowtype;
  v_hay_vig boolean;
  v_version uuid;
  v_n       int;
  v_paths   text[];
  v_old     text[];
  v_total   bigint;
  v_cuantas int;
  v_mal     int;
  v_mismo   boolean;
  v_avisa   boolean;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede subir boletas.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_tipo is null or p_tipo not in ('imagen', 'pdf') then
    raise exception 'El tipo de boleta tiene que ser «imagen» o «pdf».';
  end if;
  if p_partes is null or jsonb_typeof(p_partes) <> 'array' or jsonb_array_length(p_partes) = 0 then
    raise exception 'Agrega al menos una foto o un PDF.';
  end if;
  if jsonb_array_length(p_partes) > 1000 then
    raise exception 'Son demasiadas hojas para una sola boleta.';
  end if;

  select p.tipo_vinculo into v_grupo from personas p where p.id = p_persona_id;
  if not found then
    raise exception 'Esa persona no existe.';
  end if;
  -- Sin fila en periodo_grupo_pago = no pagado (0323 midió cero casos de fila ausente).
  if not exists (select 1 from periodo_grupo_pago g
                  where g.periodo_id = p_periodo_id and g.grupo = v_grupo and g.estado = 'pagado') then
    raise exception 'Ese periodo todavía no está pagado para el grupo de esa persona: la boleta oficial se sube cuando cierra.';
  end if;

  -- Una sola fila por (periodo, persona) y con candado: dos DO subiendo la misma
  -- boleta a la vez se ordenan, no se pisan.
  insert into boletas (periodo_id, persona_id, creada_por)
  values (p_periodo_id, p_persona_id, v_quien)
  on conflict (periodo_id, persona_id) do nothing;
  select * into v_boleta from boletas b
   where b.periodo_id = p_periodo_id and b.persona_id = p_persona_id for update;

  if v_boleta.estado = 'papel' then
    raise exception 'Esa boleta está anotada como entregada en papel. Anúlala antes de subir una digital.';
  end if;

  -- Cada hoja: ruta con el prefijo de ESTA persona y periodo, sin repetirse, y
  -- que exista en Storage. El peso y el tipo salen de Storage, no del cliente.
  select array_agg(e.item->>'path' order by e.ord), count(*)
    into v_paths, v_cuantas
    from jsonb_array_elements(p_partes) with ordinality as e(item, ord);

  if exists (select 1 from unnest(v_paths) as r(path)
              where r.path is null
                 or r.path !~ ('^' || p_periodo_id::text || '/' || p_persona_id::text || '/[0-9a-f-]{36}\.[a-z0-9]{2,5}$')) then
    raise exception 'Una de las hojas no corresponde a esta persona y periodo.';
  end if;
  if (select count(distinct r.path) from unnest(v_paths) as r(path)) <> v_cuantas then
    raise exception 'Hay una hoja repetida.';
  end if;

  select coalesce(sum((o.metadata->>'size')::bigint), 0),
         count(*),
         count(*) filter (where not coalesce(
              (p_tipo = 'imagen' and o.metadata->>'mimetype' like 'image/%')
           or (p_tipo = 'pdf'    and o.metadata->>'mimetype' = 'application/pdf'), false))
    into v_total, v_n, v_mal
    from storage.objects o
   where o.bucket_id = 'boletas' and o.name = any(v_paths);

  if v_n <> v_cuantas then
    raise exception 'Una de las hojas no llegó al almacén. Vuelve a subirla.';
  end if;
  if v_mal > 0 then
    raise exception 'Todas las hojas de una boleta tienen que ser del mismo tipo (fotos o PDF).';
  end if;
  if v_total > 524288000 then
    raise exception 'La boleta pasa el tope de 500 MB. Quita alguna hoja.';
  end if;

  -- La versión vigente, si la hay. `n` es único por boleta: el orden es total.
  select * into v_vig from boletas_versiones v
   where v.boleta_id = v_boleta.id order by v.n desc limit 1;
  v_hay_vig := found;
  v_avisa := true;

  if v_hay_vig then
    select array_agg(pt.storage_path order by pt.orden) into v_old
      from boletas_partes pt where pt.version_id = v_vig.id;
    if v_old = v_paths and v_vig.tipo = p_tipo and v_boleta.estado <> 'anulada' then
      raise exception 'No hiciste ningún cambio: agrega, quita o reordena alguna hoja.';
    end if;
    v_mismo := v_vig.tipo = p_tipo
      and (select array_agg(x order by x) from unnest(v_old) as x)
        = (select array_agg(x order by x) from unnest(v_paths) as x);
    if v_boleta.estado = 'publicada' then
      -- Solo se puede NO avisar si el contenido es el mismo (solo se reordenó).
      v_avisa := coalesce(p_avisar, true) or not coalesce(v_mismo, false);
    end if;
  end if;

  v_n := coalesce(v_vig.n, 0) + 1;
  insert into boletas_versiones (boleta_id, n, tipo, avisar, nota, creada_por)
  values (v_boleta.id, v_n, p_tipo, v_avisa, nullif(btrim(p_nota), ''), v_quien)
  returning id into v_version;

  insert into boletas_partes (version_id, tipo, orden, storage_path, mime, bytes)
  select v_version, p_tipo, e.ord::int, e.item->>'path',
         o.metadata->>'mimetype', (o.metadata->>'size')::bigint
    from jsonb_array_elements(p_partes) with ordinality as e(item, ord)
    join storage.objects o on o.bucket_id = 'boletas' and o.name = e.item->>'path';

  -- Sin aviso: la constancia de la versión anterior sigue valiendo para esta.
  if v_hay_vig and v_boleta.estado = 'publicada' and not v_avisa then
    insert into boletas_acuses (version_id, vista_at, recibida_at, firma)
    select v_version, a.vista_at,
           case when a.firma is not null then a.recibida_at end,   -- CAMBIO 0532: sin firma no hay «recibida»
           a.firma                                                  -- CAMBIO 0532
      from boletas_acuses a where a.version_id = v_vig.id;
  end if;

  -- Una anulada que se vuelve a subir arranca otra vez como borrador.
  if v_boleta.estado = 'anulada' then
    update boletas set estado = 'borrador', estado_previo = null where id = v_boleta.id;   -- CAMBIO 0532: ya no se puede restablecer
  end if;

  return v_version;
end;
$fn$;


-- ── 12 · Permisos ────────────────────────────────────────────────────────────
-- Lo que se borró y se creó de nuevo pierde sus permisos: se concede otra vez.
-- Las funciones nuevas siguen la regla de la 0482: nada para anon ni public.
grant execute on function
  fn_boleta_firmar(uuid),
  fn_boleta_constancia(uuid),
  fn_boleta_restablecer(uuid),
  fn_boleta_anulaciones(uuid),
  fn_boleta_anular(uuid, text),
  fn_boleta_confirmar_recibo(uuid),
  fn_boleta_guardar_version(uuid, uuid, text, jsonb, boolean, text),
  fn_boletas_tablero(uuid),
  fn_mis_boletas()
to authenticated;
revoke execute on function
  fn_boleta_firmar(uuid),
  fn_boleta_constancia(uuid),
  fn_boleta_restablecer(uuid),
  fn_boleta_anulaciones(uuid),
  fn_boleta_anular(uuid, text),
  fn_boleta_confirmar_recibo(uuid),
  fn_boleta_guardar_version(uuid, uuid, text, jsonb, boolean, text),
  fn_boletas_tablero(uuid),
  fn_mis_boletas()
from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (532, 'las_boletas_se_firman_y_una_anulacion_se_restablece')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────────
-- Cuatro funciones nuevas y las columnas de firma; el registro tiene que ser el
-- de esta migración (si dice otro nombre, alguien más tenía el 532).
select
  (select count(*) from pg_proc where proname in
     ('fn_boleta_firmar','fn_boleta_constancia','fn_boleta_restablecer','fn_boleta_anulaciones')) as funciones_nuevas_de_4,
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'boletas_acuses' and column_name = 'firma') as columna_firma,
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'boletas' and column_name = 'estado_previo') as columna_estado_previo,
  (select count(*) from pg_class where relname = 'boletas_anulaciones' and relrowsecurity) as historial_con_rls,
  (select count(*) from pg_proc where proname = 'fn_boletas_tablero' and position('CAMBIO 0532' in prosrc) > 0) as tablero_nuevo,
  (select count(*) from pg_proc where proname = 'fn_mis_boletas' and position('CAMBIO 0532' in prosrc) > 0) as mis_boletas_nuevo,
  (select count(*) from pg_proc where proname = 'fn_boleta_guardar_version' and position('CAMBIO 0532' in prosrc) > 0) as guardar_version_nuevo,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 532) as registro;
