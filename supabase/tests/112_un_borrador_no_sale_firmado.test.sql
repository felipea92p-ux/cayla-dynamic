-- ============================================================================
-- 112_un_borrador_no_sale_firmado.test.sql
-- ============================================================================
-- Un memo se redacta eligiendo quién lo firmará, y se firma después. Entre esos
-- dos momentos el documento tenía `firmante_id` puesto y `firmado_at` vacío —
-- y `fn_firma_de_memo` solo miraba el primero.
--
-- Así que un borrador impreso para revisarlo salía con una rúbrica escaneada de
-- verdad, y el aviso de «borrador» de la pantalla no se imprime (lleva
-- `no-print`). En el papel, un borrador firmado y un memo firmado eran el mismo
-- documento.
--
-- Importa porque el memo es la pieza que arma el expediente disciplinario
-- (D.S. 003-97-TR art. 25): su valor depende de que la fecha y la firma digan
-- la verdad.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ba00', 'ZZBOR', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000ba01', 'BorradorAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ba00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ba09');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000ba02', 'BorradorPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ba00', 'test-hash');

-- La firma escaneada de quien va a firmar los memos.
insert into firmas_escaneadas (persona_id, imagen)
values ('00000000-0000-0000-0000-00000000ba01',
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ba09', true);

-- Dos memos idénticos salvo en una cosa: uno está firmado y el otro no.
-- El borrador lleva `firmante_id` y NO lleva `firmado_at`: así queda un memo
-- entre que se redacta —eligiendo quién lo firmará— y que se firma. El esquema
-- lo permite a propósito (`chk_firmado_completo` solo exige las tres cosas
-- cuando el memo ya salió de borrador), y ese hueco legítimo es justo por donde
-- se colaba la firma.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, correlativo, firmante_id, firmado_at, creado_por) values
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-00000000ba02',
   'tardanza', 'amonestacion', 'borrador', null,
   '00000000-0000-0000-0000-00000000ba01', null,
   '00000000-0000-0000-0000-00000000ba01'),
  ('00000000-0000-0000-0000-00000000bb02', '00000000-0000-0000-0000-00000000ba02',
   'tardanza', 'amonestacion', 'firmado', 'ZZ-LAB-0001',
   '00000000-0000-0000-0000-00000000ba01', '2026-08-01T10:00:00-05:00',
   '00000000-0000-0000-0000-00000000ba01');

-- ── El borrador ─────────────────────────────────────────────────────────────
select is(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bb01')),
  null::text,
  'BORRADOR · un memo sin firmar no entrega ninguna rúbrica');

select is(
  (select firmado_at from expediente_disciplinario
    where id = '00000000-0000-0000-0000-00000000bb01'),
  null::timestamptz,
  'BORRADOR · y sigue sin firmar: pedir la firma no firma nada');

-- ── El firmado ──────────────────────────────────────────────────────────────
-- La otra mitad, y la que impide "arreglar" esto devolviendo null siempre: un
-- memo de verdad firmado tiene que seguir saliendo con su firma.
select isnt(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bb02')),
  null::text,
  'FIRMADO · un memo firmado sí entrega la rúbrica de quien lo firmó');

select ok(
  (select fn_firma_de_memo('00000000-0000-0000-0000-00000000bb02')) like 'data:image/%',
  'FIRMADO · y lo que entrega es la imagen de la firma, no otra cosa');

select * from finish();
rollback;
