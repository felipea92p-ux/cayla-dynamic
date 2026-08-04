-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 106_ningun_guard_deja_pasar_al_terminal.test.sql — El guardián de los guards
-- ============================================================================
-- Hermana de la 92. Esa vigila `current_date`; esta vigila la forma del guard.
--
-- EL PROBLEMA, en tres pasos:
--   · Un guard escrito «if not (A or B or C)» parece equivalente a
--     «if (A or B or C) is not true», y no lo es.
--   · Para una identidad autenticada SIN fila en personas —que es exactamente lo
--     que es la cuenta de la Mac mini de cada sede— fn_persona_actual_id()
--     devuelve null, así que «p_persona_id = fn_persona_actual_id()» es null y la
--     expresión completa queda «false or null or null» = NULL.
--   · «not null» es null, el IF no entra, y el raise nunca se dispara. La función
--     sigue de largo y escribe.
--
-- Este error entró SEIS veces: lo cerró la 0078 para las funciones de entonces, y
-- volvió en la 0125 —tres funciones a la vez— porque se copió el cuerpo de la
-- 0061 sin releer la regla. La 0126 lo cerró otra vez.
--
-- La 0078 arregló los booleanos para que no devolvieran null, y volvió a pasar
-- igual: cualquier comparación de un UUID contra una función que puede devolver
-- null produce null por su cuenta. Por eso la defensa no es arreglar las
-- funciones de permiso, es la FORMA del guard. Y por eso esto es una prueba y no
-- una nota en el CLAUDE.md: la nota ya estaba escrita y no alcanzó.
--
-- Si estás leyendo esto porque acaba de fallar: no busques un rodeo. Cambiá
-- «if not ( … )» por «if ( … ) is not true» y seguí.
--
-- Qué NO cuenta como infracción:
--   · Mencionarlo en un comentario (avisar del peligro es lo correcto).
--   · Las funciones de extensiones: no son nuestras.
--   · «if not <un booleano suelto>» sin paréntesis de disyunción — no es la forma
--     peligrosa, aunque sigue siendo mejor estilo usar `is not true`.
-- ============================================================================
begin;
select plan(2);

-- Quita los comentarios de línea antes de buscar, para que avisar del peligro en
-- un comentario no cuente como cometerlo.
create or replace function _sin_comentarios_106(p_src text)
returns text language sql immutable as $$
  select string_agg(split_part(linea, '--', 1), E'\n')
  from unnest(string_to_array(p_src, E'\n')) as linea;
$$;

-- ── 1 · Ninguna función usa la forma peligrosa ───────────────────────────────
-- El patrón busca «if not (» seguido, en la misma expresión, de alguna de las
-- funciones de permiso. Es la combinación que produce el null que se cuela.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and _sin_comentarios_106(pg_get_functiondef(p.oid))
         ~* 'if\s+not\s*\(\s*(fn_es_admin_o_lider|fn_es_admin|fn_rol_actual|fn_persona_actual_id)'),
  '',
  'ningún guard usa «if not ( … )» — con una identidad sin fila en personas eso da null y deja pasar; usa «is not true»');

-- ── 2 · Y la prueba de fuego: que de verdad no deje pasar ────────────────────
-- No alcanza con vigilar la forma del texto: se comprueba el comportamiento.
-- Se simula la sesión de un terminal —autenticada, sin fila en personas— y se
-- exige que las tres funciones de la ficha personal se nieguen.
--
-- Se usa un uuid que no existe en auth.users a propósito: lo que importa es que
-- fn_persona_actual_id() devuelva null, que es la condición que abría el hueco.
select lives_ok($$
  do $prueba$
  declare
    v_victima uuid;
    v_fallaron int := 0;
    v_pasaron  text := '';
  begin
    perform set_config('request.jwt.claim.sub',
                       '99999999-9999-9999-9999-999999999999', true);

    select id into v_victima from personas limit 1;
    if v_victima is null then
      -- Base sin personas: no hay a quién atacar y la prueba no aplica.
      return;
    end if;

    begin
      perform fn_set_datos_personales(v_victima, 'PISADO', null, null, null, null,
        'BANCO DEL ATACANTE', '0000', null, null, null, null, null,
        null, null, null, null, null);
      v_pasaron := v_pasaron || 'fn_set_datos_personales ';
      v_fallaron := v_fallaron + 1;
    exception when others then null;   -- se negó: es lo correcto
    end;

    begin
      perform fn_set_derechohabiente(null, v_victima, 'Falso', 'Familiar', 'hijo',
        null, '2018-01-01', true, true);
      v_pasaron := v_pasaron || 'fn_set_derechohabiente ';
      v_fallaron := v_fallaron + 1;
    exception when others then null;
    end;

    if v_fallaron > 0 then
      raise exception 'Una sesión sin fila en personas pudo escribir con: %', v_pasaron;
    end if;
  end
  $prueba$;
$$, 'una sesión autenticada sin fila en personas no puede tocar la ficha de nadie');

drop function _sin_comentarios_106(text);

select * from finish();
rollback;
