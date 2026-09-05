-- ============================================================================
-- 0247 — Una licencia con goce se puede registrar
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Un tipo de ausencia `licencia_con_goce` en el catálogo: la empresa exonera a
-- alguien de asistir y le sigue pagando. Hoy no cabe en ningún tipo existente.
--
-- Los nueve tipos de la 0101 dejan un hueco exacto: los tres que PAGAN
-- (vacaciones, descanso médico, maternidad) los pide la ley y los pide la
-- persona; los seis que no pagan (salud, duelo, permiso personal, cumpleaños,
-- estudios, otro) los pide la persona también. **Ninguno lo decide la empresa.**
-- Registrar una exoneración de asistencia como `permiso_personal` u `otro` deja
-- escrito que ella pidió no venir, cuando la decisión fue de la empresa — y con
-- `paga = false`, además, le quita esos días de la gratificación.
--
-- QUÉ ASUME
--
-- Que la 0101 está aplicada (es la que creó `tipos_ausencia`). Nada más: no
-- toca una función, ni una política, ni una columna.
--
-- ── LO QUE ESTA MIGRACIÓN **NO** HACE, Y HAY QUE LEERLO ANTES DE USARLA ─────
--
-- **NO PAGA. Ni un céntimo.** Medido contra la base local el 2026-08-13, no
-- razonado:
--
--     select (prosrc like '%ausencias%') from pg_proc
--     where proname = 'fn_planilla_calcular';   →  f
--     select count(*) from regexp_matches(prosrc,'ausencias','g') …  →  0
--
-- `fn_planilla_calcular` NO LEE la tabla `ausencias`. Ni esta ni ninguna. El
-- sueldo del periodo sale de `pago_base`, y `pago_base` son las horas MARCADAS
-- por su tarifa, más un único añadido: los días de VACACIONES, que vienen de la
-- tabla `vacaciones` y no de `ausencias` (bloque `vacd`, CAMBIO 0177).
--
-- Consecuencia, dicha sin rodeos: **quien tenga una licencia con goce registrada
-- y no marque, cobra CERO por esos días.** El nombre del tipo dice «paga» y la
-- planilla no lo mira. Un tipo que se llama «con goce» y produce un sueldo de
-- menos es exactamente la clase de pantalla que miente sobre la plata, así que
-- se dice acá y se dice en el comentario de la fila.
--
-- LA PLATA VA POR `movimientos_planilla`, que existe desde la planilla v2 y es
-- el mecanismo previsto para esto: un movimiento `tipo = 'bono'`, con el
-- concepto escrito, sobre el periodo que corresponda. Esa es la vía, y es
-- deliberada — un bono deja el monto explícito y auditable en la boleta, en vez
-- de esconderlo dentro de una fórmula de horas que nadie va a poder reconstruir
-- dentro de dos años.
--
-- ── LO QUE SÍ HACE, Y POR QUÉ VALE LA PENA IGUAL ────────────────────────────
--
-- 1. **Deja de contar como falta.** Medido: `fn_faltas_resumen` no lee
--    `ausencias` directamente, lee la vista `justificaciones_asistencia`, y esa
--    vista ES `ausencias` desplegada día por día (`where anulada_at is null and
--    tipo <> 'vacaciones'`). Cualquier tipo sirve para eso — pero ver «Licencia
--    con goce» en el legajo y no «Otro» es la diferencia entre un registro que
--    explica y uno que hay que ir a preguntar.
--
-- 2. **Los días cuentan para la gratificación.** `paga = true` lo leen las
--    cuatro funciones de provisiones (0135, 0158, 0160 y 0196), todas con el
--    mismo join: `join tipos_ausencia ta on ta.codigo = au.tipo and ta.paga`.
--    Y todas con el mismo comentario, que es justamente por qué esta migración
--    es una fila y no un `if`: «POR QUÉ ta.paga Y NO UNA LISTA DE CÓDIGOS
--    ESCRITA A MANO». El catálogo se amplía y los cuatro consumidores se enteran
--    solos. Con `permiso_personal` esos días NO devengarían grati.
--
-- 3. **No le come las vacaciones.** `descuenta_vacaciones = false`. Es el campo
--    que más caro sale si se pone mal: una exoneración decidida por la empresa
--    que además le gasta el saldo de vacaciones a la persona es plata suya
--    pagando una decisión ajena.
--
-- ── LOS CUATRO INTERRUPTORES, UNO POR UNO ───────────────────────────────────
--
--   paga                 = true   los días devengan gratificación (ver 2)
--   requiere_documento   = false  el papel lo emite la EMPRESA, no lo trae ella.
--                                 Pedirle documento a quien no pidió el permiso
--                                 dejaría la fila marcada como incompleta para
--                                 siempre.
--   requiere_aprobacion  = true   es una decisión de dirección con costo. Los
--                                 otros dos tipos pagados (descanso médico,
--                                 maternidad) también la piden; el único pagado
--                                 que no la pide es vacaciones, que tiene su
--                                 propio circuito de aprobación aparte.
--   descuenta_vacaciones = false  ver (3)
--
-- `orden = 35` lo deja junto a los otros tres que pagan (10, 20, 30) y antes de
-- los que no (40+). El desplegable agrupa por comportamiento, no por alfabeto.
--
-- ── IDEMPOTENTE ─────────────────────────────────────────────────────────────
--
-- `on conflict (codigo) do nothing`, igual que la 0101. Se pega dos veces y la
-- segunda no hace nada — y en particular NO pisa el tipo si alguien ya editó sus
-- interruptores desde la base. La 0101 usa exactamente esta forma.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   delete from tipos_ausencia where codigo = 'licencia_con_goce';
--
-- Y solo funciona si nadie la usó todavía: `ausencias.tipo` tiene FK contra el
-- catálogo, así que con filas registradas el delete falla en vez de dejar
-- ausencias huérfanas. Es el comportamiento correcto. Si hay que retirarlo con
-- filas vivas, se marca `activo = false`: desaparece del desplegable y las
-- ausencias ya registradas conservan su significado.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--
--   La consulta del final, y la prueba 187.
-- ============================================================================

insert into tipos_ausencia
  (codigo, nombre, paga, requiere_documento, requiere_aprobacion,
   descuenta_vacaciones, alerta_desde, ventana_alerta_dias, orden)
values
  ('licencia_con_goce', 'Licencia con goce de haber',
   true,   -- paga: devenga gratificación (0135/0158/0160/0196)
   false,  -- requiere_documento: el papel lo emite la empresa
   true,   -- requiere_aprobacion: decisión de dirección, con costo
   false,  -- descuenta_vacaciones: NO le gasta su saldo
   null, null, 35)
on conflict (codigo) do nothing;

comment on table tipos_ausencia is
  'Que tipos de ausencia existen y como se comporta cada uno. Editable sin migracion: cambiar la politica de permisos no deberia exigir tocar el esquema. OJO: `paga` gobierna las PROVISIONES (grati/CTS/vacaciones), NO el sueldo del periodo — fn_planilla_calcular no lee esta tabla. El sueldo de una licencia con goce se paga con un movimiento de planilla.';

-- ── El rastro ───────────────────────────────────────────────────────────────
-- Lo exige la prueba 122: `migraciones_aplicadas` es lo único que se puede
-- consultar para saber qué hay en producción sin abrir el SQL Editor, y vale
-- exactamente lo que valga su completitud.
insert into migraciones_aplicadas (numero, nombre)
values (247, 'una_licencia_con_goce_se_puede_registrar')
on conflict (numero) do nothing;

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe devolver la fila nueva junto a los otros tres que pagan, y `paga_sueldo`
-- en `false` para TODOS: ningún tipo de ausencia mueve el sueldo del periodo.
--
--   select codigo, nombre, paga as devenga_grati, descuenta_vacaciones,
--          false as paga_sueldo_del_periodo
--   from tipos_ausencia
--   where paga
--   order by orden;
