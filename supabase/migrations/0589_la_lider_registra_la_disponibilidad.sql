-- ============================================================================
-- 0589 — La líder de equipo registra la disponibilidad de su gente
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la líder de equipo pueda registrar la disponibilidad de una integrante
--   de SU sede —no solo DO y admin, como hasta la 0584—, y que todo registro
--   hecho por otra persona diga POR QUÉ se registró así: «Me lo dijo en
--   persona», «Está en preselección y todavía no tiene cuenta»…, o «Otro» con
--   el texto escrito. Lo registrado entra APROBADO, igual que cuando lo
--   registra DO.
--
-- DECIDIÓ FELIPE (2026-11-03)
--   1. La líder registra la de una integrante de su sede. Nunca la propia; la
--      de otra líder la registra DO.
--   2. Entra aprobada directamente.
--   3. Con un motivo del registro obligatorio, distinto del motivo de la
--      disponibilidad (estudios, hijos, salud…, que se queda). Lista de lo más
--      simple a lo más complejo, con «Otro» para escribir.
--   El riesgo de (2) —la líder registra y aprueba a la vez, sin otro par de
--   ojos— se discutió con Felipe: lo acotan el motivo obligatorio y que cada
--   registro queda en «Cambios de horario» con quién lo hizo y por qué.
--
-- QUÉ ASUME
--   · `fn_puede_resolver_disponibilidad` (0584) es la regla de «quién decide
--     sobre la disponibilidad de esta persona»: DO y admin sobre cualquiera, la
--     líder sobre las integrantes de su sede, nunca la propia. Registrar es la
--     misma pregunta, así que se usa la misma función. No se escribe otra.
--   · `fn_disponibilidad_guardar_interno` (0584) no cambia: se le pasan los
--     mismos datos y el motivo del registro se anota DESPUÉS sobre la fila que
--     devuelve, en la misma transacción.
--
-- LO QUE REESCRIBE
--   `fn_disponibilidad_registrar`, vigente en la 0584 (donde-vive.sh). Su
--   firma cambia —suma p_registro_motivo y p_registro_detalle—, así que se
--   borra la de 8 argumentos y se crea la de 10: dejar las dos sería una
--   sobrecarga, y con argumentos por defecto Postgres no sabría cuál llamar
--   («function is not unique», el accidente de la 0297/0299).
--   md5 de partida en PRODUCCIÓN, pedido antes de escribir (2026-11-03):
--   `6a553cab51679590a25291fae1510243`, 837 caracteres, sin `\r`, una sola
--   versión. Coincide con el Postgres local. Si al pegar producción devuelve
--   otro, PARAR.
--   `fn_puede_resolver_disponibilidad` NO se toca (md5 de producción
--   `76f2653c1a091036ad8a4eb3455fd030`, 686, igual al local).
--
-- ENTRE PEGAR Y FUSIONAR (corregido el 2026-11-03: el PR #662 se fusionó ANTES de pegar)
--   Se pensó para pegarse antes de fusionar. No pasó: el #662 ya está en `main`
--   y publicado, así que la pantalla llama con `p_registro_motivo` y
--   `p_registro_detalle` mientras producción sigue con la función de 8
--   argumentos. Hasta pegar esto, registrar por otra persona (DO y líder) falla
--   por no encontrar esa firma. Enviar su propia disponibilidad no se ve
--   afectado (esa es otra función). Por eso pegarla es urgente, no opcional.
--
-- CÓMO SE PEGA — EN DOS PARTES, UNA POR UNA (la lección de la 0591, 2026-11-03)
--   El SQL Editor corre todo lo pegado en UNA transacción. Esta migración altera
--   una sola tabla (`disponibilidades`) y cambia una función, así que no cierra
--   un ciclo de bloqueos por sí sola; aun así se parte, por dos razones:
--   (a) la parte 1 empieza con `set local lock_timeout = '3s'`: si no consigue el
--   bloqueo falla con 55P03 en vez de quedarse en cola frenando a todos los que
--   vienen detrás, y se repega; (b) la función nueva NO puede existir sin las
--   columnas que escribe, y la guardia de la parte 2 lo impide.
--     PARTE 1 · las columnas y sus candados      (solo `disponibilidades`)
--     PARTE 2 · la puerta, su registro y la comprobación
--   Cada una se pega SOLA, en ese orden. Entera, en un solo bloque, sigue siendo
--   válida en una base sin tráfico (`supabase db reset`, las pruebas).
--
-- ANTES DE PEGAR: LO QUE HAY QUE PEDIRLE A PRODUCCIÓN (solo lee)
--   El md5 de partida es una foto y caduca (CLAUDE.md): se vuelve a pedir el día
--   que se pega. Si no sale exactamente esto, PARAR.
--     select (select md5(prosrc) || ' · ' || length(prosrc) from pg_proc
--              where proname = 'fn_disponibilidad_registrar') as la_funcion_hoy,
--            (select count(*) from pg_proc where proname = 'fn_disponibilidad_registrar') as versiones,
--            exists (select 1 from information_schema.columns where table_name = 'disponibilidades'
--                     and column_name = 'registro_motivo') as ya_tiene_la_columna;
--   Esperado: `6a553cab51679590a25291fae1510243 · 837`, 1 versión y false.
--   Si da `ae579eb75a2efdf906554dcfbe105e94 · 854` es el MISMO código pegado
--   desde Windows (un `\r` por línea, 17 líneas): seguir. Cualquier otro número,
--   o 2 versiones, o true: alguien tocó la función o la pegó a medias. Parar.
--
-- CÓMO SE COMPRUEBA DESPUÉS (la consulta del final de la parte 2)
--   Todo en true y una sola versión. md5 de llegada de la función nueva, medido
--   al escribir esta versión del archivo (2026-11-03, sin renumerar):
--   `e9f7c9c0efc2c258275046f473e3a202 · 1609`, 33 líneas. Si llega con un `\r`
--   por línea es el mismo código pegado desde Windows: `ea5ed9d1e726a2e2bc8f23fcba01f027 · 1642`.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text);
--   Volver a pegar fn_disponibilidad_registrar de la 0584 (con su comment y grants).
--   alter table disponibilidades drop constraint if exists disponibilidad_registro_otro_con_texto;
--   alter table disponibilidades drop column if exists registro_detalle, drop column if exists registro_motivo;
--     (solo si no hay registros que conservar: es historia)
--   delete from migraciones_aplicadas where numero = 589;
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: todo en true, una sola versión de la función y
--   «589 · la_lider_registra_la_disponibilidad».
-- ============================================================================

-- ═══ PARTE 1 · El motivo del registro (solo disponibilidades) ═══════════════

set local lock_timeout = '3s';

alter table disponibilidades add column if not exists registro_motivo text;
alter table disponibilidades add column if not exists registro_detalle text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'disponibilidad_registro_motivo_valido') then
    alter table disponibilidades add constraint disponibilidad_registro_motivo_valido check (
      registro_motivo is null or registro_motivo in (
        'en_persona', 'por_mensaje', 'preseleccion_sin_cuenta', 'sin_acceso',
        'conversacion_horario', 'documento', 'otro'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'disponibilidad_registro_otro_con_texto') then
    alter table disponibilidades add constraint disponibilidad_registro_otro_con_texto check (
      (registro_motivo is distinct from 'otro' or length(trim(coalesce(registro_detalle, ''))) >= 5)
      and (registro_detalle is null or length(registro_detalle) <= 300));
  end if;
end;
$$;

comment on column disponibilidades.registro_motivo is
  'Por qué la registró otra persona (líder o DO) y no ella misma. Null cuando la envió ella. 0589.';
comment on column disponibilidades.registro_detalle is
  'El texto de «Otro» (obligatorio en ese caso) o una aclaración del registro. 0589.';

-- ═══ PARTE 2 · La puerta, su registro y la comprobación ═════════════════════
-- Se pega DESPUÉS de la parte 1 y sola.

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'disponibilidades' and column_name = 'registro_motivo')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'disponibilidades' and column_name = 'registro_detalle')
     or not exists (select 1 from pg_constraint where conname = 'disponibilidad_registro_otro_con_texto') then
    raise exception 'Falta la PARTE 1 (las columnas del registro): pégala primero y sola, y después esta.';
  end if;
end;
$$;

drop function if exists fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text);

create or replace function fn_disponibilidad_registrar(
  p_persona_id uuid, p_tipo text, p_motivo text, p_desde date, p_hasta date, p_bloques jsonb,
  p_horario_fijo boolean default false, p_nota text default null,
  p_registro_motivo text default null, p_registro_detalle text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  v_id uuid;
begin
  if v_yo is null or v_yo = p_persona_id then
    raise exception 'Tu propia disponibilidad la mandas desde «Lo mío», y la aprueba otra persona.';
  end if;
  -- ⇩ CAMBIO 0589 ⇩ antes: solo fn_es_admin_o_lider(). Ahora la misma regla que aprueba.
  if fn_puede_resolver_disponibilidad(p_persona_id) is not true then
    raise exception 'La registra su líder de equipo (si es de su sede) o Desarrollo Organizacional.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no está activa.';
  end if;
  -- ⇩ CAMBIO 0589 ⇩ el motivo del registro.
  if p_registro_motivo is null or p_registro_motivo not in (
       'en_persona', 'por_mensaje', 'preseleccion_sin_cuenta', 'sin_acceso',
       'conversacion_horario', 'documento', 'otro') then
    raise exception 'Elige por qué la registras tú y no ella.';
  end if;
  if p_registro_motivo = 'otro' and length(trim(coalesce(p_registro_detalle, ''))) < 5 then
    raise exception 'Escribe por qué la registras (al menos 5 caracteres).';
  end if;

  perform pg_advisory_xact_lock(hashtext('disponibilidad:' || p_persona_id::text));
  v_id := fn_disponibilidad_guardar_interno(p_persona_id, p_tipo, p_motivo, p_desde, p_hasta,
                                            coalesce(p_bloques, '[]'::jsonb), p_nota, 'aprobada', v_yo, p_horario_fijo);
  update disponibilidades
     set registro_motivo = p_registro_motivo, registro_detalle = nullif(trim(p_registro_detalle), '')
   where id = v_id;
  return v_id;
end;
$$;

comment on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text) is
  'Su líder de equipo (integrantes de su sede), DO o admin registra la disponibilidad de una persona por ella, '
  'con el motivo del registro; entra aprobada y reemplaza la que tenía pendiente. Nunca la propia. 0584, 0589.';

revoke all on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text) from public, anon;
grant execute on function fn_disponibilidad_registrar(uuid, text, text, date, date, jsonb, boolean, text, text, text) to authenticated;

-- Registro

insert into migraciones_aplicadas (numero, nombre) values (589, 'la_lider_registra_la_disponibilidad')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  (select count(*) from pg_proc where proname = 'fn_disponibilidad_registrar') = 1              as una_sola_version,
  to_regprocedure('fn_disponibilidad_registrar(uuid,text,text,date,date,jsonb,boolean,text,text,text)') is not null as la_nueva_existe,
  exists (select 1 from information_schema.columns
           where table_name = 'disponibilidades' and column_name = 'registro_motivo')            as tiene_el_motivo,
  exists (select 1 from pg_constraint where conname = 'disponibilidad_registro_otro_con_texto') as otro_pide_texto,
  (select md5(prosrc) || ' · ' || length(prosrc) from pg_proc where proname = 'fn_disponibilidad_registrar') as md5_de_llegada,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 589)              as registro;
