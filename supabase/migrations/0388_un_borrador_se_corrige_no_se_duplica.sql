-- ============================================================================
-- 0388 · Un borrador se corrige, no se duplica
-- ============================================================================
-- QUÉ PROMETE
--
--   Que la misma persona no pueda quedarse con dos documentos vivos que digan
--   a la vez cosas distintas sobre su vínculo — y que el que todavía no está
--   firmado se pueda CORREGIR en su sitio, en vez de generar otro al lado.
--
--   El accidente es real y está en el archivo de producción: el 4 de setiembre
--   de 2026, Geison Alcántara quedó con DOS convenios de prácticas idénticos
--   —mismo tipo, mismo periodo (3/09 – 3/12/2026), los dos «pendiente de
--   firma»— más uno anulado. Nada en `/admin/contratos` distinguía «generar el
--   suyo» de «generar uno más», y como la pantalla no sabía corregir, el gesto
--   natural para arreglar una fecha era volver a generar. El archivo terminó
--   con dos papeles que se contradicen sobre las mismas fechas de una persona
--   real, y ninguno de los dos se sabe cuál vale.
--
--   Cinco cambios:
--     1. `contratos_generados` gana `datos_formulario jsonb` — la foto de lo
--        que se tecleó — y `editado_at` / `editado_por`.
--     2. `fn_contrato_registrar` rechaza el duplicado al generar, rechaza la
--        firma que pisaría un contrato ya firmado, y guarda esa foto.
--     3. `fn_contrato_editar` (nueva) corrige un borrador EN SU SITIO.
--     4. `fn_contratos_listar` devuelve `editado_at` / `editado_por`.
--     5. Ningún dato se toca: los duplicados que YA existen se quedan donde
--        están (ver «QUÉ NO HACE»).
--
-- LAS TRES REGLAS, Y DÓNDE SE APLICA CADA UNA
--
--   · CANDADO 1 — «un solo borrador sin firmar por persona y tipo».
--     Solo AL GENERAR. Un documento sin firmar no es un documento: es un
--     borrador, y un borrador se corrige. Si ya hay uno de ese tipo esperando
--     firma, el segundo sobra siempre.
--
--   · CANDADO 2 — «nada de periodos pisados».
--     Dos papeles que cubren los mismos días son el problema, esté uno firmado
--     o no. Al GENERAR se mide contra todos los no anulados; AL EDITAR, solo
--     contra los FIRMADOS (ver por qué más abajo). AL FIRMAR no se mide nunca:
--     registrar un papel que existe no se bloquea jamás (también más abajo).
--
--   · EL ADENDUM QUEDA FUERA DEL CANDADO 2, por los dos lados.
--     No define un vínculo: MODIFICA el que ya existe. Se monta sobre su
--     contrato por definición, y pisarlo es exactamente lo que le toca hacer.
--     Sigue sujeto al candado 1, que es el que caza el adendum duplicado.
--
-- POR QUÉ AL EDITAR EL CANDADO 2 SOLO MIRA LOS FIRMADOS
--
--   Porque si mirara todos, la pantalla ofrecería «Editar» sobre los dos
--   convenios de Geison y el servidor rechazaría los dos: cada uno pisa al
--   otro, y no habría forma de arreglar ninguno sin anular primero — una
--   trampa cerrada justo sobre los datos que motivan esta migración. Editar no
--   CREA nada; el desorden que ya existe se resuelve corrigiendo o anulando, y
--   para eso hay que poder entrar.
--
-- POR QUÉ AL FIRMAR NO SE MIDE NADA
--
--   Porque un papel firmado existe, y el sistema tiene que poder registrarlo
--   siempre. Es la promesa de la 0287/0312, y la prueba 246 la vigila con
--   nombre y apellido: «El borrador viejo se puede archivar igual: el papel
--   existe». La primera versión de esta migración sí puso un candado ahí y esa
--   prueba lo tumbó — bien tumbado: negarse a registrar un escaneo no evita el
--   desorden, lo saca del panel y lo deja solo en el archivador. El desorden se
--   ataja donde se CREA, no donde se documenta.
--
-- POR QUÉ SE GUARDA `datos_formulario` Y NO BASTA `documento_html`
--
--   `documento_html` guarda el RESULTADO —el papel que se imprime—, no las
--   respuestas que lo produjeron: la causa objetiva, las funciones del Anexo I,
--   los cuatro datos del centro de formación, los hitos de los meses 3 y 6.
--   Son veintiún campos. Sin esta foto, «editar» obligaría a reescribirlos
--   todos para corregir una fecha, y nadie corrige una fecha a ese precio:
--   volvería a generar otro documento — que es el duplicado que esta migración
--   viene a impedir. Un freno que deja el camino cómodo por fuera no frena.
--
--   Es `jsonb` y no veintiuna columnas a propósito: no es un dato del negocio
--   que nadie vaya a consultar ni cruzar, es el estado de un formulario para
--   poder volver a abrirlo. La verdad legal sigue siendo `documento_html`.
--   Un borrador anterior a esta migración la tiene en NULL, y la pantalla lo
--   dice al abrirlo en vez de fingir que esos textos son los suyos.
--
-- POR QUÉ `fn_contrato_editar` NO ACEPTA `persona_id` NI `sede_id`
--
--   Un borrador es de quien es. Cambiarle la persona no sería corregirlo,
--   sería otro documento — y para eso está generar. La sede sale de la ficha
--   de esa persona y no se elige en esta pantalla.
--
-- POR QUÉ UN CONTRATO FIRMADO NO SE EDITA NUNCA
--
--   Porque lo que vale es el papel que las dos partes firmaron. Reescribir su
--   texto por detrás dejaría al sistema diciendo una cosa y al archivador otra,
--   y ese archivador es lo que se presenta ante una inspección. Para corregir
--   algo firmado están las dos puertas de siempre: el adendum, que modifica sin
--   negar, y la anulación con motivo, que deja el rastro.
--
-- ⚠️ SE BORRA LA FIRMA VIEJA DE `fn_contrato_registrar` ANTES DE CREARLA
--
--   `p_datos_formulario` es un parámetro NUEVO, y los doce que ya tenía la
--   función tienen todos valor por defecto. Un `create or replace` NO la
--   reemplazaría: crearía una SEGUNDA función con distinta aridad, y la
--   llamada de la pantalla —que pasa los argumentos por nombre— encajaría en
--   las dos. Postgres respondería «function fn_contrato_registrar is not
--   unique» y el generador de contratos dejaría de funcionar en producción,
--   sin fallar al pegar esta migración: fallaría al abrir la pantalla. Es
--   exactamente el accidente de la 0297/0299 con `fn_vacaciones_por_vencer`,
--   documentado en CLAUDE.md. Por eso va un `drop function` con la firma
--   completa y explícita antes del `create`.
--
-- QUÉ ASUME
--
--   · Que la 0347 es la versión vigente de `fn_contrato_registrar` y la 0287
--     la de `fn_contratos_listar` (comprobado con `./scripts/donde-vive.sh`).
--   · Que `fn_contrato_editar` no existe en ninguna rama (comprobado también
--     con `donde-vive.sh`, que es la regla desde la 0299).
--
-- QUÉ NO HACE, Y ES DELIBERADO
--
--   No toca ni una fila. Los duplicados que ya están en producción —los dos
--   convenios de Geison— siguen ahí después de pegar esto. Anularlos desde una
--   migración sería decidir por Desarrollo Organizacional cuál de los dos vale,
--   sin verlos, y sobre documentos de una persona real. La pantalla ahora los
--   muestra juntos con «Editar» y «Anular» al lado; esa decisión es de quien
--   los mira.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_contrato_editar(uuid, text, text, numeric, date, date, text, jsonb);
--   drop function if exists fn_contrato_registrar(uuid, text, text, uuid, numeric, date, date, numeric, text, jsonb, uuid, text, date);
--   drop function if exists fn_contratos_listar(uuid);
--   Y correr de nuevo el cuerpo de `fn_contrato_registrar` tal como quedó en la
--   0347, y el de `fn_contratos_listar` tal como quedó en la 0287.
--   alter table contratos_generados drop constraint contrato_edicion_coherente;
--   alter table contratos_generados drop column editado_por, drop column editado_at,
--                                   drop column datos_formulario;
-- ============================================================================

-- ── 1 · Las tres columnas nuevas ────────────────────────────────────────────
alter table contratos_generados add column if not exists datos_formulario jsonb;
alter table contratos_generados add column if not exists editado_at       timestamptz;
alter table contratos_generados add column if not exists editado_por      uuid references personas(id);

alter table contratos_generados drop constraint if exists contrato_edicion_coherente;
alter table contratos_generados add constraint contrato_edicion_coherente
  check ((editado_at is null) = (editado_por is null));

alter table contratos_generados drop constraint if exists contrato_datos_formulario_objeto;
alter table contratos_generados add constraint contrato_datos_formulario_objeto
  check (datos_formulario is null or jsonb_typeof(datos_formulario) = 'object');

comment on column contratos_generados.datos_formulario is
  'Foto de lo que se tecleó en /admin/contratos al generar este documento '
  '(0388), para poder reabrirlo y corregirlo sin reescribir los veintiún '
  'campos. NO es la verdad legal — esa es documento_html, que es el papel que '
  'se imprime y se firma. NULL en todo lo generado antes de la 0388.';

comment on column contratos_generados.editado_at is
  'Cuándo se corrigió este borrador por última vez (0388). Solo un borrador se '
  'edita: con escaneo firmado adentro, el papel manda y se corrige con adendum '
  'o anulación.';

-- ── 2 · fn_contrato_registrar: los candados, y la foto del formulario ───────
-- Cuerpo vigente: 0347_el_generador_de_contratos_hace_indefinidos.sql.
-- Los cambios van marcados CAMBIO 0388; el resto es idéntico.
--
-- El drop de la firma vieja NO es opcional — ver la advertencia de la cabecera.
drop function if exists fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, uuid, text, date
);

create or replace function fn_contrato_registrar(
  p_persona_id            uuid    default null,
  p_tipo                  text    default null,
  p_cargo                 text    default null,
  p_sede_id               uuid    default null,
  p_remuneracion_mensual  numeric default null,
  p_fecha_inicio          date    default null,
  p_fecha_fin             date    default null,
  p_horas_semanales       numeric default null,
  p_documento_html        text    default null,
  p_datos_formulario      jsonb   default null,   -- CAMBIO 0388
  p_id                    uuid    default null,   -- no nulo = adjuntar firma a un borrador existente
  p_storage_path          text    default null,
  p_fecha_firma           date    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  v_yo      uuid := fn_persona_actual_id();
  v_nota    text := '';
  r         contratos_generados%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional genera contratos.';
  end if;

  -- ── Adjuntar la firma a un borrador ya generado ──
  if p_id is not null then
    select * into r from contratos_generados where id = p_id;
    if not found then raise exception 'Ese contrato no existe.'; end if;
    if r.anulado_at is not null then raise exception 'Ese contrato está anulado.'; end if;
    if r.storage_path is not null then raise exception 'Ese contrato ya tiene un escaneo registrado.'; end if;
    if p_storage_path is null then raise exception 'Falta el escaneo firmado.'; end if;
    if p_fecha_firma is null then raise exception 'Falta la fecha en que se firmó.'; end if;
    if p_fecha_firma > fn_hoy_lima() then raise exception 'La fecha de firma no puede ser futura.'; end if;

    -- POR QUÉ AQUÍ NO HAY NINGÚN CANDADO DE PERIODO, Y ES DELIBERADO.
    -- La primera versión de esta migración sí ponía uno: adjuntar un escaneo
    -- se rechazaba si ese periodo ya lo cubría otro contrato firmado. Lo tumbó
    -- la prueba 246 —«El borrador viejo se puede archivar igual: el papel
    -- existe»— y tenía razón. Esa promesa es de la 0287/0312 y es más
    -- importante que la simetría: si dos papeles se firmaron, los dos
    -- existen, y un sistema que se niega a registrar uno no evita el
    -- desorden — lo esconde, que es peor, porque entonces el archivador y el
    -- panel dicen cosas distintas. El desorden se controla donde se CREA
    -- (los dos candados de más abajo) y se resuelve anulando con motivo;
    -- registrar la realidad nunca se bloquea.

    -- El archivo tiene que ser EL DE ESTE CONTRATO. `p_storage_path` es texto
    -- libre, y `fn_contrato_puede_ver` resuelve el permiso por el uuid que va
    -- en el nombre del archivo: apuntar la fila de una persona al escaneo de
    -- otra dejaría a la primera sin poder abrir su propio contrato y a la
    -- segunda viéndolo. Se cierra acá, que es donde se elige el path.
    if p_storage_path !~ ('^contratos/' || p_id::text || '\.') then
      raise exception 'La ruta del escaneo no corresponde a este contrato.';
    end if;

    update contratos_generados
       set storage_path = p_storage_path, fecha_firma = p_fecha_firma, registrado_por = v_yo
     where id = p_id;

    -- La fecha de vencimiento se mueve recién con la firma puesta: un borrador
    -- descartado nunca debe haber tocado este dato.
    --
    -- PERO NO SE DEJA CAER EL REGISTRO SI LA PERSONA YA NO ESTÁ ACTIVA. Ese era
    -- el defecto: `fn_set_fin_contrato` corta con «ya está inactiva», y quien
    -- cesó entre imprimir y firmar se quedaba SIN PODER ARCHIVAR su contrato
    -- firmado — justo el papel que hay que conservar. Para alguien cesado la
    -- fecha de vencimiento no significa nada; el documento sí.
    -- La fecha se recalcula, no se escribe a ciegas (0312). Antes se le ponía
    -- la fecha DE ESTE contrato sin más. Firmar un borrador viejo después de
    -- haber firmado el nuevo movía el vencimiento HACIA ATRÁS, y ese es el
    -- dato que `fn_contratos_desnaturalizados` usa para avisar del riesgo del
    -- artículo 77: retrocederlo fabrica una desnaturalización que no ocurrió,
    -- o esconde una que sí.
    --
    -- Se recalcula DESPUÉS del update de arriba, así que el contrato que se
    -- acaba de firmar ya cuenta como firmado y compite en igualdad. Si es el
    -- más reciente firmado, la fecha es la suya; si no, gana el otro y la suya
    -- no toca nada. Nunca borra: acaba de aparecer un contrato firmado.
    -- Un convenio firmado también mueve fecha_fin_contrato (0333) — es el
    -- mismo dato, reusado como fecha de fin de convenio.
    -- Un indefinido firmado también dispara el recálculo (0347): su
    -- `fecha_fin` es NULL, y `fn_set_fin_contrato(..., null, ...)` ya sabe
    -- leer eso como "sin fecha de vencimiento" — no hace falta un caso aparte.
    if r.tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
      v_nota := fn_contrato_refrescar_vencimiento(
                  r.persona_id, 'Contrato firmado — generador de contratos');
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'contrato_firmado', null,
       r.tipo || ' · firmado el ' || p_fecha_firma::text, v_yo,
       'Escaneo del contrato firmado registrado' || v_nota);

    return p_id;
  end if;

  -- ── Generar el borrador ──
  if p_tipo not in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
    raise exception 'Tipo de contrato inválido: «%».', p_tipo;
  end if;
  if p_persona_id is null or not exists (
    select 1 from personas where id = p_persona_id and estado = 'activo'
  ) then
    raise exception 'Esa persona no existe o no está activa.';
  end if;
  if p_cargo is null or btrim(p_cargo) = '' then
    raise exception 'Falta el cargo.';
  end if;
  if p_sede_id is null then
    raise exception 'Falta la sede.';
  end if;
  if p_remuneracion_mensual is null or p_remuneracion_mensual < 0 then
    raise exception 'Falta la remuneración, o es inválida.';
  end if;
  -- Un indefinido NUNCA lleva fecha de fin; cualquier otro tipo SIEMPRE la
  -- exige, posterior a la de inicio (0347).
  if p_fecha_inicio is null then
    raise exception 'Las fechas del contrato son inválidas.';
  end if;
  if p_tipo = 'indefinido' then
    if p_fecha_fin is not null then
      raise exception 'Un contrato indefinido no lleva fecha de fin.';
    end if;
  else
    if p_fecha_fin is null or p_fecha_fin <= p_fecha_inicio then
      raise exception 'Las fechas del contrato son inválidas.';
    end if;
  end if;
  if p_documento_html is null or btrim(p_documento_html) = '' then
    raise exception 'Falta el texto del contrato.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0388 ⇩⇩⇩ CANDADO 1 · un solo borrador sin firmar por tipo.
  -- Un documento sin firmar es un borrador, y un borrador se corrige — para eso
  -- existe `fn_contrato_editar`. Si ya hay uno de este tipo esperando firma, el
  -- segundo sobra siempre, tenga las fechas que tenga.
  if exists (
    select 1 from contratos_generados c
     where c.persona_id   = p_persona_id
       and c.tipo         = p_tipo
       and c.anulado_at   is null
       and c.storage_path is null
  ) then
    raise exception 'Esa persona ya tiene un documento de ese tipo sin firmar. Edítalo o anúlalo: no se generan dos.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0388 ⇩⇩⇩ CANDADO 2 · nada de periodos pisados.
  -- Acá se mide contra TODOS los no anulados —firmados o no—: al generar aún no
  -- hay nada que rescatar, así que no hace falta la indulgencia que sí necesita
  -- editar. El adendum queda fuera por los dos lados.
  if p_tipo <> 'adendum' and exists (
    select 1 from contratos_generados c
     where c.persona_id  = p_persona_id
       and c.anulado_at  is null
       and c.tipo       <> 'adendum'
       and daterange(c.fecha_inicio, coalesce(c.fecha_fin, 'infinity'::date), '[]')
        && daterange(p_fecha_inicio, coalesce(p_fecha_fin, 'infinity'::date), '[]')
  ) then
    raise exception 'Esas fechas se pisan con otro documento vigente de esa persona. Cambia el periodo, o anula el anterior si ya no vale.';
  end if;

  insert into contratos_generados (
    persona_id, tipo, cargo, sede_id, remuneracion_mensual,
    fecha_inicio, fecha_fin, horas_semanales, documento_html, datos_formulario, generado_por
  ) values (
    p_persona_id, p_tipo, trim(p_cargo), p_sede_id, p_remuneracion_mensual,
    p_fecha_inicio, p_fecha_fin, p_horas_semanales, p_documento_html, p_datos_formulario, v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'contrato_generado', null,
     p_tipo || ' · generado el ' || fn_hoy_lima()::text, v_yo,
     'Alta de borrador de contrato');

  return v_id;
end;
$$;

grant execute on function fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, jsonb, uuid, text, date
) to authenticated;
revoke execute on function fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, jsonb, uuid, text, date
) from public, anon;

-- ── 3 · fn_contrato_editar: corregir un borrador EN SU SITIO ────────────────
-- Función nueva (comprobado con `donde-vive.sh` antes de escribirla, que es la
-- regla desde el choque de la 0297/0299).
create or replace function fn_contrato_editar(
  p_id                    uuid    default null,
  p_tipo                  text    default null,
  p_cargo                 text    default null,
  p_remuneracion_mensual  numeric default null,
  p_fecha_inicio          date    default null,
  p_fecha_fin             date    default null,
  p_documento_html        text    default null,
  p_datos_formulario      jsonb   default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  r    contratos_generados%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional corrige contratos.';
  end if;

  if p_id is null then
    raise exception 'Falta indicar qué borrador se corrige.';
  end if;
  select * into r from contratos_generados where id = p_id;
  if not found then
    raise exception 'Ese contrato no existe.';
  end if;
  if r.anulado_at is not null then
    raise exception 'Ese contrato está anulado: ya no se corrige, se genera uno nuevo.';
  end if;
  -- LA LÍNEA QUE NO SE CRUZA. Con el escaneo adentro, lo que vale es el papel
  -- que las dos partes firmaron; reescribir su texto por detrás dejaría al
  -- sistema diciendo una cosa y al archivador otra. Se corrige con un adendum,
  -- que modifica sin negar, o con la anulación, que deja el rastro.
  if r.storage_path is not null then
    raise exception 'Ese contrato ya está firmado: no se edita. Usa un adendum, o anúlalo con su motivo.';
  end if;

  -- Las mismas validaciones que al generar: un borrador corregido tiene que
  -- salir tan válido como uno recién hecho.
  if p_tipo not in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
    raise exception 'Tipo de contrato inválido: «%».', p_tipo;
  end if;
  if p_cargo is null or btrim(p_cargo) = '' then
    raise exception 'Falta el cargo.';
  end if;
  if p_remuneracion_mensual is null or p_remuneracion_mensual < 0 then
    raise exception 'Falta la remuneración, o es inválida.';
  end if;
  if p_fecha_inicio is null then
    raise exception 'Las fechas del contrato son inválidas.';
  end if;
  if p_tipo = 'indefinido' then
    if p_fecha_fin is not null then
      raise exception 'Un contrato indefinido no lleva fecha de fin.';
    end if;
  else
    if p_fecha_fin is null or p_fecha_fin <= p_fecha_inicio then
      raise exception 'Las fechas del contrato son inválidas.';
    end if;
  end if;
  if p_documento_html is null or btrim(p_documento_html) = '' then
    raise exception 'Falta el texto del contrato.';
  end if;

  -- CANDADO 2, EN SU VERSIÓN INDULGENTE: solo contra lo YA FIRMADO.
  -- Ver «POR QUÉ AL EDITAR EL CANDADO 2 SOLO MIRA LOS FIRMADOS» en la cabecera:
  -- medirlo contra los otros borradores dejaría sin salida justo a quien ya
  -- tiene dos pisados, que es a quien esto viene a rescatar.
  if p_tipo <> 'adendum' and exists (
    select 1 from contratos_generados c
     where c.persona_id      = r.persona_id
       and c.id             <> r.id
       and c.anulado_at      is null
       and c.storage_path    is not null
       and c.tipo           <> 'adendum'
       and daterange(c.fecha_inicio, coalesce(c.fecha_fin, 'infinity'::date), '[]')
        && daterange(p_fecha_inicio, coalesce(p_fecha_fin, 'infinity'::date), '[]')
  ) then
    raise exception 'Esas fechas se pisan con un contrato ya firmado de esa persona. Cambia el periodo, o anula el firmado si ya no vale.';
  end if;

  update contratos_generados
     set tipo                 = p_tipo,
         cargo                = trim(p_cargo),
         remuneracion_mensual = p_remuneracion_mensual,
         fecha_inicio         = p_fecha_inicio,
         fecha_fin            = p_fecha_fin,
         documento_html       = p_documento_html,
         datos_formulario     = p_datos_formulario,
         editado_at           = now(),
         editado_por          = v_yo
   where id = p_id;

  -- `generado_at` NO se toca: es lo que ordena el archivo y lo que usa
  -- `fn_contratos_tablero` para elegir el contrato que manda. Moverlo al
  -- corregir una coma reordenaría el historial de esa persona.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id, 'contrato_editado',
     r.tipo || ' · ' || r.fecha_inicio::text || ' → ' || coalesce(r.fecha_fin::text, 'sin fin'),
     p_tipo || ' · ' || p_fecha_inicio::text || ' → ' || coalesce(p_fecha_fin::text, 'sin fin'),
     v_yo,
     'Borrador de contrato corregido antes de firmarse');

  return p_id;
end;
$$;

grant execute on function fn_contrato_editar(
  uuid, text, text, numeric, date, date, text, jsonb
) to authenticated;
revoke execute on function fn_contrato_editar(
  uuid, text, text, numeric, date, date, text, jsonb
) from public, anon;

-- ── 4 · fn_contratos_listar dice si un borrador se corrigió ─────────────────
-- Cuerpo vigente: 0287_el_contrato_firmado_se_registra_y_sus_plazos_se_miden.sql.
-- Devuelve TABLE y gana dos columnas, así que `create or replace` no basta:
-- Postgres no deja cambiarle el tipo de retorno. Va drop + create, con la firma
-- explícita — es la misma `(uuid)` de siempre, así que no queda sobrecarga.
drop function if exists fn_contratos_listar(uuid);

create function fn_contratos_listar(p_persona_id uuid default null)
returns table (
  id                    uuid,
  persona_id            uuid,
  persona               text,
  tipo                  text,
  cargo                 text,
  sede                  text,
  remuneracion_mensual  numeric,
  fecha_inicio          date,
  fecha_fin             date,
  horas_semanales       numeric,
  generado_at           timestamptz,
  generado_por          text,
  storage_path          text,
  fecha_firma           date,
  copia_entregada_at    date,
  comunicado_mtpe_at    date,
  anulado_at            timestamptz,
  anulado_motivo        text,
  editado_at            timestamptz,   -- CAMBIO 0388
  editado_por           text,          -- CAMBIO 0388
  vigente               boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id, c.persona_id, p.nombres || ' ' || p.apellidos,
    c.tipo, c.cargo, s.nombre,
    c.remuneracion_mensual, c.fecha_inicio, c.fecha_fin, c.horas_semanales,
    c.generado_at,
    gen.nombres || ' ' || gen.apellidos,
    c.storage_path, c.fecha_firma,
    c.copia_entregada_at, c.comunicado_mtpe_at,
    c.anulado_at, c.anulado_motivo,
    c.editado_at,
    edi.nombres || ' ' || edi.apellidos,
    (c.anulado_at is null and c.id = (
       select c2.id from contratos_generados c2
        where c2.persona_id = c.persona_id and c2.anulado_at is null
        order by c2.generado_at desc limit 1))
  from contratos_generados c
  join personas p on p.id = c.persona_id
  left join personas gen on gen.id = c.generado_por
  left join personas edi on edi.id = c.editado_por
  left join sedes s on s.id = c.sede_id
  where (fn_es_admin_o_lider() is true or c.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or c.persona_id = p_persona_id)
  order by c.generado_at desc;
$$;

grant execute on function fn_contratos_listar(uuid) to authenticated;
revoke execute on function fn_contratos_listar(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (388, 'un_borrador_se_corrige_no_se_duplica')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación para pegar después en el SQL Editor ────────────────────────
-- Las tres cosas que tienen que ser ciertas al terminar. La primera es la que
-- no se ve al pegar y mata la pantalla: dos fn_contrato_registrar conviviendo.
--
--   select
--     (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public' and p.proname = 'fn_contrato_registrar') = 1
--       as una_sola_registrar,
--     (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public' and p.proname = 'fn_contratos_listar')   = 1
--       as una_sola_listar,
--     (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public' and p.proname = 'fn_contrato_editar')    = 1
--       as existe_editar;
--
-- Y esta dice si en producción quedan duplicados de los de antes — los que esta
-- migración NO toca a propósito, para que los mire Desarrollo Organizacional:
--
--   select p.nombres || ' ' || p.apellidos as persona, c.tipo, count(*)
--     from contratos_generados c join personas p on p.id = c.persona_id
--    where c.anulado_at is null and c.storage_path is null
--    group by 1, 2 having count(*) > 1;
