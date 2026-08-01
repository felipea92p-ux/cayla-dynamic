-- ============================================================================
-- 0115 — La pensión se descuenta DESDE AHORA, y la tabla de tasas lleva candado.
--
-- Arregla dos defectos que introdujo la 0114 y que están vivos en producción.
-- Los encontró una auditoría adversarial el 2026-07-31; los dos son míos.
--
-- ── DEFECTO 1: EL DESCUENTO SE ENCENDIÓ SOLO, Y HACIA ATRÁS ─────────────────
--
-- La 0114 dice en su cabecera que la diferencia contra el 13% plano «es de S/0.57
-- al mes». Eso solo sería cierto si configuracion.tasa_afp valiera 0.13. Vale 0.
--
-- El descuento se calcula con «coalesce(tpen.tasa, v_tasa_afp)»: usa la tasa del
-- régimen de la persona y, si no tiene, cae al valor global. Como la 0114 asignó
-- régimen a 20 personas, para ellas tpen.tasa NUNCA es nulo y el interruptor
-- global —que estaba en 0 justamente para que nada se moviera— jamás se consulta.
--
-- Resultado real, medido en la boleta de agosto de una persona de colibrí:
--
--     Remuneración Básica proporcional       36.96
--     Feriados                               39.71
--                                          ───────
--     suma de lo que la boleta imprime       76.67
--     Total que la boleta remata en          71.84
--                                          ───────
--     diferencia sin explicar                 4.83   ← 36.96 × 13.06% (Profuturo)
--
-- Y como las tasas se sembraron con vigente_desde = 2026-01-01, el descuento
-- alcanza TODO 2026. fn_proyeccion_periodo recalcula en vivo y no lee la foto
-- congelada de la 0096, así que cualquier periodo YA PAGADO que se reimprima sale
-- con un neto ~S/147 menor que el que se depositó de verdad.
--
-- LA CORRECCIÓN, y por qué no toca ni una línea de código: tasas_pension nació
-- versionada. Basta mover vigente_desde al inicio del primer periodo ABIERTO.
-- Los periodos anteriores no encuentran fila vigente (el lateral filtra por
-- «tp.vigente_desde <= p_fin»), caen al interruptor global en 0, y quedan
-- exactamente como se pagaron. Eso es «desde ahora», que es lo que Felipe pidió.
--
-- Decisión de Felipe el 2026-07-31: el descuento SE QUEDA encendido de aquí en
-- adelante —la movilidad lo compensa— pero visible en la boleta, no enmascarado.
--
-- ── DEFECTO 2: LA TABLA DE TASAS NO TENÍA CANDADO ───────────────────────────
--
-- tasas_pension quedó como la ÚNICA de 39 tablas sin row level security, y con
-- los permisos que Supabase da por defecto:
--
--     grants a authenticated -> SELECT, INSERT, UPDATE, DELETE, TRUNCATE
--     relrowsecurity = false, políticas = 0
--
-- Cualquiera que pueda iniciar sesión en la app llegaba a la tabla por la API
-- REST y cambiaba las tasas. Y fn_planilla_calcular es «security definer», o sea
-- que corre con permisos de dueño y aplica lo que encuentre sin chistar:
--
--     update tasas_pension set comision = 0.9 where regimen = 'profuturo';
--
-- descontaría el 103% de la remuneración a nueve personas. Al revés es más
-- silencioso: poner los tres componentes en 0 apaga el descuento y nadie lo nota.
--
-- El repo ya había fijado la convención contraria en la 0077 (líneas 36-37) y la
-- siguió en la 0101 y la 0105. Esta migración la aplica: RLS encendido, permisos
-- revocados, y lectura solo para admin o líder. La función no necesita política
-- porque es security definer.
--
-- ── LO QUE NO TOCA ──────────────────────────────────────────────────────────
-- Ninguna función. Ni fn_planilla_calcular, ni fn_provisiones. Solo datos y
-- permisos, así que no puede romper un cálculo.
--
-- ── LO QUE QUEDA PENDIENTE, Y ES IMPORTANTE ─────────────────────────────────
-- 1. Seis personas activas NO tienen régimen asignado (Carlos, Catherine, Camila,
--    Claudia, Rufina, Carmen). Caen al interruptor global en 0, así que a ellas
--    NO se les descuenta pensión mientras a las otras 20 sí. Hay que completar el
--    dato o decidir que quedan fuera a propósito.
-- 2. La boleta todavía no imprime la línea del descuento. Mientras no lo haga, el
--    total sigue sin cuadrar con sus propias líneas. Va en el frontend, aparte.
-- 3. Confirmar con el contador si ya retiene la AFP por fuera del sistema. Si lo
--    hace, este descuento la duplica y hay que apagarlo.
--
-- CÓMO SE REVIERTE: update tasas_pension set vigente_desde = '2026-01-01';
-- ============================================================================

-- ── 1. El candado ───────────────────────────────────────────────────────────

alter table tasas_pension enable row level security;

revoke all on tasas_pension from authenticated, anon;

drop policy if exists tasas_pension_lectura_admin on tasas_pension;
create policy tasas_pension_lectura_admin on tasas_pension
  for select using (fn_es_admin_o_lider());

grant select on tasas_pension to authenticated;

comment on table tasas_pension is
  'Tasas de aporte previsional por régimen, versionadas por vigencia. Solo lectura '
  'para admin o líder (0115). La escritura se hace por migración: una tasa mal puesta '
  'acá cambia el descuento de toda la planilla, y fn_planilla_calcular es security '
  'definer, así que aplica lo que encuentre sin validar.';

-- ── 2. La pensión, desde el primer periodo abierto ──────────────────────────

do $mig$
declare
  v_desde date;
  v_periodo text;
  v_movidas int;
  v_afectados int;
begin
  -- El primer periodo que todavía NO está pagado. Ese es el «ahora» de Felipe:
  -- lo que ya se depositó no se toca, lo que aún no cierra sí lleva el descuento.
  select p.fecha_ini, to_char(p.fecha_ini, 'DD/MM/YYYY') || ' → ' || to_char(p.fecha_fin, 'DD/MM/YYYY')
    into v_desde, v_periodo
  from periodos_planilla p
  where p.estado <> 'pagado'
  order by p.fecha_ini
  limit 1;

  if v_desde is null then
    -- Sin periodo abierto, arrancamos el día después del último pagado, para no
    -- alcanzar nada ya depositado.
    select max(p.fecha_fin) + 1 into v_desde from periodos_planilla p where p.estado = 'pagado';
    v_periodo := '(no hay periodo abierto; se usa el día siguiente al último pagado)';
  end if;

  -- BASE SIN NINGÚN PERIODO: no es un error, es una base nueva.
  --
  -- La primera versión de esta migración lanzaba una excepción acá, con el
  -- razonamiento de «mejor fallar que adivinar una fecha». Estaba bien para
  -- producción y MAL como migración: CI la aplicó sobre una base recién creada,
  -- donde periodos_planilla está vacía, y el replay completo se cayó. Una
  -- migración tiene que poder correr sobre una base vacía.
  --
  -- Y no hay nada que proteger: sin periodos, nunca se calculó una planilla, así
  -- que no existe un pago pasado al que este descuento pudiera alcanzar. Se deja
  -- la vigencia como vino y se avisa. Cuando esa base tenga su primer periodo, la
  -- vigencia se ajusta corriendo el update de la sección 2 a mano.
  if v_desde is null then
    raise notice '0115 · periodos_planilla está vacía: base nueva, no hay pago pasado que proteger.';
    raise notice '0115 · la vigencia de tasas_pension queda como está (%).',
      (select coalesce(min(vigente_desde)::text, 'sin filas') from tasas_pension);
    raise notice '0115 · el candado de RLS de la sección 1 SÍ quedó aplicado.';
    return;
  end if;

  update tasas_pension set vigente_desde = v_desde where vigente_desde < v_desde;
  v_movidas := (select count(*) from tasas_pension where vigente_desde = v_desde);

  select count(*) into v_afectados
  from personas pe
  where pe.estado = 'activo' and pe.regimen_pension is not null;

  raise notice '0115 · la pensión se descuenta desde: % (periodo %)', v_desde, v_periodo;
  raise notice '0115 · filas de tasas_pension con esa vigencia: %', v_movidas;
  raise notice '0115 · personas activas a las que SÍ se les descontará: %', v_afectados;
  raise notice '0115 · personas activas SIN régimen (no se les descuenta): %',
    (select coalesce(string_agg(pe.nombres || ' ' || pe.apellidos, ', ' order by pe.nombres), '(ninguna)')
       from personas pe where pe.estado = 'activo' and pe.regimen_pension is null);
  raise notice '0115 · periodos ya pagados: quedan intactos (no encuentran tasa vigente y caen al interruptor global)';
end
$mig$;

-- ── 3. Comprobación: ningún periodo pagado debe encontrar tasa vigente ──────

do $mig$
declare
  v_malos int;
begin
  select count(*) into v_malos
  from periodos_planilla p
  where p.estado = 'pagado'
    and exists (
      select 1 from tasas_pension tp
      where tp.vigente_desde <= p.fecha_fin
        and (tp.vigente_hasta is null or tp.vigente_hasta >= p.fecha_fin)
    );

  if v_malos > 0 then
    raise exception '0115 · FALLA: % periodo(s) ya pagado(s) siguen alcanzando una tasa vigente. '
                    'Se reescribiría un pago hecho. Reviso antes de dar esto por bueno.', v_malos;
  end if;

  raise notice '0115 · verificado: ningún periodo pagado alcanza una tasa vigente';
end
$mig$;

insert into migraciones_aplicadas (numero, nombre)
values (115, 'la_pension_desde_ahora_y_con_candado')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
