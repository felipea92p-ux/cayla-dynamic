-- ============================================================================
-- 0616 — La firma de CAYLA en cada documento queda la de su día
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cada documento que firma CAYLA en Dynamic guarde SU copia de la firma
--   de quien firmaba por CAYLA en ese momento, con quién era y con qué cargo, y
--   que se muestre esa —no la de hoy— para siempre. Vale para el contrato de
--   trabajo (`contratos_generados`), la declaración de ruta y la constancia
--   del bono (`documentos_firmados`) y cada versión de la política salarial
--   (`politica_salarial`). Decisión de Felipe, 2026-11-10.
--
--   Y que la confirmación de un contrato de trabajo anote desde qué IP y con
--   qué navegador se firmó, como ya hace la declaración de ruta (0423/0425).
--   También decidido por Felipe ese día («Sí, súmalo»). Va en
--   `confirmaciones_firma_contrato` (0406), no en el contrato: un contrato se
--   puede volver a confirmar y su fila se pisa; el historial es append-only y
--   guarda la evidencia de CADA confirmación, la primera incluida.
--
-- POR QUÉ
--   Hasta hoy la firma de CAYLA se estampaba AL MOSTRAR con `fn_firma_empresa()`
--   (0398), que devuelve la firma ACTUAL de quien figura HOY en
--   `configuracion.firmante_empresa`. El nombre del firmante, en cambio, queda
--   congelado en el texto (el contrato y la política lo llevan escrito). Si
--   mañana cambia el firmante, o redibuja su firma en «Mi firma», todo lo ya
--   firmado muestra otra rúbrica —bajo el nombre de antes, en el contrato—. La
--   firma de la PERSONA ya se congelaba desde la 0402; la de CAYLA solo en la
--   política de movilidad (0531). Esta migración lleva el molde de la 0531 a
--   todo lo demás.
--
--   Importa más de lo que parecía: medido en producción el 2026-11-10, 17 de
--   los 23 contratos vivos se firmaron SOLO en Dynamic (desde la 0430), sin
--   papel detrás. Para ellos lo que se ve en Dynamic es el original, y si
--   alguien niega haber firmado, la prueba es de CAYLA (reglamento de la Ley
--   27269, art. 2-A). Por eso también la IP y el navegador.
--
-- CÓMO SE CONGELA: AL NACER EL DOCUMENTO, CON UN TRIGGER
--   `fn_congelar_firma_empresa()`, BEFORE INSERT en las tres tablas (en
--   `documentos_firmados`, solo lo firmado en Dynamic: un escaneo trae la firma
--   de CAYLA en su papel): toma el
--   firmante de `configuracion.firmante_empresa`, su cargo y su firma de
--   `firmas_escaneadas` en ese instante, y lo escribe en la fila. Se eligió el
--   trigger y no reescribir las funciones que crean filas (son siete
--   `insert into contratos_generados` y veinte en `documentos_firmados` a lo
--   largo de las migraciones) porque así ningún camino —una función de mañana,
--   el SQL Editor— puede crear un documento sin su firma congelada, ni con la
--   firma de otra persona: el valor que traiga la fila se pisa, siempre.
--
--   Un contrato que se CORRIGE antes de firmarse (cambia su `documento_html`)
--   vuelve a congelar: el texto nuevo nombra al firmante de hoy. Firmado, ya no.
--   Y nadie la cambia después: el mismo trigger rechaza el UPDATE.
--
-- LO YA FIRMADO (el relleno), con la regla de Felipe
--   «Se copia la firma de hoy solo donde se pueda probar que es la misma.» La
--   firma del firmante se guardó por última vez en `firmas_escaneadas.
--   actualizado_at` (en producción, el 2026-09-08). Se copia si:
--     · contrato: firmado en Dynamic después de esa fecha, o todavía sin firmar
--       (al congelarlo, CAYLA lo firma ahora), y su texto lleva el DNI del
--       firmante de hoy. Uno firmado en papel, solo si se generó después.
--     · declaración de ruta o constancia: firmada en Dynamic después de esa fecha.
--     · política de movilidad del sistema (0531): su `firma_persona` YA es la
--       firma de CAYLA de ese día; se copia tal cual, sin regla.
--     · política salarial: publicada después de esa fecha.
--   Lo demás queda en null: el documento muestra el nombre impreso y la línea
--   en blanco, más honesto que una rúbrica que quizá no fue la de ese día.
--   Medido el 2026-11-10: 0 contratos y 0 rutas firmados antes del 08-09 y 0
--   con otro firmante, así que todo lo firmado en Dynamic recibe la suya; en
--   blanco queda, como mucho, el contrato con escaneo y alguna versión vieja de
--   la política salarial.
--
-- QUÉ ASUME
--   · `configuracion.firmante_empresa` (0147) y `firmas_escaneadas` (0076, su
--     `actualizado_at` y `chk_firma_es_imagen`).
--   · `documentos_firmados.firmante_empresa_id` y su regla
--     `chk_documento_politica_del_sistema` (0531): la regla se reescribe,
--     porque decía que solo la política del sistema tiene firmante.
--   · Que no exista `fn_congelar_firma_empresa`: comprobado con
--     `donde-vive.sh` y en producción (`congelar_ya_existe` = 0).
--
-- LAS TRES FUNCIONES QUE REESCRIBE, Y SU MD5 DE PARTIDA
--   No se le pudo pedir el md5 a producción antes de escribirla (Felipe pidió
--   las migraciones el 2026-11-10 sin haber corrido la consulta), así que la
--   comprobación va DENTRO: el bloque 0 mide las tres en la base donde se pega
--   y se niega a seguir —sin aplicar nada— si alguna no es la de main. Acepta
--   las cuatro formas benignas que documenta CLAUDE.md: tal cual, sin
--   comentarios, y las dos con \r\n de un pegado desde Windows.
--     fn_documentos_listar            (0489) · c3f59252… · 1117 caracteres
--     fn_politica_salarial_vigente    (0491) · 79b6a2e4… · 1832 caracteres
--     fn_confirmar_mi_firma_contrato  (0462) · 00ab0d72… · 3429 caracteres
--   Las tres se copian literales de esas migraciones, con los cambios marcados
--   «CAMBIO 0616».
--
-- CÓMO SE PEGA
--   En UNA pegada, con el molde de la 0604: altera tres tablas en uso, así que
--   toma los tres candados SIN ESPERAR (`nowait`) y, si una está ocupada,
--   deshace el intento y reintenta a los 0.2 s. Nadie queda esperando un
--   candado con otro en la mano, que es lo que cierra un deadlock.
--
-- CÓMO SE REVIERTE
--   drop trigger congelar_firma_empresa on contratos_generados;
--   drop trigger congelar_firma_empresa on documentos_firmados;
--   drop trigger congelar_firma_empresa on politica_salarial;
--   drop function fn_congelar_firma_empresa();
--   Las columnas NO se sueltan: son la evidencia de lo firmado. Las pantallas,
--   sin columna llena, vuelven a la línea en blanco; para volver a la firma de
--   hoy hay que revertir también su código.
-- ============================================================================

set local lock_timeout = '3s';

-- ── 0 · Las tres funciones que se reescriben tienen que ser las de main ─────
do $$
declare
  v_esperado constant jsonb := jsonb_build_object(
    'fn_documentos_listar', jsonb_build_array(
      'c3f59252b4fe6b024297c3b0c779ec5a', '6c69fdfb8471b06035df7959e5faecbc',
      '84fbedb503ed9a006dd5fd3aaa2cddee', 'bb8f0fc7d37d3606ccfe36d5b52f1ac7'),
    'fn_politica_salarial_vigente', jsonb_build_array(
      '79b6a2e4a3c0c87d4c2b485dbcb4fbf4', '662bd848e69845e20b48635da64b15c7',
      'e07f5727279f501551d4bfb7c2f0d3cf', 'ecf1fab9eba31e8b93e03d35b014c27e'),
    'fn_confirmar_mi_firma_contrato', jsonb_build_array(
      '00ab0d721692e13dda68819613e2bed4', 'fcbca6f77070f032108db545e6f813a2',
      'fdc9d5a74787e11c3ec8262fc62dedaf', '53970aec7e1fc2f33432b8924a415dd1'));
  -- Con el nombre, no solo el número: el 2026-11-10 la 0612 de otra rama ya
  -- ocupaba un número, y un freno que se salta «si el número ya está» se
  -- habría saltado por la migración de otra.
  v_ya_aplicada boolean := exists (select 1 from migraciones_aplicadas
                                    where numero = 616 and nombre = 'la_firma_de_cayla_queda_la_de_su_dia');
  r record;
begin
  if v_ya_aplicada then
    return;  -- repegar la 0616 no vuelve a medir: ya reemplazó estas tres.
  end if;
  for r in
    select k.nombre, k.validos, f.tal_cual, f.sin_comentarios
      from jsonb_each(v_esperado) as k(nombre, validos)
      left join lateral (
        select md5(p.prosrc) as tal_cual,
               md5(array_to_string(array(
                 select regexp_replace(l, '[[:space:]]*--.*$', '')
                 from unnest(string_to_array(p.prosrc, chr(10))) as l
                 where btrim(l) not like '--%'
               ), chr(10))) as sin_comentarios
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = k.nombre
         limit 1) f on true
  loop
    if not (r.validos ? coalesce(r.tal_cual, '') or r.validos ? coalesce(r.sin_comentarios, '')) then
      raise exception 'PARAR: % en esta base no es la de main (md5 % / sin comentarios %). No se aplicó nada: avisa antes de seguir.',
        r.nombre, coalesce(r.tal_cual, 'no existe'), coalesce(r.sin_comentarios, '—');
    end if;
  end loop;
end $$;

-- ── 0b · Los candados, sin esperar con ninguno en la mano (molde 0604) ──────
do $$
declare
  v_intentos int := 0;
begin
  loop
    begin
      -- ACCESS EXCLUSIVE de entrada: los `alter table` de abajo lo piden, y
      -- subir después desde un candado menor sería volver a esperar.
      lock table contratos_generados, documentos_firmados, politica_salarial, confirmaciones_firma_contrato
        in access exclusive mode nowait;
      exit;
    exception when lock_not_available then
      v_intentos := v_intentos + 1;
      if v_intentos >= 50 then
        raise exception 'No se pudieron tomar los candados en 10 s: hay mucho movimiento en este momento. No se aplicó nada; vuelve a pegarla en un rato.';
      end if;
      perform pg_sleep(0.2);
    end;
  end loop;
end $$;


-- ── 1 · Las columnas ────────────────────────────────────────────────────────
alter table contratos_generados
  add column if not exists firma_empresa text,
  add column if not exists firmante_empresa_id uuid references personas(id),
  add column if not exists firmante_empresa_cargo text;

alter table confirmaciones_firma_contrato
  add column if not exists ip text,
  add column if not exists user_agent text;

alter table documentos_firmados
  add column if not exists firma_empresa text,
  add column if not exists firmante_empresa_cargo text;

alter table politica_salarial
  add column if not exists firma_empresa text,
  add column if not exists firmante_empresa_id uuid references personas(id),
  add column if not exists firmante_empresa_cargo text;

alter table contratos_generados drop constraint if exists chk_contrato_firma_empresa_imagen;
alter table contratos_generados add constraint chk_contrato_firma_empresa_imagen
  check (firma_empresa is null or (firma_empresa ~ '^data:image/(png|jpeg);base64,' and firmante_empresa_id is not null));
alter table documentos_firmados drop constraint if exists chk_documento_firma_empresa_imagen;
alter table documentos_firmados add constraint chk_documento_firma_empresa_imagen
  check (firma_empresa is null or (firma_empresa ~ '^data:image/(png|jpeg);base64,' and firmante_empresa_id is not null));
alter table politica_salarial drop constraint if exists chk_politica_firma_empresa_imagen;
alter table politica_salarial add constraint chk_politica_firma_empresa_imagen
  check (firma_empresa is null or (firma_empresa ~ '^data:image/(png|jpeg);base64,' and firmante_empresa_id is not null));

-- La 0531 decía «solo la política del sistema tiene firmante». Desde hoy todo
-- documento lo tiene; lo que sigue siendo solo de la política del sistema es
-- guardar su texto (`documento_html`), con su firmante y su firma.
alter table documentos_firmados drop constraint if exists chk_documento_politica_del_sistema;
alter table documentos_firmados add constraint chk_documento_politica_del_sistema check (
  documento_html is null
  or (tipo = 'politica' and firmante_empresa_id is not null and firma_persona is not null)
);

comment on column contratos_generados.firma_empresa is
  'La firma de quien firmaba por CAYLA cuando nació el documento (0616): se muestra esta, no la de hoy. Null en lo firmado antes de la 0616 que no se pudo probar (ver la migración).';
comment on column documentos_firmados.firma_empresa is
  'La firma de quien firmaba por CAYLA cuando nació el documento (0616). En la política del sistema (0531) es la misma que firma_persona.';
comment on column politica_salarial.firma_empresa is
  'La firma de quien firmaba por CAYLA al publicar esta versión (0616). El nombre y el cargo ya van dentro de `documento`.';
comment on column confirmaciones_firma_contrato.ip is
  'IP desde la que se confirmó esta firma (cabecera x-forwarded-for, primera de la cadena, como la 0423). Null en lo confirmado antes de la 0616 y cuando no hubo cabeceras (SQL Editor).';
comment on column confirmaciones_firma_contrato.user_agent is
  'El navegador con que se confirmó esta firma (cabecera user-agent). Evidencia: si alguien niega haber firmado, la prueba es de CAYLA (reglamento de la Ley 27269, art. 2-A).';


-- ── 2 · El relleno de lo ya firmado (antes del trigger, para que este no lo frene) ──
drop trigger if exists congelar_firma_empresa on contratos_generados;
drop trigger if exists congelar_firma_empresa on documentos_firmados;
drop trigger if exists congelar_firma_empresa on politica_salarial;

create temp table firma_de_hoy on commit drop as
select p.id as persona_id, p.documento as dni, c.valor ->> 'cargo' as cargo,
       f.imagen, f.actualizado_at
  from configuracion c
  join personas p on p.id = (c.valor ->> 'persona_id')::uuid
  join firmas_escaneadas f on f.persona_id = p.id
 where c.clave = 'firmante_empresa';

update contratos_generados g
   set firma_empresa = h.imagen, firmante_empresa_id = h.persona_id, firmante_empresa_cargo = h.cargo
  from firma_de_hoy h
 where g.firma_empresa is null
   and h.dni is not null and position(btrim(h.dni) in g.documento_html) > 0
   and (g.firma_persona_confirmada_at >= h.actualizado_at
        or (g.firma_persona_confirmada_at is null and g.fecha_firma is null)
        or (g.firma_persona_confirmada_at is null and g.generado_at >= h.actualizado_at));

update documentos_firmados d
   set firma_empresa = h.imagen, firmante_empresa_id = h.persona_id, firmante_empresa_cargo = h.cargo
  from firma_de_hoy h
 where d.firma_empresa is null and d.documento_html is null
   and d.firma_persona_confirmada_at >= h.actualizado_at;

-- La política del sistema (0531) ya guardó la firma de CAYLA de su día en `firma_persona`.
update documentos_firmados d
   set firma_empresa = d.firma_persona
 where d.firma_empresa is null and d.documento_html is not null and d.firmante_empresa_id is not null;

update politica_salarial s
   set firma_empresa = h.imagen, firmante_empresa_id = h.persona_id, firmante_empresa_cargo = h.cargo
  from firma_de_hoy h
 where s.firma_empresa is null and s.publicada_at >= h.actualizado_at;


-- ── 3 · Congelar al nacer, y que nadie la cambie después ───────────────────
-- SECURITY DEFINER a propósito: la firma que se congela tiene que ser la
-- configurada, la escriba quien la escriba. Con los permisos de quien inserta,
-- un camino que corriera como `authenticated` leería `firmas_escaneadas` con su
-- RLS (solo la propia) y congelaría un null sin que nada avisara. No recibe
-- parámetros ni devuelve datos: no abre nada que antes estuviera cerrado.
create or replace function fn_congelar_firma_empresa()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if tg_op = 'UPDATE' then
    -- Un contrato que se corrige antes de firmarse lleva el firmante de HOY en
    -- su texto nuevo: vuelve a congelar. Firmado, ya no se toca.
    if tg_table_name = 'contratos_generados' then
      if new.documento_html is distinct from old.documento_html
         and new.fecha_firma is null and new.firma_persona_confirmada_at is null then
        select h.persona_id, h.cargo, h.imagen
          into new.firmante_empresa_id, new.firmante_empresa_cargo, new.firma_empresa
          from (select p.id as persona_id, c.valor ->> 'cargo' as cargo, f.imagen
                  from configuracion c
                  join personas p on p.id = (c.valor ->> 'persona_id')::uuid
                  left join firmas_escaneadas f on f.persona_id = p.id
                 where c.clave = 'firmante_empresa') h;
        return new;
      end if;
    end if;
    if (new.firma_empresa, new.firmante_empresa_id, new.firmante_empresa_cargo)
       is distinct from (old.firma_empresa, old.firmante_empresa_id, old.firmante_empresa_cargo) then
      raise exception 'La firma de CAYLA de un documento no se cambia: es la de su día.';
    end if;
    return new;
  end if;

  -- INSERT: la de este instante, siempre. Lo que traiga la fila se pisa: nadie
  -- puede crear un documento con la firma de otra persona.
  new.firma_empresa := null;
  new.firmante_empresa_id := null;
  new.firmante_empresa_cargo := null;
  -- El argumento, si lo hay, nombra la columna que dice «este documento se
  -- firmó EN Dynamic». En `documentos_firmados` es `firma_persona`: un papel
  -- escaneado trae la firma de CAYLA en el papel, y Dynamic muestra el papel,
  -- no una firma estampada. Sin argumento (contratos, política salarial), todo
  -- documento nace en Dynamic.
  if tg_nargs > 0 and to_jsonb(new) ->> tg_argv[0] is null then
    return new;
  end if;
  select p.id, c.valor ->> 'cargo', f.imagen
    into new.firmante_empresa_id, new.firmante_empresa_cargo, new.firma_empresa
    from configuracion c
    join personas p on p.id = (c.valor ->> 'persona_id')::uuid
    left join firmas_escaneadas f on f.persona_id = p.id
   where c.clave = 'firmante_empresa';
  return new;
end;
$fn$;

create trigger congelar_firma_empresa
  before insert or update on contratos_generados
  for each row execute function fn_congelar_firma_empresa();
create trigger congelar_firma_empresa
  before insert or update on documentos_firmados
  for each row execute function fn_congelar_firma_empresa('firma_persona');
create trigger congelar_firma_empresa
  before insert or update on politica_salarial
  for each row execute function fn_congelar_firma_empresa();


-- ── 4 · Las tres funciones que leen y firman ────────────────────────────────

-- 4a · fn_documentos_listar: la firma de CAYLA de cada documento, con quién y
-- con qué cargo. Cuerpo de la 0489, copiado literal salvo lo marcado. `drop` +
-- `create`: Postgres no deja sumar columnas a una función que devuelve TABLE.
drop function if exists fn_documentos_listar(uuid);
create function fn_documentos_listar(p_persona_id uuid default null)
returns table (
  id uuid, alcance text, persona_id uuid, persona text, tipo text,
  fecha_firma date, ruta_declarada text, monto_declarado numeric, anio integer,
  es_negativa boolean, storage_path text, nota text, registrado_por text,
  anulado_at timestamptz, anulado_motivo text, vigente boolean, firma_persona text,
  ruta_distrito text, ruta_provincia text, ruta_medios_ida integer, ruta_medios_vuelta integer,
  ruta_costo_pasaje numeric, ruta_gasto_diario numeric, ruta_costo_taxi numeric, ruta_frecuencia_taxi integer,
  -- ⇩⇩⇩ CAMBIO 0616 ⇩⇩⇩
  firma_empresa text, firmante_empresa_nombre text, firmante_empresa_cargo text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    d.id, d.alcance, d.persona_id,
    coalesce(p.nombres || ' ' || p.apellidos, 'CAYLA'),
    d.tipo, d.fecha_firma, d.ruta_declarada, d.monto_declarado, d.anio,
    d.es_negativa, d.storage_path, d.nota,
    reg.nombres || ' ' || reg.apellidos,
    d.anulado_at, d.anulado_motivo,
    (d.anulado_at is null and d.id = (
       select d2.id from documentos_firmados d2
        where d2.tipo = d.tipo and d2.anulado_at is null
          and d2.persona_id is not distinct from d.persona_id
        order by d2.fecha_firma desc, d2.created_at desc, d2.id desc limit 1)),
    d.firma_persona,
    d.ruta_distrito, d.ruta_provincia, d.ruta_medios_ida, d.ruta_medios_vuelta,
    -- ⇩⇩⇩ CAMBIO 0489 ⇩⇩⇩
    d.ruta_costo_pasaje, d.ruta_gasto_diario, d.ruta_costo_taxi, d.ruta_frecuencia_taxi,
    -- ⇩⇩⇩ CAMBIO 0616 ⇩⇩⇩ La firma de CAYLA de su día, y quién la puso. El
    -- nombre sale de su ficha: es la misma persona, y un nombre corregido se
    -- ve corregido. El cargo, el de ese día.
    d.firma_empresa,
    case when d.firmante_empresa_id is not null then fir.nombres || ' ' || fir.apellidos end,
    d.firmante_empresa_cargo
  from documentos_firmados d
  left join personas p on p.id = d.persona_id
  left join personas reg on reg.id = d.registrado_por
  left join personas fir on fir.id = d.firmante_empresa_id   -- CAMBIO 0616
  where (fn_es_admin_o_lider() is true or d.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or d.persona_id = p_persona_id)
  order by d.fecha_firma desc, d.created_at desc;
$$;

grant execute on function fn_documentos_listar(uuid) to authenticated;
revoke execute on function fn_documentos_listar(uuid) from public, anon;


-- 4b · fn_politica_salarial_vigente: la firma de CAYLA de la versión vigente.
-- Cuerpo de la 0491, copiado literal salvo lo marcado. Misma firma (sin
-- parámetros, devuelve jsonb): `create or replace` basta.
create or replace function public.fn_politica_salarial_vigente()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_yo   uuid;
  v_row  politica_salarial%rowtype;
  v_hoy  text;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'Inicia sesion para ver la politica salarial.';
  end if;

  select * into v_row from politica_salarial order by version desc limit 1;

  if not found then
    return jsonb_build_object(
      'publicada',    false,
      'desactualizada', false,
      'mi_acuse',     null,
      'aviso', 'Todavia no se ha publicado ninguna version. Mientras tanto CAYLA sigue incursa en el numeral 25.23 del RLGIT.'
    );
  end if;

  v_hoy := md5(fn_cuadro_categorias()::text);

  return jsonb_build_object(
    'publicada',      true,
    'version',        v_row.version,
    'documento',      v_row.documento,
    'publicada_at',   v_row.publicada_at,
    'notas',          v_row.notas,
    -- CAMBIO 0616: la firma de CAYLA congelada al publicar esta versión (null
    -- si se publicó antes de que se pudiera probar cuál era).
    'firma_empresa',  v_row.firma_empresa,
    -- Si el cuadro cambio despues de publicar, el documento que la gente acuso
    -- ya no describe la realidad. Hay que publicar de nuevo.
    'desactualizada', v_row.huella_cuadro <> v_hoy,
    'mi_acuse', (
      select jsonb_build_object('acusado_at', a.acusado_at, 'nombre', a.nombre_declarado)
      from politica_salarial_acuses a
      where a.persona_id = v_yo and a.version = v_row.version
    ),
    'total_personas', (
      select count(*)::int from personas
      where estado = 'activo' and en_planilla is true
        and not cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    ),
    'total_acuses', (
      select count(*)::int from politica_salarial_acuses a
      join personas p on p.id = a.persona_id
      where a.version = v_row.version and p.estado = 'activo' and p.en_planilla is true
        and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    )
  );
end;
$function$;


-- 4c · fn_confirmar_mi_firma_contrato: anota la IP y el navegador de cada
-- confirmación. Cuerpo de la 0462, copiado literal salvo lo marcado. Misma
-- firma: `create or replace` basta.
create or replace function fn_confirmar_mi_firma_contrato(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo            uuid;
  v_imagen        text;
  v_dueno         uuid;
  v_anulado       timestamptz;
  v_fecha_previa  date;
  v_tipo          text;
  v_nota          text := '';
  v_ip            text;   -- CAMBIO 0616
  v_ua            text;   -- CAMBIO 0616
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select persona_id, anulado_at, fecha_firma, tipo
    into v_dueno, v_anulado, v_fecha_previa, v_tipo
    from contratos_generados where id = p_contrato_id;
  if v_dueno is null then raise exception 'No se encontró ese contrato.'; end if;
  if v_dueno <> v_yo then raise exception 'Ese contrato no es tuyo.'; end if;
  if v_anulado is not null then raise exception 'Ese contrato está anulado.'; end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a Mi perfil → Firma antes de confirmar.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0616 ⇩⇩⇩ La evidencia, igual que la declaración de ruta
  -- (0425): la IP y el navegador vienen en las cabeceras que PostgREST deja
  -- ver. Sin cabeceras (SQL Editor, pruebas) quedan en null: la firma vale igual.
  begin
    v_ip := nullif(btrim(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1)), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  -- La constancia primero (0406): reconfirmar con otra firma no debe borrar
  -- de qué imagen era ni de qué día la anterior.
  insert into confirmaciones_firma_contrato (contrato_id, persona_id, imagen, ip, user_agent)  -- CAMBIO 0616
  values (p_contrato_id, v_yo, v_imagen, v_ip, v_ua);

  -- La primera confirmación digital fecha el contrato (0430) Y entrega su
  -- copia (0462): quien firma en pantalla ve ahí mismo, para siempre, el
  -- documento que firmó — no hay una copia distinta que darle aparte. Los dos
  -- `coalesce` protegen un valor que ya exista (de una confirmación anterior,
  -- o —para fecha_firma/registrado_por— de un escaneo que subió DO):
  -- reconfirmar sigue sirviendo solo para corregir la IMAGEN de la firma,
  -- nunca para mover estas fechas.
  update contratos_generados
     set firma_persona = v_imagen,
         firma_persona_confirmada_at = now(),
         fecha_firma = coalesce(fecha_firma, fn_hoy_lima()),
         registrado_por = coalesce(registrado_por, v_yo),
         copia_entregada_at = coalesce(copia_entregada_at, fn_hoy_lima())  -- ⇦ CAMBIO 0462
   where id = p_contrato_id;

  -- Solo la PRIMERA vez (v_fecha_previa era null): recalcular hasta cuándo
  -- vale el vencimiento de esta persona (0287/0312/0333/0347) y dejar
  -- constancia en su historial. Sin cambios desde la 0430.
  if v_fecha_previa is null then
    if v_tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
      v_nota := fn_contrato_refrescar_vencimiento(v_yo, 'Contrato firmado — autoservicio digital');
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_yo, 'contrato_firmado', null,
       v_tipo || ' · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
       'Firma digital confirmada en /mio/contrato, sin escaneo' || v_nota);

    -- ⇩⇩⇩ CAMBIO 0462 ⇩⇩⇩ Constancia aparte para la entrega de copia, con el
    -- mismo `campo_modificado` que ya usa el trámite manual
    -- (`fn_contrato_marcar_tramite`, 0287) — así el historial de la persona
    -- lee «se entregó la copia» igual sin importar por cuál de las dos vías.
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_yo, 'contrato_copia_entregada', null, fn_hoy_lima()::text, v_yo,
       'Entrega de copia del contrato — acceso digital permanente en /mio/contrato, sin trámite físico aparte');
  end if;
end;
$$;

notify pgrst, 'reload schema';


insert into migraciones_aplicadas (numero, nombre) values (616, 'la_firma_de_cayla_queda_la_de_su_dia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación (una fila; la última consulta es la que muestra el SQL Editor) ──
with firma as (
  select fs.actualizado_at
    from configuracion c join firmas_escaneadas fs on fs.persona_id = (c.valor ->> 'persona_id')::uuid
   where c.clave = 'firmante_empresa'
)
select
  (select count(*) from pg_trigger where tgname = 'congelar_firma_empresa' and not tgisinternal) as triggers_de_3,
  (select count(*) from contratos_generados where anulado_at is null)                            as contratos_vivos,
  (select count(*) from contratos_generados where anulado_at is null and firma_empresa is not null) as contratos_con_firma_congelada,
  (select count(*) from documentos_firmados where anulado_at is null and firma_persona is not null) as documentos_firmados_en_dynamic,
  (select count(*) from documentos_firmados where anulado_at is null and firma_persona is not null
                                              and firma_empresa is not null)                        as documentos_con_firma_congelada,
  (select count(*) from politica_salarial)                                                         as versiones_politica,
  (select count(*) from politica_salarial where firma_empresa is not null)                         as versiones_con_firma_congelada,
  (select count(*) from information_schema.columns
    where table_name = 'confirmaciones_firma_contrato' and column_name in ('ip', 'user_agent'))   as evidencia_de_2,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 616)                 as registro;
