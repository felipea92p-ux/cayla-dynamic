-- ============================================================================
-- 0201 — La foto del pago aprende el sobretiempo, y por eso el periodo se puede
--        cerrar
--
-- QUÉ DESBLOQUEA. «Marcar como PAGADO» va a fallar —para TODAS las personas del
-- periodo, no solo para quien hizo sobretiempo— en cuanto alguien pase de 48 h
-- en un ciclo de siete días. Hoy todavía no ha pasado; el 28/08 se paga.
--
-- POR QUÉ. Es la 0127 otra vez, con una causa nueva. Aquel día el candado se
-- había quedado atrás de la movilidad, la educación y la pensión. Hoy se quedó
-- atrás del sobretiempo:
--
--     chk_foto_cuadra (0127) exige
--         total = pago_base + monto_feriados + monto_plus + asignacion_familiar
--               + monto_movilidad + monto_educacion - descuento_pension
--               + bonos - descuentos
--
--     y fn_planilla_calcular (0199, línea 519) le suma al total un término más:
--         + round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2)
--
-- Ese término lo metió la 0185, que es cuando el sobretiempo empezó a pagarse
-- solo. El candado no se actualizó, y no hay columna donde guardar el monto: la
-- foto no tiene dónde poner la diferencia, así que no puede cuadrar.
--
-- POR QUÉ NO HA REVENTADO TODAVÍA, que es lo que engaña. El retroactivo de
-- jun-jul (S/100.03 en 8 personas) se registró como MOVIMIENTO, y los
-- movimientos entran por `bonos`, que el candado sí conoce. El sobretiempo
-- nativo de la 0185 no ha tenido ocasión de aparecer aún. El primer ciclo de
-- 56 h lo estrena.
--
-- LO QUE PASA CUANDO REVIENTE, en orden —y está escrito en la 0127 porque ya
-- pasó—: el insert falla con 23514, se revierte TODA la transacción, no queda
-- foto, el periodo sigue ABIERTO, Costos nunca ve el mes, y la pantalla muestra
-- «Alguno de los datos no es válido. Revisa las fechas y los números»,
-- mandando a corregir datos que están bien. Y mientras el periodo no cierre,
-- los candados de marcaje no se activan: el total se sigue moviendo después de
-- que el dinero salió al banco.
--
-- QUÉ NO SE HACE, y es deliberado:
--   · NO se suelta el CHECK. Es lo que impide guardar una foto que no se
--     sostiene, y es lo que hizo ruido para que esto se encontrara. Aflojarlo
--     sería apagar el detector en vez de arreglar el reloj. Mismo argumento que
--     la 0127, que también pudo tomar el atajo y no lo tomó.
--   · NO se rellenan las filas viejas, y no hace falta: CERO ES SU VALOR
--     VERDADERO. Antes de la 0185 el sobretiempo no se pagaba solo, y después
--     de la 0185 una fila con sobretiempo no habría podido insertarse —el
--     candado la habría rechazado—, así que no existe ninguna. Con la columna
--     nueva en cero el candado nuevo se reduce exactamente al viejo, que esas
--     filas ya cumplían al insertarse. La sección 2 lo comprueba igual antes de
--     tocar nada.
--   · NO se agrega columna para las HORAS de sobretiempo. Ya viajan en `fila`
--     ('horas_sobretiempo', 'sobretiempo_desde', 'sobretiempo_hasta', 0199:586).
--     La 0127 sí le dio columna propia al EsSalud, pero porque la pantalla de
--     Costos lo consulta; a las horas no las consulta nadie todavía. Cuando
--     alguna lo necesite, se agrega entonces y se sabrá para qué.
--
-- QUÉ ASUME. Que el término del total y el valor de la clave 'monto_sobretiempo'
-- son la MISMA expresión, carácter por carácter, en fn_planilla_calcular —
-- ambos `round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2)`.
-- Si algún día divergen, el candado volverá a reventar, y eso es lo correcto:
-- es su trabajo.
--
-- CÓMO SE ESCRIBIÓ fn_planilla_congelar. Se partió del cuerpo de la 0134 —la
-- VIGENTE según ./scripts/donde-vive.sh, md5 8c07866249e413c2b76bb7f5a75b47da—
-- y se le insertó una columna en cada una de las dos listas del insert. Ni un
-- carácter más cambió. Copiarla de la 0127 habría revertido en silencio la
-- provisión de la bonificación extraordinaria de la Ley 30334.
--
-- CÓMO SE REVIERTE. Restaurar chk_foto_cuadra desde la 0127 y
-- fn_planilla_congelar desde la 0134, y soltar la columna. Pero eso vuelve a
-- bloquear el pago en cuanto alguien haga sobretiempo.
-- ============================================================================


-- ── 1 · La columna ───────────────────────────────────────────────────────────
-- Default 0 a propósito: es el valor verdadero de las fotos ya guardadas, no un
-- relleno. El argumento completo está arriba.
alter table planilla_pagada_detalle
  add column if not exists monto_sobretiempo numeric(12,2) not null default 0;

comment on column planilla_pagada_detalle.monto_sobretiempo is
  'El RECARGO por sobretiempo (25 % / 35 %), no la hora completa: las horas ya están dentro de pago_base. SUMA al total. Las horas, el desde y el hasta viajan en la columna `fila`. Se mide contra 48 h semanales en ciclos de siete días que no se solapan, nunca contra 8 h diarias — ver la 0185.';


-- ── 2 · Antes de tocar el candado, comprobar que las filas viejas lo cumplen ──
-- Si alguna no cuadra, el ALTER fallaría con un mensaje opaco. Mejor decirlo
-- claro y por nombre, y decidir con el dato a la vista. Copiado de la 0127,
-- que lo hizo por la misma razón.
do $mig$
declare v_malas int; v_detalle text;
begin
  select count(*), string_agg(nombre || ' (periodo ' || periodo_id::text || ', v' || version || ')', '; ')
    into v_malas, v_detalle
  from planilla_pagada_detalle
  where total <> pago_base + monto_feriados + monto_plus + asignacion_familiar
                 + monto_movilidad + monto_educacion - descuento_pension
                 + monto_sobretiempo
                 + bonos - descuentos;

  if v_malas = 0 then
    raise notice '0201 · las % filas de foto ya existentes cumplen el candado nuevo.',
      (select count(*) from planilla_pagada_detalle);
  else
    raise exception E'0201 · ABORTADO: % fila(s) de foto no cumplen el candado nuevo.\n%\n'
      'No se cambia nada. Revisar esas filas antes de seguir: si alguna trae sobretiempo '
      'guardado por otra via, su monto hay que escribirlo en la columna nueva antes de '
      'poner el candado.',
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
        + monto_sobretiempo
        + bonos - descuentos
);


-- ── 4 · Y la función que la escribe, copiando el campo nuevo ─────────────────
-- Partida del cuerpo de la 0134 (la vigente). Un campo en cada lista del insert.
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
    monto_sobretiempo,                                                     -- CAMBIO 0201
    total,
    provision_gratificacion, provision_bonif_extraordinaria, provision_cts, provision_vacaciones, provision_total,   -- CAMBIO 0134
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
    -- CAMBIO 0201 — el recargo del sobretiempo, que la 0185 metio al total.
    -- Mismo motivo que la linea de arriba: sin columna, la foto no cuadra.
    coalesce((f->>'monto_sobretiempo')::numeric, 0),
    coalesce((f->>'total')::numeric, 0),
    coalesce((f->>'provision_gratificacion')::numeric, 0),
    coalesce((f->>'provision_bonif_extraordinaria')::numeric, 0),   -- CAMBIO 0134
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
values (201, 'la_foto_del_pago_aprende_el_sobretiempo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── 5 · Comprobación posterior ───────────────────────────────────────────────
-- Que la migración diga en voz alta que quedó como prometió. Se pega a mano, y
-- una mano se equivoca: sin esto, un `drop constraint if exists` que corriera
-- solo dejaría la tabla SIN candado y en silencio, que es peor que el bug.
do $mig$
declare v_def text; v_col int;
begin
  select pg_get_constraintdef(c.oid) into v_def
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  where t.relname = 'planilla_pagada_detalle' and c.conname = 'chk_foto_cuadra';

  if v_def is null then
    raise exception '0201 · el candado chk_foto_cuadra NO existe. La tabla quedo sin proteccion.';
  end if;
  if v_def not like '%monto_sobretiempo%' then
    raise exception '0201 · chk_foto_cuadra existe pero NO conoce el sobretiempo: %', v_def;
  end if;

  select count(*) into v_col
  from information_schema.columns
  where table_name = 'planilla_pagada_detalle' and column_name = 'monto_sobretiempo';
  if v_col <> 1 then
    raise exception '0201 · la columna monto_sobretiempo no quedo creada.';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_congelar'
      and p.prosrc like '%monto_sobretiempo%'
  ) then
    raise exception '0201 · fn_planilla_congelar no escribe monto_sobretiempo: el candado la va a rechazar en el proximo cierre.';
  end if;

  raise notice '0201 · listo. Candado, columna y funcion conocen el sobretiempo.';
end
$mig$;
