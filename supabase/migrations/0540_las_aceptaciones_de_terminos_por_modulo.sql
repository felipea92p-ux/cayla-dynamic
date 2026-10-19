-- ============================================================================
-- 0540 — Las aceptaciones de términos, por módulo y por versión
-- ============================================================================
--
-- QUÉ PROMETE
--   Cuando una integrante acepta los términos de uso de Dynamic o los de un
--   módulo de «Lo mío» (Boletas, Firma, Disciplina…), queda UNA constancia:
--   quién, de qué módulo, de qué versión del texto, con qué texto exacto y
--   cuándo. Una fila por aceptación, para siempre: no se edita ni se borra.
--
--   «Qué le falta aceptar a alguien» se contesta por diferencia: lo que el
--   código dice que está vigente (módulo + número de versión) menos lo que
--   esta tabla tiene de ella. Subir la versión de UN módulo hace que solo ese
--   módulo vuelva a pedirse; nadie tiene que tocar la base.
--
-- QUÉ ASUME
--   · Que los TEXTOS viven en el código (`packages/shared/src/terminos.ts`,
--     aún por escribir) con su número de versión, y que una prueba impide
--     cambiar la redacción sin subir la versión. Esta tabla no conoce los
--     textos vigentes: guarda lo que la persona tuvo delante.
--   · Que solo se guardan las aceptaciones «con aceptación» (casilla). Los
--     avisos de «Entendido» y la guía no son prueba de nada y viven en el
--     navegador, como `useRecorridoGuiado`.
--   · Que «general» es un módulo más: los términos de uso son el caso en que
--     el módulo es el sistema entero. Una sola tabla y una sola función, en
--     vez de dos que se parezcan.
--
-- POR QUÉ ASÍ
--   · Tabla propia y no `consentimientos_datos_personales` (0404). Esa guarda
--     el consentimiento de la Ley N.° 29733 en el momento de recolectar un dato
--     (finalidad libre, sin versión) y se lee para decidir si un DNI se aprueba.
--     Esto es otra pregunta —«¿ya aceptó la v2 de Boletas?»— y necesita lo que
--     aquella no tiene: versión, y una sola fila por versión. Meterlo ahí
--     habría mezclado dos cosas que se consultan distinto.
--   · El texto completo se guarda en cada fila (como en la 0404) y no solo su
--     número de versión: si mañana el código cambia o se pierde, la constancia
--     sigue diciendo qué leyó esa persona ese día. ~900 filas en tres años:
--     el espacio no es un argumento.
--   · `unique (persona_id, modulo, version)` hace el trabajo que haría una
--     validación: dos aceptaciones de la misma versión (dos pestañas, celular y
--     Mac al mismo tiempo) no pueden existir. La función las absorbe con
--     `on conflict do nothing`, así que la segunda no falla: contesta «ya
--     estaba». Por eso no hay carrera que arreglar.
--   · El nombre del módulo NO es una lista cerrada en la base. Una lista en un
--     `check` obligaría a una migración cada vez que «Lo mío» gane una sección;
--     lo que se exige es la FORMA (minúsculas y guion bajo). Quién decide qué
--     módulos existen es el código, que es donde se agregan las secciones.
--   · Inmutable por trigger, no solo por permisos: quitar el `grant` frena al
--     cliente, pero no a una migración o a alguien con el SQL Editor abierto, y
--     una constancia que se puede reescribir no prueba nada.
--   · La persona lee las suyas con `fn_mis_aceptaciones_terminos()` y no con un
--     `select` directo: un administrador ve TODAS por la policy, y un `select`
--     sin filtro en su pantalla le diría «aceptó» por las de otra persona.
--
-- QUÉ NO HACE, Y ES DELIBERADO
--   No bloquea nada en la base. Que un módulo no se abra sin aceptar es de la
--   pantalla (`capaActiva` / `bloqueaElModulo` en packages/shared): igual que
--   la 0404, escribir una regla de UN módulo en el camino de las funciones de
--   todos es peor que dejarla donde se ve. Esta migración solo da dónde
--   dejar y consultar la constancia.
--   No reescribe ninguna función existente: no hay md5 de partida que medir.
--
-- ORDEN DE PEGADO. Se pega ANTES de fusionar el pull request que la usa. Si el
-- código llegara primero no se rompería nada: sin poder leer las aceptaciones,
-- la pantalla no pide ni guía y el módulo funciona (se degrada callando).
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_aceptar_terminos(text, integer, text);
--   drop function if exists fn_mis_aceptaciones_terminos();
--   drop trigger if exists trg_aceptaciones_terminos_inmutable on aceptaciones_terminos;
--   drop function if exists fn_aceptaciones_terminos_inmutable();
--   drop table if exists aceptaciones_terminos;
--   (Solo mientras la tabla esté vacía: con filas, borrarla es destruir prueba.)
-- ============================================================================


-- ── A · La constancia, una fila por aceptación ──────────────────────────────
create table if not exists aceptaciones_terminos (
  id          uuid primary key default gen_random_uuid(),
  persona_id  uuid not null references personas(id),
  modulo      text not null,
  version     integer not null,
  texto       text not null,
  aceptado_at timestamptz not null default now(),
  -- Los estados que NUNCA deben existir, hechos imposibles aquí y no en el código:
  constraint aceptaciones_terminos_modulo_forma
    check (modulo ~ '^[a-z][a-z_]{1,31}$'),
  constraint aceptaciones_terminos_version_positiva
    check (version >= 1),
  -- Mismo mínimo que la 0404: «esto no puede ser una constancia vacía».
  constraint aceptaciones_terminos_texto_no_vacio
    check (length(btrim(texto)) >= 50),
  constraint aceptaciones_terminos_una_por_version
    unique (persona_id, modulo, version)
);

comment on table aceptaciones_terminos is
  'Constancia de que una persona aceptó los términos de uso (modulo = ''general'') '
  'o los de un módulo de Lo mío, en una versión concreta del texto. Append-only: '
  'una fila por aceptación, con el texto exacto que tuvo delante. No se edita ni '
  'se borra (trigger). Escritura solo vía fn_aceptar_terminos.';

comment on column aceptaciones_terminos.modulo is
  'Nombre del módulo en minúsculas y guion bajo (''general'', ''boletas'', ''disciplina''…). '
  'Sin lista cerrada a propósito: las secciones nuevas de Lo mío no deberían exigir una migración.';

comment on column aceptaciones_terminos.version is
  'Número de versión del texto aceptado, definido en el código. Subirlo hace que ese módulo '
  'se vuelva a pedir; la fila anterior queda como historia.';

alter table aceptaciones_terminos enable row level security;

-- Cada quien ve las suyas.
drop policy if exists aceptaciones_terminos_select_propia on aceptaciones_terminos;
create policy aceptaciones_terminos_select_propia on aceptaciones_terminos
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- Y Desarrollo Organizacional y los administradores ven todas: es lo que
-- responde «quién no ha aceptado la v2 de este módulo».
drop policy if exists aceptaciones_terminos_select_admin on aceptaciones_terminos;
create policy aceptaciones_terminos_select_admin on aceptaciones_terminos
  for select to authenticated using (fn_es_admin_o_lider() is true);

-- El orden importa, y `authenticated` va en el `revoke`: Supabase le da TODOS los
-- permisos a toda tabla nueva de `public` por defecto (medido en el Postgres
-- local, 2026-10-19: DELETE, UPDATE y TRUNCATE incluidos). Quitarle solo a
-- `anon` y `public`, como hizo la 0404, dejaba la escritura protegida únicamente
-- por RLS; la 0480 lo corrigió y esta sigue a la 0480. Después se devuelve solo leer.
revoke all on aceptaciones_terminos from anon, authenticated, public;
grant select on aceptaciones_terminos to authenticated;
-- Sin insert/update/delete para nadie: se escribe solo por fn_aceptar_terminos.


-- ── B · Una constancia no se reescribe ──────────────────────────────────────
create or replace function fn_aceptaciones_terminos_inmutable()
returns trigger language plpgsql as $$
begin
  raise exception 'Una aceptación de términos es una constancia: no se edita ni se borra. '
                  'Si la persona acepta una versión nueva, se agrega otra fila.';
end;
$$;

drop trigger if exists trg_aceptaciones_terminos_inmutable on aceptaciones_terminos;
create trigger trg_aceptaciones_terminos_inmutable
  before update or delete on aceptaciones_terminos
  for each row execute function fn_aceptaciones_terminos_inmutable();


-- ── C · Dejar constancia de MI aceptación ───────────────────────────────────
-- Devuelve true si esta llamada fue la que la dejó, y false si ya estaba (otra
-- pestaña, otro dispositivo, o un doble clic). En los dos casos la constancia
-- existe al terminar, que es lo único que le importa a quien llama.
create or replace function fn_aceptar_terminos(p_modulo text, p_version integer, p_texto text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_yo    uuid;
  v_filas integer;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  if coalesce(p_modulo, '') !~ '^[a-z][a-z_]{1,31}$' then
    raise exception 'El nombre del módulo no es válido: minúsculas y guion bajo.';
  end if;

  if p_version is null or p_version < 1 then
    raise exception 'Falta decir de qué versión de los términos se trata.';
  end if;

  if length(btrim(coalesce(p_texto, ''))) < 50 then
    raise exception 'El texto de los términos llegó vacío o incompleto; no se puede dejar constancia de él.';
  end if;

  insert into aceptaciones_terminos (persona_id, modulo, version, texto)
  values (v_yo, p_modulo, p_version, p_texto)
  on conflict (persona_id, modulo, version) do nothing;

  get diagnostics v_filas = row_count;
  return v_filas = 1;
end;
$$;
grant execute on function fn_aceptar_terminos(text, integer, text) to authenticated;
revoke execute on function fn_aceptar_terminos(text, integer, text) from public, anon;


-- ── D · Qué he aceptado YO ──────────────────────────────────────────────────
-- Solo módulo y versión: el texto no hace falta para decidir qué falta, y no
-- hay por qué traer centenares de caracteres por fila en cada carga de /mio.
-- `security invoker`: corre con los permisos de quien llama, y la policy propia
-- ya filtra; el `where` es el que impide que un administrador vea las ajenas.
create or replace function fn_mis_aceptaciones_terminos()
returns table (modulo text, version integer, aceptado_at timestamptz)
language sql stable security invoker set search_path = public as $$
  select a.modulo, a.version, a.aceptado_at
    from aceptaciones_terminos a
   where a.persona_id = fn_persona_actual_id()
   order by a.modulo, a.version;
$$;
grant execute on function fn_mis_aceptaciones_terminos() to authenticated;
revoke execute on function fn_mis_aceptaciones_terminos() from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (540, 'las_aceptaciones_de_terminos_por_modulo')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
