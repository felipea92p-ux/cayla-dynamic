-- ============================================================================
-- 0349 — HISTORIAL MENSUAL DE OBJETIVOS (para el gráfico de /admin/objetivos)
-- ----------------------------------------------------------------------------
-- Qué promete: una lectura de los últimos N meses (12 por defecto) de
-- cumplidos/total de una persona, terminando en el mes que la pantalla tiene
-- elegido — la serie que alimenta el gráfico de barras que muestra la
-- tendencia, no solo el mes actual. Lee `objetivos_mensuales`, que YA es el
-- resumen sincronizado por `fn_objetivos_sync_mes` (0032): no se calcula nada
-- nuevo, se expone una ventana de lo que ya existe.
--
-- Qué asume: los meses SIN checklist entran igual en la serie, con
-- cumplidos=0 y total=0 — no se saltan. Un mes sin registro no es lo mismo
-- que un mes con 0% cumplido, y la pantalla es quien decide cómo dibujar esa
-- diferencia (un hueco gris, no una barra roja): esta función solo dice la
-- verdad de qué hay, `total=0` ya la distingue sin que haga falta un tercer
-- campo. Mismas reglas de visibilidad que `fn_objetivos_resumen` (0032):
-- admin/líder cualquiera, encargada su sede, la propia persona a sí misma —
-- sin autorización, la ventana vuelve vacía (no hay nada que ocultar con un
-- error: es de solo lectura, igual que el resto de las consultas del
-- checklist).
--
-- Por qué se eligió así: `generate_series` sobre meses + `left join` es lo
-- que rellena los huecos sin un `for` en plpgsql. `p_meses` se acota a
-- [1, 24] — un año y medio de sobra para una tendencia, y sin tope alguien
-- podría pedir una serie arbitrariamente larga.
--
-- Cómo se revierte: `drop function fn_objetivos_historial(uuid, int, int, int);`
-- No hay columnas nuevas que revertir.
-- ============================================================================

create or replace function fn_objetivos_historial(
  p_persona_id uuid, p_anio int, p_mes int, p_meses int default 12
)
returns jsonb
language sql stable security definer set search_path = public
as $$
  with ventana as (
    select generate_series(
      make_date(coalesce(p_anio, 2000), coalesce(p_mes, 1), 1)
        - (least(greatest(coalesce(p_meses, 12), 1), 24) - 1) * interval '1 month',
      make_date(coalesce(p_anio, 2000), coalesce(p_mes, 1), 1),
      interval '1 month'
    ) as d
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'anio', extract(year from v.d)::int,
           'mes', extract(month from v.d)::int,
           'cumplidos', coalesce(om.cumplidos, 0),
           'total', coalesce(om.total, 0)
         ) order by v.d), '[]'::jsonb)
  from ventana v
  left join objetivos_mensuales om
    on om.persona_id = p_persona_id
   and om.anio = extract(year from v.d)::int
   and om.mes = extract(month from v.d)::int
  where p_persona_id is not null
    and p_anio between 2020 and 2100
    and p_mes between 1 and 12
    and (
      fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and exists (
            select 1 from personas p
            where p.id = p_persona_id
              and p.sede_base_id = fn_sede_actual_persona()))
      or p_persona_id = fn_persona_actual_id()
    );
$$;

grant execute on function fn_objetivos_historial(uuid, int, int, int) to authenticated;
revoke execute on function fn_objetivos_historial(uuid, int, int, int) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (349, 'objetivos_historial_mensual')
on conflict (numero) do nothing;
