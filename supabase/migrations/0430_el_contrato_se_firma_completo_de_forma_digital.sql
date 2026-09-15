-- ============================================================================
-- 0430 — El contrato se firma completo de forma digital
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que Contrato pase a firmarse igual que Movilidad (0423/0425): confirmar tu
--   firma en /mio/contrato («Confirmar mi firma aquí») ES firmar el contrato,
--   sin que además haga falta imprimir, firmar a mano y subir un escaneo.
--   Decisión de Felipe, 2026-09-12: dibujar tu firma, escribirla o subir la
--   foto de una firma manuscrita son solo MÉTODOS de cómo se ve tu firma —no
--   deciden si el documento es válido—, y el documento siempre fue,
--   íntegramente, el HTML que ya se genera y se estampa con las dos firmas.
--
--   Antes de esta migración, `fecha_firma` (la columna que el resto del
--   sistema ya trata como «el contrato está firmado» — ver
--   `fn_contrato_firmado_vigente_de`, 0312) solo la ponía DO al subir un
--   escaneo (`fn_contrato_registrar`). La confirmación digital de la persona
--   (0402/0406) solo tocaba `firma_persona_confirmada_at`, una columna aparte
--   que nada más leía. Ese hueco es el que reportó Fernanda Espinoza el
--   2026-09-12: confirmó su firma, y /mio le seguía diciendo «Pendiente de
--   firma», porque en los hechos su contrato NUNCA quedaba firmado del todo
--   sin que alguien de DO le imprimiera, hiciera firmar a mano y escaneara el
--   mismo documento que ella ya había firmado en pantalla.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No retira la vía del escaneo. Decisión explícita de Felipe (2026-09-12,
--   preguntado con AskUserQuestion): Desarrollo Organizacional la conserva
--   como respaldo para quien no pueda autoservirse desde /mio/contrato —mismo
--   criterio que ya vale para movilidad ("Desarrollo Organizacional conserva
--   la vía del escaneo para quien no pueda firmar desde acá", 0423). Subir un
--   escaneo sigue funcionando exactamente igual que hoy para un contrato que
--   todavía no tiene `fecha_firma`; para uno que ya la tiene por confirmación
--   digital, adjuntar un escaneo después queda permitido —como archivo de
--   respaldo— pero deja de MOVER la fecha de firma: `fecha_firma` y
--   `registrado_por` se protegen con `coalesce`, nunca se sobrescriben. Sin
--   ese `coalesce`, subir un escaneo semanas después de la firma digital
--   habría corrido la fecha legal de firma hacia adelante en silencio.
--
--   No cambia el criterio de «cuál es el contrato vigente/firmado» en ningún
--   sitio del backend: `fn_contrato_firmado_vigente_de` YA medía contra
--   `fecha_firma is not null`, nunca contra `storage_path` — el defecto
--   estaba en que nada ponía `fecha_firma` por la vía digital, y en que el
--   FRONTEND de admin/contratos sí usaba `storage_path` como atajo para «está
--   firmado» en varios sitios (corregido aparte, en el mismo commit, sin
--   migración: es lectura de columnas que ya vienen, no un cambio de esquema).
--
--   No toca `confirmaciones_firma_contrato` (0406): sigue siendo el historial
--   de qué IMAGEN se confirmó y cuándo, independiente de si esa confirmación
--   fue la primera (la que ahora también firma el contrato) o una posterior
--   (que solo corrige la imagen, sin volver a fechar nada — ver el `coalesce`
--   de arriba).
--
--   No le abre a nadie una puerta nueva sobre `personas.fecha_fin_contrato`.
--   `fn_set_fin_contrato_nucleo` (parte E) nunca se concede a `authenticated`:
--   solo la alcanzan `fn_set_fin_contrato` (que sigue exigiendo admin/líder,
--   sin cambios) y `fn_contrato_refrescar_vencimiento` (que nunca estuvo
--   concedida a `authenticated`, desde la 0312, y cuyo `p_fecha` nunca sale de
--   quien pregunta). Ver el porqué completo en la parte E.
--
-- QUÉ ASUME
--
--   `fn_confirmar_mi_firma_contrato` vigente es la 0406 (un parámetro,
--   `p_contrato_id`); `fn_contrato_registrar` y `fn_contrato_editar` vigentes
--   son las de la 0388; `fn_set_fin_contrato` vigente es la 0144, sin cambios
--   desde entonces; `fn_contrato_refrescar_vencimiento` vigente es la 0347 —
--   confirmado el 2026-09-12 con `./scripts/donde-vive.sh` y, para las cinco,
--   comparando directo contra el Postgres local (`pg_proc.prosrc`), porque el
--   stack de PostgREST sigue sin poder levantarse en esta Mac (ver 0423/0424)
--   y `donde-vive.sh` no pudo comparar por esa vía.
--
--   RE-VERIFICADO CONTRA PRODUCCIÓN el 2026-09-15, antes de pegar: las cinco
--   siguen con el cuerpo que esta migración asume. md5 de `pg_proc.prosrc`
--   pedido al SQL Editor — fn_contrato_editar a867178f…, fn_contrato_registrar
--   fd1f86f5…, fn_set_fin_contrato fda44096…, fn_contrato_refrescar_vencimiento
--   a78d1a73…, todos idénticos al cuerpo del repositorio. El de
--   fn_confirmar_mi_firma_contrato (9fd167ef…) NO coincide tal cual y sí al
--   quitarle los `\r`: producción tiene 30 retornos de carro de más, uno por
--   línea, porque se pegó desde Windows. Es la causa benigna que documenta
--   CLAUDE.md — mismo código, se comporta igual — y no la otra, que sí
--   obligaría a parar.
--
--   QUE EL BACKFILL DE LA PARTE F NECESITA UN AUTOR, y que en el SQL Editor no
--   lo hay. Es el motivo por el que esta migración estuvo sin poder pegarse:
--   ver el bloque comentado en la propia parte F. Se resolvió sembrando la
--   sesión con el admin activo más antiguo, con el criterio de la 0176. Si
--   alguna vez no hubiera ningún admin activo con usuario, la migración se
--   detiene sin tocar nada en vez de escribir datos de personas sin poder
--   decir quién los cambió.
--
-- CÓMO SE REVIERTE
--
--   alter table contratos_generados drop constraint contrato_firma_coherente;
--   alter table contratos_generados add constraint contrato_firma_coherente
--     check (storage_path is null and fecha_firma is null and registrado_por is null
--        or storage_path is not null and fecha_firma is not null and registrado_por is not null);
--   -- recrear fn_confirmar_mi_firma_contrato con el cuerpo de la 0406;
--   -- recrear fn_contrato_registrar y fn_contrato_editar con los cuerpos de la 0388;
--   -- recrear fn_set_fin_contrato con el cuerpo de la 0144;
--   -- recrear fn_contrato_refrescar_vencimiento con el cuerpo de la 0347;
--   drop function if exists fn_set_fin_contrato_nucleo(uuid, date, text);
--   El backfill de la parte D no se puede deshacer con exactitud (no queda
--   registro de qué `fecha_firma` puso cada fila antes de esta migración,
--   porque antes de pegar esto ninguna fila digital-only tenía una), pero
--   revertir el código deja de LEER esas fechas como «firma legal» — no hace
--   falta borrarlas para que el revert sea seguro.
-- ============================================================================


-- ── A · El constraint deja de exigir escaneo para que el contrato cuente como firmado ──
-- Antes: storage_path, fecha_firma y registrado_por viajaban juntos, los tres
-- o ninguno. Ahora: fecha_firma y registrado_por siguen viajando juntos (son
-- «¿está firmado, y quién lo registró?»), pero storage_path queda
-- independiente — puede haber un contrato firmado SIN escaneo (el caso nuevo,
-- puramente digital) o CON escaneo (el de siempre). Lo único que se sigue
-- prohibiendo: un escaneo sin fecha de firma, que no significa nada.
alter table contratos_generados drop constraint if exists contrato_firma_coherente;
alter table contratos_generados add constraint contrato_firma_coherente check (
  (fecha_firma is null) = (registrado_por is null)
  and (storage_path is null or fecha_firma is not null)
);


-- ── B · fn_confirmar_mi_firma_contrato: confirmar ES firmar, la primera vez ──
-- Cuerpo vigente: 0406, copiado literal salvo lo marcado CAMBIO 0430. Misma
-- firma (un parámetro): `create or replace` basta.
create or replace function fn_confirmar_mi_firma_contrato(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo            uuid;
  v_imagen        text;
  v_dueno         uuid;
  v_anulado       timestamptz;
  -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩
  v_fecha_previa  date;
  v_tipo          text;
  v_nota          text := '';
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ se trae también `fecha_firma` y `tipo`: hace falta
  -- saber si esta confirmación es la PRIMERA (la que va a fechar el contrato)
  -- y qué tipo es (para decidir si corresponde recalcular su vencimiento).
  select persona_id, anulado_at, fecha_firma, tipo
    into v_dueno, v_anulado, v_fecha_previa, v_tipo
    from contratos_generados where id = p_contrato_id;
  if v_dueno is null then raise exception 'No se encontró ese contrato.'; end if;
  if v_dueno <> v_yo then raise exception 'Ese contrato no es tuyo.'; end if;
  if v_anulado is not null then raise exception 'Ese contrato está anulado.'; end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a Mi perfil → Firma antes de confirmar.';
  end if;

  -- La constancia primero (0406): reconfirmar con otra firma no debe borrar
  -- de qué imagen era ni de qué día la anterior.
  insert into confirmaciones_firma_contrato (contrato_id, persona_id, imagen)
  values (p_contrato_id, v_yo, v_imagen);

  -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ La primera confirmación digital fecha el contrato.
  -- `coalesce` protege una `fecha_firma` que ya exista —de una confirmación
  -- digital anterior, o de un escaneo que subió DO—: reconfirmar (0406) sigue
  -- sirviendo para corregir la IMAGEN de tu firma, nunca para volver a fechar
  -- el contrato.
  update contratos_generados
     set firma_persona = v_imagen,
         firma_persona_confirmada_at = now(),
         fecha_firma = coalesce(fecha_firma, fn_hoy_lima()),
         registrado_por = coalesce(registrado_por, v_yo)
   where id = p_contrato_id;

  -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ Solo la PRIMERA vez (v_fecha_previa era null): esto
  -- es justo lo que hasta ahora solo disparaba subir un escaneo
  -- (`fn_contrato_registrar`) — recalcular hasta cuándo vale el vencimiento
  -- de esta persona (0287/0312/0333/0347) y dejar constancia en su historial.
  -- Sin esto, un contrato firmado solo de forma digital nunca actualizaría
  -- `personas.fecha_fin_contrato`, y el aviso de vencimiento y el riesgo de
  -- desnaturalización (art. 77) seguirían mirando el contrato anterior.
  if v_fecha_previa is null then
    if v_tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
      v_nota := fn_contrato_refrescar_vencimiento(v_yo, 'Contrato firmado — autoservicio digital');
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_yo, 'contrato_firmado', null,
       v_tipo || ' · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
       'Firma digital confirmada en /mio/contrato, sin escaneo' || v_nota);
  end if;
end;
$$;
-- Sin GRANT nuevo: la firma no cambió, y ya estaba concedida a `authenticated`
-- desde la 0402/0406.


-- ── C · fn_contrato_registrar: el candado y el escaneo miran fecha_firma ────
-- Cuerpo vigente: 0388, copiado literal salvo lo marcado CAMBIO 0430. Misma
-- firma (13 parámetros): `create or replace` basta.
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
  p_datos_formulario      jsonb   default null,
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
    -- (sin cambios desde la 0388 — ver esa migración para el porqué completo.)

    -- El archivo tiene que ser EL DE ESTE CONTRATO.
    if p_storage_path !~ ('^contratos/' || p_id::text || '\.') then
      raise exception 'La ruta del escaneo no corresponde a este contrato.';
    end if;

    -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ `coalesce`, no un `update` a ciegas: este contrato
    -- puede llegar aquí YA firmado por autoservicio digital (0430), y adjuntar
    -- un escaneo después es un archivo de respaldo, no una nueva firma. Sin
    -- el `coalesce`, subir el escaneo habría corrido la fecha legal de firma
    -- hacia adelante en silencio.
    update contratos_generados
       set storage_path   = p_storage_path,
           fecha_firma    = coalesce(fecha_firma, p_fecha_firma),
           registrado_por = coalesce(registrado_por, v_yo)
     where id = p_id;

    -- La fecha de vencimiento se mueve recién con la firma puesta (sin
    -- cambios desde la 0312/0333/0347 — ver esas migraciones).
    if r.tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
      v_nota := fn_contrato_refrescar_vencimiento(
                  r.persona_id, 'Contrato firmado — generador de contratos');
    end if;

    -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ El mensaje distingue «esto lo firma» de «esto solo
    -- archiva un escaneo de respaldo de algo que ya estaba firmado».
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'contrato_firmado', null,
       r.tipo || ' · ' || case
         when r.fecha_firma is null then 'firmado el ' || p_fecha_firma::text
         else 'escaneo de respaldo adjuntado (ya firmado digitalmente el ' || r.fecha_firma::text || ')'
       end,
       v_yo,
       case
         when r.fecha_firma is null then 'Escaneo del contrato firmado registrado' || v_nota
         else 'Escaneo adjuntado como respaldo de un contrato ya firmado por autoservicio digital'
       end);

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

  -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ CANDADO 1 · un solo documento SIN FIRMAR por tipo.
  -- Antes medía `storage_path is null» («sin escaneo»). Con la firma digital
  -- (0430), un contrato puede estar firmado y vigente SIN escaneo — medido
  -- así, ese contrato ya firmado se seguía contando como «borrador sin
  -- firmar» y bloqueaba generar uno nuevo del mismo tipo (p. ej. una
  -- renovación) aunque el anterior ya estuviera firmado. El criterio real de
  -- «sin firmar» siempre fue `fecha_firma is null` — es el mismo que ya usa
  -- `fn_contrato_firmado_vigente_de` (0312) para decidir cuál es el vigente.
  if exists (
    select 1 from contratos_generados c
     where c.persona_id  = p_persona_id
       and c.tipo        = p_tipo
       and c.anulado_at  is null
       and c.fecha_firma is null
  ) then
    raise exception 'Esa persona ya tiene un documento de ese tipo sin firmar. Edítalo o anúlalo: no se generan dos.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0388 ⇩⇩⇩ CANDADO 2 · nada de periodos pisados (sin cambios).
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
-- Sin GRANT nuevo: misma firma que ya estaba concedida a `authenticated`.


-- ── D · fn_contrato_editar: la línea que no se cruza mira fecha_firma ───────
-- Cuerpo vigente: 0388, copiado literal salvo lo marcado CAMBIO 0430. Misma
-- firma (8 parámetros): `create or replace` basta.
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
  -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ LA LÍNEA QUE NO SE CRUZA, medida contra `fecha_firma`
  -- y no contra `storage_path`: con la firma digital (0430), un contrato
  -- firmado sin escaneo pasaba antes esta guarda y se podía seguir editando
  -- por detrás — exactamente lo que esta línea existe para impedir.
  if r.fecha_firma is not null then
    raise exception 'Ese contrato ya está firmado: no se edita. Usa un adendum, o anúlalo con su motivo.';
  end if;

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

  -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩ CANDADO 2, versión indulgente: solo contra lo YA
  -- FIRMADO, medido con `fecha_firma` en vez de `storage_path` — mismo motivo
  -- que arriba.
  if p_tipo <> 'adendum' and exists (
    select 1 from contratos_generados c
     where c.persona_id      = r.persona_id
       and c.id             <> r.id
       and c.anulado_at      is null
       and c.fecha_firma     is not null
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
-- Sin GRANT nuevo: misma firma que ya estaba concedida a `authenticated`.


-- ── E · fn_set_fin_contrato se abre un núcleo interno, sin el permiso ───────
-- EL PROBLEMA QUE ESTO CIERRA, medido al probar la parte B: `fn_confirmar_
-- mi_firma_contrato` corre como la propia colaboradora, y ella no es
-- admin/líder. `fn_contrato_refrescar_vencimiento` (llamado desde B, igual
-- que ya lo llama `fn_contrato_registrar`) intenta `fn_set_fin_contrato`, que
-- SIEMPRE exige `fn_es_admin_o_lider()` — con razón: es una RPC concedida
-- directa a `authenticated`, con `p_fecha` libre, así que sin ese guardián
-- cualquiera podría mover el vencimiento de cualquier contrato al valor que
-- quisiera. La firma digital de su propio contrato quedaba bloqueada al medio
-- camino: `fecha_firma` sí se ponía, pero `personas.fecha_fin_contrato` nunca
-- se actualizaba, y el aviso de vencimiento y el riesgo de desnaturalización
-- (art. 77) se habrían quedado mirando el contrato anterior para siempre.
--
-- La salida NO es agregarle a `fn_set_fin_contrato` un parámetro que salte el
-- permiso: esa función sigue concedida a `authenticated`, así que un parámetro
-- así sería alcanzable por cualquiera con solo nombrarlo en la llamada — el
-- mismo agujero que se quiere evitar, con un paso más.
--
-- La salida es separar EL PERMISO de EL MECANISMO. El mecanismo (escribir y
-- auditar) pasa a un núcleo que NO se concede a `authenticated` —solo lo
-- llaman otras funciones `security definer`—, así que nunca es alcanzable
-- desde un cliente. `fn_set_fin_contrato` seguirá siendo la única puerta con
-- `p_fecha` libre, y sigue exigiendo admin/líder como siempre.
-- `fn_contrato_refrescar_vencimiento` (que ya era interna, sin GRANT a
-- `authenticated` desde la 0312) llama al núcleo directo: su `p_fecha` nunca
-- viene de quien pregunta, siempre sale de `fn_contrato_firmado_vigente_de`
-- —el mismo criterio de «un cálculo seguro puede escribir un campo sensible
-- sin ser admin, mientras el VALOR no lo elija quien llama» que ya usa este
-- repositorio para `fn_confirmar_mi_declaracion_ruta` con el monto de la
-- movilidad.
create or replace function fn_set_fin_contrato_nucleo(p_persona_id uuid, p_fecha date, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  date;
  v_estado text;
  v_quien  uuid;
begin
  select fecha_fin_contrato, estado into v_antes, v_estado from personas where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;

  if v_estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva: su contrato ya terminó, no hay término que prever.';
  end if;

  if v_antes is not distinct from p_fecha then
    return;   -- nada que hacer, y así no se ensucia la auditoría
  end if;

  update personas set fecha_fin_contrato = p_fecha where id = p_persona_id;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Inicia sesión con tu usuario.';
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.fecha_fin_contrato',
          to_char(v_antes, 'YYYY-MM-DD'), to_char(p_fecha, 'YYYY-MM-DD'),
          coalesce(nullif(trim(p_motivo), ''),
                   case when p_fecha is null
                        then 'Se quita la fecha de término: el contrato continúa.'
                        else 'Se fija la fecha de término prevista del contrato.' end),
          v_quien);
end;
$$;
comment on function fn_set_fin_contrato_nucleo(uuid, date, text) is
  'El mecanismo de fn_set_fin_contrato, sin el permiso — lo cierra quien la '
  'llama. NUNCA concedida a authenticated (0430): solo fn_set_fin_contrato '
  '(tras exigir admin/lider) y fn_contrato_refrescar_vencimiento (cuyo '
  'p_fecha siempre sale de fn_contrato_firmado_vigente_de, nunca de quien '
  'pregunta) la invocan.';
revoke all on function fn_set_fin_contrato_nucleo(uuid, date, text) from public, anon, authenticated;

-- Cuerpo vigente: 0144, con el mecanismo movido al núcleo de arriba. Misma
-- firma: `create or replace` basta, y el GRANT a `authenticated` sigue igual
-- —lo sigue protegiendo el `if` de adentro, intacto.
create or replace function fn_set_fin_contrato(
  p_persona_id uuid,
  p_fecha      date,          -- null = se borra (el contrato se renovó)
  p_motivo     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Guard null-safe: un null no pasa como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede fijar la fecha de término de un contrato.';
  end if;

  perform fn_set_fin_contrato_nucleo(p_persona_id, p_fecha, p_motivo);
end;
$$;

-- Cuerpo vigente: 0347, con un solo cambio marcado CAMBIO 0430: las dos
-- llamadas a `fn_set_fin_contrato` pasan a `fn_set_fin_contrato_nucleo` — el
-- permiso ya no aplica acá (nunca debió bloquear a quien firma su propio
-- contrato), y el valor que se escribe sigue siendo el mismo de siempre:
-- el de `fn_contrato_firmado_vigente_de`, nunca uno libre.
create or replace function fn_contrato_refrescar_vencimiento(
  p_persona_id   uuid,
  p_motivo       text,
  p_puede_borrar boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r      contratos_generados%rowtype;
  v_activa boolean;
begin
  select (estado = 'activo') into v_activa from personas where id = p_persona_id;
  if v_activa is not true then
    return ' · su fecha de vencimiento no se tocó: la persona ya no está activa';
  end if;

  v_r := fn_contrato_firmado_vigente_de(p_persona_id);

  if v_r.id is not null then
    -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩
    perform fn_set_fin_contrato_nucleo(p_persona_id, v_r.fecha_fin, p_motivo);
    if v_r.fecha_fin is not null then
      return ' · su vencimiento queda en ' || to_char(v_r.fecha_fin, 'DD/MM/YYYY')
             || ', el del contrato firmado más reciente';
    else
      return ' · queda sin fecha de vencimiento: su contrato firmado más reciente es indefinido';
    end if;
  elsif p_puede_borrar is true then
    -- ⇩⇩⇩ CAMBIO 0430 ⇩⇩⇩
    perform fn_set_fin_contrato_nucleo(p_persona_id, null, p_motivo);
    return ' · no queda ningún contrato firmado: su vencimiento queda sin fijar';
  else
    return '';
  end if;
end;
$$;
-- Sin GRANT nuevo en ninguna de las tres: ninguna cambió a quién se concede.


-- ── F · Backfill: lo ya confirmado digitalmente pasa a contar como firmado ──
-- Sin esto, quien ya había confirmado su firma ANTES de esta migración (como
-- Fernanda Espinoza, el caso que la motivó) seguiría viendo «Pendiente de
-- firma» hasta volver a confirmar. Por persona y no en un solo `update`
-- masivo: cada una necesita además su propio recálculo de vencimiento.
do $$
declare
  v_persona uuid;
  v_admin   uuid;
  v_auth    uuid;
  v_cuantas int;
begin
  select count(distinct persona_id) into v_cuantas from contratos_generados
   where firma_persona_confirmada_at is not null and fecha_firma is null;

  if v_cuantas = 0 then
    raise notice '0430 · no hay nada que rellenar: nadie tiene la firma confirmada sin fecha.';
    return;
  end if;

  -- EL BACKFILL NECESITA UN AUTOR, Y EN EL SQL EDITOR NO HAY NINGUNO.
  --
  -- El bucle de abajo llama a fn_contrato_refrescar_vencimiento, que acaba en
  -- fn_set_fin_contrato_nucleo, que audita el cambio de fecha_fin_contrato en
  -- `correcciones_auditoria` — y esa tabla tiene `corregido_por` NOT NULL con
  -- FK a personas. El núcleo lo resuelve con fn_persona_actual_id(), o sea
  -- auth.uid(), que en el SQL Editor es NULL porque ahí no hay sesión. Sin
  -- esto, el `raise exception 'No puedo identificar quién hace el cambio…'`
  -- salta a la primera persona del bucle y, como todo el archivo se pega
  -- dentro de una transacción, ABORTA LA MIGRACIÓN ENTERA.
  --
  -- Medido contra producción el 2026-09-15: hay 7 filas que entran a este
  -- bucle, las 7 de gente activa y las 7 con una fecha que de verdad cambia,
  -- así que el bucle se ejecuta seguro y el fallo era seguro también. No es
  -- un caso de borde.
  --
  -- El criterio del autor NO se inventa aquí: se copia de la 0176, que se topó
  -- con lo mismo y lo resolvió tomando el admin activo más antiguo, y
  -- deteniéndose si no hay ninguno. Se le agrega una condición que la 0176 no
  -- necesitaba: que ese admin TENGA usuario (`auth_user_id`), porque lo que se
  -- siembra es la sesión, no el id de persona. El `set_config` es
  -- transaction-local (tercer argumento `true`), así que se deshace solo al
  -- terminar y no deja la sesión de nadie suplantada.
  select p.id, p.auth_user_id into v_admin, v_auth
    from personas p
   where p.rol = 'admin' and p.estado = 'activo' and p.auth_user_id is not null
   order by p.fecha_ingreso
   limit 1;

  if v_admin is null then
    raise exception '0430 · hay % persona(s) por rellenar pero ningun admin activo con usuario que firme el rastro. No se toca nada.', v_cuantas;
  end if;

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  raise notice '0430 · rellenando % persona(s); el rastro queda a nombre del admin activo mas antiguo.', v_cuantas;

  for v_persona in
    select distinct persona_id from contratos_generados
     where firma_persona_confirmada_at is not null and fecha_firma is null
  loop
    update contratos_generados
       set fecha_firma    = (firma_persona_confirmada_at at time zone 'America/Lima')::date,
           registrado_por = persona_id
     where persona_id = v_persona
       and firma_persona_confirmada_at is not null
       and fecha_firma is null;

    perform fn_contrato_refrescar_vencimiento(
      v_persona, 'Backfill de la migracion 0430: la firma digital ya confirmada pasa a contar como firma del contrato. Lo ejecuta la migracion, no el admin que figura como autor — el rastro exige un autor y se toma el admin activo mas antiguo.');
  end loop;
end $$;


insert into migraciones_aplicadas (numero, nombre)
values (430, 'el_contrato_se_firma_completo_de_forma_digital')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select prosrc like '%CAMBIO 0430%' from pg_proc
    where proname = 'fn_confirmar_mi_firma_contrato' and pronargs = 1)
    as confirmar_al_dia,
  (select prosrc like '%CAMBIO 0430%' from pg_proc
    where proname = 'fn_contrato_registrar' and pronargs = 13)
    as registrar_al_dia,
  (select prosrc like '%CAMBIO 0430%' from pg_proc
    where proname = 'fn_contrato_editar' and pronargs = 8)
    as editar_al_dia,
  (select count(*) from pg_proc where proname = 'fn_set_fin_contrato_nucleo') = 1
    as nucleo_puesto,
  (select prosrc like '%CAMBIO 0430%' from pg_proc
    where proname = 'fn_contrato_refrescar_vencimiento' and pronargs = 3)
    as refrescar_al_dia,
  (select count(*) from contratos_generados
    where firma_persona_confirmada_at is not null and fecha_firma is null) = 0
    as backfill_completo;
