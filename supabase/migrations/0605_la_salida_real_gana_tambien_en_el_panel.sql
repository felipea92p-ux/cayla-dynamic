-- ============================================================================
-- 0605 · La salida real gana a la del auto-cierre también desde Correcciones
-- ============================================================================
--
-- QUÉ PROMETE
--   · Agregar desde Correcciones la salida final de un día que cerró el sistema
--     deja UNA sola salida final: la del sistema se anula (no se borra) y queda
--     «auto_cierre_reemplazado» en la auditoría, con quién lo hizo.
--   · Si DO ya CONFIRMÓ la salida del sistema, agregar otra se rechaza con un
--     aviso que dice qué hacer (corregir su hora o anularla primero).
--   · Confirmar la salida del sistema cuando el día ya tiene otra salida final
--     activa también se rechaza: es la otra puerta al mismo defecto.
--   · Nada más cambia: las demás marcas, los días sin auto-cierre, los candados
--     de periodo pagado y de expediente formal siguen idénticos.
--
-- EL DEFECTO (hallazgos-abiertos.md, Crítica 14; tarea 1 de la semana del 9-nov)
--   El auto-cierre pone la salida a la hora programada y deja el día como
--   «auto_cerrada_pendiente». Si DO agregaba la salida real con «Agregar un
--   marcaje», fn_agregar_marcaje la insertaba sin mirar la del sistema, y
--   fn_recalcular_jornada (0446) se queda con la ÚLTIMA salida_final del día:
--     · salió antes de su hora (16:00 contra 18:00) → se pagaban 9 h en vez de 7,
--       y el día seguía «pendiente» aunque DO creyera haberlo arreglado;
--     · salió después → se pagaba bien, pero el día quedaba con dos salidas y una
--       secuencia imposible.
--   Medido en local antes de esta migración con la prueba 492: 2 salidas activas
--   y 9.00 h donde correspondían 7.00.
--
--   El terminal lo resolvía desde la 0320 («la marca real gana a la que adivinó
--   el robot»). El panel entra por otra función, y esa regla nunca llegó.
--
-- POR QUÉ ASÍ (decidido por Felipe el 2026-11-08, entre tres opciones)
--   · Se descartó un trigger sobre `marcajes` que retirara la salida del sistema
--     por cualquier camino: es lo más completo, pero mete un efecto escondido en
--     la tabla del marcaje en tienda y obliga a volver a probar el terminal entero.
--   · Se descartó arreglarlo solo en la pantalla: la base quedaba abierta.
--   · La regla de la 0320 pasa a una función propia, fn_retirar_salida_del_robot,
--     para que exista en UN lugar. El terminal conserva por ahora su copia:
--     migrarlo es tocar fn_registrar_marcaje y va aparte.
--
-- QUÉ ASUME
--   · Que en producción fn_agregar_marcaje y fn_confirmar_auto_cierre son las de
--     la 0437. Se comprueba AL PEGAR, abajo, con md5 en sus formas conocidas
--     (tal cual, sin comentarios, con \r\n): si no coincide, PARA sin aplicar nada.
--   · Que fn_fecha_de_jornada (0307) existe, igual que la usa la 0366.
--
-- LOS DÍAS QUE YA QUEDARON CON DOS SALIDAS
--   Esta migración NO los toca (decisión de Felipe, 2026-11-08: se listan para
--   que DO elija en cada uno). Correcciones los muestra con un aviso propio, y la
--   consulta para contarlos en producción está en estado.md.
--
-- CÓMO SE REVIERTE
--   Volver a pegar los cuerpos de fn_agregar_marcaje y fn_confirmar_auto_cierre
--   de la 0437, y `drop function fn_retirar_salida_del_robot(uuid, date,
--   timestamptz, uuid, text)`. Las marcas que esta migración anuló siguen en el
--   historial con su motivo; se reactivan una por una desde Correcciones.
--
-- md5 de partida, medidos en el Postgres local con las 604 migraciones de main
-- (75bbbcd). La confirmación contra producción la hace el bloque de abajo AL
-- PEGAR, no una persona de memoria:
--   fn_agregar_marcaje         tal cual 22017a5fd5b6a7b1aaa4e0af3b883f17 · 2252 caracteres
--                              sin comentarios 23ffd96e15416f5806e12c17caad80ee
--   fn_confirmar_auto_cierre   tal cual c49270228c71bf74e6a4b75a3ab4078f · 2548 caracteres
--                              sin comentarios 7b5f69fbfdead7ff2fdbb044f52e5173
-- La guarda los mide sobre el cuerpo sin \r, así que el mismo código pegado
-- desde Windows (crlf_tal_cual daebe56b… y 07efbba1… de donde-vive.sh) también pasa.
-- ============================================================================

-- ── 1 · Guarda: producción tiene que tener las versiones de la 0437 ──────────
-- Si ya se pegó esta migración (repegar), las funciones ya son las de la 0605 y
-- se deja pasar: la marca es fn_retirar_salida_del_robot, que solo crea esta.
do $$
declare
  r record;
  -- Por función: [tal cual, sin comentarios]. Se miden sobre el cuerpo SIN \r,
  -- así el mismo código pegado desde Windows (0401) coincide igual.
  v_esperado jsonb := '{
    "fn_agregar_marcaje":       ["22017a5fd5b6a7b1aaa4e0af3b883f17", "23ffd96e15416f5806e12c17caad80ee"],
    "fn_confirmar_auto_cierre": ["c49270228c71bf74e6a4b75a3ab4078f", "7b5f69fbfdead7ff2fdbb044f52e5173"]
  }'::jsonb;
begin
  if to_regprocedure('public.fn_retirar_salida_del_robot(uuid, date, timestamptz, uuid, text)') is not null then
    raise notice '0605 · ya estaba aplicada: se vuelve a pegar sin comprobar las versiones de la 0437.';
    return;
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname in ('fn_agregar_marcaje', 'fn_confirmar_auto_cierre')) <> 2 then
    raise exception '0605 · PARA. Esperaba exactamente una fn_agregar_marcaje y una fn_confirmar_auto_cierre (sin sobrecargas). No se aplicó nada.';
  end if;

  for r in
    select q.proname, q.largo, q.retornos,
           md5(q.cuerpo) as tal_cual,
           md5(array_to_string(array(
             select regexp_replace(l, '[[:space:]]*--.*$', '')
               from unnest(string_to_array(q.cuerpo, chr(10))) as l
              where btrim(l) not like '--%'), chr(10))) as sin_comentarios
      from (select p.proname,
                   replace(p.prosrc, chr(13), '') as cuerpo,
                   length(p.prosrc) as largo,
                   length(p.prosrc) - length(replace(p.prosrc, chr(13), '')) as retornos
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('fn_agregar_marcaje', 'fn_confirmar_auto_cierre')) q
  loop
    if r.tal_cual <> (v_esperado -> r.proname ->> 0)
       and r.sin_comentarios <> (v_esperado -> r.proname ->> 1) then
      raise exception '0605 · PARA. % en esta base es % (% caracteres, % retornos \r; sin comentarios %) y no es la de la 0437. Producción tiene otra versión: no se aplicó nada. Compruébalo con ./scripts/donde-vive.sh %.',
        r.proname, r.tal_cual, r.largo, r.retornos, r.sin_comentarios, r.proname;
    end if;
  end loop;
end
$$;

-- ── 2 · fn_retirar_salida_del_robot: la regla de la 0320, en un solo lugar ───
-- Anula (no borra) la salida_final que puso el auto-cierre en una jornada,
-- cuando una persona aporta la salida real. Mismas condiciones que la 0320:
--   · solo origen 'auto_cierre'      → una marca de una persona no se toca;
--   · solo si NO está 'revisada'     → una confirmación humana manda;
--   · solo la que sigue activa.
-- No mira el periodo pagado ni el expediente formal: esos candados los pone
-- quien la llama, antes, como ya hacen fn_agregar_marcaje y la 0320.
-- Devuelve el id de la marca retirada, o null si no había nada que retirar.
--
-- Hoy la usa fn_agregar_marcaje. El terminal (fn_registrar_marcaje, 0366)
-- conserva su copia de la 0320 a propósito: pasarlo a esta función es tocar
-- el camino del marcaje en tienda, y eso va en su propia migración, con su
-- propia prueba del terminal.
create or replace function public.fn_retirar_salida_del_robot(
  p_persona_id uuid,
  p_fecha      date,
  p_ts_real    timestamptz,
  p_actor      uuid,
  p_motivo     text
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_sintetica marcajes;
begin
  select * into v_sintetica
    from marcajes m
   where m.persona_id = p_persona_id
     and m.tipo = 'salida_final'
     and m.origen = 'auto_cierre'
     and m.anulada_at is null
     and m.estado_revision is distinct from 'revisada'
     and fn_fecha_de_jornada(m.timestamp_marca, m.fecha_jornada) = p_fecha
   order by m.timestamp_marca desc, m.id desc
   limit 1
   for update;

  if not found then
    return null;
  end if;

  update marcajes
     set anulada_at     = now(),
         anulada_por    = p_actor,
         anulada_motivo = 'Se registró la salida real: el auto-cierre había supuesto '
                          || 'la hora programada (0605).'
   where id = v_sintetica.id;

  insert into correcciones_auditoria
    (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo,
     corregido_por, motivo)
  values (v_sintetica.id, p_persona_id, 'auto_cierre_reemplazado',
          'salida_final @ ' || v_sintetica.timestamp_marca::text,
          'salida_final @ ' || p_ts_real::text,
          p_actor,
          coalesce(nullif(trim(coalesce(p_motivo, '')), ''),
                   'Se registró la salida real y la marca del sistema se retira (0605).'));

  return v_sintetica.id;
end;
$function$;

-- SECURITY DEFINER porque escribe en correcciones_auditoria, y desde la 0508 eso
-- solo lo hacen funciones que corren como su dueño (la prueba 402 lo exige: una
-- INVOKER más fallaría con «permission denied» el día que alguien la llame desde
-- otra parte). Y por eso mismo NO es una puerta para la app: se le quita el
-- execute a todos. Sin esto, cualquiera con sesión podría anular la salida de
-- otra persona saltándose el motivo, el corrector y los candados.
revoke execute on function public.fn_retirar_salida_del_robot(uuid, date, timestamptz, uuid, text)
  from public, anon, authenticated;

-- ── 3 · fn_confirmar_auto_cierre (cuerpo de la 0437 + CAMBIO 0605) ─────────
CREATE OR REPLACE FUNCTION public.fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
        v_otra timestamptz;  -- CAMBIO 0605
begin
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.origen <> 'auto_cierre' then
    raise exception 'Solo se confirma una marca puesta por el auto-cierre.';
  end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada.';
  end if;
  if v_ant.estado_revision = 'revisada' then
    raise exception 'Ese auto-cierre ya está confirmado.';
  end if;

  -- CAMBIO 0307 · Acá `v_fecha` no lo usa nadie más que el candado, así que
  -- pasa a ser directamente la fecha de la JORNADA: una marca de madrugada
  -- pertenece al turno que cierra, no al día del calendario en que cae.
  v_fecha := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  -- CAMBIO 0327 · El candado mira el GRUPO (tipo_vinculo) de la persona
  -- dueña de la marca, no el periodo entero: si planilla ya pagó pero RxH
  -- todavía no, confirmar un auto-cierre de alguien de planilla sigue
  -- bloqueado aunque el grupo RxH de ese periodo siga abierto.
  if fn_fecha_en_periodo_pagado(v_fecha, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: confirmarla haría que ese día empiece a medir salida anticipada y tiempo adicional, cambiando una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0437 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(v_ant.persona_id, v_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado construido sobre este marcaje: confirmarlo cambiaría cómo se mide ese día (salida anticipada, tiempo adicional), el mismo hecho sobre el que ya se construyó ese expediente. Resuelve o anula el expediente en Disciplina antes de confirmar esta marca.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0605 ⇩⇩⇩ NO SE CONFIRMA LA DEL SISTEMA SI YA HAY UNA REAL.
  -- Es la otra puerta al día con dos salidas finales: alguien agregó la salida
  -- real y después otra persona pulsa «Confirmar» sobre la del sistema. Las dos
  -- quedarían activas y la jornada pagaría la más tardía. Se rechaza y se dice
  -- cuál es la otra salida, para que DO anule la que no corresponda.
  select m.timestamp_marca into v_otra
    from marcajes m
   where m.persona_id = v_ant.persona_id
     and m.tipo = 'salida_final'
     and m.anulada_at is null
     and m.id <> p_marcaje_id
     and fn_fecha_de_jornada(m.timestamp_marca, m.fecha_jornada) = v_fecha
   order by m.timestamp_marca desc, m.id desc
   limit 1;
  if found then
    raise exception 'Ese día ya tiene otra salida final activa (a las %): confirmar la que puso el sistema dejaría dos salidas finales, y se pagaría la más tardía. Anula la que no corresponda y el día queda con una sola.',
      to_char(v_otra at time zone 'America/Lima', 'HH24:MI');
  end if;

  update marcajes set estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'auto_cierre_confirmado',
          'pendiente_revision', 'revisada', v_corr,
          coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Confirmado: esa es su salida final.'));

  return v_nuevo;
end;
$function$;


-- ── 4 · fn_agregar_marcaje (cuerpo de la 0437 + CAMBIO 0605) ───────────────
CREATE OR REPLACE FUNCTION public.fn_agregar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_ts timestamp with time zone, p_motivo text, p_motivo_otro text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sede uuid; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  v_fecha := (p_ts at time zone 'America/Lima')::date;

  if fn_fecha_en_periodo_pagado(v_fecha, p_persona_id) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: agregar un marcaje ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0437 ⇩⇩⇩ NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL.
  if fn_dia_con_expediente_formal(p_persona_id, v_fecha) then
    raise exception 'Ese día ya tiene un expediente disciplinario firmado o entregado construido sobre él: agregar un marcaje ahí cambiaría el hecho que ese expediente ya documentó. Resuelve o anula el expediente en Disciplina antes de agregar este marcaje.';
  end if;

  v_corr := fn_verificar_corrector(p_persona_id);

  -- La sede la manda el DÍA, no el escritorio: si la persona ya marcó ese día
  -- (por ejemplo, de visita en otra tienda), la corrección se graba en esa misma
  -- sede. Solo si el día está vacío cae a su sede base. Sin esto, la jornada
  -- queda partida entre dos sedes y el terminal ve media verdad.
  select m.sede_id into v_sede
  from marcajes m
  where m.persona_id = p_persona_id
    and (m.timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and m.sede_id is not null
  order by m.timestamp_marca, m.id
  limit 1;

  if v_sede is null then
    select sede_base_id into v_sede from personas where id = p_persona_id;
  end if;
  if v_sede is null then raise exception 'Persona no encontrada.'; end if;

  -- ⇩⇩⇩ CAMBIO 0605 ⇩⇩⇩ LA SALIDA REAL GANA TAMBIÉN DESDE EL PANEL.
  -- Si el día lo cerró el sistema, su salida_final sintética seguía viva al
  -- agregar la real, y fn_recalcular_jornada se queda con la más tardía: quien
  -- salió antes de su hora programada cobraba horas que no trabajó. El terminal
  -- ya lo resolvía desde la 0320; aquí se aplica la misma regla, que ahora vive
  -- en fn_retirar_salida_del_robot.
  --
  -- Con una diferencia, decidida por Felipe el 2026-11-08: si DO ya CONFIRMÓ la
  -- salida del sistema, no se reemplaza sola. Esa confirmación fue una decisión
  -- de una persona; deshacerla tiene que ser otra decisión, a la vista.
  if p_tipo = 'salida_final' then
    if exists (
      select 1 from marcajes m
       where m.persona_id = p_persona_id
         and m.tipo = 'salida_final'
         and m.origen = 'auto_cierre'
         and m.anulada_at is null
         and m.estado_revision = 'revisada'
         and fn_fecha_de_jornada(m.timestamp_marca, m.fecha_jornada) = v_fecha
    ) then
      raise exception 'Este día ya tiene una salida final que puso el sistema y que se CONFIRMÓ como buena. Si estaba mal, corrige su hora o anúlala primero: así queda claro quién deshizo esa confirmación.';
    end if;

    perform fn_retirar_salida_del_robot(p_persona_id, v_fecha, p_ts, v_corr, trim(p_motivo));
  end if;

  insert into marcajes (client_uuid, persona_id, sede_id, tipo, motivo_otro, timestamp_marca, origen, estado_revision)
  values (gen_random_uuid(), p_persona_id, v_sede, p_tipo, p_motivo_otro, p_ts, 'admin_correccion', 'revisada')
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_nuevo.id, p_persona_id, 'marcaje_agregado', null, p_tipo::text || ' @ ' || p_ts::text, v_corr, trim(p_motivo));

  perform fn_resellar_dia(p_persona_id, v_fecha);

  return v_nuevo;
end;
$function$;


insert into migraciones_aplicadas (numero, nombre)
values (605, 'la_salida_real_gana_tambien_en_el_panel')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- Lo que se ve en el SQL Editor al terminar: las tres en true.
select to_regprocedure('public.fn_retirar_salida_del_robot(uuid, date, timestamptz, uuid, text)') is not null as retirar_existe,
       position('CAMBIO 0605' in (select prosrc from pg_proc where proname = 'fn_agregar_marcaje')) > 0 as agregar_es_0605,
       position('CAMBIO 0605' in (select prosrc from pg_proc where proname = 'fn_confirmar_auto_cierre')) > 0 as confirmar_es_0605,
       (select nombre from migraciones_aplicadas where numero = 605) as registro;
