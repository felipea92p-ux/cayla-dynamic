-- ============================================================================
-- 0558 · QUIEN LA 0554 PASÓ A PLANILLA SIN CONTRATO VUELVE A PRESELECCIÓN  (ESTA MUEVE PLATA)
-- ============================================================================
--
-- QUÉ PROMETE
--   Toda persona ACTIVA que la 0554 pasó de «prueba» a «planilla» y que todavía
--   no tiene ningún contrato firmado vuelve al vínculo `prueba` —en pantalla se
--   llama «preselección»—, con su preselección abierta desde su fecha de ingreso
--   (no desde hoy). Desde ese momento se paga como se pagaba antes de la 0554:
--     · sin aporte de EsSalud (0484),
--     · sin asignación familiar,
--     · sin beneficios (0085): no devenga gratificación, CTS ni vacaciones.
--   Las horas que se pagan son las mismas: cambia lo que se suma, no lo trabajado.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-27)
--   «Antes, para los nuevos colaboradores, se ponía de prueba y no se les pagaba
--   EsSalud: volvamos a eso. Todo el apartado de prueba se llamará preselección.»
--   Revierte la 0554 para quienes mueve; el resto de la reversión (pantallas,
--   Parámetros) vive en el código y en la 0559.
--
-- ⚠ LO QUE HAY QUE SABER ANTES DE PEGAR (ya lo dejó dicho la 0554, y sigue siendo así)
--   «Prueba» sin alta y sin contrato es la infracción muy grave del num. 25.20
--   del RLGIT, y no pagar EsSalud a quien trabaja es lo que la 0484 aceptó como
--   riesgo (Felipe, 2026-09-27). Esta migración no lo decide: devuelve lo que
--   Felipe pidió. La defensa que ya estaba escrita sigue siendo la misma: que la
--   preselección dure pocos días y termine en contrato o en baja.
--
-- ⚠ EL PERIODO ABIERTO CIERRA EL 28/10
--   Los totales proyectados del periodo 29/09–28/10 de estas personas cambian en
--   cuanto se pega (pierden el EsSalud y la asignación). Conviene pegarla ANTES del
--   cierre, no después: un periodo pagado está congelado y no se recalcula.
--
-- QUÉ ASUME
--   · La 0536 pegada: existen `pruebas` y el trigger `trg_pruebas_vinculo`, que
--     abre la fila de preselección en cuanto alguien pasa a `prueba`.
--   · La 0554 pegada: es la que las movió, y dejó cerrada su prueba como
--     `contratada` el 26/10 (hora de Lima). Eso es lo que las identifica.
--
-- A QUIÉN MUEVE (y a quién NO)
--   Mueve a quien cumple las cuatro: activa, vínculo `planilla`, no es cuenta de
--   servicio, y su prueba se cerró como `contratada` el 26/10 SIN que exista un
--   contrato firmado y vigente. Esa última condición separa a las que la 0554
--   pasó a planilla de quien fue a planilla legítimamente firmando su contrato
--   ese mismo día: a esas NO se las toca.
--   NO mueve: a quien ingresó a planilla después del 26/10 (por el alta nueva);
--   a una cesada; ni a una cuenta de servicio (0544). Si hace falta devolver a
--   alguna de esas, se hace desde Equipo con «Tipo de vínculo».
--
-- LA GUARDIA DE «A LO SUMO DOS»
--   La 0554 movió a dos personas, y esta migración se niega a mover a más de dos.
--   Si la consulta (1) de abajo devuelve más, algo no es lo que se midió el
--   26/10: se frena y se mira, en vez de mover a quien nadie nombró.
--
-- QUÉ NO HACE
--   · NO TOCA NINGUNA FUNCIÓN DE PAGO. Ni una línea de `fn_planilla_calcular*`:
--     solo cambia un dato (`personas.tipo_vinculo`) que esas funciones ya leen.
--     Por eso no hay md5 de planilla que pedir a producción.
--   · NO REVIERTE LA 0555. Quien se retira en preselección sigue cobrando lo que
--     trabajó (sin asignación familiar y sin EsSalud): Mariel Sarmiento y Noelia
--     Ibarcena aparecen en la planilla de este periodo. Volver a retener lo
--     trabajado es otra decisión, y la ley no la respalda (0555).
--   · NO DEJA RASTRO EN `correcciones_auditoria`: esa tabla exige quién cambió, y
--     una migración no es nadie (0508: solo la escriben las funciones). El rastro
--     es esta migración, su fila en `migraciones_aplicadas` y la fila de
--     `pruebas` que se abre.
--
-- CÓMO SE REVIERTE
--   Persona por persona, desde Equipo («Tipo de vínculo» → Planilla), o en la base:
--     update personas set tipo_vinculo = 'planilla' where id = '…';
--   (el trigger cierra la preselección abierta como `contratada`).
--
-- ANTES DE PEGAR (solo lectura; devuelve lo que salga)
--   (1) ¿A quién mueve? Debe salir a lo sumo dos filas, y las conoces por nombre:
--         select p.nombres, p.apellidos, p.fecha_ingreso, p.con_hijos, s.codigo as sede
--           from personas p
--           left join sedes s on s.id = p.sede_base_id
--          where p.estado = 'activo' and p.tipo_vinculo = 'planilla'
--            and not coalesce(p.cuenta_de_servicio, false)
--            and exists (select 1 from pruebas pr
--                         where pr.persona_id = p.id and pr.resultado = 'contratada'
--                           and pr.cerrada_at >= timestamptz '2026-10-26 00:00:00-05'
--                           and pr.cerrada_at <  timestamptz '2026-10-27 00:00:00-05')
--            and not exists (select 1 from contratos_generados c
--                             where c.persona_id = p.id and c.fecha_firma is not null
--                               and c.anulado_at is null)
--          order by p.fecha_ingreso;
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 450.
-- ============================================================================

-- ── Guardia: la 0536 y la 0554 tienen que estar ─────────────────────────────
do $guardia$
begin
  if to_regclass('public.pruebas') is null
     or to_regclass('public.contratos_generados') is null then
    raise exception 'PARA. Falta la 0536 (no existe la tabla pruebas) o contratos_generados. Pega primero la 0536.';
  end if;
  if not exists (select 1 from migraciones_aplicadas where numero = 554) then
    raise exception 'PARA. La 0554 no está pegada: no hay nadie que devolver. Pega primero la 0554 si de verdad se quiere (y luego esta).';
  end if;
end
$guardia$;

-- ── Quién se mueve, y se mueve ───────────────────────────────────────────────
-- Todo en un bloque: o se mueven las dos y su preselección queda abierta desde su
-- ingreso, o no pasa nada. Repegar es seguro: la segunda vez no encuentra a nadie
-- (ya no son «planilla»).
do $volver$
declare
  v_ids uuid[];
  v_n   integer;
begin
  select coalesce(array_agg(p.id), '{}'::uuid[]) into v_ids
    from personas p
   where p.estado = 'activo'
     and p.tipo_vinculo = 'planilla'
     and not coalesce(p.cuenta_de_servicio, false)
     and exists (select 1 from pruebas pr
                  where pr.persona_id = p.id
                    and pr.resultado = 'contratada'
                    and pr.cerrada_at >= timestamptz '2026-10-26 00:00:00-05'
                    and pr.cerrada_at <  timestamptz '2026-10-27 00:00:00-05')
     and not exists (select 1 from contratos_generados c
                      where c.persona_id = p.id
                        and c.fecha_firma is not null
                        and c.anulado_at is null);

  v_n := coalesce(cardinality(v_ids), 0);

  if v_n > 2 then
    raise exception 'PARA. Esta migración devuelve a preselección a lo sumo a las 2 personas que movió la 0554, y la consulta encontró %. No se mueve a nadie: corre la consulta (1) del encabezado y revisa quién es quién.', v_n;
  end if;

  if v_n > 0 then
    update personas set tipo_vinculo = 'prueba' where id = any(v_ids);

    -- El trigger de la 0536 abrió su preselección con inicio = hoy; empezó el día
    -- en que ingresó, y desde ahí se cuentan sus días trabajados.
    update pruebas pr
       set inicio = coalesce(p.fecha_ingreso, pr.inicio)
      from personas p
     where pr.persona_id = p.id
       and pr.persona_id = any(v_ids)
       and pr.resultado = 'en_curso';
  end if;
end
$volver$;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (558, 'quien_paso_a_planilla_sin_contrato_vuelve_a_preseleccion')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: 0 · «558 · quien_paso_a_planilla_sin_contrato_vuelve_a_preseleccion»
-- y la lista de abajo: quienes están en preselección activa, con su inicio.
select
  (select count(*) from personas p
    where p.estado = 'activo' and p.tipo_vinculo = 'planilla'
      and not coalesce(p.cuenta_de_servicio, false)
      and exists (select 1 from pruebas pr
                   where pr.persona_id = p.id and pr.resultado = 'contratada'
                     and pr.cerrada_at >= timestamptz '2026-10-26 00:00:00-05'
                     and pr.cerrada_at <  timestamptz '2026-10-27 00:00:00-05')
      and not exists (select 1 from contratos_generados c
                       where c.persona_id = p.id and c.fecha_firma is not null
                         and c.anulado_at is null))                              as quedan_por_devolver,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 558) as registro;

select p.nombres, p.apellidos, p.fecha_ingreso, pr.inicio as preseleccion_desde, p.tipo_vinculo
  from personas p
  join pruebas pr on pr.persona_id = p.id and pr.resultado = 'en_curso'
 where p.estado = 'activo' and p.tipo_vinculo = 'prueba'
 order by p.fecha_ingreso;
