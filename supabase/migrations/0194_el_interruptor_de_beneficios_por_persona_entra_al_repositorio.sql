-- ============================================================================
-- 0194_el_interruptor_de_beneficios_por_persona_entra_al_repositorio.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que `personas.devenga_beneficios`, `personas.devenga_hasta` y
--   `fn_set_devenga_beneficios` existan también como archivo. Hoy corren en
--   producción y en ningún otro sitio.
--
--   **NO CAMBIA NADA.** Es idempotente: en producción no hace nada porque ya
--   está todo, y en una base reconstruida desde cero lo crea igual. Ni un
--   céntimo se mueve.
--
-- QUÉ ASUME
--   Nada. Los cuerpos se pidieron a producción con `pg_get_functiondef` el
--   2026-08-08 y se pegan tal cual, sin una coma de diferencia.
--
-- ── QUÉ ES ESTO ─────────────────────────────────────────────────────────────
--
-- El interruptor por persona que decide quién devenga CTS, gratificación y
-- vacaciones, con una fecha de corte opcional. Es el trabajo que Felipe dio por
-- perdido —«en otra sesión arreglé esto pero se perdió»—: no se perdió, llevaba
-- semanas corriendo en producción sin estar en ningún archivo, sin una prueba y
-- sin que nadie hubiera leído su código.
--
-- Lo que hace, leído de su propio cuerpo: escribe la bandera, y si se APAGA sin
-- dar fecha congela HOY en `devenga_hasta` —«dejarlo en null habría hecho que el
-- devengo siguiera corriendo, justo lo contrario de lo que la pantalla dice»—.
-- Exige sesión identificada y deja rastro en `correcciones_auditoria`. Está bien
-- escrito; el problema nunca fue su calidad, fue que no existía como plano.
--
-- ⚠️ ── LO QUE HAY QUE SABER ANTES DE CONFIAR EN ESE BOTÓN ───────────────────
--
-- HOY NO HACE NADA. Medido el 2026-08-08, no deducido:
--
--   · `fn_devenga_beneficios(p_tipo)` —la que deciden las provisiones— tiene
--     como cuerpo entero `select p_tipo = 'planilla'`. Mira el TIPO DE VÍNCULO
--     de la persona, no esta columna.
--   · Sus cuatro consumidores —fn_provisiones, fn_cts_trunca,
--     fn_grati_trunca_bruta y fn_vacaciones_truncas— la llaman con el tipo.
--   · Ninguna función del esquema lee `personas.devenga_beneficios`.
--   · Y no es que producción tenga otra versión: el md5 de
--     `fn_devenga_beneficios` (5c99fb45…) y el de `fn_provisiones` (c0967791…)
--     son IDÉNTICOS en producción y en el repositorio.
--
-- O sea: el interruptor se escribe, se audita, y nadie lo lee. Quien lo apague
-- verá la pantalla decir que sí y las provisiones seguir corriendo igual.
--
-- ESTA MIGRACIÓN NO LO CONECTA, Y ES A PROPÓSITO. Conectarlo cambia lo que se
-- provisiona por persona: es una decisión de negocio sobre dinero, a tres
-- semanas del cierre del 28/08, y le toca a Felipe. Rescatar y arreglar son dos
-- pasos, y mezclarlos haría imposible saber si una diferencia vino de mover
-- código o de cambiar la regla.
--
-- Lo que hay que decidir, cuando toque: hoy `devenga_beneficios` es UN SOLO
-- booleano para los tres beneficios a la vez. La decisión sobre Carlos Espejo
-- —«grati y CTS sí, vacaciones no»— no cabe en un booleano. O se parte en tres
-- banderas, o se resuelve por otro camino.
--
-- CÓMO SE REVIERTE
--   No se revierte: quitar esto borraría de producción algo que ya está en uso.
--   Si algún día el interruptor se retira, será con su propia migración y su
--   propio porqué.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final debe devolver las dos columnas y la función.
-- ============================================================================

-- ── Las dos columnas ────────────────────────────────────────────────────────
-- `if not exists` porque en producción ya están: esta migración tiene que poder
-- pegarse ahí sin dar error, que es la única forma de que el plano y el edificio
-- vuelvan a coincidir sin tocar el edificio.
alter table personas add column if not exists devenga_beneficios boolean;
alter table personas add column if not exists devenga_hasta      date;

comment on column personas.devenga_beneficios is
  'Interruptor por persona del devengo de CTS, gratificación y vacaciones. '
  'NULL = se decide por el tipo de vínculo, que es el comportamiento de siempre. '
  'OJO: al 2026-08-08 ninguna función lo lee todavía — ver la 0194.';

comment on column personas.devenga_hasta is
  'Fecha en que se congeló el devengo al apagar el interruptor. La escribe '
  'fn_set_devenga_beneficios; apagar sin dar fecha congela el día de hoy.';

-- ── La función, tal como está en producción ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_devenga_beneficios(p_persona_id uuid, p_devenga boolean, p_hasta date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_antes boolean; v_yo uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede cambiar el devengo de beneficios.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien hace el cambio, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  select devenga_beneficios into v_antes from personas where id = p_persona_id;
  if not found then raise exception 'No existe esa persona.'; end if;

  -- Apagar sin fecha congela HOY. Es lo que quiere quien lo apaga, y dejarlo en
  -- null habria hecho que el devengo siguiera corriendo — justo lo contrario de
  -- lo que la pantalla dice que hace.
  update personas
     set devenga_beneficios = p_devenga,
         devenga_hasta = case
           when p_devenga is not true
             then coalesce(p_hasta, (now() at time zone 'America/Lima')::date)
           else null
         end
   where id = p_persona_id;

  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.devenga_beneficios',
          coalesce(v_antes::text, 'default del vinculo'),
          coalesce(p_devenga::text, 'default del vinculo'),
          'Cambio de devengo de beneficios desde la pantalla de Equipo',
          v_yo);
end;
$function$;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (194, 'el_interruptor_de_beneficios_por_persona_entra_al_repositorio')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las dos primeras deben decir 2 y 1. La tercera es la que importa de verdad:
-- mientras diga 0, el interruptor sigue sin estar conectado a nada.
select
  (select count(*) from pg_attribute a join pg_class c on c.oid = a.attrelid
    where c.relname = 'personas'
      and a.attname in ('devenga_beneficios', 'devenga_hasta')) as columnas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_set_devenga_beneficios') as la_funcion,
  -- El patrón exige que ANTES de la palabra no venga `_` ni una letra. Sin eso
  -- contaba 4 funciones que no leen nada: contienen `fn_devenga_beneficios` —la
  -- LLAMADA a la función que mira el tipo de vínculo— y un `like '%…%'` no
  -- distingue una cosa de la otra. Cuatro falsos positivos habrían dado por
  -- conectado un interruptor que no lo está.
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosrc ~ '(^|[^_[:alnum:]])devenga_beneficios'
      and p.proname <> 'fn_set_devenga_beneficios') as funciones_que_lo_leen;
