-- ============================================================================
-- 0554 · QUIEN FIGURABA COMO «PRUEBA» PASA A PLANILLA  (ESTA MUEVE PLATA)
-- ============================================================================
--
-- QUÉ PROMETE
--   Toda persona ACTIVA con vínculo «prueba» pasa a «planilla». Desde ese
--   momento es una persona más de la planilla, con su periodo de prueba de tres
--   meses corriendo desde su ingreso (`periodoDePrueba`, packages/shared).
--   Con eso se DEROGA, para quien hoy está de prueba, lo decidido el 2026-10-19
--   (0536 y 0537):
--     · «Se retiró» → no se le paga:        ya no hay quien quede en ese estado.
--     · «Prueba» sin EsSalud (0484):         EsSalud lo genera como a cualquiera.
--     · «Prueba» sin asignación familiar:    la cobra si tiene hijos.
--     · «Prueba» sin beneficios (0085):      devenga por mes cumplido, como todos.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-26: «sí, deroga»)
--   Quien trabaja se registra desde el primer día y se le paga lo trabajado,
--   siempre. Retener lo trabajado a quien se retira es una deuda remunerativa
--   (Constitución, art. 23) y una infracción grave por no pagar íntegra y
--   oportunamente (RLGIT, num. 24.4); la propia 0536 dejó registrada esa
--   objeción cuando se construyó. «Prueba» sin alta es, además, la infracción
--   muy grave del num. 25.20 del RLGIT. El periodo de prueba legal (art. 10 del
--   D.S. 003-97-TR) vive DENTRO del contrato: ver la 0553.
--
-- QUÉ ASUME
--   · La 0553 pegada (los «días de prueba» ya no son un parámetro y el aviso de
--     feriado ya mira la antigüedad, no el vínculo). Se comprueba abajo.
--   · La 0536 pegada: el trigger `trg_pruebas_vinculo` cierra la prueba abierta
--     de quien deja de ser «prueba» (resultado `contratada`). Esa fila es el
--     rastro de cuándo ocurrió.
--
-- LO QUE SE MIDIÓ ANTES DE ESCRIBIRLO (Postgres local con las 552 migraciones)
--   Una persona con hijos, sueldo de S/ 1 230, tres días de 6,5 h en el periodo
--   29/09–28/10, antes y después de este cambio: ver el PR. En resumen, cambia
--   exactamente lo que se quiso cambiar —asignación familiar, aporte EsSalud y
--   la pensión que se descuenta sobre esa asignación— y las horas pagadas son las
--   mismas. La gente que ya estaba en planilla cobra IGUAL.
--
-- QUÉ NO HACE
--   · NO TOCA NINGUNA FUNCIÓN DE PAGO. Ni una línea de `fn_planilla_calcular*`:
--     solo cambia un dato (`personas.tipo_vinculo`) que esas funciones ya leen.
--     Por eso no hay md5 de planilla que pedir a producción.
--   · NO TOCA A LAS INACTIVAS. Su historia ya está en `fecha_cese` y
--     `motivo_cese`; cambiarles el vínculo reescribiría cómo se liquidó cada una.
--   · NO TOCA LAS CUENTAS DE SERVICIO (0544): nunca van a planilla.
--   ⚠ NO CORRIGE a quien ya quedó cerrado como «se retiró». Esa persona sigue
--     inactiva, sigue excluida de la planilla de su periodo (0537) y, si ese
--     periodo está abierto, sigue sin cobrar lo que trabajó. Es la parte que no
--     se arregla sola: la consulta (2) de abajo la lista, y hay que mirarla ANTES
--     de pegar. Quitar esa exclusión exige reescribir `fn_planilla_calcular_nucleo`
--     (120 000 caracteres) y su md5 se pide a PRODUCCIÓN justo antes de escribirlo.
--
-- ANTES DE PEGAR (las dos son de solo lectura; dime lo que devuelven)
--   (1) ¿A quién mueve?
--         select p.nombres, p.apellidos, p.fecha_ingreso, p.con_hijos, s.codigo as sede
--           from personas p left join sedes s on s.id = p.sede_base_id
--          where p.tipo_vinculo = 'prueba' and p.estado = 'activo'
--            and not coalesce(p.cuenta_de_servicio, false)
--          order by p.fecha_ingreso;
--   (2) ¿Hay alguien cerrado como «se retiró» cuyo periodo sigue sin pagarse?
--         select p.nombres, p.apellidos, pr.inicio, pr.cerrada_fecha,
--                per.fecha_ini, per.fecha_fin, per.estado
--           from pruebas pr
--           join personas p on p.id = pr.persona_id
--           left join periodos_planilla per
--                  on per.fecha_ini <= pr.cerrada_fecha and per.fecha_fin >= pr.inicio
--          where pr.resultado = 'retirado'
--          order by pr.cerrada_fecha desc;
--       Cualquier fila con estado distinto de «pagado» (o sin periodo todavía) es
--       alguien a quien hoy NO se le paga lo trabajado.
--
-- CÓMO SE REVIERTE
--   No se revierte en bloque a propósito: volver a poner a alguien en «prueba»
--   es volver a no registrarlo. Si hubiera que deshacerlo para UNA persona, el
--   cambio es `update personas set tipo_vinculo = 'prueba' where id = '…'`, y
--   queda dicho aquí que la ley no lo respalda.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 446.
-- ============================================================================

-- ── Guardia: la 0553 y la 0536 tienen que estar ─────────────────────────────
do $guardia$
begin
  if to_regclass('public.pruebas') is null then
    raise exception 'PARA. Falta la 0536: no existe la tabla pruebas. Pega primero la 0536.';
  end if;
  if not exists (select 1 from migraciones_aplicadas where numero = 553) then
    raise exception 'PARA. Falta la 0553: las pantallas todavía hablan de «días de prueba». Pega primero la 0553.';
  end if;
end
$guardia$;

-- ── Quién se mueve (se muestra, y se mueve) ─────────────────────────────────
-- Las cuentas de servicio nunca van a planilla (0544); las inactivas no se tocan.
with movidas as (
  update personas
     set tipo_vinculo = 'planilla'
   where tipo_vinculo = 'prueba'
     and estado = 'activo'
     and not coalesce(cuenta_de_servicio, false)
  returning id, nombres, apellidos, fecha_ingreso, con_hijos, sede_base_id
)
select m.nombres, m.apellidos, m.fecha_ingreso, m.con_hijos, s.codigo as sede
  from movidas m
  left join sedes s on s.id = m.sede_base_id
 order by m.fecha_ingreso;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (554, 'quien_figuraba_de_prueba_pasa_a_planilla')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: 0 · 0 · «554 · quien_figuraba_de_prueba_pasa_a_planilla»
-- y la lista de abajo, VACÍA o con quien hay que mirar a mano.
select
  (select count(*) from personas
    where tipo_vinculo = 'prueba' and estado = 'activo'
      and not coalesce(cuenta_de_servicio, false))                           as activas_que_siguen_de_prueba,
  (select count(*) from pruebas p join personas x on x.id = p.persona_id
    where p.resultado = 'en_curso' and x.estado = 'activo')                  as pruebas_abiertas_de_activas,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 554) as registro;

-- Quien se retiró en prueba y cuyo periodo no está pagado: hoy no cobra lo que trabajó (0537).
select p.nombres, p.apellidos, pr.inicio, pr.cerrada_fecha, per.fecha_ini, per.fecha_fin, per.estado as periodo
  from pruebas pr
  join personas p on p.id = pr.persona_id
  left join periodos_planilla per on per.fecha_ini <= pr.cerrada_fecha and per.fecha_fin >= pr.inicio
 where pr.resultado = 'retirado'
   and coalesce(per.estado, 'abierto') <> 'pagado'
 order by pr.cerrada_fecha desc;
