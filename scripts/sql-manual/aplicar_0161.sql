-- ############################################################################
-- ####  ESTE ES EL ARCHIVO QUE SE PEGA EN EL SQL EDITOR DE SUPABASE.      ####
-- ############################################################################
--
-- aplicar_0161.sql — El tablero de Documentación también ve el cargo del
--                    cumpleaños
--
-- QUÉ HACE
--   1. Reemplaza `fn_documentos_tablero` para que, además del estado de la
--      declaración de ruta, informe el del cargo de la asignación por
--      onomástico: quién ya lo firmó, quién cumple años ESTE mes y a quién se
--      le pasó el mes sin firmarlo.
--   2. Extiende una condición de `fn_documento_registrar`: el bono tampoco se
--      le registra a quien no está en planilla. Antes esa regla solo cubría la
--      declaración de ruta.
--
-- QUÉ **NO** HACE
--   No condiciona ningún pago, no crea tablas ni columnas, y no escribe ni
--   borra un solo dato. Si se pega dos veces no pasa nada: las dos sentencias
--   son un reemplazo de función.
--
-- ANTES DE PEGAR
--   Requiere la 0157 aplicada (crea `documentos_firmados` y las funciones que
--   esto reemplaza). Comprobación:
--
--     select numero from migraciones_aplicadas where numero = 157;
--
--   Si no devuelve fila, pega primero `aplicar_0157_documentos_firmados.sql`.
--
-- DESPUÉS DE PEGAR
--   Los NOTICE del final dicen cuántas personas en planilla no tienen fecha de
--   nacimiento cargada (esas aparecen pidiendo el dato, no en rojo) y cuántas
--   cumplen años este mes.
--
--   Y en la pantalla de Documentación: la columna «Cargo de cumpleaños» debe
--   aparecer al lado de la de ruta. Si no aparece, falta desplegar la web.
--
-- CÓMO SE REVIERTE
--   Volviendo a pegar las secciones E y G de `aplicar_0157_documentos_firmados.sql`.
-- ############################################################################


-- ============================================================================
-- 0161 — El tablero también ve el cargo del cumpleaños
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la pregunta «¿a quién le falta firmar?» se pueda responder también para
--   la asignación por onomástico, y no solo para la declaración de ruta. Y que
--   se pueda responder A TIEMPO: no «quién no firmó» sino «a quién le toca este
--   mes y todavía no hay papel».
--
-- QUÉ ASUME
--   · `documentos_firmados` y `fn_documentos_tablero` de la 0157 — esta migración
--     reemplaza esa función y no toca la tabla.
--   · `datos_personales.fecha_nacimiento` (0061). Es opcional: quien no la tenga
--     cargada aparece pidiéndola, no acusado.
--   · `personas.en_planilla` (0085), igual que la 0157.
--
-- POR QUÉ EL AVISO ES POR MES Y NO POR PERSONA
--   El bono se entrega UNA vez al año y su ventana es el mes del onomástico. Una
--   columna que dijera «falta» los doce meses del año para las 22 personas es un
--   aviso que grita sin motivo, y un aviso que grita siempre se ignora a la
--   semana — el mismo criterio con el que la 0157 comparó la tarifa contra la de
--   SU sede en vez de contra el máximo. Aquí solo se pone en rojo quien ya
--   cumplió años y no tiene su cargo; quien cumple más adelante se ve en gris.
--
-- POR QUÉ SE COMPARA EL MES Y NO EL DÍA
--   Porque el documento que se firma dice «en el mes de su onomástico»: el mes
--   ES la unidad del negocio. Comparar el día exacto obligaría además a inventar
--   una rama para el 29 de febrero, que no existe en tres de cada cuatro años.
--   Un caso borde que se puede diseñar afuera no se maneja con un `if`.
--
-- POR QUÉ QUIEN ENTRÓ DESPUÉS DE SU CUMPLEAÑOS NO APARECE EN ROJO
--   Si alguien cumple en marzo y entró en septiembre, en marzo no era parte del
--   equipo: no había nada que entregarle y no falta ningún papel. Marcarla en
--   rojo sería acusar de un descuido que no ocurrió, y en este sistema el falso
--   positivo cuesta más que la falta que se escapa. La exclusión se aplica ANTES
--   de contar, no después.
--
-- POR QUÉ EL BONO TAMPOCO SE LE PIDE A UN LOCADOR
--   `fn_documento_registrar` ya rechazaba una declaración de ruta de quien no
--   está en planilla (0117: un locador no cobra movilidad). La asignación por
--   onomástico es igual de laboral: a quien emite recibo por honorarios no se le
--   entrega un beneficio de trabajador, se le paga su recibo. Eran dos reglas del
--   mismo hecho escritas una sola vez a medias; acá se unifican.
--
-- QUÉ NO HACE
--   No condiciona ningún pago. Decisión de Felipe (2026-08-05): el cargo del bono
--   se firma AL RECIBIR el dinero, así que exigirlo antes de pagar invertiría el
--   orden real del acto — nadie firma que recibió algo que todavía no recibió.
--   El sistema avisa; entregar y perseguir la firma es de Desarrollo
--   Organizacional. Por eso acá no hay interruptor como el de la 0157.
--
-- CÓMO SE REVIERTE
--   Volver a pegar la sección G de la 0157 (la función tal como estaba) y
--   restaurar el `if p_tipo = 'ruta'` de su sección E. Nada que borrar: esta
--   migración no crea tablas, columnas ni datos.
-- ============================================================================


-- ── A · El tablero, ahora con las dos columnas ─────────────────────────────
-- Va DROP y no CREATE OR REPLACE porque cambia el tipo de retorno: Postgres no
-- deja reemplazar una función que devuelve TABLE si cambian sus columnas.
--
-- Las columnas de ruta y el `estado` de la 0157 se conservan con el mismo nombre
-- y el mismo significado: la pantalla que ya los usa sigue funcionando aunque
-- todavía no sepa leer los nuevos.
drop function if exists fn_documentos_tablero();

create function fn_documentos_tablero()
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
           extract(month from fn_hoy_lima())::int    as mes
  ),
  ruta as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.fecha_firma, d.monto_declarado, d.es_negativa
    from documentos_firmados d
    where d.tipo = 'ruta' and d.anulado_at is null
    order by d.persona_id, d.fecha_firma desc, d.created_at desc
  ),
  bono as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.anio, d.fecha_firma
    from documentos_firmados d, hoy
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = hoy.anio
    order by d.persona_id, d.fecha_firma desc
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    r.id, r.fecha_firma, r.monto_declarado, coalesce(r.es_negativa, false),
    -- Firmada con una tarifa que ya no es la vigente: el papel declara un monto
    -- y se está pagando otro. No bloquea; avisa, que es lo acordado.
    --
    -- La tarifa es POR SEDE desde la 0142 (AQP y TRU a S/10, LIM a S/12), así que
    -- se compara contra la de SU sede. Compararla contra el máximo marcaría como
    -- desfasadas todas las de TRU y AQP el día que LIM tenga otra cifra — un aviso
    -- que grita sin motivo se desactiva a la semana.
    (r.monto_declarado is not null
      and tar.valor is not null
      and r.monto_declarado <> tar.valor),
    b.id, b.anio, b.fecha_firma,
    dp.mes_nacimiento,
    case
      -- El orden importa: primero lo que ya está resuelto, después lo que no se
      -- puede saber, y al final lo que hay que perseguir. Así ninguna persona
      -- cae en dos estados a la vez.
      when b.id is not null            then 'ok'
      when dp.mes_nacimiento is null   then 'sin_fecha'
      -- Su mes de onomástico de este año cayó antes del mes en que entró: ese año
      -- no había nada que entregarle.
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
  -- Solo el MES sale de la ficha personal. La fecha de nacimiento completa es
  -- dato sensible y esta consulta la ve una pantalla: se devuelve lo mínimo que
  -- responde la pregunta, que es en qué mes hay que entregar.
  left join lateral (
    select extract(month from d.fecha_nacimiento)::int as mes_nacimiento
    from datos_personales d
    where d.persona_id = p.id and d.fecha_nacimiento is not null
  ) dp on true
  left join lateral (
    -- La fila de su sede si existe; si no, la general (sede_codigo nulo).
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
    and p.en_planilla
    and fn_es_admin_o_lider() is true
  order by (r.id is not null), p.apellidos;
$$;

grant execute on function fn_documentos_tablero() to authenticated;


-- ── B · El bono tampoco se le pide a quien no está en planilla ─────────────
-- Cuerpo copiado de la 0157 (verificado con ./scripts/donde-vive.sh: es la única
-- definición vigente). Cambia UNA condición, señalada abajo.
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
    -- CAMBIO 0161: antes decía `p_tipo = 'ruta'`. Los dos documentos individuales
    -- son beneficios de trabajador: un locador no cobra movilidad (0117) ni recibe
    -- asignación por onomástico — se le paga su recibo. Pedirle cualquiera de los
    -- dos es pedirle un papel que no sostiene ningún pago suyo.
    if not exists (
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


insert into migraciones_aplicadas (numero, nombre)
values (161, 'el_tablero_tambien_ve_el_cargo_del_cumpleanos')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_sin_fecha int;
  v_este_mes  int;
begin
  select count(*) into v_sin_fecha
  from personas p
  where p.estado = 'activo' and p.en_planilla
    and not exists (select 1 from datos_personales d
                    where d.persona_id = p.id and d.fecha_nacimiento is not null);

  select count(*) into v_este_mes
  from personas p
  join datos_personales d on d.persona_id = p.id
  where p.estado = 'activo' and p.en_planilla
    and extract(month from d.fecha_nacimiento) = extract(month from fn_hoy_lima());

  raise notice '0161 · en planilla sin fecha de nacimiento cargada: % (aparecen como «falta su fecha», no como pendientes)', v_sin_fecha;
  raise notice '0161 · cumplen anios este mes: %', v_este_mes;
  raise notice '0161 · esta migracion no condiciona ningun pago.';
end $mig$;
