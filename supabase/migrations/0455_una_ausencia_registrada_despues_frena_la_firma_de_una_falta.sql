-- ============================================================================
-- 0455_una_ausencia_registrada_despues_frena_la_firma_de_una_falta.sql
-- ============================================================================
-- QUÉ PROMETE
--   fn_expediente_firmar deja de firmar un borrador de FALTA cuando, DESPUÉS
--   de generarse, se registró una ausencia (sin anular) que cubre alguno de
--   los días que el borrador cita como `hechos`. Antes de esto, un borrador es
--   una foto congelada al generarse (0060) y nadie la revisaba de nuevo al
--   firmar: se podía firmar un memo citando un día que un descanso médico o
--   unas vacaciones registradas más tarde ya volvieron justificado.
--
-- POR QUÉ EXISTE
--   Hallazgo de la auditoría de Ausencias del 2026-09-15, ya documentado en el
--   código (apps/web/lib/admin/disciplina.ts, estadoHoyFalta): "Registrar una
--   ausencia no revisa ningún expediente". Ahí solo se podía AVISAR, mirando
--   la pantalla de Disciplina; nada impedía firmar igual. Es exactamente el
--   riesgo que la propia pantalla de Ausencias promete evitar ("un día
--   registrado aquí deja de contar como falta injustificada y no alimenta el
--   expediente disciplinario") y que, sin este candado, solo cumplía a medias.
--
-- QUÉ ASUME — Y POR QUÉ SOLO 'FALTA', NUNCA 'TARDANZA'
--   Que una ausencia SÍ invalida un hecho de tipo_causal = 'falta': fn_faltas
--   (0414) excluye en vivo cualquier día con una ausencia sin anular, así que
--   un borrador de falta que cita ese día ya quedó desactualizado respecto a
--   lo que la base contaría hoy.
--
--   Para 'tardanza' es AL REVÉS, y aplicar el mismo candado ahí sería el error
--   que el propio hallazgo de la auditoría advierte no cometer: la persona
--   pudo marcar tarde y, aparte, tener una ausencia registrada ese mismo día
--   (un permiso a media jornada, por ejemplo) — fn_tardanzas_resumen no mira
--   `ausencias` en absoluto, así que la tardanza sigue contando igual según la
--   base. Bloquear la firma ahí no protegería nada: contradiría a la base, que
--   es la única autoridad real (ver el comentario de estadoHoyTardanza en
--   disciplina.ts: "una ausencia registrada NO excluye ... decir 'no cuenta'
--   ahí sería contradecir a la base").
--
-- POR QUÉ UN RECHAZO DIRECTO Y NO UN AVISO
--   Un aviso ya existe — la pantalla de Disciplina lo pinta desde el mismo
--   hallazgo de hoy — y no bastó: la firma seguía sin nada que la detuviera.
--   Es el mismo criterio que ya se aplicó en la 0442 para anular una ausencia
--   ya aprobada por DO: cuando avisar no alcanza para impedir el error, hace
--   falta un candado, no un cartel.
--
-- SE ROMPE SI
--   Alguien necesita firmar IGUAL un memo de falta que cita un día ya cubierto
--   por una ausencia — por ejemplo, si la ausencia se registró por error y va
--   a anularse de todas formas. Con este candado, primero hay que anular esa
--   ausencia (o corregir el borrador quitando ese día) antes de poder firmar.
--   Es el costo aceptado a cambio de que ningún memo cite, sin que nadie lo
--   note, un día que ya dejó de ser falta.
--
-- CÓMO SE REVIERTE
--   Repegar el cuerpo de fn_expediente_firmar tal como está en la 0267 (sin el
--   bloque marcado CAMBIO 0455 más abajo).
--
-- MD5 DE PARTIDA (Postgres LOCAL, no producción — pedir el de producción con
-- donde-vive.sh justo antes de pegar esto, no antes de escribirlo):
--   verificar con: select md5(prosrc) from pg_proc where proname = 'fn_expediente_firmar';
-- ============================================================================

create or replace function fn_expediente_firmar(p_id uuid, p_firmante_id uuid default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  r expediente_disciplinario%rowtype;
  v_corr text; v_firmante uuid; v_f personas%rowtype; v_falta text;
  v_exige boolean;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede firmar un borrador (estado actual: %).', r.estado;
  end if;

  -- ⇩⇩⇩ CAMBIO 0455 ⇩⇩⇩ Ver "QUÉ ASUME" arriba: solo 'falta', nunca
  -- 'tardanza' — fn_faltas sí excluye por ausencia, fn_tardanzas_resumen no.
  if r.tipo_causal = 'falta' and exists (
    select 1
    from jsonb_array_elements(r.hechos) h
    join ausencias a on a.persona_id = r.persona_id
     and a.anulada_at is null
     and (h->>'fecha')::date between a.fecha_inicio and a.fecha_fin
  ) then
    raise exception 'Uno o más días de este borrador ya tienen una ausencia registrada que los justifica — dejaron de contar como falta injustificada. Revísalo en Disciplina (o anula esa ausencia si se registró por error) antes de firmar.';
  end if;
  -- ⇧⇧⇧ CAMBIO 0455 ⇧⇧⇧

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

  -- ART. 55.2 Y 19.3 DEL RIT, ahora bajo la política de la empresa.
  --
  -- `is distinct from 'false'` y no `= 'true'`: si la clave no existe, o trae un
  -- valor que nadie esperaba, se EXIGE. Una configuración ausente no puede
  -- relajar una garantía sin que nadie lo haya decidido.
  select (valor is distinct from 'false'::jsonb) into v_exige
  from configuracion where clave = 'disciplina_descargo_previo';
  v_exige := coalesce(v_exige, true);

  if v_exige and r.nivel in ('amonestacion', 'suspension') then
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

  -- Que el documento diga bajo qué política se firmó. Es lo único que separa
  -- una decisión de empresa de un trámite olvidado, y es lo que se va a leer si
  -- la sanción se discute. Solo cuando de verdad faltó el descargo previo: un
  -- documento que sí lo tuvo no necesita explicar nada.
  update expediente_disciplinario
    set estado = 'firmado', firmante_id = v_firmante, firmado_at = now(), correlativo = v_corr,
        observacion = case
          when not v_exige and r.nivel in ('amonestacion', 'suspension')
               and (r.cargos_comunicados_at is null or r.descargo_acogido is null)
          then coalesce(observacion || E'\n', '') ||
               'Firmado sin descargo previo registrado, conforme a la política vigente de la ' ||
               'empresa (configuracion.disciplina_descargo_previo = false), que admite recoger ' ||
               'el descargo verbalmente. Art. 55.2 del RIT.'
          else observacion
        end
    where id = p_id;
  return v_corr;
end;
$$;

comment on function fn_expediente_firmar(uuid, uuid) is
  'Firma un borrador disciplinario. Rechaza firmar una FALTA si una ausencia registrada después ya cubre alguno de sus días (0455). El descargo previo del art. 55.2 se exige o no según configuracion.disciplina_descargo_previo (ausente = se exige). Lo firmado sin él queda diciéndolo en su expediente.';

grant execute on function fn_expediente_firmar(uuid, uuid) to authenticated, service_role;
revoke execute on function fn_expediente_firmar(uuid, uuid) from public;

insert into migraciones_aplicadas (numero, nombre)
values (455, 'una_ausencia_registrada_despues_frena_la_firma_de_una_falta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select prosrc like '%CAMBIO 0455%' as candado_presente
  from pg_proc where proname = 'fn_expediente_firmar';
