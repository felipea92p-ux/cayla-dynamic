-- ============================================================================
-- 0485_el_practicante_ve_su_descanso_y_subvencion_semestral.sql
-- ============================================================================
--
-- QUÉ PROMETE
--   Que un practicante deje de ver, en SU PROPIA constancia de subvención
--   (/mio/boleta), un texto que dice «este sistema todavía no los calcula»
--   sobre dos beneficios que la 0465/0467 (Ley 28518, art. 42) SÍ calculan
--   desde el 2026-09-15 — solo que hasta hoy ese cálculo vivía únicamente en
--   la pantalla de Provisiones, que ve DO, nunca en el documento que la
--   persona se lleva. Dos relojes de la misma ley: uno visible para DO, otro
--   ciego para quien lo devenga.
--
--   Función nueva de SOLO LECTURA, `fn_mis_subvenciones_practicante()`, que
--   una practicante puede llamar sobre SU PROPIA fila sin permiso de
--   admin/líder — `fn_subvenciones_practicante` (0467) exige
--   `fn_es_admin_o_lider()` a propósito, y esa puerta no se toca: sigue
--   siendo la única forma en que DO ve a TODAS las practicantes a la vez.
--
-- DECIDÍ:    una función HERMANA, no una reescritura ni un parámetro nuevo en
--            la de admin. Mismo molde que ya usa este repo dos veces —
--            fn_planilla_calcular (bulk, admin) junto a
--            fn_planilla_calcular_persona (una fila, self, 0329); y
--            fn_bonos_por_transferir (bulk, DO) junto a fn_mi_bono_cumpleanos
--            (self, 0478)—. `fn_mis_subvenciones_practicante` filtra
--            `where p.id = fn_persona_actual_id()` en vez de recorrer toda la
--            tabla, y no pide `fn_es_admin_o_lider()`.
-- DESCARTÉ:  (a) agregar un `p_persona_id` opcional a `fn_subvenciones_
--            practicante` y relajar su guard cuando coincide con quien llama.
--            Esa función ya la usa `provisiones.ts` con su forma actual
--            (jsonb con 'personas' como arreglo); tocar su guard mezclaría
--            "DO mirando a todo el equipo" con "alguien mirando su propio
--            dato" en la misma función, y un guard mal leído ahí filtraría
--            la subvención de una persona a cualquier otra que llame con su
--            propio id — el peor lugar para un error de ese tipo.
--            (b) exponer el cálculo desde `fn_planilla_calcular_persona`.
--            Esa función corre en el camino caliente de CADA vista de
--            autoservicio de CADA persona en planilla, y ya tiene 4 versiones
--            (0329/0339/0349/0397): sumarle una lateral join más por algo que
--            solo le importa a un practicante — hoy, un puñado de personas—
--            es correr el riesgo de esa función por un beneficio que ni
--            siquiera se paga solo todavía (ver QUÉ NO HACE).
-- SE ROMPE SI: alguien reordena el semestre/descanso de 0467 sin tocar esta
--            copia — las dos fórmulas quedan escritas por separado a
--            propósito (ver DESCARTÉ-a), así que un cambio de fórmula en una
--            sin la otra las desalinea. Se avisa en el comentario de la
--            función vigente (0467) para que la próxima sesión que la toque
--            mire también acá.
--
-- CÓMO SE CALCULA
--   Exactamente la misma fórmula que `fn_subvenciones_practicante` (0467),
--   copiada para una sola persona — ver esa migración para el razonamiento
--   completo de por qué se acumula desde el ingreso y no por semestre suelto.
--   No se reutiliza esa función internamente (llamarla desde acá chocaría con
--   su propio guard de admin/líder sobre la sesión de la propia practicante).
--
-- QUÉ NO HACE
--   · No paga nada. Sigue sin haber una línea automática en la boleta ni un
--     botón de "pagar" — Felipe decide cuándo, como ya documentó la 0465.
--   · No toca `fn_subvenciones_practicante`, `fn_provisiones` ni
--     `fn_planilla_calcular*`. Ninguna de esas cuatro funciones se reescribe.
--   · No le da a un practicante NADA de lo que ya no tenía: grati, CTS,
--     vacaciones de 30 días y aporte a pensión siguen en cero (art. 47).
--
-- QUÉ ASUME
--   · `fn_persona_actual_id()`, `fn_hoy_lima()` y `fn_beneficio_ya_
--     depositado(uuid,text,int)` sin cambios desde la 0163/0467.
--   · Quien no está enlazado (`fn_persona_actual_id() is null`) o no es
--     practicante activo recibe CERO FILAS, nunca un error — mismo criterio
--     que `fn_mi_bono_cumpleanos()` (0478): una pantalla de autoservicio no
--     puede reventar por preguntar por algo que no le corresponde a quien
--     mira.
--
-- CAÍDA EXTERNA
--   Ninguna dependencia externa: todo es esta base.
-- ============================================================================

create or replace function fn_mis_subvenciones_practicante()
returns table (
  subvencion_mensual   numeric,
  sin_subvencion        boolean,
  semestres_cumplidos   int,
  semestre_desde        date,
  semestre_hasta        date,
  media_sub_devengado   numeric,
  media_sub_pagado      numeric,
  media_sub_saldo       numeric,
  descanso_cumple       date,
  descanso_ganado       boolean,
  descanso_devengado    numeric,
  descanso_pagado       numeric,
  descanso_saldo        numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_yo     uuid := fn_persona_actual_id();
  v_as_of  date := fn_hoy_lima();
begin
  if v_yo is null then
    return;
  end if;

  return query
  select
    sub.monto,
    sub.monto is null,
    hit.cumplidos,
    sem.desde,
    sem.hasta,
    ms.devengado,
    nullif(ms.pagado, 0),
    round(ms.devengado - ms.pagado, 2),
    (p.fecha_ingreso + interval '12 months')::date,
    v_as_of >= (p.fecha_ingreso + interval '12 months')::date,
    ds.devengado,
    nullif(ds.pagado, 0),
    round(ds.devengado - ds.pagado, 2)
  from personas p
  -- La subvención mensual vigente a la fecha de corte. Mismo lateral que
  -- fn_subvenciones_practicante (0467) contra la misma tabla.
  left join lateral (
    select a.salario_mensual_soles as monto
    from asignaciones_salario a
    where a.persona_id = p.id
      and v_as_of >= a.vigente_desde
      and (a.vigente_hasta is null or v_as_of <= a.vigente_hasta)
    order by a.vigente_desde desc limit 1
  ) sub on true
  cross join lateral (
    select ((extract(year from age(v_as_of, p.fecha_ingreso)) * 12
             + extract(month from age(v_as_of, p.fecha_ingreso)))::int / 6) as cumplidos
  ) hit
  cross join lateral (
    select (p.fecha_ingreso + make_interval(months => hit.cumplidos * 6))::date       as desde,
           (p.fecha_ingreso + make_interval(months => (hit.cumplidos + 1) * 6))::date as hasta
  ) sem
  cross join lateral (
    select
      round(coalesce(sub.monto, 0) * 0.5
            * (hit.cumplidos
               + least((v_as_of - sem.desde)::numeric
                       / nullif((sem.hasta - sem.desde)::numeric, 0), 1)), 2)  as devengado,
      (select coalesce(sum(fn_beneficio_ya_depositado(p.id, 'subvencion_semestral', y)), 0)
         from generate_series(extract(year from p.fecha_ingreso)::int,
                              extract(year from v_as_of)::int + 1) y)          as pagado
  ) ms
  cross join lateral (
    select
      round(coalesce(sub.monto, 0) * 0.5
            * least((v_as_of - p.fecha_ingreso)::numeric / 365.0, 1), 2)       as devengado,
      (select coalesce(sum(fn_beneficio_ya_depositado(p.id, 'descanso_practicante', y)), 0)
         from generate_series(extract(year from p.fecha_ingreso)::int,
                              extract(year from v_as_of)::int + 1) y)          as pagado
  ) ds
  where p.id = v_yo
    and p.estado = 'activo'
    and p.tipo_vinculo = 'practicante';
end;
$$;

comment on function fn_mis_subvenciones_practicante() is
  'Lo mismo que fn_subvenciones_practicante (0467) para UNA SOLA persona: la que llama, '
  'sin exigir admin/líder. Vacío si no está enlazada o no es practicante activa. 0485.';

grant execute on function fn_mis_subvenciones_practicante() to authenticated;
revoke execute on function fn_mis_subvenciones_practicante() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (485, 'el_practicante_ve_su_descanso_y_subvencion_semestral')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
