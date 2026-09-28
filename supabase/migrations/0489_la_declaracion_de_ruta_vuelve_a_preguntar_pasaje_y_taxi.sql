-- ============================================================================
-- 0489 — La declaración de ruta vuelve a preguntar el pasaje y el taxi
-- ============================================================================
--
-- QUÉ PROMETE
--
--   La declaración que se firma desde «Lo mío» (/mio/movilidad) vuelve a
--   tener los cinco puntos del papel que se imprime en admin/documentacion:
--
--     1. distrito y provincia donde reside            (ya estaba)
--     2. medios de transporte de ida y de regreso     (ya estaba)
--     3. costo de cada pasaje, y el gasto diario de ida y vuelta   ← vuelve
--     4. si en ocasiones usa taxi: costo por viaje y veces/semana  ← vuelve
--     5. declaración de veracidad                     (ya estaba)
--
--   Pedido el 2026-09-28, comparando la firma digital con una declaración
--   en papel del 10/08/26 que sí traía los cinco puntos: la digital había
--   quedado más pobre que el papel al que reemplaza.
--
--   ESTO DESHACE, A SABIENDAS, DOS DECISIONES DEL 2026-09-12: la 0425 quitó
--   el costo del pasaje y el gasto diario, la 0426 quitó el taxi, y la 0429
--   dejó escrito «esas preguntas ya se quitaron y no vuelven». Vuelven por
--   decisión de producto, no por un defecto; se deja dicho acá para que la
--   próxima sesión no crea que esto es una regresión y lo revierta.
--
--   Cada pieza se guarda en su propia columna, igual que la 0429 hizo con
--   distrito/provincia/medios: la pantalla arma la lista numerada desde las
--   columnas, nunca parseando `ruta_declarada`.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   NO TOCA CUÁNTO SE PAGA. La razón por la que la 0425 quitó el pasaje era
--   que el monto nunca fuera «una cuenta que la persona arme sola». Eso se
--   mantiene entero: `monto_declarado` sigue siendo la tarifa vigente de la
--   sede (0142), calculada por el servidor. Lo que la persona declara del
--   pasaje y del taxi es DESCRIPTIVO — es lo que sostiene que la movilidad
--   es un criterio objetivo (art. 19 e, D.S. 001-97-TR) — y no entra a
--   ningún cálculo de planilla. El papel del 10/08 ya convivía así: gasto
--   diario S/ 5.00 declarado, asignación S/ 10.00 de la sede.
--
--   El gasto diario NO lo escribe la persona: sale de
--   (medios de ida + medios de regreso) × costo del pasaje — la misma
--   fórmula de la 0424 — y se guarda congelado en `ruta_gasto_diario`. Así
--   el punto 3 no puede contradecirse a sí mismo.
--
--   No cambia el candado de la 0425 ni el criterio de «vigente»: siguen
--   mirando `es_negativa` y `monto_declarado`. Quien ya firmó y está al día
--   NO tiene que volver a firmar: su declaración sigue vigente, y se ve con
--   los puntos que tenía el día que la firmó.
--
--   No toca lo ya firmado. Las cuatro columnas nuevas quedan en null en todo
--   lo firmado antes de esta migración, y la pantalla lo muestra como se
--   firmó (sin los puntos 3 y 4) — no se inventan datos que nadie declaró.
--
-- QUÉ ASUME
--
--   `fn_confirmar_mi_declaracion_ruta` y `fn_documentos_listar` vigentes son
--   las de la 0429 — confirmado el 2026-09-28 con `./scripts/donde-vive.sh`
--   y con `git grep` en todas las ramas (ninguna las redefine después).
--
-- POR QUÉ LOS PARÁMETROS NUEVOS TIENEN DEFAULT
--
--   La migración se pega ANTES de fusionar el PR, así que durante unos
--   minutos la pantalla vieja (4 argumentos) llama a la función nueva. Con
--   default null la llamada vieja encuentra la función y recibe un mensaje
--   que se entiende —«Indica el costo de cada pasaje»— en vez de un «no se
--   encontró la función». Y se borra la firma de 4 parámetros antes de crear
--   la nueva: si convivieran, una llamada con 4 argumentos encajaría en las
--   dos y Postgres respondería «function … is not unique» (lo que tumbó el
--   aviso de vacaciones con la 0297/0299).
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,numeric,numeric,integer);
--   -- recrear fn_confirmar_mi_declaracion_ruta con el cuerpo de la 0429
--   -- (4 parámetros), y fn_documentos_listar con el de la 0429 (drop + create).
--   -- Las columnas pueden quedarse: nada más las lee.
--   Las declaraciones ya firmadas quedan intactas: esta migración no borra ni
--   modifica ninguna fila existente de documentos_firmados.
-- ============================================================================

alter table documentos_firmados
  add column if not exists ruta_costo_pasaje    numeric(8,2),
  add column if not exists ruta_gasto_diario    numeric(8,2),
  add column if not exists ruta_costo_taxi      numeric(8,2),
  add column if not exists ruta_frecuencia_taxi integer;

comment on column documentos_firmados.ruta_costo_pasaje is
  'Solo tipo=ruta, desde la 0489. Lo que la persona declara que cuesta cada '
  'pasaje — descriptivo, NO entra a la planilla (lo que se paga es '
  'monto_declarado, la tarifa de la sede). Null = firmada antes de la 0489.';
comment on column documentos_firmados.ruta_gasto_diario is
  'Solo tipo=ruta, desde la 0489. (medios_ida + medios_vuelta) × costo_pasaje, '
  'calculado por fn_confirmar_mi_declaracion_ruta y congelado al firmar.';
comment on column documentos_firmados.ruta_costo_taxi is
  'Solo tipo=ruta, desde la 0489. Costo por viaje del taxi u otro medio '
  'particular que usa en ocasiones. Null = no usa taxi (o firmó antes de la 0489).';
comment on column documentos_firmados.ruta_frecuencia_taxi is
  'Solo tipo=ruta, desde la 0489. Veces por semana que usa taxi (1 a 7). '
  'Null exactamente cuando ruta_costo_taxi es null.';


-- ── fn_confirmar_mi_declaracion_ruta: 4 → 7 parámetros ──────────────────────
-- Postgres no deja agregar parámetros con `create or replace` sin crear una
-- sobrecarga: se borra la de 4 primero (ver «POR QUÉ LOS PARÁMETROS NUEVOS
-- TIENEN DEFAULT»).
drop function if exists fn_confirmar_mi_declaracion_ruta(text,text,integer,integer);

create or replace function fn_confirmar_mi_declaracion_ruta(
  p_distrito         text,
  p_provincia        text,
  p_medios_ida       integer,
  p_medios_vuelta    integer,
  p_costo_pasaje     numeric default null,
  p_costo_taxi       numeric default null,
  p_frecuencia_taxi  integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo            uuid := fn_persona_actual_id();
  v_imagen        text;
  v_sede_codigo   text;
  v_tarifa        numeric;
  v_declarada     text;
  v_id            uuid;
  v_ip            text;
  v_ua            text;
  v_es_negativa   boolean;
  v_monto_anterior numeric;
  v_gasto_diario  numeric;
  v_usa_taxi      boolean;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  if not exists (select 1 from personas where id = v_yo and estado = 'activo')
     or not fn_persona_le_corresponde_movilidad(v_yo) then
    raise exception 'No estás en planilla ni eres practicante: no te corresponde declarar tu ruta.';
  end if;

  if p_distrito is null or length(trim(p_distrito)) = 0 then
    raise exception 'Falta el distrito donde resides.';
  end if;
  if p_provincia is null or length(trim(p_provincia)) = 0 then
    raise exception 'Falta la provincia donde resides.';
  end if;
  if p_medios_ida is null or p_medios_ida < 0 or p_medios_ida > 10 then
    raise exception 'Indica cuántos medios de transporte usas de ida (entre 0 y 10).';
  end if;
  if p_medios_vuelta is null or p_medios_vuelta < 0 or p_medios_vuelta > 10 then
    raise exception 'Indica cuántos medios de transporte usas de vuelta (entre 0 y 10).';
  end if;

  -- ⇩⇩⇩ CAMBIO 0489 ⇩⇩⇩ El pasaje y el taxi vuelven (ver encabezado). Cero
  -- es un pasaje válido: quien va caminando declara 0 medios y S/ 0.00.
  if p_costo_pasaje is null or p_costo_pasaje < 0 or p_costo_pasaje > 1000 then
    raise exception 'Indica el costo de cada pasaje (S/ 0 si no usas transporte).';
  end if;

  -- Taxi: opcional. Sin costo y sin veces = no usa taxi. Si declara uno de
  -- los dos, tiene que declarar el otro — un «S/ 8 por viaje» sin cuántas
  -- veces, o al revés, no le dice nada a quien lo lea.
  v_usa_taxi := coalesce(p_costo_taxi, 0) > 0 or coalesce(p_frecuencia_taxi, 0) > 0;
  if v_usa_taxi then
    if p_costo_taxi is null or p_costo_taxi <= 0 or p_costo_taxi > 1000 then
      raise exception 'Indica cuánto te cuesta cada viaje en taxi u otro medio particular.';
    end if;
    if p_frecuencia_taxi is null or p_frecuencia_taxi < 1 or p_frecuencia_taxi > 7 then
      raise exception 'Indica cuántas veces por semana usas taxi u otro medio particular (entre 1 y 7).';
    end if;
  end if;

  v_gasto_diario := round((p_medios_ida + p_medios_vuelta) * p_costo_pasaje, 2);
  -- ⇧⇧⇧ FIN CAMBIO 0489 ⇧⇧⇧

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  select s.codigo into v_sede_codigo
    from personas p join sedes s on s.id = p.sede_base_id
   where p.id = v_yo;

  select pl.valor into v_tarifa
    from parametros_laborales pl
   where pl.clave = 'movilidad_diaria'
     and pl.vigente_desde <= fn_hoy_lima()
     and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima())
     and (pl.sede_codigo = v_sede_codigo or pl.sede_codigo is null)
   order by (pl.sede_codigo is null), pl.vigente_desde desc
   limit 1;

  if v_tarifa is null then
    raise exception 'Tu sede todavía no tiene una tarifa de movilidad vigente. Avisa a Desarrollo Organizacional antes de firmar.';
  end if;

  -- Candado (0425), sin cambios de criterio.
  select d.es_negativa, d.monto_declarado into v_es_negativa, v_monto_anterior
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'ruta' and d.anulado_at is null
   order by d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;

  if v_es_negativa is not true and v_monto_anterior is not null and v_monto_anterior = v_tarifa then
    raise exception 'Ya tienes una declaración de ruta firmada y vigente. Si algo cambió, pide una revisión en vez de volver a firmar.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0489 ⇩⇩⇩ El texto legal vuelve a decir el pasaje y el taxi,
  -- con la redacción de la 0424, y conserva el cierre de la tarifa de la 0429.
  v_declarada :=
    'Reside en el distrito de ' || trim(p_distrito) || ', provincia de ' || trim(p_provincia) || '. '
    || 'Para llegar a su centro de labores utiliza ' || p_medios_ida || ' medio(s) de transporte por tramo, '
    || 'y de regreso ' || p_medios_vuelta || '. '
    || 'El costo de cada pasaje es de S/ ' || to_char(p_costo_pasaje, 'FM999999990.00')
    || ', con un gasto diario habitual de ida y vuelta de S/ ' || to_char(v_gasto_diario, 'FM999999990.00') || '. '
    || case when v_usa_taxi
         then 'Según el horario de su turno, en ocasiones utiliza taxi u otro medio particular, cuyo costo por viaje '
              || 'asciende aproximadamente a S/ ' || to_char(p_costo_taxi, 'FM999999990.00')
              || ', alrededor de ' || p_frecuencia_taxi || ' vez(veces) por semana. '
         else 'No reporta uso ocasional de taxi u otro medio particular. '
       end
    || 'CAYLA le otorga una asignación de movilidad de S/ ' || to_char(v_tarifa, 'FM999999990.00')
    || ' por día efectivamente asistido, conforme a la tarifa vigente para su sede.';

  begin
    v_ip := nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  -- Las piezas se guardan aparte (0429), ahora también el pasaje y el taxi.
  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent,
    ruta_distrito, ruta_provincia, ruta_medios_ida, ruta_medios_vuelta,
    ruta_costo_pasaje, ruta_gasto_diario, ruta_costo_taxi, ruta_frecuencia_taxi
  ) values (
    'individual', v_yo, 'ruta', fn_hoy_lima(), v_declarada, v_tarifa,
    v_yo, v_imagen, now(), v_ip, v_ua,
    trim(p_distrito), trim(p_provincia), p_medios_ida, p_medios_vuelta,
    p_costo_pasaje, v_gasto_diario,
    case when v_usa_taxi then p_costo_taxi end,
    case when v_usa_taxi then p_frecuencia_taxi end
  )
  returning id into v_id;
  -- ⇧⇧⇧ FIN CAMBIO 0489 ⇧⇧⇧

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'ruta · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la declaración de ruta (0423), reemplaza el escaneo físico.');

  return v_id;
end;
$$;

grant execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,numeric,numeric,integer)
  to authenticated;
revoke execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,numeric,numeric,integer)
  from public, anon;


-- ── fn_documentos_listar: gana las cuatro columnas nuevas ──────────────────
-- `returns table` con columnas nuevas: hace falta `drop` antes de `create`,
-- mismo motivo que ya documentaron la 0161 y la 0429.
drop function if exists fn_documentos_listar(uuid);

create function fn_documentos_listar(p_persona_id uuid default null)
returns table (
  id uuid, alcance text, persona_id uuid, persona text, tipo text,
  fecha_firma date, ruta_declarada text, monto_declarado numeric, anio integer,
  es_negativa boolean, storage_path text, nota text, registrado_por text,
  anulado_at timestamptz, anulado_motivo text, vigente boolean, firma_persona text,
  ruta_distrito text, ruta_provincia text, ruta_medios_ida integer, ruta_medios_vuelta integer,
  ruta_costo_pasaje numeric, ruta_gasto_diario numeric, ruta_costo_taxi numeric, ruta_frecuencia_taxi integer
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
    d.ruta_costo_pasaje, d.ruta_gasto_diario, d.ruta_costo_taxi, d.ruta_frecuencia_taxi
  from documentos_firmados d
  left join personas p on p.id = d.persona_id
  left join personas reg on reg.id = d.registrado_por
  where (fn_es_admin_o_lider() is true or d.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or d.persona_id = p_persona_id)
  order by d.fecha_firma desc, d.created_at desc;
$$;

grant execute on function fn_documentos_listar(uuid) to authenticated;
revoke execute on function fn_documentos_listar(uuid) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (489, 'la_declaracion_de_ruta_vuelve_a_preguntar_pasaje_y_taxi')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Las cuatro tienen que salir en true, y la última en 1: si sale 2, quedó
-- viva la firma de 4 parámetros y la pantalla va a chocar con «is not unique».
select
  (select count(*) from information_schema.columns
     where table_name = 'documentos_firmados' and column_name = 'ruta_costo_pasaje') = 1
    as columnas_puestas,
  (select prosrc like '%CAMBIO 0489%' from pg_proc
     where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 7)
    as confirmar_pide_pasaje,
  (select count(*) from pg_proc where proname = 'fn_documentos_listar'
     and pg_get_function_result(oid) like '%ruta_frecuencia_taxi%') = 1
    as listar_devuelve_pasaje,
  (select numero = 489 and nombre = 'la_declaracion_de_ruta_vuelve_a_preguntar_pasaje_y_taxi'
     from migraciones_aplicadas where numero = 489)
    as registro_es_el_mio,
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_declaracion_ruta')
    as versiones_de_confirmar;
