-- ============================================================================
-- 187_una_licencia_con_goce_se_registra_y_no_paga_sola.test.sql — migración 0247
-- ============================================================================
-- La 0247 agrega el tipo `licencia_con_goce`: la empresa exonera de asistir y
-- sigue pagando. La fila es trivial; lo que esta prueba fija es el MALENTENDIDO
-- que la rodea, porque es el que cuesta plata.
--
-- EL MALENTENDIDO. El tipo se llama «con goce» y tiene `paga = true`. Cualquiera
-- —incluida una sesión futura leyendo esto— asume que registrar la ausencia hace
-- que la planilla le pague esos días. NO LO HACE. Si nadie fija eso por escrito,
-- el día que alguien registre una licencia y cierre el mes, la persona cobra de
-- menos y el sistema se ve correcto en pantalla.
--
-- ⚠️ Y OJO, QUE ESTO CAMBIÓ. Hasta la 0254 el argumento era fuerte y simple:
-- `fn_planilla_calcular` no leía `ausencias` en absoluto. Ya no es cierto — la
-- 0254 conectó `descanso_medico`, porque el RIT art. 31 f) obliga a CAYLA a
-- asumir los primeros 20 días de incapacidad del año. Así que hoy la planilla
-- SÍ lee esa tabla, y lo que sostiene el párrafo de arriba es más estrecho:
-- lee UN tipo, y `licencia_con_goce` no es ese tipo.
--
-- Por eso la prueba central no es «el tipo existe» sino las dos que van detrás:
-- qué mueve `paga` (las provisiones) y qué NO mueve (el sueldo del periodo).
--
-- LAS CUATRO COSAS QUE SE FIJAN:
--
--   1. El tipo existe y sus cuatro interruptores son los que la 0247 declara.
--      `descuenta_vacaciones = false` es el caro: si se pone mal, una decisión
--      de la empresa le gasta a la persona su saldo de vacaciones.
--   2. `fn_planilla_calcular` NO paga `licencia_con_goce` ni `maternidad`, y sí
--      paga `descanso_medico` desde la 0254. Es la prueba que sostiene todo el
--      párrafo de arriba, y se hace contra `prosrc` porque es la única forma de
--      comprobar una AUSENCIA de lectura sin montar una planilla entera.
--   3. Registrar la licencia SÍ tapa la falta: la vista
--      `justificaciones_asistencia` la ve, y es la que leen las faltas.
--   4. La licencia entra por la vista con su tipo, no con otro. Si mañana
--      alguien filtra la vista por tipo, esta prueba se entera.
--
-- NO se prueba que la gratificación suba: eso vive en las provisiones, tiene su
-- propia prueba, y montar un devengado completo acá duplicaría ese escenario
-- para verificar un `join ... and ta.paga` que ya está cubierto.
-- ============================================================================
begin;
select plan(13);

-- ── 1 · El tipo existe, y con los interruptores declarados ──────────────────
select is(
  (select count(*)::int from tipos_ausencia where codigo = 'licencia_con_goce'),
  1,
  'El catalogo tiene el tipo licencia_con_goce'
);

select is(
  (select paga from tipos_ausencia where codigo = 'licencia_con_goce'),
  true,
  'licencia_con_goce PAGA: sus dias devengan gratificacion'
);

select is(
  (select descuenta_vacaciones from tipos_ausencia where codigo = 'licencia_con_goce'),
  false,
  'licencia_con_goce NO descuenta vacaciones: la decision es de la empresa, el saldo es de la persona'
);

select is(
  (select requiere_documento from tipos_ausencia where codigo = 'licencia_con_goce'),
  false,
  'licencia_con_goce no pide documento: el papel lo emite la empresa, no lo trae quien la recibe'
);

select is(
  (select requiere_aprobacion from tipos_ausencia where codigo = 'licencia_con_goce'),
  true,
  'licencia_con_goce pide aprobacion: es una decision de direccion con costo'
);

select is(
  (select activo from tipos_ausencia where codigo = 'licencia_con_goce'),
  true,
  'licencia_con_goce nace activo'
);

-- ── 2 · Lo que el nombre promete y la planilla no cumple ────────────────────
-- ESTA PRUEBA YA SE CAYÓ UNA VEZ, y era su trabajo. Decía que
-- `fn_planilla_calcular` no leía `ausencias` en absoluto — cierto hasta la
-- **0254**, que conectó `descanso_medico` porque el RIT art. 31 f) obliga a
-- CAYLA a asumir los primeros 20 días de incapacidad del año. Al conectarla,
-- esta prueba se puso en rojo y avisó de que la afirmación había caducado.
--
-- Así que ahora dice la verdad de hoy, que es más estrecha y más útil: la
-- planilla paga UN tipo de ausencia, y `licencia_con_goce` no es ese tipo. Si
-- alguien la conecta, esto se cae otra vez — y volverá a ser lo correcto,
-- porque el nombre del tipo promete un pago que nadie decidió todavía.
select ok(
  (select prosrc not like '%licencia_con_goce%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  'la planilla NO paga licencia_con_goce: el tipo se registra y tapa la falta, pero no paga sola'
);

-- Y la maternidad tampoco, por la misma razón y con más motivo: tiene reglas
-- propias —98 días, subsidio de EsSalud desde el día uno— que hay que decidir
-- antes de escribirlas. La 0254 la dejó fuera a propósito.
--
-- Se mira el FILTRO y no la palabra suelta, y eso lo enseñó esta misma prueba:
-- escrita como `prosrc not like '%maternidad%'` salió en rojo por un COMENTARIO
-- que solo la nombraba. Grepear una cadena en el cuerpo de una función no mide
-- la regla — la lección que `docs/estado.md` ya tenía escrita del 13 de agosto.
select ok(
  (select prosrc like '%a.tipo = ''descanso_medico''%'
      and prosrc not like '%a.tipo = ''maternidad''%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  'la planilla lee ausencias SOLO para descanso_medico: la maternidad sigue fuera a propósito'
);

select ok(
  (select prosrc not like '%ausencias%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_faltas_resumen'),
  'fn_faltas_resumen tampoco lee ausencias directamente: pasa por la vista justificaciones_asistencia'
);

-- ── 3 · Pero la licencia sí tapa la falta, por la vista ─────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000a7'::uuid, 'ZZLIC', 'Sede de laboratorio licencia', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000a701'::uuid, 'Licen', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000a7'::uuid, 'integrante', 'test-hash',
        '00000000-0000-0000-0000-00000000a702'::uuid),
       ('00000000-0000-0000-0000-00000000a703'::uuid, 'AdmLic', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000a7'::uuid, 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000a704'::uuid);
set session_replication_role = origin;

-- `registrada_por` es NOT NULL a propósito: una licencia con goce la CONCEDE
-- alguien, y el legajo tiene que decir quién. No hay licencia sin firmante.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por)
values ('00000000-0000-0000-0000-00000000a701'::uuid, 'licencia_con_goce',
        date '2026-08-14', date '2026-08-16', 'Exoneracion de asistencia decidida por la empresa',
        '00000000-0000-0000-0000-00000000a703'::uuid);

select is(
  (select count(*)::int from justificaciones_asistencia
   where persona_id = '00000000-0000-0000-0000-00000000a701'::uuid),
  3,
  'Una licencia de tres dias aparece como tres dias justificados: la vista despliega el rango'
);

select is(
  (select count(distinct motivo)::int from justificaciones_asistencia
   where persona_id = '00000000-0000-0000-0000-00000000a701'::uuid),
  1,
  'Los tres dias llevan el mismo motivo'
);

select is(
  (select distinct motivo from justificaciones_asistencia
   where persona_id = '00000000-0000-0000-0000-00000000a701'::uuid),
  'licencia_con_goce',
  'La vista expone el TIPO como motivo: el legajo dice licencia con goce, no "otro"'
);

-- ── 4 · Y anularla la retira de la vista ────────────────────────────────────
-- `chk_ausencia_anulacion` exige las tres columnas juntas y un motivo de cuatro
-- caracteres como mínimo: no se puede borrar una licencia sin decir por qué ni
-- quién. Se anota acá porque es la clase de guarda que una sesión futura intenta
-- esquivar poniendo solo `anulada_at` y no entiende por qué la base la frena.
update ausencias
   set anulada_at = now(),
       anulada_por = '00000000-0000-0000-0000-00000000a703'::uuid,
       anulada_motivo = 'Se dejo sin efecto la licencia'
 where persona_id = '00000000-0000-0000-0000-00000000a701'::uuid;

select is(
  (select count(*)::int from justificaciones_asistencia
   where persona_id = '00000000-0000-0000-0000-00000000a701'::uuid),
  0,
  'Anulada la ausencia, los dias dejan de estar justificados y vuelven a contar'
);

select * from finish();
rollback;
