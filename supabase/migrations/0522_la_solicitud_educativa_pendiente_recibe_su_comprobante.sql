-- ============================================================================
-- 0522 — La solicitud de apoyo educativo pendiente puede recibir su comprobante
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Mientras su solicitud de apoyo educativo está PENDIENTE, la integrante puede
--   adjuntarle el comprobante —o cambiar el que adjuntó— desde «Lo mío ›
--   Educación». Una sola puerta: fn_educacion_solicitud_adjuntar(solicitud, ruta).
--
-- POR QUÉ
--
--   El formulario de la 0461 dice «Comprobante (opcional) … Puedes enviarlo
--   después». Pero «después» no existía: la solicitud pendiente solo ofrecía
--   «Retirar solicitud», y el trigger de la 0461 prohíbe cambiar
--   `comprobante_url` en cualquier caso. El 2026-10-16, Danixa Valverde
--   (TRU · UPN) envió su solicitud sin el papel y DO vio en Educación «No
--   adjuntó comprobante todavía» sin poder pedírselo desde el sistema: solo
--   aprobar o rechazar a ciegas. Ver el rechazo con motivo —«falta el
--   comprobante»— obligaba a la integrante a rehacer toda la solicitud.
--
--   Se evaluó y se descartó EXIGIR el comprobante al enviar:
--     · rompe lo decidido el 2026-09-15 («comprobante inicial opcional»): quien
--       pide desde el celular muchas veces no tiene el papel a mano en ese
--       momento, y la alternativa real no es «sube el papel» sino «no pide»;
--     · no arregla a quien ya tiene una solicitud pendiente sin papel (Danixa);
--     · el defecto no es que el papel sea opcional al pedir, sino que no haya
--       cómo completarlo después. Se arregla lo segundo.
--
-- QUÉ HACE
--
--   1. fn_educacion_solicitud_adjuntar(p_id, p_ruta) — SECURITY DEFINER,
--      null-safe. Solo la dueña, solo si la solicitud sigue pendiente, y solo
--      con un archivo que de verdad esté en el almacén dentro de SU carpeta
--      educacion/<ella>/solicitudes/… (la misma que fn_educacion_puede_subir_
--      solicitud, 0461, ya le deja escribir). Deja rastro en
--      correcciones_auditoria con la ruta anterior y la nueva.
--   2. fn_educacion_solicitud_inmutable (trigger de la 0461): `comprobante_url`
--      sale del grupo de lo que nunca cambia y pasa a tener su propia regla —
--      solo cambia si la solicitud está pendiente y SOLO desde una función
--      (current_user = 'postgres'; mismo molde que fn_bloquear_sede_directa,
--      0342). Lo que se pidió (institución, costo, fechas, beneficiario, nota)
--      sigue sin poder reescribirse. Una solicitud aprobada, rechazada o
--      retirada conserva el comprobante con el que se revisó.
--
-- QUÉ ASUME
--
--   · md5 de PARTIDA de fn_educacion_solicitud_inmutable —la única definición
--     es la 0461—, medido en el Postgres local con la 0461 aplicada
--     (2026-10-16): a677cd87c0931ca77a2c88dd7c3151a8 · 1116 caracteres.
--     Producción no se pudo preguntar desde la sesión: Felipe lo reconfirma en
--     el SQL Editor ANTES de pegar (consulta al final, comentada). Si no
--     coincide con ninguna de las variantes de donde-vive.sh (tal cual, sin
--     comentarios, CRLF), PARAR: alguien la reescribió.
--   · La 0461 está pegada en producción (la tabla y sus cuatro funciones).
--   · `fn_educacion_solicitudes_pendientes` (0461) ya devuelve `comprobante_url`
--     y la pantalla de DO lo lee de ahí: no se toca. Cuando la integrante
--     adjunta, DO lo ve al recargar «Pendientes de revisión».
--
-- QUÉ NO HACE
--
--   · No toca plata: ningún cálculo de planilla, tope ni monto. El comprobante
--     solo lo mira DO al decidir.
--   · No avisa a DO que llegó el papel (no hay correo ni novedad en Bandeja):
--     el ítem ya está en su lista, ahora con el papel adentro.
--   · No cambia las políticas del almacén: la carpeta de una solicitud sigue
--     abierta solo para quien la sube y solo mientras esa carpeta no
--     corresponde a una solicitud existente. El archivo nuevo va a una carpeta
--     nueva (un uuid fresco, como ya hace el formulario), nunca encima del
--     anterior.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_educacion_solicitud_adjuntar(uuid, text);
--   -- fn_educacion_solicitud_inmutable: volver a pegar el cuerpo de la 0461
--   -- (md5 de partida arriba); `comprobante_url` vuelve a ser inmutable.
--   Las rutas ya adjuntadas quedan en la tabla y en correcciones_auditoria
--   (campo 'educacion_solicitud_comprobante').
-- ============================================================================


-- ── A · El trigger: el comprobante tiene su propia regla ─────────────────────
-- Cuerpo de la 0461 con dos cambios marcados.
create or replace function fn_educacion_solicitud_inmutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una solicitud de apoyo educativo no se borra: se retira mientras está pendiente, o queda en el historial.';
  end if;

  -- ⇩ CAMBIO 0522 ⇩ `comprobante_url` sale de esta lista: tiene su regla abajo.
  if (new.persona_id, new.institucion, new.costo_declarado, new.beneficiario, new.beneficiario_nombre,
      new.vigente_desde, new.vigente_hasta, new.nota, new.enviada_at)
     is distinct from
     (old.persona_id, old.institucion, old.costo_declarado, old.beneficiario, old.beneficiario_nombre,
      old.vigente_desde, old.vigente_hasta, old.nota, old.enviada_at) then
    raise exception 'Lo que se pidió en una solicitud no se reescribe. Si hay que corregirlo, se envía otra.';
  end if;

  -- ⇩ CAMBIO 0522 ⇩ el comprobante cambia solo mientras está pendiente y solo
  -- por fn_educacion_solicitud_adjuntar (el rol de conexión de un cliente por
  -- PostgREST es `authenticated`; una función SECURITY DEFINER corre como `postgres`).
  if new.comprobante_url is distinct from old.comprobante_url then
    if current_user <> 'postgres' then
      raise exception 'El comprobante se adjunta con fn_educacion_solicitud_adjuntar, no con un update directo.';
    end if;
    if old.estado <> 'pendiente' then
      raise exception 'Esta solicitud ya está %: su comprobante no se cambia.', old.estado;
    end if;
  end if;

  if old.estado <> 'pendiente'
     and (new.estado, new.revisada_at, new.revisada_por, new.motivo_rechazo, new.retirada_at, new.asignacion_id)
         is distinct from
         (old.estado, old.revisada_at, old.revisada_por, old.motivo_rechazo, old.retirada_at, old.asignacion_id) then
    raise exception 'Esta solicitud ya está %: su revisión no se cambia.', old.estado;
  end if;

  return new;
end;
$$;


-- ── B · La integrante adjunta su comprobante ─────────────────────────────────
create or replace function fn_educacion_solicitud_adjuntar(p_id uuid, p_ruta text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo uuid := fn_persona_actual_id();
  v_s  educacion_solicitudes%rowtype;
begin
  if v_yo is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;

  select * into v_s from educacion_solicitudes where id = p_id for update;
  if not found then raise exception 'Esa solicitud no existe.'; end if;

  if v_s.persona_id is distinct from v_yo then
    raise exception 'Solo quien envió la solicitud puede adjuntarle el comprobante.';
  end if;
  if v_s.estado <> 'pendiente' then
    raise exception 'Esta solicitud ya está %: su comprobante no se cambia.', v_s.estado;
  end if;

  -- El archivo tiene que estar en SU carpeta de solicitudes, y existir de verdad:
  -- la ruta la manda el navegador, y apuntar a un archivo ajeno —o a uno que no
  -- llegó a subirse— dejaría a DO con un «Ver comprobante» que no abre.
  if p_ruta is null
     or split_part(p_ruta, '/', 1) <> 'educacion'
     or lower(split_part(p_ruta, '/', 2)) <> v_yo::text
     or split_part(p_ruta, '/', 3) <> 'solicitudes'
     or split_part(p_ruta, '/', 4) !~ '^[0-9a-fA-F-]{36}$'
     or split_part(p_ruta, '/', 5) = '' then
    raise exception 'El comprobante tiene que estar en tu carpeta de solicitudes.';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'comprobantes' and name = p_ruta) then
    raise exception 'El archivo no llegó a subirse. Vuelve a intentarlo.';
  end if;

  if v_s.comprobante_url is not distinct from p_ruta then
    return;
  end if;

  update educacion_solicitudes set comprobante_url = p_ruta where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'educacion_solicitud_comprobante', v_s.comprobante_url, p_ruta, v_yo,
     case when v_s.comprobante_url is null
          then 'La integrante adjuntó el comprobante a su solicitud pendiente'
          else 'La integrante cambió el comprobante de su solicitud pendiente' end);
end;
$$;

grant execute on function fn_educacion_solicitud_adjuntar(uuid, text) to authenticated;
revoke execute on function fn_educacion_solicitud_adjuntar(uuid, text) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (522, 'la_solicitud_educativa_pendiente_recibe_su_comprobante')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN (un solo select; el SQL Editor corre solo el último) ────────
-- Antes de pegar, md5 de partida contra producción:
--   select md5(prosrc), length(prosrc) from pg_proc where proname = 'fn_educacion_solicitud_inmutable';
-- Después de pegar:
--   select (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 522) as registro,
--          (select count(*) from pg_proc where proname = 'fn_educacion_solicitud_adjuntar') as la_funcion,
--          (select prosrc like '%CAMBIO 0522%' from pg_proc where proname = 'fn_educacion_solicitud_inmutable') as el_trigger;
