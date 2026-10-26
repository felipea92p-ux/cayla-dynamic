-- ============================================================================
-- 0496 — Un periodo con todo pagado deja de leerse como "pagado en parte"
-- ============================================================================
--
-- ---- QUÉ PROMETE ----
--
--   Que un periodo cuyos grupos CON GENTE REAL ya están todos pagados deje de
--   mostrarse como «Pagado en parte» y pase a «Pagado», sin volver a mover ni
--   un sol: es la MISMA comprobación que ya hace `fn_periodo_pagado` (0323) al
--   final de cada pago, re-evaluada ahora porque nadie va a volver a llamarla.
--
-- ---- EL PROBLEMA, MEDIDO EN PRODUCCIÓN EL 2026-09-28 ----
--
--   El periodo 29 ago → 27 sep (e813d970-85ec-4e12-9e29-74a08e1cf48c) tiene
--   sus cuatro grupos reales pagados —planilla, practicante, prueba, rxh— y
--   coinciden EXACTO con los grupos que hoy tienen gente. Aun así
--   `periodos_planilla.estado` sigue en 'abierto', y la pantalla lo lee como
--   «Pagado en parte» (`lecturaDelEstado`, revision.ts).
--
--   La causa es la 0490/0491: mientras el filtro de cuentas de servicio
--   estuvo roto (ver la 0495), las 6 estaciones de retail contaban como
--   filas del grupo 'no_trabajador' — con S/ 0, pero contaban. Nadie iba a
--   pagar ese grupo (no es gente real), así que el chequeo final de
--   `fn_periodo_pagado` —¿están pagados TODOS los grupos que tienen gente?—
--   nunca encontraba que sí. Ahora que la 0495 repuso el filtro, ese quinto
--   grupo ya no tiene a nadie — pero el chequeo solo se ejecuta como efecto
--   colateral de PAGAR un grupo, y los cuatro reales ya están pagados: nadie
--   va a volver a llamarlo por su cuenta.
--
--   No es un problema de dinero: cada candado del sistema (0444, 0380, 0442…)
--   ya mira `periodo_grupo_pago` POR GRUPO, no este campo agregado — así que
--   nada se pudo editar de más mientras el periodo se veía "a medias". Es
--   solo la etiqueta.
--
-- ---- QUÉ HACE ----
--
--   Repite, para TODO periodo 'abierto', exactamente la comprobación final de
--   `fn_periodo_pagado`: si los grupos con gente HOY (según
--   `fn_planilla_calcular_nucleo`, en vivo) están TODOS cubiertos por una
--   fila 'pagada' en `periodo_grupo_pago`, pasa `periodos_planilla.estado` a
--   'pagado'. Ningún grupo se marca, ninguna foto se toca, ningún sol se
--   mueve — es la misma condición, no una nueva.
--
--   Se llama a `fn_planilla_calcular_nucleo` y NO a `fn_planilla_calcular`
--   (la envoltura que usa `fn_periodo_pagado`): esa envoltura exige
--   `fn_es_admin_o_lider()`, que lee `auth.uid()` — y una migración pegada en
--   el SQL Editor corre sin sesión de usuario, igual que le pasó a Felipe al
--   probar el diagnóstico a mano. El núcleo se escribió A PROPÓSITO sin ese
--   candado (ver su propio encabezado, 0339): está pensado para que lo llame
--   otra función o, como acá, una migración.
--
--   General y no por id a propósito: si algún otro periodo quedó en la misma
--   situación (o vuelve a pasar por otra causa), esto lo destraba igual, sin
--   tener que escribir su UUID a mano.
--
-- ---- QUÉ NO TOCA ----
--
--   Un periodo con `grupos_pagados` vacío (ninguno pagado aún, como el de
--   octubre 2026 recién abierto) no cumple la condición y se queda igual.
--
-- ---- CÓMO SE REVIERTE ----
--
--   No hay nada que revertir en el esquema (no crea columnas ni funciones).
--   Si algún periodo se marcó por error, se reabre como cualquier otro:
--   `fn_periodo_pagado` de reversa (Revertir pago) desde la pantalla.
--
-- Idempotente: un periodo ya 'pagado' no vuelve a evaluarse.
-- ============================================================================

do $arreglo$
declare
  r record;
  v_grupos_con_gente text[];
  v_marcados int := 0;
begin
  for r in
    select pp.id, pp.fecha_ini, pp.fecha_fin
    from periodos_planilla pp
    where pp.estado <> 'pagado'
  loop
    select array_agg(distinct f->>'tipo_vinculo') into v_grupos_con_gente
    from jsonb_array_elements(
      coalesce(fn_planilla_calcular_nucleo(r.fecha_ini, r.fecha_fin, r.id)->'filas', '[]'::jsonb)
    ) f;

    -- Misma condición que el final de fn_periodo_pagado (0323): hay al menos
    -- un grupo con gente, y NINGUNO de ellos está sin una fila 'pagada'.
    if v_grupos_con_gente is not null and not exists (
      select 1 from unnest(v_grupos_con_gente) g(grupo)
       where not exists (
         select 1 from periodo_grupo_pago
          where periodo_id = r.id and grupo = g.grupo and estado = 'pagado'
       )
    ) then
      update periodos_planilla set estado = 'pagado', pagado_at = now() where id = r.id;
      v_marcados := v_marcados + 1;
      raise notice 'Periodo % → % pasó a pagado (todos sus grupos con gente ya lo estaban).', r.fecha_ini, r.fecha_fin;
    end if;
  end loop;
  raise notice '0496: % periodo(s) destrabado(s).', v_marcados;
end
$arreglo$;

insert into migraciones_aplicadas (numero, nombre)
values (496, 'un_periodo_con_todo_pagado_deja_de_leerse_como_a_medias')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ─────────────────────────────────────────────────────────
select id, fecha_ini, fecha_fin, estado, pagado_at
  from periodos_planilla
 order by fecha_ini desc
 limit 5;
