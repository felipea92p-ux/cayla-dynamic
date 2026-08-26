-- ============================================================================
-- 0312 · Un contrato anulado no deja su fecha puesta, y un borrador viejo no
--        mueve el vencimiento hacia atrás
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1. Que un escaneo que falló a medias se pueda volver a subir. Hoy no se
--      puede: el bucket `contratos` tiene políticas de INSERT, SELECT y DELETE
--      pero NO de UPDATE, y la pantalla sube con `x-upsert: true`
--      (apps/web/lib/subir-archivo.ts), que Storage traduce a
--      `insert … on conflict (name, bucket_id) do update`. Esa sentencia pide
--      permiso de UPDATE en cuanto la ruta ya existe.
--
--      La ruta es determinista —`contratos/<id del contrato>.<ext>`—, así que
--      basta con que el archivo llegue al bucket y el RPC posterior falle (red,
--      sesión caducada, una excepción de la función) para que ese contrato
--      quede con su escaneo huérfano y SIN forma de volver a intentarlo. La
--      persona firmó el papel y el sistema no lo puede archivar nunca.
--
--   2. Que firmar un borrador viejo no mueva la fecha de vencimiento HACIA
--      ATRÁS. La 0287 mueve `personas.fecha_fin_contrato` al registrar la
--      firma, y solo comprueba que la persona esté activa. Nada obliga a anular
--      un borrador antes de generar otro, y la pantalla ofrece «Subir contrato
--      firmado» en todas las filas sin escaneo: firmar primero el nuevo y
--      después el viejo deja a la persona con el vencimiento del viejo.
--
--      Ese dato no es decorativo. `fn_contratos_desnaturalizados` (0231) lo usa
--      para avisar de quién marcó después de que su contrato venciera —el
--      riesgo del artículo 77 del TUO del D. Leg. 728—, y el tablero de
--      contratos ordena por él. Retrocederlo fabrica una desnaturalización que
--      no ocurrió, o esconde una que sí.
--
--   3. Que anular un contrato ya firmado devuelva la fecha de vencimiento a la
--      que corresponde. Hoy `fn_contrato_anular` solo marca la fila como
--      anulada: la persona se queda con el vencimiento de un documento que
--      acabamos de declarar nulo, y nada en el sistema lo delata.
--
-- QUÉ ASUME
--   La 0272 (`contratos_generados`, `fn_contrato_anular`, políticas del bucket),
--   la 0287 (`fn_contrato_registrar`, `fn_contratos_tablero`) y la 0144
--   (`fn_set_fin_contrato`, `personas.fecha_fin_contrato`).
--
--   md5 de partida, pedido a PRODUCCIÓN el 2026-08-26:
--     fn_contrato_registrar  07aaf0545ada5375ddcd8f96beb69f52  (4589 caracteres)
--     fn_contrato_anular     981f1160d962b1bd30e0642ac43e72e4  ( 960 caracteres)
--   Las dos con `definiciones = 1`: no hay sobrecargas que desambiguar.
--
-- POR QUÉ SE ELIGIÓ ASÍ
--
--   «DE DÓNDE VIENE LA FECHA» SE DEFINE UNA SOLA VEZ, Y ES LA PREGUNTA
--   CORRECTA. La primera versión de esta migración preguntaba «¿es el contrato
--   más reciente sin anular?», calcando el criterio de `fn_contratos_tablero`.
--   La revisión adversarial (61 agentes) la tumbó: esa pregunta la gana un
--   BORRADOR sin firmar generado después, y de ahí salían cuatro averías, todas
--   por el mismo agujero — entre ellas que anular el contrato firmado NO
--   devolvía la fecha, que es justo lo que esta migración promete arreglar.
--
--   La pregunta correcta es de cuál VIENE la fecha, y una fecha de vencimiento
--   solo puede venir de un papel firmado: un borrador no obliga a nadie. De ahí
--   `fn_contrato_firmado_vigente_de`, que usan las dos rutas — y por eso no
--   pueden discrepar, porque es literalmente la misma función.
--
--   Y EL RECÁLCULO TAMBIÉN SE DICE UNA SOLA VEZ. El otro hallazgo fue que el
--   código que decidía SI recalcular y el que recalculaba usaban criterios
--   distintos dentro de la misma función. Ahora los dos son
--   `fn_contrato_refrescar_vencimiento`.
--
--   AL ANULAR SE RECALCULA SIEMPRE, incluso si lo anulado era un borrador:
--   retirarlo puede destrabar la fecha de un contrato firmado que no había
--   llegado a propagarse. Pero solo anular un contrato FIRMADO puede llegar a
--   BORRAR la fecha — retirar un borrador no debe dejar sin vencimiento a quien
--   lo tenía puesto a mano desde antes de que el generador existiera. Si no
--   queda ningún contrato firmado, la fecha se borra en vez de dejarse: un
--   vencimiento heredado de un papel nulo es una certeza falsa, y el tablero ya
--   sabe decir «sin fecha de vencimiento», que es visible y accionable. El
--   valor anterior no se pierde — `fn_set_fin_contrato` lo deja en
--   `correcciones_auditoria` con su motivo.
--
--   Y NO SE CAE SI LA PERSONA YA NO ESTÁ ACTIVA. `fn_set_fin_contrato` corta
--   con «Esa persona ya está inactiva». Es la misma trampa que la 0287
--   documentó como su defecto 1: para quien cesó, la fecha de vencimiento no
--   significa nada, pero el papel sí — y anular no puede fallar por eso.
--
--   LA POLÍTICA DE UPDATE PIDE LO MISMO QUE LA DE INSERT, y no menos: quien
--   puede crear el objeto puede reemplazarlo. `with check` además de `using`
--   porque un UPDATE evalúa las dos: sin `with check`, se podría renombrar un
--   objeto para sacarlo del prefijo `contratos/`.
--
-- CÓMO SE REVIERTE
--   drop policy if exists contratos_update on storage.objects;
--   drop function if exists fn_contrato_refrescar_vencimiento(uuid, text, boolean);
--   drop function if exists fn_contrato_firmado_vigente_de(uuid);
--   Y volver a pegar la 0272 (`fn_contrato_anular`) y la 0287
--   (`fn_contrato_registrar`).
-- ============================================================================


-- ── A · El escaneo que falló a medias se puede volver a subir ──────────────
drop policy if exists contratos_update on storage.objects;
create policy contratos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'contratos'
    and split_part(name, '/', 1) = 'contratos'
    and fn_es_admin_o_lider() is true
  )
  with check (
    bucket_id = 'contratos'
    and split_part(name, '/', 1) = 'contratos'
    and fn_es_admin_o_lider() is true
  );


-- ── B · Una sola regla, y responde a la pregunta correcta ─────────────────
--
-- La primera versión de esta migración preguntaba «¿es el contrato más reciente
-- sin anular?». La revisión adversarial (61 agentes, 2026-08-26) la tumbó: esa
-- pregunta la gana un BORRADOR sin firmar generado después, y de ahí salían
-- cuatro averías distintas, todas por el mismo agujero.
--
--   · Anular el contrato FIRMADO teniendo un borrador nuevo en pie no devolvía
--     la fecha — que es exactamente lo que esta migración promete arreglar.
--   · Firmar un contrato mientras había un borrador más nuevo no movía la fecha
--     NUNCA, ni siquiera siendo el único contrato firmado que existe.
--   · Y si luego se descartaba ese borrador, la fecha ya no volvía sola.
--
-- La pregunta correcta no es cuál se generó al final: es DE CUÁL VIENE LA
-- FECHA. Y esa fecha solo puede venir de un papel firmado — un borrador no
-- obliga a nadie. Así que la regla es una sola, la usan las dos rutas, y no
-- pueden discrepar porque es literalmente la misma función.
create or replace function fn_contrato_firmado_vigente_de(p_persona_id uuid)
returns contratos_generados
language sql
stable
security definer
set search_path = public
as $$
  select c.*
    from contratos_generados c
   where c.persona_id = p_persona_id
     and c.anulado_at is null
     and c.fecha_firma is not null
   -- Los tres desempates NO son adorno. `generado_at` es `now()`, que dentro de
   -- una misma transacción vale lo mismo para todas las filas: dos contratos
   -- generados de una sola vez empatan, y sin desempate «el más reciente» lo
   -- decidía el orden físico de la tabla. Lo destapó la prueba pgTAP de esta
   -- migración, que corre entera dentro de una transacción.
   --
   -- El criterio dice lo mismo que diría una persona: manda el que empieza
   -- después, y a igualdad, el que termina después.
   order by c.generado_at desc, c.fecha_inicio desc, c.fecha_fin desc, c.id desc
   limit 1;
$$;

comment on function fn_contrato_firmado_vigente_de(uuid) is
  'El contrato del que viene la fecha de vencimiento de esa persona: el mas '
  'reciente FIRMADO y sin anular. Un borrador no obliga a nadie, asi que no '
  'gobierna ninguna fecha. La usan fn_contrato_registrar y fn_contrato_anular, '
  'y por eso no pueden discrepar.';

-- Sin grant a `authenticated`, y a propósito. Nadie la llama desde el
-- navegador: sus dos usos son internos, dentro de funciones que ya tienen su
-- propio guard. Concederla abriría por RPC lo que la 0292 cerró — devolver la
-- fila entera de un contrato de CUALQUIER persona, saltándose la RLS de
-- `contratos_generados` por ser SECURITY DEFINER.
revoke execute on function fn_contrato_firmado_vigente_de(uuid) from public;


-- ── B2 · Y el recálculo también se dice una sola vez ───────────────────────
-- Registrar una firma y anular un contrato hacían el mismo cálculo con dos
-- códigos distintos, y ese fue el otro hallazgo: el que decidía SI recalcular
-- usaba un criterio y el que recalculaba usaba otro. Ahora es una función.
--
-- `p_puede_borrar` existe por un caso concreto: retirar un BORRADOR no debe
-- poder dejar sin fecha a quien la tenía puesta a mano desde antes de que el
-- generador existiera. Solo anular un contrato FIRMADO puede llegar a borrarla.
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
    -- `fn_set_fin_contrato` corta con «ya está inactiva». Para quien cesó la
    -- fecha de vencimiento no significa nada, pero el papel sí: registrar o
    -- anular no pueden fallar por esto. Es el defecto 1 que documentó la 0287.
    return ' · su fecha de vencimiento no se tocó: la persona ya no está activa';
  end if;

  v_r := fn_contrato_firmado_vigente_de(p_persona_id);

  if v_r.id is not null then
    perform fn_set_fin_contrato(p_persona_id, v_r.fecha_fin, p_motivo);
    return ' · su vencimiento queda en ' || to_char(v_r.fecha_fin, 'DD/MM/YYYY')
           || ', el del contrato firmado más reciente';
  elsif p_puede_borrar is true then
    perform fn_set_fin_contrato(p_persona_id, null, p_motivo);
    return ' · no queda ningún contrato firmado: su vencimiento queda sin fijar';
  else
    return '';
  end if;
end;
$$;

revoke execute on function fn_contrato_refrescar_vencimiento(uuid, text, boolean) from public;


-- ── C · Firmar un borrador viejo no mueve el vencimiento hacia atrás ───────
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
    -- ⇩⇩⇩ CAMBIO 0312 ⇩⇩⇩ LA FECHA SE RECALCULA, NO SE ESCRIBE A CIEGAS.
    -- Antes se le ponía la fecha DE ESTE contrato sin más. Firmar un borrador
    -- viejo después de haber firmado el nuevo movía el vencimiento HACIA ATRÁS,
    -- y ese es el dato que `fn_contratos_desnaturalizados` usa para avisar del
    -- riesgo del artículo 77: retrocederlo fabrica una desnaturalización que no
    -- ocurrió, o esconde una que sí.
    --
    -- Se recalcula DESPUÉS del update de arriba, así que el contrato que se
    -- acaba de firmar ya cuenta como firmado y compite en igualdad. Si es el
    -- más reciente firmado, la fecha es la suya; si no, gana el otro y la suya
    -- no toca nada. Nunca borra: acaba de aparecer un contrato firmado.
    if r.tipo in ('nuevo', 'renovacion', 'adendum') then
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
  if p_tipo not in ('nuevo', 'renovacion', 'adendum') then
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
  if p_fecha_inicio is null or p_fecha_fin is null or p_fecha_fin <= p_fecha_inicio then
    raise exception 'Las fechas del contrato son inválidas.';
  end if;
  if p_documento_html is null or btrim(p_documento_html) = '' then
    raise exception 'Falta el texto del contrato.';
  end if;

  insert into contratos_generados (
    persona_id, tipo, cargo, sede_id, remuneracion_mensual,
    fecha_inicio, fecha_fin, horas_semanales, documento_html, generado_por
  ) values (
    p_persona_id, p_tipo, trim(p_cargo), p_sede_id, p_remuneracion_mensual,
    p_fecha_inicio, p_fecha_fin, p_horas_semanales, p_documento_html, v_yo
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

-- ── D · Anular devuelve la fecha de vencimiento a la que corresponde ───────
create or replace function fn_contrato_anular(p_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r        contratos_generados%rowtype;
  v_nota   text := '';
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional anula contratos.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se anula.';
  end if;

  select * into r from contratos_generados where id = p_id;
  if not found then raise exception 'Ese contrato no existe.'; end if;
  if r.anulado_at is not null then raise exception 'Ese contrato ya estaba anulado.'; end if;

  -- ⇩⇩⇩ CAMBIO 0312 ⇩⇩⇩ ¿DE ESTE CONTRATO VENÍA LA FECHA?
  -- Se pregunta ANTES de anularlo: después ya no sería el firmado vigente y la
  -- respuesta sería siempre que no.
  if r.fecha_firma is not null and (fn_contrato_firmado_vigente_de(r.persona_id)).id = p_id then
    v_nota := ' · era el contrato firmado vigente';
  end if;

  update contratos_generados
     set anulado_at = now(), anulado_por = fn_persona_actual_id(), anulado_motivo = trim(p_motivo)
   where id = p_id;

  -- ⇩⇩⇩ CAMBIO 0312 ⇩⇩⇩ Y LA FECHA SE RECALCULA SIEMPRE, NO SOLO A VECES.
  -- Antes, anular solo marcaba la fila: la persona conservaba el vencimiento de
  -- un documento declarado nulo, y nada lo delataba.
  --
  -- Se recalcula aunque el anulado fuera un BORRADOR, porque retirar un
  -- borrador también puede cambiar quién manda — la revisión encontró un caso
  -- donde firmar con un borrador pendiente y descartarlo después dejaba a la
  -- persona sin fecha para siempre.
  --
  -- Pero solo anular un contrato FIRMADO puede llegar a BORRARLA: retirar un
  -- borrador no debe dejar sin fecha a quien la tenía puesta a mano desde antes
  -- de que el generador existiera. El valor anterior nunca se pierde —
  -- `fn_set_fin_contrato` lo deja en `correcciones_auditoria` con su motivo.
  v_nota := v_nota || fn_contrato_refrescar_vencimiento(
              r.persona_id,
              'Contrato anulado — se recalcula desde el firmado vigente',
              r.fecha_firma is not null);

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id, 'contrato_anulado',
     r.tipo || ' · generado el ' || r.generado_at::date::text, 'anulado',
     fn_persona_actual_id(), trim(p_motivo) || v_nota);
end;
$$;


-- ── E · El rastro ──────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (312, 'un_contrato_anulado_no_deja_su_fecha_puesta')
on conflict (numero) do nothing;


-- ── F · Comprobación ───────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado de la
-- última consulta. Todo tiene que salir `true`.
select
  (select count(*) from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'contratos_update') = 1        as se_puede_reemplazar_un_escaneo,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_contrato_firmado_vigente_de', 'fn_contrato_refrescar_vencimiento')) = 2
                                                      as una_sola_puerta_para_la_fecha,
  position('CAMBIO 0312' in (select p.prosrc from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_contrato_registrar')) > 0
                                                      as registrar_ya_no_retrocede_la_fecha,
  position('CAMBIO 0312' in (select p.prosrc from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_contrato_anular')) > 0
                                                      as anular_ya_devuelve_la_fecha,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_contrato_registrar', 'fn_contrato_anular')) = 2
                                                      as sin_sobrecargas_duplicadas,
  (select count(*) from migraciones_aplicadas where numero = 312) = 1
                                                      as quedo_el_rastro;
