-- ============================================================================
-- 0477 — El bono de cumpleaños se firma desde el sistema
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que quien recibe su bono de cumpleaños pueda firmar SU constancia desde
--   /mio, con la firma digital que ya tiene guardada (la misma que usa para
--   la ruta y el contrato) — sin imprimir, sin firmar a mano y sin escanear
--   nada. Mismo criterio y mismo molde que la 0423 le dio a la declaración
--   de ruta: `fn_confirmar_mi_bono_cumpleanos` es una copia estructural de
--   `fn_confirmar_mi_declaracion_ruta`, con las piezas propias de la ruta
--   (distrito, provincia, medios de transporte) reemplazadas por nada —el
--   bono no tiene nada que declarar, solo confirma que se recibió.
--
--   No hay candado de secuencia. El bono de CAYLA se paga por TRANSFERENCIA
--   bancaria (confirmado con Felipe, 2026-09-16) — a diferencia de un pago en
--   efectivo, la transferencia ya es su propia prueba de entrega, así que no
--   hace falta que un admin marque nada antes de que la persona pueda firmar.
--   Es EXACTAMENTE la misma puerta que ya usa el escaneo de siempre
--   (`fn_documento_registrar` con p_tipo = 'bono'): en planilla, activa, y sin
--   una constancia vigente todavía este año.
--
--   (Una primera versión de esta migración —revertida antes de pegarse en
--   ningún lado, ver el commit anterior en esta misma rama— sí tenía ese
--   candado, con una tabla `bono_entregas_pendientes` y una función
--   `fn_bono_marcar_entregado`. Se descartó completo al confirmar con Felipe
--   que el pago es por transferencia: el candado resolvía un riesgo — firmar
--   antes de recibir el efectivo — que con transferencia no existe.)
--
--   `fn_bono_monto_vigente()` también es nueva. `parametros_laborales` solo
--   la lee un admin (`parametros_laborales_lectura_admin`), así que sin esta
--   función /mio/cumpleanos no tiene cómo mostrarle a la persona, ANTES de
--   firmar, la cifra que está a punto de confirmar — se probó en el
--   navegador contra el Postgres local y la pantalla se quedaba mostrando
--   "no hay monto vigente" con la fila SÍ presente, exactamente por RLS.
--   `fn_confirmar_mi_bono_cumpleanos` pasa a llamarla en vez de repetir el
--   mismo `select`: una sola función que sabe cuál es el monto vigente,
--   igual que `fecha-lima.ts` es el único lugar que sabe qué hora es en Lima.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No toca `fn_documento_registrar` ni `fn_documentos_tablero`: el bono no
--   necesita ningún estado nuevo ni ninguna columna nueva, porque no hay nada
--   que esta migración tenga que coordinar con el camino del escaneo más
--   allá del candado que ya existe (el índice único `persona_id, anio` de
--   `documentos_firmados` impide dos constancias vigentes del mismo año, sin
--   importar por cuál de los dos caminos llegue la primera).
--
--   No exige que la persona esté en su mes de cumpleaños para poder firmar:
--   `fn_documento_registrar` tampoco lo exige hoy para el escaneo (un cargo
--   se puede subir tarde o temprano sin que la base lo bloquee), así que el
--   autoservicio sigue el mismo criterio — no inventa una restricción que el
--   camino de siempre no tiene.
--
--   No borra ni reemplaza la vía del escaneo: `fn_documento_registrar` sigue
--   intacta, sin cambios, para quien no pueda o no quiera firmar desde el
--   sistema. Las dos conviven, y gana la más reciente — mismo criterio que ya
--   usa esta tabla entre dos escaneos sucesivos.
--
-- QUÉ ASUME
--
--   `firmas_escaneadas`, `fn_persona_actual_id()`, `fn_hoy_lima()`,
--   `fn_es_admin_o_lider()` sin cambios desde su origen — mismas piezas que
--   ya usa `fn_confirmar_mi_declaracion_ruta` (0423/0429).
--
--   El índice `idx_documentos_bono_uno_por_anio` (0157) — único por
--   `persona_id, anio` donde `tipo = 'bono' and anulado_at is null and not
--   es_negativa` — sigue vigente y es lo que impide, incluso bajo dos
--   firmas concurrentes, que queden dos constancias vivas del mismo año.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_confirmar_mi_bono_cumpleanos();
--   drop function if exists fn_bono_monto_vigente();
-- ============================================================================


-- El monto vigente de la asignación por onomástico, para quien no es admin.
-- Nunca un valor de respaldo: sin fila vigente, null — mismo criterio que ya
-- exige el comentario de `admin/documentacion` sobre este mismo monto.
create function fn_bono_monto_vigente()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select pl.valor
    from parametros_laborales pl
   where pl.clave = 'bono_onomastico'
     and pl.vigente_desde <= fn_hoy_lima()
     and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima())
   order by pl.vigente_desde desc
   limit 1;
$$;

grant execute on function fn_bono_monto_vigente() to authenticated;


create function fn_confirmar_mi_bono_cumpleanos()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo     uuid := fn_persona_actual_id();
  v_imagen text;
  v_monto  numeric;
  v_anio   integer := extract(year from fn_hoy_lima())::int;
  v_id     uuid;
  v_ip     text;
  v_ua     text;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  if not exists (
    select 1 from personas where id = v_yo and estado = 'activo' and en_planilla
  ) then
    raise exception 'No estás en planilla: no te corresponde este documento.';
  end if;

  if exists (
    select 1 from documentos_firmados
     where persona_id = v_yo and tipo = 'bono' and anio = v_anio
       and anulado_at is null and not es_negativa
  ) then
    raise exception 'Ya tienes la constancia de este año firmada.';
  end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  v_monto := fn_bono_monto_vigente();

  if v_monto is null then
    raise exception 'No hay un monto de bono de onomástico vigente. Avisa a Desarrollo Organizacional antes de firmar.';
  end if;

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
    alcance, persona_id, tipo, fecha_firma, monto_declarado, anio,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent
  ) values (
    'individual', v_yo, 'bono', fn_hoy_lima(), v_monto, v_anio,
    v_yo, v_imagen, now(), v_ip, v_ua
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'bono · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la constancia del bono de cumpleaños, reemplaza el escaneo físico.');

  return v_id;
end;
$$;

grant execute on function fn_confirmar_mi_bono_cumpleanos() to authenticated;
revoke execute on function fn_confirmar_mi_bono_cumpleanos() from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (477, 'el_bono_de_cumpleanos_se_firma_desde_el_sistema')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_bono_cumpleanos') = 1 as tiene_confirmar,
  (select count(*) from pg_proc where proname = 'fn_bono_monto_vigente') = 1        as tiene_monto_vigente;
