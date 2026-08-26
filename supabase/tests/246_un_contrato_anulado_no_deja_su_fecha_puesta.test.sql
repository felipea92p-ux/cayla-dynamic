-- ============================================================================
-- 246_un_contrato_anulado_no_deja_su_fecha_puesta.test.sql
-- ============================================================================
-- Los tres defectos que la auditoría del 2026-08-26 encontró en el área de
-- contratos y que la 0312 arregla, más los cuatro que la revisión adversarial
-- de la propia 0312 encontró en su PRIMERA versión — que preguntaba «¿es el
-- contrato más reciente sin anular?» y esa pregunta la gana un BORRADOR.
--
-- Todos comparten raíz: `personas.fecha_fin_contrato` se movía sin preguntar de
-- qué contrato venía. Ese dato lo usa `fn_contratos_desnaturalizados` (0231)
-- para avisar del riesgo del artículo 77 del TUO del D. Leg. 728; moverlo mal
-- fabrica una desnaturalización que no ocurrió, o esconde una que sí.
--
-- Los `generado_at` se fijan A MANO. `now()` es constante dentro de una
-- transacción, así que sin esto los contratos empatan y «el más reciente» lo
-- decidiría el desempate en vez de la intención de la prueba.
-- ============================================================================
begin;
select plan(15);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000c07b000', 'ZZANU', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000c07b009', 'AnuDO', 'Laboratorio',
        '00000000-0000-0000-0000-00000c07b000', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-00000c07b009', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000c07b001', 'AnuAna',   'Laboratorio', '00000000-0000-0000-0000-00000c07b000', 'test-hash', '2022-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000c07b002', 'AnuBeto',  'Laboratorio', '00000000-0000-0000-0000-00000c07b000', 'test-hash', '2022-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000c07b003', 'AnuCarla', 'Laboratorio', '00000000-0000-0000-0000-00000c07b000', 'test-hash', '2022-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000c07b004', 'AnuDora',  'Laboratorio', '00000000-0000-0000-0000-00000c07b000', 'test-hash', '2022-01-02', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000c07b009', true);

-- Atajo: generar un contrato con su `generado_at` puesto a mano.
create or replace function _lab_contrato(p_persona uuid, p_fin date, p_marca text, p_cuando timestamptz)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := fn_contrato_registrar(
    p_persona_id := p_persona, p_tipo := 'renovacion', p_cargo := 'Asesora',
    p_sede_id := '00000000-0000-0000-0000-00000c07b000',
    p_remuneracion_mensual := 1130, p_fecha_inicio := '2026-01-01',
    p_fecha_fin := p_fin, p_documento_html := p_marca);
  update contratos_generados set generado_at = p_cuando where id = v;
  return v;
end $$;

create or replace function _lab_firmar(p_id uuid, p_dia date)
returns void language sql as $$
  select fn_contrato_registrar(p_id := p_id,
           p_storage_path := 'contratos/' || p_id::text || '.pdf', p_fecha_firma := p_dia);
$$;


-- ── El bucket admite reemplazar un escaneo ────────────────────────────────
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'contratos_update'),
  1, 'El bucket contratos ya admite reemplazar un objeto (política UPDATE)');

-- ── Un borrador NO gobierna ninguna fecha ─────────────────────────────────
select is(
  (fn_contrato_firmado_vigente_de('00000000-0000-0000-0000-00000c07b001')).id,
  null, 'Sin ningún contrato firmado, no hay contrato que gobierne la fecha');


-- ── ANA · firma el nuevo, después el viejo: la fecha no retrocede ──────────
select _lab_contrato('00000000-0000-0000-0000-00000c07b001', '2026-06-30', '<p>viejo</p>',  '2026-01-01 09:00+00');
select _lab_contrato('00000000-0000-0000-0000-00000c07b001', '2026-12-31', '<p>nuevo</p>',  '2026-01-02 09:00+00');

select _lab_firmar((select id from contratos_generados where documento_html = '<p>nuevo</p>'), '2026-01-05');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b001'),
  '2026-12-31'::date, 'El contrato firmado fija el vencimiento');

select lives_ok(
  $$ select _lab_firmar((select id from contratos_generados where documento_html = '<p>viejo</p>'), '2026-01-06') $$,
  'El borrador viejo se puede archivar igual: el papel existe');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b001'),
  '2026-12-31'::date, 'Pero NO retrocede el vencimiento: manda el firmado más reciente');

-- Anular el vigente devuelve la fecha al firmado anterior.
select fn_contrato_anular((select id from contratos_generados where documento_html = '<p>nuevo</p>'),
                          'se firmó con el sueldo equivocado');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b001'),
  '2026-06-30'::date, 'Anular el vigente devuelve el vencimiento al firmado que queda en pie');

-- Y anular el último firmado deja la fecha sin fijar.
select fn_contrato_anular((select id from contratos_generados where documento_html = '<p>viejo</p>'),
                          'tambien estaba mal');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b001'),
  null, 'Sin ningún contrato firmado en pie, el vencimiento se borra en vez de heredar uno nulo');


-- ── BETO · EL DEFECTO QUE LA REVISIÓN ENCONTRÓ EN LA PRIMERA 0312 ──────────
-- Firma su contrato y DESPUÉS se le prepara la renovación, que queda de
-- borrador. Con el criterio viejo —«el más reciente sin anular»— ese borrador
-- ganaba, y anular el contrato firmado NO devolvía la fecha: la persona se
-- quedaba con el vencimiento de un documento declarado nulo.
select _lab_contrato('00000000-0000-0000-0000-00000c07b002', '2026-12-31', '<p>beto firmado</p>', '2026-01-01 09:00+00');
select _lab_firmar((select id from contratos_generados where documento_html = '<p>beto firmado</p>'), '2026-01-05');
select _lab_contrato('00000000-0000-0000-0000-00000c07b002', '2027-12-31', '<p>beto borrador</p>', '2026-06-01 09:00+00');

select is(
  (fn_contrato_firmado_vigente_de('00000000-0000-0000-0000-00000c07b002')).documento_html,
  '<p>beto firmado</p>',
  'Un borrador más reciente NO le quita el gobierno al contrato firmado');

select fn_contrato_anular((select id from contratos_generados where documento_html = '<p>beto firmado</p>'),
                          'se firmó con el cargo equivocado');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b002'),
  null,
  'Anular el firmado devuelve la fecha AUNQUE haya un borrador pendiente más nuevo');
select ok(
  exists (select 1 from correcciones_auditoria
           where persona_id = '00000000-0000-0000-0000-00000c07b002'
             and campo_modificado = 'contrato_anulado'
             and motivo like '%era el contrato firmado vigente%'),
  'Y la auditoría lo dice: era el contrato del que venía la fecha');


-- ── CARLA · firmar con un borrador pendiente sí fija la fecha ──────────────
-- Con el criterio viejo, el borrador más nuevo impedía que el contrato
-- realmente firmado fijara nada — ni siendo el único firmado que existe.
select _lab_contrato('00000000-0000-0000-0000-00000c07b003', '2026-12-31', '<p>carla firma</p>',    '2026-01-01 09:00+00');
select _lab_contrato('00000000-0000-0000-0000-00000c07b003', '2027-12-31', '<p>carla borrador</p>', '2026-06-01 09:00+00');
select _lab_firmar((select id from contratos_generados where documento_html = '<p>carla firma</p>'), '2026-01-05');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b003'),
  '2026-12-31'::date,
  'Un borrador pendiente no impide que el contrato firmado fije el vencimiento');

-- Y retirar ese borrador no le borra la fecha a nadie.
select fn_contrato_anular((select id from contratos_generados where documento_html = '<p>carla borrador</p>'),
                          'ya no se renueva');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b003'),
  '2026-12-31'::date,
  'Retirar un borrador no toca el vencimiento que puso un contrato firmado');


-- ── DORA · un borrador anulado no borra una fecha puesta a mano ────────────
-- Su fecha viene de antes de que el generador existiera. Anular un BORRADOR
-- suyo no puede dejarla sin vencimiento: solo un contrato FIRMADO puede.
select fn_set_fin_contrato('00000000-0000-0000-0000-00000c07b004', '2026-09-30', 'puesta a mano');
select _lab_contrato('00000000-0000-0000-0000-00000c07b004', '2027-12-31', '<p>dora borrador</p>', '2026-06-01 09:00+00');
select fn_contrato_anular((select id from contratos_generados where documento_html = '<p>dora borrador</p>'),
                          'se generó por error');
select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07b004'),
  '2026-09-30'::date,
  'Anular un borrador NO borra una fecha de vencimiento puesta a mano');


-- ── Quien cesó: anular su contrato no puede fallar ────────────────────────
update personas set estado = 'inactivo', fecha_cese = '2026-03-31'
 where id = '00000000-0000-0000-0000-00000c07b003';

select lives_ok(
  $$ select fn_contrato_anular(
       (select id from contratos_generados where documento_html = '<p>carla firma</p>'),
       'se firmó por duplicado') $$,
  'Anular el contrato de quien ya cesó no se cae por fn_set_fin_contrato');
select ok(
  exists (select 1 from correcciones_auditoria
           where persona_id = '00000000-0000-0000-0000-00000c07b003'
             and campo_modificado = 'contrato_anulado'
             and motivo like '%ya no está activa%'),
  'Y la auditoría dice por qué no se tocó su fecha');

select * from finish();
rollback;
