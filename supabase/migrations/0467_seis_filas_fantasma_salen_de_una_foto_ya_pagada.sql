-- ============================================================================
-- 0467 · seis filas fantasma salen de una foto ya pagada
-- ============================================================================
-- QUÉ PROMETE
--
--   Borrar EXACTAMENTE seis filas de `planilla_pagada_detalle` — las de
--   Geison Alcantára y Pamela Burgos en las fotos ya pagadas del grupo
--   «planilla» de julio y agosto de 2026 — y ninguna otra. No recalcula, no
--   toca a nadie más, no cambia ni un centavo de lo que ya se le pagó al
--   resto del equipo.
--
-- EL DEFECTO
--
--   El 2026-09-03, entre las 20:37 y las 22:27 UTC, alguien reabrió y volvió
--   a pagar el grupo «planilla» de julio (2026-06-28→2026-07-28, versiones 4
--   y 5) y de agosto (2026-07-29→2026-08-28, versión 2) — probablemente por
--   una corrección real, sin relación con esto. Geison y Pamela habían
--   ingresado ESE MISMO DÍA (`fecha_ingreso = 2026-09-03`), y el cálculo en
--   vivo de ese momento —antes de la 0463— los barrió como fila fantasma de
--   0 horas y salario nulo, exactamente el bug que la 0463 cerró para el
--   cálculo EN VIVO. Pero `fn_proyeccion_periodo` (0313/0323) lee la FOTO
--   congelada para un grupo ya pagado, no recalcula, así que la 0463 no la
--   toca: el bug quedó horneado dentro de esas dos fotos, para siempre,
--   hasta que alguien lo saque a mano.
--
--   Reportado por Felipe el 2026-09-15, viéndolos aparecer en `/admin/planilla`
--   con «Sin salario», 0 h, en un periodo donde ni siquiera existían.
--
-- QUÉ ASUME
--
--   · `planilla_pagada_detalle` es append-only A PROPÓSITO (0096): un trigger
--     rechaza cualquier `update`/`delete`. Su propio mensaje de error dice el
--     camino oficial — reabrir con `fn_revertir_pago` y volver a pagar con
--     `fn_repagar_periodo` — pero los dos operan sobre el GRUPO ENTERO del
--     periodo, no por persona. Usarlos aquí recalcularía a las ~30 personas
--     de «planilla» de julio y ~16 de agosto con las reglas de HOY —muchas
--     con diferencias de cientos de soles frente a lo que de verdad se les
--     pagó—, que es exactamente el daño que se quiere evitar. Medido antes de
--     decidir esto: comparar el cálculo en vivo de hoy contra la foto de esos
--     dos periodos NO da coincidencia para casi nadie, porque la función de
--     planilla cambió con decenas de migraciones desde que se pagaron. Por
--     eso esta migración apaga el candado un instante, en vez de usar el
--     camino oficial.
--   · Las seis filas objetivo se verifican UNA POR UNA antes de borrar nada
--     (ver el bloque de comprobación abajo): mismo `persona_id`, mismo
--     `periodo_id`, misma `version`, y las tres con `total = 0.00`. Si algo
--     no calza —otra sesión ya las tocó, o los datos no son los auditados—,
--     la migración se detiene sin borrar una sola fila.
--   · No hace falta `correcciones_auditoria`: su `corregido_por` es
--     `not null` contra `personas(id)` y no hay una fila de esa tabla que
--     represente «quien pegó este SQL en el editor» de forma fiable. Mismo
--     motivo por el que la 0452 descartó esa tabla para un borrado que no es
--     de una persona sola — aquí el rastro es esta migración, que se lee como
--     documentación del negocio igual que todas las demás.
--
-- QUÉ NO HACE
--
--   · No toca ninguna versión ANTERIOR a la contaminación: la fila de agosto
--     de Geison y Pamela solo existe en la versión 2 (la 1, si existió, no
--     los traía) — no hay nada más viejo que limpiar ahí.
--   · No repaga ni reabre ningún periodo. `periodos_planilla` y
--     `periodo_grupo_pago` quedan exactamente como estaban: el grupo sigue
--     'pagado', con el mismo `pagado_at`. Solo desaparecen dos filas de
--     detalle que nunca debieron congelarse.
--   · No cambia ninguna cifra agregada: las seis filas valen S/0.00 cada una
--     (`total`, `pago_base`, `provision_total`, todo en cero), así que ningún
--     total ni costo del periodo se mueve al quitarlas — sencillamente
--     ninguna suma las contaba con nada distinto de cero.
--
-- CÓMO SE REVIERTE
--   No hay vuelta atrás automática — es un `delete`, y `planilla_pagada_detalle`
--   no guarda lo borrado. Si hiciera falta deshacerlo, los seis valores están
--   en el cuerpo de esta migración (persona, periodo, version, `congelada_at`)
--   para reconstruirlas a mano con un `insert` idéntico.
-- ============================================================================

do $$
declare
  v_filas jsonb;
  v_n int;
begin
  select jsonb_agg(jsonb_build_object(
           'periodo_id', t.periodo_id, 'persona_id', t.persona_id, 'version', t.version
         )),
         count(*)
    into v_filas, v_n
    from (values
      ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '032f3ecd-83a4-450e-bad8-cce3c5f5b54d'::uuid, 4),  -- Geison · julio · v4
      ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '032f3ecd-83a4-450e-bad8-cce3c5f5b54d'::uuid, 5),  -- Geison · julio · v5
      ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '4890c3d6-4507-4ef7-af7e-c732f530a348'::uuid, 4),  -- Pamela · julio · v4
      ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '4890c3d6-4507-4ef7-af7e-c732f530a348'::uuid, 5),  -- Pamela · julio · v5
      ('e3a37f03-e542-4bb1-bd04-ed897a29a608'::uuid, '032f3ecd-83a4-450e-bad8-cce3c5f5b54d'::uuid, 2),  -- Geison · agosto · v2
      ('e3a37f03-e542-4bb1-bd04-ed897a29a608'::uuid, '4890c3d6-4507-4ef7-af7e-c732f530a348'::uuid, 2)   -- Pamela · agosto · v2
    ) as t(periodo_id, persona_id, version);

  -- ── El candado, antes de borrar nada ──────────────────────────────────────
  -- Verifica, una por una, que las seis filas objetivo existan, que tengan
  -- `grupo = 'planilla'` y que las seis valgan S/0.00. Si Postgres devuelve
  -- otro conteo o cualquiera de ellas dejó de ser cero, PARA: alguien más
  -- tocó estos datos entre que se auditó esto y que se pegó, y borrar a
  -- ciegas sobre una foto ya pagada es justo lo que esta migración existe
  -- para no hacer.
  if (select count(*) from planilla_pagada_detalle d, jsonb_array_elements(v_filas) f
       where d.periodo_id = (f->>'periodo_id')::uuid
         and d.persona_id = (f->>'persona_id')::uuid
         and d.version = (f->>'version')::int
         and d.grupo = 'planilla'
         and d.total = 0.00) <> 6 then
    raise exception '0467 · PARA. No se encontraron las seis filas fantasma esperadas, tal como se auditaron el 2026-09-15 (persona, periodo, version, total = 0.00 exacto). No se borró nada.';
  end if;

  raise notice '0467 · las seis filas verificadas, procediendo a borrarlas: %', v_filas;

  -- ── Apaga el candado de inmutabilidad, SOLO por esta transacción ─────────
  drop trigger if exists trg_foto_es_inmutable on planilla_pagada_detalle;

  delete from planilla_pagada_detalle d
   using jsonb_array_elements(v_filas) f
   where d.periodo_id = (f->>'periodo_id')::uuid
     and d.persona_id = (f->>'persona_id')::uuid
     and d.version = (f->>'version')::int;

  get diagnostics v_n = row_count;
  if v_n <> 6 then
    raise exception '0467 · PARA. Se esperaba borrar 6 filas y se borraron %. Revisa antes de continuar — el candado ya está apagado.', v_n;
  end if;

  -- ── Y lo vuelve a encender, en la misma transacción ───────────────────────
  create trigger trg_foto_es_inmutable
    before update or delete on planilla_pagada_detalle
    for each row execute function fn_trg_foto_es_inmutable();

  raise notice '0467 · seis filas fantasma borradas. Candado de inmutabilidad reactivado.';
end;
$$;

insert into migraciones_aplicadas (numero, nombre) values
  (467, 'seis_filas_fantasma_salen_de_una_foto_ya_pagada')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ─────────────────────────────────────────────────────────
-- Que no quede ninguna de las seis, que el candado siga en pie, y que a
-- nadie más de esos dos periodos-grupo se le haya tocado una sola fila.
select
  (select count(*) from planilla_pagada_detalle d, (values
     ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '032f3ecd-83a4-450e-bad8-cce3c5f5b54d'::uuid, 4),
     ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '032f3ecd-83a4-450e-bad8-cce3c5f5b54d'::uuid, 5),
     ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '4890c3d6-4507-4ef7-af7e-c732f530a348'::uuid, 4),
     ('3078a134-903e-4d4a-8015-767e46b100a6'::uuid, '4890c3d6-4507-4ef7-af7e-c732f530a348'::uuid, 5),
     ('e3a37f03-e542-4bb1-bd04-ed897a29a608'::uuid, '032f3ecd-83a4-450e-bad8-cce3c5f5b54d'::uuid, 2),
     ('e3a37f03-e542-4bb1-bd04-ed897a29a608'::uuid, '4890c3d6-4507-4ef7-af7e-c732f530a348'::uuid, 2)
   ) as t(periodo_id, persona_id, version)
   where d.periodo_id = t.periodo_id and d.persona_id = t.persona_id and d.version = t.version
  ) = 0                                                                          as ya_no_quedan,
  (select count(*) from pg_trigger where tgname = 'trg_foto_es_inmutable'
     and tgrelid = 'planilla_pagada_detalle'::regclass and not tgisinternal) = 1 as candado_reactivado,
  (select count(*) from planilla_pagada_detalle
    where periodo_id in ('3078a134-903e-4d4a-8015-767e46b100a6','e3a37f03-e542-4bb1-bd04-ed897a29a608')
      and grupo = 'planilla') as filas_que_quedan_en_esos_dos_periodos_grupo;
