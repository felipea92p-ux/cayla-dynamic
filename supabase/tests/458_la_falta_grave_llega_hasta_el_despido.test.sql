-- ============================================================================
-- 458 — La falta grave llega hasta el despido (migración 0568)
-- ============================================================================
--
-- Once de las diecisiete aserciones son casos que DEBEN bloquear. No es
-- desconfianza del código: cada una es un camino por el que un despido real se
-- vuelve impugnable, y lo que esta prueba fija es que el sistema no deje
-- recorrerlo.
--
-- El orden sigue el de la escalera: primero quién puede citar la falta grave,
-- después qué falta la habilita, después el plazo del art. 31, y al final la
-- carta de despido y su candado.
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000008a1', 'ZZFG', 'Sede de laboratorio FG', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('ee000000-0000-0000-0000-0000000008af',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'gerencia.fg@laboratorio.local', '', now(), now()),
       ('ee000000-0000-0000-0000-0000000008bf',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'lider.fg@laboratorio.local', '', now(), now());

set session_replication_role = replica;
-- `en_planilla` no se escribe: es una columna generada desde `tipo_vinculo`,
-- cuyo valor por defecto («planilla») ya es el que hace falta — el régimen
-- disciplinario solo alcanza a quien tiene contrato de trabajo (RIT 2.5 y 2.6).
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-0000000008a2', 'FgGerencia', 'Lab',
        '00000000-0000-0000-0000-0000000008a1', 'admin', 'x',
        'ee000000-0000-0000-0000-0000000008af', '2024-01-01', 'activo'),
       ('00000000-0000-0000-0000-0000000008a4', 'FgLider', 'Lab',
        '00000000-0000-0000-0000-0000000008a1', 'supervisor_sede', 'x',
        'ee000000-0000-0000-0000-0000000008bf', '2024-01-01', 'activo'),
       ('00000000-0000-0000-0000-0000000008a3', 'FgImputada', 'Lab',
        '00000000-0000-0000-0000-0000000008a1', 'integrante', 'x', null, '2024-01-01', 'activo');
set session_replication_role = origin;


-- ── 1 · El catálogo nombra la falta grave ───────────────────────────────────
-- Sin esto no hay nada más: hasta la 0568, el CHECK del numeral solo dejaba
-- entrar 53.1 y 53.2, así que una falta del art. 25 de la LPCL no se podía
-- ni escribir.
select is(
  (select count(*)::int from faltas_catalogo
    where rit_version = 4.0 and numeral = '53.3' and gravedad = 'grave'),
  6,
  'los seis literales del numeral 53.3 están en el catálogo del RIT v4.0');

-- ── 2 · Y las dos que no se tramitan por acá quedan marcadas ────────────────
-- e) asistencia (la miden los motores) y f) hostigamiento sexual (arts. 48 a
-- 51, Ley 27942). Están en el catálogo para poder NOMBRARLAS, no para
-- tramitarlas con un memo.
select is(
  (select string_agg(literal, ',' order by literal) from faltas_catalogo
    where numeral = '53.3' and not se_registra_a_mano),
  'e,f',
  'la asistencia y el hostigamiento sexual no se registran a mano');


-- ── La líder no cita faltas graves ──────────────────────────────────────────
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000008bf","role":"authenticated"}';

-- ── 3 · El caso que DEBE bloquear ───────────────────────────────────────────
-- Decisión de Felipe del 2026-10-29: «solo DO/Gerencia citan». Y es el art.
-- 54.4 c): la competencia para imputar no es de la líder de equipo.
select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.3', 'a', 'imputacion',
       date '2026-10-20', date '2026-10-20',
       'Registró la asistencia de otra integrante en el terminal de la sede.', 6) $$,
  '%Sin permiso%',
  'la líder de equipo no imputa una falta grave');


-- ── DO sí, pero solo por lo que el Reglamento habilita ──────────────────────
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000008af","role":"authenticated"}';

-- ── 4 · Una falta significativa nunca habilita el despido (53.4) ────────────
select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.2', 'd', 'imputacion',
       date '2026-10-20', date '2026-10-20',
       'Omitió el registro de asistencia de forma reiterada durante la semana.', 6) $$,
  '%53.4%',
  'una falta significativa no se imputa: el 53.4 lo prohíbe');

-- ── 5 · Y una falta grave no se amonesta de frente (54.8 y 52.5) ────────────
-- El caso que menos se espera y el que más cuesta: amonestar por un 53.3 deja
-- el hecho grave documentado como leve y consumido por el non bis in idem.
select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.3', 'a', 'amonestacion',
       date '2026-10-20', date '2026-10-20',
       'Registró la asistencia de otra integrante en el terminal de la sede.') $$,
  '%se imputa%',
  'una falta grave no se amonesta de frente: se imputa');

-- ── 6 · La asistencia no entra por esta puerta ──────────────────────────────
-- Dos puertas a la misma pregunta con umbrales distintos es el defecto que la
-- 0237 cerró y la 0297/0299 repitió.
select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.3', 'e', 'imputacion',
       date '2026-10-20', date '2026-10-20',
       'Acumuló seis ausencias injustificadas en el último mes calendario.', 6) $$,
  '%no se registra a mano%',
  'el literal de asistencia lo miden los motores, no se cita a mano');


-- ── El plazo del art. 31 de la LPCL ─────────────────────────────────────────

-- ── 7 · Sin plazo no hay imputación ────────────────────────────────────────
select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.3', 'a', 'imputacion',
       date '2026-10-20', date '2026-10-20',
       'Registró la asistencia de otra integrante en el terminal de la sede.') $$,
  '%no menor de seis%',
  'una imputación sin plazo de descargo no se crea');

-- ── 8 · Y no se puede bajar del mínimo legal ───────────────────────────────
select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.3', 'a', 'imputacion',
       date '2026-10-20', date '2026-10-20',
       'Registró la asistencia de otra integrante en el terminal de la sede.', 3) $$,
  '%seis (6) días naturales%',
  'tres días de plazo no alcanzan: el art. 57.2 pide seis como mínimo');

-- ── 9 · El plazo de seis días no es de la amonestación ─────────────────────
-- Dos relojes distintos porque la ley usa dos relojes distintos: el art. 55.2
-- cuenta días hábiles, el art. 57.2 cuenta naturales. Pasarle el segundo a una
-- amonestación sería conceder un plazo que esa vía no abre.
select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.2', 'e', 'amonestacion',
       date '2026-10-20', date '2026-10-20',
       'No atendió una instrucción expresa sobre el cierre de caja de la tienda.', 6) $$,
  '%art. 55.2%',
  'el plazo del art. 57.2 no se le concede a una amonestación');

-- ── 10 · El numeral 60.5, que en esta rama no lo comprobaba nadie ──────────
-- Imputar la inobservancia de un Reglamento cuya entrega no consta es imputar
-- el incumplimiento de algo que no se puede probar que la persona recibió.
-- Antes de la 0568 este freno vivía solo en `fn_expediente_comunicar_cargos`,
-- que rechaza la imputación — así que la rama del despido era la única sin él.
insert into documentos_institucionales (id, tipo, version, titulo, documento, vigente_desde)
values ('00000000-0000-0000-0000-0000000008c1', 'rit', 4, 'RIT de laboratorio',
        'cuerpo', date '2026-01-01');

select throws_like(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.3', 'a', 'imputacion',
       date '2026-10-20', date '2026-10-20',
       'Registró la asistencia de otra integrante en el terminal de la sede.', 6) $$,
  '%60.5%',
  'sin constancia de entrega del Reglamento no se imputa una falta grave');

-- `chk_acuse_coherente` pide el nombre declarado cuando el acuse es por el
-- sistema, y que `registrado_por` quede vacío: lo declaró ella, no un tercero.
insert into documentos_acuses (documento_id, persona_id, via, nombre_declarado)
values ('00000000-0000-0000-0000-0000000008c1', '00000000-0000-0000-0000-0000000008a3',
        'sistema', 'FgImputada Lab');


-- ── 11 · El camino bueno ───────────────────────────────────────────────────
-- Un freno que lo frena todo no es un freno: es una pared.
select lives_ok(
  $$ select fn_expediente_crear_conducta(
       '00000000-0000-0000-0000-0000000008a3', '53.3', 'a', 'imputacion',
       date '2026-10-20', date '2026-10-20',
       'Registró la asistencia de otra integrante en el terminal de la sede.', 8) $$,
  'DO imputa la falta grave citando su literal y concediendo ocho días');

select is(
  (select nivel || ' / ' || falta_numeral || falta_literal || ' / ' || plazo_descargo_dias
     from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion'),
  'imputacion / 53.3a / 8',
  'la imputación queda con su literal citado y su plazo guardado');


-- ── La carta de despido ────────────────────────────────────────────────────
-- Se lleva la imputación recién creada hasta ENTREGADA a mano: entregarla de
-- verdad es trabajo de la 0569, y lo que esta prueba mide es la carta.
set session_replication_role = replica;
update expediente_disciplinario
   set estado = 'entregado', correlativo = 'LAB-IMP-458',
       firmante_id = '00000000-0000-0000-0000-0000000008a2', firmado_at = now(),
       medio_entrega = 'fisico', entregado_at = now() - interval '10 days',
       -- `chk_descargo_coherente` exige las dos fechas o ninguna, y que el
       -- vencimiento sea posterior a la comunicación. En el camino del art. 57
       -- los cargos se comunican AL ENTREGAR la carta: por eso van juntas.
       cargos_comunicados_at = now() - interval '10 days',
       descargo_vence_at = now() - interval '2 days'
 where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion';
set session_replication_role = origin;

-- ── 12 · Sin resolver por escrito no hay carta (57.6) ──────────────────────
select throws_like(
  $$ select fn_expediente_crear_despido(
       (select id from expediente_disciplinario
         where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion'),
       date '2026-11-05',
       'Se resuelve el despido pese al descargo presentado por la colaboradora.') $$,
  '%Primero se resuelve%',
  'la carta de despido no se escribe antes de resolver el procedimiento');

select fn_expediente_resolver(
  (select id from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion'),
  'archivado',
  'Los descargos acreditan que el marcaje lo hizo el terminal por duplicado.');

-- ── 13 · Un procedimiento archivado no se reabre con una carta (57.6 i) ────
select throws_like(
  $$ select fn_expediente_crear_despido(
       (select id from expediente_disciplinario
         where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion'),
       date '2026-11-05',
       'Se resuelve el despido pese al descargo presentado por la colaboradora.') $$,
  '%archivo no se reabre%',
  'un procedimiento archivado no produce una carta de despido');

set session_replication_role = replica;
update expediente_disciplinario
   set resuelto_resultado = 'despido'
 where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion';
set session_replication_role = origin;

-- ── 15 · Un cese antedatado no se escribe ──────────────────────────────────
-- Una fecha de cese anterior a hoy declara fuera del vínculo días que la
-- persona trabajó, y hace correr el plazo de impugnación del art. 36 de la
-- LPCL desde un día que no ocurrió.
select throws_like(
  $$ select fn_expediente_crear_despido(
       (select id from expediente_disciplinario
         where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion'),
       date '2026-10-01',
       'Se resuelve el despido pese al descargo presentado por la colaboradora.') $$,
  '%anterior a hoy%',
  'la fecha de cese no se antedata');

-- ── 16 · La causa se HEREDA: la carta no la recibe ─────────────────────────
-- Art. 57.7: «La causa expresada en la carta de imputación vincula a la carta
-- de despido y no puede modificarse». `fn_expediente_crear_despido` no tiene
-- parámetro de causa, así que no hay nada que pueda divergir.
select fn_expediente_crear_despido(
  (select id from expediente_disciplinario
    where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'imputacion'),
  date '2026-11-05',
  'Se resuelve el despido pese al descargo presentado por la colaboradora.');

select is(
  (select d.falta_numeral || d.falta_literal || ' / ' || i.correlativo || ' / '
          || to_char(d.fecha_cese, 'YYYY-MM-DD')
     from expediente_disciplinario d
     join expediente_disciplinario i on i.id = d.doc_previo_id
    where d.persona_id = '00000000-0000-0000-0000-0000000008a3' and d.nivel = 'despido'),
  '53.3a / LAB-IMP-458 / 2026-11-05',
  'la carta de despido hereda la causa y queda atada a su imputación');


-- ── 17 · Y no se le puede cambiar por una escritura directa ────────────────
-- El candado del molde de la casa (0261, 0295, 0342), cuarta instancia. Se
-- prueba con `service_role` y NO con `authenticated`: la tabla tiene RLS con
-- solo políticas de SELECT, así que un UPDATE desde `authenticated` no da
-- error — no alcanza ninguna fila, el trigger no llega a dispararse y la
-- aserción pasaría en falso.
set local role service_role;

select throws_like(
  $$ update expediente_disciplinario
        set falta_literal = 'b'
      where persona_id = '00000000-0000-0000-0000-0000000008a3' and nivel = 'despido' $$,
  '%no se cambian%',
  'la causa de una carta de despido no se cambia con un UPDATE directo');

select * from finish();
rollback;
