-- ============================================================================
-- 0594 · QUIEN INGRESA DESPUÉS NO MARCA NI DEVENGA ANTES DE SU FECHA
-- ============================================================================
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--   Que se puede registrar HOY que alguien ingresa mañana (o en cualquier fecha
--   futura de hasta un año), y que mientras esa fecha no llegue la persona:
--     · no aparece en el terminal de marcaje,
--     · no puede registrar una marca (aunque llegue por otro camino),
--     · no devenga subvención ni descanso de practicante.
--   Desde su fecha de ingreso todo corre igual que siempre. Nada se le paga
--   antes: lo que cuenta es lo trabajado desde esa fecha.
--
-- ── EL PROBLEMA ─────────────────────────────────────────────────────────────
--   `fn_set_fecha_ingreso` (0027) rechazaba cualquier fecha posterior a hoy con
--   «La fecha de ingreso no puede ser futura». Esa regla nació cuando la fecha
--   de ingreso era «la primera entrada marcada» y servía de freno al error de
--   tipeo. Hoy bloquea un caso normal: dar de alta a alguien que empieza pronto
--   (`fn_crear_persona` no recibe fecha y la deja en el día del alta, así que
--   la única forma de ponerle la verdadera era editarla después — y ahí frenaba).
--
-- ── POR QUÉ NO SE QUITÓ SIN MÁS ─────────────────────────────────────────────
--   Se midió (lectura de las funciones vigentes, 2026-11-04) qué haría el
--   sistema con una fecha futura. Ya lo manejaban bien las faltas, los feriados,
--   la CTS, la gratificación y las vacaciones truncas. Lo que NO:
--     1. El terminal la ofrecía y la dejaba marcar antes de su fecha
--        (`terminal_roster` solo miraba `estado = 'activo'`; `fn_registrar_marcaje`
--        no lee `fecha_ingreso`).
--     2. Si ya tenía horas marcadas, moverle el ingreso a una fecha posterior
--        las dejaba pagándose desde antes de «ingresar».
--     3. `fn_subvenciones_practicante` y `fn_mis_subvenciones_practicante`
--        restan `v_as_of - fecha_ingreso` sin acotar: con ingreso futuro el
--        devengado y el saldo salían NEGATIVOS.
--   Esta migración cierra esos tres y nada más.
--
-- ── LO QUE NO SE TOCA, A PROPÓSITO ──────────────────────────────────────────
--   `fn_planilla_calcular` NO se reescribe. La planilla paga horas marcadas; si
--   nadie puede marcar antes del ingreso, no hay nada que pagar antes. Lo que sí
--   hace la planilla con alguien que ingresa a MITAD de un periodo —sale como
--   fila del periodo entero, con el piso de EsSalud y la asignación familiar
--   completa— ya pasa hoy con cualquier ingreso pasado a mitad de mes y es una
--   regla de planilla ya decidida: esta migración no la cambia ni la empeora
--   (con fecha futura la fila solo existe si `fecha_ingreso <= p_fin`).
--   Tampoco se tocan los avisos con «días» negativos de vacaciones y del
--   vínculo, ni el tablero: son de pantalla y no mueven plata.
--
-- ── QUÉ CAMBIA ──────────────────────────────────────────────────────────────
--   1 · fn_set_fecha_ingreso: acepta fechas futuras, hasta 365 días (solo
--       contra el error de tipeo: 2062 por 2026). Si la fecha es futura y la
--       persona YA tiene jornadas con horas antes de ella, se niega.
--       Con fecha de hoy o pasada se comporta EXACTAMENTE como antes.
--   2 · fn_marcaje_no_anterior_al_ingreso + trigger nuevo sobre `marcajes`:
--       una marca anterior al ingreso se rechaza SOLO si el ingreso todavía no
--       llegó. Quien ya ingresó —aunque alguien le haya puesto un ingreso
--       posterior a sus primeras marcas— no se ve afectado: no se reescribe la
--       historia de nadie.
--   3 · terminal_roster: no ofrece a quien todavía no ingresó.
--   4 · fn_subvenciones_practicante y fn_mis_subvenciones_practicante: no
--       cuentan a quien su fecha de ingreso (o la fecha `as_of` que se mira)
--       todavía no alcanzó.
--
-- ── ANTES DE PEGAR ──────────────────────────────────────────────────────────
--   Reescribe tres funciones y una vista vivas, y cada una se verifica contra
--   producción en el bloque «0 · La guardia»: si el md5 no es el esperado, la
--   migración se NIEGA y no cambia nada. Esa guardia reconoce su propio trabajo
--   (el md5 de llegada), así que repegar es seguro.
--   Se pega de una sola vez: toca UNA tabla (`marcajes`, el trigger) y su
--   bloqueo es breve; `lock_timeout` de 3 s hace que, si una Mac mini está
--   marcando justo en ese instante, falle en vez de dejar a todos en cola.
--   Si falla por eso, se repega.
--
-- ── md5 DE PARTIDA (PRODUCCIÓN, 2026-11-04, no el local) ────────────────────
--   fn_set_fecha_ingreso            30917fdcf0e99db26b63004807676488 · 870
--   fn_subvenciones_practicante     9ccd9ca3cbad7397e5269f7efbe0b800 · 5888
--   fn_mis_subvenciones_practicante d998f8772d23337ab2d08f96b94e8c1f · 2414
--   vista terminal_roster           95d3ef531dda159dfabfdbfbbca2f6ec · 564
--   (coincidieron con el repositorio: las vigentes son 0327, 0467, 0485 y 0539.)
--
-- ── md5 DE LLEGADA ──────────────────────────────────────────────────────────
--   fn_set_fecha_ingreso            95229586f07f3b538a0eeda5eb0c8ba8
--   fn_subvenciones_practicante     a24985973af97c7951b16d2f3ed4b895
--   fn_mis_subvenciones_practicante 56f583b54f884bf3915440ed9507a959
--   vista terminal_roster           bef31762f93ecdb28bf732b742b66942
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop trigger if exists trg_marcaje_no_anterior_al_ingreso on marcajes;
--   drop function if exists fn_marcaje_no_anterior_al_ingreso();
--   y volver a pegar los cuerpos de la 0327 (fn_set_fecha_ingreso), 0467
--   (fn_subvenciones_practicante), 0485 (fn_mis_subvenciones_practicante) y
--   0539 (vista terminal_roster). Quien ya tenga una fecha futura guardada se
--   queda con ella; solo volvería a ser imposible guardar una nueva.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final devuelve una fila con CINCO `true`.
-- ============================================================================

set local lock_timeout = '3s';

-- ── 0 · La guardia: esta migración se niega si producción no es lo que cree ─
--
-- Reescribe objetos vivos con `create or replace`, que no da ninguna señal si lo
-- que pisa no es lo que se creía. Acepta el md5 de partida o el de llegada (para
-- poder repegar); cualquier otro significa que alguien construyó encima.
do $guardia$
declare
  v_md5 text;
  v_ok  boolean;
begin
  select md5(prosrc) into v_md5 from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'fn_set_fecha_ingreso';
  if v_md5 is null or v_md5 not in ('30917fdcf0e99db26b63004807676488', '95229586f07f3b538a0eeda5eb0c8ba8') then
    raise exception 'fn_set_fecha_ingreso no es la versión que esta migración espera (md5 %). Alguien la cambió: no se pega nada. Revisa con ./scripts/donde-vive.sh fn_set_fecha_ingreso.', coalesce(v_md5, 'no existe');
  end if;

  select md5(prosrc) into v_md5 from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'fn_subvenciones_practicante';
  if v_md5 is null or v_md5 not in ('9ccd9ca3cbad7397e5269f7efbe0b800', 'a24985973af97c7951b16d2f3ed4b895') then
    raise exception 'fn_subvenciones_practicante no es la versión que esta migración espera (md5 %). No se pega nada.', coalesce(v_md5, 'no existe');
  end if;

  select md5(prosrc) into v_md5 from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'fn_mis_subvenciones_practicante';
  if v_md5 is null or v_md5 not in ('d998f8772d23337ab2d08f96b94e8c1f', '56f583b54f884bf3915440ed9507a959') then
    raise exception 'fn_mis_subvenciones_practicante no es la versión que esta migración espera (md5 %). No se pega nada.', coalesce(v_md5, 'no existe');
  end if;

  v_md5 := md5(pg_get_viewdef('terminal_roster'::regclass));
  if v_md5 not in ('95d3ef531dda159dfabfdbfbbca2f6ec', 'bef31762f93ecdb28bf732b742b66942') then
    raise exception 'La vista terminal_roster no es la que esta migración espera (md5 %). No se pega nada.', v_md5;
  end if;
end;
$guardia$;

-- ── 1 · fn_set_fecha_ingreso: ya se puede registrar un ingreso futuro ───────
-- Cuerpo de la 0327 con DOS bloques nuevos (marcados CAMBIO 0594). Las demás
-- validaciones, el mensaje del periodo pagado y el update final no se tocaron.
CREATE OR REPLACE FUNCTION public.fn_set_fecha_ingreso(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la fecha de ingreso.';
  end if;
  if p_fecha is null then raise exception 'La fecha de ingreso es obligatoria.'; end if;
  -- CAMBIO 0594 · antes: `p_fecha > fn_hoy_lima()` → «no puede ser futura». Quien ingresa mañana
  -- tiene que poder registrarse hoy. Queda un tope de un año, solo contra el error de tipeo.
  if p_fecha > fn_hoy_lima() + 365 then
    raise exception 'La fecha de ingreso está a más de un año de hoy. Revisa el año.';
  end if;
  -- CAMBIO 0594 · si el ingreso es futuro, no puede haber horas anteriores a él: esa persona ya
  -- estaría trabajando antes de «ingresar», y esas horas seguirían pagándose desde antes.
  -- Con fecha de hoy o pasada esto no corre, y el cambio se comporta como siempre.
  if p_fecha > fn_hoy_lima() and exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha < p_fecha
      and (j.horas_trabajadas is not null or j.entrada_ts is not null)
  ) then
    raise exception 'Esta persona ya tiene horas marcadas antes del %. Su ingreso no puede ser posterior a su primera jornada.', to_char(p_fecha, 'DD/MM/YYYY');
  end if;
  if exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id
      and j.horas_trabajadas is not null
      and fn_fecha_en_periodo_pagado(j.fecha, p_persona_id)
  ) then
    raise exception 'Esta persona ya tiene un periodo PAGADO con jornadas trabajadas: cambiar su fecha de ingreso podría alterar los feriados de esa planilla. Reabre el periodo primero.';
  end if;
  update personas set fecha_ingreso = p_fecha where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$function$;

-- ── 2 · Ninguna marca antes del ingreso, si el ingreso todavía no llegó ─────
-- Misma forma que `fn_marcaje_no_posterior_al_cese` (0086). Se limita a quien
-- TODAVÍA no ingresó (`fecha_ingreso > hoy`) a propósito: a quien ya ingresó no se
-- le reescribe la historia —DO corrige marcas viejas todos los días, y una persona
-- con el ingreso mal puesto no debe quedar sin poder corregirlas—. Y no usa
-- `fn_registrar_marcaje`: reescribir esa función crítica por esto sería peor que el mal.
create or replace function fn_marcaje_no_anterior_al_ingreso()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ingreso date;
  v_fecha   date;
begin
  select fecha_ingreso into v_ingreso from personas where id = new.persona_id;
  if v_ingreso is null or v_ingreso <= fn_hoy_lima() then
    return new;
  end if;

  v_fecha := (new.timestamp_marca at time zone 'America/Lima')::date;
  if v_fecha < v_ingreso then
    raise exception 'No se puede registrar una marca del %: esa persona ingresa el %.',
      to_char(v_fecha, 'DD/MM/YYYY'), to_char(v_ingreso, 'DD/MM/YYYY');
  end if;
  return new;
end;
$$;

comment on function fn_marcaje_no_anterior_al_ingreso() is
  'Rechaza una marca anterior a la fecha de ingreso, pero SOLO si esa fecha todavía no llegó. Así quien ingresa mañana no '
  'marca ni cobra antes, y quien ya ingresó no ve reescrita su historia. Desde la 0594.';

revoke execute on function fn_marcaje_no_anterior_al_ingreso() from public, anon, authenticated;

drop trigger if exists trg_marcaje_no_anterior_al_ingreso on marcajes;
create trigger trg_marcaje_no_anterior_al_ingreso
  before insert on marcajes
  for each row execute function fn_marcaje_no_anterior_al_ingreso();

-- ── 3 · terminal_roster: no ofrece a quien todavía no ingresó ───────────────
-- El cuerpo es EXACTAMENTE el de la 0539; solo se agrega una condición al final.
create or replace view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  p.foto_url,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre,
  -- CAMBIO 0539 · cuántos días de prueba lleva, o NULL si no está de prueba. Si la fila de la
  -- prueba no existe (el trigger de la 0536 nunca frena un cambio de vínculo), cuenta desde su ingreso.
  fn_terminal_prueba_dias(p.id) as prueba_dias,
  case when p.tipo_vinculo = 'prueba' then fn_prueba_dias_plazo() end as prueba_plazo
from personas p
join sedes s on s.id = p.sede_base_id
where p.estado = 'activo'
  and not p.cuenta_de_servicio   -- CAMBIO 0490: una estación de retail no marca asistencia
  and p.fecha_ingreso <= fn_hoy_lima()   -- CAMBIO 0594: quien ingresa mañana no aparece hoy
  and fn_sede_actual_terminal() is not null
  and fn_persona_marca_en_sede(p.id, fn_sede_actual_terminal());

-- ── 4 · Subvenciones del practicante: nada se devenga antes del ingreso ─────
-- Cuerpos de la 0467 y la 0485 con UNA condición más en el `where`.
CREATE OR REPLACE FUNCTION public.fn_subvenciones_practicante(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      -- CAMBIO 0594 · quien todavía no ingresó (a la fecha que se mira) no devenga nada: sin esto la resta
      -- `v_as_of - fecha_ingreso` da negativo y la subvención y el saldo salían en menos.
      and p.fecha_ingreso <= v_as_of
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_mis_subvenciones_practicante()
 RETURNS TABLE(subvencion_mensual numeric, sin_subvencion boolean, semestres_cumplidos integer, semestre_desde date, semestre_hasta date, media_sub_devengado numeric, media_sub_pagado numeric, media_sub_saldo numeric, descanso_cumple date, descanso_ganado boolean, descanso_devengado numeric, descanso_pagado numeric, descanso_saldo numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    and p.tipo_vinculo = 'practicante'
    -- CAMBIO 0594 · quien todavía no ingresó no devenga nada (ver fn_subvenciones_practicante).
    and p.fecha_ingreso <= v_as_of;
end;
$function$;

-- ── Registro ─────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (594, 'quien_ingresa_despues_no_marca_ni_devenga_antes_de_su_fecha')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Verificación: UNA fila con CINCO `true` ──────────────────────────────────
select
  (select prosrc like '%CAMBIO 0594%' from pg_proc
    where pronamespace = 'public'::regnamespace and proname = 'fn_set_fecha_ingreso')              as ingreso_futuro_permitido,
  exists (select 1 from pg_trigger t where t.tgname = 'trg_marcaje_no_anterior_al_ingreso'
            and t.tgrelid = 'marcajes'::regclass and not t.tgisinternal)                            as freno_de_marcas,
  (select definition like '%fecha_ingreso%' from pg_views
    where schemaname = 'public' and viewname = 'terminal_roster')                                   as roster_sin_futuros,
  (select bool_and(prosrc like '%CAMBIO 0594%') from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('fn_subvenciones_practicante', 'fn_mis_subvenciones_practicante'))            as subvenciones_acotadas,
  exists (select 1 from migraciones_aplicadas
           where numero = 594 and nombre = 'quien_ingresa_despues_no_marca_ni_devenga_antes_de_su_fecha') as registrada;
