-- ============================================================================
-- 129_el_tablero_no_pide_lo_que_no_se_va_a_firmar.test.sql
-- ============================================================================
-- La 0162 saca del tablero de Documentación a dos personas que nunca van a
-- firmar su declaración de ruta: quien firma por CAYLA —no puede ser las dos
-- partes del mismo pacto individual— y quien termina contrato este mes.
--
-- Lo que este archivo vigila son las tres formas en que ese filtro se rompe sin
-- que nada falle:
--
--   1. Que la condición del firmante VACÍE el tablero cuando la fila de
--      configuración no existe. Con `<>` en vez de `is distinct from`, la
--      comparación contra null da null, el WHERE lo lee como falso y NADIE
--      aparece: 22 personas sin papel y una pantalla que dice que está todo al
--      día. Es el mismo modo de fallo que los guards `is not true`.
--
--   2. Que «tiene fecha de fin» se confunda con «se va ya». Un contrato a plazo
--      fijo hasta diciembre desaparecería en agosto, y esa persona cobraría cinco
--      meses de movilidad sin el pacto que la sostiene.
--
--   3. Que alguien copie el cuerpo de esta función de la 0157 en vez de la 0161
--      y borre en silencio las columnas del bono de cumpleaños. `donde-vive.sh`
--      señala la 0157, y se equivoca: la 0161 usa `drop`+`create` porque cambió
--      el tipo de retorno, y el script solo reconoce `create or replace`.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000c9f00', 'ZTAB', 'Sede de laboratorio 129', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000c9f01', 'TabDO', 'Laboratorio',
        '00000000-0000-0000-0000-0000000c9f00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-0000000c9f09', '2020-01-01');
set session_replication_role = origin;

-- Quien firma por CAYLA. Lleva rol admin porque el trigger de la 0147 no admite
-- que firme documentos de empresa una cuenta sin ese permiso.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000c9f02', 'TabFirmante', 'Laboratorio',
        '00000000-0000-0000-0000-0000000c9f00', 'admin', 'test-hash', '2025-01-02', 'planilla');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, fecha_fin_contrato) values
  -- Se va el último día de este mes.
  ('00000000-0000-0000-0000-0000000c9f03', 'TabSeVa', 'Laboratorio',
   '00000000-0000-0000-0000-0000000c9f00', 'test-hash', '2025-01-02', 'planilla',
   (date_trunc('month', fn_hoy_lima()) + interval '1 month - 1 day')::date),
  -- Contrato a plazo fijo que vence dentro de cuatro meses: NO se va todavía.
  ('00000000-0000-0000-0000-0000000c9f04', 'TabPlazoLargo', 'Laboratorio',
   '00000000-0000-0000-0000-0000000c9f00', 'test-hash', '2025-01-02', 'planilla',
   (date_trunc('month', fn_hoy_lima()) + interval '4 months')::date),
  -- Contrato indefinido.
  ('00000000-0000-0000-0000-0000000c9f05', 'TabNormal', 'Laboratorio',
   '00000000-0000-0000-0000-0000000c9f00', 'test-hash', '2025-01-02', 'planilla', null);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000c9f09', true);


-- ── 1 · Sin fila de firmante, el tablero NO se vacía ───────────────────────
-- Este es el falso positivo caro: una pantalla que dice «0 pendientes» porque la
-- consulta se rompió, no porque el equipo haya firmado.
select ok(
  (select count(*) from fn_documentos_tablero()
    where persona_id::text like '00000000-0000-0000-0000-0000000c9f%') >= 4,
  'Sin fila firmante_empresa el tablero sigue listando a todo el mundo');

select ok(
  exists (select 1 from fn_documentos_tablero()
           where persona_id = '00000000-0000-0000-0000-0000000c9f02'),
  'Sin fila firmante_empresa, quien luego será firmante todavía aparece');


-- ── 2 · Quien termina contrato este mes no aparece, con o sin firmante ─────
select ok(
  not exists (select 1 from fn_documentos_tablero()
               where persona_id = '00000000-0000-0000-0000-0000000c9f03'),
  'Quien termina contrato este mes no aparece en el tablero');

select ok(
  exists (select 1 from fn_documentos_tablero()
           where persona_id = '00000000-0000-0000-0000-0000000c9f04'),
  'Quien tiene contrato hasta dentro de 4 meses SIGUE apareciendo — todavía cobra movilidad');


-- ── 3 · Con la fila puesta, el firmante desaparece y nadie más ─────────────
insert into configuracion (clave, valor)
values ('firmante_empresa',
        jsonb_build_object('persona_id', '00000000-0000-0000-0000-0000000c9f02',
                           'cargo', 'Gerencia General'))
on conflict (clave) do update set valor = excluded.valor;

select ok(
  not exists (select 1 from fn_documentos_tablero()
               where persona_id = '00000000-0000-0000-0000-0000000c9f02'),
  'Quien firma por CAYLA no se pide a sí mismo la declaración');

select ok(
  exists (select 1 from fn_documentos_tablero()
           where persona_id = '00000000-0000-0000-0000-0000000c9f05')
  and exists (select 1 from fn_documentos_tablero()
               where persona_id = '00000000-0000-0000-0000-0000000c9f04'),
  'Nombrar firmante no arrastra a nadie más fuera del tablero');


-- ── 4 · Las columnas del bono de la 0161 siguen ahí ────────────────────────
-- Si esto falla, alguien copió el cuerpo de la 0157 —que es lo que
-- `donde-vive.sh` indica— y la pantalla del bono se quedó ciega en silencio.
select ok(
  (select pg_get_function_result(p.oid)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'fn_documentos_tablero' and n.nspname = 'public')
    like '%bono_estado%',
  'El tablero conserva las columnas del bono que agregó la 0161');

select * from finish();
rollback;
