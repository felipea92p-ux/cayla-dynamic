-- ############################################################################
-- ####  ESTA SÍ ESCRIBE. Cambia lo que una persona devenga.                ####
-- ############################################################################
--
-- apagar_un_beneficio.sql — la excepción por persona, de la 0196
--
-- ── ANTES DE CORRER ─────────────────────────────────────────────────────────
--   Cambia SOLO las dos líneas marcadas con ⇦ CAMBIA ESTO. Nada más.
--
--   · A QUIÉN     un trozo del nombre, suficiente para que sea una sola persona.
--                 Si el trozo encaja con dos, se niega: nunca adivina.
--   · QUÉ         'grati', 'cts' o 'vacaciones'. Cualquier otra cosa revienta.
--   · Y el valor: false = NO devenga · true = SÍ devenga · null = vuelve al
--                 defecto de su tipo de vínculo, que es como deshacerlo.
--
-- ── QUÉ HACE Y QUÉ NO ───────────────────────────────────────────────────────
--   Escribe la bandera y deja rastro en `correcciones_auditoria` con quién lo
--   hizo. NO toca ningún periodo ya pagado: las provisiones se recalculan en
--   vivo, así que lo que cambia es lo que se provisiona de aquí en adelante.
--
--   Y no borra nada: apagar un beneficio deja de acumularlo, no le quita a nadie
--   lo ya acumulado si eso se pagó. Eso vive en el libro de desembolsos.
--
-- ── POR QUÉ ESTE ARCHIVO NO LLEVA NINGÚN NOMBRE ESCRITO ─────────────────────
--   Porque quién devenga qué es un dato de una persona, y este repositorio no
--   guarda datos personales. El nombre lo pones tú al correrlo y se queda en tu
--   pantalla.
-- ############################################################################

do $$
declare
  -- ⇦ CAMBIA ESTO ────────────────────────────────────────────────────────────
  v_busca     text    := 'ESCRIBE AQUI PARTE DEL NOMBRE';
  v_beneficio text    := 'vacaciones';
  v_devenga   boolean := false;
  -- ───────────────────────────────────────────────────────────────────────────
  v_id uuid; v_nombre text; v_n int;
begin
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
  raise notice 'Listo: % → % = %', v_nombre, v_beneficio, coalesce(v_devenga::text, 'defecto del vínculo');
end $$;

-- ── La comprobación, que es lo único que prueba que sirvió ──────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Mira la fila de esa persona: el beneficio que apagaste tiene que estar en 0 y
-- los otros dos exactamente como estaban.
select e ->> 'nombre'        as persona,
       e ->> 'grati_total'   as gratificacion,
       e ->> 'cts_total'     as cts,
       e ->> 'vac'           as vacaciones,
       e ->> 'vac_dias'      as dias_de_vacaciones,
       e ->> 'gran_total'    as gran_total
from jsonb_array_elements(fn_provisiones((now() at time zone 'America/Lima')::date) -> 'personas') e
where (e ->> 'nombre') ilike '%' || 'ESCRIBE AQUI PARTE DEL NOMBRE' || '%';   -- ⇦ CAMBIA ESTO
