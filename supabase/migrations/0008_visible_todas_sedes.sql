-- Personas que viajan entre sedes (ej. el founder, con base TRU pero que marca
-- también en LIM y AQP). Con este flag aparecen en el roster de TODOS los
-- terminales, no solo el de su sede base. El marcaje sigue registrando la sede
-- del terminal donde efectivamente marcan (marcajes.sede_id viene del terminal).

alter table personas add column visible_todas_sedes boolean not null default false;

-- Ampliar el roster del terminal: además de la gente de la sede del terminal,
-- incluye a quienes tienen visible_todas_sedes = true.
drop policy if exists personas_select_terminal_roster on personas;

create policy personas_select_terminal_roster on personas
  for select to authenticated
  using (
    estado = 'activo'
    and fn_sede_actual_terminal() is not null
    and (sede_base_id = fn_sede_actual_terminal() or visible_todas_sedes = true)
  );
