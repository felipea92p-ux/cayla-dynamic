-- ============================================================================
-- 0401 — Cada quien sube su DNI, y DO lo aprueba
-- ============================================================================
--
-- QUÉ PROMETE
--   Cualquier persona sube desde «Lo mío» las dos caras de su DNI —anverso y
--   reverso—, y esas fotos NO entran a su ficha hasta que Administración/DO
--   las aprueba. Vale igual para la primera vez que para una actualización:
--   mandar unas nuevas deja la propuesta anterior en «reemplazada» y el valor
--   real sigue siendo el último aprobado.
--
--   Y una vez aprobado, ese archivo deja de estar en manos de quien lo subió:
--   no se puede sobrescribir ni borrar salvo por un administrador.
--
-- QUÉ ASUME
--   La 0399 pegada: catalogo_campos_perfil, solicitudes_cambio_perfil, el
--   bucket privado `solicitudes-perfil` con sus cuatro políticas,
--   fn_snapshot_valor_actual, fn_crear_solicitud_perfil,
--   fn_aplicar_cambio_perfil, fn_solicitud_perfil_puede_escribir.
--   Más datos_personales (0061), correcciones_auditoria, fn_es_admin_o_lider()
--   y fn_persona_actual_id().
--
--   ⚠ Antes de pegar esto hay que comprobar que la 0399 esté aplicada:
--     select count(*) from catalogo_campos_perfil;   -- tiene que dar 11
--   Si da 0 o falla, la 0401 no tiene sobre qué apoyarse.
--
-- POR QUÉ SE COLGÓ DE LA 0399 EN VEZ DE HACER LO SUYO
--   La pregunta que responde esta migración —«el colaborador propone, DO
--   aprueba»— ya estaba respondida, con su tabla, su bandeja en /admin/bandeja,
--   su bucket privado y su prueba. Construir una segunda puerta para la misma
--   pregunta es exactamente lo que costó la 0297/0299 (dos sesiones creando
--   `fn_vacaciones_por_vencer` el mismo día, y el aviso dejando de mostrarse en
--   producción porque Postgres no sabía cuál llamar). Acá se agrega una fila al
--   catálogo y una rama a tres funciones; no se inventa un mecanismo nuevo.
--
-- POR QUÉ DOS COLUMNAS NUEVAS Y NO `foto_dni_url`
--   `datos_personales.foto_dni_url` existe desde la 0061 y guarda «enlaces de
--   Google Drive (por ahora)» —URLs absolutas, cargadas a mano, que ninguna
--   pantalla de este repo edita hoy—. Las columnas nuevas guardan otra cosa:
--   una RUTA dentro del bucket `solicitudes-perfil`, que solo significa algo
--   pasándola por `createSignedUrl`. Meter los dos significados en la misma
--   columna dejaría un campo cuyo valor hay que adivinar antes de usarlo. Por
--   eso se llaman `_ruta` y no `_url`, y por eso la vieja no se toca ni se
--   migra.
--
-- QUÉ NO HACE
--   - No toca `fn_set_datos_personales`. A propósito: esa función es un upsert
--     que REEMPLAZA las tres `foto_*_url` en cada llamada (ver el comentario en
--     admin/datos-personales/page.tsx). Si las rutas del DNI fueran parámetros
--     suyos, cada «Guardar ficha» las borraría, y además habría una segunda
--     forma de escribirlas sin pasar por la aprobación.
--   - No borra los archivos de solicitudes rechazadas ni reemplazadas. Ocupan
--     lugar y no se los apunta nadie; limpiarlos es otra decisión, y borrar
--     nunca es lo primero que hace este repo.
--   - No desbloquea las rutas de un DNI viejo cuando se aprueba uno nuevo: la
--     solicitud anterior sigue en «aprobado», así que sus dos archivos siguen
--     congelados. Son la prueba de qué se aprobó ese día.
--   - No agrega aviso por correo. Igual que la 0399: tocar
--     fn_alertas_email_pendientes exige el md5 de PRODUCCIÓN antes de escribir,
--     y esta sesión no tiene acceso a producción. «Solicitudes de perfil» ya
--     vive en /admin/bandeja y el aviso in-app no depende de esto.
--
-- CÓMO SE REVIERTE
--   -- 1) las políticas, a como las dejó la 0399 (sin el candado):
--   drop policy if exists solicitud_perfil_update on storage.objects;
--   create policy solicitud_perfil_update on storage.objects
--     for update to authenticated
--     using      (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name))
--     with check (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name));
--   drop policy if exists solicitud_perfil_delete on storage.objects;
--   create policy solicitud_perfil_delete on storage.objects
--     for delete to authenticated
--     using (bucket_id = 'solicitudes-perfil' and fn_solicitud_perfil_puede_escribir(name));
--   drop function if exists fn_solicitud_perfil_ruta_congelada(text);
--   drop index if exists idx_solicitudes_perfil_rutas;
--   -- 2) el campo del catálogo (las solicitudes ya creadas lo referencian, así
--   --    que primero hay que decidir qué hacer con ellas):
--   delete from catalogo_campos_perfil where campo = 'foto_dni';
--   alter table catalogo_campos_perfil drop column if exists en_formulario_generico;
--   -- 3) las columnas — OJO: se lleva por delante qué DNI tenía cada quien:
--   alter table datos_personales
--     drop column if exists foto_dni_anverso_ruta,
--     drop column if exists foto_dni_reverso_ruta;
--   -- 4) las tres funciones vuelven a su cuerpo de la 0399, copiándolo de
--   --    supabase/migrations/0399_el_colaborador_propone_do_aprueba.sql.
-- ============================================================================


-- ── A · Dónde vive el DNI aprobado ──────────────────────────────────────────
-- Dos columnas y no una sola con las dos rutas dentro: cada cara se muestra,
-- se reemplaza y se pierde por separado, y un `text[]` de dos elementos
-- obligaría a que cada lector se acuerde de que el [1] es el anverso.
alter table datos_personales
  add column if not exists foto_dni_anverso_ruta text,
  add column if not exists foto_dni_reverso_ruta text;

comment on column datos_personales.foto_dni_anverso_ruta is
  'Ruta dentro del bucket privado `solicitudes-perfil` de la cara del DNI que '
  'lleva la foto. La escribe SOLO fn_aplicar_cambio_perfil, al aprobarse una '
  'solicitud del campo `foto_dni` — nunca fn_set_datos_personales. Se lee con '
  'createSignedUrl; no es una URL.';
comment on column datos_personales.foto_dni_reverso_ruta is
  'Ruta dentro del bucket privado `solicitudes-perfil` de la cara del DNI que '
  'lleva la dirección. Mismas reglas que foto_dni_anverso_ruta.';


-- ── B · El catálogo aprende un campo más ────────────────────────────────────
-- `en_formulario_generico` existe porque el DNI tiene su propia pestaña en «Lo
-- mío», con sus dos recuadros y su vista previa. Si además siguiera saliendo
-- en el desplegable de «Cambiar mis datos», habría dos puertas para la misma
-- pregunta. Se resuelve con una columna y no con un `campo === 'foto_dni'`
-- escrito en la pantalla: la regla de la casa es que la lista de campos vive
-- en esta tabla y en ningún otro lado.
alter table catalogo_campos_perfil
  add column if not exists en_formulario_generico boolean not null default true;

comment on column catalogo_campos_perfil.en_formulario_generico is
  'false cuando el campo tiene su propia pantalla y no debe aparecer también '
  'en el desplegable genérico de «Cambiar mis datos» (hoy: foto_dni).';

insert into catalogo_campos_perfil
  (campo, etiqueta, requiere_documento, documento_sugerido, columnas, en_formulario_generico)
values
  ('foto_dni', 'Foto del DNI (ambos lados)', true,
   'Las dos caras del DNI vigente, legibles y completas',
   array['foto_dni_anverso_ruta','foto_dni_reverso_ruta'], false)
on conflict (campo) do update set
  etiqueta               = excluded.etiqueta,
  requiere_documento     = excluded.requiere_documento,
  documento_sugerido     = excluded.documento_sugerido,
  columnas               = excluded.columnas,
  en_formulario_generico = excluded.en_formulario_generico;


-- ── C · El «antes» de una solicitud de DNI ──────────────────────────────────
-- md5 de partida (cuerpo tal cual lo dejó la 0399):
--   fn_snapshot_valor_actual: 7dd7db9af1ce15da7dede1d10f5b39a2
--     length 1825 · octet_length 1831
--   Medido sobre el TEXTO de supabase/migrations/0399_*.sql, no contra
--   producción — esta sesión no tiene acceso al SQL Editor. Antes de pegar,
--   confirmarlo allá (la consulta está al pie de este archivo). Si no coincide,
--   parar: alguien reescribió esta función entre medias.
create or replace function fn_snapshot_valor_actual(p_persona_id uuid, p_campo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_p personas%rowtype;
  v_d datos_personales%rowtype;
begin
  select * into v_p from personas where id = p_persona_id;
  select * into v_d from datos_personales where persona_id = p_persona_id;
  -- v_d puede no existir todavía (fila nunca creada) — sus campos quedan null,
  -- que es el valor real: "no tiene nada guardado ahí".

  return case p_campo
    when 'celular' then jsonb_build_object('celular', v_d.celular)
    when 'direccion' then jsonb_build_object('direccion', v_d.direccion)
    when 'contacto_emergencia' then jsonb_build_object(
      'emergencia_nombre', v_d.emergencia_nombre,
      'emergencia_vinculo', v_d.emergencia_vinculo,
      'emergencia_telefono', v_d.emergencia_telefono)
    when 'estado_civil' then jsonb_build_object('estado_civil', v_d.estado_civil)
    when 'hijos_menores' then jsonb_build_object('hijos_menores', v_d.hijos_menores)
    when 'grado_instruccion' then jsonb_build_object('grado_instruccion', v_d.grado_instruccion)
    when 'discapacidad' then jsonb_build_object(
      'discapacidad', v_d.discapacidad, 'discapacidad_conadis', v_d.discapacidad_conadis)
    when 'cuenta_bancaria' then jsonb_build_object(
      'entidad_bancaria', v_d.entidad_bancaria, 'numero_cuenta', v_d.numero_cuenta)
    when 'cuspp' then jsonb_build_object('cuspp', v_d.cuspp)
    -- CAMBIO 0401: las dos rutas vigentes, para que la solicitud guarde de qué
    -- DNI se venía. No es decoración: si mañana hay que saber qué imagen tenía
    -- la ficha antes de una actualización, `valor_anterior` es el único sitio
    -- donde queda escrito.
    when 'foto_dni' then jsonb_build_object(
      'foto_dni_anverso_ruta', v_d.foto_dni_anverso_ruta,
      'foto_dni_reverso_ruta', v_d.foto_dni_reverso_ruta)
    -- 'nombre_dni' (datos_personales) — el nombre "como aparece en el DNI"
    -- para el T-Registro. NO es personas.nombres/apellidos, que es el nombre
    -- de sistema y esta feature nunca lo toca.
    when 'correccion_identidad' then jsonb_build_object(
      'documento', v_p.documento, 'nombre_dni', v_d.nombre_dni,
      'fecha_nacimiento', v_d.fecha_nacimiento, 'genero', v_d.genero)
    when 'familiar_nuevo' then '{}'::jsonb  -- siempre es un alta, no hay "antes"
    else '{}'::jsonb
  end;
end;
$fn$;

revoke all on function fn_snapshot_valor_actual(uuid, text) from public, anon, authenticated;


-- ── D · Crear la solicitud: las dos caras, y de tu carpeta ──────────────────
-- md5 de partida (cuerpo tal cual lo dejó la 0399):
--   fn_crear_solicitud_perfil: f7f9ec2ee558a0f3097fb82904397420
--     length 1741 · octet_length 1747
--
-- POR QUÉ LA COMPROBACIÓN VA ACÁ Y NO EN fn_validar_valor_propuesto
--   Esa función recibe (campo, valor) y no sabe de quién es la solicitud, así
--   que no puede decir si una ruta pertenece a la carpeta de quien pregunta.
--   Acá, en cambio, el bucle de arriba ya validó que TODA ruta adjunta empiece
--   por `solicitud/<mi persona_id>/`. Exigiendo que las dos caras estén entre
--   esas rutas, el permiso se comprueba una sola vez y de una sola manera —
--   en vez de tener dos comprobaciones parecidas que algún día divergirán.
create or replace function fn_crear_solicitud_perfil(
  p_campo           text,
  p_valor_propuesto jsonb,
  p_rutas_adjuntas  text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_persona uuid := fn_persona_actual_id();
  v_requiere_doc boolean;
  v_ruta text;
  v_id uuid;
  v_anverso text;   -- CAMBIO 0401
  v_reverso text;   -- CAMBIO 0401
begin
  if v_persona is null then
    raise exception 'Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.';
  end if;

  select requiere_documento into v_requiere_doc from catalogo_campos_perfil where campo = p_campo;
  if v_requiere_doc is null then
    raise exception 'Campo de perfil desconocido: %', p_campo;
  end if;

  perform fn_validar_valor_propuesto(p_campo, p_valor_propuesto);

  if v_requiere_doc and coalesce(array_length(p_rutas_adjuntas, 1), 0) = 0 then
    raise exception 'Este cambio exige adjuntar al menos un documento de sustento.';
  end if;

  foreach v_ruta in array p_rutas_adjuntas loop
    if v_ruta !~ ('^solicitud/' || v_persona::text || '/') then
      raise exception 'Uno de los archivos adjuntos no pertenece a tu carpeta.';
    end if;
  end loop;

  -- CAMBIO 0401: el DNI son DOS caras, y las dos tienen que venir además como
  -- adjuntos — que es lo que las hace visibles en /admin/bandeja para quien va
  -- a aprobarlas, y lo que ya las validó como "de tu carpeta" en el bucle de
  -- arriba. Sin este bloque se podría proponer como DNI la ruta del DNI de
  -- otra persona: el valor propuesto es jsonb libre y nadie más lo mira.
  if p_campo = 'foto_dni' then
    v_anverso := nullif(trim(coalesce(p_valor_propuesto->>'foto_dni_anverso_ruta', '')), '');
    v_reverso := nullif(trim(coalesce(p_valor_propuesto->>'foto_dni_reverso_ruta', '')), '');
    if v_anverso is null or v_reverso is null then
      raise exception 'Hacen falta las dos caras del DNI: el anverso y el reverso.';
    end if;
    if v_anverso = v_reverso then
      raise exception 'El anverso y el reverso no pueden ser la misma imagen.';
    end if;
    if not (p_rutas_adjuntas @> array[v_anverso, v_reverso]) then
      raise exception 'Las dos caras del DNI tienen que ir también como archivos adjuntos.';
    end if;
  end if;

  -- Reemplaza cualquier pendiente anterior sobre el mismo campo — nunca para
  -- familiar_nuevo (ver el índice único parcial, admite varias en paralelo).
  if p_campo <> 'familiar_nuevo' then
    update solicitudes_cambio_perfil
    set estado = 'reemplazada', resuelta_at = now(), resuelta_por = v_persona
    where persona_id = v_persona and campo = p_campo and estado = 'pendiente';
  end if;

  insert into solicitudes_cambio_perfil
    (persona_id, campo, valor_anterior, valor_propuesto, rutas_adjuntas)
  values
    (v_persona, p_campo, fn_snapshot_valor_actual(v_persona, p_campo), p_valor_propuesto, p_rutas_adjuntas)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Ya tienes una solicitud pendiente sobre ese campo. Espera a que se resuelva.';
end;
$fn$;

grant execute on function fn_crear_solicitud_perfil(text, jsonb, text[]) to authenticated;
revoke execute on function fn_crear_solicitud_perfil(text, jsonb, text[]) from public, anon;


-- ── E · Aplicar el DNI aprobado ─────────────────────────────────────────────
-- md5 de partida (cuerpo tal cual lo dejó la 0399):
--   fn_aplicar_cambio_perfil: fa4c181e8e5a8d640d83aac08c52378c
--     length 5448 · octet_length 5459
create or replace function fn_aplicar_cambio_perfil(p_solicitud_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s solicitudes_cambio_perfil%rowtype;
  v_quien uuid := fn_persona_actual_id();
  v_motivo text;
begin
  select * into v_s from solicitudes_cambio_perfil where id = p_solicitud_id;
  if not found then
    raise exception 'Esa solicitud no existe.';
  end if;

  v_motivo := 'Aprobado por solicitud de perfil — ver solicitudes_cambio_perfil.id=' || v_s.id;

  case v_s.campo
    when 'celular' then
      insert into datos_personales (persona_id, celular) values (v_s.persona_id, v_s.valor_propuesto->>'celular')
      on conflict (persona_id) do update set celular = excluded.celular;

    when 'direccion' then
      insert into datos_personales (persona_id, direccion) values (v_s.persona_id, v_s.valor_propuesto->>'direccion')
      on conflict (persona_id) do update set direccion = excluded.direccion;

    when 'contacto_emergencia' then
      insert into datos_personales (persona_id, emergencia_nombre, emergencia_vinculo, emergencia_telefono)
      values (v_s.persona_id, v_s.valor_propuesto->>'emergencia_nombre',
              v_s.valor_propuesto->>'emergencia_vinculo', v_s.valor_propuesto->>'emergencia_telefono')
      on conflict (persona_id) do update set
        emergencia_nombre = excluded.emergencia_nombre,
        emergencia_vinculo = excluded.emergencia_vinculo,
        emergencia_telefono = excluded.emergencia_telefono;

    when 'estado_civil' then
      insert into datos_personales (persona_id, estado_civil) values (v_s.persona_id, v_s.valor_propuesto->>'estado_civil')
      on conflict (persona_id) do update set estado_civil = excluded.estado_civil;

    when 'hijos_menores' then
      insert into datos_personales (persona_id, hijos_menores)
      values (v_s.persona_id, (v_s.valor_propuesto->>'hijos_menores')::boolean)
      on conflict (persona_id) do update set hijos_menores = excluded.hijos_menores;

    when 'grado_instruccion' then
      insert into datos_personales (persona_id, grado_instruccion)
      values (v_s.persona_id, v_s.valor_propuesto->>'grado_instruccion')
      on conflict (persona_id) do update set grado_instruccion = excluded.grado_instruccion;

    when 'discapacidad' then
      insert into datos_personales (persona_id, discapacidad, discapacidad_conadis)
      values (v_s.persona_id, (v_s.valor_propuesto->>'discapacidad')::boolean, v_s.valor_propuesto->>'discapacidad_conadis')
      on conflict (persona_id) do update set
        discapacidad = excluded.discapacidad, discapacidad_conadis = excluded.discapacidad_conadis;

    when 'cuenta_bancaria' then
      insert into datos_personales (persona_id, entidad_bancaria, numero_cuenta)
      values (v_s.persona_id, v_s.valor_propuesto->>'entidad_bancaria', v_s.valor_propuesto->>'numero_cuenta')
      on conflict (persona_id) do update set
        entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta;

    when 'cuspp' then
      insert into datos_personales (persona_id, cuspp)
      values (v_s.persona_id, nullif(upper(trim(v_s.valor_propuesto->>'cuspp')), ''))
      on conflict (persona_id) do update set cuspp = excluded.cuspp;

    -- CAMBIO 0401: las dos caras entran juntas. Deja fila en la auditoría igual
    -- que correccion_identidad, y por lo mismo: es un documento de identidad, y
    -- «quién aprobó qué DNI y cuándo» tiene que poder responderse sin abrir el
    -- almacén de archivos.
    when 'foto_dni' then
      insert into datos_personales (persona_id, foto_dni_anverso_ruta, foto_dni_reverso_ruta)
      values (v_s.persona_id,
              v_s.valor_propuesto->>'foto_dni_anverso_ruta',
              v_s.valor_propuesto->>'foto_dni_reverso_ruta')
      on conflict (persona_id) do update set
        foto_dni_anverso_ruta = excluded.foto_dni_anverso_ruta,
        foto_dni_reverso_ruta = excluded.foto_dni_reverso_ruta;

      insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
      values (v_s.persona_id, 'datos_personales.foto_dni',
              v_s.valor_anterior::text, v_s.valor_propuesto::text, v_motivo, v_quien);

    when 'correccion_identidad' then
      if v_s.valor_propuesto ? 'documento' then
        perform fn_set_documento(v_s.persona_id, v_s.valor_propuesto->>'documento', v_motivo);
      end if;
      if (v_s.valor_propuesto ? 'nombre_dni') or (v_s.valor_propuesto ? 'fecha_nacimiento') or (v_s.valor_propuesto ? 'genero') then
        insert into datos_personales (persona_id, nombre_dni, fecha_nacimiento, genero)
        values (v_s.persona_id,
                coalesce(v_s.valor_propuesto->>'nombre_dni', (select nombre_dni from datos_personales where persona_id = v_s.persona_id)),
                coalesce((v_s.valor_propuesto->>'fecha_nacimiento')::date, (select fecha_nacimiento from datos_personales where persona_id = v_s.persona_id)),
                coalesce(v_s.valor_propuesto->>'genero', (select genero from datos_personales where persona_id = v_s.persona_id)))
        on conflict (persona_id) do update set
          nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento, genero = excluded.genero;

        insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
        values (v_s.persona_id, 'datos_personales.correccion_identidad',
                v_s.valor_anterior::text, v_s.valor_propuesto::text, v_motivo, v_quien);
      end if;

    when 'familiar_nuevo' then
      perform fn_set_derechohabiente(
        null, v_s.persona_id,
        v_s.valor_propuesto->>'nombres', v_s.valor_propuesto->>'apellidos', v_s.valor_propuesto->>'vinculo',
        v_s.valor_propuesto->>'documento', (v_s.valor_propuesto->>'fecha_nacimiento')::date,
        false, false, v_motivo);

    else
      raise exception 'No sé cómo aplicar el campo: %', v_s.campo;
  end case;

  -- Tarea de seguimiento a planilla — solo para estos dos, y solo aquí (al
  -- aprobar), nunca al crear la solicitud.
  if v_s.campo in ('estado_civil', 'hijos_menores') then
    insert into seguimiento_planilla_por_solicitud (solicitud_id, persona_id, campo, descripcion)
    select v_s.id, v_s.persona_id, v_s.campo,
           'Revisar planilla — ' || pe.nombres || ' ' || pe.apellidos || ' — ' || c.etiqueta
    from personas pe, catalogo_campos_perfil c
    where pe.id = v_s.persona_id and c.campo = v_s.campo
    on conflict (solicitud_id) do nothing;
  end if;
end;
$fn$;

revoke all on function fn_aplicar_cambio_perfil(uuid) from public, anon, authenticated;


-- ── F · Un adjunto aprobado deja de ser de quien lo subió ───────────────────
--
-- EL AGUJERO QUE CIERRA
--   La 0399 deja que la propia persona escriba y borre dentro de su carpeta
--   `solicitud/<su id>/`, sin mirar el estado de la solicitud. Y la subida usa
--   `x-upsert: true` (ver lib/subir-archivo.ts), así que escribir de nuevo en
--   una ruta que ya existe la REEMPLAZA. Junto: después de que DO aprobó, quien
--   subió el archivo puede cambiar sus bytes por otros —o borrarlo— desde la
--   consola del navegador, y la ficha seguiría apuntando a esa misma ruta.
--
--   Mientras el valor aprobado era un texto (un celular, un CUSPP), eso era
--   feo pero no decisivo: el dato vivía en la tabla y el adjunto solo lo
--   sustentaba. Con el DNI el archivo ES el valor, así que sin este candado la
--   promesa «lo aprueba un administrador antes de guardarse» sería de interfaz
--   y no de base de datos — que es justo la distinción que la 0399 se tomó el
--   trabajo de cerrar en su punto E.
--
--   Se aplica a TODO adjunto de una solicitud aprobada, no solo a los del DNI:
--   el certificado CONADIS, la carátula de la cuenta y la partida de nacimiento
--   sustentan decisiones que ya se tomaron, y valen lo mismo.
--
-- LO QUE NO CIERRA
--   Un adjunto de una solicitud pendiente, rechazada o reemplazada sigue siendo
--   suyo, y está bien: todavía no sustenta ninguna decisión.
create index if not exists idx_solicitudes_perfil_rutas
  on solicitudes_cambio_perfil using gin (rutas_adjuntas);

create or replace function fn_solicitud_perfil_ruta_congelada(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from solicitudes_cambio_perfil
    where estado = 'aprobado' and rutas_adjuntas @> array[p_path]
  );
$$;

comment on function fn_solicitud_perfil_ruta_congelada(text) is
  'Verdadera si esta ruta del bucket `solicitudes-perfil` está citada por una '
  'solicitud ya APROBADA. Las políticas de update y delete la usan para que '
  'nadie reemplace ni borre un papel que Desarrollo Organizacional ya aprobó.';

grant execute on function fn_solicitud_perfil_ruta_congelada(text) to authenticated;

-- Las dos políticas que cambian. `insert` y `select` quedan como las dejó la
-- 0399: subir un archivo NUEVO y mirar los propios sigue igual de abierto.
--
-- `is not true` y no `not (...)`: la regla de la casa para todo guard, porque
-- un null no puede pasar como autorizado.
drop policy if exists solicitud_perfil_update on storage.objects;
create policy solicitud_perfil_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'solicitudes-perfil'
              and fn_solicitud_perfil_puede_escribir(name)
              and (fn_solicitud_perfil_ruta_congelada(name) is not true
                   or fn_es_admin_o_lider() is true))
  with check (bucket_id = 'solicitudes-perfil'
              and fn_solicitud_perfil_puede_escribir(name)
              and (fn_solicitud_perfil_ruta_congelada(name) is not true
                   or fn_es_admin_o_lider() is true));

drop policy if exists solicitud_perfil_delete on storage.objects;
create policy solicitud_perfil_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'solicitudes-perfil'
         and fn_solicitud_perfil_puede_escribir(name)
         and (fn_solicitud_perfil_ruta_congelada(name) is not true
              or fn_es_admin_o_lider() is true));


insert into migraciones_aplicadas (numero, nombre)
values (401, 'cada_quien_sube_su_dni_y_do_lo_aprueba')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*)::int from information_schema.columns
     where table_name = 'datos_personales'
       and column_name in ('foto_dni_anverso_ruta','foto_dni_reverso_ruta')) = 2 as las_dos_columnas,
  (select count(*)::int from catalogo_campos_perfil) as filas_catalogo,        -- 12
  (select en_formulario_generico from catalogo_campos_perfil where campo = 'foto_dni')
    is false as el_dni_no_sale_en_el_desplegable,
  (select count(*)::int from pg_proc where proname = 'fn_solicitud_perfil_ruta_congelada') as fn_candado,
  (select count(*)::int from pg_policies where tablename = 'objects' and schemaname = 'storage'
     and policyname like 'solicitud_perfil_%') = 4 as las_cuatro_politicas_siguen,
  (select prosrc like '%CAMBIO 0401%' from pg_proc where proname = 'fn_aplicar_cambio_perfil') as aplicar_al_dia,
  (select prosrc like '%CAMBIO 0401%' from pg_proc where proname = 'fn_crear_solicitud_perfil') as crear_al_dia,
  (select prosrc like '%CAMBIO 0401%' from pg_proc where proname = 'fn_snapshot_valor_actual') as snapshot_al_dia;

-- ── ANTES de pegar lo de arriba: el md5 de partida, contra PRODUCCIÓN ───────
-- Si alguno de los tres no coincide con el declarado en las secciones C, D y E,
-- PARAR: esta migración se escribió sobre un cuerpo que ya no es el vigente.
--
--   select proname, md5(prosrc), length(prosrc), octet_length(prosrc)
--     from pg_proc
--    where proname in ('fn_snapshot_valor_actual',
--                      'fn_crear_solicitud_perfil',
--                      'fn_aplicar_cambio_perfil');
--
-- Y si la longitud coincide pero el md5 no, mirar primero si es el caso
-- conocido de los comentarios: la mitad de las funciones de producción se
-- pegaron sin ellos (ver CLAUDE.md). `donde-vive.sh` da los dos md5.
