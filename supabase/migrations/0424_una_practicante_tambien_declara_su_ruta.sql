-- ============================================================================
-- 0424 — Una practicante también declara su ruta
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que quien tiene `tipo_vinculo = 'practicante'` pueda registrar, ver y
--   firmar su propia declaración de ruta — hoy no podía ninguna de las tres
--   cosas, aunque la 0397 ya le abrió el cobro de la movilidad misma.
--
-- EL DEFECTO, VISTO EN VIVO
--
--   Medido hoy contra producción: Benjamin Cueva, Fernanda Espinoza y Daniel
--   Ruiz —los tres `tipo_vinculo = 'practicante'`, los tres ingresados esta
--   semana— no aparecen en el tablero de admin/documentacion, no aparecen en
--   su desplegable «Elige a quién», y `/mio/movilidad` le dice a cualquiera de
--   los tres «Esto no te corresponde por ahora». Diego Narro, ingresado el
--   mismo día pero con `tipo_vinculo = 'planilla'`, sí aparece.
--
--   La causa es una sola: `personas.en_planilla` es una columna GENERADA
--   (`tipo_vinculo in ('planilla','prueba')`, 0085) que nunca se actualizó
--   cuando la 0322 creó la categoría `practicante`, y tres puertas la usan
--   como si fuera sinónimo de «le corresponde movilidad»:
--
--     · `fn_documento_registrar` (0211) — rechaza registrar su declaración.
--     · `fn_documentos_tablero` (0423)  — no la lista, ni para admin ni para
--       ella misma con `p_solo_mi_fila => true`.
--     · `fn_confirmar_mi_declaracion_ruta` (0423) — rechaza que firme.
--
--   La 0397 ya resolvió esta MISMA confusión para el cálculo de planilla,
--   con el mismo criterio que se copia acá: `en_planilla or tipo_vinculo =
--   'practicante'`. No se inventa un criterio nuevo — se propaga el que ya
--   está en producción y ya se probó.
--
-- POR QUÉ UNA FUNCIÓN COMPARTIDA, Y NO TRES COPIAS DEL MISMO `or`
--
--   Copiar `en_planilla or tipo_vinculo = 'practicante'` una tercera vez
--   (después de la 0397 y de esta migración) es exactamente el patrón que
--   este repositorio ya se cansó de perseguir con `rol` y con
--   `"America/Lima"`: un criterio de negocio repetido en varios sitios que
--   se vuelve a romper la próxima vez que alguien agregue una categoría de
--   vínculo. `fn_persona_le_corresponde_movilidad` lo dice una sola vez; las
--   tres puertas de esta migración lo leen de ahí.
--
--   NO se toca `fn_planilla_calcular_nucleo` (0397) para que use esta función
--   nueva: es la función que decide cuánto se paga cada mes, y tocarla de
--   paso en una migración sobre PAPELEO —sin necesidad real, porque ya
--   funciona bien— sería el tipo de cambio que este repositorio pide medir
--   aparte, no de arrastre. Queda con su copia propia, anotada acá para quien
--   busque la tercera.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No abre el bono de cumpleaños a practicantes. `fn_documento_registrar`
--   comparte un solo `if` para `ruta` y `bono` desde la 0161; este cambio lo
--   separa en dos para tocar SOLO `ruta` — si el bono se abriera con el mismo
--   `or`, sería una decisión de negocio nueva (¿una practicante en su primer
--   mes cobra el bono de cumpleaños?) que nadie pidió y que no le toca
--   decidir a una migración de movilidad.
--
--   No toca `en_planilla` ni su fórmula: sigue significando exactamente lo
--   mismo que hoy (¿se le mide asistencia y disciplina?, comentario de la
--   0085), para lo que ya se usa en el resto del sistema. Esta migración
--   agrega una pregunta nueva y distinta —¿le corresponde movilidad?—, no
--   redefine la vieja.
--
-- QUÉ ASUME
--
--   `fn_documento_registrar` vigente es la 0211, `fn_documentos_tablero` y
--   `fn_confirmar_mi_declaracion_ruta` vigentes son las de la 0423 —
--   confirmado el 2026-09-12 con `./scripts/donde-vive.sh` y, para las dos
--   últimas, comprobando directo en el Postgres local (`pg_proc.pronargs`)
--   porque el stack de PostgREST sigue sin poder levantarse en esta Mac (ver
--   0423) y `donde-vive.sh` no pudo comparar por esa vía.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_persona_le_corresponde_movilidad(uuid);
--   -- recrear fn_documento_registrar con el cuerpo de la 0211;
--   -- recrear fn_documentos_tablero y fn_confirmar_mi_declaracion_ruta con
--   -- los cuerpos de la 0423.
--   No hay datos que deshacer: ninguna fila cambia al pegar esto.
-- ============================================================================


-- ── A · Un solo lugar para «¿le corresponde movilidad?» ────────────────────
create or replace function fn_persona_le_corresponde_movilidad(p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select en_planilla or tipo_vinculo = 'practicante' from personas where id = p_persona_id),
    false
  );
$$;

comment on function fn_persona_le_corresponde_movilidad(uuid) is
  'Mismo criterio que ya usa fn_planilla_calcular_nucleo (0397) para pagar la '
  'movilidad: en_planilla, o tipo_vinculo = practicante. Un solo lugar para '
  'esta pregunta — la usan fn_documento_registrar, fn_documentos_tablero y '
  'fn_confirmar_mi_declaracion_ruta (0424). NO decide el bono de cumpleaños, '
  'que sigue exigiendo en_planilla a secas.';

grant execute on function fn_persona_le_corresponde_movilidad(uuid) to authenticated;


-- ── B · fn_documento_registrar: la ruta admite a la practicante, el bono no ─
-- Cuerpo vigente: 0211, copiado literal. El único cambio, marcado CAMBIO 0424,
-- separa en dos el `if` que la 0161 había dejado compartido entre ruta y bono
-- — ver «QUÉ NO HACE» arriba. `create or replace`: ni columnas de retorno ni
-- parámetros cambian.
create or replace function fn_documento_registrar(
  p_tipo            text,
  p_fecha_firma     date,
  p_persona_id      uuid    default null,
  p_ruta_declarada  text    default null,
  p_monto_declarado numeric default null,
  p_anio            integer default null,
  p_es_negativa     boolean default false,
  p_nota            text    default null,
  p_storage_path    text    default null,
  p_id              uuid    default null   -- no nulo = enlazar el archivo recién subido
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  v_alcance text;
  v_yo      uuid := fn_persona_actual_id();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra documentos firmados.';
  end if;

  if p_tipo not in ('ruta', 'politica', 'bono') then
    raise exception 'Tipo de documento inválido: «%».', p_tipo;
  end if;

  -- El alcance no se recibe: se deduce del tipo, que es lo único que puede
  -- decidirlo. Recibirlo abriría la puerta a una ruta declarada «de empresa».
  v_alcance := case when p_tipo = 'politica' then 'empresa' else 'individual' end;

  if p_fecha_firma is null then
    raise exception 'Falta la fecha en que se firmó el documento.';
  end if;
  if p_fecha_firma > fn_hoy_lima() then
    raise exception 'La fecha de firma no puede ser futura.';
  end if;

  -- Enlazar el archivo a una fila que ya existe.
  if p_id is not null then
    update documentos_firmados
       set storage_path = coalesce(p_storage_path, storage_path)
     where id = p_id and anulado_at is null;
    if not found then raise exception 'Ese documento no existe o está anulado.'; end if;
    return p_id;
  end if;

  if v_alcance = 'individual' then
    if p_persona_id is null then
      raise exception 'Falta de quién es el documento.';
    end if;
    if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
      raise exception 'Esa persona no existe o no está activa.';
    end if;
    -- ⇩⇩⇩ CAMBIO 0424 ⇩⇩⇩ Antes era un solo `if` compartido entre ruta y bono
    -- (CAMBIO 0161), con `en_planilla` a secas. Se separa en dos: la ruta
    -- ahora también admite a quien es practicante (0397 le abrió el cobro de
    -- la movilidad misma), y el bono se queda exactamente como estaba —
    -- abrirlo también sería otra decisión de negocio, que nadie pidió.
    if p_tipo = 'ruta' and not fn_persona_le_corresponde_movilidad(p_persona_id) then
      raise exception 'Esa persona no está en planilla ni es practicante: no le corresponde declarar su ruta.';
    end if;
    if p_tipo = 'bono' and not exists (
      select 1 from personas where id = p_persona_id and en_planilla
    ) then
      raise exception 'Esa persona no está en planilla: no le corresponde ese documento.';
    end if;
  elsif p_persona_id is not null then
    raise exception 'La política de movilidad la emite CAYLA: no se atribuye a una persona.';
  end if;

  if p_tipo = 'bono' and p_anio is null then
    raise exception 'Falta de qué año es la constancia del bono.';
  end if;

  -- ── REEMPLAZAR ES REEMPLAZAR (0211) ──────────────────────────────────
  -- Una política nueva anula la anterior. Antes no lo hacia: insertaba una
  -- SEGUNDA fila y dejaba las dos vivas, y como fn_documentos_estado_politica
  -- elegía con `order by fecha_firma desc limit 1` SIN desempate, la pantalla
  -- se quedaba mostrando la vieja. Reproducido: dos políticas del 29/07/2026
  -- y la consulta devolvía la primera.
  --
  -- Y no es un caso raro, es EL caso: la política tiene que conservar su fecha
  -- —anterior al primer pago de movilidad, que es todo su valor legal—, así
  -- que todo reemplazo legítimo empata en fecha_firma.
  --
  -- Se ANULA, no se borra: queda con su motivo, su autor y su hora, y sigue
  -- siendo el historial de qué política regía cuando se pago cada mes. Esa
  -- traza es lo que sostiene los pagos ya hechos ante una inspección.
  --
  -- Solo la política. Las rutas y los bonos son de una persona y su reemplazo
  -- no tiene por qué anular el de otra; el bono ya lleva su índice único por año.
  if p_tipo = 'politica' and p_id is null then
    update documentos_firmados
       set anulado_at = now(),
           anulado_por = v_yo,
           anulado_motivo = 'Reemplazada por la política firmada el ' ||
                            to_char(p_fecha_firma, 'DD/MM/YYYY')
     where tipo = 'politica' and anulado_at is null;
  end if;
  insert into documentos_firmados (
    alcance, persona_id, tipo, storage_path, fecha_firma,
    ruta_declarada, monto_declarado, anio, es_negativa, nota, registrado_por
  ) values (
    v_alcance, p_persona_id, p_tipo, p_storage_path, p_fecha_firma,
    nullif(trim(coalesce(p_ruta_declarada, '')), ''),
    case when p_es_negativa then null else p_monto_declarado end,
    p_anio, coalesce(p_es_negativa, false),
    nullif(trim(coalesce(p_nota, '')), ''), v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (coalesce(p_persona_id, v_yo),
     case when p_es_negativa then 'documento_negativa' else 'documento_firmado' end,
     null,
     p_tipo || ' · firmado el ' || p_fecha_firma::text,
     v_yo,
     case when p_es_negativa
          then 'Se registró la negativa a firmar'
          else 'Alta de documento firmado' end);

  return v_id;
end;
$$;

grant execute on function fn_documento_registrar(text,date,uuid,text,numeric,integer,boolean,text,text,uuid)
  to authenticated;


-- ── C · fn_documentos_tablero: también lista a la practicante ──────────────
-- Cuerpo vigente: 0423, copiado literal. Un cambio, marcado CAMBIO 0424.
-- `create or replace`: ni columnas de retorno ni parámetros cambian.
create or replace function fn_documentos_tablero(p_solo_mi_fila boolean default false)
returns table (
  persona_id        uuid,
  persona           text,
  sede              text,
  fecha_ingreso     date,
  ruta_id           uuid,
  ruta_firmada_el   date,
  ruta_monto        numeric,
  ruta_negativa     boolean,
  ruta_desfasada    boolean,
  ruta_firma_persona_confirmada_at timestamptz,
  ruta_tarifa_vigente numeric,
  bono_id           uuid,
  bono_anio         integer,
  bono_firmada_el   date,
  bono_mes          integer,
  bono_estado       text,
  estado            text
)
language sql
stable
security definer
set search_path = public
as $$
  with hoy as (
    select fn_hoy_lima()                             as dia,
           extract(year  from fn_hoy_lima())::int    as anio,
           extract(month from fn_hoy_lima())::int    as mes,
           (date_trunc('month', fn_hoy_lima()) + interval '1 month - 1 day')::date
                                                     as fin_de_mes,
           coalesce(
             (select min(vigente_desde) from parametros_laborales
               where clave = 'bono_onomastico' and valor > 0),
             '1900-01-01'::date)                     as bono_desde
  ),
  ruta as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.fecha_firma, d.monto_declarado, d.es_negativa,
           d.firma_persona_confirmada_at
    from documentos_firmados d
    where d.tipo = 'ruta' and d.anulado_at is null
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
  ),
  bono as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.anio, d.fecha_firma
    from documentos_firmados d, hoy
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = hoy.anio
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    r.id, r.fecha_firma, r.monto_declarado, coalesce(r.es_negativa, false),
    (r.monto_declarado is not null
      and tar.valor is not null
      and r.monto_declarado <> tar.valor),
    r.firma_persona_confirmada_at,
    tar.valor,
    b.id, b.anio, b.fecha_firma,
    dp.mes_nacimiento,
    case
      when b.id is not null            then 'ok'
      when dp.mes_nacimiento is null   then 'sin_fecha'
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', hoy.bono_desde)::date then 'no_aplica'
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', p.fecha_ingreso)::date then 'no_aplica'
      when dp.mes_nacimiento = hoy.mes then 'este_mes'
      when dp.mes_nacimiento <  hoy.mes then 'vencido'
      else                                  'proximo'
    end,
    case
      when r.id is null                    then 'sin_ruta'
      when coalesce(r.es_negativa, false)  then 'se_nego'
      else 'ok'
    end
  from personas p
  cross join hoy
  left join sedes s on s.id = p.sede_base_id
  left join ruta r on r.persona_id = p.id
  left join bono b on b.persona_id = p.id
  left join lateral (
    select extract(month from d.fecha_nacimiento)::int as mes_nacimiento
    from datos_personales d
    where d.persona_id = p.id and d.fecha_nacimiento is not null
  ) dp on true
  left join lateral (
    select pl.valor
    from parametros_laborales pl
    where pl.clave = 'movilidad_diaria'
      and pl.vigente_desde <= hoy.dia
      and (pl.vigente_hasta is null or pl.vigente_hasta >= hoy.dia)
      and (pl.sede_codigo = s.codigo or pl.sede_codigo is null)
    order by (pl.sede_codigo is null), pl.vigente_desde desc
    limit 1
  ) tar on true
  where p.estado = 'activo'
    -- ⇩⇩⇩ CAMBIO 0424 ⇩⇩⇩ Antes: `and p.en_planilla`. Ver el encabezado de
    -- esta migración — es la línea que dejaba a Benjamin, Fernanda y Daniel
    -- fuera del tablero aunque ya pudieran cobrar movilidad desde la 0397.
    and fn_persona_le_corresponde_movilidad(p.id)
    and (p.id = fn_persona_actual_id()
         or (not coalesce(p_solo_mi_fila, false) and fn_es_admin_o_lider() is true))
    and p.id is distinct from (
      select (c.valor->>'persona_id')::uuid
      from configuracion c
      where c.clave = 'firmante_empresa'
    )
    and (p.fecha_fin_contrato is null or p.fecha_fin_contrato > hoy.fin_de_mes)
  order by (r.id is not null), p.apellidos;
$$;

grant execute on function fn_documentos_tablero(boolean) to authenticated;

comment on function fn_documentos_tablero(boolean) is
  'Que documento de movilidad o bono de onomastico le falta a cada quien '
  '(0157/0161/0162/0165/0387/0423/0424). Sin argumentos: todo el equipo, solo '
  'para admin/lider. Con p_solo_mi_fila => true: unicamente la fila de quien '
  'pregunta. Desde la 0424, "a quien le corresponde" ya no es solo en_planilla: '
  'ver fn_persona_le_corresponde_movilidad.';


-- ── D · fn_confirmar_mi_declaracion_ruta: la practicante puede firmar ──────
-- Cuerpo vigente: 0423, copiado literal. Un cambio, marcado CAMBIO 0424.
-- `create or replace`: ni columnas de retorno ni parámetros cambian.
create or replace function fn_confirmar_mi_declaracion_ruta(
  p_distrito         text,
  p_provincia        text,
  p_medios_ida       integer,
  p_medios_vuelta    integer,
  p_costo_pasaje     numeric,
  p_usa_taxi         boolean default false,
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
  v_gasto_diario  numeric;
  v_declarada     text;
  v_id            uuid;
  v_ip            text;
  v_ua            text;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0424 ⇩⇩⇩ Antes exigía `en_planilla` a secas. Ver el
  -- encabezado de esta migración y el de fn_persona_le_corresponde_movilidad.
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
  if p_costo_pasaje is null or p_costo_pasaje < 0 then
    raise exception 'Indica el costo de cada pasaje.';
  end if;
  if p_usa_taxi and (p_costo_taxi is null or p_costo_taxi < 0) then
    raise exception 'Indica el costo del taxi u otro medio particular.';
  end if;
  if p_usa_taxi and (p_frecuencia_taxi is null or p_frecuencia_taxi < 0 or p_frecuencia_taxi > 7) then
    raise exception 'Indica cuántas veces por semana usas taxi u otro medio particular (entre 0 y 7).';
  end if;

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

  v_gasto_diario := (p_medios_ida + p_medios_vuelta) * p_costo_pasaje;

  v_declarada :=
    'Reside en el distrito de ' || trim(p_distrito) || ', provincia de ' || trim(p_provincia) || '. '
    || 'Para llegar a su centro de labores utiliza ' || p_medios_ida || ' medio(s) de transporte por tramo, '
    || 'y de regreso ' || p_medios_vuelta || '. El costo de cada pasaje es de S/ '
    || to_char(p_costo_pasaje, 'FM999999990.00')
    || ', con un gasto diario habitual de ida y vuelta de S/ ' || to_char(v_gasto_diario, 'FM999999990.00') || '. '
    || case when p_usa_taxi
         then 'En ocasiones utiliza taxi u otro medio particular, cuyo costo por viaje asciende a S/ '
              || to_char(p_costo_taxi, 'FM999999990.00') || ', aproximadamente ' || p_frecuencia_taxi
              || ' vez(veces) por semana.'
         else 'No reporta uso ocasional de taxi u otro medio particular.'
       end;

  begin
    v_ip := nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent
  ) values (
    'individual', v_yo, 'ruta', fn_hoy_lima(), v_declarada, v_tarifa,
    v_yo, v_imagen, now(), v_ip, v_ua
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'ruta · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la declaración de ruta (0423), reemplaza el escaneo físico.');

  return v_id;
end;
$$;

grant execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,numeric,boolean,numeric,integer)
  to authenticated;
revoke execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,numeric,boolean,numeric,integer)
  from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (424, 'una_practicante_tambien_declara_su_ruta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_persona_le_corresponde_movilidad') = 1
    as funcion_compartida_puesta,
  (select prosrc like '%CAMBIO 0424%' from pg_proc
    where proname = 'fn_documento_registrar' and pronargs = 10)
    as registrar_al_dia,
  (select prosrc like '%CAMBIO 0424%' from pg_proc
    where proname = 'fn_documentos_tablero' and pronargs = 1)
    as tablero_al_dia,
  (select prosrc like '%CAMBIO 0424%' from pg_proc
    where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 8)
    as firma_al_dia;
