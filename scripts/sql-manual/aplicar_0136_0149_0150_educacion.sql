-- ============================================================================
-- PARA PEGAR EN EL SQL EDITOR DE SUPABASE — la asignación por educación
-- ============================================================================
-- Junta las tres migraciones en el orden en que tienen que aplicarse:
--
--   0136 · el bucket de comprobantes, sus políticas y las funciones de la pantalla
--   0149 · las reglas (monto calculado, techo sobre la suma, candados, auditoría)
--   0150 · la planilla suma, exige el comprobante y nombra la institución
--
-- ORDEN OBLIGATORIO. La 0150 asume que la 0149 ya validó el techo sobre la suma:
-- aplicar la 0150 sola dejaría a la planilla sumando filas sin techo que las
-- controle, y dos asignaciones de S/170 pasarían un techo de S/180.
--
-- QUÉ MUEVE AL PEGARLO: nada, hoy. `asignaciones_educacion` está vacía, así que
-- las tres juntas no cambian un céntimo de ninguna planilla. Lo que cambian es
-- lo que va a pasar en cuanto se cargue la primera asignación desde
-- /admin/educacion.
--
-- LO QUE SÍ CONVIENE MIRAR DESPUÉS DE PEGAR: los avisos que imprime al final.
-- Si dice «asignaciones guardadas SIN comprobante», esas no están pagando.
--
-- ANTES DE PEGAR, la sesión de admin que exigen algunas funciones:
--
--   select set_config('request.jwt.claim.sub',
--     (select auth_user_id::text from personas
--       where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
--     true);
--
-- Generado el 2026-08-04 desde la rama `educacion-integrada`. Si las migraciones
-- cambian, este archivo se regenera — no se edita a mano.
-- ============================================================================


-- ── Preámbulo: que pegarlo dos veces no falle ───────────────────────────────
-- La 0136 crea `fn_educacion_listar` con un juego de columnas y la 0149 lo
-- amplía (semáforo, días para vencer, nombre del beneficiario). `create or
-- replace` NO puede cambiar el tipo de retorno de una función que ya existe, así
-- que en una base donde esto ya se aplicó, la 0136 aborta con
-- «cannot change return type of existing function».
--
-- Comprobado pegándolo dos veces sobre la misma base. Se borran antes las dos
-- firmas que cambian; las migraciones las vuelven a crear en orden. Nada de esto
-- toca datos: son sólo definiciones de función.
drop function if exists fn_educacion_listar();
drop function if exists fn_educacion_registrar(uuid,numeric,text,numeric,numeric,text,date,text,text,uuid);
drop function if exists fn_educacion_cerrar(uuid,date);

-- ══════════════════════════════════════════════════════════════════════════
-- 0136 ─ la_pantalla_de_educacion_con_su_comprobante
-- ══════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0136 — La asignación por educación se carga desde una pantalla, con su papel
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE. Que Desarrollo Organizacional pueda registrar, corregir y cerrar
-- una asignación por educación desde /admin/educacion, y que el comprobante que
-- la sostiene quede guardado DENTRO del sistema — no en una carpeta que alguien
-- puede mover.
--
-- QUÉ ASUME. Que existen `asignaciones_educacion` (0120), su tope por rango
-- (0132), `fn_es_admin_o_lider()` y `fn_persona_actual_id()` (0078).
--
-- POR QUÉ AHORA. La 0120 dejó escrito «PENDIENTE: la pantalla para subir el
-- comprobante; mientras no exista, las filas se insertan por SQL». Nunca se
-- insertó ninguna: la tabla está vacía. Y esa tabla vacía es una de las tres
-- compensaciones que frenan la 0128 (bajar las bases declaradas por rango), así
-- que la pantalla que faltaba está en el camino crítico de lo que cobra la gente.
--
-- POR QUÉ UN BUCKET PROPIO Y NO «expedientes». La 0120 anticipó reusar el bucket
-- de los memos, pero sus políticas preguntan «¿este path es un documento
-- disciplinario ya firmado?» — un comprobante de matrícula jamás lo será. Meterlo
-- ahí obligaría a que esa función tuviera una rama por cada clase de papel. Un
-- bucket por clase de documento, cada uno con su regla legible, es más simple de
-- auditar el día que alguien pregunte quién puede ver qué.
--
-- POR QUÉ LA ESCRITURA VA POR FUNCIÓN Y NO POR POLÍTICA DE INSERT. Igual que el
-- resto del sistema (marcajes, expedientes, salarios): la tabla no acepta
-- escritura directa desde el cliente. Así el tope por rango, el candado del
-- comprobante y el registro de quién lo hizo no dependen de que la pantalla se
-- acuerde de mandarlos.
--
-- LO QUE NO HACE. No cambia el cálculo de la planilla — `fn_planilla_calcular`
-- ya lee esta tabla desde la 0122. Cargar una fila aquí SÍ cambia lo que cobra
-- esa persona en el siguiente periodo abierto; cargar cero filas no cambia nada.
--
-- CÓMO SE REVIERTE:
--   drop policy comprobantes_insert on storage.objects;
--   drop policy comprobantes_select on storage.objects;
--   drop policy comprobantes_delete on storage.objects;
--   drop function fn_educacion_registrar(uuid,numeric,text,numeric,numeric,text,date,text,text);
--   drop function fn_educacion_cerrar(uuid,date);
--   drop function fn_educacion_listar();
--   drop function fn_educacion_candidatos();
--   drop function fn_educacion_puede_ver(text);
--   delete from storage.buckets where id = 'comprobantes';  -- vacíalo antes
-- La tabla `asignaciones_educacion` y sus datos NO se tocan al revertir.
-- ============================================================================

-- ── A · El bucket ───────────────────────────────────────────────────────────
-- Privado. Un comprobante de matrícula lleva el nombre de la persona y, cuando
-- el beneficiario es un hijo, el de un menor. Se lee con URL firmada de vida
-- corta, nunca por enlace público.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'comprobantes', 'comprobantes', false,
  10485760,  -- 10 MB: una foto de un recibo o un PDF de matrícula entran de sobra
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp', 'application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── B · ¿Quién puede tocar este archivo? ─────────────────────────────────────
-- El path es "educacion/<persona_id>/<archivo>": la carpeta identifica de quién
-- es el comprobante. Se valida que sea un uuid ANTES de castear — un path con
-- basura debe negarse limpio, no reventar con un error de casteo (misma forma
-- que fn_expediente_puede_adjuntar en la 0074).
create or replace function fn_educacion_puede_ver(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_persona text;
begin
  if split_part(p_path, '/', 1) <> 'educacion' then return false; end if;
  v_persona := split_part(p_path, '/', 2);
  if v_persona !~ '^[0-9a-fA-F-]{36}$' then return false; end if;

  -- DO ve todos los comprobantes; cada quien ve el suyo. `is not true` y no
  -- `not (...)`: un null no debe pasar como autorizado.
  if fn_es_admin_o_lider() is true then return true; end if;
  return v_persona::uuid = fn_persona_actual_id();
end;
$$;

grant execute on function fn_educacion_puede_ver(text) to authenticated;

-- ── C · Permisos sobre los archivos ─────────────────────────────────────────
-- Subir y borrar es de DO: el comprobante sostiene un monto que se paga, así que
-- no lo cambia la propia interesada. Leer sí lo puede hacer cada quien sobre el
-- suyo, para que pueda comprobar qué papel quedó archivado a su nombre.
drop policy if exists comprobantes_insert on storage.objects;
create policy comprobantes_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
  );

drop policy if exists comprobantes_select on storage.objects;
create policy comprobantes_select on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes' and fn_educacion_puede_ver(name));

drop policy if exists comprobantes_delete on storage.objects;
create policy comprobantes_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'comprobantes'
    and split_part(name, '/', 1) = 'educacion'
    and fn_es_admin_o_lider() is true
  );

-- ── D · Registrar una asignación ────────────────────────────────────────────
-- Una sola puerta de escritura. Devuelve el id de la fila para que la pantalla
-- pueda subir el comprobante a "educacion/<persona>/<id>.<ext>" y luego
-- enlazarlo con la misma función (pasando p_id).
create or replace function fn_educacion_registrar(
  p_persona_id      uuid,
  p_monto           numeric,
  p_institucion     text,
  p_costo_declarado numeric,
  p_cobertura_pct   numeric,
  p_beneficiario    text,
  p_vigente_desde   date,
  p_comprobante_url text default null,
  p_nota            text default null,
  p_id              uuid default null   -- no nulo = corregir una fila existente
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_yo  uuid := fn_persona_actual_id();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra asignaciones por educación.';
  end if;

  if p_institucion is null or length(trim(p_institucion)) < 3 then
    raise exception 'Falta la institución que emite el comprobante.';
  end if;
  if p_beneficiario not in ('trabajador', 'hijo') then
    raise exception 'El beneficiario es «trabajador» o «hijo» (llegó «%»).', p_beneficiario;
  end if;

  -- Que la persona exista y esté activa. Cargarle una asignación a alguien que
  -- ya no está sería pagar por un estudio que la empresa dejó de sostener.
  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no existe o no está activa.';
  end if;

  if p_id is null then
    insert into asignaciones_educacion (
      persona_id, monto, institucion, costo_declarado, cobertura_pct,
      beneficiario, vigente_desde, comprobante_url, nota, registrado_por
    ) values (
      p_persona_id, p_monto, trim(p_institucion), p_costo_declarado, p_cobertura_pct,
      p_beneficiario, p_vigente_desde, p_comprobante_url, nullif(trim(coalesce(p_nota, '')), ''), v_yo
    )
    returning id into v_id;
  else
    update asignaciones_educacion set
      persona_id      = p_persona_id,
      monto           = p_monto,
      institucion     = trim(p_institucion),
      costo_declarado = p_costo_declarado,
      cobertura_pct   = p_cobertura_pct,
      beneficiario    = p_beneficiario,
      vigente_desde   = p_vigente_desde,
      -- null no borra el comprobante ya cargado: se enlaza en un segundo paso,
      -- después de que el archivo terminó de subir.
      comprobante_url = coalesce(p_comprobante_url, comprobante_url),
      nota            = nullif(trim(coalesce(p_nota, '')), '')
    where id = p_id
    returning id into v_id;

    if v_id is null then raise exception 'Esa asignación no existe.'; end if;
  end if;

  return v_id;
end;
$$;

grant execute on function fn_educacion_registrar(uuid,numeric,text,numeric,numeric,text,date,text,text,uuid) to authenticated;

-- ── E · Cerrar una asignación ───────────────────────────────────────────────
-- Terminó el ciclo, o la persona dejó de estudiar. No se borra: la fila sostiene
-- lo que ya se pagó en periodos cerrados, y borrarla dejaría esos pagos sin
-- sustento el día de una fiscalización.
create or replace function fn_educacion_cerrar(p_id uuid, p_hasta date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r asignaciones_educacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional cierra asignaciones por educación.';
  end if;

  select * into r from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_hasta < r.vigente_desde then
    raise exception 'La fecha de cierre (%) es anterior al inicio (%).', p_hasta, r.vigente_desde;
  end if;

  update asignaciones_educacion set vigente_hasta = p_hasta where id = p_id;
end;
$$;

grant execute on function fn_educacion_cerrar(uuid,date) to authenticated;

-- ── F · Leer la lista con los nombres ya puestos ────────────────────────────
-- La pantalla necesita el nombre y la sede junto a cada fila. Va por función y
-- no por vista para que el filtro de permiso viva en un solo sitio: quien no es
-- DO recibe únicamente lo suyo, sin depender de que la pantalla filtre bien.
create or replace function fn_educacion_listar()
returns table (
  id               uuid,
  persona_id       uuid,
  persona          text,
  sede             text,
  rango            text,
  monto            numeric,
  institucion      text,
  costo_declarado  numeric,
  cobertura_pct    numeric,
  beneficiario     text,
  comprobante_url  text,
  vigente_desde    date,
  vigente_hasta    date,
  nota             text,
  registrada_por   text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id, a.persona_id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    a.monto, a.institucion, a.costo_declarado, a.cobertura_pct,
    a.beneficiario, a.comprobante_url, a.vigente_desde, a.vigente_hasta, a.nota,
    reg.nombres || ' ' || reg.apellidos
  from asignaciones_educacion a
  join personas p on p.id = a.persona_id
  left join sedes s on s.id = p.sede_base_id
  left join personas reg on reg.id = a.registrado_por
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = a.persona_id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  where fn_es_admin_o_lider() is true
     or a.persona_id = fn_persona_actual_id()
  order by (a.vigente_hasta is not null), p.apellidos, a.vigente_desde desc;
$$;

grant execute on function fn_educacion_listar() to authenticated;

-- ── G · A quién se le puede cargar, y hasta cuánto ──────────────────────────
-- La pantalla necesita saber el tope ANTES de guardar, no después. Si el tope
-- solo se conociera al recibir el error, la persona escribiría el monto, subiría
-- el comprobante y recién ahí se enteraría de que no cabía — con el archivo ya
-- subido. Que el formulario pueda avisar mientras se escribe es la diferencia
-- entre un sistema que corrige y uno que regaña.
create or replace function fn_educacion_candidatos()
returns table (
  persona_id uuid,
  persona    text,
  sede       text,
  rango      text,
  tope       numeric,
  ya_tiene   boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    t.tope_mensual,      -- null = rango sin techo cargado; la pantalla lo dice
    exists (
      select 1 from asignaciones_educacion a
      where a.persona_id = p.id and a.vigente_hasta is null
    )
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = p.id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  left join topes_educacion_rango t on t.rango = sal.rango
  where p.estado = 'activo'
    and fn_es_admin_o_lider() is true
  order by p.apellidos, p.nombres;
$$;

grant execute on function fn_educacion_candidatos() to authenticated;

-- El comentario de la 0120 anticipaba el bucket «expedientes»; quedó en
-- «comprobantes» por lo explicado arriba. Se corrige para que la columna no
-- mande a buscar el archivo donde no está.
comment on column asignaciones_educacion.comprobante_url is
  'Ruta en el bucket privado «comprobantes», con la forma educacion/<persona_id>/<archivo>. '
  'Se lee con URL firmada de vida corta. El día del requerimiento tiene que existir: el '
  'art. 148 del Código Tributario no admite en apelación la prueba que no se exhibió en '
  'fiscalización.';

insert into migraciones_aplicadas (numero, nombre)
values (136, 'la_pantalla_de_educacion_con_su_comprobante')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ══════════════════════════════════════════════════════════════════════════
-- 0149 ─ la_educacion_con_todas_sus_reglas
-- ══════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0149 — La asignación por educación, con todas sus reglas
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una asignación por educación no pueda existir en un estado que la
--   empresa no pueda defender ante una fiscalización, ni pagar un céntimo que
--   un comprobante no sostenga. Nueve reglas, decididas por Felipe el
--   2026-08-04, que hasta hoy vivían en su cabeza y no en la base:
--
--     1 · el monto lo calcula el sistema, nadie lo teclea
--     2 · la cobertura es 75 % y no se negocia caso por caso
--     3 · el techo del rango se mide sobre la SUMA de lo que cobra la persona
--     4 · toda asignación dice hasta cuándo vale
--     5 · un comprobante a nombre de un hijo dice de qué hijo
--     6 · no se registra ni se corrige dentro de un periodo ya pagado
--     7 · corregir lo que mueve plata abre una vigencia nueva, no reescribe
--     8 · toda corrección deja motivo y rastro
--     9 · quien cesa deja de devengar el día que cesa
--
-- QUÉ ASUME
--   · `asignaciones_educacion` (0120), su techo por rango (0132) y las funciones
--     de la 0136. La tabla está VACÍA hoy (0 filas, comprobado), que es lo que
--     permite poner `not null` sin migrar nada.
--   · `fn_hoy_lima()` (0091) y `fn_persona_actual_id()` (0078).
--   · Que la planilla suma las filas y exige comprobante — eso lo hace la 0150,
--     que va encima de ésta. Aplicar sólo la 0149 no cambia ningún pago.
--
-- POR QUÉ EL MONTO NO SE TECLEA
--   Es `min(costo del comprobante × 75 %, techo del rango)` y punto. Si sale por
--   debajo del techo es porque el 75 % del curso ya es menor — nunca porque
--   alguien decidió pagar menos. Dejarlo escribible obligaba a DO a hacer esa
--   cuenta 22 veces y a acordarse del techo de cada rango; el primer error de
--   cuenta llegaba el primer mes, y no sería un error de la persona sino del
--   diseño. Con esto el formulario pide lo único que DO puede saber leyendo el
--   papel: cuánto cuesta y hasta cuándo vale.
--
-- POR QUÉ EL TECHO VA SOBRE LA SUMA Y NO SOBRE CADA FILA
--   El diseño acordado dice que la asignación vale para el trabajador **y/o sus
--   hijos**. Con el techo medido fila por fila, dos filas de S/170 pasaban un
--   techo de S/180 y se pagaban S/340: el techo dejaba de ser un techo. Ahora se
--   suman las vigencias que se solapan y el techo se mide sobre ese total.
--
-- POR QUÉ CORREGIR ABRE UNA VIGENCIA NUEVA
--   Mismo criterio que la 0115 usó con la pensión: los periodos pagados quedaron
--   intactos, comprobado. Si corregir reescribiera la fila, un periodo ya pagado
--   cambiaría de monto retroactivamente y la foto del pago (0096) empezaría a
--   discrepar sin que nadie lo hubiera pedido. Sólo lo que mueve plata —el costo
--   declarado y las fechas— abre vigencia nueva; la institución, el nombre del
--   beneficiario, el comprobante y la nota se corrigen en la misma fila, porque
--   no cambian un céntimo.
--
-- LO QUE ESTA MIGRACIÓN NO DECIDE, Y CONVIENE MIRAR
--   La regla de vigencia acordada es «paga el mes completo si estaba vigente al
--   INICIAR el periodo». Eso resuelve el ciclo que termina a mitad de mes, y
--   deja abierto el simétrico: quien se matricula el día 10 no cobra ese mes.
--   Es evitable operativamente —DO pone `vigente_desde` en el primer día del
--   periodo, que es cuando la institución cobró la pensión— y por eso no se
--   fuerza acá. Si mañana se prefiere pagar también el mes que empieza a mitad,
--   es una sola condición en la 0150, no un rediseño.
--
-- CÓMO SE REVIERTE
--   Los `alter table` se deshacen quitando los tres constraints nuevos, la
--   columna `beneficiario_nombre` y el `not null` de `vigente_hasta`. Las
--   funciones vuelven a su cuerpo de la 0136. La 0150 depende de ésta: revertir
--   sólo la 0149 deja a la planilla sumando filas cuyo techo ya no se valida.
-- ============================================================================


-- ── A · El esquema no deja construir un estado indefendible ─────────────────
-- Un constraint vale más que diez validaciones en la pantalla: la pantalla se
-- puede saltar llamando la función, y la función se puede reescribir mal.

alter table asignaciones_educacion
  add column if not exists beneficiario_nombre text;

comment on column asignaciones_educacion.beneficiario_nombre is
  'Nombre de la persona a la que pertenece el comprobante. Obligatorio cuando el '
  'beneficiario es un hijo: sin él, un comprobante a nombre de un tercero no tiene '
  'cómo atarse a quien cobra, que es el hueco por el que estos conceptos se '
  'desconocen en fiscalización. Dato personal: no sale en la boleta.';

-- La tabla está vacía, así que el not null no rompe ninguna fila existente.
alter table asignaciones_educacion alter column vigente_hasta set not null;

alter table asignaciones_educacion alter column cobertura_pct set default 75;

do $mig$
begin
  -- 75 % fijo. Si mañana la política cambia, se cambia acá y queda el rastro de
  -- cuándo cambió — que es exactamente lo que no pasa cuando el número es un
  -- campo que cada quien llena a su criterio.
  if not exists (select 1 from pg_constraint where conname = 'educacion_cobertura_es_75') then
    alter table asignaciones_educacion
      add constraint educacion_cobertura_es_75 check (cobertura_pct = 75);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'educacion_hijo_lleva_nombre') then
    alter table asignaciones_educacion
      add constraint educacion_hijo_lleva_nombre check (
        beneficiario <> 'hijo'
        or (beneficiario_nombre is not null and length(trim(beneficiario_nombre)) >= 3)
      );
  end if;
end $mig$;


-- ── A bis · El índice que impedía el caso que el diseño promete ────────────
-- La 0120 puso `unique (persona_id, vigente_desde)` para que nadie duplicara la
-- misma asignación. Con una sola por persona era correcto; con «vale para el
-- trabajador Y/O sus hijos» dejó de serlo: madre e hija registradas el mismo día
-- —el caso normal, se cargan juntas— chocaban contra ese índice. Encontrado
-- ejecutando la prueba 115, no leyendo: el esquema decía una cosa y el diseño
-- acordado otra.
--
-- Se reemplaza por una unicidad que sigue impidiendo el duplicado literal —la
-- misma persona, el mismo beneficiario, la misma institución, el mismo día— y
-- deja convivir dos beneficiarios distintos. Quien controla que no se pague de
-- más ya no es este índice sino el techo sobre la suma, que es su lugar.
drop index if exists idx_asignaciones_educacion_unica;

create unique index if not exists idx_asignaciones_educacion_unica
  on asignaciones_educacion (
    persona_id, vigente_desde, beneficiario,
    coalesce(beneficiario_nombre, ''), institucion
  );


-- ── B · El techo del rango, medido sobre la suma ────────────────────────────
create or replace function fn_educacion_respeta_el_tope()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_rango text;
  v_tope  numeric;
  v_suma  numeric;
begin
  select a.rango into v_rango
    from asignaciones_salario a
   where a.persona_id = new.persona_id
     and a.vigente_hasta is null
   order by a.vigente_desde desc
   limit 1;

  if v_rango is null then
    return new;  -- sin rango vigente no hay techo que aplicar
  end if;

  select t.tope_mensual into v_tope
    from topes_educacion_rango t
   where t.rango = v_rango;

  if v_tope is null then
    return new;  -- rango sin techo cargado: falla abierto a propósito
  end if;

  -- ⇩ CAMBIO 0149 ⇩ La suma, no la fila. Se cuentan las asignaciones de esa
  -- persona cuya vigencia SE SOLAPA con la de la fila que entra: dos cursos en
  -- meses distintos no compiten por el mismo techo, dos cursos en el mismo mes
  -- sí. Se excluye la propia fila para que corregir no se sume a sí misma.
  select coalesce(sum(a.monto), 0) into v_suma
    from asignaciones_educacion a
   where a.persona_id   = new.persona_id
     and a.id          <> new.id
     and a.vigente_desde <= new.vigente_hasta
     and a.vigente_hasta >= new.vigente_desde;

  if v_suma + new.monto > v_tope then
    raise exception
      'La suma de las asignaciones por educación de esta persona (S/%) supera el tope '
      'del rango % (S/%). Ya tiene S/% vigente en esas fechas. Cierra la otra asignación, '
      'ajusta el monto, o sube el tope en topes_educacion_rango si la política cambió.',
      to_char(v_suma + new.monto, 'FM999999.00'), v_rango,
      to_char(v_tope, 'FM999999.00'), to_char(v_suma, 'FM999999.00');
  end if;

  return new;
end;
$$;


-- ── C · Dos ayudas que se usan en varios sitios ─────────────────────────────

-- ¿Esta fecha cae en un periodo ya pagado? Se pregunta al registrar y al
-- corregir, y la respuesta tiene que ser la misma en los dos. Escrita una vez.
create or replace function fn_educacion_fecha_pagada(p_fecha date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  );
$$;

-- Desde cuándo puede regir un cambio: el primer día que NO cae en un periodo
-- pagado, contando desde hoy. Si hoy está dentro de un periodo abierto, devuelve
-- el inicio de ese periodo — el cambio alcanza al pago que todavía no se hizo.
create or replace function fn_educacion_desde_cuando_puede_regir()
returns date
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select min(pp.fecha_ini)
       from periodos_planilla pp
      where pp.estado <> 'pagado'
        and pp.fecha_fin >= fn_hoy_lima()),
    fn_hoy_lima());
$$;

-- El monto no es un dato de entrada: es una consecuencia del comprobante y del
-- rango. Vive en una función para que la pantalla pueda mostrar la misma cifra
-- que la base va a guardar, sin reimplementar la cuenta en TypeScript — que es
-- cómo se fabrican las dos copias que después discrepan.
create or replace function fn_educacion_monto(p_persona_id uuid, p_costo numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select least(
    round(p_costo * 75 / 100.0, 2),
    coalesce(
      (select t.tope_mensual
         from asignaciones_salario a
         join topes_educacion_rango t on t.rango = a.rango
        where a.persona_id = p_persona_id and a.vigente_hasta is null
        order by a.vigente_desde desc limit 1),
      round(p_costo * 75 / 100.0, 2)));   -- sin rango o sin techo: manda el 75 %
$$;

grant execute on function fn_educacion_fecha_pagada(date)          to authenticated;
grant execute on function fn_educacion_desde_cuando_puede_regir()  to authenticated;
grant execute on function fn_educacion_monto(uuid, numeric)        to authenticated;


-- ── D · Registrar y corregir, por una sola puerta ───────────────────────────
-- La firma cambia respecto de la 0136: ya no entran `p_monto` (se calcula) ni
-- `p_cobertura_pct` (es 75), y entran el nombre del beneficiario, la fecha de
-- fin y el motivo. Se borra la anterior para que no queden dos puertas.
drop function if exists fn_educacion_registrar(uuid,numeric,text,numeric,numeric,text,date,text,text,uuid);

create or replace function fn_educacion_registrar(
  p_persona_id          uuid,
  p_institucion         text,
  p_costo_declarado     numeric,
  p_beneficiario        text,
  p_vigente_desde       date,
  p_vigente_hasta       date,
  p_beneficiario_nombre text default null,
  p_comprobante_url     text default null,
  p_nota                text default null,
  p_id                  uuid default null,   -- no nulo = corregir
  p_motivo              text default null    -- obligatorio al corregir
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id       uuid;
  v_yo       uuid := fn_persona_actual_id();
  v_monto    numeric;
  v_vieja    asignaciones_educacion%rowtype;
  v_mueve    boolean;
  v_desde    date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra asignaciones por educación.';
  end if;

  if p_institucion is null or length(trim(p_institucion)) < 3 then
    raise exception 'Falta la institución que emite el comprobante.';
  end if;
  if p_beneficiario not in ('trabajador', 'hijo') then
    raise exception 'El beneficiario es «trabajador» o «hijo» (llegó «%»).', p_beneficiario;
  end if;
  if p_beneficiario = 'hijo'
     and (p_beneficiario_nombre is null or length(trim(p_beneficiario_nombre)) < 3) then
    raise exception 'Si el comprobante es de un hijo, escribe a nombre de quién está.';
  end if;
  if p_costo_declarado is null or p_costo_declarado <= 0 then
    raise exception 'El costo que dice el comprobante tiene que ser mayor que cero.';
  end if;
  if p_vigente_hasta is null then
    raise exception 'Falta hasta cuándo vale el comprobante. Una matrícula cubre un ciclo, no la eternidad.';
  end if;
  if p_vigente_hasta < p_vigente_desde then
    raise exception 'La fecha de fin (%) es anterior a la de inicio (%).', p_vigente_hasta, p_vigente_desde;
  end if;

  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no existe o no está activa.';
  end if;

  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado);

  -- ── Alta ────────────────────────────────────────────────────────────────
  if p_id is null then
    if fn_educacion_fecha_pagada(p_vigente_desde) is true then
      raise exception
        'Esa fecha de inicio (%) cae en un periodo ya PAGADO: registrarla cambiaría una '
        'planilla cerrada. Registra desde el periodo abierto, o reabre el periodo primero.',
        p_vigente_desde;
    end if;

    insert into asignaciones_educacion (
      persona_id, monto, institucion, costo_declarado, cobertura_pct,
      beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
      comprobante_url, nota, registrado_por
    ) values (
      p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
      p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      p_vigente_desde, p_vigente_hasta,
      p_comprobante_url, nullif(trim(coalesce(p_nota, '')), ''), v_yo
    )
    returning id into v_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (p_persona_id, 'educacion_alta', null,
       trim(p_institucion) || ' · S/' || to_char(v_monto, 'FM999999.00') ||
       ' · ' || p_vigente_desde::text || ' a ' || p_vigente_hasta::text,
       v_yo, coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Alta de asignación por educación'));

    return v_id;
  end if;

  -- ── Corrección ──────────────────────────────────────────────────────────
  select * into v_vieja from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se corrige. Esto mueve lo que cobra una persona.';
  end if;

  -- ¿La corrección mueve plata? Sólo el costo y las fechas lo hacen. Cambiar el
  -- nombre de la institución o subir el comprobante que faltaba no cambia un
  -- céntimo, y obligar a abrir vigencia nueva por eso llenaría la lista de filas
  -- cerradas por erratas.
  v_mueve := (v_vieja.costo_declarado is distinct from p_costo_declarado)
          or (v_vieja.vigente_desde   is distinct from p_vigente_desde)
          or (v_vieja.vigente_hasta   is distinct from p_vigente_hasta)
          or (v_vieja.persona_id      is distinct from p_persona_id);

  if not v_mueve then
    update asignaciones_educacion set
      institucion         = trim(p_institucion),
      beneficiario        = p_beneficiario,
      beneficiario_nombre = nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      -- null no borra el comprobante ya cargado: se enlaza en un segundo paso,
      -- después de que el archivo terminó de subir.
      comprobante_url     = coalesce(p_comprobante_url, comprobante_url),
      nota                = nullif(trim(coalesce(p_nota, '')), '')
    where id = p_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_vieja.persona_id, 'educacion_datos', v_vieja.institucion,
       trim(p_institucion), v_yo, trim(p_motivo));

    return p_id;
  end if;

  -- Mueve plata: la fila vieja se cierra el día anterior al que rige el cambio y
  -- nace una nueva. Lo ya pagado queda escrito tal como se pagó.
  v_desde := greatest(fn_educacion_desde_cuando_puede_regir(), v_vieja.vigente_desde);

  if fn_educacion_fecha_pagada(v_desde) is true then
    raise exception
      'No hay ningún periodo abierto desde el que aplicar esta corrección: todos los que '
      'tocan esta asignación están pagados. Reabre el periodo primero.';
  end if;

  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado);

  if v_desde > v_vieja.vigente_desde then
    update asignaciones_educacion
       set vigente_hasta = v_desde - 1
     where id = p_id;
  else
    -- La fila vieja nunca llegó a devengar en un periodo pagado: se reemplaza
    -- entera en vez de dejar un tramo de un día que no significa nada.
    delete from asignaciones_educacion where id = p_id;
  end if;

  insert into asignaciones_educacion (
    persona_id, monto, institucion, costo_declarado, cobertura_pct,
    beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
    comprobante_url, nota, registrado_por
  ) values (
    p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
    p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
    greatest(v_desde, p_vigente_desde), p_vigente_hasta,
    coalesce(p_comprobante_url, v_vieja.comprobante_url),
    nullif(trim(coalesce(p_nota, '')), ''), v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'educacion_nueva_vigencia',
     'S/' || to_char(v_vieja.monto, 'FM999999.00') || ' desde ' || v_vieja.vigente_desde::text,
     'S/' || to_char(v_monto, 'FM999999.00') || ' desde ' || greatest(v_desde, p_vigente_desde)::text,
     v_yo, trim(p_motivo));

  return v_id;
end;
$$;

grant execute on function fn_educacion_registrar(uuid,text,numeric,text,date,date,text,text,text,uuid,text)
  to authenticated;


-- ── E · Cerrar a mano sigue existiendo, con motivo ──────────────────────────
create or replace function fn_educacion_cerrar(p_id uuid, p_hasta date, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r asignaciones_educacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional cierra asignaciones por educación.';
  end if;

  select * into r from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_hasta < r.vigente_desde then
    raise exception 'La fecha de cierre (%) es anterior al inicio (%).', p_hasta, r.vigente_desde;
  end if;

  if fn_educacion_fecha_pagada(p_hasta) is true then
    raise exception
      'Esa fecha de cierre (%) cae en un periodo ya PAGADO: acortar la vigencia ahí '
      'cambiaría una planilla cerrada.', p_hasta;
  end if;

  update asignaciones_educacion set vigente_hasta = p_hasta where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id, 'educacion_cierre', r.vigente_hasta::text, p_hasta::text,
     fn_persona_actual_id(),
     coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Cierre de asignación por educación'));
end;
$$;

grant execute on function fn_educacion_cerrar(uuid,date,text) to authenticated;


-- ── F · Quien cesa deja de devengar el día que cesa ─────────────────────────
-- No se borra la fila: sostiene lo que ya se pagó, y borrarla dejaría esos pagos
-- sin sustento el día de una fiscalización. Sólo se le pone fin.
--
-- Va en un trigger y no en la pantalla de cese porque el cese se registra desde
-- tres sitios distintos, y una regla escrita en la pantalla es una regla que las
-- otras dos no cumplen — el patrón que este repositorio ya pagó tres veces.
create or replace function fn_educacion_cerrar_al_cesar()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_n int;
begin
  if new.estado = 'inactivo' and new.fecha_cese is not null
     and (old.estado is distinct from new.estado or old.fecha_cese is distinct from new.fecha_cese) then

    update asignaciones_educacion
       set vigente_hasta = new.fecha_cese
     where persona_id = new.id
       and vigente_hasta > new.fecha_cese;

    get diagnostics v_n = row_count;

    if v_n > 0 then
      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (new.id, 'educacion_cierre_por_cese', v_n::text || ' asignación(es) abierta(s)',
         'cerradas al ' || new.fecha_cese::text,
         coalesce(fn_persona_actual_id(), new.id),
         'Cierre automático: la persona cesó el ' || new.fecha_cese::text);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_educacion_cerrar_al_cesar on personas;
create trigger trg_educacion_cerrar_al_cesar
  after update on personas
  for each row execute function fn_educacion_cerrar_al_cesar();


-- ── G · La lista, con su semáforo ───────────────────────────────────────────
-- El semáforo se calcula en la base y no en la pantalla: es la misma pregunta
-- que se va a querer hacer desde el contador del menú y desde un reporte, y
-- tres copias de «cuándo vence» es cómo empiezan a discrepar.
drop function if exists fn_educacion_listar();

create or replace function fn_educacion_listar()
returns table (
  id                  uuid,
  persona_id          uuid,
  persona             text,
  sede                text,
  rango               text,
  monto               numeric,
  institucion         text,
  costo_declarado     numeric,
  cobertura_pct       numeric,
  beneficiario        text,
  beneficiario_nombre text,
  comprobante_url     text,
  vigente_desde       date,
  vigente_hasta       date,
  nota                text,
  registrada_por      text,
  dias_para_vencer    int,
  semaforo            text,
  paga                boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id, a.persona_id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    a.monto, a.institucion, a.costo_declarado, a.cobertura_pct,
    a.beneficiario, a.beneficiario_nombre, a.comprobante_url,
    a.vigente_desde, a.vigente_hasta, a.nota,
    reg.nombres || ' ' || reg.apellidos,
    (a.vigente_hasta - fn_hoy_lima())::int,
    case
      when a.comprobante_url is null              then 'sin_comprobante'
      when a.vigente_hasta <  fn_hoy_lima()       then 'vencida'
      when a.vigente_hasta <= fn_hoy_lima() + 30  then 'por_vencer'
      else 'vigente'
    end,
    -- Lo que de verdad decide si esta fila entra en la planilla. La pantalla lo
    -- muestra tal cual para que nadie tenga que deducirlo.
    (a.comprobante_url is not null and a.vigente_hasta >= fn_hoy_lima())
  from asignaciones_educacion a
  join personas p on p.id = a.persona_id
  left join sedes s on s.id = p.sede_base_id
  left join personas reg on reg.id = a.registrado_por
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = a.persona_id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  where fn_es_admin_o_lider() is true
     or a.persona_id = fn_persona_actual_id()
  order by (a.vigente_hasta < fn_hoy_lima()), p.apellidos, a.vigente_desde desc;
$$;

grant execute on function fn_educacion_listar() to authenticated;

-- Cuántas necesitan atención: alimenta el contador del menú de una sola consulta
-- en vez de traer la lista entera para contarla en el navegador.
create or replace function fn_educacion_por_atender()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from asignaciones_educacion a
  where fn_es_admin_o_lider() is true
    and (a.comprobante_url is null or a.vigente_hasta <= fn_hoy_lima() + 30);
$$;

grant execute on function fn_educacion_por_atender() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (149, 'la_educacion_con_todas_sus_reglas')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_filas int;
begin
  select count(*) into v_filas from asignaciones_educacion;
  raise notice '0149 · reglas activas. Filas de educacion en esta base: %', v_filas;
  raise notice '0149 · el monto ya no se teclea: es min(costo x 75%%, tope del rango).';
  raise notice '0149 · esta migracion NO cambia ningun pago. Eso lo hace la 0150.';
end $mig$;

-- ══════════════════════════════════════════════════════════════════════════
-- 0150 ─ la_planilla_suma_la_educacion_y_exige_el_papel
-- ══════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0150 — La planilla suma la educación, y no paga sin el comprobante
-- ============================================================================
--
-- QUÉ PROMETE
--   Que lo que se paga por educación sea la SUMA de las asignaciones vigentes de
--   esa persona, que ninguna pague sin su comprobante cargado, y que la boleta
--   pueda decir de qué institución sale ese dinero.
--
-- QUÉ ASUME
--   La 0149: el techo del rango ya se valida sobre la suma. Sin ella, sumar acá
--   permitiría pasarse del techo — dos filas de S/170 bajo un techo de S/180.
--   Aplicar la 0150 sin la 0149 es el único orden que rompe algo.
--
-- QUÉ CAMBIA, MEDIDO
--   Tres agujeros, los tres comprobados contra el Postgres local en
--   BEGIN … ROLLBACK el 2026-08-04. La prueba 114 los fija:
--
--   1 · SUM en vez de LIMIT 1. Quien tenía dos asignaciones vigentes cobraba
--       UNA y la otra se descartaba sin avisar. Medido: dos filas de S/150 y
--       S/120 pagaban S/150; ahora pagan S/270.
--
--   2 · Exige `comprobante_url is not null`. Una fila sin papel devengaba igual.
--       Ahora se puede guardar mientras el comprobante llega —queda en amarillo
--       en la pantalla— pero no paga hasta tenerlo. Es lo que sostiene que el
--       concepto no sea remuneración: la RTF 05449-4-2007 desconoció la
--       movilidad de 14 de 21 trabajadores por exactamente esto.
--
--   3 · Vigente al INICIAR el periodo (`p_ini`) y no al terminarlo (`p_fin`).
--       Un ciclo que acababa el 15 de agosto hacía que agosto pagara CERO,
--       habiendo estudiado y pagado la pensión del mes. Ahora paga el mes
--       completo, que es como factura la institución.
--
-- EL BORDE QUE ESTO DEJA ABIERTO, A PROPÓSITO
--   Con la regla «vigente al iniciar», quien se matricula el día 10 no cobra ese
--   mes. Es evitable: DO pone `vigente_desde` en el primer día del periodo, que
--   es cuando la institución cobró. Se prefirió la regla simple y una nota, a
--   una condición de solape que nadie pidió. Si mañana se quiere pagar también
--   el mes que empieza a mitad, es cambiar `ae.vigente_desde <= p_ini` por
--   `ae.vigente_desde <= p_fin` — una línea, y la prueba 114 lo cubre.
--
-- DE QUÉ VERSIÓN PARTE
--   Del cuerpo vigente en la base (`pg_get_functiondef`), que es el que dejó la
--   0142 (tarifa de movilidad por sede). Se extrajo y se parcheó con un script,
--   no se retipeó a mano: los dos bloques cambiados llevan el marcador
--   «CAMBIO 0150» y el resto es byte por byte lo que ya estaba.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar `fn_planilla_calcular` tal como la dejó la 0142. No hay
--   cambio de esquema ni de datos: esta migración sólo redefine una función.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dias int; v_base numeric;
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_f_be numeric;   -- CAMBIO 0134: tasa de la bonificacion extraordinaria
  v_asig numeric; v_anio int; v_mes int;
  v_movilidad numeric; v_tasa_afp numeric;   -- CAMBIO 0110
  v_sexto_cts numeric;                       -- CAMBIO 0112
  v_rmv numeric; v_tasa_essalud numeric;     -- CAMBIO 0116
begin
  -- ⚠️ ESTE GUARD ES DE LA 0090 Y NO SE TOCA NUNCA.
  -- La 0076 abrió esta función a cualquier sesión con login —el terminal de
  -- tienda incluido— al conceder permisos en masa, y la 0090 lo cerró poniendo
  -- la comprobación DENTRO de la función, porque un `revoke` se deshace solo la
  -- próxima vez que alguien conceda en masa y un guard no.
  -- Quien copie este cuerpo para otra migración tiene que copiar esto también:
  -- al escribir la 0100 se copió el texto de la 0069, que es anterior, y el
  -- guard desapareció sin que nada fallara salvo la prueba 91.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular la planilla.';
  end if;

  v_dias := (p_fin - p_ini) + 1;
  v_base := 6.5 * v_dias;
  v_anio := extract(year from p_fin)::int;
  v_mes := extract(month from p_fin)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion": 0.08333, "cts": 0.04167, "vacaciones": 0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vacas := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0134 ⇩⇩⇩ LA BONIFICACION EXTRAORDINARIA DE LA LEY 30334.
  -- Versionada en parametros_laborales y no clavada en el codigo, por el mismo
  -- motivo que la movilidad (0118) y la asignacion familiar (0122): es una tasa
  -- legal, y el dia que cambie los periodos ya pagados no pueden moverse.
  -- Es 6.75 % para quien esta afiliado a una EPS. Hoy nadie lo esta y el sistema
  -- no tiene ese campo; cuando lo tenga, esta lectura pasa a ser por persona.
  select pl.valor into v_f_be
  from parametros_laborales pl
  where pl.clave = 'bonificacion_extraordinaria'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_f_be is null then v_f_be := 0.09; end if;
  -- CAMBIO 0112 — el sexto de la gratificación en la base de la CTS (Art. 16
  -- D.S. 001-97-TR). Arranca en 0: sin la clave, la CTS sale como hoy.
  v_sexto_cts := coalesce((v_prov->>'sexto_cts')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0122 ⇩⇩⇩ LA ASIGNACIÓN FAMILIAR, CON VIGENCIA.
  --
  -- Es el 10% de la RMV (Ley 25129), así que SUBE CUANDO SUBE LA RMV. El 28 de
  -- julio de 2026 se anunció el alza a S/1,300, que la llevaría de S/113 a S/130.
  --
  -- Hasta esta migración el monto vivía en 'configuracion' como un escalar SIN
  -- FECHA. El día que alguien lo actualizara a 130, TODOS los periodos ya pagados
  -- se recalcularían con el valor nuevo y las boletas viejas dejarían de
  -- reproducirse. Es el mismo defecto que ya nos mordió con tasa_afp y que la 0116
  -- y la 0118 resolvieron para la RMV, el EsSalud y la movilidad. A esta se le
  -- pasó, y se arregla ANTES de que salga la norma y no después.
  --
  -- Acá la lectura es exacta: un periodo de planilla tiene una sola asignación
  -- vigente, la del cierre, y los 15 usos de v_asig pertenecen al mismo periodo.
  select pl.valor into v_asig
  from parametros_laborales pl
  where pl.clave = 'asignacion_familiar'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;

  -- Respaldo, para que una base sin la fila se comporte igual que antes.
  if v_asig is null then
    select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
    from configuracion where clave = 'asignacion_familiar';
  end if;
  if v_asig is null then v_asig := 113.00; end if;

  -- ⇩⇩⇩ CAMBIO 0110 ⇩⇩⇩ Las dos viven en configuracion, no en el código.
  --
  -- AMBAS ARRANCAN EN CERO A PROPÓSITO. Si las claves no existen, la movilidad
  -- y el descuento de AFP salen 0 y NINGÚN pago se mueve: esta migración se puede
  -- pegar en producción sin que nadie cobre un sol distinto. Se activan con dos
  -- UPDATE cuando Felipe decida, no al aplicar la migración.
  --
  --   update configuracion set valor = '{"monto": 12.50}'::jsonb
  --    where clave = 'movilidad_diaria';
  --   update configuracion set valor = '{"tasa": 0.13}'::jsonb
  --    where clave = 'tasa_afp';
  --
  -- La tarifa vive en configuracion porque los pasajes cambian (Trujillo pasó de
  -- S/2.50 a S/2.00 en junio de 2026) y la tasa de AFP porque varía por AFP:
  -- entre 12.84% (Habitat) y 13.06% (Profuturo). El 13% es el techo práctico.
  -- ⇩⇩⇩ CAMBIO 0118 ⇩⇩⇩ LA TARIFA DE MOVILIDAD, CON VIGENCIA Y CON SUSTENTO.
  --
  -- Antes salía de 'configuracion', que guarda valores globales SIN fecha. El día
  -- que la tarifa cambie —y va a cambiar, porque sigue al pasaje— ese valor único
  -- recalcularía TODOS los periodos ya pagados. Es el mismo defecto que ya nos
  -- mordió con tasa_afp y que la 0116 evitó para la RMV.
  --
  -- Ahora sale de parametros_laborales, eligiendo la fila vigente al FIN del
  -- periodo. Cuando el pasaje suba se cierra la fila con vigente_hasta y se abre
  -- otra: el pasado queda intacto y el porqué de cada tarifa queda archivado en
  -- la columna 'sustento' de su propia fila.
  --
  -- Se conserva la lectura de 'configuracion' como respaldo, para que una base
  -- que aún no tenga la fila siga comportándose igual que antes.
  select pl.valor into v_movilidad
  from parametros_laborales pl
  where pl.clave = 'movilidad_diaria'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;

  if v_movilidad is null then
    select coalesce((valor->>'monto')::numeric, 0) into v_movilidad
    from configuracion where clave = 'movilidad_diaria';
  end if;
  if v_movilidad is null then v_movilidad := 0; end if;

  select coalesce((valor->>'tasa')::numeric, 0) into v_tasa_afp
  from configuracion where clave = 'tasa_afp';
  if v_tasa_afp is null then v_tasa_afp := 0; end if;

  -- ⇩⇩⇩ CAMBIO 0116 ⇩⇩⇩ EL ESSALUD, DESDE UNA TABLA VERSIONADA.
  --
  -- La RMV y la tasa NO van en 'configuracion' a propósito. Esa tabla guarda
  -- valores globales SIN fecha, así que el día que la RMV suba de 1,130 a 1,200
  -- todos los periodos ya pagados se recalcularían con el valor nuevo — el mismo
  -- defecto que tenían movilidad_diaria y tasa_afp. Aquí se elige la fila vigente
  -- al FIN del periodo, que además es lo que manda la norma: el piso se congela
  -- con la RMV vigente al último día calendario del período declarado.
  select pl.valor into v_rmv
  from parametros_laborales pl
  where pl.clave = 'rmv'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_rmv is null then v_rmv := 0; end if;

  select pl.valor into v_tasa_essalud
  from parametros_laborales pl
  where pl.clave = 'tasa_essalud'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_tasa_essalud is null then v_tasa_essalud := 0; end if;

  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_feriados
  from feriados f
  where f.fecha between p_ini and p_fin;

  with pers as (
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, p.fecha_ingreso, p.sueldo_fijo,
           p.sueldo_base_legal,   -- CAMBIO 0105
           p.regimen_pension,     -- CAMBIO 0114
           p.tipo_vinculo, p.en_planilla,   -- CAMBIO 0117
           s.codigo as sede
    from personas p
    join sedes s on s.id = p.sede_base_id
    where p.estado = 'activo'
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between p_ini and p_fin)
       or (p_periodo_id is not null and exists (
             select 1 from movimientos_planilla m
             where m.persona_id = p.id and m.periodo_id = p_periodo_id))
  ),
  horas as (
    select j.persona_id, j.fecha,
           coalesce(j.horas_trabajadas, 0) as h,
           (j.estado = 'auto_cerrada_pendiente') as pendiente
    from jornadas j
    where j.fecha between p_ini and p_fin
  ),
  tramos as (
    select a.persona_id, a.rango, a.salario_mensual_soles as salario,
           a.base_provision,                                   -- CAMBIO 0111
           greatest(a.vigente_desde, p_ini) as t_ini,
           least(coalesce(a.vigente_hasta, p_fin), p_fin) as t_fin
    from asignaciones_salario a
    where a.vigente_desde <= p_fin
      and (a.vigente_hasta is null or a.vigente_hasta >= p_ini)
  )
  select jsonb_build_object(
    'fecha_ini', p_ini,
    'fecha_fin', p_fin,
    'anio_etiqueta', v_anio,
    'mes_etiqueta', v_mes,
    'dias', v_dias,
    'base_horas', v_base,
    'feriados', v_feriados,
    'factores_provision', v_prov,
    'asignacion_monto', v_asig,
    'filas', coalesce(jsonb_agg(sub.fila order by sub.orden_nombre), '[]'::jsonb)
  )
  into v_out
  from (
    select (pe.nombres || ' ' || pe.apellidos) as orden_nombre,
      jsonb_build_object(
        'persona_id', pe.id,
        'nombre', pe.nombres || ' ' || pe.apellidos,
        'sede', pe.sede,
        'estado', pe.estado,
        'fecha_ingreso', pe.fecha_ingreso,
        'rango', ref.rango,
        'salario_ref', ref.salario,
        'horas_mes', round(h.horas_mes, 2),
        'dias_trabajados', h.dias,
        -- ⇩ CAMBIO 0110 ⇩ MOVILIDAD SUPEDITADA A LA ASISTENCIA.
        -- Se devenga por DÍA EFECTIVAMENTE ASISTIDO, que es el requisito del
        -- Art. 19 inciso e) del D.S. 001-97-TR: «el valor del transporte, siempre
        -- que esté supeditado a la asistencia al centro de trabajo». h.dias cuenta
        -- los días con horas > 0, así que si no vino, no la cobra, sin que nadie
        -- tenga que acordarse. La Res. 239-2020-SUNAFIL declaró remunerativa una
        -- movilidad de monto razonable justamente por pagarse 30 días cuando se
        -- laboraban 6.
        'monto_movilidad', round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla then 1 else 0 end), 2),   -- CAMBIO 0142
        'movilidad_diaria', tar.tarifa,
        -- ⇩ CAMBIO 0110 ⇩ DESCUENTO DE AFP/ONP, visible en la boleta.
        -- Se calcula sobre la REMUNERACIÓN ASEGURABLE: la básica legal proporcional
        -- más la asignación familiar, que también es remuneración (Ley 25129). No
        -- entran la movilidad ni los bonos no remunerativos.
        -- Sale 0 para quien no tenga básica legal fijada (sueldo fijo: socios,
        -- dirección), porque para ellos pb.basica es 0.
        'descuento_afp',
          round((pb.basica + (case when pe.con_hijos then v_asig else 0 end))
                * coalesce(tpen.tasa, v_tasa_afp), 2),
        'tasa_afp', coalesce(tpen.tasa, v_tasa_afp),
        'regimen_pension', pe.regimen_pension,          -- CAMBIO 0114
        'tasa_es_del_regimen', (tpen.tasa is not null),  -- CAMBIO 0114
        'dias_pendientes', h.pendientes,
        -- ⇩ CAMBIO 0100 ⇩ por qué esta persona está en cero. Sin esto, «de
        -- vacaciones», «no marcó» y «sin salario» se ven exactamente igual: 0.
        'dias_vacaciones', vac.dias,
        'dias_laborables', lab.dias,
        'horas_sin_salario', round(pb.horas_sin_salario, 2),
        'pago_base', round(pb.pago_base, 2),
        -- CAMBIO 0105 — Desglose legal. Sale en cuanto la persona tiene básica
        -- legal fijada: ya NO hace falta puntuación, porque sin fila el defecto es
        -- 100 y el pago es el mismo de siempre. Sin básica legal sigue saliendo
        -- NULL y la boleta muestra el pago sin partir, antes que inventar una
        -- separación. Los de sueldo fijo (socios, dirección) quedan fuera.
        -- La básica tal cual, sin prorratear: la pantalla de Planilla la necesita
        -- para poder editarla en su celda.
        'sueldo_base_legal', pe.sueldo_base_legal,
        'basica_legal_prop',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else round(pb.basica, 2) end,
        'complemento_variable',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else round(pb.pago_base, 2) - round(pb.basica, 2) end,
        'rendimiento_pct',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else coalesce(rmp.porcentaje, 100) end,
        -- true cuando el 100 es el defecto y no una decisión escrita. Sirve para
        -- que la pantalla distinga «nadie lo ha puntuado» de «lo puntuaron 100».
        'rendimiento_por_defecto', (rmp.porcentaje is null),
        -- El coalesce va AQUÍ y no dentro del lateral: sin fila el lateral no
        -- devuelve nada, así que rmp.etiqueta sería NULL y la boleta se quedaría
        -- sin nombre en la fila del complemento.
        'complemento_etiqueta',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else coalesce(rmp.etiqueta, 'Rendimiento Extraordinario') end,
        'feriados_detalle', fer.detalle,
        'monto_feriados', round(fer.monto, 2),
        'feriados_no_corresponde', fer.no_corresponde,
        'feriados_compensados', fer.compensados,
        'objetivos_cumplidos', obj.cumplidos,
        'objetivos_total', obj.total,
        'monto_plus', round(obj.monto, 2),
        'bajo_desempeno', (obj.cumplidos is not null and obj.total > 0
                           and obj.cumplidos::numeric / obj.total < 0.3),
        'feriados_sin_salario', fer.sin_tramo,
        'con_hijos', pe.con_hijos,
        'asignacion_familiar', case when pe.con_hijos then round(v_asig, 2) else 0 end,
        'bonos', round(mov.bonos, 2),
        'descuentos', round(mov.descuentos, 2),
        'movimientos', mov.detalle,
        -- ⇩ CAMBIO 0113 ⇩ La base de provisión incluye la ASIGNACIÓN FAMILIAR.
        -- Los S/113 de la Ley 25129 son remuneración, así que integran la
        -- remuneración computable de gratificación, CTS y vacaciones. Antes se
        -- pagaban como línea aparte y quedaban fuera de la base.
        --
        -- ⇩⇩⇩ CAMBIO 0111 ⇩⇩⇩ Las cuatro provisiones llevan un FACTOR.
        --
        -- POR QUÉ EXISTE. La 0110 permite bajar el rango a la básica legal para que
        -- el Rendimiento Extraordinario desaparezca (la fórmula lo anula sola cuando
        -- rango = básica). Pero las provisiones se calculan sobre pago_base, así que
        -- bajar el rango de 1,320 a 1,130 les recortaría la gratificación, la CTS y
        -- las vacaciones en un 14.4% — unos S/422 al año por persona. Eso es plata
        -- del equipo, no del empleador, y Felipe decidió no tocarla.
        --
        -- CÓMO FUNCIONA. factor = base_provision / salario. Si base_provision está
        -- en NULL el factor sale 1 y NADA cambia: la migración se puede pegar sin
        -- que ninguna provisión se mueva. Si se pone en 1,320 mientras el salario es
        -- 1,130, el factor es 1.1681 y las provisiones quedan idénticas a las de
        -- antes de bajar el rango.
        --
        -- POR QUÉ UN FACTOR Y NO OTRA BASE. pago_base y feriados escalan LINEALMENTE
        -- con el salario del tramo (los dos usan tt.salario), así que multiplicar el
        -- resultado por el factor da exactamente lo mismo que haber calculado todo
        -- con el salario viejo. Verificado: (1,090.74 + 165.43) × 1.1681 = 1,467.33
        -- contra (1,274.14 + 193.25) = 1,467.39 con el rango en 1,320.
        --
        -- LO QUE NO CAMBIA: la movilidad sigue FUERA de esta base. El factor
        -- multiplica (pago_base + feriados), no la movilidad ni el AFP.
        'provision_gratificacion',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * v_f_grati, 2),
        -- CAMBIO 0134 — se calcula del MISMO numero que la gratificacion, nunca
        -- de una base propia: si manana cambia la formula de la grati, esta la
        -- sigue sola. Es la linea 0312 del PLAME.
        'provision_bonif_extraordinaria',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * v_f_grati * v_f_be, 2),
        'provision_cts',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * v_f_cts * (1 + v_sexto_cts), 2),
        'provision_vacaciones',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * v_f_vacas, 2),
        'provision_total',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * (v_f_grati * (1 + v_f_be) + v_f_cts * (1 + v_sexto_cts) + v_f_vacas), 2),   -- CAMBIO 0134
        -- Para que la pantalla pueda mostrar sobre qué base se provisionó.
        'base_provision', ref.base_provision,
        'factor_provision', coalesce(ref.base_provision / nullif(ref.salario, 0), 1),
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
                 + (case when pe.con_hijos then round(v_asig, 2) else 0 end)
                 + round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla then 1 else 0 end), 2)              -- CAMBIO 0142
                 + round(coalesce(edu.monto, 0) * (case when pe.en_planilla then 1 else 0 end), 2)   -- CAMBIO 0120
                 - round((pb.basica + (case when pe.con_hijos then v_asig else 0 end))
                         * coalesce(tpen.tasa, v_tasa_afp), 2)                                    -- CAMBIO 0110
                 + round(mov.bonos, 2) - round(mov.descuentos, 2)
      )
      || jsonb_build_object(
        -- ⇩⇩⇩ CAMBIO 0116 ⇩⇩⇩ EL APORTE DE ESSALUD QUE PAGA CAYLA.
        --
        -- NO entra en el 'total' y no debe entrar nunca: el 9% es íntegramente de
        -- cargo del empleador (Ley 26790 art. 6). Descontárselo al trabajador
        -- sería una retención ilegal. Va como dato, para que cada integrante vea
        -- lo que la empresa paga por él — que es lo que Felipe pidió el 2026-07-31.
        --
        -- LA BASE LLEVA PISO, y es lo que más se equivoca. La base imponible
        -- mínima mensual no puede ser inferior a la RMV, y ese piso se aplica
        -- «independientemente de las horas y días laborados» (reglamento de la
        -- Ley 26790, D.S. 009-97-SA modificado por el D.S. 020-2006-TR; criterio
        -- confirmado en el Informe 003-2007-SUNAT/2B0000).
        --
        -- O sea: por alguien que trabajó 6 h 35 min y devengó S/36.96, la empresa
        -- NO aporta 9% × 36.96 = S/3.33. Aporta 9% × 1,130 = S/101.70 — el mismo
        -- monto que por alguien de mes completo. Prorratear RMV/30 × días está
        -- expresamente prohibido, salvo el caso de subsidios (descanso médico,
        -- maternidad), que esta función todavía NO modela.
        --
        -- Consecuencia de gestión: el costo de EsSalud lo manda el número de
        -- personas, no el monto de la planilla. Calcularlo como «9% del total de
        -- la planilla» subestima el aporte real cuando hay gente de pocas horas.
        'base_essalud',
          round(greatest(coalesce(pb.basica, 0)
                         + (case when pe.con_hijos then v_asig else 0 end),
                         v_rmv), 2),
        'aporte_essalud',
          round(greatest(coalesce(pb.basica, 0)
                         + (case when pe.con_hijos then v_asig else 0 end),
                         v_rmv) * v_tasa_essalud
                * (case when pe.en_planilla then 1 else 0 end), 2),
        'essalud_tasa', v_tasa_essalud,
        -- ⇩⇩⇩ CAMBIO 0117 ⇩⇩⇩ Qué es esta persona para el sistema. Sin este dato
        -- la boleta no puede explicar por qué a alguien no le aparece movilidad ni
        -- EsSalud, y la pantalla de Planilla no puede advertir que un locador con
        -- conceptos laborales encima es un problema.
        -- ⇩ CAMBIO 0120 ⇩ Condicionada a en_planilla igual que la movilidad: un
        -- locador no recibe asignaciones laborales. Y el monto NO se prorratea por
        -- asistencia — es el costo de un estudio, no una compensación por venir.
        'monto_educacion',
          round(coalesce(edu.monto, 0) * (case when pe.en_planilla then 1 else 0 end), 2),
        -- ⇩ CAMBIO 0150 ⇩ Para que la boleta pueda decir de qué institución sale
        -- ese dinero. Una línea que dice sólo «S/270» no le permite a la persona
        -- cuadrar su propio pago, y un concepto no remunerativo que no se
        -- identifica es el que se reclasifica como sueldo.
        'instituciones_educacion',
          case when pe.en_planilla then edu.instituciones else null end,
        'tipo_vinculo', pe.tipo_vinculo,
        'en_planilla', pe.en_planilla,
        -- true cuando el piso fue lo que decidió la base, o sea cuando la persona
        -- devengó MENOS que la RMV. Sirve para que la boleta pueda explicarlo en
        -- vez de mostrar un número que no cuadra con el sueldo del mes.
        'essalud_es_piso',
          (coalesce(pb.basica, 0) + (case when pe.con_hijos then v_asig else 0 end)) < v_rmv
      ) as fila
    from pers pe
    -- ⇩ CAMBIO 0142 ⇩ La tarifa de movilidad de LA SEDE de esta persona.
    --
    -- Antes era un escalar unico para las tres ciudades. Pero el Art. 19 inciso e)
    -- del D.S. 001-97-TR pide que el monto «razonablemente cubra el respectivo
    -- traslado», y el traslado no cuesta lo mismo en Arequipa que en Lima.
    --
    -- Una tarifa uniforme fijada al caso mas caro deja a las otras ciudades
    -- pagando por encima de su costo real, y ese exceso es lo que se reclasifica.
    -- El Exp. 01038-2019 de Lima Norte tumbo una movilidad ENTERA —no solo el
    -- exceso— porque el monto «depende del mero arbitrio del empleador sin
    -- atender a los lugares de residencia ni a otros criterios objetivos». Una
    -- tarifa que sigue al pasaje de cada ciudad es exactamente ese criterio.
    --
    -- Sin fila para su sede cae al valor general, asi que una base sin las filas
    -- nuevas se comporta exactamente igual que antes.
    cross join lateral (
      select coalesce((
        select pl.valor
        from parametros_laborales pl
        where pl.clave = 'movilidad_diaria'
          and pl.sede_codigo = pe.sede
          and pl.vigente_desde <= p_fin
          and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
        order by pl.vigente_desde desc
        limit 1
      ), v_movilidad) as tarifa
    ) tar
    left join lateral (
      select coalesce(sum(x.h), 0) as horas_mes,
             count(*) filter (where x.h > 0) as dias,
             count(*) filter (where x.pendiente) as pendientes
      from horas x where x.persona_id = pe.id
    ) h on true
    left join lateral (
      -- CAMBIO 0105 — Puntuación de rendimiento del mes.
      --
      -- SIN FILA, EL DEFECTO ES 100 (decidido con Felipe el 2026-07-28). Eso no
      -- le cambia el sueldo a nadie: al 100% la fórmula da
      -- básica + (rango − básica) = el rango exacto, que es lo que ya se pagaba.
      -- Lo que sí gana es que la boleta muestre la estructura legal en TODAS,
      -- desde el primer mes, en vez de solo en las de quien tenga puntuación.
      -- Para bajarle a alguien hay que escribir su fila a mano: el sistema nunca
      -- recorta por omisión.
      select rm.porcentaje,
             coalesce(ec.etiqueta, 'Rendimiento Extraordinario') as etiqueta
      from rendimiento_mensual rm
      left join etiquetas_complemento ec on ec.codigo = rm.etiqueta_codigo
      where rm.persona_id = pe.id and rm.anio = v_anio and rm.mes = v_mes
      limit 1
    ) rmp on true
    left join lateral (
      -- SUELDO FIJO: quien lo tiene cobra su remuneración completa del periodo,
      -- marque o no (socios, dirección). Para el resto la fórmula es EXACTAMENTE
      -- la de siempre — la rama `else` es idéntica a la anterior, así que ningún
      -- pago existente se mueve.
      select case when pe.sueldo_fijo then coalesce(sf.salario, 0)
                  else coalesce(hh.pago, 0) end as pago_base,
             coalesce(hh.basica, 0) as basica,   -- CAMBIO 0105
             coalesce(hh.sin_sal, 0) as horas_sin_salario
      from (select 1) _sf
      left join lateral (
        -- ⇩ CAMBIO 0105 ⇩ El salario del día deja de ser un bloque único: es la
        -- básica legal más la brecha hasta el rango, multiplicada por la
        -- puntuación del mes (100 si no hay fila). Dos guardas para que nunca
        -- pague de menos por descuido:
        --   · sin básica legal fijada → el salario del tramo, como siempre
        --   · si el tramo está por debajo de la básica → el tramo, sin subirlo
        -- Y la propiedad que lo hace seguro: al 100%, base + (rango − base) es
        -- el rango exacto, así que el defecto no mueve ningún pago.
        select coalesce(sum(case when tt.salario is not null then x.h * (
                 case
                   when pe.sueldo_base_legal is null then tt.salario
                   when tt.salario <= pe.sueldo_base_legal then tt.salario
                   else pe.sueldo_base_legal
                        + (tt.salario - pe.sueldo_base_legal)
                          * coalesce(rmp.porcentaje, 100) / 100.0
                 end
               ) / v_base end), 0) as pago,
               -- La parte que corresponde a la básica legal NO se escala por la
               -- puntuación: es lo fijo. Se prorratea solo por horas.
               coalesce(sum(case when tt.salario is not null and pe.sueldo_base_legal is not null
                                 then x.h * least(pe.sueldo_base_legal, tt.salario) / v_base end), 0) as basica,
               coalesce(sum(case when tt.salario is null then x.h end), 0) as sin_sal
        from horas x
        left join lateral (
          select t.salario from tramos t
          where t.persona_id = x.persona_id and x.fecha between t.t_ini and t.t_fin
          order by t.t_ini desc limit 1
        ) tt on true
        where x.persona_id = pe.id
      ) hh on true
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id
        order by t.t_fin desc, t.t_ini desc limit 1
      ) sf on true
    ) pb on true
    left join lateral (
      select t.rango, t.salario, t.base_provision              -- CAMBIO 0111
      from tramos t
      where t.persona_id = pe.id
      order by t.t_fin desc, t.t_ini desc
      limit 1
    ) ref on true
    -- ⇩⇩⇩ CAMBIO 0114 ⇩⇩⇩ La tasa de pensión EXACTA de esta persona.
    --
    -- Hasta la 0113 el descuento usaba una sola tasa global (configuracion.tasa_afp,
    -- el 13% aproximado). Ahora sale del régimen de cada uno: Profuturo cobra
    -- 13.06%, Integra 12.92%, Prima 12.97%, Habitat 12.84% y la ONP 13.00% exacto.
    --
    -- Se elige la fila VIGENTE a la fecha de fin del periodo, no la última: así un
    -- periodo de mayo se calcula con la comisión que estaba vigente en mayo, aunque
    -- la AFP la haya cambiado en junio. Las comisiones se mueven, y la prima de
    -- seguro la actualiza la SBS cada trimestre.
    --
    -- SI LA PERSONA NO TIENE RÉGIMEN ASIGNADO, el lateral no devuelve fila y más
    -- abajo el coalesce cae a la tasa global. Así nadie se queda sin descuento por
    -- un dato faltante, y la migración se puede aplicar aunque falten personas por
    -- clasificar.
    left join lateral (
      select tp.aporte + tp.comision + tp.prima as tasa
      from tasas_pension tp
      where tp.regimen = pe.regimen_pension
        and tp.vigente_desde <= p_fin
        and (tp.vigente_hasta is null or tp.vigente_hasta >= p_fin)
      order by tp.vigente_desde desc
      limit 1
    ) tpen on true
    -- ⇩⇩⇩ CAMBIO 0120 ⇩⇩⇩ LA ASIGNACIÓN POR EDUCACIÓN, por persona y con vigencia.
    --
    -- Por persona y no por rango porque depende del curso que cada uno lleva y de
    -- que traiga su comprobante. Dos personas del mismo rango pueden tener montos
    -- distintos, y eso no es un problema: es lo correcto, porque cada monto sigue
    -- el costo real de SU estudio. Que fueran todos iguales sería la señal de que
    -- el monto no sale de un comprobante sino de una resta.
    --
    -- Con vigencia porque alguien deja de estudiar en diciembre y en enero su
    -- asignación tiene que ser cero sin reescribir los meses en que sí estudió.
    -- ⇩⇩⇩ CAMBIO 0150 ⇩⇩⇩ Tres cambios, cada uno cerrando un agujero medido:
    --
    --   SUM y no LIMIT 1 · quien estudia y además tiene un hijo estudiando tenía
    --     dos filas y cobraba una; la otra se descartaba en silencio. El techo
    --     del rango se valida sobre la suma desde la 0149, así que sumar acá no
    --     puede pasarse del techo.
    --
    --   comprobante_url is not null · sin el papel no se paga. Una asignación se
    --     puede guardar mientras el comprobante llega (queda en amarillo en la
    --     pantalla), pero no devenga hasta que el papel esté cargado. Es lo que
    --     mantiene al concepto fuera de la remuneración: pagar sin comprobante es
    --     el caso exacto que la RTF 05449-4-2007 usó para desconocerlo.
    --
    --   p_ini y no p_fin · antes exigía seguir vigente el ÚLTIMO día del periodo,
    --     así que un ciclo que terminaba el 15 hacía que ese mes pagara CERO —
    --     habiendo estudiado y pagado la pensión del mes. Ahora basta con estar
    --     vigente al INICIAR el periodo y se paga el mes completo, que es como
    --     factura la institución.
    left join lateral (
      select sum(ae.monto) as monto,
             string_agg(distinct ae.institucion, ' · ') as instituciones
      from asignaciones_educacion ae
      where ae.persona_id = pe.id
        and ae.comprobante_url is not null
        and ae.vigente_desde <= p_ini
        and ae.vigente_hasta >= p_ini
    ) edu on true
    -- feriados: solo cuentan los que caen EN o DESPUÉS del ingreso de la persona
    left join lateral (
      -- ⇩⇩⇩ CAMBIO 0069 ⇩⇩⇩
      -- `ds.otorgado` = ese feriado se compensó con día libre (acta firmada).
      -- Cuando es true se anula el pago EXTRA de las horas laboradas (la
      -- sobretasa) y queda solo el día de feriado prorrateado — el feriado vale
      -- lo mismo que si no se hubiera trabajado. Las horas siguen pagadas en
      -- `pago_base`. Para volver a la lectura literal "adicional = 0",
      -- reemplazar todo el paréntesis por `0`.
      select coalesce(sum(case when tt.salario is not null and f.fecha >= pe.fecha_ingreso
               then ((case when ds.otorgado then 0 else coalesce(hf.h, 0) end)
                     + 7.5 * h.horas_mes / v_base) * tt.salario / v_base end), 0) as monto,
             count(*) filter (where tt.salario is null and f.fecha >= pe.fecha_ingreso) as sin_tramo,
             count(*) filter (where f.fecha < pe.fecha_ingreso) as no_corresponde,
             count(*) filter (where ds.otorgado) as compensados,
             coalesce(jsonb_agg(jsonb_build_object(
               'fecha', f.fecha,
               'horas_trabajadas', coalesce(hf.h, 0),
               'proporcional_horas', case when f.fecha >= pe.fecha_ingreso
                                          then round(7.5 * h.horas_mes / v_base, 2) else 0 end,
               'sin_salario', (tt.salario is null and f.fecha >= pe.fecha_ingreso),
               'antes_ingreso', (f.fecha < pe.fecha_ingreso),
               'descanso_sustitutorio', ds.otorgado,
               'descanso_fecha', ds.fecha_descanso
             ) order by f.fecha), '[]'::jsonb) as detalle
      from feriados f
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id and f.fecha between t.t_ini and t.t_fin
        order by t.t_ini desc limit 1
      ) tt on true
      left join horas hf on hf.persona_id = pe.id and hf.fecha = f.fecha
      left join lateral (
        -- Solo OTORGADO anula la sobretasa. PENDIENTE y NO_OTORGADO pagan
        -- normal — VALIDACIÓN 3: NO_OTORGADO revierte solo, sin tocar nada.
        select true as otorgado, d.fecha_descanso_sustitutorio as fecha_descanso
        from feriados_descanso_sustitutorio d
        where d.persona_id = pe.id and d.fecha_feriado = f.fecha and d.estado = 'OTORGADO'
        limit 1
      ) ds on true
      where f.fecha between p_ini and p_fin
      -- ⇧⇧⇧ CAMBIO 0069 ⇧⇧⇧
    ) fer on true
    left join lateral (
      select om.cumplidos, om.total,
             case
               when om.cumplidos is null or ref.salario is null then 0
               when om.cumplidos::numeric / om.total >= 1 then 0.21 * ref.salario
               when om.cumplidos::numeric / om.total >= 0.6 then 0.126 * ref.salario
               else 0
             end as monto
      from (select 1) uno
      left join objetivos_mensuales om
        on om.persona_id = pe.id and om.anio = v_anio and om.mes = v_mes
    ) obj on true
    -- ⇩ CAMBIO 0100 ⇩ Días del periodo que caen dentro de un periodo de
    -- vacaciones de esta persona. Solo se LEE: esta función nunca escribe.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      where exists (
        select 1 from vacaciones v
        where v.persona_id = pe.id
          and d.d::date between v.fecha_inicio and v.fecha_fin
      )
    ) vac on true
    -- Días que esta persona TENÍA que trabajar según su horario vigente. Si son
    -- cero, no marcó porque no le tocaba: no es una ausencia, es un dato que falta.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia   -- CAMBIO 0109
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hh on true
      -- ⇩⇩⇩ CAMBIO 0109 ⇩⇩⇩ Dos arreglos en una condición.
      --
      -- 1. isodow → dow. Postgres tiene dos funciones de día de semana y devuelven
      --    números distintos para el domingo: dow da 0, isodow da 7. TODO el resto
      --    del sistema usa dow —la 0015 valida el rango 0..6, las faltas (0054, 0060),
      --    el auto-cierre (0036) y la pantalla de Turnos— y el esquema documenta
      --    «0=domingo … 6=sábado». Solo esta línea usaba isodow.
      --    Como el array solo admite 0..6, el domingo únicamente puede guardarse
      --    como 0, e isodow jamás devuelve 0: el domingo NUNCA contaba como día
      --    laborable. En Trujillo se trabaja domingo, así que a esa gente le faltaban
      --    ~4 días al mes en la cuenta.
      --    Ese era el origen del «21 de 10 días que te tocaba trabajar» que apareció
      --    en producción: dias_trabajados sí cuenta domingos y dias_laborables no.
      --    En su momento se corrigió el TEXTO de la boleta; esta es la causa.
      --
      -- 2. Preferir horario_por_dia. La 0016 dejó dicho que dias_laborables queda
      --    como RESUMEN de compatibilidad y que la fuente de verdad es
      --    horario_por_dia (claves 0..6, día ausente = descanso). Las faltas ya lo
      --    leen así; la planilla se había quedado en el campo viejo. Ahora usa el
      --    mismo orden de preferencia que 0054 y 0060, para que no haya dos
      --    respuestas distintas a «¿le tocaba trabajar este día?».
      --
      -- NO MUEVE NINGÚN PAGO. lab.dias se usa en un solo lugar de toda la función:
      -- el campo 'dias_laborables' del JSON. No entra en pago_base, ni en feriados,
      -- ni en las provisiones. El generador lo verifica abajo.
      where case
              when hh.horario_por_dia is not null
                then hh.horario_por_dia ? (extract(dow from d.d)::int::text)
              else extract(dow from d.d)::int = any(hh.dias_laborables)
            end
    ) lab on true
    left join lateral (
      select coalesce(sum(m.monto) filter (where m.tipo = 'bono'), 0) as bonos,
             coalesce(sum(m.monto) filter (where m.tipo = 'descuento'), 0) as descuentos,
             coalesce(jsonb_agg(jsonb_build_object(
               'id', m.id, 'tipo', m.tipo, 'concepto', m.concepto, 'monto', m.monto
             ) order by m.created_at) filter (where m.id is not null), '[]'::jsonb) as detalle
      from movimientos_planilla m
      where p_periodo_id is not null
        and m.periodo_id = p_periodo_id
        and m.persona_id = pe.id
    ) mov on true
  ) sub;

  return v_out;
end;






$function$;


insert into migraciones_aplicadas (numero, nombre)
values (150, 'la_planilla_suma_la_educacion_y_exige_el_papel')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_sin_papel int;
  v_con_papel int;
begin
  select count(*) filter (where comprobante_url is null),
         count(*) filter (where comprobante_url is not null)
    into v_sin_papel, v_con_papel
  from asignaciones_educacion;

  raise notice '0150 · asignaciones que YA pagan (con comprobante): %', v_con_papel;
  raise notice '0150 · asignaciones guardadas SIN comprobante, que no pagan: %', v_sin_papel;
  if v_sin_papel > 0 then
    raise warning '0150 · esas % estan esperando su papel: no devengan hasta cargarlo.', v_sin_papel;
  end if;
end $mig$;
