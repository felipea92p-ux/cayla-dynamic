-- ============================================================================
-- 0267 — El descargo previo pasa a ser una política de la empresa
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que exigir o no el descargo previo del art. 55.2 antes de firmar una
-- amonestación o una suspensión deje de estar clavado en el código y pase a ser
-- una decisión de la empresa, guardada en `configuracion` y cambiable en un
-- valor. Se aplica con la política en **false**: se firma sin esperar plazo, y
-- el descargo se recoge verbalmente.
--
-- ── DE QUIÉN ES ESTA DECISIÓN ───────────────────────────────────────────────
--
-- De Gerencia General, tomada el 17 de agosto de 2026 y sostenida después de
-- que se le expusiera por escrito lo que hay debajo. Queda dicho aquí porque
-- una migración que reduce una garantía tiene que decir quién la pidió y qué
-- sabía al pedirla — si no, dentro de un año parecerá un descuido de código.
--
-- Lo que se expuso, en corto:
--
--   · El Tribunal de Fiscalización Laboral de SUNAFIL (Res. 568-2021-SUNAFIL/TFL)
--     extendió el debido proceso a las sanciones DISTINTAS del despido: ese
--     caso trataba exactamente de una amonestación escrita y una suspensión sin
--     goce impuestas sin plazo de descargo.
--   · La Res. 810-2022-SUNAFIL/TFL califica sancionar sin plazo de descargos
--     como ACTO DE HOSTILIDAD, infracción muy grave del art. 25.14 del RLGIT.
--     Para pequeña empresa el tope 2026 llega a 7.65 UIT (≈ S/ 42,075).
--   · El propio RIT de CAYLA, art. 55.2, lo exige por escrito y anuncia su
--     consecuencia: la omisión INVALIDA la medida y esta no cuenta como
--     antecedente para el inciso h) del art. 25 de la LPCL.
--
-- Esto último es lo que más cuesta y lo que menos se ve: los memos firmados sin
-- descargo previo siguen sirviendo para ordenar al equipo, pero son el peldaño
-- que sostiene un despido futuro, y ese peldaño queda discutible.
--
-- ── POR QUÉ UNA POLÍTICA Y NO BORRAR EL CANDADO ─────────────────────────────
--
-- Porque borrarlo dejaría el sistema sin memoria de que alguna vez existió: en
-- seis meses nadie sabría si esto se decidió o se rompió. Con una fila de
-- configuración, la regla sigue escrita, se sabe quién la puso en false, y
-- volver atrás es cambiar un valor — no otra migración pegada a mano un día de
-- apuro.
--
-- Y sobre todo: cada documento firmado bajo esta política lo dice en su propio
-- expediente. Si mañana se discute una sanción, lo que se lee no es un hueco,
-- sino «se firmó sin descargo previo registrado; la política vigente admite el
-- descargo verbal». Es la diferencia entre una decisión y un olvido.
--
-- ── LO QUE NO CAMBIA ────────────────────────────────────────────────────────
--
--   · El numeral 60.5 sigue frenando: sin constancia de entrega del Reglamento
--     no se firma una amonestación ni una suspensión. No se pidió tocarlo, y no
--     se toca — sancionar con un reglamento que nunca se entregó no se sostiene
--     con ninguna política interna.
--   · Los guardas de firmante (art. 54.4), el estado borrador y los permisos
--     quedan exactamente igual.
--   · Con la política en TRUE, la función se comporta byte a byte como la 0228.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- Que `configuracion` es la fuente de esta decisión y que la clave puede no
-- existir: si falta, se asume TRUE (exigir), que es el comportamiento anterior.
-- Una configuración perdida no debe relajar una garantía en silencio.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Para volver a exigir el descargo previo NO hace falta revertir nada:
--
--   update configuracion set valor = 'true'::jsonb
--    where clave = 'disciplina_descargo_previo';
--
-- Para deshacer la migración entera, restaurar `fn_expediente_firmar` de la
-- 0228 y borrar la fila de configuración.
--
-- md5 de partida (pedido a PRODUCCIÓN el 17-08-2026, confirmado idéntico en el
-- Postgres local):
--   fn_expediente_firmar  8d392dbc21d5caf52d9157335c37b44b  (0228, 4528 caracteres)
-- ============================================================================

-- ── La decisión, en una fila ────────────────────────────────────────────────
insert into configuracion (clave, valor, descripcion)
values (
  'disciplina_descargo_previo',
  'false'::jsonb,
  'Si antes de firmar una amonestación o una suspensión hay que comunicar los cargos, esperar el plazo del art. 55.2 del RIT y valorar el descargo por escrito. En false, se firma sin esperar y el descargo se recoge verbalmente; cada documento firmado así lo hace constar en su expediente. Decisión de Gerencia General del 17-08-2026.'
)
on conflict (clave) do nothing;

-- ── Y la función, copiada de la 0228 con la política dentro ─────────────────
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
  'Firma un borrador disciplinario. El descargo previo del art. 55.2 se exige o no según configuracion.disciplina_descargo_previo (ausente = se exige). Lo firmado sin él queda diciéndolo en su expediente.';

grant execute on function fn_expediente_firmar(uuid, uuid) to authenticated, service_role;
revoke execute on function fn_expediente_firmar(uuid, uuid) from public;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (267, 'el_descargo_previo_pasa_a_ser_una_politica_de_la_empresa')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- `exige_descargo_previo` debe decir FALSE: es la política que se acaba de
-- fijar. `firmables_ahora` cuenta los borradores de amonestación y suspensión
-- que con ella ya se pueden firmar — hoy deberían ser 2 (Sasha y Mateo);
-- Paola no aparece porque le falta la constancia del Reglamento, que esto no
-- toca.
select
  (select valor from configuracion where clave = 'disciplina_descargo_previo')
    = 'false'::jsonb                                          as politica_descargo_verbal,
  (select count(*) from expediente_disciplinario d
    where d.estado = 'borrador'
      and d.nivel in ('amonestacion', 'suspension')
      and fn_reglamento_no_acusado(
            d.persona_id, coalesce(d.periodo_hasta, d.periodo_desde, fn_hoy_lima())) is null)
                                                              as firmables_ahora;
