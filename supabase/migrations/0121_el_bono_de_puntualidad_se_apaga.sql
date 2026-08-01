-- ============================================================================
-- 0121 — El bono de puntualidad se apaga.
--
-- QUÉ HACE. Pone en cero el monto del bono de puntualidad que la 0034 dejó en
-- S/60 por periodo, y limpia las filas que ese bono ya haya generado en periodos
-- que todavía no están pagados.
--
-- POR QUÉ. Decisión de Felipe el 2026-08-01, junto con sacar de la boleta el
-- «Rendimiento Extraordinario» y el «Incentivo Variable por Metas». Los tres eran
-- conceptos variables que se acumulaban encima del sueldo, y la estructura
-- remunerativa que se acordó el 2026-07-31 los reemplaza con cuatro conceptos que
-- sí tienen amparo nombrado en el art. 19 del D.S. 001-97-TR: movilidad (inciso
-- e), educación (f), asignación por cumpleaños (g) y el sueldo declarado.
--
-- ── POR QUÉ BASTA CON PONER EL MONTO EN CERO ────────────────────────────────
--
-- Porque fn_calcular_bono_puntualidad ya tiene el guard adecuado:
--
--     if v_monto > 0 and v_puntuales > 0 then
--       insert into movimientos_planilla ...
--
-- Con el monto en cero no inserta nada, así que no aparecen filas de «Bono
-- puntualidad S/0.00» ensuciando las boletas. Y la función, antes de insertar,
-- borra las filas AUTO-generadas del periodo:
--
--     delete from movimientos_planilla
--      where periodo_id = ... and concepto = 'Bono puntualidad' and creado_por is null;
--
-- O sea que volver a calcular la planilla de un periodo abierto limpia sola lo que
-- había. Igual esta migración lo hace de una vez, para no depender de que alguien
-- vuelva a pulsar el botón.
--
-- ── LO QUE NO TOCA, Y ES A PROPÓSITO ────────────────────────────────────────
--
-- **No toca los periodos PAGADOS.** Si el bono se pagó en un periodo cerrado, ese
-- pago ocurrió y su rastro se queda. Borrarlo reescribiría un pago hecho, que es
-- justamente lo que la 0096 (la foto del pago) y la 0115 existen para impedir.
--
-- **No borra las filas creadas A MANO.** Solo las que tienen `creado_por is null`,
-- que son las que generó la función. Si alguien registró un bono de puntualidad a
-- mano, hubo una decisión detrás y no le corresponde a una migración deshacerla.
--
-- **No borra la función ni la clave de configuración.** Quedan ahí con el monto en
-- cero: si Felipe quiere volver a encenderlo, es un update y no hay que reescribir
-- lógica. Y el histórico de por qué existió queda legible en la 0034.
--
-- CÓMO SE REVIERTE:
--   update configuracion
--      set valor = jsonb_set(valor, '{monto}', '60'::jsonb)
--    where clave = 'bono_puntualidad';
-- ============================================================================

update configuracion
   set valor = jsonb_set(valor, '{monto}', '0'::jsonb),
       descripcion = 'APAGADO el 2026-08-01 por decisión de Felipe: monto en 0. La estructura '
                     'remunerativa acordada el 2026-07-31 lo reemplaza con conceptos que tienen '
                     'amparo nombrado en el art. 19 del D.S. 001-97-TR. Para volver a encenderlo, '
                     'poner un monto mayor a 0 — fn_calcular_bono_puntualidad ya tiene el guard.'
 where clave = 'bono_puntualidad';

-- Limpia lo que el bono haya generado en periodos que aún NO están pagados.
delete from movimientos_planilla m
 where m.concepto = 'Bono puntualidad'
   and m.creado_por is null
   and exists (
     select 1 from periodos_planilla p
      where p.id = m.periodo_id and p.estado <> 'pagado'
   );

insert into migraciones_aplicadas (numero, nombre)
values (121, 'el_bono_de_puntualidad_se_apaga')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_monto numeric;
  v_borradas int;
  v_pagadas int;
begin
  select (valor->>'monto')::numeric into v_monto
    from configuracion where clave = 'bono_puntualidad';

  select count(*) into v_pagadas
    from movimientos_planilla m
    join periodos_planilla p on p.id = m.periodo_id
   where m.concepto = 'Bono puntualidad' and p.estado = 'pagado';

  select count(*) into v_borradas
    from movimientos_planilla m
   where m.concepto = 'Bono puntualidad';

  raise notice '0121 · monto del bono de puntualidad: % (0 = apagado)', coalesce(v_monto, 0);
  raise notice '0121 · filas que quedan en total: %', v_borradas;
  raise notice '0121 · de esas, en periodos YA PAGADOS (no se tocan): %', v_pagadas;
  if v_borradas > v_pagadas then
    raise notice '0121 · OJO: quedan % fila(s) en periodos abiertos, creadas A MANO. No se borran: hubo una decisión detrás.', v_borradas - v_pagadas;
  end if;
end
$mig$;
