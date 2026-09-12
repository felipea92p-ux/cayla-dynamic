-- ============================================================================
-- 0423 — La declaración de ruta ya no necesita escaneo
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1. Que una integrante en planilla pueda firmar SU declaración de ruta y
--      gasto de transporte desde /mio, sin imprimir, sin firmar a mano y sin
--      escanear nada — y que esa firma digital tenga el MISMO valor que el
--      escaneo de hoy: sostiene por sí sola el carácter no remunerativo de la
--      movilidad (D.S. 001-97-TR art. 19 e), no es una confirmación aparte
--      del trámite físico como la del contrato (0402).
--   2. Que en cuanto le falte firmarla, se lo diga su propia Bandeja
--      (`/mio/bandeja` y el número de `/mio`) — hoy no se lo dice nadie: todo
--      el ciclo (imprimir → firmar a mano → escanear → subir) vive del lado
--      admin en `admin/documentacion/`, y ninguna pantalla de `(mio)` sabe que
--      existe.
--   3. Que Desarrollo Organizacional pueda SEGUIR subiendo un escaneo a mano
--      —decisión explícita de Felipe, 2026-09-12— para quien no tenga cómo
--      firmar desde el sistema. Las dos vías conviven: la que gana es la más
--      reciente, igual que ya pasa hoy entre dos escaneos.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No toca `politica` ni `bono` — decisión explícita de Felipe, 2026-09-12,
--   «solo la declaración de ruta por ahora». Los dos siguen exactamente igual
--   que hoy: escaneo físico, subido a mano por un admin.
--
--   No enciende `movilidad_exige_declaracion` (0157/0159): sigue en 0. Esta
--   migración cambia CÓMO se firma, no si el pago depende de estar firmada.
--
--   No toca el bug ya diagnosticado de `en_planilla` para `tipo_vinculo =
--   'practicante'` (la 0397 le abrió el cobro de movilidad pero no el acceso a
--   este mismo trámite, en ningún lado que lo exija). Es un problema real y
--   distinto, todavía sin autorizar — arreglarlo acá de paso repetiría el error
--   que ya cometió la 0397: parchar UN sitio de una condición de elegibilidad
--   que vive repetida en varios. Esta migración usa la MISMA condición
--   (`en_planilla`) que ya usan `fn_documento_registrar` (0211) y
--   `fn_documentos_tablero` (0387), a propósito: no inventa una cuarta versión
--   de "a quién le corresponde".
--
-- QUÉ ASUME
--
--   · `documentos_firmados` con su forma de la 0157, sin ALTER desde entonces
--     (comprobado: `grep -rn "alter table documentos_firmados"
--     supabase/migrations/` solo encuentra el `enable row level security` de
--     su propia migración de origen).
--   · `firmas_escaneadas` (0065/0076/0395) y `fn_persona_actual_id()`.
--   · Que `fn_documentos_tablero` vigente es la 0387 y `fn_documentos_listar`
--     vigente es la 0391 — confirmado con `./scripts/donde-vive.sh` el
--     2026-09-12. Los dos cuerpos de abajo son copias literales de esas dos,
--     con los cambios marcados CAMBIO 0423.
--   · El patrón de «reemplazar el escaneo» que ya usa esta migración para la
--     evidencia (`firma_persona`, `firma_persona_confirmada_at`) copia
--     literalmente las columnas que la 0402 le agregó a `contratos_generados`
--     — misma forma, mismo constraint de formato — con dos columnas más
--     (`firma_persona_ip`, `firma_persona_user_agent`) que esa migración no
--     tiene, porque ahí la firma digital NO reemplaza nada (sigue habiendo un
--     escaneo físico detrás) y acá si.
--
-- POR QUÉ NO HACE FALTA UNA TABLA DE HISTORIAL APARTE (a diferencia de la 0406)
--
--   La 0406 tuvo que crear `confirmaciones_firma_contrato` porque
--   `fn_confirmar_mi_firma_contrato` hace un UPDATE sobre la MISMA fila cada
--   vez que alguien confirma: sin esa tabla, volver a confirmar con otra firma
--   borraba la anterior sin dejar rastro.
--
--   Acá no hace falta: `documentos_firmados` ya es append-only desde la 0157
--   («cuando cambia, la anterior no se pisa»). Si la persona vuelve a firmar
--   —cambió de domicilio, cambió su ruta— `fn_confirmar_mi_declaracion_ruta`
--   INSERTA una fila nueva, nunca actualiza la anterior. La versión vieja
--   sigue entera, con SU imagen, SU hora y SU ip, exactamente igual que ya
--   pasa con dos escaneos sucesivos. El historial ya estaba resuelto por el
--   diseño de la 0157; copiar la tabla aparte de la 0406 aquí sería agregar lo
--   que el diseño ya da gratis.
--
-- POR QUÉ LA EVIDENCIA DE IP/DISPOSITIVO ES «MEJOR ESFUERZO», NO UNA GARANTÍA
--
--   Se lee de `current_setting('request.headers', true)`, el GUC que PostgREST
--   deja armado con los encabezados del pedido — no hay ningún precedente de
--   esto en el repositorio (comprobado: `grep -rn "request.headers"` no
--   encuentra nada), así que es la primera vez que se usa acá. No se pudo
--   comprobar contra el PostgREST real de este proyecto —ver más abajo, «QUÉ
--   NO SE PUDO PROBAR»—, así que el criterio es: si el GUC no está, o no es el
--   JSON que se espera, la firma se guarda IGUAL y las dos columnas quedan en
--   null. Nunca se bloquea una firma por no poder fotografiar de dónde vino.
--   Es una foto de lo que el navegador mandó —cualquiera puede mandar un
--   `user-agent` falso desde la consola—, no una prueba criptográfica: sirve
--   como un dato más si algún día se discute una firma, no como blindaje.
--
-- QUÉ NO SE PUDO PROBAR
--
--   El stack local completo de PostgREST/Kong de este proyecto no se pudo
--   levantar en esta sesión: sus puertos por defecto (54321/54323/54324/54329)
--   ya los tiene tomados OTRO proyecto local de esta misma Mac
--   (`cayla-retail`, con su propio stack sano), y este script no detiene
--   contenedores de otro proyecto sin que se lo pidan. Solo el contenedor de
--   Postgres de `cayla-dynamic` (puerto 54322) quedó arriba y sano.
--
--   Contra ESE Postgres, por psql directo (sin PostgREST), se probó dentro de
--   `begin … rollback`, prestando sesión con `set_config('request.jwt.claim.sub', …)`
--   —mismo mecanismo que ya usa `scripts/sql-manual/a_quien_le_falta_firmar.sql`—:
--
--     · una integrante en planilla, sin firma guardada → la función rechaza
--       con «Todavía no configuraste tu firma»;
--     · la misma, con firma guardada, sede con tarifa vigente → inserta la
--       fila, `estado` en el tablero pasa de 'sin_ruta' a 'ok';
--     · la misma persona llamando `fn_documentos_tablero(p_solo_mi_fila =>
--       true)` ve SOLO su fila — nunca las de sus compañeras, aunque sea
--       encargada de sede;
--     · admin llamando `fn_documentos_tablero()` sin argumentos sigue viendo
--       a TODO el equipo, exactamente las mismas filas que antes de esta
--       migración (se comparó el resultado byte a byte contra 0387 con una
--       persona ya firmada de antes).
--
--   Lo que NO se pudo probar así es que `current_setting('request.headers',
--   true)` de verdad traiga la IP en el PostgREST de este proyecto —eso exige
--   una llamada HTTP real, no una sesión de psql—. Queda pendiente probarlo
--   una vez que el stack completo pueda levantarse (o contra producción, con
--   cuidado, después de pegar esto), y no bloquea nada mientras tanto por lo
--   explicado arriba.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,numeric,boolean,numeric,integer);
--   drop function if exists fn_documentos_tablero(boolean);
--   drop function if exists fn_documentos_listar(uuid);
--   -- recrear fn_documentos_tablero con el cuerpo de la 0387;
--   -- recrear fn_documentos_listar con el cuerpo de la 0391;
--   alter table documentos_firmados
--     drop constraint if exists chk_documento_firma_persona_coherente,
--     drop column if exists firma_persona,
--     drop column if exists firma_persona_confirmada_at,
--     drop column if exists firma_persona_ip,
--     drop column if exists firma_persona_user_agent;
--
--   Las filas que ya se hayan firmado digitalmente quedan en `documentos_firmados`
--   como filas normales (siguen sirviendo su `ruta_declarada`/`monto_declarado`);
--   lo único que se pierde al revertir es la imagen y la evidencia, no el
--   registro de que existió.
-- ============================================================================


-- ── A · La evidencia de la firma, sobre la misma tabla ─────────────────────
alter table documentos_firmados
  add column if not exists firma_persona text,
  add column if not exists firma_persona_confirmada_at timestamptz,
  add column if not exists firma_persona_ip text,
  add column if not exists firma_persona_user_agent text;

alter table documentos_firmados drop constraint if exists chk_documento_firma_persona_coherente;
alter table documentos_firmados add constraint chk_documento_firma_persona_coherente check (
  (firma_persona is null and firma_persona_confirmada_at is null)
  or (firma_persona is not null and firma_persona_confirmada_at is not null
      and firma_persona ~ '^data:image/(png|jpeg);base64,')
);

comment on column documentos_firmados.firma_persona is
  'La firma de QUIEN DECLARA, congelada al momento de firmar (0423) — no una '
  'referencia viva a firmas_escaneadas, por la misma razón que contratos_generados '
  'no la usa: si cambia su firma general después, esta declaración sigue mostrando '
  'la que firmó. Solo se llena cuando el trámite fue digital; un escaneo subido a '
  'mano (admin, sigue existiendo) deja esta columna en null y usa storage_path.';

comment on column documentos_firmados.firma_persona_confirmada_at is
  'El instante exacto de la firma digital. Distinto de fecha_firma, que es la '
  'fecha (sin hora) que se usa en todo el sistema para ordenar y comparar contra '
  'la tarifa vigente — se llenan las dos a la vez, nunca una sin la otra.';


-- ── B · Firmar mi propia declaración, reemplazando el escaneo ──────────────
--
-- El físico de hoy (admin/documentacion) tiene CINCO datos que la persona
-- declara a mano: distrito y provincia de residencia, medios de transporte
-- por tramo (ida y vuelta), costo del pasaje y uso ocasional de taxi con su
-- costo y frecuencia. Para que la firma digital sostenga lo MISMO que el
-- papel, esta función pide esos mismos cinco datos y compone con ellos el
-- mismo texto que hoy queda escrito a mano — no un resumen más corto.
--
-- El monto NUNCA lo manda quien firma: lo calcula esta función con la MISMA
-- tarifa por sede que ya usa `fn_documentos_tablero` (0387) y el documento
-- impreso (`tarifaDeSede` en admin/documentacion/page.tsx). Aceptar un monto
-- por parámetro dejaría que cualquiera declarara el número que quisiera desde
-- la consola del navegador.
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

  -- Misma condición que fn_documento_registrar (0211) para tipo='ruta': un
  -- locador o alguien fuera de planilla no cobra movilidad, así que no tiene
  -- declaración que firmar. A propósito NO se revisa aquí el hueco de
  -- practicante — ver «QUÉ NO HACE» arriba.
  if not exists (
    select 1 from personas where id = v_yo and estado = 'activo' and en_planilla
  ) then
    raise exception 'No estás en planilla: no cobras movilidad, así que no tienes una declaración de ruta que firmar.';
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

  -- La MISMA tarifa por sede que usa fn_documentos_tablero (0387) y el
  -- documento impreso: la de SU sede si existe, si no la general.
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

  -- El mismo texto que hoy queda escrito a mano en el papel (ver el numerado
  -- 1-4 de la hoja en admin/documentacion/page.tsx), para que esta firma
  -- sostenga exactamente lo mismo.
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

  -- Evidencia MEJOR ESFUERZO — ver el encabezado de esta migración. Nunca
  -- bloquea la firma: si el GUC no está o no es el JSON esperado, las dos
  -- columnas quedan en null y el resto sigue igual.
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


-- ── C · fn_documentos_tablero: también contesta «solo mi fila» ────────────
-- Cuerpo vigente: 0387, copiado literal. Dos cambios, marcados CAMBIO 0423:
--   1. Parámetro nuevo `p_solo_mi_fila` (default false, no cambia ninguna
--      llamada existente) — sin él, un admin abriendo SU PROPIO /mio vería la
--      fila de cualquiera de sus compañeras (la primera que devuelva el
--      `order by`), no la suya: `fn_es_admin_o_lider() is true` la habría
--      dejado pasar igual que antes. Con el parámetro, `/mio` pide siempre
--      `p_solo_mi_fila => true` y ve SOLO la suya, sea quien sea.
--   2. Dos columnas nuevas de retorno: `ruta_firma_persona_confirmada_at` —si
--      no es null, la fila se firmó digitalmente (0423) y no con escaneo— y
--      `ruta_tarifa_vigente`, la tarifa de HOY para su sede, exista o no ya
--      una declaración firmada. Sin ella, /mio/movilidad no tendría forma de
--      mostrarle CUÁNTO va a declarar antes de firmar: `ruta_monto` solo trae
--      el monto de una firma que YA existe. El valor sale del mismo `tar.valor`
--      que esta función ya calculaba para decidir `ruta_desfasada` — no es un
--      join nuevo, es devolver uno que ya estaba.
-- Postgres no deja cambiar las columnas de salida con `create or replace`
-- —mismo motivo que ya documentaron la 0161, la 0388 y la 0402 para esta
-- misma familia de funciones—, de ahí el `drop function` explícito.
drop function if exists fn_documentos_tablero();

create function fn_documentos_tablero(p_solo_mi_fila boolean default false)
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
  ruta_firma_persona_confirmada_at timestamptz,  -- CAMBIO 0423
  ruta_tarifa_vigente numeric,                   -- CAMBIO 0423
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
           d.firma_persona_confirmada_at   -- CAMBIO 0423
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
    r.firma_persona_confirmada_at,   -- CAMBIO 0423
    tar.valor,                       -- CAMBIO 0423 (ruta_tarifa_vigente)
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
    and p.en_planilla
    -- ⇩⇩⇩ CAMBIO 0423 ⇩⇩⇩ Antes: `and fn_es_admin_o_lider() is true`. Es tu
    -- propia fila SIEMPRE, más TODAS si eres admin/líder Y no pediste
    -- `p_solo_mi_fila` — así /mio puede pedir «solo la mía» aunque quien
    -- pregunte sea admin, y admin/documentacion sigue viendo exactamente lo
    -- mismo que antes al no pasar el parámetro.
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
  '(0157/0161/0162/0165/0387/0423). Sin argumentos: todo el equipo, solo para '
  'admin/lider (vacio para cualquier otra persona). Con p_solo_mi_fila => true: '
  'unicamente la fila de quien pregunta, sea quien sea — la usa /mio para no '
  'depender de que quien mira su propia bandeja no sea ademas admin.';


-- ── D · fn_documentos_listar: también trae la firma digital ────────────────
-- Cuerpo vigente: 0391, copiado literal. Un cambio, marcado CAMBIO 0423: una
-- columna más de retorno (`firma_persona`) para que admin/documentacion pueda
-- estampar la firma de quien declaró al ver o imprimir su declaración —
-- mismo criterio que ya usa /mio/contrato con la firma de la empresa. Drop
-- explícito por el mismo motivo que en el bloque C.
drop function if exists fn_documentos_listar(uuid);

create function fn_documentos_listar(p_persona_id uuid default null)
returns table (
  id              uuid,
  alcance         text,
  persona_id      uuid,
  persona         text,
  tipo            text,
  fecha_firma     date,
  ruta_declarada  text,
  monto_declarado numeric,
  anio            integer,
  es_negativa     boolean,
  storage_path    text,
  nota            text,
  registrado_por  text,
  anulado_at      timestamptz,
  anulado_motivo  text,
  vigente         boolean,
  firma_persona   text   -- CAMBIO 0423
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
    d.firma_persona   -- CAMBIO 0423
  from documentos_firmados d
  left join personas p on p.id = d.persona_id
  left join personas reg on reg.id = d.registrado_por
  where (fn_es_admin_o_lider() is true or d.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or d.persona_id = p_persona_id)
  order by d.fecha_firma desc, d.created_at desc;
$$;

grant execute on function fn_documentos_listar(uuid) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (423, 'la_declaracion_de_ruta_ya_no_necesita_escaneo')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from information_schema.columns
    where table_name = 'documentos_firmados' and column_name = 'firma_persona_confirmada_at') = 1
    as columnas_de_firma_puestas,
  (select prosrc like '%CAMBIO 0423%' from pg_proc
    where proname = 'fn_documentos_tablero' and pronargs = 1)
    as tablero_al_dia,
  (select prosrc like '%CAMBIO 0423%' from pg_proc
    where proname = 'fn_documentos_listar' and pronargs = 1)
    as listar_al_dia,
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_declaracion_ruta') = 1
    as funcion_de_firma_puesta;
