-- ============================================================================
-- 166_reemplazar_la_politica_la_reemplaza.test.sql
-- ============================================================================
-- EL CASO, reportado desde producción el 2026-08-11: se pulsa «Reemplazar» en
-- Documentación, se sube el escaneo nuevo, y la pantalla sigue diciendo
-- «Política de movilidad firmada el 29 de julio de 2026» con el papel VIEJO
-- detrás del botón «Ver».
--
-- Eran dos defectos sumados:
--
--   · `fn_documento_registrar` insertaba una SEGUNDA fila y dejaba las dos
--     vivas: no anulaba nada.
--   · `fn_documentos_estado_politica` elegía con `order by fecha_firma desc
--     limit 1`, SIN desempate.
--
-- Reproducido antes de arreglarlo: dos políticas con fecha 2026-07-29 y la
-- consulta devolvía la primera. El archivo nuevo estaba guardado y era
-- inalcanzable desde la pantalla.
--
-- POR QUÉ EL EMPATE ES EL CASO NORMAL Y NO UNA RAREZA
--   La política tiene que conservar la fecha del papel, anterior al primer pago
--   de movilidad — es exactamente lo que la hace válida, y la propia pantalla
--   avisa en rojo cuando no lo es. Así que TODO reemplazo legítimo empata en
--   `fecha_firma`. Una prueba con fechas distintas habría pasado en verde
--   mientras el defecto seguía vivo: por eso las dos de aquí comparten fecha.
--
-- QUÉ DEFIENDE, Y LAS DOS MITADES
--   Que la nueva mande, Y que la vieja NO desaparezca. Anular en vez de borrar
--   es lo que deja por escrito qué política regía cuando se pagó cada mes, y esa
--   traza es la que sostiene los pagos ya hechos si alguien los discute.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000016500', 'ZZ165', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000016501', 'PolAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000016500', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000016509', '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000016509', true);

-- La movilidad empieza a pagarse el 29/07: por eso la política lleva esa fecha.
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('movilidad_diaria', 10, '2026-07-29', 'laboratorio de la 165');

-- ── 1 · La primera política ─────────────────────────────────────────────────
select lives_ok(
  -- POR NOMBRE, NO POR POSICIÓN: la firma tiene diez parámetros y `p_storage_path`
  -- es el NOVENO, detrás de ruta_declarada, monto, año, negativa y nota. Escrito
  -- posicionalmente, esta misma llamada guardaba el path como «ruta declarada» y
  -- la política quedaba sin archivo — sin fallar.
  $$ select fn_documento_registrar(p_tipo => 'politica', p_fecha_firma => '2026-07-29'::date,
       p_storage_path => 'documentos/vieja.pdf') $$,
  'PRIMERA · se registra la política de movilidad');

select is(
  (select storage_path from fn_documentos_estado_politica()),
  'documentos/vieja.pdf',
  'PRIMERA · y es la que ve la pantalla');

-- ── 2 · El reemplazo, con la MISMA fecha de firma ───────────────────────────
-- Misma fecha a propósito: es la única fecha legítima que puede llevar.
select lives_ok(
  $$ select fn_documento_registrar(p_tipo => 'politica', p_fecha_firma => '2026-07-29'::date,
       p_storage_path => 'documentos/nueva.pdf') $$,
  'REEMPLAZO · se registra la política nueva con la misma fecha');

select is(
  (select storage_path from fn_documentos_estado_politica()),
  'documentos/nueva.pdf',
  'REEMPLAZO · la pantalla muestra la NUEVA (antes seguía en la vieja)');

-- ── 3 · Queda una sola viva, y la otra no se perdió ─────────────────────────
select is(
  (select count(*)::int from documentos_firmados
    where tipo = 'politica' and anulado_at is null),
  1,
  'VIGENTE · una sola política viva: no quedan dos compitiendo');

select is(
  (select count(*)::int from documentos_firmados where tipo = 'politica'),
  2,
  'HISTORIAL · la vieja sigue guardada — se anula, no se borra');

-- ── 4 · Y la anulación dice por qué, que es lo que la hace servir ───────────
-- Un motivo vacío convertiría el historial en una lista de papeles sin relato.
select ok(
  (select anulado_motivo like 'Reemplazada por la pol%'
     from documentos_firmados
    where tipo = 'politica' and storage_path = 'documentos/vieja.pdf'),
  'HISTORIAL · la anulada dice por qué se anuló y con qué fecha se la reemplazó');

select * from finish();
rollback;
