-- ============================================================================
-- 0561 · LA PRESELECCIÓN NO TIENE SEGURO, Y VUELVE A ELLA QUIEN QUEDÓ COMO RXH  (ESTA MUEVE PLATA)
-- ============================================================================
--
-- QUÉ PROMETE (dos cosas, en este orden, y el orden importa)
--   1. En Seguros, quien está en preselección (vínculo `prueba`) deja de caer en
--      EsSalud: `seguros_tipos.essalud.aplica_a_vinculos` pasa de {planilla, prueba}
--      a {planilla}. Desde ahí la preselección es, para Seguros, lo mismo que los
--      honorarios: «Sin seguro (no aplica)», sin póliza, sin «confirmar el alta en
--      EsSalud» y sin nada pendiente.
--   2. Quien la 0554 pasó a planilla sin contrato y después quedó como RxH vuelve al
--      vínculo `prueba`, con su preselección abierta desde su ingreso. Es lo que
--      la 0558 quiso hacer y no encontró: la 0558 buscaba solo en `planilla`, y las
--      dos personas ya estaban en `rxh` (medido en producción el 2026-10-27).
--      Esta migración busca en `planilla` y en `rxh`.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-27)
--   «Los de prueba quedan como antes: no tienen seguro, no tienen beneficios, solo
--   sueldo. Seguros debe seguir la lógica: no deben tener nada, ni póliza ni nada.»
--   «Lo que sí tienen aparte de su sueldo es la movilidad asistida.»
--   Y sobre las dos personas: «podría ir a Tipo de vínculo y ponerles de prueba y
--   por lo tanto les quitaría que están contratados, RxH, etc.».
--
-- POR QUÉ PRIMERO LO DE SEGUROS
--   Hay un disparador que escucha el cambio de vínculo y anota en `seguros_cambios`
--   cuando el seguro principal de la persona se mueve (0528). Mientras `prueba`
--   siga cayendo en EsSalud, pasar a alguien de RxH a preselección anotaría un
--   «alta en EsSalud» pendiente de confirmar con el contador: justo lo que Felipe
--   dice que no existe. Con el orden de abajo, RxH → preselección no mueve nada
--   (los dos son «sin seguro») y no deja cambio.
--
-- ⚠ LO QUE CAMBIA EN LA PLATA (medido con las mismas horas, en un Postgres clon,
--   con la tarifa de movilidad de S/ 10 por día y régimen ONP)
--   RxH → preselección, 6 días de 6,5 h (con hijos) y 4 días de 6,5 h:
--     · lo que se paga por lo trabajado NO cambia;
--     · SE SUMA la movilidad asistida: la tarifa de su sede por cada día que ASISTIÓ
--       —provincia S/ 10, Lima S/ 12 (parametros_laborales, 0142); el día que no asistió
--       no cuenta—. Con S/ 10: S/ 60,00 por 6 días y S/ 40,00 por 4. El RxH no la recibe
--       porque la planilla la da a quien está en planilla, y la preselección lo está. Si
--       la declaración de ruta se exige y no la tiene firmada, no se suma (0159): la
--       boleta lo dice;
--     · se les DESCUENTA pensión, por la misma razón: con ONP, 13 % (S/ 31,98 y
--       S/ 21,32). Con otro régimen es lo que corresponda, y sin régimen cargado no se
--       descuenta nada;
--     · el EsSalud y la asignación familiar siguen en cero (aunque tenga hijos);
--     · total: S/ 246,00 → S/ 274,02 y S/ 164,00 → S/ 182,68;
--     · quien siempre fue planilla cobra exactamente igual.
--   Es lo que se hacía con la preselección antes de la 0554 («como antes»): sueldo y
--   movilidad asistida, sin seguro ni beneficios (Felipe, 2026-10-27).
--
-- ⚠ EL PERIODO ABIERTO CIERRA EL 28/10
--   Conviene pegarla ANTES del cierre: un periodo pagado está congelado y no se
--   recalcula.
--
-- QUÉ ASUME
--   · La 0528 pegada (existen `seguros_tipos` y el disparador de vínculo).
--   · La 0536 pegada (existe `pruebas` y su disparador) y la 0554 pegada, que dejó
--     cerrada la prueba de estas personas como `contratada` el 26/10 (hora de Lima).
--
-- A QUIÉN MUEVE (y a quién NO)
--   Mueve a quien cumple las cuatro: activa, vínculo `planilla` o `rxh`, no es
--   cuenta de servicio, y su prueba se cerró como `contratada` el 26/10 SIN que
--   exista un contrato firmado y vigente. NO mueve a quien ingresó después del
--   26/10, a una cesada, ni a una cuenta de servicio.
--
-- LA GUARDIA DE «A LO SUMO DOS»
--   La 0554 movió a dos personas, y esta migración se niega a mover a más de dos.
--   Si la consulta (1) de abajo devuelve más, algo no es lo que se midió: se frena
--   y se mira, en vez de mover a quien nadie nombró. La guardia corre ANTES de
--   tocar Seguros: o pasa todo, o no pasa nada.
--
-- QUÉ NO HACE
--   · NO TOCA NINGUNA FUNCIÓN DE PAGO. Ni una línea de `fn_planilla_calcular*`:
--     cambia un dato (`personas.tipo_vinculo`) que esas funciones ya leen. No hay
--     md5 de planilla que pedir a producción.
--   · NO TOCA `personas.en_planilla` (columna generada que usan el pago, la pensión
--     y el resto del sistema): la preselección sigue en planilla para pagarse. Por
--     eso el atajo «las de planilla» del formulario de una póliza colectiva todavía
--     las marca; quien registre una póliza lo ve en la lista y la desmarca.
--   · NO REVIERTE LA 0555: quien se retira en preselección cobra lo trabajado.
--   · NO TOCA a nadie que DO ya haya asignado a mano a un seguro (`seguros_asignaciones`).
--   · NO DEJA RASTRO EN `correcciones_auditoria`: esa tabla exige quién cambió y una
--     migración no es nadie (0508). El rastro es esta migración, su fila en
--     `migraciones_aplicadas` y la fila de `pruebas` que se abre.
--
-- CÓMO SE REVIERTE
--   Seguros: update seguros_tipos set aplica_a_vinculos = array['planilla','prueba']
--             where clave = 'essalud';   (o editarlo en «Tipos de seguro»).
--   Personas: desde Equipo, «Tipo de vínculo», una por una; el disparador de la 0536
--             cierra la preselección abierta.
--
-- ANTES DE PEGAR (solo lectura; devuelve lo que salga)
--   (1) ¿A quién mueve? Debe salir a lo sumo dos filas, y las conoces por nombre:
--         select p.nombres, p.apellidos, p.tipo_vinculo, p.fecha_ingreso, s.codigo as sede
--           from personas p
--           left join sedes s on s.id = p.sede_base_id
--          where p.estado = 'activo' and p.tipo_vinculo in ('planilla', 'rxh')
--            and not coalesce(p.cuenta_de_servicio, false)
--            and exists (select 1 from pruebas pr
--                         where pr.persona_id = p.id and pr.resultado = 'contratada'
--                           and pr.cerrada_at >= timestamptz '2026-10-26 00:00:00-05'
--                           and pr.cerrada_at <  timestamptz '2026-10-27 00:00:00-05')
--            and not exists (select 1 from contratos_generados c
--                             where c.persona_id = p.id and c.fecha_firma is not null
--                               and c.anulado_at is null)
--          order by p.fecha_ingreso;
--   (2) ¿Quién está hoy en «Tipos de seguro» → EsSalud?
--         select aplica_a_vinculos from seguros_tipos where clave = 'essalud';
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   Los `select` del final, y la prueba pgTAP 452.
-- ============================================================================

-- ── Guardia: la 0528, la 0536 y la 0554 tienen que estar ────────────────────
do $guardia$
begin
  if to_regclass('public.seguros_tipos') is null then
    raise exception 'PARA. Falta la 0528 (Seguros): no existe seguros_tipos. Pega primero la 0528.';
  end if;
  if to_regclass('public.pruebas') is null or to_regclass('public.contratos_generados') is null then
    raise exception 'PARA. Falta la 0536 (no existe la tabla pruebas) o contratos_generados. Pega primero la 0536.';
  end if;
  if not exists (select 1 from migraciones_aplicadas where numero = 554) then
    raise exception 'PARA. La 0554 no está pegada: no hay nadie que devolver. Pega primero la 0554 si de verdad se quiere (y luego esta).';
  end if;
end
$guardia$;

-- ── Las dos cosas, en un solo bloque y en este orden ────────────────────────
do $preseleccion$
declare
  v_ids uuid[];
  v_n   integer;
begin
  -- A quién mueve: se cuenta ANTES de tocar nada, y si son más de dos no se toca nada.
  select coalesce(array_agg(p.id), '{}'::uuid[]) into v_ids
    from personas p
   where p.estado = 'activo'
     and p.tipo_vinculo in ('planilla', 'rxh')
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
    raise exception 'PARA. Esta migración devuelve a preselección a lo sumo a las 2 personas que movió la 0554, y la consulta encontró %. No se toca nada (ni Seguros): corre la consulta (1) del encabezado y revisa quién es quién.', v_n;
  end if;

  -- 1 · Seguros primero: la preselección deja de caer en EsSalud.
  update seguros_tipos
     set aplica_a_vinculos = array_remove(aplica_a_vinculos, 'prueba')
   where clave = 'essalud'
     and 'prueba' = any(aplica_a_vinculos);

  -- 2 · Después, las personas.
  if v_n > 0 then
    update personas set tipo_vinculo = 'prueba' where id = any(v_ids);

    -- El disparador de la 0536 abrió su preselección con inicio = hoy; empezó el día
    -- en que ingresó, y desde ahí se cuentan sus días trabajados.
    update pruebas pr
       set inicio = coalesce(p.fecha_ingreso, pr.inicio)
      from personas p
     where pr.persona_id = p.id
       and pr.persona_id = any(v_ids)
       and pr.resultado = 'en_curso';
  end if;
end
$preseleccion$;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (561, 'la_preseleccion_no_tiene_seguro_y_vuelve_quien_quedo_como_rxh')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: {planilla} · null · 0 · «561 · la_preseleccion_no_tiene_seguro_y_vuelve_…»
select
  (select aplica_a_vinculos from seguros_tipos where clave = 'essalud')           as essalud_aplica_a,
  fn_seguro_tipo_por_vinculo('prueba')                                            as seguro_de_la_preseleccion,
  (select count(*) from personas p
    where p.estado = 'activo' and p.tipo_vinculo in ('planilla', 'rxh')
      and not coalesce(p.cuenta_de_servicio, false)
      and exists (select 1 from pruebas pr
                   where pr.persona_id = p.id and pr.resultado = 'contratada'
                     and pr.cerrada_at >= timestamptz '2026-10-26 00:00:00-05'
                     and pr.cerrada_at <  timestamptz '2026-10-27 00:00:00-05')
      and not exists (select 1 from contratos_generados c
                       where c.persona_id = p.id and c.fecha_firma is not null
                         and c.anulado_at is null))                              as quedan_por_devolver,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 561) as registro;

-- Quienes están en preselección activa, con su inicio: deben salir las dos personas
-- (y nadie más, salvo quien ya estuviera).
select p.nombres, p.apellidos, p.fecha_ingreso, pr.inicio as preseleccion_desde, p.tipo_vinculo
  from personas p
  join pruebas pr on pr.persona_id = p.id and pr.resultado = 'en_curso'
 where p.estado = 'activo' and p.tipo_vinculo = 'prueba'
 order by p.fecha_ingreso;
