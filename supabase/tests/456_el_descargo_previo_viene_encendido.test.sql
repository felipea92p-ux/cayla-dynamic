-- ============================================================================
-- 456 — El descargo previo viene encendido (migración 0566)
-- ============================================================================
--
-- Esta prueba es distinta de la 205 en algo que importa: la 205 FIJA la política
-- en cada caso para comprobar que la función la obedece en los dos sentidos.
-- Esta no la toca. Lo que verifica es la DECISIÓN: que el sistema, tal como sale
-- de las migraciones, exige el descargo previo del art. 55.2 del RIT.
--
-- Hace falta porque desde el 17-08-2026 salía al revés (0267, política en false)
-- y un memo firmado así no sirve de escalón para el art. 25 h) de la LPCL. Si
-- alguien vuelve a apagarla sin decidirlo, esta prueba se pone roja.
--
-- Y deja escrito el recorrido, que son TRES puertas antes de firmar y no una:
-- comunicar cargos → esperar el plazo → valorar el descargo por escrito. Son
-- las cuatro etapas que la pantalla ya dibuja (`etapaDelBorrador`), y conviene
-- que una prueba las fije: al encender la política, un memo que antes se firmaba
-- de un clic pasa a pedir tres pasos, y quien no lo sepa lo leerá como una
-- avería.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000009a1', 'ZZDP', 'Sede de laboratorio DP', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('ee000000-0000-0000-0000-0000000009af',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.dp@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-0000000009a2', 'DpAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000009a1', 'admin', 'x',
        'ee000000-0000-0000-0000-0000000009af', '2024-01-01', 'activo'),
       ('00000000-0000-0000-0000-0000000009a3', 'DpSancionada', 'Lab',
        '00000000-0000-0000-0000-0000000009a1', 'integrante', 'x', null, '2024-01-01', 'activo');

-- Cuatro borradores idénticos, uno por cada puerta del recorrido.
-- Los hechos van con fechas de 2025 para que el guard del numeral 60.5 no se
-- meta en medio, igual que en la 205.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, creado_por)
select v.id, '00000000-0000-0000-0000-0000000009a3', 'tardanza', 'amonestacion', 'borrador',
       date '2025-02-03', date '2025-02-08',
       '[{"fecha":"2025-02-05","minutos":17}]'::jsonb, '00000000-0000-0000-0000-0000000009a2'
from (values
  ('00000000-0000-0000-0000-0000000009b1'::uuid),   -- sin cargos comunicados
  ('00000000-0000-0000-0000-0000000009b2'::uuid),   -- cargos comunicados, plazo vivo
  ('00000000-0000-0000-0000-0000000009b3'::uuid),   -- plazo vencido, descargo sin valorar
  ('00000000-0000-0000-0000-0000000009b4'::uuid)    -- el recorrido completo
) as v(id);
set session_replication_role = origin;

-- ── El escenario, completo, antes de bajar a `authenticated` ────────────────
-- `session_replication_role` solo lo puede tocar un superusuario, así que todo
-- lo que mueve filas a mano va aquí arriba. El jwt ya está puesto: las
-- funciones del expediente leen de ahí quién actúa, no del rol de conexión.
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000009af","role":"authenticated"}';

-- b2 se queda con el plazo vivo. b3 y b4 lo tienen vencido.
select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-0000000009b2', 2, null);
select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-0000000009b3', 2, null);
select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-0000000009b4', 2, null);

set session_replication_role = replica;
-- Las dos fechas se mueven juntas: `chk_descargo_coherente` exige que el
-- vencimiento sea POSTERIOR a la comunicación, y tiene razón.
update expediente_disciplinario
   set cargos_comunicados_at = now() - interval '10 days',
       descargo_vence_at     = now() - interval '1 day'
 where id in ('00000000-0000-0000-0000-0000000009b3', '00000000-0000-0000-0000-0000000009b4');
set session_replication_role = origin;

-- Y solo a b4 se le valora el descargo: es el que recorre las tres puertas.
select fn_expediente_valorar_descargo('00000000-0000-0000-0000-0000000009b4', 'sin_descargo', null);

set local role authenticated;

-- ── 1 · La política sale encendida ──────────────────────────────────────────
select is(
  (select valor from configuracion where clave = 'disciplina_descargo_previo'),
  'true'::jsonb,
  'el sistema sale exigiendo el descargo previo del art. 55.2');

-- ── 2 · Primera puerta: sin cargos comunicados ──────────────────────────────
-- El caso que DEBE bloquear. Es la prueba de que el encendido llega hasta la
-- firma y no se queda en una fila de configuración que nadie lee.
select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000009b1') $$,
  '%comunicar los cargos%',
  'sin cargos comunicados no se firma');

-- ── 3 · Segunda puerta: el plazo todavía corre ──────────────────────────────
select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000009b2') $$,
  '%plazo de descargo vence%',
  'firmar antes de que venza el plazo invalidaría la sanción');

-- ── 4 · Tercera puerta: el plazo venció, pero nadie valoró el descargo ──────
-- La que menos se espera, y la que la pantalla resuelve con su etapa «valorar».
select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000009b3') $$,
  '%valorar por escrito el descargo%',
  'con el plazo vencido pero sin valorar el descargo, tampoco se firma');

-- ── 5 · El recorrido completo sí firma ──────────────────────────────────────
-- Un freno que lo frena todo no es un freno: es una pared.
select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000009b4') $$,
  'comunicados los cargos, vencido el plazo y valorado el descargo, la amonestación se firma');

select * from finish();
rollback;
