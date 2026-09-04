-- ============================================================================
-- 0368 — Un código de sede no se pisa en silencio
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que `fn_guardar_sede` distinga CREAR de EDITAR, y que crear una
-- sede con un código que ya existe falle diciéndolo, en vez de sobrescribir la
-- sede que ya lo tenía. Editar sigue funcionando igual —incluida la llamada de
-- dos argumentos que solo cambia el nombre— y ponerle a una sede el código de
-- OTRA falla en vez de pisarla; el código de una sede ya creada no se cambia.
--
-- EL DEFECTO (hallazgo 33 de la auditoría del 2026-09-03/04): la pantalla de
-- Sedes comprueba el código repetido contra la lista que cargó al ABRIRSE, una
-- sola vez, y la función de la 0099 es un upsert puro sobre `codigo`:
--
--     insert into sedes (codigo, nombre, tipo) values (…)
--     on conflict (codigo) do update set nombre = excluded.nombre, …
--
-- Dos personas de administración creando «LIM03» en pestañas distintas ven las
-- dos que no existe, guardan las dos, y la segunda le cambia el nombre y el
-- tipo a la primera sin ningún aviso. No hace falta mala fe ni simultaneidad
-- exacta: basta con dejar la pantalla abierta desde ayer.
--
-- Y una sede no es una etiqueta. De `sedes` cuelgan marcajes, jornadas,
-- horarios, contratos, terminales y la sede base de cada persona; su `tipo`
-- decide si el reporte de costos la cuenta como tienda o como administración
-- (0099). Que su nombre y su tipo cambien porque alguien creyó estar creando
-- otra cosa es un dato malo que nadie va a saber de dónde salió.
--
-- QUÉ ASUME:
--   · Que la intención la sabe quien llama, no la base. Crear y editar se
--     parecen mucho por dentro —los dos escriben nombre y tipo— y solo se
--     distinguen por lo que la persona creía estar haciendo. Por eso llega
--     como argumento (`p_es_alta`) y no se deduce de si el código existe: esa
--     deducción es exactamente el defecto que se corrige.
--   · Que `sedes.codigo` ya tiene un candado único en la base. NO se agrega
--     acá porque YA ESTÁ: se midió antes de escribir esto — la constraint
--     `sedes_codigo_key` (UNIQUE btree sobre `codigo`) viene de la creación de
--     la tabla. Y en producción está garantizado sin tener que mirar: el
--     `on conflict (codigo)` de la 0099 lleva ahí desde entonces, y Postgres
--     exige un índice único para aceptar esa cláusula. La comprobación del
--     final lo confirma de todos modos al pegar.
--   · Que la sede se identifica por `id` cuando quien llama lo tiene, y por
--     `codigo` cuando no. El `id` es la identidad de verdad; el `codigo` es la
--     etiqueta con la que la busca el camino histórico.
--   · Que el `codigo` de una sede NO se cambia. Sigue siendo inmutable, igual
--     que con el upsert de la 0099, y la edición ni lo escribe ni lo ignora en
--     silencio: si llega uno distinto del que tiene la fila, lanza. Se midió
--     antes de decidirlo — `parametros_laborales.sede_codigo` (la tarifa de
--     movilidad POR SEDE, o sea plata), `planilla_pagada_detalle.sede_codigo`
--     y `terminal_roster.sede_codigo` apuntan a la sede por TEXTO y ninguna
--     tiene clave foránea contra `sedes(codigo)`: las ocho FKs que existen van
--     todas contra `sedes(id)`. Renombrar el código dejaría esas tres filas
--     huérfanas sin un solo error, y la de movilidad caería al respaldo
--     general (`admin/documentacion/page.tsx`, el `find` por `sede_codigo`).
--     El día que de verdad haga falta cambiar un código, eso es su propia
--     migración y arrastra las tres columnas en la misma transacción.
--
-- POR QUÉ SE ELIGIÓ ASÍ:
--   · **Dos argumentos nuevos y no uno.** Con solo `p_id` —«sin id es un
--     alta»— la llamada histórica de dos argumentos, que renombra por código,
--     pasaría a ser un alta duplicada y fallaría; la usa la prueba 100 y es un
--     camino legítimo. Con solo `p_es_alta` no habría forma de decir sobre qué
--     fila se edita cuando quien llama la tiene identificada. Cada argumento
--     tiene un trabajo: `p_es_alta` dice la intención, `p_id` dice qué fila.
--   · **El valor por defecto es la EDICIÓN, no el alta.** Un llamador viejo
--     que quisiera crear ya no crea: falla con «no existe ninguna sede con ese
--     código». Es un fallo ruidoso y reversible; el que se corrige —pisar una
--     sede ajena— es silencioso y no se deshace. Entre los dos, el default
--     tiene que ser el que se nota.
--   · **Se comprueba ANTES y se atrapa DESPUÉS.** La consulta previa existe
--     para poder decir el nombre de la sede que ya usa ese código, que es lo
--     que le dice a la persona qué pasó. Pero entre esa consulta y el insert
--     cabe otra sesión, así que la garantía de verdad es el `unique_violation`
--     atrapado: el candado de la base, no el vistazo.
--   · **Se extiende la función que ya existe**, sin crear una segunda puerta
--     para guardar una sede — el mismo motivo que escribió la 0099, y el
--     accidente de la 0297/0299 (dos funciones con el mismo nombre y firmas
--     distintas conviviendo en silencio). Por eso la firma de tres argumentos
--     se retira abajo con `drop function`.
--   · Los mensajes dicen qué hacer, no qué falló: «usa Editar en su fila»,
--     «usa Agregar sede». Salen como `raise exception` (P0001), así que
--     `mensaje-error.ts` los muestra tal cual, sin traducir.
--
-- QUÉ NO CAMBIA: el guard de permiso (`fn_es_admin_o_lider() is not true`),
-- las tres validaciones de código, nombre y tipo, la regla de que `p_tipo`
-- null significa «no lo toques», la inmutabilidad del `codigo` de una sede ya
-- creada, y la firma de `fn_costos_planilla`. Ninguna sede existente se
-- modifica: esta migración solo reemplaza una función.
--
-- VIGENTE EN: supabase/migrations/0099_una_tienda_no_es_una_oficina.sql
--   (`donde-vive.sh fn_guardar_sede`, vuelto a correr al entregar esto).
-- md5 de partida (Postgres LOCAL): tal cual b83590a169a115d07c5ab36c156aaf9e
--   · sin comentarios 3ac8f6efadd2776fcca7c417a8924fe2
-- ⚠️ ANTES DE PEGAR: vuelve a pedirle los dos md5 a PRODUCCIÓN con la consulta
--   que imprime `./scripts/donde-vive.sh fn_guardar_sede`. Si coincide el
--   primero, sigue. Si coincide solo el segundo, sigue (producción perdió los
--   comentarios al pegarse, le pasa a la mitad de las funciones). Si no
--   coincide ninguno, PARA: producción tiene otra versión y esto la
--   revertiría.
--
-- ORDEN DE DESPLIEGUE: esta migración y el despliegue del panel van JUNTOS —
-- la pantalla de esta rama manda `p_id` y `p_es_alta` en CADA guardado, y la
-- firma vieja no los tiene. Si hay que separarlos, esta migración va PRIMERO:
-- con el panel viejo (tres argumentos) editar sigue funcionando y solo el alta
-- falla, con un mensaje que ya avisa de que la pantalla está desactualizada.
-- Al revés —panel nuevo contra base vieja— PostgREST no encuentra la función y
-- Sedes deja de poder guardar NADA hasta que esto se pegue.
--
-- SE REVIERTE: volviendo a pegar el bloque `create or replace function
-- fn_guardar_sede(...)` de la 0099 —tres argumentos— y después
--   drop function if exists fn_guardar_sede(text, text, text, uuid, boolean);
--   grant execute on function fn_guardar_sede(text, text, text) to authenticated;
--   revoke execute on function fn_guardar_sede(text, text, text) from public, anon;
--   notify pgrst, 'reload schema';
-- ⚠️ Revertir la función NO basta, y el orden importa: primero se vuelve al
-- despliegue anterior del panel en Vercel, DESPUÉS se pega este SQL. PostgREST
-- no descarta las claves que la firma no tiene — busca la función por el
-- conjunto de nombres del cuerpo JSON, no la encuentra y devuelve PGRST202.
-- Medido contra el PostgREST local: un cuerpo con una clave de más responde
-- «Could not find the function public.fn_guardar_sede(p_clave_inexistente,
-- p_codigo, p_nombre, p_tipo) in the schema cache». O sea que la
-- compatibilidad solo va hacia adelante (llamador viejo → función nueva),
-- nunca hacia atrás: revertir esto con el panel nuevo puesto deja Sedes sin
-- poder guardar ni un alta ni una edición.
-- ============================================================================

create or replace function fn_guardar_sede(
  p_codigo text,
  p_nombre text,
  p_tipo   text default null,
  -- ⇩⇩⇩ CAMBIO 0368 ⇩⇩⇩ Los dos argumentos nuevos, los dos con valor por
  -- defecto para que la llamada de tres —y la de dos— siga encajando.
  p_id      uuid    default null,
  p_es_alta boolean default false
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_codigo text;
  v_id     uuid;
  v_actual text;
  v_choque text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar sedes.';
  end if;
  if p_codigo is null or upper(trim(p_codigo)) !~ '^[A-Z0-9]{2,8}$' then
    raise exception 'Código inválido (2 a 8 letras/números, ej. LIMT): %', coalesce(p_codigo, '(vacío)');
  end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre de la sede es obligatorio.';
  end if;
  if p_tipo is not null and p_tipo not in ('central', 'taller', 'tienda') then
    raise exception 'El tipo de sede tiene que ser central, taller o tienda.';
  end if;

  v_codigo := upper(trim(p_codigo));

  -- ⇩⇩⇩ CAMBIO 0368 ⇩⇩⇩ Todo lo que sigue reemplaza al upsert ciego. Decía:
  --
  --   insert into sedes (codigo, nombre, tipo)
  --   values (upper(trim(p_codigo)), trim(p_nombre), coalesce(p_tipo, 'tienda'))
  --   on conflict (codigo) do update
  --     set nombre = excluded.nombre,
  --         -- null = «no lo toques». Así una pantalla que todavía no manda el
  --         -- tipo no lo borra sin querer al guardar el nombre.
  --         tipo = coalesce(p_tipo, sedes.tipo);

  -- ── ALTA ────────────────────────────────────────────────────────────────
  if coalesce(p_es_alta, false) then
    -- El vistazo previo es para el MENSAJE: poder decir de quién es el código
    -- que ya está ocupado. La garantía viene abajo.
    select nombre into v_choque from sedes where codigo = v_codigo;
    if found then
      raise exception
        'Ya existe una sede con el código «%»: «%». Si querías cambiarla, usa «Editar» en su fila; si es otra sede, dale un código distinto.',
        v_codigo, v_choque;
    end if;

    -- Y acá está la garantía. Entre el select de arriba y este insert cabe
    -- otra sesión haciendo lo mismo, y ese es literalmente el caso del
    -- hallazgo: dos pestañas creando «LIM03». Quien pierde la carrera choca
    -- con el índice único de `codigo` y se entera, en vez de pisar.
    begin
      insert into sedes (codigo, nombre, tipo)
      values (v_codigo, trim(p_nombre), coalesce(p_tipo, 'tienda'));
    exception when unique_violation then
      raise exception
        'Ya existe una sede con el código «%». Alguien acaba de crearla desde otra pantalla; vuelve a abrir Sedes antes de repetir el alta.',
        v_codigo;
    end;
    return;
  end if;

  -- ── EDICIÓN ─────────────────────────────────────────────────────────────
  -- Sobre QUÉ fila. Con `p_id` es la identidad de verdad, la que no depende de
  -- una etiqueta; sin él, se busca por código, que es el camino histórico y el
  -- que usa la prueba 100 para renombrar.
  if p_id is not null then
    select id, codigo into v_id, v_actual from sedes where id = p_id;
    if not found then
      raise exception 'La sede que intentas modificar ya no existe. Vuelve a abrir la pantalla de Sedes.';
    end if;
  else
    select id, codigo into v_id, v_actual from sedes where codigo = v_codigo;
    if not found then
      raise exception
        'No existe ninguna sede con el código «%». Para crear una nueva, usa «Agregar sede». Si acabas de apretar «Agregar sede» y aun así sale esto, la pantalla está desactualizada frente a la base: recárgala, y si sigue igual avisa a Felipe.',
        v_codigo;
    end if;
  end if;

  -- Cambiarle el código a uno que ya tiene OTRA sede tampoco pisa a nadie.
  -- El `id <> v_id` es lo que deja pasar el caso normal: guardar una sede
  -- dejándole SU PROPIO código, que es lo que hace la pantalla cada vez.
  select nombre into v_choque from sedes where codigo = v_codigo and id <> v_id;
  if found then
    raise exception
      'El código «%» ya lo usa la sede «%». Los códigos de sede no se repiten: elige otro.',
      v_codigo, v_choque;
  end if;

  -- Y si el código está libre pero no es el suyo, tampoco se renombra: el
  -- `codigo` de una sede es inmutable, como con el upsert de la 0099, porque
  -- tres columnas lo referencian por TEXTO y sin clave foránea —la tarifa de
  -- movilidad por sede, la planilla ya pagada y el roster del terminal—.
  -- Renombrar aquí las dejaría huérfanas sin un solo error. No se ignora en
  -- silencio, que sería el mismo pecado que corrige esta migración: se dice.
  if v_actual is distinct from v_codigo then
    raise exception
      'La sede «%» no puede pasar a «%»: el código de una sede no se cambia una vez creada — de él cuelgan su tarifa de movilidad y la planilla ya pagada. Si de verdad hace falta otro código, crea la sede nueva y desactiva esta.',
      v_actual, v_codigo;
  end if;

  -- Sin escribir `codigo`, este update no tiene ningún candado único que
  -- violar: por eso no lleva el `exception when unique_violation` que sí
  -- necesita el alta.
  update sedes
     set nombre = trim(p_nombre),
         -- null = «no lo toques», igual que en la 0099. Una pantalla que no
         -- muestra el tipo no puede borrarlo al guardar el nombre.
         tipo   = coalesce(p_tipo, sedes.tipo)
   where id = v_id;
end;
$fn$;

-- La firma de tres argumentos se retira para que no queden dos funciones con
-- el mismo nombre. Es el accidente de la 0297/0299: no falla al pegar la
-- migración, falla al abrir la pantalla —«function … is not unique»— o, peor,
-- se queda la vieja atendiendo. Quien llame por nombre de argumento (así lo
-- hace PostgREST) sigue igual: los dos nuevos toman su valor por defecto.
drop function if exists fn_guardar_sede(text, text, text);

grant execute on function fn_guardar_sede(text, text, text, uuid, boolean) to authenticated;
revoke execute on function fn_guardar_sede(text, text, text, uuid, boolean) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (368, 'un_codigo_de_sede_no_se_pisa_en_silencio')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- Que entró el cuerpo nuevo, que quedó UNA sola `fn_guardar_sede` —la de
-- cinco argumentos— que la pantalla puede llamarla y `anon` no, y que el
-- candado único de `codigo` sigue ahí: sin él, el `unique_violation` de
-- arriba no se levantaría nunca y la carrera volvería a pisar en silencio.
select
  position('CAMBIO 0368' in p.prosrc) > 0                                  as tiene_el_cambio,
  (select count(*) from pg_proc where proname = 'fn_guardar_sede')         as una_sola_version,
  pg_get_function_identity_arguments(p.oid)                                as firma,
  (select count(*) from migraciones_aplicadas where numero = 367) = 1      as anotada,
  has_function_privilege('authenticated', p.oid, 'execute')                as la_pantalla_puede,
  not has_function_privilege('anon', p.oid, 'execute')                     as anon_no_puede,
  exists (
    select 1 from pg_index i
    where i.indrelid = 'sedes'::regclass and i.indisunique
      and i.indkey::text = (select a.attnum::text from pg_attribute a
                             where a.attrelid = 'sedes'::regclass and a.attname = 'codigo')
  )                                                                        as codigo_tiene_candado_unico
from pg_proc p
where p.proname = 'fn_guardar_sede';
