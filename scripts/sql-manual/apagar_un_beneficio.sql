-- ############################################################################
-- ####  ESTA SÍ ESCRIBE. Cambia lo que una persona devenga.                ####
-- ####                                                                     ####
-- ####  SOLO HAY QUE TOCAR LA LÍNEA QUE DICE  ⇦ CAMBIA ESTA LÍNEA          ####
-- ####  Está justo debajo del `declare`. Es una sola. El resto no se toca.  ####
-- ############################################################################
--
-- apagar_un_beneficio.sql — la excepción por persona, de la 0196
--
-- ── QUÉ SE PUEDE PONER ──────────────────────────────────────────────────────
--   v_busca      un trozo del apellido o del nombre. Si encaja con dos personas
--                se niega y te lo dice: nunca adivina.
--   v_beneficio  'grati', 'cts' o 'vacaciones'. Cualquier otra cosa revienta.
--   v_devenga    false = NO devenga · true = SÍ devenga
--                null  = vuelve al defecto de su tipo de vínculo (deshacer)
--   v_quien_soy  quién queda anotado como autor. Normalmente no se toca.
--
-- ── QUÉ HACE Y QUÉ NO ───────────────────────────────────────────────────────
--   Escribe la bandera y deja rastro en `correcciones_auditoria` con quién lo
--   hizo. NO toca ningún periodo ya pagado: las provisiones se recalculan en
--   vivo, así que cambia lo que se provisiona de aquí en adelante.
--
--   Y no le quita a nadie lo ya acumulado: apagar un beneficio deja de sumarlo.
--
-- ── POR QUÉ ESTE ARCHIVO NO LLEVA NINGÚN NOMBRE ESCRITO ─────────────────────
--   Porque quién devenga qué es un dato de una persona, y este repositorio no
--   guarda datos personales. El nombre lo pones tú y se queda en tu pantalla.
--
-- ── POR QUÉ SE EDITA UN SOLO SITIO ──────────────────────────────────────────
--   La primera versión pedía cambiar el nombre en DOS líneas: una arriba y otra
--   en la comprobación del final. Se hizo mal a la primera, y con razón — dos
--   huecos que hay que mantener iguales es un error esperando. Ahora el bloque
--   guarda a quién eligió y la comprobación lo lee de ahí.
--
--   Y tampoco hay un `if v_busca = 'PON_AQUI…'` que avise de que falta cambiarlo.
--   Lo hubo, y era peor: el mismo texto aparecía dos veces, así que un
--   buscar-y-reemplazar sobre todo el archivo —lo más natural del mundo— cambiaba
--   las dos y el aviso saltaba con el nombre ya puesto. Sobra, además: si nadie
--   se llama «PON_AQUI_EL_APELLIDO», el propio buscador lo dice con ese nombre
--   dentro del mensaje.
-- ############################################################################

drop table if exists _elegido;
create temp table _elegido (id uuid, nombre text);

do $$
declare
  v_busca     text    := 'PON_AQUI_EL_APELLIDO';   -- ⇦ CAMBIA ESTA LÍNEA
  v_beneficio text    := 'vacaciones';
  v_devenga   boolean := false;
  v_quien_soy text    := 'Felipe';   -- quién queda como autor del cambio

  v_id uuid; v_nombre text; v_n int; v_yo uuid;
begin
  -- ── Identificarse, que en el SQL Editor no es automático ──────────────────
  -- Esta función AUDITA quién cambia el devengo, así que se niega a correr sin
  -- saber quién es. Y el SQL Editor entra como `postgres`, sin sesión de nadie:
  -- `auth.uid()` es null y `fn_es_admin_o_lider()` dice que no.
  --
  -- Es el mismo prólogo que docs/estado.md ya documenta para fn_planilla_calcular
  -- y fn_provisiones. Va con `false` —alcance de sesión y no de transacción—
  -- porque la comprobación del final también lo necesita y es otra sentencia.
  select p.auth_user_id into v_yo
  from personas p
  where p.rol in ('admin', 'lider_do')
    and p.auth_user_id is not null
    and (p.nombres || ' ' || p.apellidos) ilike '%' || v_quien_soy || '%'
  limit 1;

  if v_yo is null then
    raise exception 'No encontré a un administrador que se parezca a «%». Es quien queda anotado como autor del cambio.', v_quien_soy;
  end if;
  perform set_config('request.jwt.claim.sub', v_yo::text, false);

  select count(*) into v_n
  from personas
  where (nombres || ' ' || apellidos) ilike '%' || v_busca || '%';

  if v_n = 0 then
    raise exception 'No encontré a nadie que se parezca a «%». Revisa cómo está escrito.', v_busca;
  end if;
  if v_n > 1 then
    raise exception '«%» encaja con % personas. Escribe algo más específico: esto decide plata y no puede adivinar.', v_busca, v_n;
  end if;

  select id, nombres || ' ' || apellidos into v_id, v_nombre
  from personas
  where (nombres || ' ' || apellidos) ilike '%' || v_busca || '%';

  perform fn_set_devenga_beneficio(v_id, v_beneficio, v_devenga);
  insert into _elegido values (v_id, v_nombre);

  raise notice 'Listo: % → % = %  ·  anotado a nombre de %',
    v_nombre, v_beneficio, coalesce(v_devenga::text, 'defecto del vínculo'), v_quien_soy;
end $$;

-- ── La comprobación, que es lo único que prueba que sirvió ──────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta. Lee a
-- quién eligió el bloque de arriba, así que acá no hay nada que cambiar.
--
-- El beneficio que apagaste tiene que salir en 0 y los otros dos exactamente
-- como estaban.
select e ->> 'nombre'      as persona,
       e ->> 'grati_total' as gratificacion,
       e ->> 'cts_total'   as cts,
       e ->> 'vac'         as vacaciones,
       e ->> 'vac_dias'    as dias_de_vacaciones,
       e ->> 'gran_total'  as gran_total
from _elegido q,
     jsonb_array_elements(fn_provisiones((now() at time zone 'America/Lima')::date) -> 'personas') e
where (e ->> 'persona_id')::uuid = q.id;
