-- ============================================================================
-- 0228 — No se sanciona con un Reglamento que no se entregó
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que Dynamic no emita una amonestación, una suspensión ni una llamada de
-- atención verbal contra una persona a la que no le consta entregada la versión
-- del Reglamento que regía cuando ocurrieron los hechos.
--
-- Es el numeral 60.5, y conviene leerlo entero porque dice dos cosas y solo una
-- es la que se programa:
--
--   «El desconocimiento de este Reglamento no exime de su cumplimiento.
--
--    Sin embargo, CAYLA no puede fundar una sanción en una disposición cuya
--    entrega, en la versión vigente a la fecha de los hechos, no conste
--    acreditada conforme al numeral 60.3. Mientras esa entrega no conste, no se
--    le aplican a esa colaboradora las disposiciones sancionadoras de este
--    Reglamento: los hechos se califican y sancionan conforme a la versión que
--    sí le fue entregada, en todo lo que no se oponga a la ley.»
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, Y ES LA MITAD DEL TRABAJO ────────────────
--
-- No impide sancionar. Impide fundar la sanción EN EL REGLAMENTO. La diferencia
-- decide el alcance del candado:
--
--   · La llamada verbal, la amonestación y la suspensión salen de la gradación
--     de los artículos 19, 21 y 54 — disposiciones del Reglamento. Sin entrega
--     acreditada no se pueden fundar, así que se BLOQUEAN.
--
--   · La imputación de cargos y el despido se fundan en una causal del artículo
--     25 de la LPCL, que rige por ley y no por entrega. Bloquearlos habría
--     impedido despedir por una falta grave a quien no firmó un cargo — o sea,
--     habría premiado no firmarlo. NO se bloquean.
--
-- Y hay un tercer caso que tampoco se bloquea: los hechos anteriores a la
-- primera versión publicada. Ahí el 60.5 manda calificar «conforme a la versión
-- que sí le fue entregada», que hoy es una de papel y no consta en la base. El
-- sistema no puede decidir sobre lo que no ve, así que calla en vez de frenar.
-- Es el caso de casi todo lo que hay abierto: el Reglamento se publicó el
-- 11-08-2026 y los hechos en curso son anteriores.
--
-- ── POR QUÉ AHORA Y NO EN DICIEMBRE ─────────────────────────────────────────
--
-- Porque el riesgo de esto es máximo hoy y baja cada día. El Reglamento se
-- publicó ayer y de veintiuna personas con contrato solo una ha dejado
-- constancia. Cada memo que se emita esta semana por hechos posteriores a la
-- publicación va contra alguien a quien todavía no le es oponible, y hasta hoy
-- el sistema lo dejaba pasar sin decir nada. Cuando lleguen las veinte
-- constancias, este candado dejará de dispararse solo.
--
-- ── DÓNDE SE PONE ───────────────────────────────────────────────────────────
--
-- En dos sitios, y el primero importa más que el segundo:
--
--   `fn_expediente_comunicar_cargos`  antes de comunicarle nada a la persona.
--                                     No se empieza un procedimiento que no se
--                                     va a poder terminar: citar a alguien a
--                                     descargo y después no poder firmar es
--                                     hacerle pasar el mal rato para nada.
--   `fn_expediente_firmar`            el punto sin retorno.
--
-- El borrador NO se bloquea: preparar el documento y ver qué falta es
-- justamente lo que permite darse cuenta de que hay que entregar el Reglamento.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- Que la fecha de los hechos es `periodo_hasta` — el último día del periodo
-- imputado. Es la que decide qué versión regía: si los hechos cruzan una
-- entrega, manda la versión vigente al final, que es la más exigente y la que
-- el documento va a citar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Restaurando las dos funciones de la 0214 y la 0212, y borrando
-- `fn_reglamento_no_acusado`. No toca datos.
--
-- md5 de partida (pedirlos a PRODUCCIÓN, no al Postgres local):
--   fn_expediente_comunicar_cargos  eee47bb570b7876e4856810cd26be0ca  (0212)
--   fn_expediente_firmar            ef830f2b896c4a72f3cd381bb3077c66  (0214)
-- ============================================================================

-- ── La pregunta, en un solo sitio ───────────────────────────────────────────
--
-- Devuelve NULL cuando no hay nada que objetar, y el motivo cuando lo hay. Se
-- eligió texto y no un booleano porque quien lea el error tiene que saber QUÉ
-- versión falta y DESDE cuándo regía: «no se puede» sin el porqué se convierte
-- en un ticket para Felipe.
create or replace function fn_reglamento_no_acusado(p_persona_id uuid, p_fecha date)
returns text language plpgsql stable security definer set search_path = public as $$
declare v record;
begin
  if p_persona_id is null or p_fecha is null then return null; end if;

  -- La versión que regía en la fecha de los hechos.
  select d.id, d.version, d.vigente_desde into v
  from documentos_institucionales d
  where d.tipo = 'rit'
    and d.vigente_desde <= p_fecha
  order by d.vigente_desde desc, d.version desc
  limit 1;

  -- Ninguna versión publicada regía entonces. El 60.5 manda calificar conforme
  -- a la que sí le fue entregada, que hoy es de papel y no consta en la base:
  -- el sistema calla en vez de frenar sobre lo que no puede ver.
  if not found then return null; end if;

  if exists (
    select 1 from documentos_acuses a
    where a.documento_id = v.id and a.persona_id = p_persona_id
  ) then
    return null;
  end if;

  return format(
    'No consta la entrega del Reglamento (versión %s, vigente desde el %s) a esta persona, '
    || 'y los hechos son del %s. El numeral 60.5 impide fundar una sanción en una disposición '
    || 'cuya entrega no conste acreditada. Entrégaselo y registra su constancia en Normas '
    || '—también vale la constancia en papel, con el cargo escaneado— y vuelve a intentarlo.',
    v.version,
    to_char(v.vigente_desde, 'DD/MM/YYYY'),
    to_char(p_fecha, 'DD/MM/YYYY'));
end;
$$;

comment on function fn_reglamento_no_acusado(uuid, date) is
  'Numeral 60.5 del RIT: NULL si a esa persona le consta entregada la version del '
  'Reglamento vigente en esa fecha; si no, el motivo por escrito.';

grant execute on function fn_reglamento_no_acusado(uuid, date) to authenticated, service_role;
revoke execute on function fn_reglamento_no_acusado(uuid, date) from public;

-- ── Y la misma pregunta, para toda la gente de una vez ──────────────────────
--
-- La pantalla de Disciplina la necesita para AVISAR antes, no para frenar. Sin
-- esto habría que preguntar persona por persona, y con veinte de veintiuna sin
-- constancia esta semana, Desarrollo Organizacional chocaría contra el error una
-- y otra vez sin saber de antemano a quién puede sancionar.
--
-- Un botón que solo sabe dar error enseña que los avisos del sistema son
-- trámite; el día que frene por algo que de verdad importa, ya nadie lo lee.
create or replace function fn_sin_constancia_del_reglamento()
returns table(persona_id uuid, motivo text)
language sql stable security definer set search_path = public as $$
  select p.id, fn_reglamento_no_acusado(p.id, fn_hoy_lima())
  from personas p
  where p.estado = 'activo'
    and fn_reglamento_no_acusado(p.id, fn_hoy_lima()) is not null
    -- Solo lo ve quien puede actuar sobre un expediente. Es una lista de quién
    -- no ha firmado algo: no es secreta, pero tampoco es de todos.
    and fn_es_admin_o_lider() is true;
$$;

comment on function fn_sin_constancia_del_reglamento() is
  'Quien no tiene constancia del Reglamento vigente hoy, para avisar en Disciplina antes de empezar un procedimiento (numeral 60.5).';

grant execute on function fn_sin_constancia_del_reglamento() to authenticated, service_role;
revoke execute on function fn_sin_constancia_del_reglamento() from public;

-- ── Antes de comunicarle los cargos a nadie ─────────────────────────────────
-- Copiada de la 0212, con el guard nuevo justo después de los que ya estaban.
create or replace function fn_expediente_comunicar_cargos(
  p_id uuid, p_dias integer default 2, p_nota text default null)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  v_doc   record;
  v_vence timestamptz;
  v_falta text;
begin
  select * into v_doc from expediente_disciplinario where id = p_id;
  if not found then raise exception 'Ese documento no existe.'; end if;

  if fn_expediente_puede_actuar(v_doc.persona_id, v_doc.nivel) is not true then
    raise exception 'Sin permiso para actuar sobre este documento.';
  end if;

  if v_doc.estado <> 'borrador' then
    raise exception 'Los cargos se comunican mientras el documento es borrador; este está %.', v_doc.estado;
  end if;

  if v_doc.nivel not in ('amonestacion', 'suspension') then
    raise exception 'Este acto es para la amonestación y la suspensión. La imputación y el despido siguen el procedimiento del artículo 57.';
  end if;

  if v_doc.cargos_comunicados_at is not null then
    raise exception 'Los cargos ya se comunicaron el %. El plazo no se reabre.',
      to_char(v_doc.cargos_comunicados_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI');
  end if;

  -- NUMERAL 60.5: no se cita a descargo por unos hechos que después no se van a
  -- poder sancionar. Va antes que el plazo, para que el freno llegue cuando aún
  -- no se le ha dicho nada a la persona.
  v_falta := fn_reglamento_no_acusado(
    v_doc.persona_id, coalesce(v_doc.periodo_hasta, v_doc.periodo_desde, fn_hoy_lima()));
  if v_falta is not null then raise exception '%', v_falta; end if;

  -- El Reglamento dice «no menor de dos»: se puede dar más, nunca menos.
  if p_dias < 2 then
    raise exception 'El plazo de descargo no puede ser menor de dos (2) días hábiles (art. 55.2 del RIT).';
  end if;

  v_vence := fn_sumar_dias_habiles(now(), p_dias);

  update expediente_disciplinario
     set cargos_comunicados_at = now(),
         descargo_vence_at     = v_vence,
         observacion = coalesce(observacion || E'\n', '') ||
                       'Cargos comunicados el ' ||
                       to_char(now() at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI') ||
                       coalesce('. ' || nullif(btrim(p_nota), ''), '')
   where id = p_id;

  return v_vence;
end;
$$;

grant execute on function fn_expediente_comunicar_cargos(uuid, integer, text) to authenticated, service_role;
revoke execute on function fn_expediente_comunicar_cargos(uuid, integer, text) from public;

-- ── Y en el punto sin retorno ───────────────────────────────────────────────
-- Copiada de la 0214, con el guard nuevo.
create or replace function fn_expediente_firmar(p_id uuid, p_firmante_id uuid default null)
returns text language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype; v_corr text; v_firmante uuid; v_f personas%rowtype; v_falta text;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede firmar un borrador (estado actual: %).', r.estado;
  end if;

  -- NUMERAL 60.5 DEL RIT: la llamada verbal, la amonestación y la suspensión
  -- salen de la gradación de los artículos 19, 21 y 54 — disposiciones de este
  -- Reglamento—, así que sin entrega acreditada no se pueden fundar.
  --
  -- La imputación y el despido NO pasan por aquí a propósito: se fundan en una
  -- causal del artículo 25 de la LPCL, que rige por ley y no por entrega.
  -- Frenarlos habría impedido despedir por falta grave a quien no firmó su
  -- cargo, es decir, habría premiado no firmarlo.
  if r.nivel in ('verbal', 'amonestacion', 'suspension') then
    v_falta := fn_reglamento_no_acusado(
      r.persona_id, coalesce(r.periodo_hasta, r.periodo_desde, fn_hoy_lima()));
    if v_falta is not null then raise exception '%', v_falta; end if;
  end if;

  -- ART. 55.2 Y 19.3 DEL RIT: antes de una amonestación o una suspensión hay
  -- que comunicar los cargos y esperar el plazo de descargo. Su omisión
  -- INVALIDA la medida, así que el sistema no puede dejar firmarla: una sanción
  -- inválida no se nota al firmarla — se nota el día que alguien la discute, y
  -- para entonces ya no se puede arreglar.
  --
  -- La imputación y el despido NO pasan por aquí: siguen el procedimiento
  -- propio del art. 57, con el plazo del art. 31 de la LPCL.
  if r.nivel in ('amonestacion', 'suspension') then
    if r.cargos_comunicados_at is null then
      raise exception 'Antes de firmar hay que comunicar los cargos y dar el plazo de descargo (art. 55.2 del RIT).';
    end if;
    if now() < r.descargo_vence_at then
      raise exception 'El plazo de descargo vence el %. Firmar antes invalidaría la sanción (art. 55.2 del RIT).',
        to_char(r.descargo_vence_at at time zone 'America/Lima', 'DD/MM/YYYY');
    end if;
    if r.descargo_acogido is null then
      raise exception 'Falta valorar por escrito el descargo antes de firmar (art. 19.3 del RIT), aunque no se haya presentado ninguno.';
    end if;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso para firmar un documento de nivel %.', r.nivel;
  end if;

  v_firmante := coalesce(p_firmante_id, fn_persona_actual_id());

  -- ART. 54.4 c) DEL RIT — «La carta de despido la suscribe siempre la Gerencia
  -- General». Para los demás niveles se conserva lo de la 0071: quien tramita
  -- puede estampar la firma de otra persona competente. Para el despido no: una
  -- carta que dice estar firmada por quien no la firmó se cae entera.
  if r.nivel = 'despido' and v_firmante is distinct from fn_persona_actual_id() then
    raise exception 'La carta de despido la suscribe la Gerencia General en persona (art. 54.4 c del RIT): no se puede firmar a nombre de otra persona.';
  end if;

  -- El firmante elegido tiene que poder suscribir ESTE documento por derecho
  -- propio. Sin esto, quien puede firmar podría estampar a cualquiera —
  -- incluida gente sin autoridad para el nivel que se está firmando.
  select * into v_f from personas where id = v_firmante;
  if not found then raise exception 'El firmante elegido no existe.'; end if;
  if v_f.estado <> 'activo' then raise exception 'El firmante elegido no está activo.'; end if;
  if fn_cargo_de_rol(v_f.rol) is null then
    raise exception 'El firmante elegido no tiene un cargo que pueda suscribir documentos.';
  end if;
  -- Art. 54.4, escrito una sola vez en fn_expediente_puede_suscribir.
  if fn_expediente_puede_suscribir(v_f.rol::text, r.nivel) is not true then
    raise exception '% no puede suscribir un documento de nivel % (art. 54.4 del RIT).',
      coalesce(fn_cargo_de_rol(v_f.rol), 'El firmante elegido'), r.nivel;
  end if;
  if v_f.rol = 'supervisor_sede'
     and v_f.sede_base_id is distinct from (select sede_base_id from personas where id = r.persona_id) then
    raise exception 'El firmante elegido no pertenece a la sede de esta persona.';
  end if;

  v_corr := fn_expediente_correlativo(fn_expediente_doc_code(r.tipo_causal, r.nivel));
  update expediente_disciplinario
    set estado = 'firmado', firmante_id = v_firmante, firmado_at = now(), correlativo = v_corr
    where id = p_id;
  return v_corr;
end;
$$;

grant execute on function fn_expediente_firmar(uuid, uuid) to authenticated, service_role;
revoke execute on function fn_expediente_firmar(uuid, uuid) from public;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (228, 'no_se_sanciona_con_un_reglamento_que_no_se_entrego')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- TRES deben decir true. La otra, `personas_sin_constancia_hoy`, es un NÚMERO y
-- es la que más vale: dice a cuánta gente le falta la constancia del Reglamento
-- vigente. Mientras no sea 0, este candado está frenando memos de verdad — y ese
-- es exactamente su trabajo. Hoy debería salir 20.
select
  fn_reglamento_no_acusado(null, current_date) is null                       as un_null_no_revienta,
  fn_reglamento_no_acusado(
    (select id from personas limit 1), date '2000-01-01') is null            as antes_de_la_primera_version_no_frena,
  (select count(*) from personas p
    where p.estado = 'activo'
      and fn_reglamento_no_acusado(p.id, current_date) is not null)          as personas_sin_constancia_hoy,
  (select count(*) from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
    where n.nspname = 'public'
      and pr.proname in ('fn_reglamento_no_acusado', 'fn_sin_constancia_del_reglamento')) = 2
                                                                            as las_dos_funciones_existen;
