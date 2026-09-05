-- ============================================================================
-- 0237_la_mitad_de_la_0213_que_produccion_nunca_recibio.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el motor de FALTAS deje de agravar con documentos que nunca se
--   entregaron. Es la mitad de la 0213 que producción no llegó a recibir.
--
-- QUÉ ASUME
--   Que `fn_tardanza_escalon` ya devuelve seis columnas, o sea que la 0232 está
--   aplicada. Si no lo estuviera, lo correcto es pegar la 0213 entera y no esto.
--
-- ── POR QUÉ EXISTE ESTA MIGRACIÓN Y NO SE PEGA LA 0213 ──────────────────────
--
-- Medido el 2026-08-12 contra producción: `migraciones_aplicadas` tiene 21
-- números de la 200 en adelante y le faltan dos, **0213 y 0233**. La 0213 toca
-- DOS funciones:
--
--   fn_tardanza_escalon          la pisó después la 0232, así que ese lado
--                                quedó bien por casualidad
--   fn_expediente_generar_falta  nunca llegó — y esta es la que falta
--
-- Y LA 0213 NO SE PUEDE PEGAR AHORA. Comprobado ejecutándola contra una base
-- con la 0232 puesta:
--
--     ERROR:  cannot change return type of existing function
--     DETAIL: Row type defined by OUT parameters is different.
--     HINT:   Use DROP FUNCTION fn_tardanza_escalon(uuid) first.
--
-- Su `fn_tardanza_escalon` devuelve cinco columnas y la viva devuelve seis.
-- Postgres se niega y **aborta la migración entera**, así que tampoco entraría
-- la función de faltas — que es lo único que hacía falta. Forzarlo soltando la
-- función primero sería peor: devolvería la escalera de tres peldaños y
-- desharía la 0232, que es justo lo que se acaba de arreglar.
--
-- ── QUÉ ARREGLA, EN CASTELLANO ──────────────────────────────────────────────
--
-- El artículo 56 del Reglamento: un documento firmado y NO entregado «no está
-- vigente, no agrava, no habilita el escalón siguiente y no constituye sanción
-- disciplinaria previa para los efectos del literal h) del artículo 25 de la
-- LPCL». Y los doce meses de vigencia corren desde la ENTREGA, no desde la
-- firma.
--
-- Hoy, en faltas, un memo firmado y guardado en un cajón cuenta como antecedente
-- para subir de escalón. Nadie está en umbral de faltas ahora mismo, así que no
-- ha hecho daño todavía — pero el motor de tardanzas ya lo respeta y el de
-- faltas no, y dos mitades del mismo sistema con reglas distintas es como se
-- arregla una y se olvida la otra.
--
-- ── LO QUE NO HACE ──────────────────────────────────────────────────────────
--
-- No toca `fn_tardanza_escalon`. Ni una línea. Lo que hay vivo es la versión de
-- la 0232 y así se queda.
--
-- No anota el número 213 en `migraciones_aplicadas`: la 0213 sigue sin
-- aplicarse y el registro tiene que seguir diciéndolo. Anotarla sería tapar el
-- hueco en vez de explicarlo, y ese registro es lo único que se puede consultar
-- para saber qué hay en producción.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Restaurando `fn_expediente_generar_falta` desde la 0202. Revertir significa
--   volver a agravar con papeles que nadie recibió.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_expediente_generar_falta(p_persona_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prev     record; v_has_prev boolean := false; v_vigente boolean := false;
  v_cutoff   date := date '2000-01-01';
  v_full     record; v_new record;
  v_nivel    text; v_hechos jsonb; v_desde date; v_hasta date;
  v_id       uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de falta para esta persona.';
  end if;
  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'falta' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de falta pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- ART. 56 DEL RIT: solo agrava lo ENTREGADO, y los doce meses corren desde
  -- la entrega. Un documento firmado y guardado en un cajón no es antecedente.
  select id, nivel, periodo_hasta, entregado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'falta' and estado = 'entregado'
  order by entregado_at desc limit 1;
  v_has_prev := found;
  if v_has_prev then
    v_vigente := v_prev.entregado_at >= now() - interval '12 months';
    if v_vigente and v_prev.periodo_hasta is not null then v_cutoff := v_prev.periodo_hasta; end if;
  end if;

  -- art. 25-h sobre TODO el histórico (hayan sido o no sancionadas)
  select * into v_full from fn_falta_contadores(p_persona_id, fn_hoy_lima() - 180);

  if coalesce(v_full.consecutivas,0) >= 4 or coalesce(v_full.en_30,0) >= 6 or coalesce(v_full.en_180,0) >= 16 then
    -- NON BIS IN IDEM, también aquí.
    -- La ley deja MIRAR todo el histórico para probar que se alcanzó el umbral,
    -- pero no deja volver a reprochar un hecho ya reprochado. Sin esto, una vez
    -- superado el umbral cada pulsación de "Generar borrador" producía otra
    -- imputación idéntica sobre exactamente las mismas faltas — indefinidamente,
    -- porque esas faltas siguen dentro de la ventana de 180 días. El único freno
    -- era el chequeo de borrador pendiente, que se levanta al firmar el anterior.
    if (select count(*) from unnest(v_full.fechas) as f where f > v_cutoff) = 0 then
      raise exception 'No corresponde: todas esas faltas ya quedaron cubiertas por el documento anterior (hasta el %). Para volver a sancionar hace falta al menos una falta nueva.',
        to_char(v_cutoff, 'DD/MM/YYYY');
    end if;
    -- Y el candado que ya existía, que vivía solo en la rama de escalación y por
    -- eso esta nunca lo veía.
    if v_vigente and v_has_prev and v_prev.nivel = 'imputacion' then
      raise exception 'Ya hay una imputación vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
    end if;
    v_nivel  := 'imputacion';
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_full.fechas) as f);
    v_desde  := (select min(f) from unnest(v_full.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_full.fechas) as f);
  else
    -- escalación sobre faltas NUEVAS (non bis in idem)
    select * into v_new from fn_falta_contadores(p_persona_id, v_cutoff + 1);
    if coalesce(v_new.en_180,0) < 1 then
      raise exception 'No corresponde: sin faltas injustificadas nuevas.';
    end if;
    if v_vigente and v_prev.nivel = 'imputacion' then
      raise exception 'Ya hay una imputación vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
    elsif v_vigente and v_prev.nivel = 'suspension' then
      v_nivel := 'imputacion';                              -- reincidencia sobre suspensión
    elsif v_vigente and v_prev.nivel = 'amonestacion' then
      v_nivel := 'suspension';                              -- reincidencia sobre amonestación
    else
      v_nivel := 'amonestacion';                            -- 1ª falta injustificada
    end if;
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_new.fechas) as f);
    v_desde  := (select min(f) from unnest(v_new.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_new.fechas) as f);
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'falta', v_nivel, v_hechos, v_desde, v_hasta,
    case when v_has_prev then v_prev.id else null end,
    case when v_nivel = 'suspension' then 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    null);
  return v_id;
end;
$function$;

-- El `create or replace` conserva los permisos porque no hay `drop` y la firma
-- no cambia. Se re-declaran igual, que es la costumbre de la casa desde que un
-- drop sin grant dejó el semáforo disciplinario ciego dos días (0189 → 0204).
grant execute on function public.fn_expediente_generar_falta(uuid) to authenticated;
revoke execute on function public.fn_expediente_generar_falta(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (237, 'la_mitad_de_la_0213_que_produccion_nunca_recibio')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
select
  (select prosrc ilike '%entregado_at%' from pg_proc
    where proname = 'fn_expediente_generar_falta')            as faltas_exige_entregado,
  -- Y que NO se haya tocado la escalera: seis columnas es la 0232.
  (select pg_get_function_result(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_tardanza_escalon')
                                                              as escalera_intacta,
  has_function_privilege('authenticated',
    'public.fn_expediente_generar_falta(uuid)'::regprocedure, 'EXECUTE')
                                                              as generador_ejecutable,
  -- Cuenta filas, así que 0 = NO aplicada. En producción tiene que salir 0: la
  -- 0213 sigue sin aplicarse y el registro debe seguir diciéndolo. (En un
  -- Postgres local reconstruido desde las migraciones sale 1, y también es
  -- correcto: ahí sí se aplicó, en su orden.)
  (select count(*) from migraciones_aplicadas where numero = 213)
                                                              as la_213_anotada_0_es_lo_esperado;
