-- ============================================================================
-- 0157 — Los documentos firmados entran al sistema
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el papel que sostiene un concepto no remunerativo viva DENTRO del
--   sistema, atado a la persona que lo firmó y a la fecha en que lo hizo — y no
--   en una carpeta que alguien puede mover. Y que se pueda responder, sin abrir
--   ninguna carpeta, «¿a quién le falta firmar?».
--
-- QUÉ ASUME
--   · `personas.en_planilla` (generada desde `tipo_vinculo`) decide a quién se le
--     exige: un locador no cobra movilidad (0117), así que no tiene nada que
--     firmar. Fue lo primero que Felipe corrigió del diseño.
--   · `fn_es_admin_o_lider()` (admin y lider_do) y `fn_persona_actual_id()`.
--   · Esta migración NO toca la planilla. El candado que condiciona el pago va
--     en la 0158, y nace apagado.
--
-- POR QUÉ UNA TABLA PROPIA Y NO `expediente_adjuntos`
--   Esa tabla exige un `documento_id` de `expediente_disciplinario`, y sus
--   permisos preguntan «¿este path es un memo firmado?». Una declaración de ruta
--   no es un memo y jamás lo será: meterla ahí obligaría a inventar expedientes
--   falsos y a que esa función tuviera una rama por cada clase de papel. Un
--   bucket y una tabla por clase de documento, cada uno con su regla legible, es
--   el mismo criterio con el que la 0136 le dio bucket propio a los comprobantes.
--
-- POR QUÉ EL ALCANCE SE DECLARA Y NO SE DEDUCE
--   La política de movilidad es de la empresa: no es de nadie en particular, así
--   que su fila no lleva persona. Deducir «sin persona = de empresa» dejaba dos
--   estados indistinguibles: el documento institucional y la declaración de ruta
--   que alguien guardó mal. Con el candado del pago encendido, el segundo haría
--   que esa persona dejara de cobrar movilidad, y el motivo estaría escondido en
--   una fila que se ve normal.
--
--   Por eso la fila DICE su alcance, y tres constraints hacen imposibles las
--   combinaciones absurdas: una ruta sin persona, una política atribuida a
--   alguien, o un bono sin el año del que es. Un candado en el esquema vale más
--   que diez validaciones en la pantalla, porque la pantalla se puede saltar
--   llamando la función.
--
-- POR QUÉ SE VERSIONA Y NO SE REEMPLAZA
--   Una declaración de ruta no vence: vale hasta que la persona se mude o cambie
--   de ciudad (precisión de Felipe, y por eso NO lleva fecha de fin ni semáforo
--   que fastidie cada mes — a diferencia del comprobante de educación, que sí
--   cubre un ciclo). Pero cuando cambia, la anterior no se pisa: si un inspector
--   pregunta por un pago de marzo, tiene que existir el papel que regía en marzo.
--
-- POR QUÉ SE GUARDA EL MONTO Y LA RUTA, Y NO EL PDF GENERADO
--   El escaneo firmado ES una foto del documento impreso: ya contiene el texto
--   entero más la firma. Guardar también el PDF generado es guardar el mismo
--   texto dos veces y crear la pregunta «¿cuál vale?» cada vez que alguien abre
--   la carpeta. Lo que un PDF NO permite es consultarse: guardando la ruta y el
--   monto como campos, el sistema puede avisar solo cuando el monto firmado deja
--   de coincidir con la tarifa vigente — y si el escaneo sale borroso, sigue
--   sabiéndose qué decía el papel.
--
-- CÓMO SE REVIERTE
--   drop table documentos_firmados;  (borra también los registros: los archivos
--   quedan en el bucket y hay que vaciarlo aparte)
--   drop function fn_documento_registrar(...), fn_documento_anular(uuid,text),
--        fn_documentos_listar(), fn_documentos_tablero();
--   delete from storage.buckets where id = 'documentos';
--   Y devolver el bucket `expedientes` a su estado sin límites.
-- ============================================================================


-- ── A · El bucket de expedientes, que estaba abierto de par en par ─────────
-- Encontrado de paso: `expedientes` no tenía límite de tamaño NI lista de
-- formatos. Cualquier archivo, de cualquier peso, al bucket que guarda los
-- papeles más delicados del sistema. Se cierra igual que `comprobantes` — dos
-- buckets del mismo sistema con reglas distintas significa que una está mal.
update storage.buckets
   set file_size_limit    = 50 * 1024 * 1024,
       allowed_mime_types = array['image/jpeg','image/png','image/heic','image/webp','application/pdf']
 where id = 'expedientes';


-- ── B · El bucket de los documentos firmados ───────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documentos', 'documentos', false,
  50 * 1024 * 1024,
  array['image/jpeg','image/png','image/heic','image/webp','application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- ── C · La tabla ───────────────────────────────────────────────────────────
create table if not exists documentos_firmados (
  id              uuid primary key default gen_random_uuid(),

  -- Lo que hace que un hueco deje de ser una ambigüedad.
  alcance         text not null check (alcance in ('individual', 'empresa')),
  persona_id      uuid references personas(id) on delete restrict,

  tipo            text not null check (tipo in ('ruta', 'politica', 'bono')),
  storage_path    text,
  fecha_firma     date not null,

  -- Con qué se generó el documento. No es decoración: con esto el sistema avisa
  -- cuando el monto firmado deja de coincidir con la tarifa vigente, sin que
  -- nadie tenga que abrir el archivo.
  ruta_declarada  text,
  monto_declarado numeric(10,2) check (monto_declarado is null or monto_declarado >= 0),

  -- Solo para el bono: de qué año es la constancia. El bono se paga una vez al
  -- año, íntegro, en el mes del onomástico; así que se firma una vez por año.
  anio            integer check (anio is null or anio between 2020 and 2100),

  -- Se ofreció firmar y la persona se negó. Se documenta —queda constancia de
  -- que se ofreció— pero NO habilita el pago: sin pacto individual firmado el
  -- monto no es no remunerativo, y pagarlo igual es lo que la RTF 05449-4-2007
  -- sanciona. El acta con testigo se sube igual, en `storage_path`.
  es_negativa     boolean not null default false,

  nota            text,
  registrado_por  uuid not null references personas(id),
  created_at      timestamptz not null default now(),

  -- Nada se borra. Si se sube el papel de otra persona, tiene que quedar rastro
  -- de que pasó y de quién lo corrigió.
  anulado_at      timestamptz,
  anulado_por     uuid references personas(id),
  anulado_motivo  text,

  constraint doc_alcance_coherente check (
    (alcance = 'individual' and persona_id is not null)
    or (alcance = 'empresa' and persona_id is null)
  ),
  constraint doc_politica_es_de_empresa check (
    tipo <> 'politica' or alcance = 'empresa'
  ),
  constraint doc_ruta_y_bono_son_individuales check (
    tipo not in ('ruta', 'bono') or alcance = 'individual'
  ),
  constraint doc_bono_lleva_su_anio check (
    tipo <> 'bono' or anio is not null
  ),
  -- Una negativa no lleva monto firmado: no se firmó nada.
  constraint doc_negativa_sin_monto check (
    not es_negativa or monto_declarado is null
  ),
  constraint doc_anulado_con_motivo check (
    (anulado_at is null and anulado_por is null and anulado_motivo is null)
    or (anulado_at is not null and anulado_por is not null
        and anulado_motivo is not null and length(trim(anulado_motivo)) >= 3)
  )
);

comment on table documentos_firmados is
  'Los papeles firmados que sostienen los conceptos no remunerativos: la declaración '
  'de ruta que respalda la movilidad (D.S. 001-97-TR art. 19 e), la política de '
  'movilidad de la empresa, y la constancia del bono de cumpleaños (art. 19 g). '
  'Se versiona: la firma más reciente rige y las anteriores quedan, porque un pago '
  'de marzo se defiende con el papel que regía en marzo.';

comment on column documentos_firmados.alcance is
  'individual = lo firma una persona · empresa = lo emite CAYLA y no es de nadie. '
  'Se declara y no se deduce del hueco en persona_id: un hueco no explica por qué '
  'está vacío, y una declaración de ruta guardada sin persona sería indistinguible '
  'de un documento institucional.';

-- Un bono por persona y por año. Las anuladas y las negativas no ocupan el sitio:
-- quien se negó un año puede firmar al siguiente.
create unique index if not exists idx_documentos_bono_uno_por_anio
  on documentos_firmados (persona_id, anio)
  where tipo = 'bono' and anulado_at is null and not es_negativa;

create index if not exists idx_documentos_persona_tipo
  on documentos_firmados (persona_id, tipo, fecha_firma desc)
  where anulado_at is null;

alter table documentos_firmados enable row level security;

-- Leer: DO todo, cada quien lo suyo. El papel que sostiene el propio pago no
-- debería ser secreto para quien lo firmó. Escribir NO se concede: pasa por
-- función, igual que marcajes, expedientes y salarios.
drop policy if exists documentos_lectura on documentos_firmados;
create policy documentos_lectura on documentos_firmados
  for select to authenticated
  using (fn_es_admin_o_lider() is true or persona_id = fn_persona_actual_id());


-- ── D · Los archivos del bucket ────────────────────────────────────────────
-- El path es "documentos/<id de la fila>.<ext>": el archivo se nombra con la
-- fila que lo declara, así que no hay forma de subir uno que no corresponda.
create or replace function fn_documento_puede_ver(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id      text;
  v_persona uuid;
begin
  if split_part(p_path, '/', 1) <> 'documentos' then return false; end if;
  v_id := split_part(split_part(p_path, '/', 2), '.', 1);
  -- Se valida ANTES de castear: un path con basura debe negarse limpio, no
  -- reventar con un error de casteo (misma forma que fn_expediente_puede_adjuntar).
  if v_id !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  if fn_es_admin_o_lider() is true then return true; end if;

  select d.persona_id into v_persona from documentos_firmados d where d.id = v_id::uuid;
  return v_persona = fn_persona_actual_id();
end;
$$;

grant execute on function fn_documento_puede_ver(text) to authenticated;

drop policy if exists documentos_insert on storage.objects;
create policy documentos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and split_part(name, '/', 1) = 'documentos'
    and fn_es_admin_o_lider() is true
  );

drop policy if exists documentos_select on storage.objects;
create policy documentos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'documentos' and fn_documento_puede_ver(name));

drop policy if exists documentos_delete on storage.objects;
create policy documentos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'documentos'
    and split_part(name, '/', 1) = 'documentos'
    and fn_es_admin_o_lider() is true
  );


-- ── E · Registrar ──────────────────────────────────────────────────────────
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
    -- Un locador no cobra movilidad (0117), así que no tiene declaración que
    -- firmar. Pedírsela sería pedirle un papel que no sostiene ningún pago suyo.
    if p_tipo = 'ruta' and not exists (
      select 1 from personas where id = p_persona_id and en_planilla
    ) then
      raise exception 'Esa persona no está en planilla: no cobra movilidad, así que no necesita declarar su ruta.';
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


-- ── F · Anular, que no es borrar ───────────────────────────────────────────
create or replace function fn_documento_anular(p_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r documentos_firmados%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional anula documentos firmados.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se anula. Si el archivo era de otra persona, eso tiene que quedar dicho.';
  end if;

  select * into r from documentos_firmados where id = p_id;
  if not found then raise exception 'Ese documento no existe.'; end if;
  if r.anulado_at is not null then raise exception 'Ese documento ya estaba anulado.'; end if;

  update documentos_firmados
     set anulado_at = now(), anulado_por = fn_persona_actual_id(), anulado_motivo = trim(p_motivo)
   where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (coalesce(r.persona_id, fn_persona_actual_id()), 'documento_anulado',
     r.tipo || ' · firmado el ' || r.fecha_firma::text, 'anulado',
     fn_persona_actual_id(), trim(p_motivo));
end;
$$;

grant execute on function fn_documento_anular(uuid, text) to authenticated;


-- ── G · El tablero: a quién le falta ───────────────────────────────────────
-- Se arma de la gente EN PLANILLA, no de una lista escrita a mano: quien entra
-- aparece pendiente desde su primer día sin que nadie la agregue, y un locador
-- no aparece nunca porque no cobra movilidad.
create or replace function fn_documentos_tablero()
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
  estado            text
)
language sql
stable
security definer
set search_path = public
as $$
  with tarifa as (
    select max(valor) as vigente
    from parametros_laborales
    where clave = 'movilidad_diaria'
      and vigente_desde <= fn_hoy_lima()
      and (vigente_hasta is null or vigente_hasta >= fn_hoy_lima())
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
           d.persona_id, d.id, d.anio
    from documentos_firmados d
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = extract(year from fn_hoy_lima())::int
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
    (r.monto_declarado is not null
      and (select vigente from tarifa) is not null
      and r.monto_declarado <> (select vigente from tarifa)),
    b.id, b.anio,
    case
      when r.id is null                    then 'sin_ruta'
      when coalesce(r.es_negativa, false)  then 'se_nego'
      else 'ok'
    end
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join ruta r on r.persona_id = p.id
  left join bono b on b.persona_id = p.id
  where p.estado = 'activo'
    and p.en_planilla
    and fn_es_admin_o_lider() is true
  order by (r.id is not null), p.apellidos;
$$;

grant execute on function fn_documentos_tablero() to authenticated;

-- Lo firmado de una persona (o todo, si es DO). Incluye lo anulado para que se
-- pueda ver qué pasó, con su motivo.
create or replace function fn_documentos_listar(p_persona_id uuid default null)
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
  vigente         boolean
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
    -- Vigente = es la más reciente de su tipo para esa persona, y no está anulada.
    (d.anulado_at is null and d.id = (
       select d2.id from documentos_firmados d2
        where d2.tipo = d.tipo and d2.anulado_at is null
          and d2.persona_id is not distinct from d.persona_id
        order by d2.fecha_firma desc, d2.created_at desc limit 1))
  from documentos_firmados d
  left join personas p on p.id = d.persona_id
  left join personas reg on reg.id = d.registrado_por
  where (fn_es_admin_o_lider() is true or d.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or d.persona_id = p_persona_id)
  order by d.fecha_firma desc, d.created_at desc;
$$;

grant execute on function fn_documentos_listar(uuid) to authenticated;


-- ── H · El interruptor del candado, apagado ────────────────────────────────
-- Se escribe ahora y se enciende después: hoy nadie tiene su declaración
-- cargada, así que encenderlo dejaría a 22 personas sin movilidad por un trámite
-- que recién arranca. Encenderlo es UNA sentencia, y queda su fecha:
--
--   insert into parametros_laborales (clave, valor, vigente_desde, sustento)
--   values ('movilidad_exige_declaracion', 1, '2026-08-29',
--           'Convenios individuales de movilidad completos. RTF 05449-4-2007.');
--
-- La 0158 es la que lo consulta. Mientras el valor vigente sea 0, la planilla
-- paga exactamente como hoy.
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
select 'movilidad_exige_declaracion', 0, '2020-01-01',
       'Apagado. La declaración de ruta todavía no condiciona el pago de movilidad: '
       'se enciende insertando una fila con valor 1 y la fecha desde la que se exige, '
       'cuando el tablero de Documentación esté completo. Escrito por la 0157.'
where not exists (
  select 1 from parametros_laborales where clave = 'movilidad_exige_declaracion'
);


insert into migraciones_aplicadas (numero, nombre)
values (157, 'los_documentos_firmados_entran_al_sistema')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_personas int;
  v_exp      bigint;
begin
  select count(*) into v_personas from personas where estado = 'activo' and en_planilla;
  select file_size_limit into v_exp from storage.buckets where id = 'expedientes';

  raise notice '0157 · personas en planilla que necesitan declaracion de ruta: %', v_personas;
  raise notice '0157 · documentos firmados cargados: 0 (la tabla nace vacia)';
  raise notice '0157 · bucket expedientes cerrado a % MB (antes: sin limite)', round(v_exp/1024.0/1024.0);
  raise notice '0157 · el candado del pago esta APAGADO. Esta migracion no cambia ningun pago.';
end $mig$;
