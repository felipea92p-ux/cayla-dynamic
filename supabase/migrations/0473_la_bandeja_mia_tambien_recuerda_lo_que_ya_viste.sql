-- ============================================================================
-- 0473 — fn_bandeja_marcar_visto reconoce los cambios de turno
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: agrega 'cambio_turno' a los tipos de ítem que
-- `fn_bandeja_marcar_visto` (0436/0450/0453/0461) acepta. Con esto, /mio/bandeja
-- —el buzón de CADA PERSONA, distinto de /admin/bandeja, que es la cola de
-- aprobación— puede usar el MISMO mecanismo de «ya lo viste» para sus seis
-- tipos de respuesta, sin tabla ni función nueva: cinco ya encajaban en un tipo
-- existente (perfil→solicitud_perfil, vacaciones→solicitud_vacacion,
-- revisión de un día→revision, revisión de ruta→revision_movilidad,
-- constancia de estudios→entrega_educacion); solo el cambio de turno que le
-- hicieron a alguien (correcciones_auditoria filtrada por
-- campo_modificado = 'turnos.horario', ver bandeja-mia.ts) no tenía dónde caer.
--
-- QUÉ ASUME:
--   · Que la 0461 es la versión vigente de esta función y de este check.
--     Comprobado con `donde-vive.sh fn_bandeja_marcar_visto` al escribir esta
--     migración: 4 versiones (0436, 0450, 0453, 0461), la 0461 es la última, y
--     `git grep bandeja_vistos` sobre todas las ramas locales y remotas no
--     encontró ninguna rama sin fusionar que la vuelva a tocar.
--   · MD5 DE PARTIDA — PEDIRLO A PRODUCCIÓN ANTES DE PEGAR, no copiarlo de acá:
--
--       select md5(p.prosrc), length(p.prosrc)
--         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--        where n.nspname = 'public' and p.proname = 'fn_bandeja_marcar_visto';
--
--     y comparar contra el cuerpo de la 0461 en este repositorio. El md5 medido
--     en el Postgres LOCAL de este worktree dio 2acf861c9961c9d81dce9bcb7958d51f
--     — que es el cuerpo de la 0436/0453 VIEJA (593 caracteres): el Postgres
--     compartido de los worktrees está atrasado respecto al repositorio, no
--     corrió la 0461 todavía, así que ese md5 local NO sirve de referencia acá.
--     El cuerpo de partida de esta migración se copió tal cual del ARCHIVO de
--     la 0461, no de una consulta a ese Postgres local.
--
-- POR QUÉ UN TIPO NUEVO Y NO REUSAR UNO EXISTENTE: un cambio de turno no es
-- una solicitud que alguien pidió, ni una revisión que alguien reclamó, ni una
-- constancia — es algo que le HICIERON a la persona sin que ella lo pidiera
-- (mismo origen que ya distingue bandeja-mia.ts). Forzarlo dentro de otro tipo
-- mezclaría dos preguntas distintas bajo la misma fila de bandeja_vistos.
--
-- CÓMO SE REVIERTE:
--   alter table bandeja_vistos drop constraint bandeja_vistos_tipo_item_check;
--   alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check
--     check (tipo_item in ('revision', 'revision_movilidad', 'revision_contrato',
--       'solicitud_vacacion', 'solicitud_perfil', 'entrega_educacion',
--       'aviso_fin_educacion', 'solicitud_educacion'));
--   -- y volver a pegar el cuerpo de la 0461 de fn_bandeja_marcar_visto (sin
--   -- 'cambio_turno' en su lista). De paso, borrar las filas que hayan quedado
--   -- con tipo_item = 'cambio_turno': delete from bandeja_vistos where
--   -- tipo_item = 'cambio_turno';
--
-- Idempotente: `drop constraint if exists` + `add constraint`, y
-- `create or replace function`.
-- ============================================================================

alter table bandeja_vistos drop constraint if exists bandeja_vistos_tipo_item_check;
alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check check (tipo_item in (
  'revision', 'revision_movilidad', 'revision_contrato',
  'solicitud_vacacion', 'solicitud_perfil',
  'entrega_educacion', 'aviso_fin_educacion',
  'solicitud_educacion',
  -- ⇩ CAMBIO 0473 ⇩
  'cambio_turno'
));

-- Cuerpo de la 0461 (md5 de partida arriba) con un tipo agregado.
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
                          'solicitud_educacion', 'cambio_turno') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$$;

grant execute on function fn_bandeja_marcar_visto(text, uuid) to authenticated;
revoke execute on function fn_bandeja_marcar_visto(text, uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (473, 'la_bandeja_mia_tambien_recuerda_lo_que_ya_viste')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.check_constraints
    where constraint_name = 'bandeja_vistos_tipo_item_check') as check_existe,
  (select count(*) from pg_proc where proname = 'fn_bandeja_marcar_visto') as fn_existe;
