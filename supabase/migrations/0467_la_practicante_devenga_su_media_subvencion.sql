-- ============================================================================
-- 0467_la_practicante_devenga_su_media_subvencion.sql
-- ============================================================================
--
-- QUÉ PROMETE
--   1 · Que el libro de desembolsos (`desembolsos_beneficios`, 0155) admita dos
--       ventanas más: 'subvencion_semestral' y 'descanso_practicante'. Son los
--       dos pagos que la ley le debe a una practicante y que hasta hoy no se
--       podían anotar en ningún sitio.
--   2 · Una función nueva de SOLO LECTURA, `fn_subvenciones_practicante`, que
--       dice cuánto lleva devengado cada practicante por esos dos conceptos,
--       cuánto se le pagó ya y cuándo cae su próximo hito.
--
-- POR QUÉ, Y POR QUÉ RECIÉN AHORA
--   La 0322 creó la categoría y dejó escrito, con la ley en la mano, que una
--   modalidad formativa NO genera gratificación, CTS ni vacaciones (Ley 28518,
--   art. 47) pero SÍ:
--     · media subvención económica adicional por cada 6 meses continuos, y
--     · 15 días de descanso subvencionado al cumplir 12 meses continuos.
--   Aquella migración los dejó anotados como trabajo pendiente porque «casi
--   nunca se activan». La mitad de esa premisa era falsa: el hito de 6 meses lo
--   cruza cualquier convenio normal. Y la boleta, desde entonces, le dice a la
--   practicante que esos dos derechos son suyos «aunque este sistema todavía no
--   los calcule solo: pídelos si se cumplen» (`boleta-hoja.tsx`). El sistema le
--   pedía a la persona que reclamara lo que él mismo podía calcular.
--
--   SUNAFIL lo dice con número: con una subvención de S/1.130, son S/565 por
--   cada seis meses, y otros S/565 por el descanso — que SE PAGA aunque el
--   convenio termine sin gozarlo. No es tiempo libre: es plata que hoy no
--   figura en ninguna reserva.
--
-- QUÉ ASUME
--   · Que la subvención mensual vive en `asignaciones_salario`, igual que el
--     salario de cualquiera: es lo que ya usa `fn_planilla_calcular_nucleo`
--     para pagarle sus horas. Sin tramo vigente no se inventa un monto: la
--     fila sale en cero con `sin_subvencion` en true, para que la pantalla lo
--     diga en vez de mentir con un cero mudo (la lección de la 0365).
--   · Que los hitos se cuentan desde `personas.fecha_ingreso`, el mismo origen
--     que usa la 0336 para el tope de 12 meses del convenio. No suma convenios
--     anteriores, por la misma decisión que aquella tomó con Felipe.
--
-- POR QUÉ UNA FUNCIÓN NUEVA Y NO UNA COLUMNA EN fn_provisiones
--   Decisión de Felipe, 2026-09-16. `fn_provisiones` no es solo el reporte de
--   una pantalla: `fn_grati_cts_periodo` (0346) la usa para autocompletar el
--   depósito REAL de gratificación y CTS. Meter ahí un concepto que solo le
--   toca a una categoría obligaría a reescribir sus 49.000 caracteres para
--   agregar plata que esa otra función no debe ver. Acá es una función aparte,
--   de solo lectura, que nadie más consume todavía. El precio, dicho: el
--   `gran_total` de `fn_provisiones` NO incluye estos dos conceptos, y la
--   pantalla los suma aparte diciendo de dónde salen.
--
-- CÓMO SE DEVENGA, Y POR QUÉ ASÍ
--   · MEDIA SUBVENCIÓN · se gana al completar cada 6 meses continuos, pero se
--     acumula proporcionalmente dentro del semestre en curso — el mismo
--     criterio con que esta casa provisiona una gratificación. Al llegar el
--     hito, la reserva ya está completa y no aparece un salto de medio mes de
--     subvención por persona el día del aniversario.
--   · DESCANSO · se gana al cumplir 12 meses. También se acumula mes a mes
--     desde el ingreso (decisión de Felipe, 2026-09-16), y por eso el
--     encabezado lo dice claro: si el convenio se corta antes del año, ese
--     devengado NO se paga, y la pantalla tiene que decirlo donde se lea.
--     Se acumula igual porque el convenio llega a 12 meses por diseño (0336) y
--     la alternativa —cero durante un año y medio mes de golpe— es justo la
--     sorpresa que esta pantalla existe para evitar.
--   · El tope del descanso es media subvención (15 días sobre 30), y se satura
--     ahí: pasado el año no sigue creciendo. Un segundo año de convenio
--     generaría un segundo descanso, y eso NO lo resuelve esta migración
--     —CAYLA topa los convenios en 12 meses (0336)—: queda dicho acá para que
--     el día que se amplíe a 24 meses (Ley 31396) nadie crea que ya está hecho.
--
-- LO QUE NO HACE, A PROPÓSITO
--   · No toca `fn_provisiones`, `fn_devenga`, `fn_devenga_beneficios` ni
--     `fn_planilla_calcular`. Un practicante sigue sin devengar gratificación,
--     CTS ni vacaciones en todas las demás pantallas, que es lo que dice la ley.
--   · No paga nada ni registra nada solo: `fn_registrar_desembolso` (0343) ya
--     es la puerta para anotar un pago, y con el CHECK ampliado acepta las dos
--     ventanas nuevas sin tocar su código.
--   · No amplía el tope de 12 meses del convenio. La Ley 31396 permite 24 en
--     prácticas profesionales y no derogó expresamente el art. 13 de la 28518;
--     Felipe decidió el 2026-09-16 dejar el tope como está hasta confirmarlo.
--
-- QUÉ COMPROBAR ANTES DE PEGAR (la función es NUEVA, no reescribe ninguna)
--   select proname, oidvectortypes(proargtypes) from pg_proc
--    where proname = 'fn_subvenciones_practicante';
--   → debe dar 0 filas. Si da alguna, PARAR: otra rama la creó primero y hay
--     que leerla antes de reemplazarla (el accidente de la 0297/0299).
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_subvenciones_practicante(date);
--   alter table desembolsos_beneficios drop constraint desembolsos_beneficios_ventana_check;
--   alter table desembolsos_beneficios add constraint desembolsos_beneficios_ventana_check
--     check (ventana = any (array['grati_s1','grati_s2','cts_may','cts_nov','vacaciones']));
--   Ojo: si ya se anotó algún pago con las ventanas nuevas, ese último paso
--   falla — y está bien que falle: son pagos hechos a personas reales.
-- ============================================================================

-- ── 1 · Las dos ventanas nuevas ─────────────────────────────────────────────
-- Idempotente: se suelta el CHECK viejo por nombre y se crea el nuevo. Si la
-- migración se pega dos veces, la segunda no cambia nada.
alter table desembolsos_beneficios
  drop constraint if exists desembolsos_beneficios_ventana_check;

alter table desembolsos_beneficios
  add constraint desembolsos_beneficios_ventana_check
  check (ventana = any (array[
    'grati_s1', 'grati_s2', 'cts_may', 'cts_nov', 'vacaciones',
    -- CAMBIO 0467 · los dos pagos de una modalidad formativa (Ley 28518,
    -- art. 42). Su fecha no es el 15 de un mes fijo: cae en el aniversario
    -- del convenio de cada persona, y por eso necesitan ventana propia en
    -- vez de colarse en 'vacaciones', que un practicante no devenga.
    'subvencion_semestral', 'descanso_practicante'
  ]));

comment on table desembolsos_beneficios is
  'Libro de beneficios desembolsados: las cinco ventanas del año laboral (dos gratificaciones, '
  'dos CTS, vacaciones) mas las dos de modalidad formativa que agrego la 0467 '
  '(subvencion_semestral, descanso_practicante). De que ano, cuanto, cuando y por donde salio. '
  'Solo lectura para admin o lider de DO; se escribe por fn_registrar_desembolso (0343).';

-- ── 2 · Lo que una practicante lleva devengado ──────────────────────────────
create or replace function fn_subvenciones_practicante(p_as_of date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_as_of date;
  v_out jsonb;
begin
  -- Mismo guard que fn_provisiones: esto dice cuánto se le debe a cada
  -- persona. `is not true` y no `not`, por la regla de la casa: un null no
  -- puede pasar como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver las subvenciones de practicantes.';
  end if;

  v_as_of := coalesce(p_as_of, fn_hoy_lima());

  select coalesce(jsonb_agg(f.fila order by f.nombre), '[]'::jsonb) into v_out
  from (
    select (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id', p.id,
        'nombre', p.nombres || ' ' || p.apellidos,
        'sede', s.codigo,
        'fecha_ingreso', p.fecha_ingreso,
        'subvencion_mensual', sub.monto,
        -- Sin tramo cargado no se inventa un monto: se avisa. Misma lección
        -- que la 0365 — dos ceros que se ven iguales significan cosas
        -- distintas, y el que miente es el que nadie revisa.
        'sin_subvencion', sub.monto is null,

        -- ── Media subvención acumulada desde el ingreso ──────────────────
        'semestres_cumplidos', hit.cumplidos,
        'semestre_desde', sem.desde,
        'semestre_hasta', sem.hasta,
        'proximo_hito', sem.hasta,
        'media_sub_devengado', ms.devengado,
        'media_sub_pagado', nullif(ms.pagado, 0),
        'media_sub_saldo', round(ms.devengado - ms.pagado, 2),

        -- ── Descanso de 15 días (se gana al cumplir 12 meses) ────────────
        'descanso_cumple', (p.fecha_ingreso + interval '12 months')::date,
        'descanso_ganado', v_as_of >= (p.fecha_ingreso + interval '12 months')::date,
        'descanso_devengado', ds.devengado,
        'descanso_pagado', nullif(ds.pagado, 0),
        'descanso_saldo', round(ds.devengado - ds.pagado, 2),

        'total_saldo', round((ms.devengado - ms.pagado) + (ds.devengado - ds.pagado), 2)
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    -- La subvención mensual vigente a la fecha de corte. Mismo lateral que
    -- usan fn_provisiones y fn_planilla_calcular_nucleo contra la misma tabla.
    left join lateral (
      select a.salario_mensual_soles as monto
      from asignaciones_salario a
      where a.persona_id = p.id
        and v_as_of >= a.vigente_desde
        and (a.vigente_hasta is null or v_as_of <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) sub on true
    -- Cuántos hitos de 6 meses ya cumplió, y entre qué fechas corre el que
    -- está acumulando ahora.
    cross join lateral (
      select ((extract(year from age(v_as_of, p.fecha_ingreso)) * 12
               + extract(month from age(v_as_of, p.fecha_ingreso)))::int / 6) as cumplidos
    ) hit
    cross join lateral (
      select (p.fecha_ingreso + make_interval(months => hit.cumplidos * 6))::date       as desde,
             (p.fecha_ingreso + make_interval(months => (hit.cumplidos + 1) * 6))::date as hasta
    ) sem
    cross join lateral (
      -- ⇩⇩⇩ SE ACUMULA DESDE EL INGRESO, NO POR SEMESTRE SUELTO ⇩⇩⇩
      --
      -- El primer intento miraba solo el semestre en curso, y el laboratorio
      -- lo tumbó en el borde exacto: al cumplir los 6 meses, `cumplidos` pasa
      -- a 1, el semestre nuevo arranca ESE día con 0 días corridos, y la media
      -- subvención recién ganada —S/565— desaparecía de la pantalla justo el
      -- día en que había que pagarla.
      --
      -- Es el mismo defecto que la auditoría del 2026-09-15 le encontró a
      -- `fn_provisiones` (una ventana no pagada se esfuma al cambiar de año),
      -- así que aquí se escribe al revés desde el principio: lo devengado es
      -- lo de TODOS los hitos cumplidos más la fracción del que corre, y lo
      -- pagado se resta de esa misma cuenta. Un hito que nadie pagó nunca se
      -- borra solo; queda pendiente hasta que aparezca en el libro.
      select
        round(coalesce(sub.monto, 0) * 0.5
              * (hit.cumplidos
                 + least((v_as_of - sem.desde)::numeric
                         / nullif((sem.hasta - sem.desde)::numeric, 0), 1)), 2)  as devengado,
        -- Todo lo anotado, de cualquier año. Un hito de un convenio que
        -- empezó en julio se paga al año siguiente, así que filtrar por un
        -- solo año volvería a esconder plata ya pagada (y la propondría dos
        -- veces). Se pregunta con `fn_beneficio_ya_depositado` (0163) año por
        -- año en vez de con un `sum` propio: dos copias de la misma regla es
        -- como nació el defecto que arregló la 0271.
        (select coalesce(sum(fn_beneficio_ya_depositado(p.id, 'subvencion_semestral', y)), 0)
           from generate_series(extract(year from p.fecha_ingreso)::int,
                                extract(year from v_as_of)::int + 1) y)          as pagado
    ) ms
    cross join lateral (
      select
        -- Descanso: media subvención repartida en los 12 meses, saturada al
        -- llegar al año. No se reparte más allá: el segundo descanso de un
        -- convenio de 24 meses no lo calcula esta migración.
        round(coalesce(sub.monto, 0) * 0.5
              * least((v_as_of - p.fecha_ingreso)::numeric / 365.0, 1), 2)       as devengado,
        (select coalesce(sum(fn_beneficio_ya_depositado(p.id, 'descanso_practicante', y)), 0)
           from generate_series(extract(year from p.fecha_ingreso)::int,
                                extract(year from v_as_of)::int + 1) y)          as pagado
    ) ds
    where p.estado = 'activo'
      and p.tipo_vinculo = 'practicante'
  ) f;

  return jsonb_build_object(
    'as_of', v_as_of,
    -- Las dos tasas van en el payload para que la pantalla no las escriba a
    -- mano: media subvención = 0.5 de la mensual; descanso = 15 días de 30.
    'factor_media_subvencion', 0.5,
    'factor_descanso', 0.5,
    'personas', v_out
  );
end;
$$;

comment on function fn_subvenciones_practicante(date) is
  'Lo que una practicante lleva devengado por los dos pagos de la Ley 28518 art. 42: '
  'media subvencion por cada 6 meses continuos y 15 dias de descanso al cumplir 12 meses '
  '(se paga aunque no se goce). Solo lectura. NO toca fn_provisiones: un practicante sigue '
  'sin devengar gratificacion, CTS ni vacaciones (art. 47). 0467.';

grant execute on function fn_subvenciones_practicante(date) to authenticated;
revoke execute on function fn_subvenciones_practicante(date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (467, 'la_practicante_devenga_su_media_subvencion')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Lo que hay que ver al terminar de pegar:
--   ventanas_del_libro  · debe listar las SIETE
--   la_funcion_existe   · una sola, con firma (date)
--   la_pantalla_puede   · `authenticated` puede ejecutarla
--   el_registro         · numero 467 con ESTE nombre (no el de otra migración)
select
  (select pg_get_constraintdef(c.oid)
     from pg_constraint c join pg_class t on t.oid = c.conrelid
    where t.relname = 'desembolsos_beneficios' and c.conname = 'desembolsos_beneficios_ventana_check')
                                                                    as ventanas_del_libro,
  (select count(*) from pg_proc where proname = 'fn_subvenciones_practicante')
                                                                    as la_funcion_existe,
  (select has_function_privilege('authenticated', p.oid, 'execute')
     from pg_proc p where p.proname = 'fn_subvenciones_practicante') as la_pantalla_puede,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 467)
                                                                    as el_registro;

-- NO se llama acá a fn_subvenciones_practicante: exige fn_es_admin_o_lider(),
-- que en el SQL Editor corre sin JWT y siempre da false (la misma advertencia
-- que dejó escrita la 0428). Se comprueban sus insumos directo sobre las
-- tablas: quiénes son practicantes, si tienen subvención cargada y en qué
-- fecha caen sus dos hitos.
select p.nombres || ' ' || p.apellidos                        as practicante,
       s.codigo                                               as sede,
       p.fecha_ingreso,
       a.salario_mensual_soles                                as subvencion_mensual,
       round(coalesce(a.salario_mensual_soles, 0) * 0.5, 2)   as media_subvencion_completa,
       (p.fecha_ingreso + interval '6 months')::date          as primer_hito_6_meses,
       (p.fecha_ingreso + interval '12 months')::date         as cumple_12_meses
  from personas p
  join sedes s on s.id = p.sede_base_id
  left join lateral (
    select a.salario_mensual_soles
      from asignaciones_salario a
     where a.persona_id = p.id
       and fn_hoy_lima() >= a.vigente_desde
       and (a.vigente_hasta is null or fn_hoy_lima() <= a.vigente_hasta)
     order by a.vigente_desde desc limit 1
  ) a on true
 where p.estado = 'activo' and p.tipo_vinculo = 'practicante'
 order by p.fecha_ingreso;
