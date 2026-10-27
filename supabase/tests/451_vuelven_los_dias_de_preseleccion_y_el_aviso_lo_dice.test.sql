-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 451_vuelven_los_dias_de_preseleccion_y_el_aviso_lo_dice.test.sql — la 0559 y la 0560
-- ============================================================================
-- Ninguna de las dos toca planilla. Esta prueba fija:
--   · Los «días de preselección» están otra vez en Parámetros, editables.
--   · Las tres filas de la semana pasada (0553 y 0557) y sus claves ya no están,
--     y las dos funciones de lectura tampoco: no queda un número editable que
--     nada lee.
--   · Si una de esas filas ya tenía historial NO se borra: queda fija y dicha.
--   · El aviso de Liquidaciones dice «preselección» y no «prueba», sigue
--     avisando a las mismas personas y solo a quien administra.
--
-- El bloque de retiro de abajo es el de la 0559; si uno cambia, cambia el otro.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000451a01', 'ZZ451', 'Sede de laboratorio 451', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000451a1a', 'integrante-451@local'),
  ('00000000-0000-0000-0000-000000451a1d', 'admin-451@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000451b11', 'Integrante', 'Comun', '00000000-0000-0000-0000-000000451a01',
   'integrante', 'activo', 'x', '00000000-0000-0000-0000-000000451a1a', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000451b14', 'Direccion',  'Admin', '00000000-0000-0000-0000-000000451a01',
   'admin',      'activo', 'x', '00000000-0000-0000-0000-000000451a1d', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000451b15', 'Mas', 'DeUnMes', '00000000-0000-0000-0000-000000451a01',
   'integrante', 'activo', 'x', null, (fn_hoy_lima() - 60), 'prueba'),
  ('00000000-0000-0000-0000-000000451b16', 'Recien', 'Llegada', '00000000-0000-0000-0000-000000451a01',
   'integrante', 'activo', 'x', null, (fn_hoy_lima() - 5), 'prueba');
set session_replication_role = origin;

-- ── 0559 · Parámetros ────────────────────────────────────────────────────────
select is(
  (select count(*)::int from parametros_catalogo
    where parametro = 'prueba_dias' and editable and clase = 'operativo' and valor_min = 1 and valor_max = 15 and valor_defecto = 3),
  1, 'Los días de preselección están en Parámetros, editables, de 1 a 15, hoy 3');

select is(
  (select nombre from parametros_catalogo where parametro = 'prueba_dias'),
  'Días de preselección antes del contrato',
  'Y se llaman «preselección» en pantalla');

select is(fn_prueba_dias_plazo(), 3, 'La función de la 0536 sigue entregando el plazo');

select is(
  (select count(*)::int from parametros_catalogo
    where parametro in ('periodo_prueba_meses', 'feriado_aviso_antiguedad_dias', 'prueba_etiqueta_desde')),
  0, 'Las tres filas de la semana pasada ya no están');

select is(
  (select count(*)::int from configuracion
    where clave in ('periodo_prueba_meses', 'feriado_aviso_antiguedad_dias', 'prueba_etiqueta_desde')),
  0, 'Ni sus claves: nadie las lee');

select is(
  (select count(*)::int from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('fn_feriado_aviso_dias', 'fn_prueba_etiqueta_desde')),
  0, 'Ni las dos funciones de lectura que les servían');

-- Una fila con historial NO se borra: el rastro no se borra nunca. Se simula lo que
-- dejó la 0553 y se corre el mismo bloque de retiro de la 0559.
insert into configuracion (clave, valor, descripcion) values ('periodo_prueba_meses', '3'::jsonb, 'laboratorio');
insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen_clave, ruta, editable, base, orden)
values ('periodo_prueba_meses', 'Periodo de prueba', 'laboratorio', 'meses', 'normativo', 'entero', 3, 3, 3,
        'periodo_prueba_meses', null, false, 'laboratorio', 10);
insert into parametros_historial (parametro, valor_anterior, valor_nuevo, motivo, cambiado_por, origen)
values ('periodo_prueba_meses', 3, 4, 'laboratorio', null, 'base');

do $retiro$
declare
  v_p text;
begin
  foreach v_p in array array['periodo_prueba_meses', 'feriado_aviso_antiguedad_dias', 'prueba_etiqueta_desde'] loop
    if exists (select 1 from parametros_historial where parametro = v_p) then
      update parametros_catalogo
         set nombre      = case when nombre like '%(retirado)' then nombre else nombre || ' (retirado)' end,
             descripcion = 'Ya no se usa para nada: «prueba» volvió a ser un vínculo, con el nombre de «preselección» (0559). Se conserva solo porque tiene historial.',
             clase       = 'normativo',
             editable    = false,
             orden       = 900
       where parametro = v_p;
    else
      delete from parametros_catalogo where parametro = v_p;
      delete from configuracion where clave = v_p;
    end if;
  end loop;
end
$retiro$;

select is(
  (select nombre || ' · ' || editable::text from parametros_catalogo where parametro = 'periodo_prueba_meses'),
  'Periodo de prueba (retirado) · false',
  'Con historial, la fila se queda fija y dicha «(retirado)»; no se borra');

-- ── 0560 · El aviso de Liquidaciones ─────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000451a1d', true);

select ok(
  (select aviso like 'Lleva más de un mes como «preselección».%' and aviso not like '%prueba%' and ya_devenga
     from fn_avisos_vinculo() where persona = 'Mas DeUnMes'),
  'Quien lleva más de un mes lee «preselección», y no «prueba»');

select ok(
  (select aviso like 'Cumple un mes el %«preselección»%' and aviso not like '%prueba%' and not ya_devenga
     from fn_avisos_vinculo() where persona = 'Recien Llegada'),
  'Quien acaba de llegar también, y no dice que ya devenga');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000451a1a', true);
select is((select count(*)::int from fn_avisos_vinculo()), 0,
  'Un integrante común no ve el aviso: solo la dirección, DO y las líderes');

select * from finish();
rollback;
