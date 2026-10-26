-- ============================================================================
-- 0506 · UN ALTA QUE SE PARECE A ALGUIEN YA REGISTRADO PIDE CONFIRMACIÓN
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_crear_persona` se niegue a dar de alta a alguien cuyo nombre se
--   parece al de una persona que YA existe —esté en el equipo o ya haya salido—
--   salvo que quien da de alta confirme, a propósito, que es otra persona. Y que
--   la pantalla de Equipo pueda preguntar «¿a quién se parece?» ANTES de
--   escribir nada (`fn_personas_parecidas`).
--
-- EL DEFECTO, EN UNA LÍNEA
--   Dar de alta no miraba a nadie. El 2026-10-04 una persona quedó registrada dos
--   veces con dos escrituras de su propio nombre —una corta y una completa—,
--   cada una con su PIN, las dos activas y visibles en el terminal de su sede.
--
-- POR QUÉ NADA LO FRENABA
--   El único freno de identidad que tiene el sistema es el índice único de
--   documento (0125, `idx_personas_documento_unico`), y el alta no captura el
--   documento: llega después, cuando la persona sube su DNI. Al momento del alta
--   lo único que se sabe de alguien es cómo se escribe su nombre, y dos
--   escrituras distintas del mismo nombre no chocan contra ninguna restricción.
--   Tampoco ayuda el correo (opcional) ni mirar el listado: el filtro «Mostrar»
--   arranca en «Solo el equipo actual», así que quien ya salió y vuelve
--   —el reingreso, que se hace REACTIVANDO a la persona y no creando otra— ni
--   siquiera aparece al lado.
--
-- POR QUÉ LA REGLA ES UNA ADVERTENCIA Y NO UN CANDADO
--   Los homónimos existen: dos «María Quispe» pueden ser dos personas. Un candado
--   duro bloquearía una contratación legítima sin salida; una advertencia que
--   pide un clic cuesta un clic. Por eso `p_confirmo_distinta` existe, y por eso
--   la excepción dice A QUIÉN se parece: un «ya hay alguien parecido, ¿seguro?»
--   que no nombra a nadie se confirma a ciegas.
--
-- LA REGLA DE PARECIDO (probada contra 66 casos escritos a mano y contra 6 000
-- parejas «la misma persona tecleada dos veces» y 160 000 de personas distintas;
-- los casos viven en la prueba 400)
--   La gente no escribe DISTINTO el mismo nombre: escribe MENOS de él, o lo mismo
--   en el otro campo. Por eso se compara por palabras y no por texto:
--     · se quitan tildes, mayúsculas y partículas («de», «del», «la»…);
--     · avisa si, campo por campo, uno contiene al otro SIN contradicción y
--       comparten al menos un nombre y un apellido  («Marisol | Quispe» contra
--       «Marisol Aurora | Quispe Rivas»);
--     · o con los campos cruzados (apellidos escritos en «nombres»);
--     · o si TODAS las palabras de una están en la otra, sin mirar campos;
--     · o lo mismo tras reparar UN solo tipeo de una letra en palabras de 5+
--       letras («Marisol» / «Marizol»).
--   NO avisa por compartir solo el nombre de pila ni solo un apellido: en un
--   equipo con tantos Quispe, Mamani y Flores eso avisaría siempre y se aprende
--   a ignorar. Cuando dos registros se CONTRADICEN en un mismo campo («Quispe
--   Mamani» contra «Quispe Flores») tampoco avisa.
--   Costo medido: ~65 ms por alta contra 60 personas; a ~1 alta por semana son
--   segundos de CPU al año. Falsos avisos esperados: ~2.5 al año.
--
-- DECISIONES
--   DECIDÍ:    el guardián vive en `fn_crear_persona` —la única puerta de alta de
--              la APP— y la pantalla solo lo vuelve amable preguntando antes.
--   DESCARTÉ:  validarlo solo en la pantalla, porque quien manda es el servidor
--              (la misma razón por la que `fn_contrato_registrar` rechaza lo que
--              rechaza la pantalla de Contratos): un chequeo del lado del cliente
--              se salta con dos pestañas o con una carga fallida.
--   DESCARTÉ:  un índice único sobre el nombre normalizado, porque rompería a los
--              homónimos reales y a las estaciones de retail.
--   DESCARTÉ:  que el guardián devuelva un jsonb «{id: null, parecidas: […]}» en
--              vez de levantar una excepción. Hoy la pantalla trata «sin error»
--              como éxito y mostraría el PIN de alguien que no existe. Con una
--              excepción, la pantalla VIEJA —que seguirá corriendo contra la
--              función NUEVA los minutos que pasan entre pegar esto y fusionar—
--              falla seguro: muestra el error y no crea a nadie.
--   SE ROMPE SI: dos registros de la misma persona no comparten NINGUNA palabra
--              (en la simulación, 7.5 % de las parejas): ninguna regla de texto
--              lo ve, y lo único que lo cierra es capturar el DNI en el alta.
--
-- LO QUE ESTO NO CIERRA: LA PUERTA DE LA API
--   Protege la pantalla de Equipo, no la base. La política `personas_insert_admin_lider`
--   (0003) y el privilegio de INSERT dejan que un admin o líder DO inserte en
--   `personas` directo por REST, saltándose esta función entera: el guardián de
--   parecidos y, de paso, el escalafón de la 0300 (medido: un lider_do crea un admin
--   directo). No es una regresión de esta migración —la 0300 ya decía «única puerta»
--   y no lo era—, pero no se cierra aquí: es otra decisión (quitar la política y
--   el INSERT a `authenticated`) y va en su propia migración.
--
-- ORDEN DE DESPLIEGUE
--   Se pega ANTES de fusionar el PR. La pantalla nueva llama primero a
--   `fn_personas_parecidas`: si el PR llega a `main` antes que esta migración, Equipo
--   NO puede dar de alta a nadie hasta que se pegue (falla cerrado, con el aviso
--   «falta aplicar una migración»). La pantalla VIEJA contra la función nueva también
--   falla seguro: muestra el error y no crea a nadie.
--
-- UNA SOLA ALTA A LA VEZ
--   La comprobación y el insert están separados por unos milisegundos: dos altas
--   simultáneas del mismo nombre pasarían las dos. `pg_advisory_xact_lock` las
--   pone en fila —se suelta solo al terminar la transacción—. Cuesta nada: hay
--   ~1 alta por semana.
--
-- LA FIRMA CAMBIA, Y ESO EXIGE EL `drop function`
--   `create or replace` con un parámetro nuevo NO reemplaza: deja DOS funciones,
--   y llamar con los siete argumentos de siempre queda ambiguo —«function … is
--   not unique»—. Es exactamente lo que la 0297/0299 dejó en producción con el
--   aviso de vacaciones, y la 0367 con el marcaje. Medido antes de escribir esta
--   migración: con ambas firmas vivas, la llamada de siete argumentos falla; con
--   el `drop` de la vieja queda una sola y esa llamada resuelve a la nueva (con
--   `p_confirmo_distinta = false`). Un `drop` se lleva sus permisos, por eso se
--   vuelven a dar abajo.
--
-- MD5 DE PARTIDA
--   Cuerpo vigente según el repositorio (0300): `143a698ae6f6907298430324c7ff623d`,
--   2050 caracteres; sin comentarios: `8ed9099437a0dc93ecd1fd70560169e7`. El Postgres
--   local lo tiene idéntico. PENDIENTE: contrastarlo
--   con PRODUCCIÓN antes de pegar —en el mensaje en que se entrega este SQL, no
--   antes— con `scripts/sql-manual/md5_fn_crear_persona.sql`. Si no coincide, esta
--   migración se escribió sobre la versión equivocada y NO se pega.
--
-- QUÉ NO CAMBIA
--   Las validaciones de la 0300 (guard de admin/líder, nombres y apellidos, sede,
--   rol, escalafón, área, PIN) siguen iguales y en el mismo orden. El parecido se
--   comprueba DESPUÉS de todas ellas, justo antes del insert: un error de siempre
--   sigue dando su mensaje de siempre.
--
-- QUÉ NO HACE
--   No mira renombres: cambiar el nombre de alguien que ya existe (`Editar`) no
--   pasa por esta regla. No mira el documento ni el correo (el correo ya tiene su
--   `unique`, y el documento su índice). No compara contra las estaciones de retail
--   (`cuenta_de_servicio`, 0490): no son personas, y la tabla de Equipo las oculta,
--   así que «Ver en la lista» no podría mostrar a nadie. Se excluyen leyendo la
--   columna por `to_jsonb`, no por nombre, para que esta migración se pueda
--   pegar también en una base que todavía no tiene la 0490.
--   Límite: los nombres de más de 120 caracteres se rechazan. Con un texto de
--   cientos de palabras la comparación es cuadrática y, con el candado de arriba
--   tomado, frenaría todas las altas (medido: 600 caracteres = ~4 s de CPU).
--
-- CÓMO SE REVIERTE
--   `drop function` de la firma de 8 argumentos y de las cinco funciones nuevas, y
--   volver a aplicar el cuerpo de la 0300 (grant incluido). Ninguna fila cambia.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final.
-- ============================================================================


-- ── 1 · LA REGLA, como funciones puras ──────────────────────────────────────
-- Sin tablas, sin extensiones (no hay garantía de `unaccent` ni `pg_trgm` en
-- producción) y sin permisos para la API: las llaman las funciones de abajo, que
-- son SECURITY DEFINER. Nadie las necesita desde la pantalla.

-- La CLAVE de un texto: sus palabras sin tildes, en minúscula, sin partículas ni
-- letras sueltas, ordenadas. Los duplicados se conservan: los operadores de
-- arrays los ignoran. `normalize(… NFC)` primero: un PDF o un archivo de Mac puede
-- traer «María» como «Maria» + una tilde suelta, y sin juntarlas la tilde caería
-- en el filtro y la palabra quedaría como «mari».
create or replace function fn_nombre_clave(p_texto text)
returns text[]
language sql immutable parallel safe
as $$
  select coalesce(array_agg(t order by t), '{}')
    from regexp_split_to_table(
           btrim(regexp_replace(
             lower(translate(normalize(coalesce(p_texto, ''), NFC),
               'áàâäãåéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ',
               'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC')),
             '[^a-z]+', ' ', 'g')),
           ' ') as t
   where length(t) >= 2                                   -- «J.» y la «y» suelta no son palabras
     and t not in ('de', 'del', 'la', 'las', 'los')       -- «De la Cruz» = «Cruz»
$$;

-- UN TIPEO: dos palabras de 5+ letras que difieren en UNA letra (cambiada, de más,
-- de menos, o dos contiguas intercambiadas), en cualquier posición. Incluye la
-- última letra, así que también avisa «María»/«Mario» o «Daniel»/«Daniela»
-- (hermanos): se acepta a propósito —avisar cuesta un clic, no avisar cuesta una
-- persona duplicada—. Con 4 letras o menos no hay tolerancia: «Nora»/«Norma» y
-- «Elsa»/«Elisa» son personas distintas.
create or replace function fn_tipeo_de_una_letra(p_a text, p_b text)
returns boolean
language sql immutable parallel safe
as $$
  select p_a <> p_b
     and length(p_a) >= 5 and length(p_b) >= 5
     and (
          (length(p_a) = length(p_b) and (
             (select count(*) from generate_series(1, length(p_a)) i
               where substr(p_a, i, 1) <> substr(p_b, i, 1)) = 1
             or exists (select 1 from generate_series(1, length(p_a) - 1) i
                         where substr(p_a, i, 1) = substr(p_b, i + 1, 1)
                           and substr(p_a, i + 1, 1) = substr(p_b, i, 1)
                           and left(p_a, i - 1) = left(p_b, i - 1)
                           and substr(p_a, i + 2) = substr(p_b, i + 2))))
          or (abs(length(p_a) - length(p_b)) = 1 and exists (
                select 1 from generate_series(1, greatest(length(p_a), length(p_b))) i
                 where overlay(case when length(p_a) > length(p_b) then p_a else p_b end placing '' from i for 1)
                     = case when length(p_a) > length(p_b) then p_b else p_a end))
         )
$$;

-- COMPATIBLES, sin tipeos. g = palabras de «nombres», s = palabras de «apellidos»
-- (ya son claves).
create or replace function fn_nombres_compatibles(g1 text[], s1 text[], g2 text[], s2 text[])
returns boolean
language sql immutable parallel safe
as $$
  select
    -- (a) campo por campo, sin contradicción: en nombres uno contiene al otro, en
    --     apellidos uno contiene al otro, y comparten al menos un nombre y un
    --     apellido. NO cubre «Maria | Quispe Mamani» contra «Maria | Quispe
    --     Flores»: ahí los segundos apellidos se contradicen, y son dos personas.
       ((g1 <@ g2 or g2 <@ g1) and (s1 <@ s2 or s2 <@ s1) and g1 && g2 and s1 && s2)
    -- (b) lo mismo con los campos de la segunda persona cruzados (apellidos
    --     escritos en «nombres»).
    or ((g1 <@ s2 or s2 <@ g1) and (s1 <@ g2 or g2 <@ s1) and g1 && s2 and s1 && g2)
    -- (c) sin mirar campos: todas las palabras de una están en la otra, y la más
    --     corta tiene 2+ palabras distintas (una sola palabra no alcanza).
    or ((g1 || s1) <@ (g2 || s2) and (select count(distinct t) from unnest(g1 || s1) t) >= 2)
    or ((g2 || s2) <@ (g1 || s1) and (select count(distinct t) from unnest(g2 || s2) t) >= 2)
$$;

-- EL PREDICADO: compatibles, o compatibles tras reparar UN solo tipeo.
-- Promete: TRUE si dos altas podrían ser la misma persona. Nunca NULL. Simétrica.
-- Asume: solo mira las palabras de nombres y apellidos —no sede, estado ni
-- documento—. No decide nada: avisa, y una persona confirma.
create or replace function fn_nombres_parecidos(
  p_nombres_a text, p_apellidos_a text, p_nombres_b text, p_apellidos_b text)
returns boolean
language sql immutable parallel safe
as $$
  with k as materialized (select fn_nombre_clave(p_nombres_a)   as g1, fn_nombre_clave(p_apellidos_a) as s1,
                    fn_nombre_clave(p_nombres_b)   as g2, fn_nombre_clave(p_apellidos_b) as s2)
  select coalesce(
           fn_nombres_compatibles(g1, s1, g2, s2)
           or exists (
                select 1 from unnest(g1 || s1) t, unnest(g2 || s2) u
                 where t <> all(g2 || s2) and u <> all(g1 || s1)       -- palabras sin pareja exacta
                   and fn_tipeo_de_una_letra(t, u)
                   and fn_nombres_compatibles(g1, s1, array_replace(g2, u, t), array_replace(s2, u, t))),
           false)
    from k
$$;


-- ── 2 · A QUIÉN SE PARECE (lo que la pantalla pregunta antes de escribir) ───
-- Promete: las personas —activas o ya salidas— cuyo nombre se parece al pedido,
-- las que están en el equipo primero. Solo la ve un administrador o líder DO:
-- decir quién existe ya es dar un dato de personal.
create or replace function fn_personas_parecidas(p_nombres text, p_apellidos text)
returns table (
  persona_id uuid, nombres text, apellidos text, estado text,
  sede_codigo text, fecha_ingreso date, fecha_cese date
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver si alguien ya está registrado.';
  end if;
  if trim(coalesce(p_nombres, '')) = '' or trim(coalesce(p_apellidos, '')) = '' then
    return;
  end if;
  -- El tope va ANTES de comparar: la comparación es cuadrática en palabras y
  -- `fn_crear_persona` la llama con el candado de altas tomado.
  if length(p_nombres) > 120 or length(p_apellidos) > 120 then
    raise exception 'Nombres y apellidos no pueden pasar de 120 caracteres cada uno.';
  end if;

  return query
    select pe.id, pe.nombres, pe.apellidos, pe.estado, s.codigo, pe.fecha_ingreso, pe.fecha_cese
      from personas pe
      left join sedes s on s.id = pe.sede_base_id
     where fn_nombres_parecidos(p_nombres, p_apellidos, pe.nombres, pe.apellidos)
       -- Las estaciones de retail (0490) no son personas. `to_jsonb` y no la columna
       -- directa: así la función se crea y funciona en una base sin la 0490.
       and coalesce((to_jsonb(pe) ->> 'cuenta_de_servicio')::boolean, false) is not true
     order by (pe.estado = 'activo') desc, pe.created_at, pe.id;
end;
$$;


-- ── 3 · EL ALTA, con el guardián ────────────────────────────────────────────
-- La firma cambia (parámetro nuevo), así que se borra la vieja: ver arriba.
-- El `drop` es SOLO de la firma de siete argumentos y el `create` es `or replace`
-- de la de ocho: así repegar esta migración —se pega a mano, y una mano se
-- equivoca— no falla con «ya existe» ni deja dos versiones.
drop function if exists fn_crear_persona(text, text, uuid, text, text, text, text);

create or replace function fn_crear_persona(
  p_nombres text,
  p_apellidos text,
  p_sede_base_id uuid,
  p_rol text,
  p_funcion text,
  p_email text,
  p_pin_hash text,
  p_confirmo_distinta boolean default false
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_yo_rol rol_usuario;
  v_yo_rango int;
  v_nuevo_rango int;
  v_parecidas text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede crear personas.';
  end if;
  if trim(coalesce(p_nombres, '')) = '' or trim(coalesce(p_apellidos, '')) = '' then
    raise exception 'Nombres y apellidos son obligatorios.';
  end if;
  if not exists (select 1 from sedes where id = p_sede_base_id) then
    raise exception 'Sede inválida.';
  end if;
  if p_rol is null or p_rol not in ('integrante', 'supervisor_sede', 'lider_do', 'admin') then
    raise exception 'Rol inválido: %', coalesce(p_rol, '(vacío)');
  end if;

  -- CAMBIO 0300 · el mismo escalafón que ya rige cambiar el rol de alguien
  -- que ya existe (fn_set_rol, 0295). Sin esto, un lider_do podía crear una
  -- cuenta NUEVA directamente como Admin, sin pasar por ninguna de las dos
  -- puertas que la 0295/0296 ya cerraron para una persona ya existente.
  select rol into v_yo_rol from personas where auth_user_id = auth.uid();
  v_yo_rango := case v_yo_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  v_nuevo_rango := case p_rol
    when 'admin' then 3 when 'lider_do' then 2 when 'supervisor_sede' then 1 else 0 end;
  if v_yo_rol <> 'admin' and v_nuevo_rango >= v_yo_rango then
    raise exception 'No puedes crear una persona con un rol igual o superior al tuyo.';
  end if;

  if p_funcion is null or not exists (select 1 from areas where codigo = p_funcion and activa) then
    raise exception 'Área inválida o inactiva: %', coalesce(p_funcion, '(vacía)');
  end if;
  if p_pin_hash is null or p_pin_hash = '' then
    raise exception 'Falta el PIN.';
  end if;

  -- CAMBIO 0506 · si el nombre se parece al de alguien que ya existe, se pide
  -- confirmar que es OTRA persona. Se hace después de todas las validaciones de
  -- arriba para que un error de siempre siga dando su mensaje de siempre, y
  -- dentro de un candado para que dos altas simultáneas del mismo nombre no
  -- pasen las dos la comprobación antes de que alguna inserte.
  perform pg_advisory_xact_lock(hashtext('fn_crear_persona'));
  if p_confirmo_distinta is not true then
    select string_agg(
             format('«%s %s» (%s · %s · ingresó %s)',
                    q.nombres, q.apellidos,
                    case when q.estado = 'activo' then 'está en el equipo' else 'ya salió' end,
                    coalesce(q.sede_codigo, 'sin sede'),
                    to_char(q.fecha_ingreso, 'DD/MM/YYYY')),
             '; ')
      into v_parecidas
      from (select * from fn_personas_parecidas(p_nombres, p_apellidos) limit 3) q;
    if v_parecidas is not null then
      -- El `hint` es el marcador estable con el que la pantalla distingue este
      -- caso de cualquier otro error, sin leer el texto.
      raise exception 'Ya hay alguien registrado que se parece: %. Si es la misma persona, no la registres otra vez: ábrela en Equipo y complétala ahí (si ya salió, se reactiva). Si es otra persona, confirma que es distinta.',
        v_parecidas
        using hint = 'persona_parecida';
    end if;
  end if;

  insert into personas (nombres, apellidos, sede_base_id, rol, funcion, email, pin_hash)
  values (
    trim(p_nombres), trim(p_apellidos), p_sede_base_id,
    p_rol::rol_usuario, p_funcion, nullif(trim(coalesce(p_email, '')), ''), p_pin_hash
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;


-- Si algo dejó DOS firmas de fn_crear_persona (la 0297/0299 y la 0367 lo hicieron),
-- esto lo dice aquí, en voz alta, y deshace la migración entera. Sin esto no falla
-- al pegar: falla cuando alguien abre Equipo y la llamada queda ambigua.
do $$
begin
  if (select count(*) from pg_proc
       where proname = 'fn_crear_persona' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'fn_crear_persona quedó con más de una firma: la pantalla de Equipo no podría dar de alta a nadie. Se deshace la migración.';
  end if;
end $$;

-- ── 4 · PERMISOS ────────────────────────────────────────────────────────────
-- Las dos funciones que la pantalla llama: abiertas a quien inició sesión y
-- cerradas a `anon` y a PUBLIC (la prueba 250 lo vigila). Las cuatro de la regla
-- no se abren a nadie: solo las llaman estas dos, que son SECURITY DEFINER.
grant execute on function fn_crear_persona(text, text, uuid, text, text, text, text, boolean) to authenticated;
revoke execute on function fn_crear_persona(text, text, uuid, text, text, text, text, boolean) from public, anon;

grant execute on function fn_personas_parecidas(text, text) to authenticated;
revoke execute on function fn_personas_parecidas(text, text) from public, anon;

revoke execute on function fn_nombre_clave(text) from public, anon, authenticated;
revoke execute on function fn_tipeo_de_una_letra(text, text) from public, anon, authenticated;
revoke execute on function fn_nombres_compatibles(text[], text[], text[], text[]) from public, anon, authenticated;
revoke execute on function fn_nombres_parecidos(text, text, text, text) from public, anon, authenticated;

-- PostgREST guarda en memoria las firmas de las funciones: sin esto la pantalla
-- sigue viendo la de siete argumentos hasta que algo lo reinicie.
notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (506, '0506_un_alta_que_se_parece_a_alguien_pide_confirmacion')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
-- Una sola versión de fn_crear_persona, con el guardián adentro, cerrada a anon.
select
  (select count(*) from pg_proc where proname = 'fn_crear_persona')
    as versiones_de_fn_crear_persona,                     -- tiene que ser 1
  (select bool_and(prosrc like '%CAMBIO 0506%') from pg_proc where proname = 'fn_crear_persona')
    as el_guardian_ya_esta_adentro,                       -- tiene que ser true
  (select has_function_privilege('anon', 'fn_crear_persona(text,text,uuid,text,text,text,text,boolean)', 'execute'))
    as anon_puede_ejecutarla,                             -- tiene que ser false
  (select fn_nombres_parecidos('Ana', 'Quispe', 'Ana Maria', 'Quispe Mamani'))
    as la_regla_responde,                                 -- tiene que ser true
  (select string_agg(md5(prosrc), ',') from pg_proc where proname = 'fn_crear_persona')
    as md5_nuevo;
