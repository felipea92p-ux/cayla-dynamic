-- ============================================================================
-- 0210 — La planilla ve la liquidación que ya se pagó
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la pantalla de Planilla pueda DECIR, junto a quien cesó a mitad de mes,
--   que esa persona ya cobró su liquidación: cuándo y cuánto. Nada más. No
--   excluye a nadie, no cambia ningún total y no escribe una sola fila.
--
-- QUÉ ASUME
--   La 0167: `liquidacion_pagada` guarda una copia congelada por persona, con
--   `monto_periodo` —el sueldo del mes que esa liquidación ya pagó— y su
--   `congelada_at`.
--
-- ── EL CASO REAL QUE LO PIDE ────────────────────────────────────────────────
--
-- Medido en producción el 2026-08-10. Hay DOS caminos por los que el sistema
-- registra un pago y no se hablan entre sí:
--
--   · el periodo completo   → fn_planilla_congelar, todo o nada
--   · la liquidación por cese → fn_liquidacion + 0167, persona a persona
--
-- Y la liquidación NO calcula un concepto aparte: llama a la propia planilla
-- con el rango que va del inicio del periodo a la fecha de cese (0164:103) y le
-- suma las truncas. O sea que el sueldo del mes está DENTRO de la liquidación.
--
-- `liquidacion_pagada` aparece en UN SOLO archivo de todo el repositorio —la
-- 0167 que la creó—. Ni fn_planilla_calcular, ni fn_planilla_congelar, ni la
-- pantalla la leen jamás. La etiqueta «ya no está» de la fila es puramente
-- visual.
--
-- Resultado medido: SEIS personas del periodo 28/06–28/07 tienen el mismo mes
-- registrado dos veces —S/1,145.87 en la foto del periodo, además de sus
-- liquidaciones—. Las seis dicen «primero el periodo, después la liquidación»:
-- el 28/07 se cerró el mes con ellas dentro, porque nada en pantalla avisó de
-- que ya habían cobrado.
--
-- ── POR QUÉ UN AVISO Y NO UN DESCUENTO AUTOMÁTICO ───────────────────────────
--
-- Porque la cifra de la liquidación HOY NO ES DE FIAR, y está medido: el pago
-- se divide entre `6.5 × días del rango` (0199:94-95) y la liquidación es la
-- única del sistema que pide un rango parcial, así que viene inflada entre 1.1×
-- y 3.1× según lo temprano que se cesara. Un sistema que descontara solo estaría
-- propagando ese número con la seguridad de una máquina.
--
-- Poner las dos cifras una al lado de la otra deja la decisión en quien paga.
-- Es la misma postura de la 0096 y la 0167: el sistema lo dice, no lo corrige
-- solo. (El divisor se arregla aparte, con su propia auditoría empírica.)
--
-- Y hay un motivo práctico: automatizarlo pondría un freno duro justo al cerrar
-- el mes. Si esa condición fallara una vez, el 28 no se podría pagar.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
--   · No arregla el dinero pagado de más. Eso es el divisor, y va aparte.
--   · No descuenta nada. El remedio sigue siendo el botón «Ya le pagué aparte»,
--     que registra el descuento con su fecha y deja rastro en la boleta.
--   · No toca fn_planilla_calcular, fn_planilla_congelar ni fn_proyeccion_periodo.
--
-- ── POR QUÉ SE FILTRA POR FECHA DE CESE Y NO POR «TIENE LIQUIDACIÓN» ────────
--
-- Quien cesó en un periodo ANTERIOR ya cobró el mes anterior: su liquidación no
-- se solapa con éste, y avisar de ella sería ruido. Solo importa cuando el cese
-- cae DENTRO del periodo que se está mirando, porque entonces —y solo entonces—
-- el mismo mes está en los dos sitios.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--   `create or replace`. Se puede pegar dos veces sin efecto distinto.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists fn_liquidaciones_del_periodo(uuid);
--   No hay dato que devolver: esta migración no escribe ninguno.
-- ============================================================================

-- ── La función ──────────────────────────────────────────────────────────────
-- Devuelve un objeto indexado por persona_id para que la pantalla busque por
-- clave en vez de recorrer una lista por cada fila. Vacío `{}` cuando no hay
-- nada que decir — y también cuando quien pregunta no tiene permiso, que es lo
-- que hace el `where` de abajo.
create or replace function fn_liquidaciones_del_periodo(p_periodo_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_object_agg(
      x.persona_id::text,
      jsonb_build_object(
        -- Lo que esa liquidación ya pagó POR ESTE MES. Es la cifra que se
        -- solapa con la planilla; el resto de la liquidación son truncas.
        'cobro_del_periodo', x.monto_periodo,
        'total_liquidacion', x.total,
        'pagada_el',         (x.congelada_at at time zone 'America/Lima')::date,
        'fecha_cese',        x.fecha_cese
      )
    ),
    '{}'::jsonb
  )
  from (
    -- Una liquidación puede tener varias versiones; manda la última, igual que
    -- en la pantalla de Liquidaciones.
    select distinct on (lp.persona_id)
           lp.persona_id, lp.monto_periodo, lp.total, lp.congelada_at, lp.fecha_cese
    from liquidacion_pagada lp
    join periodos_planilla per on per.id = p_periodo_id
    where lp.fecha_cese between per.fecha_ini and per.fecha_fin
    order by lp.persona_id, lp.version desc
  ) x
  -- `is true` y no `not (...)`: un null no pasa como autorizado. Estándar del
  -- repo desde la 0078.
  where fn_es_admin_o_lider() is true;
$$;

comment on function fn_liquidaciones_del_periodo(uuid) is
  'Quién de este periodo ya cobró su liquidación, con cuándo y cuánto. Solo lee; '
  'la pantalla de Planilla lo usa para avisar antes de cerrar el mes. Ver 0210.';

revoke execute on function fn_liquidaciones_del_periodo(uuid) from public, anon;
grant  execute on function fn_liquidaciones_del_periodo(uuid) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (210, 'la_planilla_ve_la_liquidacion_que_ya_se_pago')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── Comprobación posterior ──────────────────────────────────────────────────
-- Que la migración diga en voz alta que quedó como prometió. Se pega a mano, y
-- una mano se equivoca.
do $mig$
declare v_ok boolean;
begin
  select exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_liquidaciones_del_periodo'
  ) into v_ok;
  if not v_ok then
    raise exception '0210 · fn_liquidaciones_del_periodo no quedo creada.';
  end if;

  -- Que no la pueda llamar cualquiera. Es de solo lectura, pero devuelve cuánto
  -- cobró cada persona al irse.
  if has_function_privilege('anon', 'fn_liquidaciones_del_periodo(uuid)', 'execute') then
    raise exception '0210 · anon puede ejecutarla, y no debe.';
  end if;
  if not has_function_privilege('authenticated', 'fn_liquidaciones_del_periodo(uuid)', 'execute') then
    raise exception '0210 · authenticated NO puede ejecutarla, y la pantalla la necesita.';
  end if;

  raise notice '0210 · listo. La planilla ya puede preguntar quien cobro su liquidacion.';
end
$mig$;
