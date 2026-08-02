-- ============================================================================
-- 0124 — La ficha personal guarda lo que hace falta, y el DNI se puede corregir
--
-- QUÉ PROMETE. Cierra cuatro huecos de la pantalla de Datos Personales, elegidos
-- con el criterio de que un campo solo vale si algo lo lee:
--
--   A · EL DNI SE PUEDE EDITAR. Hoy `personas.documento` se muestra y no se
--       escribe desde ninguna pantalla: solo entra al crear la persona. El DNI de
--       Angie Chávez estuvo mal un mes (77025131 por 77035131, un dígito del
--       Excel del contador) y hubo que arreglarlo por SQL. Ese número se imprime
--       en los memos disciplinarios (disciplina/memo/[id]) y en los tres
--       documentos de la pantalla de Documentación: un papel legal con el DNI
--       equivocado es un papel que se cae si alguien lo discute.
--
--   B · EL RÉGIMEN DE PENSIÓN SE PUEDE ELEGIR. Mismo problema que el DNI y peor
--       consecuencia: `personas.regimen_pension` decide la tasa que se le
--       descuenta a cada uno (0114) y solo se podía cambiar por SQL.
--
--   C · LOS DERECHOHABIENTES, CON NOMBRE Y DNI. Hasta hoy el sistema solo sabía
--       `hijos_menores` sí/no. Eso alcanza para el cálculo — bajo MYPE la
--       asignación familiar no aplica — pero no para saber A QUIÉN cubre EsSalud
--       ni a quién le paga el Seguro Vida Ley.
--
--   D · CONTACTO DE EMERGENCIA Y DISCAPACIDAD. El primero no lo pide ninguna ley
--       y es obvio para un equipo de tienda. El segundo lo pregunta el T-Registro.
--
-- QUÉ ASUME. personas, datos_personales (0061), correcciones_auditoria,
--   tasas_pension (0114), y los helpers de RLS.
--
-- NO MUEVE NINGÚN PAGO. No toca fn_planilla_calcular ni ninguna función de
--   cálculo. Lo único que puede cambiar plata es que alguien use
--   fn_set_regimen_pension para corregir un régimen — y eso es justamente el
--   punto: hoy ese dato está mal o falta en 12 personas.
--
-- CÓMO SE REVIERTE. Soltar la tabla derechohabientes, las tres funciones nuevas
--   y las seis columnas nuevas de datos_personales, y restaurar
--   fn_set_datos_personales desde la 0061.
-- ============================================================================


-- ── A · El DNI, con rastro ───────────────────────────────────────────────────
-- Función propia y no un campo más de fn_set_datos_personales, por dos razones:
-- el DNI vive en `personas` y no en `datos_personales`, y un cambio de DNI
-- merece su propia entrada de auditoría con motivo — no se confunde con haber
-- corregido un celular.

create or replace function fn_set_documento(p_persona_id uuid, p_documento text, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes text;
  v_nuevo text;
  v_quien uuid;
  v_otro  text;
begin
  -- Guard null-safe, como manda el estándar del repo: un null no pasa como
  -- autorizado. Se exige admin o líder: el DNI se imprime en papeles legales, así
  -- que no lo edita la encargada ni la propia persona.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el número de documento.';
  end if;

  v_nuevo := nullif(btrim(coalesce(p_documento, '')), '');

  if v_nuevo is null then
    raise exception 'El número de documento no puede quedar vacío. Si está mal, se corrige; no se borra.';
  end if;

  -- Se acepta DNI peruano (8 dígitos, con el cero adelante que traen los de
  -- generación anterior: Carmen Sanándres es 08817189) y carné de extranjería,
  -- que es alfanumérico. Nada más, para que no entre un nombre por error.
  if v_nuevo !~ '^[0-9A-Za-z]{8,12}$' then
    raise exception 'Documento inválido: «%». Se esperan entre 8 y 12 caracteres sin espacios ni guiones.', v_nuevo;
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo es obligatorio: este número se imprime en memos y contratos.';
  end if;

  select documento into v_antes from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  if v_antes = v_nuevo then
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

  update personas set documento = v_nuevo where id = p_persona_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.documento',
          coalesce(v_antes, '(vacío)'), v_nuevo, btrim(p_motivo), v_quien);
end;
$$;

comment on function fn_set_documento(uuid, text, text) is
  'Corrige el número de documento de una persona. Solo admin o líder, motivo obligatorio '
  'y rastro en correcciones_auditoria, porque el DNI se imprime en memos disciplinarios y '
  'en los documentos de respaldo de los conceptos no remunerativos.';

revoke all    on function fn_set_documento(uuid, text, text) from public, anon;
grant execute on function fn_set_documento(uuid, text, text) to authenticated;

-- Un DNI repetido es siempre un error. Se crea el índice solo si los datos de hoy
-- lo permiten: si hay duplicados, la migración NO falla — avisa cuáles son y
-- sigue, para que se puedan limpiar y volver a correr esto.
do $mig$
declare v_dups text;
begin
  select string_agg(documento || ' (' || n || ' personas)', ', ')
    into v_dups
  from (select documento, count(*) as n
        from personas
        where documento is not null
        group by documento
        having count(*) > 1) d;

  if v_dups is null then
    create unique index if not exists idx_personas_documento_unico
      on personas (documento) where documento is not null;
    raise notice '0124 · índice único de documento creado: no hay DNI repetidos.';
  else
    raise notice '0124 · ⚠ NO se creó el índice único de documento porque hay repetidos: %', v_dups;
    raise notice '0124 · limpiá esos casos y volvé a correr esta migración (es idempotente).';
  end if;
end
$mig$;


-- ── B · El régimen de pensión, con rastro ────────────────────────────────────
-- La lista válida NO se repite acá: se lee de tasas_pension, que es la tabla que
-- ya define los regímenes (0114). Así, el día que entre una AFP nueva, se agrega
-- una fila y esta función la acepta sola.

create or replace function fn_set_regimen_pension(p_persona_id uuid, p_regimen text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes text;
  v_nuevo text;
  v_quien uuid;
  v_tasa  numeric;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el régimen de pensión.';
  end if;

  v_nuevo := nullif(btrim(lower(coalesce(p_regimen, ''))), '');

  -- null es un valor legítimo: significa «todavía no sabemos», y la 0114 lo
  -- resuelve cayendo a la tasa global. Es mejor que inventar un régimen.
  if v_nuevo is not null and not exists (
       select 1 from tasas_pension where regimen = v_nuevo) then
    raise exception 'Régimen «%» desconocido. Los cargados son: %.',
      v_nuevo,
      (select string_agg(distinct regimen, ', ' order by regimen) from tasas_pension);
  end if;

  select regimen_pension into v_antes from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  if coalesce(v_antes, '∅') = coalesce(v_nuevo, '∅') then
    return;
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  update personas set regimen_pension = v_nuevo where id = p_persona_id;

  -- La tasa que va a regir, para que el rastro diga cuánta plata mueve el cambio
  -- y no solo el nombre del régimen.
  select tp.aporte + tp.comision + tp.prima into v_tasa
  from tasas_pension tp
  where tp.regimen = v_nuevo and tp.vigente_hasta is null
  limit 1;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.regimen_pension',
          coalesce(v_antes, '(sin régimen)'), coalesce(v_nuevo, '(sin régimen)'),
          case
            when v_nuevo is null
              then 'Se quita el régimen: el descuento vuelve a la tasa global hasta que se sepa el verdadero.'
            -- round()::text y NO to_char: 'FM99D99' deja el separador colgando
            -- («13.» en vez de «13.00»), y el símbolo depende del locale del
            -- servidor. Esto sale siempre igual: 13.00, 12.92.
            else 'Régimen de pensión corregido. Desde el próximo cálculo se le descuenta el '
                 || round(coalesce(v_tasa, 0) * 100, 2)::text || ' por ciento de su remuneración asegurable.'
          end,
          v_quien);
end;
$$;

comment on function fn_set_regimen_pension(uuid, text) is
  'Asigna el régimen pensionario de una persona (los códigos válidos salen de tasas_pension). '
  'NULL es válido y significa «no sabemos»: la 0114 cae a la tasa global. Deja rastro con la '
  'tasa que va a regir, porque el cambio mueve el descuento de la boleta.';

revoke all    on function fn_set_regimen_pension(uuid, text) from public, anon;
grant execute on function fn_set_regimen_pension(uuid, text) to authenticated;


-- ── C · Los derechohabientes ─────────────────────────────────────────────────
-- UNA tabla para dos propósitos, y no dos tablas. Las personas son casi siempre
-- las mismas —cónyuge e hijos— y separarlas garantizaría que en seis meses una
-- esté al día y la otra no. Se distingue con dos banderas:
--
--   essalud   · está inscrito como derechohabiente ante SUNAT (formulario 1602)
--   vida_ley  · está declarado como beneficiario del Seguro de Vida Ley
--
-- POR QUÉ vida_ley ES UNA BANDERA Y NO UN PORCENTAJE. El D.Leg. 688 fija por ley
-- el orden y la proporción (cónyuge o conviviente, descendientes, y en su defecto
-- ascendientes y hermanos menores). La declaración jurada IDENTIFICA a los
-- beneficiarios; no reparte a criterio del trabajador. Guardar un porcentaje
-- editable sería inventar una facultad que la norma no da, y abriría la puerta a
-- que la aseguradora discuta el reparto.
create table if not exists derechohabientes (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id) on delete cascade,

  nombres        text not null,
  apellidos      text not null,
  documento      text,          -- puede faltar: un recién nacido tarda en tener DNI
  fecha_nacimiento date,

  vinculo        text not null
                   check (vinculo in ('conyuge','conviviente','hijo','madre','padre','hermano','otro')),

  essalud        boolean not null default false,
  vida_ley       boolean not null default false,

  -- No se borra a un derechohabiente: se cierra. Un hijo que cumple 18 deja de
  -- estar cubierto, pero el periodo en que sí lo estuvo tiene que seguir siendo
  -- explicable — igual que las personas, que nunca se borran.
  vigente_hasta  date,
  nota           text,

  registrado_por uuid references personas(id),
  created_at     timestamptz not null default now(),

  -- Un hijo menor incapacitado sigue cubierto de adulto, así que la edad NO se
  -- valida acá: lo decide quien inscribe ante SUNAT, no esta tabla.
  check (vinculo <> 'hijo' or fecha_nacimiento is not null)
);

comment on table derechohabientes is
  'Familiares de cada integrante, con dos propósitos en una sola tabla: la bandera essalud '
  'dice si están inscritos ante SUNAT (formulario 1602) y la bandera vida_ley si están '
  'declarados como beneficiarios del Seguro de Vida Ley (D.Leg. 688). No se borran: se cierran '
  'con vigente_hasta, para que el periodo en que estuvieron cubiertos siga siendo explicable.';

comment on column derechohabientes.vida_ley is
  'Declarado como beneficiario del Seguro de Vida Ley. Es una bandera y no un porcentaje '
  'porque el D.Leg. 688 fija el orden y la proporción por ley: la declaración jurada '
  'identifica a los beneficiarios, no reparte a criterio del trabajador.';

create index if not exists idx_derechohabientes_persona
  on derechohabientes (persona_id) where vigente_hasta is null;

alter table derechohabientes enable row level security;

-- Mismo criterio de visibilidad que datos_personales (0061): son datos de la
-- familia de alguien, así que se copia esa regla en vez de inventar otra.
drop policy if exists dh_select_admin_lider on derechohabientes;
create policy dh_select_admin_lider on derechohabientes
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists dh_select_supervisor on derechohabientes;
create policy dh_select_supervisor on derechohabientes
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists dh_select_propia on derechohabientes;
create policy dh_select_propia on derechohabientes
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- Escritura solo por función, como todo en este repo.
create or replace function fn_set_derechohabiente(
  p_id               uuid,          -- null = nuevo
  p_persona_id       uuid,
  p_nombres          text,
  p_apellidos        text,
  p_vinculo          text,
  p_documento        text default null,
  p_fecha_nacimiento date default null,
  p_essalud          boolean default false,
  p_vida_ley         boolean default false,
  p_nota             text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    uuid;
  v_sede  uuid;
begin
  select sede_base_id into v_sede from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  -- Mismo permiso que fn_set_datos_personales: admin/líder, la encargada de su
  -- sede, o la propia persona. Decisión de Felipe del 2026-08-01.
  if not (fn_es_admin_o_lider()
          or p_persona_id = fn_persona_actual_id()
          or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) then
    raise exception 'Sin permiso para editar los familiares de esta persona.';
  end if;

  if nullif(btrim(coalesce(p_nombres, '')), '') is null
     or nullif(btrim(coalesce(p_apellidos, '')), '') is null then
    raise exception 'El nombre y el apellido del familiar son obligatorios.';
  end if;

  if p_id is null then
    insert into derechohabientes
      (persona_id, nombres, apellidos, documento, fecha_nacimiento, vinculo,
       essalud, vida_ley, nota, registrado_por)
    values
      (p_persona_id, btrim(p_nombres), btrim(p_apellidos),
       nullif(btrim(coalesce(p_documento, '')), ''), p_fecha_nacimiento, p_vinculo,
       coalesce(p_essalud, false), coalesce(p_vida_ley, false),
       nullif(btrim(coalesce(p_nota, '')), ''), fn_persona_actual_id())
    returning id into v_id;
  else
    update derechohabientes set
      nombres = btrim(p_nombres), apellidos = btrim(p_apellidos),
      documento = nullif(btrim(coalesce(p_documento, '')), ''),
      fecha_nacimiento = p_fecha_nacimiento, vinculo = p_vinculo,
      essalud = coalesce(p_essalud, false), vida_ley = coalesce(p_vida_ley, false),
      nota = nullif(btrim(coalesce(p_nota, '')), '')
    where id = p_id and persona_id = p_persona_id
    returning id into v_id;

    if v_id is null then
      raise exception 'No encontré ese familiar en la ficha de esta persona.';
    end if;
  end if;

  return v_id;
end;
$$;

revoke all    on function fn_set_derechohabiente(uuid,uuid,text,text,text,text,date,boolean,boolean,text) from public, anon;
grant execute on function fn_set_derechohabiente(uuid,uuid,text,text,text,text,date,boolean,boolean,text) to authenticated;

-- Cerrar, no borrar.
create or replace function fn_cerrar_derechohabiente(p_id uuid, p_hasta date default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_persona uuid; v_sede uuid;
begin
  select d.persona_id, p.sede_base_id into v_persona, v_sede
  from derechohabientes d join personas p on p.id = d.persona_id
  where d.id = p_id;

  if not found then
    raise exception 'Ese familiar no existe.';
  end if;

  if not (fn_es_admin_o_lider()
          or v_persona = fn_persona_actual_id()
          or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) then
    raise exception 'Sin permiso para editar los familiares de esta persona.';
  end if;

  update derechohabientes
     set vigente_hasta = coalesce(p_hasta, current_date)
   where id = p_id;
end;
$$;

revoke all    on function fn_cerrar_derechohabiente(uuid, date) from public, anon;
grant execute on function fn_cerrar_derechohabiente(uuid, date) to authenticated;


-- ── D · Emergencia y discapacidad ────────────────────────────────────────────
alter table datos_personales add column if not exists emergencia_nombre    text;
alter table datos_personales add column if not exists emergencia_vinculo   text;
alter table datos_personales add column if not exists emergencia_telefono  text;
alter table datos_personales add column if not exists discapacidad         boolean;
alter table datos_personales add column if not exists discapacidad_conadis text;

comment on column datos_personales.discapacidad_conadis is
  'Número del certificado o carné del CONADIS. Se guarda porque la deducción adicional de la '
  'Ley 29973 exige el certificado, no la declaración: sin el número el beneficio no se sustenta. '
  'Hoy CAYLA no tiene a nadie en planilla con discapacidad (Carlos Espejo está por honorarios, '
  'y la deducción solo aplica en planilla), así que el campo es de valor futuro.';


-- ── Y la función de escritura, extendida ─────────────────────────────────────
-- ⚠️ OJO CON LA SEMÁNTICA DE ESTA FUNCIÓN. Es un upsert que REEMPLAZA todas las
-- columnas: lo que no se pasa queda en NULL. No es un «update parcial». Por eso
-- la pantalla tiene que mandar SIEMPRE los quince campos, y por eso agregar una
-- columna acá obliga a tocar la pantalla en el mismo cambio — si no, el primer
-- guardado borra lo nuevo.
--
-- Se dejó así (y no como update parcial con coalesce) porque un formulario que
-- muestra un campo vacío tiene que poder VACIARLO al guardar; con coalesce,
-- borrar un dato sería imposible.
create or replace function fn_set_datos_personales(
  p_persona_id uuid,
  p_nombre_dni text default null, p_fecha_nacimiento date default null, p_estado_civil text default null,
  p_direccion text default null, p_celular text default null,
  p_entidad_bancaria text default null, p_numero_cuenta text default null,
  p_grado_instruccion text default null, p_hijos_menores boolean default null,
  p_foto_dni_url text default null, p_foto_personal_url text default null, p_foto_profesional_url text default null,
  -- CAMBIO 0124
  p_emergencia_nombre text default null, p_emergencia_vinculo text default null,
  p_emergencia_telefono text default null,
  p_discapacidad boolean default null, p_discapacidad_conadis text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (fn_es_admin_o_lider()
          or p_persona_id = fn_persona_actual_id()
          or (fn_rol_actual() = 'supervisor_sede'
              and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona())) then
    raise exception 'Sin permiso para editar los datos personales de esta persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;
  insert into datos_personales as dp (
    persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular,
    entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores,
    foto_dni_url, foto_personal_url, foto_profesional_url,
    emergencia_nombre, emergencia_vinculo, emergencia_telefono,
    discapacidad, discapacidad_conadis,
    actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url,
    p_emergencia_nombre, p_emergencia_vinculo, p_emergencia_telefono,
    p_discapacidad, p_discapacidad_conadis,
    fn_persona_actual_id(), now())
  on conflict (persona_id) do update set
    nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento,
    estado_civil = excluded.estado_civil, direccion = excluded.direccion, celular = excluded.celular,
    entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta,
    grado_instruccion = excluded.grado_instruccion, hijos_menores = excluded.hijos_menores,
    foto_dni_url = excluded.foto_dni_url, foto_personal_url = excluded.foto_personal_url,
    foto_profesional_url = excluded.foto_profesional_url,
    emergencia_nombre = excluded.emergencia_nombre,
    emergencia_vinculo = excluded.emergencia_vinculo,
    emergencia_telefono = excluded.emergencia_telefono,
    discapacidad = excluded.discapacidad,
    discapacidad_conadis = excluded.discapacidad_conadis,
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$$;

grant execute on function fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,
  text,text,text,boolean,text) to authenticated;

-- La firma vieja de 13 argumentos se deja caer: si sobrevive, la pantalla podría
-- llamarla por error y las cinco columnas nuevas se borrarían en silencio en cada
-- guardado. Es exactamente el tipo de fallo que no avisa.
drop function if exists fn_set_datos_personales(
  uuid,text,date,text,text,text,text,text,text,boolean,text,text,text);


insert into migraciones_aplicadas (numero, nombre)
values (124, 'la_ficha_personal_completa')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
