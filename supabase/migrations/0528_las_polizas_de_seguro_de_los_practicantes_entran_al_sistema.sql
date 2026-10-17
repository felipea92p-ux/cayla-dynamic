-- ============================================================================
-- 0528 · las pólizas de seguro de los practicantes entran al sistema (etapa 1: DO)
-- ============================================================================
-- QUÉ PROMETE
--
--   Que la póliza FOLA —el «Seguro de Salud Practicantes» de Pacífico que
--   reemplazó a EsSalud el 2026-10-15 (0504)— viva DENTRO de Dynamic, una por
--   persona, con lo que hoy solo está en docs/estado.md y en el correo de Felipe:
--   número, vigencia, prima, si está pagada, si está firmada, si llegó la
--   factura, y los PDF (póliza, convenio de pago, factura).
--
--   Y que el sistema diga lo que nadie estaba mirando: QUÉ PRACTICANTE ACTIVO NO
--   TIENE UNA PÓLIZA QUE CUBRA HOY. La 0504 quitó EsSalud a todos de una vez y la
--   póliza es nominal: una practicante nueva, o una póliza que vence sin renovarse,
--   deja a alguien sin ningún seguro, y no contratarlo es infracción por sí solo
--   (Ley 28518, art. 52.5). Hasta hoy nada en el sistema lo notaba.
--
--   Es la ETAPA 1: solo Desarrollo Organizacional ve y escribe. La etapa 2 —«Mi
--   seguro» en Lo mío— agrega después una función `fn_mi_seguro` y la lectura de
--   cada persona sobre SU póliza; esta migración no abre nada para el practicante.
--
-- QUÉ ASUME
--
--   · `fn_es_admin_o_lider()` es «DO» (0078); `fn_persona_actual_id()` y
--     `fn_hoy_lima()` existen. Un practicante es `personas.tipo_vinculo =
--     'practicante'`, está activo si `estado = 'activo'`, y una cuenta de
--     servicio no es una persona (0490).
--   · La póliza cubre desde `vigente_desde` y hasta `vigente_hasta` EXCLUSIVO: el
--     papel dice «01/10/2026 al 01/01/2027, 92 días, a las 12 M», y de octubre 1 a
--     enero 1 son justo 92 días. El último día entero cubierto es el 31/12; el 1/1
--     ya cuenta como sin cubrir. Se eligió el lado cauteloso a propósito: equivocarse
--     aquí es avisar un día antes, no dejar a alguien sin seguro.
--   · Que el navegador sube el archivo al bucket `polizas-seguro` ANTES de llamar a
--     `fn_seguro_adjuntar` (el molde de la 0503: si Storage falla no queda ninguna
--     fila que nadie pueda abrir).
--
-- POR QUÉ TABLAS NUEVAS Y NO LAS QUE YA EXISTEN
--
--   · `archivo_empresa` (0503) es papel de la EMPRESA y no tiene persona: la
--     etapa 2 no podría enseñarle a una practicante SU póliza, y esta lleva DNI y
--     fecha de nacimiento del asegurado.
--   · `documentos_firmados` (0157) solo admite ruta, política y bono, y alimenta
--     los contadores de pendientes de cada persona.
--   · `correcciones_auditoria` NO se usa para el rastro: sus filas las leen la
--     ficha de la persona, Lo mío (cambios-mios), Correcciones y el CSV, y cada una
--     de esas pantallas tendría que aprender a rotular «seguro.pagada_el». Esta
--     tabla lleva su propio historial (`polizas_seguro_eventos`) y no le agrega
--     filas raras a cuatro pantallas que nadie pidió tocar.
--
--   Tres tablas: la póliza, sus archivos y su historial. Los archivos no se borran:
--   se retiran con motivo, y la póliza se ANULA con motivo (si se registró por
--   error), nunca se borra.
--
-- ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles)
--
--   · una póliza que termina antes de empezar ................ check
--   · dos pólizas vivas de la MISMA persona que se pisan ...... la función (rango
--       `[desde, hasta)`: una que empieza el día que otra termina NO se pisa, que es
--       como se renueva)
--   · el mismo número con la misma vigencia dos veces ......... índice único parcial
--       (la renovación automática puede conservar el número: lo que cambia es la
--       vigencia, por eso entra en la llave)
--   · una póliza de alguien que no es practicante ............. la función
--   · una ruta de archivo con nombres o DNI .................... check: `<uuid>.<ext>`
--   · un archivo que dos filas usan ............................ índice único
--   · una anulación o un retiro sin motivo ..................... check
--   · alguien sin DO leyendo una póliza o su PDF ............... RLS + política de
--       Storage
--   · escribir una póliza con la sesión de un usuario .......... sin política Y sin
--       privilegio (molde de la 0507/0509: aquí nadie legítimo escribe directo)
--   · pisar o borrar un archivo que una fila usa ............... la política de
--       update/delete de Storage exige que nadie lo referencie
--
-- LO QUE DECIDÍ, Y LO QUE DESCARTÉ
--
--   DECIDÍ:    Solo ALERTA. Nada de aquí cambia lo que cobra o paga nadie ni toca
--              `fn_planilla_calcular_nucleo`: la prima se paga a la aseguradora y no
--              pasa por la planilla (0504 lo dejó dicho).
--   DECIDÍ:    `plan` y los dos beneficios máximos son OPCIONALES y quedan «sin
--              confirmar» mientras estén vacíos. La casilla «Beneficio máximo anual»
--              viene VACÍA en las condiciones particulares de las cuatro pólizas y el
--              plan no figura en ningún papel: confirmarlos con el corredor sigue
--              abierto (docs/estado.md). Un campo obligatorio habría empujado a
--              escribir un número que nadie ha visto.
--   DECIDÍ:    `renueva_sola` es `boolean` con null = «sin confirmar». La tabla de
--              beneficios dice «Renovación automática: Aplica» y docs/estado.md
--              asumía lo contrario; hasta que el corredor conteste, no se sabe.
--   DESCARTÉ:  Un rango `daterange` con `exclude using gist` para impedir el
--              solapamiento: pide la extensión `btree_gist`, que en producción se
--              pega a mano y se olvida. La función lo comprueba con la fila bloqueada.
--   DESCARTÉ:  Un catálogo de productos o de aseguradoras. Hoy hay una póliza de un
--              producto; el `check` de `producto` tiene un solo valor, y agregar otro
--              es una línea en una migración. Una tabla de productos sería una lista
--              mantenida por una pantalla que nadie necesita todavía.
--
-- QUÉ NO HACE
--
--   · No avisa a la persona ni le muestra nada: es la etapa 2.
--   · No compara el beneficio máximo con las 14 y 30 subvenciones que el convenio
--     promete (Ley 28518, art. 42.8): para eso hace falta la subvención pactada de
--     cada quien, y esta migración no lee `asignaciones_salario`. Los beneficios se
--     guardan para que esa comparación sea una consulta, no una búsqueda en un PDF.
--   · No habla con Pacífico. Que la póliza exista y esté pagada lo dice quien la
--     registra; el sistema no lo puede comprobar.
--   · Ninguna función existente se reescribe → no hay md5 de partida.
--
-- SE ROMPE SI
--
--   · Una pantalla futura escribe estas tablas con la sesión del usuario. Dará
--     «permission denied for table …»: lo correcto es una función `SECURITY
--     DEFINER`, no devolver el privilegio. La prueba 422 exige las dos cosas (sin
--     política Y sin privilegio) y fallaría en `db-tests` antes de fusionar.
--   · Se agrega un segundo producto de seguro y se olvida que `fn_seguros_tablero`
--     marca como hueco a quien no tiene póliza de `salud_practicantes`: un
--     practicante con otro producto aparecería «sin póliza». La regla de quién debe
--     tener qué vive en esa función y en ninguna otra.
--
-- ANTES DE PEGAR — UNA CONSULTA DE SOLO LECTURA A PRODUCCIÓN (SQL Editor)
--   Esperado: ninguna tabla ni función con esos nombres, y las tres de apoyo
--   presentes. Si `tablas_que_ya_existen` no sale 0, PARAR: otra sesión la creó.
--
--   select
--     (select count(*) from information_schema.tables
--       where table_schema = 'public'
--         and table_name in ('polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos'))
--                                                            as tablas_que_ya_existen,
--     (select count(*) from pg_proc where proname like 'fn\_seguro%' or proname like 'fn\_seguros%')
--                                                            as funciones_que_ya_existen,
--     (select count(*) from pg_proc where proname in
--       ('fn_es_admin_o_lider','fn_persona_actual_id','fn_hoy_lima'))
--                                                            as apoyo_de_3,
--     (select count(*) from storage.buckets where id = 'polizas-seguro') as bucket_que_ya_existe,
--     (select string_agg(numero || ' · ' || nombre, ' | ' order by numero) from migraciones_aplicadas
--       where numero between 524 and 530)                    as registro_524_a_530;
--
-- CÓMO SE REVIERTE
--   drop function if exists
--     fn_seguro_registrar(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text),
--     fn_seguro_corregir(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text, text),
--     fn_seguro_marcar_paso(uuid, text, date, text), fn_seguro_anular(uuid, text),
--     fn_seguro_adjuntar(uuid, text, text, text), fn_seguro_retirar_archivo(uuid, text),
--     fn_seguro_archivo_libre(text), fn_seguro_datos_validos(text, text, date, date, numeric, date, text, numeric, numeric, text),
--     fn_seguros_tablero(), fn_seguro_historial(uuid), fn_seguro_archivos(uuid);
--   drop policy polizas_seguro_insert/select/update/delete on storage.objects;
--   drop table polizas_seguro_eventos, polizas_seguro_archivos, polizas_seguro;
--   delete from storage.objects where bucket_id = 'polizas-seguro';  -- vaciar antes
--   delete from storage.buckets where id = 'polizas-seguro';
--   Nada de planilla, asistencia ni pago lee estas tablas: revertir solo quita la
--   pantalla. Ojo: borrarlas destruye el registro de quién marcó cada paso.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final, que va la última porque el SQL Editor solo muestra el
--   resultado de la última. Y la prueba 422 en `db-tests`.
-- ============================================================================


-- ── 1 · El bucket ────────────────────────────────────────────────────────────
-- Privado. La póliza llega en PDF (la de las cuatro pesa 1,7 MB); las fotos se
-- admiten para un papel que solo existe impreso. HEIC porque así guarda un
-- iPhone sus fotos (lección de la 0170). El PDF lleva DNI y fecha de nacimiento
-- del asegurado: por eso es de DO, y no del archivo general de la empresa.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('polizas-seguro', 'polizas-seguro', false, 52428800,
        array['application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


-- ── 2 · Las tablas ───────────────────────────────────────────────────────────
create table if not exists polizas_seguro (
  id                  uuid primary key default gen_random_uuid(),
  persona_id          uuid not null references personas(id),
  -- Un solo producto hoy. Ver «DESCARTÉ» en la cabecera.
  producto            text not null default 'salud_practicantes'
                      check (producto in ('salud_practicantes')),
  aseguradora         text not null check (char_length(btrim(aseguradora)) between 2 and 120),
  numero_poliza       text not null check (char_length(btrim(numero_poliza)) between 3 and 40),
  vigente_desde       date not null,
  -- EXCLUSIVO: la póliza cubre hasta las 12 M de este día. Ver «QUÉ ASUME».
  vigente_hasta       date not null,
  -- Prima comercial + IGV, la que se paga (179.97 en las cuatro de hoy).
  prima_total         numeric(10,2) not null check (prima_total >= 0),
  -- Cuándo vence el pago de contado. Con 30 días de mora la cobertura se
  -- suspende sola (convenio de pago, cláusula quinta).
  prima_vence_el      date,
  -- «Plan 1», «Plan 2»: el papel NO lo dice; lo confirma el corredor.
  plan                text check (plan is null or char_length(btrim(plan)) between 1 and 60),
  beneficio_enfermedad numeric(12,2) check (beneficio_enfermedad is null or beneficio_enfermedad > 0),
  beneficio_accidente  numeric(12,2) check (beneficio_accidente is null or beneficio_accidente > 0),
  -- null = sin confirmar. Ver «DECIDÍ» en la cabecera.
  renueva_sola        boolean,
  -- Los tres pasos del papeleo. Una fecha = hecho ese día; null = pendiente.
  pagada_el           date,
  firmada_el          date,
  factura_recibida_el date,
  nota                text check (nota is null or char_length(nota) <= 2000),
  creada_por          uuid not null references personas(id),
  creada_at           timestamptz not null default now(),
  anulada_at          timestamptz,
  anulada_por         uuid references personas(id),
  anulada_motivo      text,
  constraint poliza_termina_despues_de_empezar check (vigente_hasta > vigente_desde),
  constraint poliza_anulacion_completa check (
    (anulada_at is null and anulada_por is null and anulada_motivo is null)
    or (anulada_at is not null and anulada_por is not null
        and char_length(btrim(anulada_motivo)) >= 5)
  )
);

comment on table polizas_seguro is
  'Una póliza de seguro por persona (hoy: Seguro de Salud Practicantes, Pacífico). Solo DO. Escritura solo por las funciones fn_seguro_*; nada se borra: una póliza registrada por error se anula con motivo.';
comment on column polizas_seguro.vigente_hasta is
  'EXCLUSIVO: la póliza cubre hasta las 12 M de ese día, así que ese día ya cuenta como sin cubrir.';
comment on column polizas_seguro.plan is
  'Plan de la póliza. Opcional: el papel no lo dice y lo confirma el corredor; vacío = sin confirmar.';
comment on column polizas_seguro.renueva_sola is
  'null = sin confirmar. La tabla de beneficios dice «Renovación automática: Aplica».';

-- El mismo número con la misma vigencia, una sola vez entre las vivas. La
-- renovación automática puede conservar el número: cambia la vigencia.
create unique index if not exists idx_polizas_seguro_numero_vigencia
  on polizas_seguro (aseguradora, numero_poliza, vigente_desde) where anulada_at is null;
create index if not exists idx_polizas_seguro_persona on polizas_seguro (persona_id, vigente_desde desc);


create table if not exists polizas_seguro_archivos (
  id              uuid primary key default gen_random_uuid(),
  poliza_id       uuid not null references polizas_seguro(id),
  tipo            text not null check (tipo in ('poliza','convenio_pago','factura','otro')),
  -- `<uuid>.<ext>` y nada más: ni nombres ni DNI en la ruta. Única: un archivo,
  -- una fila.
  storage_path    text not null check (storage_path ~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$'),
  -- El nombre con que se subió, para reconocerlo al abrirlo.
  nombre_archivo  text not null check (char_length(btrim(nombre_archivo)) between 1 and 255),
  mime            text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif')),
  bytes           bigint not null check (bytes > 0),
  subido_por      uuid not null references personas(id),
  subido_at       timestamptz not null default now(),
  retirado_at     timestamptz,
  retirado_por    uuid references personas(id),
  retirado_motivo text,
  constraint poliza_archivo_retiro_completo check (
    (retirado_at is null and retirado_por is null and retirado_motivo is null)
    or (retirado_at is not null and retirado_por is not null
        and char_length(btrim(retirado_motivo)) >= 5)
  )
);

comment on table polizas_seguro_archivos is
  'Los PDF de cada póliza (póliza, convenio de pago, factura). Solo DO. Nada se borra: un archivo se retira con motivo.';

create unique index if not exists idx_polizas_seguro_archivos_ruta on polizas_seguro_archivos (storage_path);
create index if not exists idx_polizas_seguro_archivos_poliza on polizas_seguro_archivos (poliza_id, subido_at desc);


create table if not exists polizas_seguro_eventos (
  id         uuid primary key default gen_random_uuid(),
  poliza_id  uuid not null references polizas_seguro(id),
  evento     text not null check (evento in (
               'registrada','datos_corregidos','paso_marcado','paso_desmarcado',
               'archivo_adjuntado','archivo_retirado','anulada')),
  -- Una frase legible, no un json: «Prima pagada el 15/10/2026».
  detalle    text not null check (char_length(btrim(detalle)) >= 3),
  motivo     text,
  hecho_por  uuid not null references personas(id),
  -- `clock_timestamp()` y no `now()`: dentro de una transacción `now()` vale lo
  -- MISMO para todas las filas, y un historial cuyo orden depende del orden físico
  -- de la tabla no es un orden (lección de la 0312/0389).
  hecho_at   timestamptz not null default clock_timestamp()
);

comment on table polizas_seguro_eventos is
  'Rastro de cada póliza: quién hizo qué y cuándo. Solo lo escriben las funciones fn_seguro_*; no se edita ni se borra.';

create index if not exists idx_polizas_seguro_eventos_poliza on polizas_seguro_eventos (poliza_id, hecho_at desc);


-- ── 3 · Permisos y RLS ───────────────────────────────────────────────────────
-- Leer: solo DO. Escribir: nadie directo; todo por las funciones de abajo. Se
-- quita lo que Supabase concede por defecto (incluye escribir y `truncate`).
alter table polizas_seguro          enable row level security;
alter table polizas_seguro_archivos enable row level security;
alter table polizas_seguro_eventos  enable row level security;

drop policy if exists polizas_seguro_select_do on polizas_seguro;
create policy polizas_seguro_select_do on polizas_seguro
  for select to authenticated using (fn_es_admin_o_lider() is true);
drop policy if exists polizas_seguro_archivos_select_do on polizas_seguro_archivos;
create policy polizas_seguro_archivos_select_do on polizas_seguro_archivos
  for select to authenticated using (fn_es_admin_o_lider() is true);
drop policy if exists polizas_seguro_eventos_select_do on polizas_seguro_eventos;
create policy polizas_seguro_eventos_select_do on polizas_seguro_eventos
  for select to authenticated using (fn_es_admin_o_lider() is true);

revoke all on polizas_seguro, polizas_seguro_archivos, polizas_seguro_eventos from anon, authenticated, public;
grant select on polizas_seguro, polizas_seguro_archivos, polizas_seguro_eventos to authenticated;


-- ── 4 · Storage ──────────────────────────────────────────────────────────────
-- Un archivo está «libre» si ninguna fila lo usa (ni una retirada: el retiro
-- conserva el archivo). Solo entonces se puede pisar o borrar: limpiar un huérfano.
create or replace function fn_seguro_archivo_libre(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select not exists (select 1 from polizas_seguro_archivos a where a.storage_path = p_path);
$fn$;

-- Las CUATRO políticas, no una: Supabase Storage escribe con
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *` y necesita insert, select y
-- update para subir (0172, 0175, 0197 costaron medio día por faltar una).
drop policy if exists polizas_seguro_insert on storage.objects;
drop policy if exists polizas_seguro_select on storage.objects;
drop policy if exists polizas_seguro_update on storage.objects;
drop policy if exists polizas_seguro_delete on storage.objects;

create policy polizas_seguro_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'polizas-seguro'
    and fn_es_admin_o_lider() is true
    and name ~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$'
  );

create policy polizas_seguro_select on storage.objects
  for select to authenticated
  using (bucket_id = 'polizas-seguro' and fn_es_admin_o_lider() is true);

create policy polizas_seguro_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'polizas-seguro' and fn_es_admin_o_lider() is true and fn_seguro_archivo_libre(name))
  with check (bucket_id = 'polizas-seguro' and fn_es_admin_o_lider() is true and fn_seguro_archivo_libre(name));

create policy polizas_seguro_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'polizas-seguro' and fn_es_admin_o_lider() is true and fn_seguro_archivo_libre(name));


-- ── 5 · Las reglas de los datos, escritas UNA vez ────────────────────────────
-- La usan `fn_seguro_registrar` y `fn_seguro_corregir`. Nadie la llama desde
-- fuera: se le quita el EXECUTE a todos (corre porque las dos que la llaman son
-- SECURITY DEFINER y la dueña es la misma).
create or replace function fn_seguro_datos_validos(
  p_aseguradora          text,
  p_numero_poliza        text,
  p_vigente_desde        date,
  p_vigente_hasta        date,
  p_prima_total          numeric,
  p_prima_vence_el       date,
  p_plan                 text,
  p_beneficio_enfermedad numeric,
  p_beneficio_accidente  numeric,
  p_nota                 text
)
returns void
language plpgsql stable set search_path = public
as $fn$
begin
  if p_aseguradora is null or char_length(btrim(p_aseguradora)) < 2 then
    raise exception 'Escribe la aseguradora.';
  end if;
  if p_numero_poliza is null or char_length(btrim(p_numero_poliza)) < 3 then
    raise exception 'Escribe el número de la póliza.';
  end if;
  if p_vigente_desde is null or p_vigente_hasta is null then
    raise exception 'Faltan las fechas de la vigencia.';
  end if;
  if p_vigente_hasta <= p_vigente_desde then
    raise exception 'La vigencia tiene que terminar después de empezar.';
  end if;
  if p_prima_total is null or p_prima_total < 0 then
    raise exception 'Escribe la prima total (con IGV); puede ser 0 si no hay que pagar.';
  end if;
  if p_beneficio_enfermedad is not null and p_beneficio_enfermedad <= 0 then
    raise exception 'El beneficio máximo por enfermedad tiene que ser mayor que 0, o quedar vacío si no está confirmado.';
  end if;
  if p_beneficio_accidente is not null and p_beneficio_accidente <= 0 then
    raise exception 'El beneficio máximo por accidente tiene que ser mayor que 0, o quedar vacío si no está confirmado.';
  end if;
  if p_plan is not null and btrim(p_plan) <> '' and char_length(btrim(p_plan)) > 60 then
    raise exception 'El plan es demasiado largo (máximo 60 letras).';
  end if;
  if p_nota is not null and char_length(p_nota) > 2000 then
    raise exception 'La nota es demasiado larga (máximo 2000 letras).';
  end if;
end;
$fn$;

revoke execute on function fn_seguro_datos_validos(text, text, date, date, numeric, date, text, numeric, numeric, text)
  from public, anon, authenticated;


-- ── 6 · Registrar una póliza ─────────────────────────────────────────────────
-- Devuelve el id de la póliza. Todo en una transacción.
create or replace function fn_seguro_registrar(
  p_persona_id           uuid,
  p_aseguradora          text,
  p_numero_poliza        text,
  p_vigente_desde        date,
  p_vigente_hasta        date,
  p_prima_total          numeric,
  p_prima_vence_el       date,
  p_plan                 text,
  p_beneficio_enfermedad numeric,
  p_beneficio_accidente  numeric,
  p_renueva_sola         boolean,
  p_nota                 text
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_p     personas%rowtype;
  v_id    uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede registrar pólizas de seguro.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  -- La fila de la persona se bloquea: dos DO registrando a la misma persona a la
  -- vez se ordenan, y la segunda ve la póliza de la primera al comprobar el solape.
  select * into v_p from personas p where p.id = p_persona_id for update;
  if not found then
    raise exception 'Esa persona no existe.';
  end if;
  if v_p.tipo_vinculo is distinct from 'practicante' then
    raise exception 'Esta póliza es el Seguro de Salud Practicantes: solo se registra a quien está en modalidad formativa.';
  end if;
  if v_p.estado is distinct from 'activo' then
    raise exception 'Esa persona está inactiva.';
  end if;

  perform fn_seguro_datos_validos(p_aseguradora, p_numero_poliza, p_vigente_desde, p_vigente_hasta,
                                  p_prima_total, p_prima_vence_el, p_plan,
                                  p_beneficio_enfermedad, p_beneficio_accidente, p_nota);

  if exists (select 1 from polizas_seguro z
              where z.persona_id = p_persona_id and z.anulada_at is null
                and daterange(z.vigente_desde, z.vigente_hasta) && daterange(p_vigente_desde, p_vigente_hasta)) then
    raise exception 'Esa persona ya tiene una póliza que se cruza con esas fechas. Si la anterior estaba mal, anúlala primero.';
  end if;

  begin
    insert into polizas_seguro
      (persona_id, aseguradora, numero_poliza, vigente_desde, vigente_hasta, prima_total, prima_vence_el,
       plan, beneficio_enfermedad, beneficio_accidente, renueva_sola, nota, creada_por)
    values
      (p_persona_id, btrim(p_aseguradora), btrim(p_numero_poliza), p_vigente_desde, p_vigente_hasta,
       p_prima_total, p_prima_vence_el, nullif(btrim(p_plan), ''), p_beneficio_enfermedad,
       p_beneficio_accidente, p_renueva_sola, nullif(btrim(p_nota), ''), v_quien)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya hay una póliza viva con ese número y esa fecha de inicio.';
  end;

  insert into polizas_seguro_eventos (poliza_id, evento, detalle, hecho_por)
  values (v_id, 'registrada',
          format('Póliza %s, del %s al %s', btrim(p_numero_poliza),
                 to_char(p_vigente_desde, 'DD/MM/YYYY'), to_char(p_vigente_hasta, 'DD/MM/YYYY')),
          v_quien);

  return v_id;
end;
$fn$;


-- ── 7 · Corregir los datos de una póliza ─────────────────────────────────────
-- La pantalla manda TODOS los campos; la función solo escribe lo que cambió y
-- deja dicho qué era antes. La persona no se cambia: se anula y se registra otra.
create or replace function fn_seguro_corregir(
  p_id                   uuid,
  p_aseguradora          text,
  p_numero_poliza        text,
  p_vigente_desde        date,
  p_vigente_hasta        date,
  p_prima_total          numeric,
  p_prima_vence_el       date,
  p_plan                 text,
  p_beneficio_enfermedad numeric,
  p_beneficio_accidente  numeric,
  p_renueva_sola         boolean,
  p_nota                 text,
  p_motivo               text
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien   uuid := fn_persona_actual_id();
  v_a       polizas_seguro%rowtype;
  v_cambios text := '';
  v_asegur  text := btrim(p_aseguradora);
  v_numero  text := btrim(p_numero_poliza);
  v_plan    text := nullif(btrim(p_plan), '');
  v_nota    text := nullif(btrim(p_nota), '');
  v_na      text := 'sin confirmar';
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede corregir pólizas de seguro.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado en el historial de la póliza.';
  end if;

  select * into v_a from polizas_seguro z where z.id = p_id for update;
  if not found then
    raise exception 'Esa póliza no existe.';
  end if;
  if v_a.anulada_at is not null then
    raise exception 'Esa póliza está anulada: no se corrige.';
  end if;

  perform fn_seguro_datos_validos(p_aseguradora, p_numero_poliza, p_vigente_desde, p_vigente_hasta,
                                  p_prima_total, p_prima_vence_el, p_plan,
                                  p_beneficio_enfermedad, p_beneficio_accidente, p_nota);

  if exists (select 1 from polizas_seguro z
              where z.persona_id = v_a.persona_id and z.anulada_at is null and z.id <> p_id
                and daterange(z.vigente_desde, z.vigente_hasta) && daterange(p_vigente_desde, p_vigente_hasta)) then
    raise exception 'Esas fechas se cruzan con otra póliza de la misma persona.';
  end if;

  if v_a.aseguradora is distinct from v_asegur then
    v_cambios := v_cambios || format('aseguradora: %s → %s; ', v_a.aseguradora, v_asegur);
  end if;
  if v_a.numero_poliza is distinct from v_numero then
    v_cambios := v_cambios || format('número: %s → %s; ', v_a.numero_poliza, v_numero);
  end if;
  if v_a.vigente_desde is distinct from p_vigente_desde then
    v_cambios := v_cambios || format('desde: %s → %s; ', to_char(v_a.vigente_desde, 'DD/MM/YYYY'), to_char(p_vigente_desde, 'DD/MM/YYYY'));
  end if;
  if v_a.vigente_hasta is distinct from p_vigente_hasta then
    v_cambios := v_cambios || format('hasta: %s → %s; ', to_char(v_a.vigente_hasta, 'DD/MM/YYYY'), to_char(p_vigente_hasta, 'DD/MM/YYYY'));
  end if;
  if v_a.prima_total is distinct from p_prima_total then
    v_cambios := v_cambios || format('prima: %s → %s; ',
      to_char(v_a.prima_total, 'FM999999990.00'), to_char(p_prima_total, 'FM999999990.00'));
  end if;
  if v_a.prima_vence_el is distinct from p_prima_vence_el then
    v_cambios := v_cambios || format('prima vence: %s → %s; ',
      coalesce(to_char(v_a.prima_vence_el, 'DD/MM/YYYY'), 'sin fecha'), coalesce(to_char(p_prima_vence_el, 'DD/MM/YYYY'), 'sin fecha'));
  end if;
  if v_a.plan is distinct from v_plan then
    v_cambios := v_cambios || format('plan: %s → %s; ', coalesce(v_a.plan, v_na), coalesce(v_plan, v_na));
  end if;
  if v_a.beneficio_enfermedad is distinct from p_beneficio_enfermedad then
    v_cambios := v_cambios || format('beneficio por enfermedad: %s → %s; ',
      coalesce(to_char(v_a.beneficio_enfermedad, 'FM999999990.00'), v_na),
      coalesce(to_char(p_beneficio_enfermedad, 'FM999999990.00'), v_na));
  end if;
  if v_a.beneficio_accidente is distinct from p_beneficio_accidente then
    v_cambios := v_cambios || format('beneficio por accidente: %s → %s; ',
      coalesce(to_char(v_a.beneficio_accidente, 'FM999999990.00'), v_na),
      coalesce(to_char(p_beneficio_accidente, 'FM999999990.00'), v_na));
  end if;
  if v_a.renueva_sola is distinct from p_renueva_sola then
    -- `case x when true … when false …` y no `case when x …`: con null el `else`
    -- diría «no» donde la verdad es «sin confirmar».
    v_cambios := v_cambios || format('renueva sola: %s → %s; ',
      coalesce(case v_a.renueva_sola when true then 'sí' when false then 'no' end, v_na),
      coalesce(case p_renueva_sola when true then 'sí' when false then 'no' end, v_na));
  end if;
  if v_a.nota is distinct from v_nota then
    v_cambios := v_cambios || 'nota; ';
  end if;

  if v_cambios = '' then
    raise exception 'No cambiaste ningún dato.';
  end if;

  begin
    update polizas_seguro
       set aseguradora = v_asegur, numero_poliza = v_numero,
           vigente_desde = p_vigente_desde, vigente_hasta = p_vigente_hasta,
           prima_total = p_prima_total, prima_vence_el = p_prima_vence_el,
           plan = v_plan, beneficio_enfermedad = p_beneficio_enfermedad,
           beneficio_accidente = p_beneficio_accidente, renueva_sola = p_renueva_sola,
           nota = v_nota
     where id = p_id;
  exception when unique_violation then
    raise exception 'Ya hay una póliza viva con ese número y esa fecha de inicio.';
  end;

  insert into polizas_seguro_eventos (poliza_id, evento, detalle, motivo, hecho_por)
  values (p_id, 'datos_corregidos', rtrim(v_cambios, '; '), btrim(p_motivo), v_quien);
end;
$fn$;


-- ── 8 · Marcar un paso del papeleo ───────────────────────────────────────────
-- p_paso: 'pagada' (la prima), 'firmada' (póliza y convenio de pago devueltos a
-- Pacífico) o 'factura' (la factura llegó). Con fecha = hecho ese día, y se
-- puede volver a marcar con otra fecha. Con `p_fecha` null = desmarcar, y eso
-- pide motivo: borrar un «pagada» es lo que más conviene que quede escrito.
create or replace function fn_seguro_marcar_paso(
  p_id     uuid,
  p_paso   text,
  p_fecha  date,
  p_motivo text default null
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien   uuid := fn_persona_actual_id();
  v_a       polizas_seguro%rowtype;
  v_etiq    text;
  v_antes   date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede marcar los pasos de una póliza.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_paso is null or p_paso not in ('pagada', 'firmada', 'factura') then
    raise exception 'Ese paso no existe: usa pagada, firmada o factura.';
  end if;

  select * into v_a from polizas_seguro z where z.id = p_id for update;
  if not found then
    raise exception 'Esa póliza no existe.';
  end if;
  if v_a.anulada_at is not null then
    raise exception 'Esa póliza está anulada: no se marca.';
  end if;

  v_etiq  := case p_paso when 'pagada'  then 'Prima pagada'
                         when 'firmada' then 'Póliza y convenio de pago firmados'
                                        else 'Factura recibida' end;
  v_antes := case p_paso when 'pagada'  then v_a.pagada_el
                         when 'firmada' then v_a.firmada_el
                                        else v_a.factura_recibida_el end;

  if p_fecha is null then
    if v_antes is null then
      raise exception 'Ese paso ya está sin marcar.';
    end if;
    if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
      raise exception 'Escribe el motivo (al menos 5 letras): desmarcar un paso queda anotado.';
    end if;
  else
    if p_fecha > fn_hoy_lima() then
      raise exception 'La fecha no puede ser posterior a hoy.';
    end if;
    if v_antes is not distinct from p_fecha then
      raise exception 'Ese paso ya estaba marcado con esa fecha.';
    end if;
  end if;

  update polizas_seguro
     set pagada_el           = case when p_paso = 'pagada'  then p_fecha else pagada_el end,
         firmada_el          = case when p_paso = 'firmada' then p_fecha else firmada_el end,
         factura_recibida_el = case when p_paso = 'factura' then p_fecha else factura_recibida_el end
   where id = p_id;

  insert into polizas_seguro_eventos (poliza_id, evento, detalle, motivo, hecho_por)
  values (p_id,
          case when p_fecha is null then 'paso_desmarcado' else 'paso_marcado' end,
          case
            when p_fecha is null  then format('%s: se quitó la marca del %s', v_etiq, to_char(v_antes, 'DD/MM/YYYY'))
            when v_antes is null  then format('%s el %s', v_etiq, to_char(p_fecha, 'DD/MM/YYYY'))
            else format('%s: %s → %s', v_etiq, to_char(v_antes, 'DD/MM/YYYY'), to_char(p_fecha, 'DD/MM/YYYY'))
          end,
          nullif(btrim(p_motivo), ''), v_quien);
end;
$fn$;


-- ── 9 · Anular una póliza ────────────────────────────────────────────────────
-- Para lo que se registró por error. La póliza no se borra: queda anulada, con
-- quién y por qué, y deja de contar para «cubre hoy» y para el solape, así que
-- se puede registrar la correcta.
create or replace function fn_seguro_anular(p_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_a     polizas_seguro%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede anular pólizas de seguro.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado junto a la póliza.';
  end if;

  select * into v_a from polizas_seguro z where z.id = p_id for update;
  if not found then
    raise exception 'Esa póliza no existe.';
  end if;
  if v_a.anulada_at is not null then
    raise exception 'Esa póliza ya está anulada.';
  end if;

  update polizas_seguro
     set anulada_at = now(), anulada_por = v_quien, anulada_motivo = btrim(p_motivo)
   where id = p_id;

  insert into polizas_seguro_eventos (poliza_id, evento, detalle, motivo, hecho_por)
  values (p_id, 'anulada', format('Póliza %s anulada', v_a.numero_poliza), btrim(p_motivo), v_quien);
end;
$fn$;


-- ── 10 · Adjuntar y retirar archivos ─────────────────────────────────────────
-- El archivo ya está en el bucket (el navegador lo subió primero). El peso y el
-- tipo salen de Storage, no de lo que diga el navegador.
create or replace function fn_seguro_adjuntar(
  p_poliza_id      uuid,
  p_tipo           text,
  p_storage_path   text,
  p_nombre_archivo text
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_obj   storage.objects%rowtype;
  v_a     polizas_seguro%rowtype;
  v_id    uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede adjuntar archivos a una póliza.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_tipo is null or p_tipo not in ('poliza', 'convenio_pago', 'factura', 'otro') then
    raise exception 'Ese tipo de archivo no existe: usa poliza, convenio_pago, factura u otro.';
  end if;
  if p_nombre_archivo is null or btrim(p_nombre_archivo) = '' then
    raise exception 'Falta el nombre del archivo.';
  end if;
  if p_storage_path is null or p_storage_path !~ '^[0-9a-f-]{36}\.[a-z0-9]{2,5}$' then
    raise exception 'La ruta del archivo no tiene la forma esperada.';
  end if;

  select * into v_a from polizas_seguro z where z.id = p_poliza_id for update;
  if not found then
    raise exception 'Esa póliza no existe.';
  end if;
  if v_a.anulada_at is not null then
    raise exception 'Esa póliza está anulada: no se le adjuntan archivos.';
  end if;

  select * into v_obj from storage.objects o
   where o.bucket_id = 'polizas-seguro' and o.name = p_storage_path;
  if not found then
    raise exception 'El archivo no llegó al almacén. Vuelve a subirlo.';
  end if;
  if exists (select 1 from polizas_seguro_archivos x where x.storage_path = p_storage_path) then
    raise exception 'Ese archivo ya está adjunto a una póliza.';
  end if;

  insert into polizas_seguro_archivos
    (poliza_id, tipo, storage_path, nombre_archivo, mime, bytes, subido_por)
  values
    (p_poliza_id, p_tipo, p_storage_path, btrim(p_nombre_archivo),
     v_obj.metadata->>'mimetype', (v_obj.metadata->>'size')::bigint, v_quien)
  returning id into v_id;

  insert into polizas_seguro_eventos (poliza_id, evento, detalle, hecho_por)
  values (p_poliza_id, 'archivo_adjuntado',
          format('%s: %s',
                 case p_tipo when 'poliza' then 'Póliza' when 'convenio_pago' then 'Convenio de pago'
                             when 'factura' then 'Factura' else 'Otro papel' end,
                 btrim(p_nombre_archivo)),
          v_quien);

  return v_id;
end;
$fn$;


create or replace function fn_seguro_retirar_archivo(p_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_f     polizas_seguro_archivos%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede retirar archivos de una póliza.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado junto al archivo.';
  end if;

  select * into v_f from polizas_seguro_archivos a where a.id = p_id for update;
  if not found then
    raise exception 'Ese archivo no existe.';
  end if;
  if v_f.retirado_at is not null then
    raise exception 'Ese archivo ya está retirado.';
  end if;

  update polizas_seguro_archivos
     set retirado_at = now(), retirado_por = v_quien, retirado_motivo = btrim(p_motivo)
   where id = p_id;

  insert into polizas_seguro_eventos (poliza_id, evento, detalle, motivo, hecho_por)
  values (v_f.poliza_id, 'archivo_retirado', format('Se retiró %s', v_f.nombre_archivo), btrim(p_motivo), v_quien);
end;
$fn$;


-- ── 11 · Lo que ve la pantalla ───────────────────────────────────────────────
-- UNA lista con dos clases de fila, y es aquí —y en ningún otro sitio— donde se
-- decide quién tiene que tener póliza:
--   · cada póliza viva (no anulada), de quien sea, con `cubre_hoy` ya resuelto y
--     `es_practicante_activo` para marcar la de quien ya no lo es (hay que pedirle
--     la baja a la aseguradora);
--   · una fila SIN póliza (`poliza_id` null) por cada practicante activo que no
--     tiene ninguna póliza viva que cubra hoy: el hueco. Si ese practicante tiene
--     pólizas vencidas, salen además como historia; la pantalla agrupa por persona.
create or replace function fn_seguros_tablero()
returns table (
  persona_id            uuid,
  persona               text,
  sede                  text,
  practicante_modalidad text,
  es_practicante_activo boolean,
  poliza_id             uuid,
  aseguradora           text,
  numero_poliza         text,
  vigente_desde         date,
  vigente_hasta         date,
  cubre_hoy             boolean,
  prima_total           numeric,
  prima_vence_el        date,
  plan                  text,
  beneficio_enfermedad  numeric,
  beneficio_accidente   numeric,
  renueva_sola          boolean,
  pagada_el             date,
  firmada_el            date,
  factura_recibida_el   date,
  nota                  text,
  archivos              integer,
  creada_at             timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_hoy date := fn_hoy_lima();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve los seguros del equipo.';
  end if;

  return query
  select t.*
    from (
      select p.id as persona_id,
             p.nombres || ' ' || p.apellidos as persona,
             coalesce(s.codigo, '?') as sede,
             p.practicante_modalidad,
             (p.tipo_vinculo = 'practicante' and p.estado = 'activo' and not p.cuenta_de_servicio) as es_practicante_activo,
             z.id as poliza_id, z.aseguradora, z.numero_poliza, z.vigente_desde, z.vigente_hasta,
             (v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta) as cubre_hoy,
             z.prima_total, z.prima_vence_el, z.plan, z.beneficio_enfermedad, z.beneficio_accidente,
             z.renueva_sola, z.pagada_el, z.firmada_el, z.factura_recibida_el, z.nota,
             (select count(*)::int from polizas_seguro_archivos a
               where a.poliza_id = z.id and a.retirado_at is null) as archivos,
             z.creada_at
        from polizas_seguro z
        join personas p on p.id = z.persona_id
        left join sedes s on s.id = p.sede_base_id
       where z.anulada_at is null

      union all

      select p.id, p.nombres || ' ' || p.apellidos, coalesce(s.codigo, '?'), p.practicante_modalidad,
             true,
             null::uuid, null::text, null::text, null::date, null::date, false,
             null::numeric, null::date, null::text, null::numeric, null::numeric,
             null::boolean, null::date, null::date, null::date, null::text, 0, null::timestamptz
        from personas p
        left join sedes s on s.id = p.sede_base_id
       where p.tipo_vinculo = 'practicante'
         and p.estado = 'activo'
         and not p.cuenta_de_servicio
         and not exists (select 1 from polizas_seguro z
                          where z.persona_id = p.id and z.anulada_at is null
                            and v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta)
    ) t
   -- `poliza_id` desc como ancla del orden: dos pólizas con la misma vigencia no
   -- empatan al azar (lección de la 0312/0389). La fila sin póliza va primero.
   order by t.persona, t.persona_id, t.vigente_desde desc nulls first, t.poliza_id desc nulls first;
end;
$fn$;


create or replace function fn_seguro_historial(p_id uuid)
returns table (
  evento    text,
  detalle   text,
  motivo    text,
  hecho_por text,
  hecho_at  timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve el historial de una póliza.';
  end if;

  return query
  select e.evento, e.detalle, e.motivo, btrim(p.nombres || ' ' || p.apellidos), e.hecho_at
    from polizas_seguro_eventos e
    left join personas p on p.id = e.hecho_por
   where e.poliza_id = p_id
   order by e.hecho_at desc, e.id desc;
end;
$fn$;


create or replace function fn_seguro_archivos(p_poliza_id uuid)
returns table (
  id                  uuid,
  tipo                text,
  storage_path        text,
  nombre_archivo      text,
  mime                text,
  bytes               bigint,
  subido_por_nombre   text,
  subido_at           timestamptz,
  retirado_at         timestamptz,
  retirado_por_nombre text,
  retirado_motivo     text
)
language plpgsql stable security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve los archivos de una póliza.';
  end if;

  return query
  select a.id, a.tipo, a.storage_path, a.nombre_archivo, a.mime, a.bytes,
         btrim(ps.nombres || ' ' || ps.apellidos), a.subido_at,
         a.retirado_at, btrim(pr.nombres || ' ' || pr.apellidos), a.retirado_motivo
    from polizas_seguro_archivos a
    left join personas ps on ps.id = a.subido_por
    left join personas pr on pr.id = a.retirado_por
   where a.poliza_id = p_poliza_id
   order by a.subido_at desc, a.id desc;
end;
$fn$;


-- ── 12 · Quién puede llamar qué ──────────────────────────────────────────────
-- Desde la 0076 ninguna función nace con EXECUTE para nadie: sin estos grants
-- la pantalla queda vacía sin dar error (0204).
grant execute on function
  fn_seguro_registrar(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text),
  fn_seguro_corregir(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text, text),
  fn_seguro_marcar_paso(uuid, text, date, text),
  fn_seguro_anular(uuid, text),
  fn_seguro_adjuntar(uuid, text, text, text),
  fn_seguro_retirar_archivo(uuid, text),
  fn_seguro_archivo_libre(text),
  fn_seguros_tablero(),
  fn_seguro_historial(uuid),
  fn_seguro_archivos(uuid)
to authenticated;
revoke execute on function
  fn_seguro_registrar(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text),
  fn_seguro_corregir(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text, text),
  fn_seguro_marcar_paso(uuid, text, date, text),
  fn_seguro_anular(uuid, text),
  fn_seguro_adjuntar(uuid, text, text, text),
  fn_seguro_retirar_archivo(uuid, text),
  fn_seguro_archivo_libre(text),
  fn_seguros_tablero(),
  fn_seguro_historial(uuid),
  fn_seguro_archivos(uuid)
from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (528, 'las_polizas_de_seguro_de_los_practicantes_entran_al_sistema')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public'
      and table_name in ('polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos')) as tablas_de_3,
  (select count(*) from pg_proc where proname in (
     'fn_seguro_registrar','fn_seguro_corregir','fn_seguro_marcar_paso','fn_seguro_anular',
     'fn_seguro_adjuntar','fn_seguro_retirar_archivo','fn_seguro_archivo_libre',
     'fn_seguro_datos_validos','fn_seguros_tablero','fn_seguro_historial','fn_seguro_archivos')) as funciones_de_11,
  (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'polizas\_seguro\_%') as politicas_storage_de_4,
  (select count(*) from storage.buckets where id = 'polizas-seguro' and public is false) as bucket_privado,
  (select count(*) from pg_class where relname in ('polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos')
      and relrowsecurity) as rls_activa_en_3,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 528) as registro;
