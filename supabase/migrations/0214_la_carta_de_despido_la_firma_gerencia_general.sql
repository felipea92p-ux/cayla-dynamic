-- ============================================================================
-- 0214 — La carta de despido la suscribe la Gerencia General
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que ningún documento del expediente disciplinario quede firmado por alguien
-- que el Reglamento no autoriza a suscribir ese nivel. En concreto:
--
--   · el DESPIDO solo lo suscribe la Gerencia General, y lo suscribe en persona;
--   · la SUSPENSIÓN y la IMPUTACIÓN, la Gerencia General o Desarrollo
--     Organizacional;
--   · la AMONESTACIÓN y la llamada VERBAL, además la encargada de tienda, y solo
--     sobre las personas cuya sede base es la suya.
--
-- Es el artículo 54.4 del Reglamento Interno de Trabajo v4.0, literal por
-- literal. Y el que decide cuánto cuesta incumplirlo es el 54.4 d):
--
--   «Ninguna sanción impuesta por quien no es competente conforme a este
--    numeral produce efecto alguno, no se incorpora al legajo y no sirve de
--    escalón para ninguna sanción posterior.»
--
-- Un despido firmado por quien no podía firmarlo no es un despido con un
-- defecto de forma: es un despido que no existe, con una persona fuera de la
-- empresa y una reposición o una indemnización esperando.
--
-- ── QUÉ ESTABA MAL ──────────────────────────────────────────────────────────
--
-- `fn_expediente_firmar` (0212) ya comprobaba el rol del FIRMANTE, no solo el
-- de quien pulsa —eso lo trajo la 0071 al permitir elegir firmante— pero solo
-- tenía escrita la mitad de la regla: la de la encargada de tienda. Para todo
-- lo demás bastaba con no ser encargada, así que un `lider_do` podía suscribir
-- un despido. `fn_expediente_firmantes`, que es la lista que la pantalla
-- ofrece, tenía el mismo hueco escrito a mano: `p.rol in ('admin','lider_do')`
-- para cualquier nivel.
--
-- Las dos decían la misma regla con palabras distintas, y las dos se habían
-- quedado cortas en el mismo sitio. Por eso acá la regla pasa a estar escrita
-- UNA sola vez, en `fn_expediente_puede_suscribir`, y las dos la consultan.
--
-- ── POR QUÉ NO SE TOCA fn_expediente_puede_actuar ───────────────────────────
--
-- Era lo primero que pedía el cambio, y habría sido un error. Trece funciones
-- la llaman: crear el borrador, editarlo, adjuntar pruebas, entregar, reabrir,
-- resolver. Cerrarle el `despido` a Desarrollo Organizacional le habría quitado
-- justamente lo que el 54.4 c) le encarga —«Desarrollo Organizacional instruye
-- el procedimiento, revisa la medición y suscribe estos actos»— y habría dejado
-- a la Gerencia General redactando sola la carta que DO tiene que instruir.
--
-- La competencia del 54.4 es sobre IMPONER, no sobre tramitar. Imponer es
-- firmar. Por eso el candado va en la firma y solo en la firma.
--
-- ── POR QUÉ EL DESPIDO NO ADMITE FIRMAR EN NOMBRE DE OTRA PERSONA ───────────
--
-- Para los demás niveles se conserva lo que trajo la 0071: quien tramita puede
-- estampar la firma escaneada de otra persona competente. Para el despido no.
-- El 54.4 c) dice «la suscribe siempre la Gerencia General», y una carta que
-- dice estar firmada por quien no la firmó es la clase de documento que se cae
-- entero cuando la persona lo discute. Aquí quien pulsa y quien firma tienen
-- que ser la misma, y ser Gerencia General.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- Que el rol `admin` es la Gerencia General. No lo decide esta migración: ya lo
-- dice `fn_cargo_de_rol`, que traduce 'admin' → 'Gerencia General' y es la
-- función con la que la pantalla rotula a cada firmante.
--
-- Ojo con la consecuencia, que es real: quien reciba `admin` para otra cosa
-- podrá suscribir un despido. Hoy `admin` ya abre todos los sueldos y todas las
-- sedes, así que no es una llave nueva; pero si algún día `admin` deja de ser
-- solo la Gerencia General, esta regla necesita una columna propia, como la que
-- la 0187 le dio a `personal_direccion` por la razón simétrica.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Restaurando el cuerpo de `fn_expediente_firmar` de la 0212 y el de
-- `fn_expediente_firmantes` de la 0076, y borrando
-- `fn_expediente_puede_suscribir`. No hay cambio de datos: esta migración solo
-- reescribe funciones.
--
-- md5 de partida (pedirlos a PRODUCCIÓN antes de pegar, no al Postgres local):
--   fn_expediente_firmar     849ba14a55f1de87ad704955229b6e63   (0212)
--   fn_expediente_firmantes  9ec82c60f3d5c92e6bdeeb7f3d695c19   (0076)
-- ============================================================================

-- ── La regla, escrita una sola vez ──────────────────────────────────────────
--
-- Pura: no mira la sesión ni la base. Recibe el rol de quien va a firmar y el
-- nivel del documento, y responde si el artículo 54.4 lo autoriza.
--
-- La pertenencia a la sede NO se comprueba acá a propósito: no depende del rol
-- sino de dos personas concretas, y mezclarlas obligaría a esta función a leer
-- la tabla. La comprueba cada quien llama, que ya tiene las dos a la mano.
create or replace function fn_expediente_puede_suscribir(p_rol text, p_nivel text)
returns boolean language sql immutable as $$
  -- `coalesce` al final y no `case … else`: si p_rol es null, la comparación
  -- devuelve null, y un null no puede pasar por autorizado (CLAUDE.md).
  select coalesce(
    case p_nivel
      -- 54.4 c) — «La carta de despido la suscribe siempre la Gerencia General.»
      when 'despido'      then p_rol = 'admin'
      -- 54.4 c) — suspensión e imputación: Gerencia General y DO.
      when 'suspension'   then p_rol in ('admin', 'lider_do')
      when 'imputacion'   then p_rol in ('admin', 'lider_do')
      -- 54.4 b) — verbal y amonestación: además la encargada de tienda.
      when 'amonestacion' then p_rol in ('admin', 'lider_do', 'supervisor_sede')
      when 'verbal'       then p_rol in ('admin', 'lider_do', 'supervisor_sede')
      -- Un nivel que no está en la escala del 54.4 no lo firma nadie.
      else false
    end, false);
$$;

comment on function fn_expediente_puede_suscribir(text, text) is
  'Artículo 54.4 del RIT: qué nivel del expediente puede SUSCRIBIR cada rol. '
  'No comprueba la sede — eso lo hace quien la llama.';

-- La 0076 revocó EXECUTE de PUBLIC por defecto: sin este grant, la función
-- nueva no la puede llamar nadie con sesión.
grant execute on function fn_expediente_puede_suscribir(text, text)
  to authenticated, service_role;
revoke execute on function fn_expediente_puede_suscribir(text, text) from public;

-- ── La lista de firmantes que ofrece la pantalla ────────────────────────────
-- Copiada de la 0076 (la vigente), cambiando solo el filtro de rol.
create or replace function fn_expediente_firmantes(p_id uuid)
returns table(persona_id uuid, nombre text, cargo text, tiene_firma boolean)
language plpgsql stable security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if fn_expediente_puede_actuar(r.persona_id, r.nivel) is not true then
    raise exception 'Sin permiso sobre este documento.';
  end if;

  return query
  select p.id,
         (p.nombres || ' ' || p.apellidos)::text,
         fn_cargo_de_rol(p.rol),
         exists (select 1 from firmas_escaneadas f where f.persona_id = p.id)
  from personas p
  where p.estado = 'activo'
    and fn_cargo_de_rol(p.rol) is not null
    -- Art. 54.4: la competencia depende del NIVEL, no de tener panel.
    and fn_expediente_puede_suscribir(p.rol::text, r.nivel)
    -- Y la encargada, solo sobre su propia sede.
    and (p.rol <> 'supervisor_sede'
         or p.sede_base_id = (select sede_base_id from personas where id = r.persona_id))
  order by 2;
end;
$$;

grant execute on function fn_expediente_firmantes(uuid) to authenticated, service_role;
revoke execute on function fn_expediente_firmantes(uuid) from public;

-- ── La firma ────────────────────────────────────────────────────────────────
-- Copiada de la 0212 (la vigente), cambiando solo el bloque que valida al
-- firmante elegido. Todo lo demás —el descargo previo del art. 55.2, el
-- correlativo— queda como estaba.
create or replace function fn_expediente_firmar(p_id uuid, p_firmante_id uuid default null)
returns text language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype; v_corr text; v_firmante uuid; v_f personas%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede firmar un borrador (estado actual: %).', r.estado;
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
values (214, 'la_carta_de_despido_la_firma_gerencia_general')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las cuatro deben decir true.
select
  fn_expediente_puede_suscribir('lider_do', 'despido')      is false as do_no_firma_despido,
  fn_expediente_puede_suscribir('admin', 'despido')         is true  as gerencia_si_firma_despido,
  fn_expediente_puede_suscribir('lider_do', 'suspension')   is true  as do_si_firma_suspension,
  fn_expediente_puede_suscribir(null, 'amonestacion')       is false as un_null_no_pasa;
