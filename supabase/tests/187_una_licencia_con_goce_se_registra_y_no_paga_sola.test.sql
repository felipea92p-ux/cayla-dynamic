-- ============================================================================
-- 187_una_licencia_con_goce_se_registra_y_no_paga_sola.test.sql
--   — migraciones 0247 y 0314
--
-- ⚠️ EL NOMBRE DEL ARCHIVO ES HISTÓRICO Y YA NO DESCRIBE LO QUE PRUEBA. Desde
-- la 0314 la licencia con goce SÍ se paga. Se intentó renombrarlo y el hook de
-- numeración lo frenó con razón: cinco ramas sin fusionar tienen todavía el
-- nombre viejo, así que al fusionarse habría DOS archivos con el número 187.
-- Un nombre que miente cuesta menos que una colisión de numeración, que deja
-- `supabase db reset` sin poder reconstruir el esquema.
-- ============================================================================
-- La 0247 agrega el tipo `licencia_con_goce`: la empresa exonera de asistir y
-- sigue pagando. La fila es trivial; lo que esta prueba fija es el MALENTENDIDO
-- que la rodea, porque es el que cuesta plata.
--
-- EL MALENTENDIDO, Y CÓMO SE CERRÓ. El tipo se llama «con goce» y tiene
-- `paga = true`. Cualquiera asume que registrar la ausencia hace que la planilla
-- le pague esos días. Durante meses NO LO HACÍA, y esta prueba existía para
-- decirlo por escrito: «el día que alguien registre una licencia y cierre el
-- mes, la persona cobra de menos y el sistema se ve correcto en pantalla».
--
-- Eso ya no pasa. La **0314** invirtió la regla: la planilla dejó de conocer
-- tipos por su nombre y pasó a preguntarle al CATÁLOGO qué paga, excluyendo
-- solo los tres que tienen tratamiento propio. Con el mismo cambio entró
-- `duelo_familiar_directo`, que la Ley 31602 obliga a pagar.
--
-- Esta prueba conserva su número y su historia porque el aviso sigue haciendo
-- falta en la otra dirección: lo que hoy protege no es que la licencia NO se
-- pague, sino que se pague UNA sola vez. Ver la 249, que monta la planilla
-- entera y mide los importes.
--
-- LAS CUATRO COSAS QUE SE FIJAN:
--
--   1. El tipo existe y sus cuatro interruptores son los que la 0247 declara.
--      `descuenta_vacaciones = false` es el caro: si se pone mal, una decisión
--      de la empresa le gasta a la persona su saldo de vacaciones.
--   2. Que `fn_planilla_calcular` pregunte al catálogo (0314) y que los tres
--      tipos con regla propia queden fuera de esa puerta — las dos mitades, y
--      la segunda es la que evita pagar dos veces el mismo día. Se hace contra
--      `prosrc` porque mide la FORMA de la regla, no un importe.
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
select plan(14);

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

-- ── 2 · Lo que el nombre promete, y que la planilla ya cumple ──────────────
-- ESTA PRUEBA SE HA CAÍDO TRES VECES, y las tres era su trabajo.
--
--   · Decía que `fn_planilla_calcular` no leía `ausencias` en absoluto. Cierto
--     hasta la **0254**, que conectó `descanso_medico` (RIT art. 31 f).
--   · Decía que la maternidad seguía fuera a propósito. Cierto hasta la **0256**.
--   · Y decía que `licencia_con_goce` no se pagaba «porque el nombre del tipo
--     promete un pago que nadie decidió todavía». Se decidió: la **0314**.
--
-- La tercera caída es la que esta prueba venía anunciando desde que se escribió.
-- Su cabecera describe el daño con precisión —«el día que alguien registre una
-- licencia y cierre el mes, la persona cobra de menos y el sistema se ve
-- correcto en pantalla»— y la 0314 lo cierra, junto con el duelo de familiar
-- directo que la Ley 31602 obliga a pagar.
--
-- LA VERDAD DE HOY, y es un cambio de forma, no de lista: la planilla ya no
-- conoce tipos POR SU NOMBRE. Pregunta al CATÁLOGO —`tipos_ausencia.paga`— y
-- excluye solo los tres que tienen tratamiento propio. Por eso lo que se fija
-- aquí no es «paga estos N tipos», que caducaría al siguiente tipo que alguien
-- cree, sino las dos mitades de la regla nueva.
--
-- Se mira el FILTRO y no la palabra suelta, por la razón que esta misma prueba
-- enseñó abajo: `prosrc not like '%maternidad%'` salió en rojo por un COMENTARIO
-- que solo la nombraba.
select ok(
  (select prosrc like '%t.codigo = a.tipo and t.paga%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  'la planilla pregunta al catálogo qué ausencia paga, en vez de conocer tipos por su nombre (0314)'
);

-- Y la otra mitad, que es la que evita pagar DOS VECES el mismo día: los tres
-- tipos con tratamiento propio quedan FUERA de esa puerta nueva. Si alguien
-- quita esta exclusión, el mes de quien estuvo de descanso médico, de
-- maternidad o de vacaciones se paga dos veces.
select ok(
  (select prosrc like '%a.tipo not in (''descanso_medico'', ''maternidad'', ''vacaciones'')%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  'y los tres que ya tienen regla propia quedan fuera de esa puerta: nadie cobra dos veces'
);

-- Y la maternidad SÍ, desde la **0256**. Esta prueba se puso en rojo por segunda
-- vez para avisarlo, que es exactamente para lo que está: afirmaba «la maternidad
-- sigue fuera a propósito» y eso fue verdad hasta el 2026-08-15.
--
-- La verdad de hoy: la planilla paga DOS tipos de ausencia, y cada uno con una
-- regla distinta que NO se puede igualar.
--   · `descanso_medico` cuenta días LABORABLES, porque es sueldo que CAYLA asume
--     (RIT art. 31 f) y el sueldo se paga por los días que tocaba trabajar.
--   · `maternidad` cuenta días CALENDARIO, porque es un subsidio de EsSalud que
--     el empleador adelanta (D.S. 013-2019-TR art. 17.1) y cuyo promedio diario
--     ya viene dividido entre días corridos. Contarlo por laborables le quitaría
--     dos séptimos a quien trabaja cinco días.
-- Si alguien las unifica «para simplificar», la 199 se cae.
--
-- Se mira el FILTRO y no la palabra suelta, y eso lo enseñó esta misma prueba:
-- escrita como `prosrc not like '%maternidad%'` salió en rojo por un COMENTARIO
-- que solo la nombraba. Grepear una cadena en el cuerpo de una función no mide
-- la regla — la lección que `docs/estado.md` ya tenía escrita del 13 de agosto.
select ok(
  (select prosrc like '%a.tipo = ''descanso_medico''%'
      and prosrc like '%a.tipo = ''maternidad''%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_calcular'),
  'la planilla lee ausencias para descanso_medico y para maternidad, cada una con su regla'
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
