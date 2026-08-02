-- ============================================================================
-- 0127 — La foto del pago vuelve a cuadrar, y por eso agosto se puede cerrar
--
-- QUÉ DESBLOQUEA. Hoy «Marcar como PAGADO» falla para TODAS las personas.
-- Reproducido contra Postgres local el 2026-08-02: las 8 filas del periodo
-- abierto violan chk_foto_cuadra.
--
-- POR QUÉ. La 0096 escribió el candado con la aritmética de ese momento:
--
--     total = pago_base + monto_feriados + monto_plus
--           + asignacion_familiar + bonos - descuentos
--
-- Después la 0110 metió al total la MOVILIDAD (sumando) y el DESCUENTO DE
-- PENSIÓN (restando), y la 0120 la ASIGNACIÓN POR EDUCACIÓN (sumando). El
-- candado no se actualizó. Mientras los tres valían cero no se notaba —y por eso
-- los periodos ya pagados sí cuadraron—, pero Felipe encendió la movilidad el
-- 29/07 y la 0115 dejó la pensión vigente desde el periodo abierto. Desde ese
-- momento la diferencia es exactamente «movilidad + educación − pensión», y el
-- CHECK revienta con 23514.
--
-- LO QUE PASA HOY AL INTENTAR PAGAR, en orden: el insert falla, se revierte TODA
-- la transacción, no queda foto, el periodo sigue ABIERTO, la pantalla de Costos
-- nunca ve agosto, y el mensaje que se muestra es «Alguno de los datos no es
-- válido. Revisa las fechas y los números» — mandando a corregir datos que están
-- bien. «Recalcular y volver a pagar» falla por lo mismo, así que no hay salida.
-- Y mientras el periodo no cierre, los candados de marcaje no se activan: el
-- total sigue moviéndose después de que el dinero salió al banco.
--
-- QUÉ NO SE HACE, y es deliberado:
--   · NO se suelta el CHECK. Es justamente lo que impide guardar una foto que no
--     se sostiene, y esta auditoría lo encontró porque el candado hizo ruido.
--     Aflojarlo sería apagar el detector en vez de arreglar el reloj.
--   · NO se rellenan las filas viejas. La tabla es append-only por trigger, y no
--     hace falta: los periodos ya pagados se calcularon cuando movilidad,
--     educación y pensión valían cero, así que CERO ES SU VALOR VERDADERO, no un
--     relleno. Con las columnas nuevas en cero el candado nuevo se reduce
--     exactamente al viejo, que esas filas ya cumplían al insertarse.
--
-- EL ESSALUD VA COMO DATO, FUERA DE LA SUMA. Es aporte del empleador: no se le
-- descuenta a la persona ni se le paga, así que no puede entrar en un total que
-- representa lo que recibe. Se guarda porque la foto es el único registro de lo
-- que costó ese mes y sin él habría que recalcularlo, que es justo lo que la
-- 0096 vino a evitar.
--
-- CÓMO SE ESCRIBIÓ fn_planilla_congelar. Se extrajo del archivo de la 0096 con un
-- script y se le insertaron cuatro columnas en las dos listas del insert. Ni un
-- carácter más cambió, para que no haya diferencia por retipear.
--
-- CÓMO SE REVIERTE. Restaurar chk_foto_cuadra y fn_planilla_congelar desde la
-- 0096 y soltar las cuatro columnas. Pero eso vuelve a bloquear el pago.
-- ============================================================================


-- ── 1 · Las cuatro columnas ──────────────────────────────────────────────────
-- Default 0 a propósito: es el valor verdadero de los periodos ya pagados.
alter table planilla_pagada_detalle
  add column if not exists monto_movilidad   numeric(12,2) not null default 0;
alter table planilla_pagada_detalle
  add column if not exists monto_educacion   numeric(12,2) not null default 0;
alter table planilla_pagada_detalle
  add column if not exists descuento_pension numeric(12,2) not null default 0;
alter table planilla_pagada_detalle
  add column if not exists aporte_essalud    numeric(12,2) not null default 0;

comment on column planilla_pagada_detalle.descuento_pension is
  'Lo que se le retuvo para su fondo de pensión (AFP u ONP). RESTA del total: es plata que la persona no recibe en la mano, pero que tampoco se queda en CAYLA.';
comment on column planilla_pagada_detalle.aporte_essalud is
  'Aporte del empleador a EsSalud. NO entra en el total porque no se le paga ni se le descuenta a la persona: se guarda para que la foto sea el registro completo de lo que costó el mes.';


-- ── 2 · Antes de tocar el candado, comprobar que las filas viejas lo cumplen ──
-- Si alguna no cuadra, el ALTER fallaría con un mensaje opaco. Mejor decirlo
-- claro y por nombre, y decidir con el dato a la vista.
do $mig$
declare v_malas int; v_detalle text;
begin
  select count(*), string_agg(nombre || ' (periodo ' || periodo_id::text || ', v' || version || ')', '; ')
    into v_malas, v_detalle
  from planilla_pagada_detalle
  where total <> pago_base + monto_feriados + monto_plus + asignacion_familiar
                 + monto_movilidad + monto_educacion - descuento_pension
                 + bonos - descuentos;

  if v_malas = 0 then
    raise notice '0127 · las % filas de foto ya existentes cumplen el candado nuevo.',
      (select count(*) from planilla_pagada_detalle);
  else
    raise exception E'0127 · ABORTADO: % fila(s) de foto no cumplen el candado nuevo.\n%\n'
      'No se cambia nada. Revisar esas filas antes de seguir: puede que un pago viejo '
      'se haya guardado con una aritmetica que ya no se puede reconstruir.',
      v_malas, v_detalle;
  end if;
end
$mig$;


-- ── 3 · El candado, con la aritmética completa ───────────────────────────────
alter table planilla_pagada_detalle drop constraint if exists chk_foto_cuadra;
alter table planilla_pagada_detalle add constraint chk_foto_cuadra check (
  total = pago_base + monto_feriados + monto_plus + asignacion_familiar
        + monto_movilidad + monto_educacion
        - descuento_pension
        + bonos - descuentos
);


-- ── 4 · Y la función que la escribe, copiando los cuatro campos nuevos ───────
create or replace function fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid)
returns int
language plpgsql security definer set search_path = public as $fn$
declare
  v_per record;
  v_calc jsonb;
  v_ver int;
  v_n int;
begin
  -- `for update` sobre el periodo: dos personas pulsando «Pagado» a la vez no
  -- pueden calcular ambas la versión 1 y chocar contra la llave primaria.
  select * into v_per from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_calc := fn_planilla_calcular(v_per.fecha_ini, v_per.fecha_fin, p_periodo_id);

  select coalesce(max(version), 0) + 1 into v_ver
  from planilla_pagada_detalle where periodo_id = p_periodo_id;

  insert into planilla_pagada_detalle (
    periodo_id, persona_id, version, congelada_por, origen,
    nombre, sede_codigo, area_codigo, rango, salario_ref,
    horas_mes, dias_trabajados,
    pago_base, monto_feriados, monto_plus, asignacion_familiar,
    bonos, descuentos,
    monto_movilidad, monto_educacion, descuento_pension, aporte_essalud,   -- CAMBIO 0127
    total,
    provision_gratificacion, provision_cts, provision_vacaciones, provision_total,
    fila
  )
  select
    p_periodo_id,
    (f->>'persona_id')::uuid,
    v_ver,
    p_autor,
    p_origen,
    f->>'nombre',
    f->>'sede',
    pe.funcion,
    f->>'rango',
    (f->>'salario_ref')::numeric,
    coalesce((f->>'horas_mes')::numeric, 0),
    coalesce((f->>'dias_trabajados')::int, 0),
    coalesce((f->>'pago_base')::numeric, 0),
    coalesce((f->>'monto_feriados')::numeric, 0),
    coalesce((f->>'monto_plus')::numeric, 0),
    coalesce((f->>'asignacion_familiar')::numeric, 0),
    coalesce((f->>'bonos')::numeric, 0),
    coalesce((f->>'descuentos')::numeric, 0),
    -- CAMBIO 0127 — los tres conceptos que entraron al total en la 0110 y la
    -- 0120, mas el EsSalud como dato. Sin esto la foto no puede cuadrar.
    coalesce((f->>'monto_movilidad')::numeric, 0),
    coalesce((f->>'monto_educacion')::numeric, 0),
    coalesce((f->>'descuento_afp')::numeric, 0),
    coalesce((f->>'aporte_essalud')::numeric, 0),
    coalesce((f->>'total')::numeric, 0),
    coalesce((f->>'provision_gratificacion')::numeric, 0),
    coalesce((f->>'provision_cts')::numeric, 0),
    coalesce((f->>'provision_vacaciones')::numeric, 0),
    coalesce((f->>'provision_total')::numeric, 0),
    f
  from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
  left join personas pe on pe.id = (f->>'persona_id')::uuid;

  get diagnostics v_n = row_count;
  return v_n;
end;
$fn$;

-- Los grants se repiten porque «create or replace» no los pierde, pero dejarlos
-- escritos hace que este archivo se sostenga sobre una base reconstruida.
revoke all     on function fn_planilla_congelar(uuid, text, uuid) from public, anon, authenticated;
grant  execute on function fn_planilla_congelar(uuid, text, uuid) to service_role;


insert into migraciones_aplicadas (numero, nombre)
values (127, 'la_foto_del_pago_vuelve_a_cuadrar')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
