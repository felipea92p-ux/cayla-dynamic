-- ============================================================================
-- 0439 — Copiar semana anterior, por sede
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Un botón en Turnos (Vista Semana/Integrada) que replica los turnos
--   PUNTUALES de la semana anterior (mismos 7 días de calendario, una semana
--   atrás) a la semana que se está mirando, para cada persona activa de la
--   sede — sin pisar ningún día que la semana destino ya tenga editado a
--   mano. Nace de la auditoría UX de Turnos (2026-09-14): hoy cada turno se
--   pone persona × día × turno, sin ningún atajo, para ~30 personas en 4
--   sedes.
--
-- QUÉ ASUME
--
--   · Que el HORARIO BASE (horarios_asignados) no necesita copiarse: ya
--     persiste automáticamente semana tras semana. Lo único que un turno
--     puntual representa es una EXCEPCIÓN a ese horario — cubrir a alguien,
--     un cambio de última hora — y es exactamente eso lo que esta función
--     replica, no la cobertura completa de la semana.
--   · Que "semana anterior" son los mismos 7 días de calendario, una semana
--     atrás (p_lunes_destino - 7 hasta p_lunes_destino - 1) — nunca "la
--     última semana CON turnos puntuales" si la inmediatamente anterior no
--     tenía ninguno. Copiar la última con datos sorprendería en silencio a
--     quien pulsa el botón esperando "la semana pasada", no "la última vez
--     que hubo excepciones".
--   · Que fn_set_turno/fn_set_descanso (0327) siguen siendo el único camino
--     para escribir en `turnos` — esta función no hace ningún insert
--     directo: llama a las mismas dos funciones que ya usa el modal de
--     edición, así que cada copia queda en correcciones_auditoria, respeta
--     el candado de periodo pagado por grupo y dispara
--     fn_recalcular_jornada igual que una edición manual.
--   · Mismo permiso que editar un turno cualquiera de esa sede: admin/DO, o
--     la encargada (supervisor_sede) de ESA sede — nunca de otra.
--
-- LA DECISIÓN QUE IMPORTA: SALTAR, NUNCA PISAR
--
--   Si el día destino YA tiene un turno puntual propio, esta función lo deja
--   intacto y lo cuenta como "saltado" en el resultado — nunca lo
--   sobrescribe. La alternativa (pisar todo) es más simple de programar y
--   mucho más cara de arrepentirse: destruiría en silencio una edición
--   manual hecha esa misma semana. El costo de "saltar de más" es que
--   alguien revise un día suelto a mano; el costo de "pisar de más" es
--   perder una corrección real sin que nadie lo note hasta que ya afectó una
--   jornada.
--
-- CÓMO SE REVIERTE
--
--   drop function fn_copiar_semana_anterior(uuid, date);
--   No toca datos por su cuenta — todo lo que escribe pasa por
--   fn_set_turno/fn_set_descanso, así que deshacer una copia puntual es lo
--   mismo que deshacer cualquier edición manual: abrir esa persona ese día y
--   corregirla, o fn_quitar_turno.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--
--   supabase/tests/348_copiar_semana_anterior_por_sede.test.sql
-- ============================================================================

create or replace function fn_copiar_semana_anterior(p_sede_id uuid, p_lunes_destino date)
returns table(persona_id uuid, fecha date, resultado text)
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
begin
  -- Permiso de sede: no hay un único "dueño" del dato para atarle
  -- fn_verificar_corrector (esto toca varias personas a la vez), así que se
  -- valida aparte, con el mismo criterio que ya usa el resto de la pantalla
  -- (permisos.ts: DO_Y_ENCARGADA). fn_set_turno/fn_set_descanso vuelven a
  -- validar por su cuenta persona por persona más abajo — esto solo evita
  -- que alguien sin ningún permiso reciba una tabla llena de "error: no
  -- autorizada" en vez de un rechazo limpio.
  if fn_es_admin_o_lider() is not true then
    if fn_rol_actual() is distinct from 'supervisor_sede'
       or fn_sede_actual_persona() is distinct from p_sede_id then
      raise exception 'No autorizada para copiar turnos de esta sede.';
    end if;
  end if;

  for r in
    select p.id as pid, t.fecha as fecha_origen, (t.fecha + 7) as fecha_destino,
           t.hora_entrada, t.hora_salida, t.es_descanso,
           exists (
             select 1 from turnos t2
              where t2.persona_id = p.id and t2.fecha = t.fecha + 7
           ) as ya_tiene
      from personas p
      join turnos t on t.persona_id = p.id
     where p.sede_base_id = p_sede_id
       and p.estado = 'activo'
       and t.fecha between p_lunes_destino - 7 and p_lunes_destino - 1
     order by p.nombres, t.fecha
  loop
    if r.ya_tiene then
      persona_id := r.pid; fecha := r.fecha_destino;
      resultado := 'saltado: ya tenía turno propio ese día';
      return next;
      continue;
    end if;

    -- Cada copia va en su propio begin/exception: si una persona choca con
    -- el candado de periodo pagado (una semana que ya se pagó parcialmente),
    -- eso no debe tumbar la copia de las otras 29.
    begin
      if r.es_descanso then
        perform fn_set_descanso(r.pid, r.fecha_destino);
      else
        perform fn_set_turno(r.pid, r.fecha_destino, r.hora_entrada, r.hora_salida);
      end if;
      persona_id := r.pid; fecha := r.fecha_destino; resultado := 'copiado';
      return next;
    exception when others then
      persona_id := r.pid; fecha := r.fecha_destino;
      resultado := 'error: ' || sqlerrm;
      return next;
    end;
  end loop;
end;
$function$;

comment on function fn_copiar_semana_anterior(uuid, date) is
  'Copia los turnos puntuales de la semana anterior (mismos 7 días de calendario, una semana atrás) a la semana que empieza en p_lunes_destino, para cada persona activa de p_sede_id — salvo los días donde el destino YA tiene un turno puntual propio, que se saltan sin pisarlos. Reusa fn_set_turno/fn_set_descanso, así que cada copia queda en correcciones_auditoria igual que una edición manual (0439).';

grant execute on function fn_copiar_semana_anterior(uuid, date) to authenticated;
revoke execute on function fn_copiar_semana_anterior(uuid, date) from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (439, 'copiar_semana_anterior_por_sede')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
