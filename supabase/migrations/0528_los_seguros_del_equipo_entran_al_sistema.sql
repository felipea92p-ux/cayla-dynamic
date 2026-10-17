-- ============================================================================
-- 0528 · los seguros del equipo entran al sistema: en qué está cada colaborador
-- ============================================================================
-- QUÉ PROMETE
--
--   Que Dynamic diga EN QUÉ SEGURO ESTÁ CADA COLABORADOR, y que lo siga diciendo
--   cuando cambie. Hoy no lo dice en ninguna parte: EsSalud se deduce de la
--   planilla, la póliza FOLA de los practicantes (la que reemplazó a EsSalud para
--   ellos el 2026-10-15, 0504) vive en docs/estado.md y en el correo de Felipe, y
--   nada avisa cuando alguien pasa de uno al otro.
--
--   Seis piezas:
--     TIPOS         (seguros_tipos)        el catálogo. FOLA y EsSalud vienen de
--                                          sistema; DO puede AGREGAR más desde la
--                                          pantalla (una EPS, un seguro de vida…).
--     PRINCIPAL     (fn_seguro_tipo_principal)  el seguro principal de cada persona:
--                                          AUTOMÁTICO por su vínculo —practicante →
--                                          FOLA; planilla y prueba → EsSalud;
--                                          honorarios y sin vínculo → ninguno— …
--     ASIGNACIONES  (seguros_asignaciones) … y DO puede CAMBIARLO por persona, con
--                                          fecha y motivo. Queda el historial.
--     PÓLIZAS       (polizas_seguro, sus archivos y su historial)  la póliza de una
--                                          persona: número, vigencia, prima, plan,
--                                          los tres pasos del papeleo (pagada,
--                                          firmada, factura) y los PDF.
--     CAMBIOS       (seguros_cambios)      cada vez que el seguro principal de
--                                          alguien cambia —por vínculo o por DO—
--                                          queda escrito «antes → ahora» con la
--                                          fecha, y deja DOS pendientes: la baja del
--                                          anterior y el alta del nuevo.
--     EL HUECO      (fn_seguros_equipo)    quien tiene como principal un seguro CON
--                                          póliza y no tiene una que cubra HOY. El
--                                          caso caro: un practicante sin ningún
--                                          seguro es infracción por sí solo (Ley
--                                          28518, art. 52.5) y la 0504 quitó EsSalud
--                                          a todos de una vez.
--
--   Es la ETAPA 1: solo Desarrollo Organizacional ve y escribe. La etapa 2 —«Mi
--   seguro» en Lo mío— agrega después la lectura de cada persona sobre SU seguro.
--
-- LO QUE DECIDIÓ FELIPE (2026-10-17, en sus palabras)
--
--   «El seguro actual que tienen los empleados déjalos como está» y «modificar todo
--   el módulo para que sea seguro general y por cada colaborador que cambie, ya que
--   ahí recién se ve en qué están; los practicantes en FOLA y los otros
--   colaboradores pueden estar ubicados en otro tipo». Y con preguntas:
--     · Los tipos que tienen los demás «no se sabe con exactitud»: se revisó (en el
--       repositorio solo consta EsSalud) y, donde no haya uno, DO agrega el tipo.
--     · La asignación es automática por vínculo y DO la cambia por persona.
--     · Cuando alguien cambia, el módulo lo muestra y deja dos pendientes.
--
-- QUÉ ASUME
--
--   · `fn_es_admin_o_lider()` es «DO» (0078); `fn_persona_actual_id()` y
--     `fn_hoy_lima()` existen. El vínculo es `personas.tipo_vinculo` (los cinco
--     valores del CHECK de la 0322), la persona está activa si `estado = 'activo'` y
--     una cuenta de servicio no es una persona (0490).
--   · Una póliza cubre desde `vigente_desde` y hasta `vigente_hasta` EXCLUSIVO: el
--     papel de FOLA dice «01/10/2026 al 01/01/2027, 92 días, a las 12 M», y de
--     octubre 1 a enero 1 son justo 92 días. El 1/1 ya cuenta como sin cubrir (el
--     lado cauteloso: equivocarse es avisar un día antes). Igual la asignación.
--   · Que el navegador sube el archivo al bucket `polizas-seguro` ANTES de llamar a
--     `fn_seguro_adjuntar` (el molde de la 0503).
--   · Que `fn_set_tipo_vinculo` (0504) y `fn_cesar_persona` son las únicas que
--     cambian `personas.tipo_vinculo` (medido en el Postgres local el 2026-10-17).
--     El disparador de abajo escucha la COLUMNA, no esas funciones: no las toca.
--
-- POR QUÉ TABLAS NUEVAS Y NO LAS QUE YA EXISTEN
--
--   · `archivo_empresa` (0503) es papel de la EMPRESA y no tiene persona; el PDF de
--     una póliza lleva DNI y fecha de nacimiento del asegurado.
--   · `documentos_firmados` (0157) solo admite ruta, política y bono.
--   · `correcciones_auditoria` NO se usa para el rastro: sus filas las leen la
--     ficha, Lo mío, Correcciones y el CSV, y cada pantalla tendría que aprender a
--     rotular «seguro.pagada_el». La póliza lleva su historial
--     (`polizas_seguro_eventos`) y los cambios de seguro los suyos (`seguros_cambios`).
--
-- PRINCIPAL Y COMPLEMENTARIO
--
--   Un tipo es PRINCIPAL (el seguro de salud de la persona: uno a la vez; FOLA,
--   EsSalud, un SIS…) o COMPLEMENTARIO (va además: una EPS, un seguro de vida). Sin
--   esa distinción, agregar «Vida Ley» y asignárselo a alguien lo sacaría de EsSalud.
--   Los complementarios no se «asignan»: tener una póliza vigente de ese tipo ES
--   estar en él, y por eso exigen póliza. Solo los principales tienen vínculos
--   automáticos y solo ellos pueden dar un hueco.
--
-- AL LEERSE, NO AL ESCRIBIRSE: LO QUE YA NO HAY QUE HACER
--
--   Un pendiente de un cambio se calcula al leer, contra el estado de hoy, para que
--   no haya falsos positivos (CLAUDE.md: el peor error es pedirle algo a alguien por
--   algo que ya pasó):
--     · la BAJA de un seguro con póliza deja de pedirse sola cuando ya no queda
--       ninguna póliza vigente de ese tipo (ya terminó o se corrigió su fecha);
--     · el ALTA de un seguro con póliza deja de pedirse sola cuando se registra una;
--     · si la persona volvió al seguro del que salió, o cambió otra vez, el paso
--       viejo ya no aplica;
--     · una persona cesada no pide pasos (su baja la lleva el cese).
--   EsSalud no tiene póliza: sus pasos los marca DO a mano («ya se lo confirmé al
--   contador»), con la fecha.
--
-- ESTADOS QUE NUNCA DEBEN EXISTIR (y qué los hace imposibles)
--
--   · una póliza que termina antes de empezar ................ check
--   · dos pólizas vivas del MISMO tipo de la misma persona que se pisan .. la función
--       (rango `[desde, hasta)`: una que empieza el día que otra termina no se pisa,
--       que es como se renueva)
--   · el mismo número con la misma vigencia dos veces .......... índice único parcial
--   · una póliza de un seguro que no tiene póliza (EsSalud) .... la función
--   · una póliza de un seguro principal que la persona no tiene .. la función: se le
--       cambia el seguro primero (no se registra FOLA a alguien de planilla)
--   · un complementario sin póliza o con vínculos automáticos .. check
--   · dos asignaciones de la misma persona que se pisan ........ la función + índice
--       único de la abierta
--   · un cambio de seguro sin cambio, o sin ninguno de los dos extremos .. check
--   · un archivo con nombres o DNI en la ruta, o que dos filas usan .. check + índice
--   · una anulación, un retiro o un archivo sin motivo ......... check
--   · alguien sin DO leyendo un seguro o su PDF ................ RLS + política de Storage
--   · escribir cualquiera de estas tablas con la sesión de un usuario .. sin política
--       Y sin privilegio (molde de la 0507/0509: aquí nadie legítimo escribe directo)
--   · que un fallo del registro de cambios frene un cambio de vínculo .. el disparador
--       atrapa su propio error y solo avisa (un warning): el seguro es secundario
--       frente a la planilla, que no puede quedar bloqueada por esto
--
-- LO QUE DECIDÍ, Y LO QUE DESCARTÉ
--
--   DECIDÍ:    Solo ALERTA. Nada de aquí cambia lo que cobra o paga nadie ni toca
--              `fn_planilla_calcular_nucleo`: la prima se paga a la aseguradora y
--              EsSalud lo sigue declarando el contador. EsSalud aparece como un tipo
--              «por planilla» para que cada persona de planilla tenga su fila; no se
--              le cambia nada.
--   DECIDÍ:    `plan` y los dos beneficios máximos son OPCIONALES y quedan «sin
--              confirmar» mientras estén vacíos. La casilla «Beneficio máximo
--              anual» viene VACÍA en las condiciones particulares de las cuatro
--              pólizas FOLA y el plan no figura en ningún papel: lo confirma el
--              corredor (docs/estado.md). `renueva_sola` es `boolean` con null =
--              «sin confirmar» (la tabla de beneficios dice «Renovación automática:
--              Aplica» y el estado asumía lo contrario).
--   DECIDÍ:    La clave de FOLA sigue siendo `salud_practicantes`, el valor que
--              `polizas_seguro.producto` ya tenía en la primera versión de esta
--              migración: quien escriba código sobre esa columna no se entera.
--   DESCARTÉ:  Materializar el seguro de TODAS las personas en una tabla que un
--              disparador mantiene al día: cualquier desfase entre esa tabla y el
--              vínculo sería un seguro mal dicho. El principal AUTOMÁTICO se calcula
--              al leer; solo lo que DO cambia a mano se guarda.
--   DESCARTÉ:  Un `daterange` con `exclude using gist` para los cruces: pide la
--              extensión `btree_gist`, que en producción se pega a mano y se olvida.
--              Las funciones lo comprueban con la fila de la persona bloqueada.
--   DESCARTÉ:  Reescribir `fn_set_tipo_vinculo`: el cambio de vínculo se escucha con
--              un disparador sobre la columna, sin copiar el cuerpo de una función
--              de planilla (CLAUDE.md: «nunca copies el cuerpo sin preguntar cuál es
--              la vigente»; aquí no hay cuerpo que copiar). Ya hay otro disparador
--              `AFTER UPDATE` sobre `personas` (`trg_educacion_cerrar_al_cesar`).
--
-- QUÉ NO HACE
--
--   · No toca la planilla, ni `aporte_essalud`, ni ninguna columna de pago. No
--     escribe en `personas`: solo lee su vínculo y su estado.
--   · No avisa a la persona ni le muestra nada: es la etapa 2.
--   · No compara el beneficio máximo con las 14 y 30 subvenciones que el convenio
--     promete (Ley 28518, art. 42.8): para eso hace falta la subvención pactada de
--     cada quien (`asignaciones_salario`), que esta migración no lee.
--   · No habla con Pacífico ni con el contador: que una póliza exista o que un alta
--     se haya confirmado lo dice quien lo marca.
--   · Ninguna función existente se reescribe → no hay md5 de partida. Lo único que
--     toca algo existente es el disparador nuevo sobre `personas`.
--
-- SE ROMPE SI
--
--   · Una pantalla futura escribe estas tablas con la sesión del usuario. Dará
--     «permission denied for table …»: lo correcto es una función `SECURITY
--     DEFINER`. La prueba 422 exige las dos cosas (sin política Y sin privilegio).
--   · Se agrega un sexto valor a `personas.tipo_vinculo` (CHECK de la 0322): no
--     tendrá seguro automático hasta que alguien lo ponga en `aplica_a_vinculos` de
--     un tipo. Aparecerá como «sin seguro», que es lo honesto.
--   · Dos tipos principales reclaman el mismo vínculo: gana el de clave menor, sin
--     avisar. Hoy solo los de sistema tienen vínculos y no se editan desde la pantalla.
--
-- ANTES DE PEGAR — UNA CONSULTA DE SOLO LECTURA A PRODUCCIÓN (SQL Editor)
--   Esperado: ninguna tabla, función ni disparador con estos nombres, y las tres de
--   apoyo presentes. Si `tablas_que_ya_existen` no sale 0, PARAR: otra sesión la creó.
--
--   select
--     (select count(*) from information_schema.tables
--       where table_schema = 'public'
--         and table_name in ('seguros_tipos','seguros_asignaciones','seguros_cambios',
--                            'polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos'))
--                                                            as tablas_que_ya_existen,
--     (select count(*) from pg_proc where proname like 'fn\_seguro%' or proname like 'fn\_seguros%'
--         or proname = 'fn_trg_seguros_cambio_de_vinculo')    as funciones_que_ya_existen,
--     (select count(*) from pg_trigger where tgname = 'trg_seguros_cambio_de_vinculo')
--                                                            as disparadores_que_ya_existen,
--     (select count(*) from pg_proc where proname in
--       ('fn_es_admin_o_lider','fn_persona_actual_id','fn_hoy_lima'))
--                                                            as apoyo_de_3,
--     (select count(*) from storage.buckets where id = 'polizas-seguro') as bucket_que_ya_existe,
--     (select string_agg(numero || ' · ' || nombre, ' | ' order by numero) from migraciones_aplicadas
--       where numero between 524 and 532)                    as registro_524_a_532;
--
-- CÓMO SE REVIERTE (en ESTE orden: las políticas de Storage dependen de
-- `fn_seguro_archivo_libre`, así que van antes que las funciones; el disparador,
-- antes que su función; y las tablas, de las que apuntan hacia las que reciben —
-- se probó corriéndola de verdad el 2026-10-17)
--   begin;
--   select set_config('storage.allow_delete_query', 'true', true);
--   drop trigger if exists trg_seguros_cambio_de_vinculo on personas;
--   drop policy if exists polizas_seguro_insert on storage.objects;
--   drop policy if exists polizas_seguro_select on storage.objects;
--   drop policy if exists polizas_seguro_update on storage.objects;
--   drop policy if exists polizas_seguro_delete on storage.objects;
--   drop function if exists
--     fn_trg_seguros_cambio_de_vinculo(), fn_seguro_tipo_por_vinculo(text), fn_seguro_tipo_principal(uuid, date),
--     fn_seguro_tipo_crear(text, text, boolean, boolean, text, text),
--     fn_seguro_tipo_editar(text, text, text, text, text), fn_seguro_tipo_activar(text, boolean, text),
--     fn_seguro_registrar(uuid, text, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text),
--     fn_seguro_corregir(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text, text),
--     fn_seguro_marcar_paso(uuid, text, date, text), fn_seguro_anular(uuid, text),
--     fn_seguro_adjuntar(uuid, text, text, text), fn_seguro_retirar_archivo(uuid, text),
--     fn_seguro_archivo_libre(text),
--     fn_seguro_datos_validos(text, text, date, date, numeric, date, text, numeric, numeric, text),
--     fn_seguro_asignar(uuid, text, date, text), fn_seguro_volver_al_automatico(uuid, date, text),
--     fn_seguro_cambio_marcar(uuid, text, date, text),
--     fn_seguros_tipos(), fn_seguros_equipo(), fn_seguros_tablero(),
--     fn_seguros_cambios(uuid, boolean), fn_seguro_historial(uuid), fn_seguro_archivos(uuid);
--   drop table seguros_cambios, seguros_asignaciones,
--              polizas_seguro_eventos, polizas_seguro_archivos, polizas_seguro, seguros_tipos;
--   -- Los PDF se borran por la API o el panel de Storage ANTES de correr esto
--   -- (cada borrado quita fila y archivo). Borrar las filas de storage.objects por
--   -- SQL deja los archivos huérfanos en el almacén, y eso no se ve en ninguna lista.
--   delete from storage.objects where bucket_id = 'polizas-seguro';  -- red de seguridad: debería dar 0 filas
--   delete from storage.buckets where id = 'polizas-seguro';
--   delete from migraciones_aplicadas where numero = 528;
--   commit;
--   Nada de planilla, asistencia ni pago lee estas tablas: revertir solo quita la
--   pantalla. Ojo: borrarlas destruye el registro de quién marcó cada paso, el
--   historial de cambios de seguro de cada persona y los PDF de las pólizas.
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

-- ── 2 · Los tipos de seguro (el catálogo) ────────────────────────────────────
-- Lo que DO puede agregar desde la pantalla. La verdad de qué tipos hay vive AQUÍ,
-- no en una lista escrita en el código (CLAUDE.md, regla 3).
create table if not exists seguros_tipos (
  -- Un slug estable: lo usan `polizas_seguro.producto` y las asignaciones. Los dos de
  -- sistema tienen la suya fija; los que agrega DO se arman del nombre.
  clave             text primary key check (clave ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre            text not null check (char_length(btrim(nombre)) between 2 and 80),
  descripcion       text check (descripcion is null or char_length(descripcion) <= 500),
  -- true: el seguro PRINCIPAL de la persona (uno a la vez). false: va además.
  principal         boolean not null,
  -- true: se registra una póliza (número, vigencia, prima, PDF). false: «por
  -- planilla» (EsSalud): no hay póliza que registrar.
  con_poliza        boolean not null,
  -- Qué vínculos caen SOLOS en este tipo. Solo los principales. Lo escribe esta
  -- migración para los de sistema; la pantalla no lo edita (decidir a qué seguro va
  -- un vínculo es una decisión legal, no un campo de un formulario).
  aplica_a_vinculos text[] not null default '{}',
  -- Qué dice el pendiente cuando alguien entra o sale de este tipo.
  texto_alta        text check (texto_alta is null or char_length(btrim(texto_alta)) between 3 and 200),
  texto_baja        text check (texto_baja is null or char_length(btrim(texto_baja)) between 3 and 200),
  de_sistema        boolean not null default false,
  activo            boolean not null default true,
  creado_por        uuid references personas(id),
  creado_at         timestamptz not null default now(),
  archivado_at      timestamptz,
  archivado_por     uuid references personas(id),
  archivado_motivo  text,
  constraint seguro_tipo_complementario_con_poliza
    check (principal or (con_poliza and aplica_a_vinculos = '{}')),
  constraint seguro_tipo_archivo_completo check (
    (activo and archivado_at is null and archivado_por is null and archivado_motivo is null)
    or (not activo and archivado_at is not null and archivado_por is not null
        and char_length(btrim(archivado_motivo)) >= 5)
  ),
  constraint seguro_tipo_sistema_siempre_activo check (not de_sistema or activo)
);

comment on table seguros_tipos is
  'Catálogo de tipos de seguro. FOLA y EsSalud son de sistema; DO agrega más. Escritura solo por fn_seguro_tipo_*; nada se borra: un tipo se archiva con motivo.';
comment on column seguros_tipos.principal is
  'true = el seguro principal de la persona (uno a la vez, automático por vínculo o asignado por DO). false = complementario: va además y exige póliza.';
comment on column seguros_tipos.aplica_a_vinculos is
  'Vínculos de personas.tipo_vinculo que caen solos en este tipo. Solo tipos principales.';

create unique index if not exists idx_seguros_tipos_nombre on seguros_tipos (lower(btrim(nombre)));

-- Los dos que ya existen en la vida real. `do nothing`: repegar no pisa lo que DO
-- haya editado (la descripción y los textos de los pendientes se editan desde la pantalla).
insert into seguros_tipos
  (clave, nombre, descripcion, principal, con_poliza, aplica_a_vinculos, texto_alta, texto_baja, de_sistema)
values
  ('salud_practicantes', 'FOLA',
   'Póliza individual de Pacífico para los practicantes («Seguro de Salud Practicantes», Ley 28518 art. 42.8). Reemplazó a EsSalud para ellos el 15/10/2026.',
   true, true, array['practicante'],
   'Registrar su póliza FOLA y avisarle al corredor',
   'Pedirle a la aseguradora la baja de su póliza FOLA',
   true),
  ('essalud', 'EsSalud',
   'Seguro social de salud. Se paga con la planilla y lo declara el contador: Dynamic solo lo muestra.',
   true, false, array['planilla', 'prueba'],
   'Confirmar con el contador el alta en EsSalud',
   'Confirmar con el contador la baja en EsSalud',
   true)
on conflict (clave) do nothing;


-- ── 3 · Las tablas ───────────────────────────────────────────────────────────
create table if not exists polizas_seguro (
  id                  uuid primary key default gen_random_uuid(),
  persona_id          uuid not null references personas(id),
  -- El tipo de seguro (`seguros_tipos.clave`). Solo uno con póliza: lo exige la función.
  producto            text not null references seguros_tipos(clave),
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
  'Una póliza de seguro por persona y por tipo (FOLA, una EPS, un seguro de vida…). Solo DO. Escritura solo por las funciones fn_seguro_*; nada se borra: una póliza registrada por error se anula con motivo.';
comment on column polizas_seguro.vigente_hasta is
  'EXCLUSIVO: la póliza cubre hasta las 12 M de ese día, así que ese día ya cuenta como sin cubrir.';
comment on column polizas_seguro.plan is
  'Plan de la póliza. Opcional: el papel no lo dice y lo confirma el corredor; vacío = sin confirmar.';
comment on column polizas_seguro.renueva_sola is
  'null = sin confirmar. La tabla de beneficios de FOLA dice «Renovación automática: Aplica».';

-- El mismo número con la misma vigencia, una sola vez entre las vivas. La
-- renovación automática puede conservar el número: cambia la vigencia.
create unique index if not exists idx_polizas_seguro_numero_vigencia
  on polizas_seguro (aseguradora, numero_poliza, vigente_desde) where anulada_at is null;
create index if not exists idx_polizas_seguro_persona on polizas_seguro (persona_id, vigente_desde desc);
create index if not exists idx_polizas_seguro_producto on polizas_seguro (producto);


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


-- Lo que DO cambia a mano: «desde esta fecha, el seguro PRINCIPAL de esta persona
-- es este tipo». Manda sobre el automático por vínculo mientras rija.
create table if not exists seguros_asignaciones (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id),
  tipo           text not null references seguros_tipos(clave),
  desde          date not null,
  -- EXCLUSIVO, como la póliza. null = sin fin. `hasta = desde` es una asignación
  -- vacía (se asignó y se deshizo el mismo día).
  hasta          date,
  motivo         text not null check (char_length(btrim(motivo)) >= 5),
  creada_por     uuid not null references personas(id),
  creada_at      timestamptz not null default clock_timestamp(),
  cerrada_por    uuid references personas(id),
  cerrada_motivo text,
  constraint asignacion_no_termina_antes check (hasta is null or hasta >= desde),
  constraint asignacion_cierre_completo check (
    (hasta is null and cerrada_por is null and cerrada_motivo is null)
    or (hasta is not null and cerrada_por is not null and char_length(btrim(cerrada_motivo)) >= 5)
  )
);

comment on table seguros_asignaciones is
  'Cambios a mano del seguro principal de una persona (con fecha y motivo). Sin fila, manda el automático por vínculo. Solo DO; escritura solo por fn_seguro_asignar y fn_seguro_volver_al_automatico.';

-- Una sola asignación abierta por persona: sin esto, dos DO asignando a la vez
-- dejarían a alguien en dos seguros principales.
create unique index if not exists idx_seguros_asignaciones_abierta
  on seguros_asignaciones (persona_id) where hasta is null;
create index if not exists idx_seguros_asignaciones_persona on seguros_asignaciones (persona_id, desde desc);


-- Cada vez que el seguro principal de alguien cambia. Lo escriben el disparador de
-- `personas` (cambio de vínculo) y las funciones de asignación (cambio de DO).
create table if not exists seguros_cambios (
  id              uuid primary key default gen_random_uuid(),
  persona_id      uuid not null references personas(id),
  -- null en `de_tipo`: no tenía seguro principal. null en `a_tipo`: se queda sin él.
  de_tipo         text references seguros_tipos(clave),
  a_tipo          text references seguros_tipos(clave),
  fecha           date not null,
  origen          text not null check (origen in ('vinculo', 'asignacion')),
  -- Solo `origen = 'vinculo'`: los dos vínculos tal cual están en `personas.tipo_vinculo`.
  vinculo_antes   text,
  vinculo_despues text,
  -- Solo `origen = 'asignacion'`: el motivo que escribió DO.
  detalle         text check (detalle is null or char_length(detalle) <= 500),
  -- Los dos pasos. Solo cuentan los que la lectura no cierra sola: ver la cabecera.
  baja_hecha_el   date,
  baja_hecha_por  uuid references personas(id),
  baja_nota       text,
  alta_hecha_el   date,
  alta_hecha_por  uuid references personas(id),
  alta_nota       text,
  creado_at       timestamptz not null default clock_timestamp(),
  constraint cambio_es_un_cambio check (de_tipo is distinct from a_tipo),
  constraint cambio_tiene_un_extremo check (de_tipo is not null or a_tipo is not null),
  constraint cambio_baja_completa check ((baja_hecha_el is null) = (baja_hecha_por is null)),
  constraint cambio_alta_completa check ((alta_hecha_el is null) = (alta_hecha_por is null))
);

comment on table seguros_cambios is
  'Cada cambio del seguro principal de una persona (por vínculo o por DO), con sus dos pasos: baja del anterior y alta del nuevo. Solo lo escriben el disparador de personas y las funciones fn_seguro_*.';

create index if not exists idx_seguros_cambios_persona on seguros_cambios (persona_id, fecha desc);


-- ── 4 · Permisos y RLS ───────────────────────────────────────────────────────
-- Leer: solo DO. Escribir: nadie directo; todo por las funciones de abajo. Se
-- quita lo que Supabase concede por defecto (incluye escribir y `truncate`).
alter table seguros_tipos           enable row level security;
alter table polizas_seguro          enable row level security;
alter table polizas_seguro_archivos enable row level security;
alter table polizas_seguro_eventos  enable row level security;
alter table seguros_asignaciones    enable row level security;
alter table seguros_cambios         enable row level security;

drop policy if exists seguros_tipos_select_do on seguros_tipos;
create policy seguros_tipos_select_do on seguros_tipos
  for select to authenticated using (fn_es_admin_o_lider() is true);
drop policy if exists polizas_seguro_select_do on polizas_seguro;
create policy polizas_seguro_select_do on polizas_seguro
  for select to authenticated using (fn_es_admin_o_lider() is true);
drop policy if exists polizas_seguro_archivos_select_do on polizas_seguro_archivos;
create policy polizas_seguro_archivos_select_do on polizas_seguro_archivos
  for select to authenticated using (fn_es_admin_o_lider() is true);
drop policy if exists polizas_seguro_eventos_select_do on polizas_seguro_eventos;
create policy polizas_seguro_eventos_select_do on polizas_seguro_eventos
  for select to authenticated using (fn_es_admin_o_lider() is true);
drop policy if exists seguros_asignaciones_select_do on seguros_asignaciones;
create policy seguros_asignaciones_select_do on seguros_asignaciones
  for select to authenticated using (fn_es_admin_o_lider() is true);
drop policy if exists seguros_cambios_select_do on seguros_cambios;
create policy seguros_cambios_select_do on seguros_cambios
  for select to authenticated using (fn_es_admin_o_lider() is true);

revoke all on seguros_tipos, polizas_seguro, polizas_seguro_archivos, polizas_seguro_eventos,
              seguros_asignaciones, seguros_cambios from anon, authenticated, public;
grant select on seguros_tipos, polizas_seguro, polizas_seguro_archivos, polizas_seguro_eventos,
                seguros_asignaciones, seguros_cambios to authenticated;

-- ── 5 · Storage ──────────────────────────────────────────────────────────────
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

-- ── 6 · Qué seguro principal tiene cada persona ──────────────────────────────
-- Dos funciones de apoyo, y la regla de «en qué seguro está» vive en ellas y en
-- ninguna otra parte. Nadie las llama desde fuera (se les quita el EXECUTE): las
-- usan las demás funciones y el disparador, que corren como su dueña.

-- El tipo principal que cae SOLO en un vínculo, o null si ninguno lo reclama.
create or replace function fn_seguro_tipo_por_vinculo(p_vinculo text)
returns text
language sql stable security definer set search_path = public
as $fn$
  select t.clave
    from seguros_tipos t
   where t.principal and t.activo and p_vinculo = any(t.aplica_a_vinculos)
   order by t.clave
   limit 1;
$fn$;

-- El seguro PRINCIPAL de una persona en una fecha: la asignación de DO que rija ese
-- día; si no hay, el automático por su vínculo; si tampoco, null (honorarios y sin
-- vínculo). El automático usa el vínculo de HOY: no sabe cuál tenía la persona en
-- una fecha pasada, así que para el automático solo es fiable preguntar por hoy.
create or replace function fn_seguro_tipo_principal(p_persona_id uuid, p_fecha date)
returns text
language sql stable security definer set search_path = public
as $fn$
  select coalesce(
    (select a.tipo
       from seguros_asignaciones a
      where a.persona_id = p_persona_id
        and a.desde <= p_fecha
        and (a.hasta is null or p_fecha < a.hasta)
      order by a.desde desc, a.id desc
      limit 1),
    (select fn_seguro_tipo_por_vinculo(p.tipo_vinculo)
       from personas p
      where p.id = p_persona_id)
  );
$fn$;

-- ── 7 · Las reglas de los datos, escritas UNA vez ────────────────────────────
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

-- ── 8 · Tipos de seguro: agregar, editar y archivar ──────────────────────────
-- DO agrega los que falten (la lista de lo que tienen los demás colaboradores «no se
-- sabe con exactitud», dijo Felipe). Un tipo nuevo nace SIN vínculos automáticos: a
-- quién le corresponde se decide persona por persona (asignación, si es principal)
-- o registrándole su póliza (si es complementario).
create or replace function fn_seguro_tipo_crear(
  p_nombre      text,
  p_descripcion text,
  p_principal   boolean,
  p_con_poliza  boolean,
  p_texto_alta  text,
  p_texto_baja  text
)
returns text
language plpgsql security definer set search_path = public
as $fn$
declare
  v_base  text;
  v_clave text;
  v_n     integer := 1;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede agregar tipos de seguro.';
  end if;
  if fn_persona_actual_id() is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_nombre is null or char_length(btrim(p_nombre)) < 2 then
    raise exception 'Escribe cómo se llama el seguro (al menos 2 letras).';
  end if;
  if char_length(btrim(p_nombre)) > 80 then
    raise exception 'El nombre del seguro es demasiado largo (máximo 80 letras).';
  end if;
  if p_principal is null or p_con_poliza is null then
    raise exception 'Falta decir si es el seguro principal y si lleva póliza.';
  end if;
  if not p_principal and not p_con_poliza then
    raise exception 'Un seguro que va además del principal necesita póliza: sin ella no hay nada que registrar.';
  end if;
  if p_descripcion is not null and char_length(p_descripcion) > 500 then
    raise exception 'La descripción es demasiado larga (máximo 500 letras).';
  end if;

  -- La clave sale del nombre: minúsculas, sin tildes, con guiones bajos. Si ya existe
  -- se le agrega un número; el nombre repetido lo frena el índice único de abajo.
  v_base := regexp_replace(translate(lower(btrim(p_nombre)), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', '_', 'g');
  v_base := btrim(v_base, '_');
  if v_base = '' then
    raise exception 'El nombre del seguro tiene que llevar letras o números.';
  end if;
  if v_base !~ '^[a-z]' then
    v_base := 'x_' || v_base;
  end if;
  v_base  := left(v_base, 36);
  v_clave := v_base;
  while exists (select 1 from seguros_tipos t where t.clave = v_clave) loop
    v_n := v_n + 1;
    v_clave := v_base || '_' || v_n;
  end loop;

  begin
    insert into seguros_tipos
      (clave, nombre, descripcion, principal, con_poliza, texto_alta, texto_baja, creado_por)
    values
      (v_clave, btrim(p_nombre), nullif(btrim(p_descripcion), ''), p_principal, p_con_poliza,
       nullif(btrim(p_texto_alta), ''), nullif(btrim(p_texto_baja), ''), fn_persona_actual_id());
  exception when unique_violation then
    raise exception 'Ya hay un seguro con ese nombre.';
  end;

  return v_clave;
end;
$fn$;


-- Cambia el nombre, la descripción y lo que dicen los pendientes. NO cambia si es
-- principal, si lleva póliza ni a qué vínculos cae: eso cambia lo que significa cada
-- fila que ya existe. Un tipo de sistema conserva su nombre.
create or replace function fn_seguro_tipo_editar(
  p_clave       text,
  p_nombre      text,
  p_descripcion text,
  p_texto_alta  text,
  p_texto_baja  text
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_t seguros_tipos%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede editar tipos de seguro.';
  end if;
  if fn_persona_actual_id() is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;

  select * into v_t from seguros_tipos t where t.clave = p_clave for update;
  if not found then
    raise exception 'Ese tipo de seguro no existe.';
  end if;
  if p_nombre is null or char_length(btrim(p_nombre)) < 2 or char_length(btrim(p_nombre)) > 80 then
    raise exception 'Escribe cómo se llama el seguro (entre 2 y 80 letras).';
  end if;
  if v_t.de_sistema and btrim(p_nombre) is distinct from v_t.nombre then
    raise exception 'Un seguro de sistema conserva su nombre.';
  end if;
  if p_descripcion is not null and char_length(p_descripcion) > 500 then
    raise exception 'La descripción es demasiado larga (máximo 500 letras).';
  end if;

  begin
    update seguros_tipos
       set nombre = btrim(p_nombre),
           descripcion = nullif(btrim(p_descripcion), ''),
           texto_alta = nullif(btrim(p_texto_alta), ''),
           texto_baja = nullif(btrim(p_texto_baja), '')
     where clave = p_clave;
  exception when unique_violation then
    raise exception 'Ya hay un seguro con ese nombre.';
  end;
end;
$fn$;


-- Archivar un tipo que ya no se usa (o volver a activarlo). No se borra: sus pólizas,
-- sus asignaciones y sus cambios siguen contando lo que pasó. Los de sistema no se archivan.
create or replace function fn_seguro_tipo_activar(p_clave text, p_activo boolean, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_hoy   date := fn_hoy_lima();
  v_t     seguros_tipos%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede archivar tipos de seguro.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_activo is null then
    raise exception 'Falta decir si se archiva o se vuelve a activar.';
  end if;

  select * into v_t from seguros_tipos t where t.clave = p_clave for update;
  if not found then
    raise exception 'Ese tipo de seguro no existe.';
  end if;
  if v_t.de_sistema then
    raise exception 'Los seguros de sistema no se archivan.';
  end if;
  if v_t.activo = p_activo then
    raise exception '%', case when p_activo then 'Ese tipo de seguro ya está activo.' else 'Ese tipo de seguro ya está archivado.' end;
  end if;

  if not p_activo then
    if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
      raise exception 'Escribe el motivo (al menos 5 letras): queda anotado junto al tipo.';
    end if;
    if exists (select 1 from polizas_seguro z
                where z.producto = p_clave and z.anulada_at is null and z.vigente_hasta > v_hoy) then
      raise exception 'Todavía hay pólizas vigentes de ese seguro: no se archiva.';
    end if;
    if exists (select 1 from seguros_asignaciones a
                where a.tipo = p_clave and (a.hasta is null or a.hasta > v_hoy)) then
      raise exception 'Todavía hay colaboradores asignados a ese seguro: vuélvelos al automático antes de archivarlo.';
    end if;
    update seguros_tipos
       set activo = false, archivado_at = now(), archivado_por = v_quien, archivado_motivo = btrim(p_motivo)
     where clave = p_clave;
  else
    update seguros_tipos
       set activo = true, archivado_at = null, archivado_por = null, archivado_motivo = null
     where clave = p_clave;
  end if;
end;
$fn$;

-- ── 9 · Registrar una póliza ─────────────────────────────────────────────────
-- Devuelve el id de la póliza. Todo en una transacción.
--   · El tipo tiene que existir, estar activo y llevar póliza (EsSalud no).
--   · Si el tipo es PRINCIPAL, tiene que ser el que la persona tiene HOY: no se le
--     registra FOLA a alguien de planilla. Si debe cambiar de seguro, se le cambia
--     primero (por su vínculo o con una asignación). Los complementarios no piden eso:
--     se registran a quien los tenga.
create or replace function fn_seguro_registrar(
  p_persona_id           uuid,
  p_producto             text,
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
  v_quien  uuid := fn_persona_actual_id();
  v_p      personas%rowtype;
  v_t      seguros_tipos%rowtype;
  v_actual text;
  v_id     uuid;
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
  if v_p.estado is distinct from 'activo' then
    raise exception 'Esa persona está inactiva.';
  end if;

  select * into v_t from seguros_tipos t where t.clave = p_producto;
  if not found then
    raise exception 'Ese tipo de seguro no existe.';
  end if;
  if not v_t.activo then
    raise exception 'Ese tipo de seguro está archivado.';
  end if;
  if not v_t.con_poliza then
    raise exception 'Ese seguro es «por planilla»: no tiene póliza que registrar.';
  end if;
  if v_t.principal then
    v_actual := fn_seguro_tipo_principal(p_persona_id, fn_hoy_lima());
    if v_actual is distinct from p_producto then
      raise exception 'El seguro principal de esa persona hoy es %: no se le registra una póliza de %. Si debe cambiar, cámbiale el seguro primero.',
        coalesce((select t.nombre from seguros_tipos t where t.clave = v_actual), 'ninguno'), v_t.nombre;
    end if;
  end if;

  perform fn_seguro_datos_validos(p_aseguradora, p_numero_poliza, p_vigente_desde, p_vigente_hasta,
                                  p_prima_total, p_prima_vence_el, p_plan,
                                  p_beneficio_enfermedad, p_beneficio_accidente, p_nota);

  if exists (select 1 from polizas_seguro z
              where z.persona_id = p_persona_id and z.producto = p_producto and z.anulada_at is null
                and daterange(z.vigente_desde, z.vigente_hasta) && daterange(p_vigente_desde, p_vigente_hasta)) then
    raise exception 'Esa persona ya tiene una póliza de % que se cruza con esas fechas. Si la anterior estaba mal, anúlala primero.', v_t.nombre;
  end if;

  begin
    insert into polizas_seguro
      (persona_id, producto, aseguradora, numero_poliza, vigente_desde, vigente_hasta, prima_total, prima_vence_el,
       plan, beneficio_enfermedad, beneficio_accidente, renueva_sola, nota, creada_por)
    values
      (p_persona_id, p_producto, btrim(p_aseguradora), btrim(p_numero_poliza), p_vigente_desde, p_vigente_hasta,
       p_prima_total, p_prima_vence_el, nullif(btrim(p_plan), ''), p_beneficio_enfermedad,
       p_beneficio_accidente, p_renueva_sola, nullif(btrim(p_nota), ''), v_quien)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya hay una póliza viva con ese número y esa fecha de inicio.';
  end;

  insert into polizas_seguro_eventos (poliza_id, evento, detalle, hecho_por)
  values (v_id, 'registrada',
          format('%s · póliza %s, del %s al %s', v_t.nombre, btrim(p_numero_poliza),
                 to_char(p_vigente_desde, 'DD/MM/YYYY'), to_char(p_vigente_hasta, 'DD/MM/YYYY')),
          v_quien);

  return v_id;
end;
$fn$;

-- ── 10 · Corregir los datos de una póliza ─────────────────────────────────────
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
              where z.persona_id = v_a.persona_id and z.producto = v_a.producto
                and z.anulada_at is null and z.id <> p_id
                and daterange(z.vigente_desde, z.vigente_hasta) && daterange(p_vigente_desde, p_vigente_hasta)) then
    raise exception 'Esas fechas se cruzan con otra póliza del mismo seguro de esa persona.';
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

-- ── 11 · Marcar un paso del papeleo ───────────────────────────────────────────
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

-- ── 12 · Anular una póliza ────────────────────────────────────────────────────
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

-- ── 13 · Adjuntar y retirar archivos ─────────────────────────────────────────
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

-- ── 14 · Cambiar el seguro principal de una persona ──────────────────────────
-- «Automático por vínculo; DO lo cambia por persona» (Felipe). Cambiarlo es crear una
-- asignación: desde esta fecha, el seguro principal de esta persona es este tipo. La
-- anterior, si había una abierta, termina donde empieza esta. Y si con eso el seguro de
-- la persona cambia de verdad, queda un cambio con sus dos pasos.
create or replace function fn_seguro_asignar(
  p_persona_id uuid,
  p_tipo       text,
  p_desde      date,
  p_motivo     text
)
returns uuid
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien   uuid := fn_persona_actual_id();
  v_hoy     date := fn_hoy_lima();
  v_p       personas%rowtype;
  v_t       seguros_tipos%rowtype;
  v_abierta seguros_asignaciones%rowtype;
  v_antes   text;
  v_despues text;
  v_id      uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede cambiar el seguro de una persona.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado en el historial de su seguro.';
  end if;
  if p_desde is null then
    raise exception 'Falta la fecha desde la que rige.';
  end if;
  if p_desde > v_hoy then
    raise exception 'La fecha no puede ser posterior a hoy.';
  end if;

  -- La fila de la persona se bloquea: dos DO cambiándole el seguro a la vez se ordenan.
  select * into v_p from personas p where p.id = p_persona_id for update;
  if not found then
    raise exception 'Esa persona no existe.';
  end if;
  if v_p.estado is distinct from 'activo' then
    raise exception 'Esa persona está inactiva.';
  end if;

  select * into v_t from seguros_tipos t where t.clave = p_tipo;
  if not found then
    raise exception 'Ese tipo de seguro no existe.';
  end if;
  if not v_t.activo then
    raise exception 'Ese tipo de seguro está archivado.';
  end if;
  if not v_t.principal then
    raise exception 'Ese seguro va además del principal: no se asigna, se le registra su póliza.';
  end if;

  -- Lo que le corresponde por su vínculo no se «asigna»: se vuelve al automático. Si se
  -- asignara, la persona quedaría fija en ese tipo y dejaría de seguir a su vínculo.
  if fn_seguro_tipo_por_vinculo(v_p.tipo_vinculo) is not distinct from p_tipo then
    raise exception 'Eso es lo que le corresponde por su vínculo: usa «volver al automático».';
  end if;

  v_antes := fn_seguro_tipo_principal(p_persona_id, v_hoy);
  if v_antes is not distinct from p_tipo then
    raise exception 'Esa persona ya está en ese seguro.';
  end if;

  -- La asignación abierta termina donde empieza esta.
  select * into v_abierta from seguros_asignaciones a
   where a.persona_id = p_persona_id and a.hasta is null for update;
  if found then
    if p_desde <= v_abierta.desde then
      raise exception 'Ya tiene una asignación desde el %: usa una fecha posterior, o vuélvela al automático primero.',
        to_char(v_abierta.desde, 'DD/MM/YYYY');
    end if;
    update seguros_asignaciones
       set hasta = p_desde, cerrada_por = v_quien, cerrada_motivo = 'Reemplazada por otra asignación'
     where id = v_abierta.id;
  end if;

  if exists (select 1 from seguros_asignaciones a where a.persona_id = p_persona_id and a.hasta > p_desde) then
    raise exception 'Esa fecha se cruza con una asignación anterior de la misma persona.';
  end if;

  insert into seguros_asignaciones (persona_id, tipo, desde, motivo, creada_por)
  values (p_persona_id, p_tipo, p_desde, btrim(p_motivo), v_quien)
  returning id into v_id;

  v_despues := fn_seguro_tipo_principal(p_persona_id, v_hoy);
  if v_antes is distinct from v_despues then
    insert into seguros_cambios (persona_id, de_tipo, a_tipo, fecha, origen, detalle)
    values (p_persona_id, v_antes, v_despues, v_hoy, 'asignacion', btrim(p_motivo));
  end if;

  return v_id;
end;
$fn$;


-- Termina una asignación: desde `p_hasta` (hoy, si no se dice) la persona vuelve a su
-- seguro automático por vínculo.
create or replace function fn_seguro_volver_al_automatico(
  p_asignacion_id uuid,
  p_hasta         date,
  p_motivo        text
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien   uuid := fn_persona_actual_id();
  v_hoy     date := fn_hoy_lima();
  v_a       seguros_asignaciones%rowtype;
  v_hasta   date := coalesce(p_hasta, fn_hoy_lima());
  v_antes   text;
  v_despues text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede cambiar el seguro de una persona.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo (al menos 5 letras): queda anotado en el historial de su seguro.';
  end if;

  select * into v_a from seguros_asignaciones a where a.id = p_asignacion_id for update;
  if not found then
    raise exception 'Esa asignación no existe.';
  end if;
  if v_a.hasta is not null then
    raise exception 'Esa asignación ya terminó.';
  end if;
  if v_hasta > v_hoy then
    raise exception 'La fecha no puede ser posterior a hoy.';
  end if;
  if v_hasta < v_a.desde then
    raise exception 'No puede terminar antes de empezar (empezó el %).', to_char(v_a.desde, 'DD/MM/YYYY');
  end if;

  perform 1 from personas p where p.id = v_a.persona_id for update;

  v_antes := fn_seguro_tipo_principal(v_a.persona_id, v_hoy);

  update seguros_asignaciones
     set hasta = v_hasta, cerrada_por = v_quien, cerrada_motivo = btrim(p_motivo)
   where id = p_asignacion_id;

  v_despues := fn_seguro_tipo_principal(v_a.persona_id, v_hoy);
  if v_antes is distinct from v_despues then
    insert into seguros_cambios (persona_id, de_tipo, a_tipo, fecha, origen, detalle)
    values (v_a.persona_id, v_antes, v_despues, v_hoy, 'asignacion', btrim(p_motivo));
  end if;
end;
$fn$;

-- ── 15 · Cuando alguien cambia de seguro ─────────────────────────────────────

-- El disparador que escucha el CAMBIO DE VÍNCULO. No reescribe `fn_set_tipo_vinculo`
-- ni `fn_cesar_persona`: escucha la columna. Hace una sola cosa: si el seguro
-- principal que le toca a la persona por su vínculo cambió, deja escrito el cambio.
--
-- Y NUNCA frena el cambio de vínculo: cualquier error propio se atrapa y solo se
-- avisa (un warning). Un cambio de vínculo mueve la planilla de una persona real; el
-- registro de su seguro es secundario y no puede dejarla sin cambiar.
--
-- No registra nada si:
--   · la persona ya no está activa (un cese puede traer un vínculo nuevo en la misma
--     sentencia, y de su baja se ocupa el cese, no esta lista de pendientes), ni
--   · tiene una asignación de DO vigente: esa manda sobre el vínculo, así que su
--     seguro no cambia por cambiar de vínculo.
create or replace function fn_trg_seguros_cambio_de_vinculo()
returns trigger
language plpgsql security definer set search_path = public
as $fn$
declare
  v_hoy     date;
  v_antes   text;
  v_despues text;
begin
  begin
    -- Todo, hasta leer la fecha, dentro del bloque que atrapa: lo que se calcula en
    -- DECLARE queda FUERA de él, y un error ahí sí frenaría el cambio de vínculo.
    v_hoy := fn_hoy_lima();
    if new.estado is distinct from 'activo' or new.cuenta_de_servicio then
      return new;
    end if;
    if exists (select 1 from seguros_asignaciones a
                where a.persona_id = new.id and a.desde <= v_hoy and (a.hasta is null or v_hoy < a.hasta)) then
      return new;
    end if;

    v_antes   := fn_seguro_tipo_por_vinculo(old.tipo_vinculo);
    v_despues := fn_seguro_tipo_por_vinculo(new.tipo_vinculo);
    if v_antes is distinct from v_despues then
      insert into seguros_cambios (persona_id, de_tipo, a_tipo, fecha, origen, vinculo_antes, vinculo_despues)
      values (new.id, v_antes, v_despues, v_hoy, 'vinculo', old.tipo_vinculo, new.tipo_vinculo);
    end if;
  exception when others then
    raise warning 'seguros: no se pudo registrar el cambio de vínculo de la persona %: % (%)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$fn$;

drop trigger if exists trg_seguros_cambio_de_vinculo on personas;
create trigger trg_seguros_cambio_de_vinculo
  after update of tipo_vinculo on personas
  for each row
  when (old.tipo_vinculo is distinct from new.tipo_vinculo)
  execute function fn_trg_seguros_cambio_de_vinculo();


-- Marcar uno de los dos pasos de un cambio: 'baja' (se pidió o se confirmó la baja del
-- seguro anterior) o 'alta' (se registró o se confirmó el alta del nuevo). Con fecha =
-- hecho ese día; con `p_fecha` null = quitar la marca, y eso pide motivo en `p_nota`
-- (desmarcar algo hecho es lo que más conviene que quede escrito).
create or replace function fn_seguro_cambio_marcar(
  p_id    uuid,
  p_paso  text,
  p_fecha date,
  p_nota  text default null
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_quien uuid := fn_persona_actual_id();
  v_c     seguros_cambios%rowtype;
  v_antes date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede marcar los pasos de un cambio de seguro.';
  end if;
  if v_quien is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha.';
  end if;
  if p_paso is null or p_paso not in ('baja', 'alta') then
    raise exception 'Ese paso no existe: usa baja o alta.';
  end if;

  select * into v_c from seguros_cambios c where c.id = p_id for update;
  if not found then
    raise exception 'Ese cambio no existe.';
  end if;
  if p_paso = 'baja' and v_c.de_tipo is null then
    raise exception 'Ese cambio no tiene baja: la persona no tenía seguro antes.';
  end if;
  if p_paso = 'alta' and v_c.a_tipo is null then
    raise exception 'Ese cambio no tiene alta: la persona se quedó sin seguro.';
  end if;

  v_antes := case p_paso when 'baja' then v_c.baja_hecha_el else v_c.alta_hecha_el end;

  if p_fecha is null then
    if v_antes is null then
      raise exception 'Ese paso ya está sin marcar.';
    end if;
    if p_nota is null or char_length(btrim(p_nota)) < 5 then
      raise exception 'Escribe el motivo (al menos 5 letras): quitar una marca queda anotado.';
    end if;
  else
    if p_fecha > fn_hoy_lima() then
      raise exception 'La fecha no puede ser posterior a hoy.';
    end if;
    if v_antes is not distinct from p_fecha then
      raise exception 'Ese paso ya estaba marcado con esa fecha.';
    end if;
  end if;

  if p_paso = 'baja' then
    update seguros_cambios
       set baja_hecha_el  = p_fecha,
           baja_hecha_por = case when p_fecha is null then null else v_quien end,
           baja_nota      = nullif(btrim(p_nota), '')
     where id = p_id;
  else
    update seguros_cambios
       set alta_hecha_el  = p_fecha,
           alta_hecha_por = case when p_fecha is null then null else v_quien end,
           alta_nota      = nullif(btrim(p_nota), '')
     where id = p_id;
  end if;
end;
$fn$;

-- ── 16 · Lo que ve la pantalla ───────────────────────────────────────────────

-- El catálogo, con cuánta gente hay en cada tipo. Para un principal, las personas
-- ACTIVAS cuyo seguro principal de hoy es ese (por vínculo o por asignación); para un
-- complementario, las que tienen una póliza vigente de él.
create or replace function fn_seguros_tipos()
returns table (
  clave            text,
  nombre           text,
  descripcion      text,
  principal        boolean,
  con_poliza       boolean,
  aplica_a_vinculos text[],
  texto_alta       text,
  texto_baja       text,
  de_sistema       boolean,
  activo           boolean,
  archivado_motivo text,
  personas         integer,
  polizas_vigentes integer
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_hoy date := fn_hoy_lima();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve los tipos de seguro.';
  end if;

  return query
  select t.clave, t.nombre, t.descripcion, t.principal, t.con_poliza, t.aplica_a_vinculos,
         t.texto_alta, t.texto_baja, t.de_sistema, t.activo, t.archivado_motivo,
         case when t.principal
              then (select count(*)::int from personas p
                     where p.estado = 'activo' and not p.cuenta_de_servicio
                       and fn_seguro_tipo_principal(p.id, v_hoy) = t.clave)
              else (select count(distinct z.persona_id)::int from polizas_seguro z
                     where z.producto = t.clave and z.anulada_at is null
                       and v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta)
         end,
         (select count(*)::int from polizas_seguro z
           where z.producto = t.clave and z.anulada_at is null
             and v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta)
    from seguros_tipos t
   order by t.de_sistema desc, t.principal desc, t.nombre, t.clave;
end;
$fn$;


-- «En qué está cada colaborador»: UNA fila por persona, con su seguro principal de hoy,
-- de dónde sale (su vínculo o una asignación de DO) y si le falta la póliza que ese
-- seguro pide. Entran las personas ACTIVAS (menos las cuentas de servicio) y las que ya
-- no lo están pero conservan una póliza vigente: de esas hay que pedir la baja.
--
-- `hueco` es la regla de quién tiene que tener póliza, escrita UNA vez: la persona está
-- activa, su seguro principal lleva póliza y no tiene ninguna de ese tipo que cubra hoy.
-- EsSalud no lleva póliza: nunca es un hueco.
create or replace function fn_seguros_equipo()
returns table (
  persona_id            uuid,
  persona               text,
  sede                  text,
  tipo_vinculo          text,
  practicante_modalidad text,
  activa                boolean,
  tipo                  text,
  tipo_nombre           text,
  origen                text,
  asignacion_id         uuid,
  asignacion_desde      date,
  asignacion_motivo     text,
  con_poliza            boolean,
  cubre_hoy             boolean,
  hueco                 boolean
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
  select p.id,
         p.nombres || ' ' || p.apellidos,
         coalesce(s.codigo, '?'),
         p.tipo_vinculo,
         p.practicante_modalidad,
         (p.estado = 'activo'),
         ef.clave,
         t.nombre,
         case when a.id is not null then 'asignacion'
              when ef.clave is not null then 'vinculo' end,
         a.id,
         a.desde,
         a.motivo,
         coalesce(t.con_poliza, false),
         case when t.con_poliza then cob.cubre end,
         (p.estado = 'activo' and coalesce(t.con_poliza, false) and not coalesce(cob.cubre, false))
    from personas p
    left join sedes s on s.id = p.sede_base_id
    left join lateral (select fn_seguro_tipo_principal(p.id, v_hoy) as clave) ef on true
    left join seguros_tipos t on t.clave = ef.clave
    left join seguros_asignaciones a
           on a.persona_id = p.id and a.desde <= v_hoy and (a.hasta is null or v_hoy < a.hasta)
    left join lateral (
      select exists (select 1 from polizas_seguro z
                      where z.persona_id = p.id and z.producto = ef.clave and z.anulada_at is null
                        and v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta) as cubre
    ) cob on true
   where not p.cuenta_de_servicio
     and (p.estado = 'activo'
          or exists (select 1 from polizas_seguro z
                      where z.persona_id = p.id and z.anulada_at is null and z.vigente_hasta > v_hoy))
   -- `id` como ancla del orden: dos personas con el mismo nombre no empatan al azar.
   order by p.nombres || ' ' || p.apellidos, p.id;
end;
$fn$;


-- Todas las pólizas vivas (no anuladas), de cualquier tipo, con su persona y su tipo.
-- `cubre_hoy` ya resuelto, con el último día EXCLUSIVO.
create or replace function fn_seguros_tablero()
returns table (
  persona_id            uuid,
  persona               text,
  sede                  text,
  persona_activa        boolean,
  producto              text,
  producto_nombre       text,
  producto_principal    boolean,
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
  select p.id, p.nombres || ' ' || p.apellidos, coalesce(s.codigo, '?'), (p.estado = 'activo'),
         t.clave, t.nombre, t.principal,
         z.id, z.aseguradora, z.numero_poliza, z.vigente_desde, z.vigente_hasta,
         (v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta),
         z.prima_total, z.prima_vence_el, z.plan, z.beneficio_enfermedad, z.beneficio_accidente,
         z.renueva_sola, z.pagada_el, z.firmada_el, z.factura_recibida_el, z.nota,
         (select count(*)::int from polizas_seguro_archivos a
           where a.poliza_id = z.id and a.retirado_at is null),
         z.creada_at
    from polizas_seguro z
    join personas p on p.id = z.persona_id
    join seguros_tipos t on t.clave = z.producto
    left join sedes s on s.id = p.sede_base_id
   where z.anulada_at is null
   -- `id` como ancla del orden: dos pólizas con la misma vigencia no empatan al azar
   -- (lección de la 0312/0389).
   order by p.nombres || ' ' || p.apellidos, p.id, z.vigente_desde desc, z.id desc;
end;
$fn$;


-- Los cambios de seguro, con lo que cada uno todavía pide. Los pasos se calculan AL
-- LEER contra el estado de hoy (ver la cabecera): un paso solo está pendiente si
--   · la persona sigue activa;
--   · nadie lo marcó;
--   · sigue teniendo sentido — para la BAJA: la persona ya no está en el seguro del que
--     salió, y (si el seguro lleva póliza) todavía queda una vigente de ese tipo; para el
--     ALTA: la persona sigue en el seguro al que entró, y (si lleva póliza) todavía no
--     se le registró una.
-- `p_persona_id` null = de todas; `p_solo_pendientes` deja solo los que piden algo.
create or replace function fn_seguros_cambios(
  p_persona_id      uuid default null,
  p_solo_pendientes boolean default false
)
returns table (
  id               uuid,
  persona_id       uuid,
  persona          text,
  sede             text,
  persona_activa   boolean,
  de_tipo          text,
  de_nombre        text,
  a_tipo           text,
  a_nombre         text,
  fecha            date,
  origen           text,
  vinculo_antes    text,
  vinculo_despues  text,
  detalle          text,
  baja_pendiente   boolean,
  baja_texto       text,
  baja_hecha_el    date,
  baja_nota        text,
  alta_pendiente   boolean,
  alta_texto       text,
  alta_hecha_el    date,
  alta_nota        text,
  creado_at        timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_hoy date := fn_hoy_lima();
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve los cambios de seguro.';
  end if;

  return query
  select x.*
    from (
      select c.id, c.persona_id,
             p.nombres || ' ' || p.apellidos as persona,
             coalesce(s.codigo, '?') as sede,
             (p.estado = 'activo') as persona_activa,
             c.de_tipo, td.nombre as de_nombre, c.a_tipo, ta.nombre as a_nombre,
             c.fecha, c.origen, c.vinculo_antes, c.vinculo_despues, c.detalle,
             (p.estado = 'activo' and c.de_tipo is not null and c.baja_hecha_el is null
              and fn_seguro_tipo_principal(c.persona_id, v_hoy) is distinct from c.de_tipo
              and (not td.con_poliza
                   or exists (select 1 from polizas_seguro z
                               where z.persona_id = c.persona_id and z.producto = c.de_tipo
                                 and z.anulada_at is null and z.vigente_hasta > v_hoy))) as baja_pendiente,
             coalesce(td.texto_baja, 'Pedir la baja de ' || td.nombre) as baja_texto,
             c.baja_hecha_el, c.baja_nota,
             (p.estado = 'activo' and c.a_tipo is not null and c.alta_hecha_el is null
              and fn_seguro_tipo_principal(c.persona_id, v_hoy) is not distinct from c.a_tipo
              and (not ta.con_poliza
                   or not exists (select 1 from polizas_seguro z
                                   where z.persona_id = c.persona_id and z.producto = c.a_tipo
                                     and z.anulada_at is null and z.vigente_hasta > v_hoy))) as alta_pendiente,
             coalesce(ta.texto_alta, 'Dar de alta en ' || ta.nombre) as alta_texto,
             c.alta_hecha_el, c.alta_nota,
             c.creado_at
        from seguros_cambios c
        join personas p on p.id = c.persona_id
        left join sedes s on s.id = p.sede_base_id
        left join seguros_tipos td on td.clave = c.de_tipo
        left join seguros_tipos ta on ta.clave = c.a_tipo
       where (p_persona_id is null or c.persona_id = p_persona_id)
    ) x
   where not coalesce(p_solo_pendientes, false) or x.baja_pendiente or x.alta_pendiente
   -- `id` como ancla del orden: dos cambios del mismo día no empatan al azar.
   order by x.fecha desc, x.creado_at desc, x.id desc;
end;
$fn$;

-- El historial de una póliza y sus archivos, tal como estaban.
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

-- ── 17 · Quién puede llamar qué ──────────────────────────────────────────────
-- Desde la 0076 ninguna función nace con EXECUTE para nadie: sin estos grants la
-- pantalla queda vacía sin dar error (0204). Diecinueve las llama quien inició
-- sesión (y adentro cada una pregunta si es DO). Las cuatro de apoyo y el
-- disparador no las llama nadie desde fuera: corren porque las que las usan son
-- SECURITY DEFINER de la misma dueña.
grant execute on function
  fn_seguro_tipo_crear(text, text, boolean, boolean, text, text),
  fn_seguro_tipo_editar(text, text, text, text, text),
  fn_seguro_tipo_activar(text, boolean, text),
  fn_seguro_registrar(uuid, text, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text),
  fn_seguro_corregir(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text, text),
  fn_seguro_marcar_paso(uuid, text, date, text),
  fn_seguro_anular(uuid, text),
  fn_seguro_adjuntar(uuid, text, text, text),
  fn_seguro_retirar_archivo(uuid, text),
  fn_seguro_archivo_libre(text),
  fn_seguro_asignar(uuid, text, date, text),
  fn_seguro_volver_al_automatico(uuid, date, text),
  fn_seguro_cambio_marcar(uuid, text, date, text),
  fn_seguros_tipos(),
  fn_seguros_equipo(),
  fn_seguros_tablero(),
  fn_seguros_cambios(uuid, boolean),
  fn_seguro_historial(uuid),
  fn_seguro_archivos(uuid)
to authenticated;
revoke execute on function
  fn_seguro_tipo_crear(text, text, boolean, boolean, text, text),
  fn_seguro_tipo_editar(text, text, text, text, text),
  fn_seguro_tipo_activar(text, boolean, text),
  fn_seguro_registrar(uuid, text, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text),
  fn_seguro_corregir(uuid, text, text, date, date, numeric, date, text, numeric, numeric, boolean, text, text),
  fn_seguro_marcar_paso(uuid, text, date, text),
  fn_seguro_anular(uuid, text),
  fn_seguro_adjuntar(uuid, text, text, text),
  fn_seguro_retirar_archivo(uuid, text),
  fn_seguro_archivo_libre(text),
  fn_seguro_asignar(uuid, text, date, text),
  fn_seguro_volver_al_automatico(uuid, date, text),
  fn_seguro_cambio_marcar(uuid, text, date, text),
  fn_seguros_tipos(),
  fn_seguros_equipo(),
  fn_seguros_tablero(),
  fn_seguros_cambios(uuid, boolean),
  fn_seguro_historial(uuid),
  fn_seguro_archivos(uuid)
from public, anon;

revoke execute on function
  fn_seguro_tipo_por_vinculo(text),
  fn_seguro_tipo_principal(uuid, date),
  fn_seguro_datos_validos(text, text, date, date, numeric, date, text, numeric, numeric, text),
  fn_trg_seguros_cambio_de_vinculo()
from public, anon, authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (528, 'los_seguros_del_equipo_entran_al_sistema')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.tables
    where table_schema = 'public'
      and table_name in ('seguros_tipos','seguros_asignaciones','seguros_cambios',
                         'polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos')) as tablas_de_6,
  (select count(*) from pg_proc where proname in (
     'fn_seguro_tipo_por_vinculo','fn_seguro_tipo_principal','fn_seguro_tipo_crear','fn_seguro_tipo_editar',
     'fn_seguro_tipo_activar','fn_seguro_registrar','fn_seguro_corregir','fn_seguro_marcar_paso',
     'fn_seguro_anular','fn_seguro_adjuntar','fn_seguro_retirar_archivo','fn_seguro_archivo_libre',
     'fn_seguro_datos_validos','fn_seguro_asignar','fn_seguro_volver_al_automatico','fn_seguro_cambio_marcar',
     'fn_seguros_tipos','fn_seguros_equipo','fn_seguros_tablero','fn_seguros_cambios',
     'fn_seguro_historial','fn_seguro_archivos','fn_trg_seguros_cambio_de_vinculo')) as funciones_de_23,
  (select count(*) from pg_trigger where tgname = 'trg_seguros_cambio_de_vinculo' and not tgisinternal) as disparador_de_1,
  (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'polizas\_seguro\_%') as politicas_storage_de_4,
  (select count(*) from storage.buckets where id = 'polizas-seguro' and public is false) as bucket_privado,
  (select count(*) from pg_class where relname in ('seguros_tipos','seguros_asignaciones','seguros_cambios',
      'polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos') and relrowsecurity) as rls_activa_en_6,
  (select string_agg(clave, ',' order by clave) from seguros_tipos where de_sistema) as tipos_de_sistema,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 528) as registro;
