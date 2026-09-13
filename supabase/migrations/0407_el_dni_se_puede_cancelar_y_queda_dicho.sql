-- ============================================================================
-- 0407 — El DNI se puede cancelar, y queda dicho quién y por qué
-- ============================================================================
--
-- QUÉ PROMETE
--   Desarrollo Organizacional puede retirar de la ficha las dos fotos del DNI
--   de una persona, dejando constancia de quién lo hizo y por qué. La función
--   limpia las dos columnas y DEVUELVE las rutas que tenía, para que quien la
--   llama borre también los archivos del almacén — cosa que el SQL no puede
--   hacer solo (ver POR QUÉ DEVUELVE LAS RUTAS).
--
-- EL HUECO QUE CIERRA
--   La pantalla que pide el DNI muestra, palabra por palabra, que la persona
--   puede ejercer sus derechos de «acceso, rectificación, cancelación y
--   oposición» (Ley N.° 29733, y el texto que la 0404 guarda como constancia).
--   Hasta hoy la CANCELACIÓN no tenía mecanismo: la 0401 congela las rutas ya
--   aprobadas contra update y delete para todos salvo admin/líder, y ninguna
--   pantalla del repositorio permitía borrarlas — ni a DO. La promesa estaba
--   escrita y no se podía cumplir sin entrar a la consola de Supabase a mano.
--
-- QUÉ NO HACE, Y ES DELIBERADO
--   - No lo hace la propia persona desde «Lo mío». La cancelación de un dato
--     que sustenta una relación laboral no es automática: hay obligaciones de
--     conservación (planilla, SUNAT) que pueden obligar a conservarlo mientras
--     dure el vínculo y su plazo posterior. Quién decide eso es DO, no una
--     migración. Y el camino ya está escrito en el propio texto que la persona
--     acepta: «escribiendo a info@cayla.pe». Esto le da a DO la herramienta
--     para responder a ese correo; no cambia quién decide.
--   - No bloquea el borrado según el estado de la persona (activa, cesada,
--     dentro o fuera del plazo de conservación). Sería meter política de
--     retención en un `if`, y esa decisión es de DO con su contador. Lo que sí
--     hace es exigir un motivo escrito, que es donde esa decisión queda dicha.
--   - No borra la solicitud aprobada que trajo esas fotos. La solicitud es el
--     registro de que la persona las mandó y de que alguien las aprobó — un
--     hecho que ocurrió. Sus `rutas_adjuntas` quedarán apuntando a archivos que
--     ya no están, y eso es correcto: dice «hubo estas fotos, y se cancelaron».
--   - No toca `foto_dni_url` (la columna vieja de enlaces de Drive, 0061). Esa
--     no la escribe ni la lee esta familia de funciones.
--
-- POR QUÉ DEVUELVE LAS RUTAS EN VEZ DE BORRAR LOS ARCHIVOS
--   Los bytes de un archivo del almacén no viven en Postgres: `storage.objects`
--   solo guarda su metadato. Un `delete` desde SQL borraría la fila y dejaría
--   el archivo huérfano en el bucket — lo contrario de lo que una cancelación
--   promete. El borrado de verdad lo hace el cliente con `storage.remove()`,
--   que sí llega al archivo, y para eso necesita saber qué rutas eran.
--
--   Por eso el orden en la pantalla es: primero esta función (atómica: limpia
--   la ficha y escribe la auditoría, o no hace ninguna de las dos) y después el
--   borrado del almacén. Si lo segundo falla, la ficha ya no reclama tener un
--   DNI y la auditoría dice que se canceló; quedan los archivos, y la pantalla
--   lo dice para que se reintente. Al revés —borrar los archivos primero— un
--   fallo dejaría la ficha apuntando a la nada sin que nadie lo supiera.
--
-- QUÉ ASUME
--   0401 aplicada (las dos columnas `foto_dni_*_ruta` y las políticas del
--   bucket, que ya dejan borrar a admin/líder). `correcciones_auditoria`,
--   `fn_es_admin_o_lider`, `fn_persona_actual_id`.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_borrar_dni_de(uuid, text);
--   -- (no hay nada más: esta migración no crea tablas ni cambia columnas)
-- ============================================================================


create or replace function fn_borrar_dni_de(p_persona_id uuid, p_motivo text)
returns table (ruta text)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_anverso text;
  v_reverso text;
  v_quien   uuid := fn_persona_actual_id();
begin
  -- Identidad es de DO, en todo el sistema: la encargada de sede no entra acá
  -- (mismo criterio que `puedeVerIdentidad` en permisos.ts y que la 0405).
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder de Desarrollo Organizacional puede cancelar el DNI de una persona.';
  end if;
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Inicia sesión con tu usuario.';
  end if;

  -- El motivo es obligatorio y por eso mismo existe esta función: es donde
  -- queda escrito por qué se canceló — a petición de quién, con qué fecha, y
  -- bajo qué criterio de conservación. Sin eso, un borrado de un documento de
  -- identidad es indistinguible de un descuido.
  if coalesce(trim(p_motivo), '') = '' then
    raise exception 'El motivo es obligatorio: acá queda dicho por qué se canceló un documento de identidad.';
  end if;

  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;

  select foto_dni_anverso_ruta, foto_dni_reverso_ruta
    into v_anverso, v_reverso
    from datos_personales where persona_id = p_persona_id;

  if v_anverso is null and v_reverso is null then
    raise exception 'Esa persona no tiene fotos de DNI en su ficha; no hay nada que cancelar.';
  end if;

  update datos_personales
     set foto_dni_anverso_ruta = null,
         foto_dni_reverso_ruta = null
   where persona_id = p_persona_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values
    (p_persona_id, 'datos_personales.foto_dni',
     jsonb_build_object('foto_dni_anverso_ruta', v_anverso,
                        'foto_dni_reverso_ruta', v_reverso)::text,
     null, trim(p_motivo), v_quien);

  -- Las rutas que había, para que quien llamó borre los archivos. `unnest` con
  -- el filtro de nulos: una ficha puede tener una sola cara si algo quedó a
  -- medias, y devolver un null haría que el cliente pidiera borrar "nada".
  return query
    select r from unnest(array[v_anverso, v_reverso]) as r where r is not null;
end;
$fn$;

grant execute on function fn_borrar_dni_de(uuid, text) to authenticated;
revoke execute on function fn_borrar_dni_de(uuid, text) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (407, 'el_dni_se_puede_cancelar_y_queda_dicho')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*)::int from pg_proc where proname = 'fn_borrar_dni_de') = 1 as funcion_puesta,
  (select count(*)::int from information_schema.role_routine_grants
     where routine_name = 'fn_borrar_dni_de' and grantee = 'anon') = 0 as anon_no_puede;
