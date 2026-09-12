-- ============================================================================
-- 0426 — La declaración de ruta ya no pregunta por el taxi
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Una sola cosa, decidida por Felipe el 2026-09-12 tras ver la 0425 en
--   producción: la declaración deja de preguntar si en ocasiones usa taxi u
--   otro medio particular. Todo lo demás de la 0425 sigue igual — distrito,
--   provincia y medios de transporte de ida/vuelta se siguen declarando, y el
--   monto sigue siendo SIEMPRE la tarifa fija de la sede, nunca un cálculo.
--
--   Esta migración pasó primero por una versión que quitaba TODO lo que se
--   declara (distrito, provincia, medios, taxi) para dejar solo sede+tarifa
--   — se escribió, se probó localmente y se descartó sin llegar a
--   commitearse ni pegarse en ningún lado, al confirmar con Felipe que el
--   pedido real era más chico: solo el taxi sobraba. Se documenta acá el
--   porqué del descarte para que nadie repita la misma vuelta completa: la
--   base legal (art. 19 e) no exige declarar CÓMO se traslada la persona,
--   pero Felipe prefiere conservar distrito/provincia/medios como parte del
--   trámite igual — es una decisión de producto, no una exigencia legal, y
--   la decisión de producto es la que manda.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No cambia en NADA cómo se calcula la tarifa (sigue siendo la 0142: fija
--   por sede, S/10 Trujillo/Arequipa, S/12 Lima). No cambia el candado de la
--   0425 (vigente y al día no se puede volver a firmar sola, sin importar si
--   el distrito declarado cambia — el candado nunca miró el distrito, mira
--   `es_negativa` y `monto_declarado`).
--
-- QUÉ ASUME
--
--   `fn_confirmar_mi_declaracion_ruta` vigente es la 0425 (5 parámetros,
--   incluyendo `p_usa_taxi`) — confirmado el 2026-09-12 con
--   `./scripts/donde-vive.sh`.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_confirmar_mi_declaracion_ruta(text,text,integer,integer);
--   -- recrear fn_confirmar_mi_declaracion_ruta con el cuerpo de la 0425
--   -- (firma de 5 parámetros, con p_usa_taxi).
--   Las declaraciones ya firmadas quedan intactas: esta migración no borra ni
--   modifica ninguna fila de documentos_firmados existente.
-- ============================================================================

-- Por si esta migración se pega sobre una base que llegó a tener, aunque sea
-- localmente, la versión de 0 parámetros de una vuelta anterior de este mismo
-- cambio (nunca commiteada ni pegada en ningún lado — ver «QUÉ PROMETE»).
drop function if exists fn_confirmar_mi_declaracion_ruta();
drop function if exists fn_mi_texto_declaracion_ruta();
drop function if exists fn_mi_tarifa_movilidad();

-- Postgres no deja quitar un parámetro con `create or replace` — hay que
-- borrar la función vieja primero, mismo motivo que ya documentó la 0425.
drop function if exists fn_confirmar_mi_declaracion_ruta(text,text,integer,integer,boolean);

create function fn_confirmar_mi_declaracion_ruta(
  p_distrito         text,
  p_provincia        text,
  p_medios_ida       integer,
  p_medios_vuelta    integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo            uuid := fn_persona_actual_id();
  v_imagen        text;
  v_sede_codigo   text;
  v_tarifa        numeric;
  v_declarada     text;
  v_id            uuid;
  v_ip            text;
  v_ua            text;
  v_es_negativa   boolean;
  v_monto_anterior numeric;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  if not exists (select 1 from personas where id = v_yo and estado = 'activo')
     or not fn_persona_le_corresponde_movilidad(v_yo) then
    raise exception 'No estás en planilla ni eres practicante: no te corresponde declarar tu ruta.';
  end if;

  if p_distrito is null or length(trim(p_distrito)) = 0 then
    raise exception 'Falta el distrito donde resides.';
  end if;
  if p_provincia is null or length(trim(p_provincia)) = 0 then
    raise exception 'Falta la provincia donde resides.';
  end if;
  if p_medios_ida is null or p_medios_ida < 0 or p_medios_ida > 10 then
    raise exception 'Indica cuántos medios de transporte usas de ida (entre 0 y 10).';
  end if;
  if p_medios_vuelta is null or p_medios_vuelta < 0 or p_medios_vuelta > 10 then
    raise exception 'Indica cuántos medios de transporte usas de vuelta (entre 0 y 10).';
  end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  select s.codigo into v_sede_codigo
    from personas p join sedes s on s.id = p.sede_base_id
   where p.id = v_yo;

  select pl.valor into v_tarifa
    from parametros_laborales pl
   where pl.clave = 'movilidad_diaria'
     and pl.vigente_desde <= fn_hoy_lima()
     and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima())
     and (pl.sede_codigo = v_sede_codigo or pl.sede_codigo is null)
   order by (pl.sede_codigo is null), pl.vigente_desde desc
   limit 1;

  if v_tarifa is null then
    raise exception 'Tu sede todavía no tiene una tarifa de movilidad vigente. Avisa a Desarrollo Organizacional antes de firmar.';
  end if;

  -- Candado (0425), sin cambios de criterio: existe una fila no anulada, no
  -- es una negativa, y su monto coincide con la tarifa de HOY. El distrito
  -- declarado nunca formó parte de este criterio.
  select d.es_negativa, d.monto_declarado into v_es_negativa, v_monto_anterior
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'ruta' and d.anulado_at is null
   order by d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;

  if v_es_negativa is not true and v_monto_anterior is not null and v_monto_anterior = v_tarifa then
    raise exception 'Ya tienes una declaración de ruta firmada y vigente. Si algo cambió, pide una revisión en vez de volver a firmar.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0426 ⇩⇩⇩ Igual que la 0425, menos la pregunta del taxi.
  v_declarada :=
    'Reside en el distrito de ' || trim(p_distrito) || ', provincia de ' || trim(p_provincia) || '. '
    || 'Para llegar a su centro de labores utiliza ' || p_medios_ida || ' medio(s) de transporte por tramo, '
    || 'y de regreso ' || p_medios_vuelta || '. '
    || 'CAYLA le otorga una asignación de movilidad de S/ ' || to_char(v_tarifa, 'FM999999990.00')
    || ' por día efectivamente asistido, conforme a la tarifa vigente para su sede.';

  begin
    v_ip := nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent
  ) values (
    'individual', v_yo, 'ruta', fn_hoy_lima(), v_declarada, v_tarifa,
    v_yo, v_imagen, now(), v_ip, v_ua
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'ruta · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la declaración de ruta (0423), reemplaza el escaneo físico.');

  return v_id;
end;
$$;

grant execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer)
  to authenticated;
revoke execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer)
  from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (426, 'la_declaracion_de_ruta_ya_no_pregunta_por_el_taxi')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 4) = 1
    as confirmar_sin_taxi,
  (select prosrc like '%CAMBIO 0426%' from pg_proc
    where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 4)
    as version_correcta,
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 5) = 0
    as version_vieja_ya_no_existe;
