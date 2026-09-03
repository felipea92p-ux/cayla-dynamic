-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 279_el_aviso_de_auto_cierre_sale_por_correo.test.sql
-- ============================================================================
-- Cubre la 0352: fn_auto_cierre ya insertaba en `alertas` desde la 0007, pero
-- con canal='push' —una app móvil que nunca se construyó— así que la fila
-- quedaba pendiente para siempre y nadie la leía. Esto fija que ahora inserta
-- con canal='email' (el que app/api/enviar-alertas sí procesa) y que el
-- payload trae `sede_id`, que ese endpoint necesita para encontrar a la
-- encargada sin adivinarla de otra tabla.
-- ============================================================================
begin;
select plan(3);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000027901', 'ZZAVI', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-000000027902', 'terminal-avi@local');
set session_replication_role = origin;

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-000000027903', '00000000-0000-0000-0000-000000027901',
        'Terminal de laboratorio', true, '00000000-0000-0000-0000-000000027902');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000027904', 'AviOlvido', 'Lab', '00000000-0000-0000-0000-000000027901', 'x', '2024-01-01');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000027904', 'colibri', 1950, '2024-01-01');
-- Horario 09:00-17:00 ayer: para hoy, el auto-cierre (3h de gracia) ya aplica.
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-000000027904', '2024-01-01', '09:00', '17:00', array[0,1,2,3,4,5,6]);

-- Entró ayer y nunca marcó salida.
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000027904', 'entrada',
  ((fn_hoy_lima() - 1)::timestamp + time '09:00') at time zone 'America/Lima',
  gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-000000027903',
  '00000000-0000-0000-0000-000000027901', null);

select fn_auto_cierre();

-- ── 1 · El canal es 'email', no 'push' ──────────────────────────────────────
select is(
  (select canal from alertas
    where persona_id = '00000000-0000-0000-0000-000000027904' and tipo = 'auto_cierre'),
  'email',
  'fn_auto_cierre ya no manda al canal push (una app que no existe): manda a email'
);

-- ── 2 · El payload trae la sede, para que el envío no tenga que adivinarla ──
select is(
  (select payload ->> 'sede_id' from alertas
    where persona_id = '00000000-0000-0000-0000-000000027904' and tipo = 'auto_cierre'),
  '00000000-0000-0000-0000-000000027901',
  'el payload trae sede_id, la misma sede de la jornada auto-cerrada'
);

-- ── 3 · Sigue quedando pendiente hasta que algo la envíe ────────────────────
-- Esta migración no cambia CUÁNDO se marca enviada — eso lo hace
-- app/api/enviar-alertas, que no corre en pgTAP. Solo fija que la fila nace
-- lista para que ese endpoint la recoja.
select is(
  (select estado from alertas
    where persona_id = '00000000-0000-0000-0000-000000027904' and tipo = 'auto_cierre'),
  'pendiente',
  'nace pendiente — el envío lo hace el endpoint, no esta función'
);

select * from finish();
rollback;
