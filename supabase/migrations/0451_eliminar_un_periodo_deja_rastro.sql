-- ============================================================================
-- 0451 — ELIMINAR UN PERIODO DEJA RASTRO
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: cuando un administrador o líder elimina un periodo de planilla,
-- antes del borrado queda una fila en `periodos_eliminados` con quién lo borró,
-- cuándo, qué periodo era (id, fecha_ini, fecha_fin, estado) y una foto en
-- jsonb de TODO lo que el borrado se lleva en cascada: los movimientos de
-- planilla (bonos y descuentos, incluidos los «Ya pagado el dd/mm — fuera de
-- planilla») y las reversas de pago. La foto y el borrado van en la misma
-- transacción: o quedan los dos, o no queda ninguno.
--
-- Hasta hoy `fn_eliminar_periodo` hacía un `delete from periodos_planilla` y
-- la cascada (`on delete cascade` de movimientos_planilla y reversas_pago) se
-- llevaba esos registros sin dejar nada. Un descuento de S/ 300 cargado a una
-- integrante desaparecía y nadie podía decir después que existió ni quién lo
-- quitó. Aprobado por Felipe: «que deje rastro del borrado».
--
-- QUÉ ASUME:
--   · Parte del cuerpo de la 0327 (la vigente según donde-vive.sh, 4 versiones:
--     0026 → 0183 → 0327). La firma `(p_periodo_id uuid) returns void` NO
--     cambia; no se agrega ningún parámetro (un parámetro nuevo con default
--     crearía una sobrecarga y «function … is not unique» en producción).
--   · Los candados siguen idénticos y en el mismo orden: guard admin/líder
--     null-safe, advisory lock, periodo inexistente, solo el ÚLTIMO periodo,
--     ningún grupo pagado. La foto se toma DESPUÉS de todos ellos, así que un
--     intento rechazado no escribe nada.
--   · El advisory lock ya serializa la eliminación con la creación de periodos,
--     así que la foto ve exactamente las filas que el `delete` borra.
--   · `fn_persona_actual_id()` no es null cuando `fn_es_admin_o_lider()` es
--     true (el rol se lee de la misma fila de personas). Aun así la columna
--     `eliminado_por` se deja nullable: ver SE ROMPE SI.
--
-- POR QUÉ ASÍ:
--   DECIDÍ: una tabla propia, `periodos_eliminados`, append-only (RLS de
--     lectura para admin/líder, sin políticas de escritura, y un trigger que
--     rechaza update y delete), con la foto en jsonb.
--   DESCARTÉ: `correcciones_auditoria`, porque su `persona_id` es NOT NULL y
--     apunta a UNA persona (esa tabla responde «qué se le corrigió a quién»),
--     y un periodo eliminado es de todo el equipo a la vez. Para usarla habría
--     que inventar una persona (el propio admin como «afectado», que es falso)
--     o escribir una fila por integrante con movimientos (y entonces el
--     periodo sin movimientos no dejaría rastro, y las reversas —que no son de
--     nadie— no tendrían dónde ir). Además `valor_anterior` es text, no jsonb.
--     Relajar su NOT NULL cambiaría la promesa que hoy leen sus políticas de
--     RLS (`auditoria_select_propia`, `auditoria_insert_supervisor`), que
--     filtran por persona_id.
--   DESCARTÉ también el borrado blando (marcar el periodo como eliminado):
--     cambiaría cómo todas las lecturas de periodos_planilla entienden la
--     cadena de periodos, que es justo lo que la tarea pide no tocar.
--   SE ROMPE SI: alguien llega a esta función con rol admin/líder pero sin
--     fila en personas enlazada a su sesión (por ejemplo, una llamada con la
--     clave de servicio que falsee el rol): el rastro queda con
--     `eliminado_por` null. Se dejó nullable a propósito: un NOT NULL ahí haría
--     que en ese caso el periodo NO se pudiera borrar, y eso cambiaría el
--     comportamiento, que esta migración promete no tocar. También se rompe si
--     una migración futura agrega otra tabla hija con `on delete cascade` a
--     periodos_planilla: la foto no la vería. Quien la agregue tiene que
--     sumarla aquí.
--
-- md5 DE PARTIDA — PENDIENTE DE PRODUCCIÓN. Esta sesión no llega a producción.
--   Postgres LOCAL (2026-09-15), idéntico byte a byte al cuerpo de la 0327:
--     tal cual:        fc4bcdd4b1a3790dfe16e3217c68dc2c   (1034 caracteres)
--     sin comentarios: fc4bcdd4b1a3790dfe16e3217c68dc2c   (no tiene comentarios)
--   Ojo: la cabecera de la 0327 declara 14acc43cf164ba17e9e7e6cf0f7dc228 y
--   754 caracteres para esta misma función. El texto medido aquí coincide con
--   el cuerpo de la 0327 línea por línea, así que ese valor viejo parece mal
--   medido; no sirve de referencia. Manda lo que devuelva producción.
--   Felipe pega esto en el SQL Editor JUSTO ANTES de pegar la migración (solo
--   lee):
--
--     select md5(p.prosrc)                                   as tal_cual,
--            md5(array_to_string(array(
--              select regexp_replace(l, '[[:space:]]*--.*$', '')
--              from unnest(string_to_array(p.prosrc, chr(10))) as l
--              where btrim(l) not like '--%'
--            ), chr(10)))                                    as sin_comentarios,
--            length(p.prosrc)                                as caracteres,
--            length(p.prosrc) - length(replace(p.prosrc, chr(13), '')) as retornos
--       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'fn_eliminar_periodo';
--
--   · tal_cual = fc4bcdd4…            → seguir.
--   · solo sin_comentarios coincide   → seguir (mismo código).
--   · retornos = número de líneas (26) y lo demás difiere → CRLF de Windows,
--     benigno (ver CLAUDE.md).
--   · ninguno                         → PARAR: producción tiene otra versión.
--   Y debe salir UNA sola fila: si salen dos, hay una sobrecarga.
--
-- CÓMO SE REVIERTE:
--   1. Volver a pegar el `create or replace function fn_eliminar_periodo` de
--      la 0327 (bloque 33). Con eso el borrado deja de escribir rastro.
--   2. La tabla NO se borra: tiene el historial de lo que ya se eliminó.
--      Si de verdad hay que retirarla (y está vacía):
--        drop trigger if exists trg_periodos_eliminados_inmutable on periodos_eliminados;
--        drop function if exists fn_trg_periodos_eliminados_inmutable();
--        drop table if exists periodos_eliminados;   -- solo si está vacía
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================

-- ── 1 · Dónde queda el rastro ───────────────────────────────────────────────
-- Sin llave foránea a periodos_planilla a propósito: la fila existe justamente
-- porque el periodo ya no está. `eliminado_por` sí referencia a personas: las
-- personas nunca se borran, así que esa llave no puede romperse.
create table if not exists periodos_eliminados (
  id             uuid primary key default gen_random_uuid(),
  periodo_id     uuid not null,
  fecha_ini      date not null,
  fecha_fin      date not null,
  estado         text not null,
  eliminado_por  uuid references personas(id),
  eliminado_at   timestamptz not null default now(),
  movimientos    jsonb not null default '[]'::jsonb,
  reversas       jsonb not null default '[]'::jsonb,
  constraint periodos_eliminados_movimientos_es_lista check (jsonb_typeof(movimientos) = 'array'),
  constraint periodos_eliminados_reversas_es_lista    check (jsonb_typeof(reversas) = 'array')
);

comment on table periodos_eliminados is
  'Rastro de cada periodo de planilla eliminado con fn_eliminar_periodo (0451): quién, cuándo, qué periodo y la foto de los movimientos y reversas que el borrado se llevó en cascada. Append-only.';

create index if not exists idx_periodos_eliminados_at on periodos_eliminados (eliminado_at desc);

-- Solo se lee, y solo quien puede eliminar periodos. Sin políticas de
-- insert/update/delete: desde el cliente no se escribe nunca; la única que
-- escribe es fn_eliminar_periodo, que es SECURITY DEFINER.
alter table periodos_eliminados enable row level security;

drop policy if exists periodos_eliminados_select_admin_lider on periodos_eliminados;
create policy periodos_eliminados_select_admin_lider on periodos_eliminados
  for select to authenticated
  using (fn_es_admin_o_lider());

-- RLS no frena a una función SECURITY DEFINER ni a quien pega SQL. El rastro de
-- un borrado que se puede borrar no es rastro: el trigger lo cierra para todos.
-- Mismo molde que fn_trg_foto_es_inmutable (planilla_pagada_detalle).
create or replace function fn_trg_periodos_eliminados_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'El rastro de un periodo eliminado no se modifica ni se borra.';
end;
$$;

drop trigger if exists trg_periodos_eliminados_inmutable on periodos_eliminados;
create trigger trg_periodos_eliminados_inmutable
  before update or delete on periodos_eliminados
  for each row execute function fn_trg_periodos_eliminados_inmutable();

-- ── 2 · fn_eliminar_periodo toma la foto antes de borrar ────────────────────
-- Cuerpo de la 0327. Único cambio: el bloque marcado CAMBIO 0451, entre el
-- último candado y el delete. v_ini se agrega al select existente para la foto.
CREATE OR REPLACE FUNCTION public.fn_eliminar_periodo(p_periodo_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fin date; v_estado text; v_max date;
  v_ini date; -- CAMBIO 0451
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede eliminar periodos.';
  end if;
  perform pg_advisory_xact_lock(hashtext('periodos_planilla'));
  select fecha_fin, estado, fecha_ini into v_fin, v_estado, v_ini from periodos_planilla where id = p_periodo_id; -- CAMBIO 0451: + fecha_ini
  if not found then raise exception 'Periodo inexistente.'; end if;
  select max(fecha_fin) into v_max from periodos_planilla;
  if v_fin <> v_max then
    raise exception 'Solo se puede eliminar el ÚLTIMO periodo (para no romper la cadena).';
  end if;
  if (v_estado = 'pagado' and not exists (
        select 1 from periodo_grupo_pago g where g.periodo_id = p_periodo_id
      ))
     or exists (
        select 1 from periodo_grupo_pago g where g.periodo_id = p_periodo_id and g.estado = 'pagado'
      )
  then
    raise exception 'Un periodo pagado no se elimina; reábrelo primero si de verdad hace falta.';
  end if;

  -- CAMBIO 0451: antes de borrar, la foto de lo que la cascada se va a llevar.
  -- Va en la misma transacción que el delete: si el delete falla, la foto se
  -- deshace con él y no queda un rastro de un borrado que no ocurrió.
  insert into periodos_eliminados
    (periodo_id, fecha_ini, fecha_fin, estado, eliminado_por, movimientos, reversas)
  values (
    p_periodo_id, v_ini, v_fin, v_estado, fn_persona_actual_id(),
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id,
               'persona_id', m.persona_id,
               'tipo', m.tipo,
               'categoria', m.categoria,
               'concepto', m.concepto,
               'monto', m.monto,
               'periodo_origen_id', m.periodo_origen_id,
               'creado_por', m.creado_por,
               'created_at', m.created_at)
             order by m.created_at, m.id)
        from movimientos_planilla m
       where m.periodo_id = p_periodo_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id,
               'tipo', r.tipo,
               'grupo', r.grupo,
               'motivo', r.motivo,
               'revertido_por', r.revertido_por,
               'revertido_at', r.revertido_at,
               'pagado_at_previo', r.pagado_at_previo)
             order by r.revertido_at, r.id)
        from reversas_pago r
       where r.periodo_id = p_periodo_id
    ), '[]'::jsonb)
  );
  -- FIN CAMBIO 0451

  delete from periodos_planilla where id = p_periodo_id;
end;
$function$;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (451, 'eliminar_un_periodo_deja_rastro')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Verificación (solo lee; pegar después) ──────────────────────────────────
-- select
--   to_regclass('public.periodos_eliminados') is not null                           as tiene_tabla,
--   position('CAMBIO 0451' in pg_get_functiondef('fn_eliminar_periodo'::regproc)) > 0 as deja_rastro,
--   (select count(*) from pg_proc where proname = 'fn_eliminar_periodo') = 1           as una_sola_version,
--   (select numero || ' ' || nombre from migraciones_aplicadas where numero = 451)     as registro;
