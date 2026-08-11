-- ============================================================================
-- 0210_ninguna_sancion_sin_escuchar_antes.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el sistema pueda hacer lo que el Reglamento exige antes de cualquier
--   amonestación o suspensión: comunicar los cargos por escrito, esperar el
--   plazo de descargo, archivar lo que la persona diga y dejar constancia de
--   cómo se valoró. Hoy no puede, y por eso toda amonestación que el sistema
--   produjera sería anulable bajo el propio Reglamento.
--
-- QUÉ ASUME
--   Que la 0206 está aplicada: de ella vienen el tipo de adjunto `descargo` y
--   los estados `resuelto`. Se comprueba sola más abajo.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
-- El artículo 55.2 del Reglamento v4.0 dice, y el 19.3 lo repite para las
-- tardanzas:
--
--     «Antes de imponer una amonestación escrita o una suspensión, la Empresa
--      comunica por escrito los hechos … y le otorga un plazo no menor de dos
--      (2) días hábiles para presentar descargo … El documento permanece como
--      BORRADOR durante ese plazo … La omisión del descargo previo INVALIDA la
--      medida, que en tal caso no se computa como antecedente.»
--
-- El sistema, hoy:
--
--   · No sabe que unos cargos se comunicaron, ni cuándo, ni cuándo vence el
--     plazo. Un borrador es solo «aún no firmado».
--   · `fn_expediente_adjuntar` RECHAZA un descargo que no cuelgue de una
--     imputación entregada (0206). El descargo previo a una amonestación no
--     tiene dónde vivir, así que el legajo probaría que se sancionó y NO que se
--     dejó defenderse.
--   · Nada impide firmar una amonestación el mismo minuto en que se genera.
--
-- ── QUÉ HACE ESTA MIGRACIÓN, Y POR QUÉ ASÍ ──────────────────────────────────
--
-- 1. Dos columnas en el expediente: cuándo se comunicaron los cargos y cuándo
--    vence el plazo. Con eso el borrador deja de ser un estado mudo.
--
-- 2. `fn_expediente_comunicar_cargos` — el acto que abre el plazo. Calcula el
--    vencimiento en DÍAS HÁBILES, no naturales: el Reglamento dice hábiles, y
--    contar corridos acortaría el plazo de quien recibe los cargos un viernes.
--
-- 3. `fn_expediente_firmar` deja de poder firmar una amonestación o una
--    suspensión sin que el plazo se haya comunicado y vencido. La imputación y
--    el despido NO pasan por aquí: tienen su propio procedimiento en el
--    artículo 57, con el plazo del art. 31 de la LPCL.
--
--    ⚠️ Se guarda el md5 de partida del cuerpo que se reemplaza. Si en
--    producción no coincide, PARAR: significa que otra migración la tocó
--    después y copiar de acá revertiría su trabajo en silencio.
--
-- 4. El descargo se puede archivar contra el documento en el que se está
--    defendiendo, sea del nivel que sea, y no solo contra una imputación.
--
-- 5. `fn_expediente_valorar_descargo` — la valoración escrita que el 19.3 exige
--    («indica si fue acogido total o parcialmente y, en caso contrario, por
--    qué»). Sin ella el descargo se archiva y no consta que se leyera.
--
-- ── LO QUE NO HACE ──────────────────────────────────────────────────────────
--
-- No obliga a que el descargo exista. Puede no haberlo: el plazo se da y la
-- persona decide. Lo que se exige es que el plazo se haya DADO y VENCIDO — que
-- es lo que el Reglamento manda y lo único que se puede comprobar.
--
-- Tampoco toca los documentos ya firmados. Los anteriores a esta migración no
-- tienen cargos comunicados y seguirán como están: el Reglamento entra en
-- vigencia con su publicación, no hacia atrás.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Reponiendo el cuerpo anterior de fn_expediente_firmar y de
--   fn_expediente_adjuntar, y quitando las tres funciones y las dos columnas.
--   Revertir significa volver a poder amonestar sin escuchar antes.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Las cinco columnas tienen que decir SÍ.
-- ============================================================================

-- ── 0 · Que la 0206 esté puesta ─────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from migraciones_aplicadas where numero = 206) then
    raise exception 'Falta la 0206: de ella vienen el adjunto de tipo descargo y el estado resuelto. Pégala primero.';
  end if;
end $$;

-- ── 1 · El borrador deja de ser un estado mudo ──────────────────────────────
alter table expediente_disciplinario
  add column if not exists cargos_comunicados_at timestamptz,
  add column if not exists descargo_vence_at     timestamptz,
  add column if not exists descargo_valoracion   text,
  add column if not exists descargo_acogido      text;

comment on column expediente_disciplinario.cargos_comunicados_at is
  'Cuando se comunicaron los cargos a la colaboradora. Abre el plazo del art. 55.2 del RIT.';
comment on column expediente_disciplinario.descargo_vence_at is
  'Cuando vence el plazo de descargo. En dias HABILES desde la comunicacion, nunca menos de dos.';
comment on column expediente_disciplinario.descargo_valoracion is
  'La valoracion escrita que exige el art. 19.3: por que se acogio o por que no.';
comment on column expediente_disciplinario.descargo_acogido is
  'total | parcial | no | sin_descargo. Lo ultimo cuando el plazo vencio sin que se presentara.';

alter table expediente_disciplinario
  drop constraint if exists chk_descargo_coherente;
alter table expediente_disciplinario
  add constraint chk_descargo_coherente check (
    (cargos_comunicados_at is null and descargo_vence_at is null)
    or (cargos_comunicados_at is not null and descargo_vence_at is not null
        and descargo_vence_at > cargos_comunicados_at)
  );

alter table expediente_disciplinario
  drop constraint if exists chk_descargo_acogido;
alter table expediente_disciplinario
  add constraint chk_descargo_acogido check (
    descargo_acogido is null
    or descargo_acogido in ('total', 'parcial', 'no', 'sin_descargo')
  );

-- ── 2 · El plazo, en días hábiles ───────────────────────────────────────────
-- El Reglamento dice «no menor de dos (2) días hábiles». Contarlos corridos
-- acortaría el plazo de quien recibe los cargos un viernes: tendría el sábado y
-- el domingo, que no son hábiles y en los que no puede pedir ayuda ni reunir
-- nada. Los feriados de `feriados` también se saltan.
create or replace function fn_sumar_dias_habiles(p_desde timestamptz, p_dias int)
returns timestamptz
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_fecha date := (p_desde at time zone 'America/Lima')::date;
  v_sumados int := 0;
begin
  if p_dias < 1 then
    raise exception 'El plazo tiene que ser de al menos un día hábil.';
  end if;
  while v_sumados < p_dias loop
    v_fecha := v_fecha + 1;
    if extract(dow from v_fecha) not in (0, 6)
       and not exists (select 1 from feriados f where f.fecha = v_fecha) then
      v_sumados := v_sumados + 1;
    end if;
  end loop;
  -- Vence al final del día: quien recibe los cargos el lunes tiene el miércoles
  -- entero, no hasta la hora en que se los comunicaron.
  return ((v_fecha + time '23:59:59') at time zone 'America/Lima');
end;
$fn$;

grant  execute on function fn_sumar_dias_habiles(timestamptz, int) to authenticated;
revoke execute on function fn_sumar_dias_habiles(timestamptz, int) from public, anon;

-- ── 3 · Comunicar los cargos abre el plazo ──────────────────────────────────
create or replace function fn_expediente_comunicar_cargos(
  p_id    uuid,
  p_dias  int default 2,
  p_nota  text default null
)
returns timestamptz
language plpgsql volatile security definer set search_path = public
as $fn$
declare
  v_doc   record;
  v_vence timestamptz;
begin
  select * into v_doc from expediente_disciplinario where id = p_id;
  if not found then raise exception 'Ese documento no existe.'; end if;

  if fn_expediente_puede_actuar(v_doc.persona_id, v_doc.nivel) is not true then
    raise exception 'Sin permiso para actuar sobre este documento.';
  end if;

  if v_doc.estado <> 'borrador' then
    raise exception 'Los cargos se comunican mientras el documento es borrador; este está %.', v_doc.estado;
  end if;

  if v_doc.nivel not in ('amonestacion', 'suspension') then
    raise exception 'Este acto es para la amonestación y la suspensión. La imputación y el despido siguen el procedimiento del artículo 57.';
  end if;

  if v_doc.cargos_comunicados_at is not null then
    raise exception 'Los cargos ya se comunicaron el %. El plazo no se reabre.',
      to_char(v_doc.cargos_comunicados_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI');
  end if;

  -- El Reglamento dice «no menor de dos»: se puede dar más, nunca menos.
  if p_dias < 2 then
    raise exception 'El plazo de descargo no puede ser menor de dos (2) días hábiles (art. 55.2 del RIT).';
  end if;

  v_vence := fn_sumar_dias_habiles(now(), p_dias);

  update expediente_disciplinario
     set cargos_comunicados_at = now(),
         descargo_vence_at     = v_vence,
         observacion = coalesce(observacion || E'\n', '') ||
                       'Cargos comunicados el ' ||
                       to_char(now() at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI') ||
                       coalesce('. ' || nullif(btrim(p_nota), ''), '')
   where id = p_id;

  return v_vence;
end;
$fn$;

grant  execute on function fn_expediente_comunicar_cargos(uuid, int, text) to authenticated;
revoke execute on function fn_expediente_comunicar_cargos(uuid, int, text) from public, anon;

-- ── 4 · La valoración escrita del descargo ──────────────────────────────────
create or replace function fn_expediente_valorar_descargo(
  p_id         uuid,
  p_acogido    text,
  p_valoracion text
)
returns void
language plpgsql volatile security definer set search_path = public
as $fn$
declare v_doc record;
begin
  select * into v_doc from expediente_disciplinario where id = p_id;
  if not found then raise exception 'Ese documento no existe.'; end if;

  if fn_expediente_puede_actuar(v_doc.persona_id, v_doc.nivel) is not true then
    raise exception 'Sin permiso para actuar sobre este documento.';
  end if;

  if v_doc.estado <> 'borrador' then
    raise exception 'El descargo se valora antes de firmar; este documento está %.', v_doc.estado;
  end if;

  if v_doc.cargos_comunicados_at is null then
    raise exception 'Todavía no se comunicaron los cargos: no hay descargo que valorar.';
  end if;

  if p_acogido not in ('total', 'parcial', 'no', 'sin_descargo') then
    raise exception 'Valor inválido: use total, parcial, no o sin_descargo.';
  end if;

  -- «Indica si fue acogido total o parcialmente y, EN CASO CONTRARIO, POR QUÉ»
  -- (art. 19.3). Un «no acogido» sin motivo es lo mismo que no haberlo leído.
  if p_acogido in ('parcial', 'no') and (p_valoracion is null or length(btrim(p_valoracion)) < 10) then
    raise exception 'Si el descargo no se acoge, hay que decir por qué (art. 19.3 del RIT).';
  end if;

  update expediente_disciplinario
     set descargo_acogido    = p_acogido,
         descargo_valoracion = nullif(btrim(coalesce(p_valoracion, '')), '')
   where id = p_id;
end;
$fn$;

grant  execute on function fn_expediente_valorar_descargo(uuid, text, text) to authenticated;
revoke execute on function fn_expediente_valorar_descargo(uuid, text, text) from public, anon;

-- ── 5 · El descargo se archiva contra el documento que se defiende ──────────
-- La 0206 lo ataba a una imputación entregada, que era correcto cuando el
-- descargo previo no existía. Ahora hay dos momentos legítimos y el segundo es
-- el que más se va a usar.
create or replace function fn_expediente_puede_recibir_descargo(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select exists (
    select 1 from expediente_disciplinario d
    where d.id = p_id
      and (
        -- El del artículo 57: contra una imputación ya entregada.
        (d.nivel = 'imputacion' and d.estado = 'entregado')
        -- O el previo del 55.2: contra el borrador cuyos cargos se comunicaron.
        or (d.nivel in ('amonestacion', 'suspension')
            and d.estado = 'borrador'
            and d.cargos_comunicados_at is not null)
      )
  );
$fn$;

grant  execute on function fn_expediente_puede_recibir_descargo(uuid) to authenticated;
revoke execute on function fn_expediente_puede_recibir_descargo(uuid) from public, anon;

-- ── 6 · No se firma sin haber escuchado ────────────────────────────────────
-- Cuerpo extraído de la base con pg_get_functiondef, NO copiado de un archivo.
-- md5 de partida: adde09b0a8dc8a390eaabbd1929604a7
-- Si en producción `select md5(prosrc) from pg_proc where proname =
-- 'fn_expediente_firmar'` no devuelve ese valor, PARAR: otra migración la tocó
-- y pegar esta revertiría su trabajo en silencio.
CREATE OR REPLACE FUNCTION public.fn_expediente_firmar(p_id uuid, p_firmante_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r expediente_disciplinario%rowtype; v_corr text; v_firmante uuid; v_f personas%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede firmar un borrador (estado actual: %).', r.estado;
  end if;

  -- ART. 55.2 Y 19.3 DEL RIT: antes de una amonestación o una suspensión hay
  -- que comunicar los cargos y esperar el plazo de descargo. Su omisión
  -- INVALIDA la medida, así que el sistema no puede dejar firmarla: una sanción
  -- inválida no se nota al firmarla — se nota el día que alguien la discute, y
  -- para entonces ya no se puede arreglar.
  --
  -- La imputación y el despido NO pasan por aquí: siguen el procedimiento
  -- propio del art. 57, con el plazo del art. 31 de la LPCL.
  if r.nivel in ('amonestacion', 'suspension') then
    if r.cargos_comunicados_at is null then
      raise exception 'Antes de firmar hay que comunicar los cargos y dar el plazo de descargo (art. 55.2 del RIT).';
    end if;
    if now() < r.descargo_vence_at then
      raise exception 'El plazo de descargo vence el %. Firmar antes invalidaría la sanción (art. 55.2 del RIT).',
        to_char(r.descargo_vence_at at time zone 'America/Lima', 'DD/MM/YYYY');
    end if;
    if r.descargo_acogido is null then
      raise exception 'Falta valorar por escrito el descargo antes de firmar (art. 19.3 del RIT), aunque no se haya presentado ninguno.';
    end if;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso para firmar un documento de nivel %.', r.nivel;
  end if;

  v_firmante := coalesce(p_firmante_id, fn_persona_actual_id());

  -- El firmante elegido tiene que poder suscribir ESTE documento por derecho
  -- propio. Sin esto, quien puede firmar podría estampar a cualquiera —
  -- incluida gente sin autoridad para el nivel que se está firmando.
  select * into v_f from personas where id = v_firmante;
  if not found then raise exception 'El firmante elegido no existe.'; end if;
  if v_f.estado <> 'activo' then raise exception 'El firmante elegido no está activo.'; end if;
  if fn_cargo_de_rol(v_f.rol) is null then
    raise exception 'El firmante elegido no tiene un cargo que pueda suscribir documentos.';
  end if;
  if v_f.rol = 'supervisor_sede' then
    if r.nivel not in ('verbal', 'amonestacion') then
      raise exception 'Una encargada de tienda no puede suscribir un documento de nivel %.', r.nivel;
    end if;
    if v_f.sede_base_id is distinct from (select sede_base_id from personas where id = r.persona_id) then
      raise exception 'El firmante elegido no pertenece a la sede de esta persona.';
    end if;
  end if;

  v_corr := fn_expediente_correlativo(fn_expediente_doc_code(r.tipo_causal, r.nivel));
  update expediente_disciplinario
    set estado = 'firmado', firmante_id = v_firmante, firmado_at = now(), correlativo = v_corr
    where id = p_id;
  return v_corr;
end;
$function$;

grant  execute on function fn_expediente_firmar(uuid, uuid) to authenticated;
revoke execute on function fn_expediente_firmar(uuid, uuid) from public, anon;

-- ── 7 · El descargo previo tiene dónde vivir ───────────────────────────────
-- md5 de partida: e88dd13d4bd1a830ad1f20cee64150e9
CREATE OR REPLACE FUNCTION public.fn_expediente_adjuntar(p_documento_id uuid, p_path text, p_tipo text DEFAULT 'cargo_firmado'::text, p_fecha_entrega timestamp with time zone DEFAULT NULL::timestamp with time zone, p_nota text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_doc expediente_disciplinario%rowtype;
begin
  select * into v_doc from expediente_disciplinario where id = p_documento_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if split_part(p_path, '/', 1) <> p_documento_id::text then
    raise exception 'El archivo no corresponde a este documento.';
  end if;
  if not fn_expediente_puede_adjuntar(p_path) then
    raise exception 'Sin permiso para adjuntar el cargo de este documento.';
  end if;
  if p_tipo not in ('cargo_firmado', 'acta_negativa', 'descargo') then
    raise exception 'Tipo de adjunto inválido: %', p_tipo;
  end if;
  -- Un descargo solo tiene sentido colgando de una imputación entregada: es la
  -- respuesta al plazo del art. 31, y ese plazo no existe en ningún otro nivel.
  -- Hay DOS momentos legítimos para un descargo, y hasta hoy el sistema solo
  -- conocía el segundo:
  --   · el previo del art. 55.2, contra el borrador cuyos cargos ya se
  --     comunicaron — es el que más se va a usar;
  --   · el del art. 57, contra una imputación ya entregada.
  -- Atarlo solo al segundo dejaba el legajo probando que se sancionó, y no que
  -- se dejó defenderse.
  if p_tipo = 'descargo' and fn_expediente_puede_recibir_descargo(p_documento_id) is not true then
    raise exception 'Este documento no admite un descargo todavía: hace falta que sea una imputación entregada, o un borrador de amonestación o suspensión con los cargos ya comunicados.';
  end if;

  if p_fecha_entrega is not null then
    if p_fecha_entrega > now() then
      raise exception 'La fecha de entrega no puede ser futura.';
    end if;
    if v_doc.firmado_at is not null and p_fecha_entrega < v_doc.firmado_at then
      raise exception 'La entrega no puede ser anterior a la firma del documento.';
    end if;
  end if;

  insert into expediente_adjuntos (documento_id, storage_path, tipo, nota, subido_por)
  values (p_documento_id, p_path, p_tipo, nullif(trim(p_nota), ''), fn_persona_actual_id())
  returning id into v_id;

  -- Solo si sigue "firmado": si ya se marcó entregado por otra vía, esa fecha
  -- es la buena y no se pisa. fn_expediente_entregar mantiene su blindaje de
  -- Nivel 4 — el medio es 'fisico', que es lo que un papel firmado significa.
  if p_fecha_entrega is not null and v_doc.estado = 'firmado' then
    perform fn_expediente_entregar(p_documento_id, 'fisico', p_fecha_entrega);
  end if;

  return v_id;
end;
$function$;

grant  execute on function fn_expediente_adjuntar(uuid, text, text, timestamptz, text) to authenticated;
revoke execute on function fn_expediente_adjuntar(uuid, text, text, timestamptz, text) from public, anon;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (210, 'ninguna_sancion_sin_escuchar_antes')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
select
  (select count(*) from information_schema.columns
    where table_name = 'expediente_disciplinario'
      and column_name in ('cargos_comunicados_at','descargo_vence_at',
                          'descargo_valoracion','descargo_acogido')) = 4
    as el_borrador_ya_no_es_mudo,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_sumar_dias_habiles','fn_expediente_comunicar_cargos',
                        'fn_expediente_valorar_descargo',
                        'fn_expediente_puede_recibir_descargo')) = 4
    as las_cuatro_funciones_estan,
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_sumar_dias_habiles','fn_expediente_comunicar_cargos',
                        'fn_expediente_valorar_descargo',
                        'fn_expediente_puede_recibir_descargo'))
    as el_navegador_las_puede_ejecutar,
  -- Dos días hábiles desde un viernes tienen que caer en martes, no en domingo.
  -- El viernes se ancla al MEDIODÍA DE LIMA a propósito: construirlo en UTC lo
  -- convierte en jueves de este lado (UTC-5) y la comprobación falla sin que
  -- la función tenga nada malo. Pasó al escribirla.
  (extract(dow from (fn_sumar_dias_habiles(
     ((date_trunc('week', fn_hoy_lima())::date + 4) + time '12:00')
       at time zone 'America/Lima', 2)
     at time zone 'America/Lima')::date) = 2)
    as el_plazo_salta_el_fin_de_semana,
  (select count(*) from migraciones_aplicadas where numero = 210) = 1
    as queda_registrada;
