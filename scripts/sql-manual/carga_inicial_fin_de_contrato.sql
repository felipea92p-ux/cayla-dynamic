-- ============================================================================
-- PARA PEGAR EN EL SQL EDITOR — la carga inicial de los fines de contrato
-- ============================================================================
-- QUÉ HACE. Pone `personas.fecha_fin_contrato = 2026-12-31` a quien está activa
-- y tiene contrato de trabajo. Es la carga de arranque: el campo se agregó en la
-- 0144, hasta el 2026-08-06 no se podía escribir desde ninguna pantalla, y por
-- eso está vacío para todo el equipo.
--
-- POR QUÉ UNA SOLA VEZ Y POR SQL. Son ~30 personas con la MISMA fecha. Meterlas
-- una por una por la ficha son treinta ediciones idénticas, y treinta
-- oportunidades de equivocarse en una. De aquí en adelante se usa la pantalla:
-- Equipo → Editar → «Último día que trabaja por contrato».
--
-- A QUIÉNES SÍ Y A QUIÉNES NO (decisión de Felipe, 2026-08-07). Solo a quien
-- tiene `tipo_vinculo = 'planilla'`, o sea contrato de trabajo. Quedan fuera:
--
--   · 'prueba'         — días de prueba, todavía SIN contrato (0085). Ponerle
--                        fecha de fin a un contrato que no existe es escribir
--                        un dato falso, y ese dato ya decide cosas.
--   · 'rxh'            — locación de servicios, no relación laboral. Anotarle
--                        «fin de contrato» de trabajo es justo el indicio que se
--                        usa para desnaturalizar un contrato civil.
--   · 'no_trabajador'  — accionista sin servicios.
--
-- POR QUÉ UN `update` Y NO `fn_set_fin_contrato`. Porque la función exige saber
-- QUIÉN hace el cambio para auditarlo, y una sesión del SQL Editor no tiene
-- persona asociada: `fn_persona_actual_id()` devuelve null y la función se niega
-- —con razón—. La contrapartida es que esta carga no deja rastro en
-- `correcciones_auditoria`. Es aceptable UNA vez, para el arranque, y queda
-- dicho acá que fue así. Cualquier cambio posterior va por la pantalla, que sí
-- audita.
--
-- QUÉ NO HACE. No da de baja a nadie. Anotar el fin de contrato NO es un cese:
-- todas siguen activas, siguen marcando y siguen cobrando hasta ese día.
--
-- NO PISA LO YA ESCRITO. Solo toca a quien tenga el campo en null, así que si
-- alguien ya tiene su fecha anotada —porque su contrato vence antes— se respeta.
--
-- CÓMO SE REVIERTE
--   update personas set fecha_fin_contrato = null
--    where fecha_fin_contrato = date '2026-12-31';
-- ============================================================================

-- ── 1 · A quiénes va a afectar (mira esto ANTES) ──────────────────────────
select nombres, apellidos, tipo_vinculo, fecha_ingreso, fecha_fin_contrato
  from personas
 where estado = 'activo' and tipo_vinculo = 'planilla'
 order by apellidos, nombres;

-- Y quiénes quedan FUERA, para que sea una decisión y no un descuido:
select tipo_vinculo, count(*) as cuantas
  from personas
 where estado = 'activo' and tipo_vinculo <> 'planilla'
 group by tipo_vinculo
 order by tipo_vinculo;


-- ── 2 · El caso imposible, antes de escribir nada ─────────────────────────
-- El constraint `personas_fin_contrato_coherente` exige que el fin no sea
-- anterior al ingreso. Si esta consulta devuelve algo, NO sigas: esa persona
-- tiene una fecha de ingreso posterior al 31/12/2026 y hay que mirarla.
select nombres, apellidos, fecha_ingreso
  from personas
 where estado = 'activo' and tipo_vinculo = 'planilla'
   and fecha_ingreso > date '2026-12-31';


-- ── 3 · Ponerlas ──────────────────────────────────────────────────────────
begin;

update personas
   set fecha_fin_contrato = date '2026-12-31'
 where estado = 'activo'
   and tipo_vinculo = 'planilla'
   and fecha_fin_contrato is null;

-- Comprueba antes de confirmar: el total tiene que coincidir con la lista del
-- paso 1, y `sin_fecha` tiene que ser 0.
select count(*) filter (where fecha_fin_contrato = date '2026-12-31') as con_31_12,
       count(*) filter (where fecha_fin_contrato is null)             as sin_fecha,
       count(*)                                                       as total_planilla
  from personas
 where estado = 'activo' and tipo_vinculo = 'planilla';

-- Si cuadra: `commit;`   ·   si no: `rollback;`
-- No dejes la transacción abierta — bloquea filas para el resto del sistema.
commit;


-- ── 4 · Qué vas a ver después ─────────────────────────────────────────────
-- En Equipo, bajo cada nombre: «Contrato hasta: 31/12/2026». En gris, no en
-- ámbar: el ámbar avisa de que vence este mes o antes, y diciembre no lo es.
--
-- En el panel de administración NO va a aparecer nada todavía. La franja de
-- contratos lista lo que vence dentro de 30 días, así que empieza a avisar el
-- 1 de diciembre. Que hoy no salga nada es la respuesta correcta.
--
-- Y en Documentación no cambia nada: el reparto solo desmarca a quien termina
-- ESTE mes. Con todo el equipo al 31/12, todos siguen recibiendo su declaración
-- de ruta, que es lo que corresponde — hasta diciembre cobran movilidad.
--
-- ── 5 · Lo que hay que recordar en diciembre ──────────────────────────────
-- El 1 de diciembre el panel va a listar al equipo entero como «vence en 30
-- días». No es una falsa alarma: es la fecha real. Lo que toca entonces es
-- renovar —y actualizar la fecha desde la ficha, o vaciarla si pasa a
-- indefinido— o registrar las salidas. Si se renueva y nadie actualiza el dato,
-- en enero todo el equipo aparece como «contrato vencido y sigue activa», y un
-- aviso que grita sin motivo se desactiva a la semana.
