-- ============================================================================
-- 0515 — DO se entera de lo que registra una líder, y la líder de lo que hace DO
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Dos avisos nuevos en la Bandeja del panel, que se van cuando se miran:
--
--   · `conducta_registrada`: a la líder DO, cada falta de conducta que registra
--     una líder de equipo. item_id = el documento.
--   · `caso_traspasado`: a la líder que inició un caso, cuando DO se lo toma o
--     se lo devuelve, con el motivo. item_id = la fila de `expediente_traspasos`.
--
-- Esta migración solo hace que la marca de «visto» los acepte: los dos sitios
-- donde vive la lista de tipos —la restricción de `bandeja_vistos` y la propia
-- `fn_bandeja_marcar_visto`— tienen que conocerlos. Qué se muestra y cuándo lo
-- decide la pantalla (`lib/admin/bandeja-fuentes.ts`).
--
-- ── DE QUIÉN ES LA DECISIÓN ─────────────────────────────────────────────────
--
-- De la usuaria, el 2026-10-06: el aviso a DO aparece al registrarse el
-- borrador —antes de que se firme, que es cuando tomar el caso todavía sirve—
-- y se va cuando lo abre; DO «solo visualiza». Y la líder recibe aviso cuando
-- DO toma o devuelve su caso, para no descubrirlo recién cuando intenta firmar.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- Se reutiliza `bandeja_vistos` (0436) y no una columna nueva en el
-- expediente: «quién vio qué» ya tiene su tabla, por persona, y la Bandeja ya
-- sabe leerla. Una columna `do_visto_at` en el expediente habría dicho «lo vio
-- DO» sin decir quién, y con dos personas en DO no alcanza.
--
-- La lista de tipos sigue escrita en dos sitios porque así está desde la 0436;
-- unificarla es otro cambio. Esta migración agrega los dos tipos en los dos.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- Que la 0511 está pegada (`expediente_traspasos`) — verificado en producción
-- el 2026-10-06.
--
-- md5 de partida (pedido a PRODUCCIÓN el 2026-10-06, idéntico al repo):
--   fn_bandeja_marcar_visto  ca3abcea2a13b8bec4ea3e08df374c44  (0473, 763 caracteres)
-- Y la restricción, en producción ese día, con los nueve tipos de la 0473.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   delete from bandeja_vistos where tipo_item in ('conducta_registrada', 'caso_traspasado');
-- y repegar la restricción y la función de la 0473.
-- ============================================================================

alter table bandeja_vistos drop constraint if exists bandeja_vistos_tipo_item_check;
alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check check (tipo_item in (
  'revision', 'revision_movilidad', 'revision_contrato',
  'solicitud_vacacion', 'solicitud_perfil',
  'entrega_educacion', 'aviso_fin_educacion',
  'solicitud_educacion',
  'cambio_turno',
  -- ⇩ CAMBIO 0515 ⇩
  'conducta_registrada', 'caso_traspasado'
));

-- Copiada de la 0473 (la vigente). Lo único nuevo son los dos tipos de la lista.
create or replace function fn_bandeja_marcar_visto(p_tipo_item text, p_item_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;
  -- ⇩ CAMBIO 0473 ⇩ cambio_turno.
  if p_tipo_item not in ('revision', 'revision_movilidad', 'revision_contrato',
                          'solicitud_vacacion', 'solicitud_perfil',
                          'entrega_educacion', 'aviso_fin_educacion',
                          'solicitud_educacion', 'cambio_turno',
                          -- CAMBIO 0515 · avisos de conducta
                          'conducta_registrada', 'caso_traspasado') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$$;

grant execute on function fn_bandeja_marcar_visto(text, uuid) to authenticated;
revoke execute on function fn_bandeja_marcar_visto(text, uuid) from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (515, 'do_se_entera_y_la_lider_tambien')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
