-- ============================================================================
-- 417_acortar_el_hasta_de_educacion_deja_de_fallar.test.sql
-- ============================================================================
-- Lo que promete la 0523 (el caso de Sandra, 2026-10-16):
--   · dar por terminada una asignación el día ANTERIOR al primer periodo abierto
--     cierra la fila: no abre una vigencia nueva con desde > hasta (que la base
--     rechazaba con el aviso genérico) y deja rastro «educacion_cierre»;
--   · acortar hasta un día que deja sin cobertura días de un periodo PAGADO se
--     rechaza, y el mensaje dice cuál es la fecha más temprana que se admite;
--   · mezclar un recorte con otro cambio (el costo) se dice, no se deja caer;
--   · corregir un costo dentro del periodo abierto sigue abriendo vigencia nueva;
--   · «Cerrar» usa el mismo criterio.
--
-- Las fechas salen de fn_hoy_lima(): el periodo pagado termina 11 días antes de
-- hoy y el abierto empieza 10 días antes, como septiembre (cierra el 27/09) y
-- octubre (empieza el 28/09). Todo en begin/rollback.
-- ============================================================================
begin;
select plan(13);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000523a00', 'ZZ523', 'Sede de laboratorio 523', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000523a01', 'DO523', 'Laboratorio',
        '00000000-0000-0000-0000-000000523a00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-000000523a09', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000523a02', 'Ana523',  'Laboratorio', '00000000-0000-0000-0000-000000523a00', 'test-hash', '2020-01-02'),
  ('00000000-0000-0000-0000-000000523a03', 'Cesa523', 'Laboratorio', '00000000-0000-0000-0000-000000523a00', 'test-hash', '2020-01-02');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000523a02', 'aurora', 1500, '2020-01-02'),
  ('00000000-0000-0000-0000-000000523a03', 'aurora', 1500, '2020-01-02');

-- Un periodo pagado (cierra hoy-11) y el abierto que sigue (de hoy-10 a hoy+20).
-- El periodo pagado de antes de la 0323 no necesita fila en periodo_grupo_pago.
insert into periodos_planilla (fecha_ini, fecha_fin, estado) values
  (fn_hoy_lima() - 40, fn_hoy_lima() - 11, 'pagado'),
  (fn_hoy_lima() - 10, fn_hoy_lima() + 20, 'abierto');

-- Las asignaciones nacen DENTRO del periodo pagado (por eso no se registran por
-- fn_educacion_registrar, que no deja dar de alta ahí): como la de Duolingo.
insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por) values
  ('00000000-0000-0000-0000-000000523b01', '00000000-0000-0000-0000-000000523a02', 150, 'Inst A', 200, 75, 'trabajador',
   fn_hoy_lima() - 30, fn_hoy_lima() + 5, '00000000-0000-0000-0000-000000523a01'),
  ('00000000-0000-0000-0000-000000523b02', '00000000-0000-0000-0000-000000523a02', 150, 'Inst B', 200, 75, 'trabajador',
   fn_hoy_lima() - 5, fn_hoy_lima() + 15, '00000000-0000-0000-0000-000000523a01'),
  ('00000000-0000-0000-0000-000000523b03', '00000000-0000-0000-0000-000000523a03', 150, 'Inst C', 200, 75, 'trabajador',
   fn_hoy_lima() - 30, fn_hoy_lima() + 5, '00000000-0000-0000-0000-000000523a01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000523a09', true);


-- ── 1 · El caso de Sandra: terminar el día anterior al periodo abierto ──────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-000000523a02'::uuid, 'Inst A', 200::numeric, 'trabajador',
    fn_hoy_lima() - 30, fn_hoy_lima() - 11,
    null, null, null, '00000000-0000-0000-0000-000000523b01'::uuid, 'finalizado') $$,
  'RECORTE · terminar el día anterior al periodo abierto se guarda (antes: error 23514)');

select is((select vigente_hasta from asignaciones_educacion where id = '00000000-0000-0000-0000-000000523b01'),
  fn_hoy_lima() - 11, 'RECORTE · la misma fila quedó cerrada ese día');

select is((select count(*)::int from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-000000523a02' and institucion = 'Inst A'),
  1, 'RECORTE · no nació una vigencia nueva: sigue una sola fila');

select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000523a02' and campo_modificado = 'educacion_cierre'
              and valor_nuevo = (fn_hoy_lima() - 11)::text and motivo = 'finalizado'),
  1, 'RECORTE · dejó rastro «educacion_cierre» con el motivo');

select is((select valor_anterior from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000523a02' and campo_modificado = 'educacion_cierre'),
  (fn_hoy_lima() + 5)::text, 'RECORTE · el rastro guarda el fin de antes');


-- ── 2 · Lo pagado no se reescribe ───────────────────────────────────────────
select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-000000523a02'::uuid, 'Inst A', 200::numeric, 'trabajador',
    fn_hoy_lima() - 30, fn_hoy_lima() - 16,
    null, null, null, '00000000-0000-0000-0000-000000523b01'::uuid, 'finalizado') $$,
  '%PAGADO%más temprana%',
  'PAGADO · acortar hasta dentro de un periodo pagado se rechaza y dice la fecha más temprana');


-- ── 3 · Un recorte mezclado con otro cambio se dice ─────────────────────────
select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-000000523a02'::uuid, 'Inst A', 100::numeric, 'trabajador',
    fn_hoy_lima() - 30, fn_hoy_lima() - 11,
    null, null, null, '00000000-0000-0000-0000-000000523b01'::uuid, 'costo y fin') $$,
  '%anterior al primer periodo abierto%',
  'MEZCLA · costo distinto con fin anterior al periodo abierto: lo dice, no cae en el check de la tabla');


-- ── 4 · Lo de siempre sigue igual: un costo nuevo abre vigencia nueva ───────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-000000523a02'::uuid, 'Inst B', 100::numeric, 'trabajador',
    fn_hoy_lima() - 5, fn_hoy_lima() + 15,
    null, null, null, '00000000-0000-0000-0000-000000523b02'::uuid, 'el comprobante decía 100') $$,
  'REGRESIÓN · corregir el costo dentro del periodo abierto sigue funcionando');

select is((select monto from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-000000523a02' and institucion = 'Inst B'
              and vigente_hasta = fn_hoy_lima() + 15),
  75.00::numeric, 'REGRESIÓN · el monto nuevo es el 75% del costo corregido');


-- ── 5 · «Cerrar» con el mismo criterio ──────────────────────────────────────
select throws_like($$
  select fn_educacion_cerrar('00000000-0000-0000-0000-000000523b03'::uuid, fn_hoy_lima() - 16, 'x') $$,
  '%PAGADO%',
  'CERRAR · una fecha que deja sin cobertura días de un periodo pagado se rechaza');

select lives_ok($$
  select fn_educacion_cerrar('00000000-0000-0000-0000-000000523b03'::uuid, fn_hoy_lima() - 11, 'finalizado') $$,
  'CERRAR · el último día del periodo pagado sí es una fecha de cierre válida (antes se rechazaba)');

select is((select vigente_hasta from asignaciones_educacion where id = '00000000-0000-0000-0000-000000523b03'),
  fn_hoy_lima() - 11, 'CERRAR · la fila quedó cerrada ese día');

select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000523a03' and campo_modificado = 'educacion_cierre'),
  1, 'CERRAR · dejó rastro');

select * from finish();
rollback;
