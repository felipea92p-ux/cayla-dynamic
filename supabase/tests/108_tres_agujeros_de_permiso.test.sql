-- ============================================================================
-- 108_tres_agujeros_de_permiso.test.sql
-- ============================================================================
-- Los tres hallazgos que cerró la 0129, cada uno con la prueba que habría
-- impedido que existieran.
--
-- A · Cualquier sesión con login podía meter vacaciones por otra persona. La
--     0101 decía por escrito que el INSERT no se concedía a authenticated, y no
--     lo conseguía: «revoke all … from anon, public» no quita lo concedido al rol
--     authenticated, y el trigger «instead of insert» es SECURITY DEFINER y no
--     comprobaba nada. Se le quemaba el saldo de vacaciones a cualquiera.
--
-- B · Las cuatro funciones de liquidación entregaban el sueldo de un colega a
--     cualquiera con login. Mismo agujero que la 0090 cerró para
--     fn_planilla_calcular; estas quedaron fuera y la prueba 91 no las miraba.
--
-- C · Anular una marca rompía el cierre del día. La 0082 puso el filtro de
--     anuladas en dos de las tres consultas de fn_siguiente_tipo_esperado.
--
-- La lección común a los tres: un `revoke` documenta una intención, un `grant`
-- concede, y solo un GUARD DENTRO de la función garantiza. Los tres agujeros
-- existían mientras el comentario del archivo decía que no.
-- ============================================================================
begin;
select plan(7);

-- ── A · Las vistas de ausencias ──────────────────────────────────────────────
select ok(
  not has_table_privilege('authenticated', 'vacaciones', 'INSERT'),
  'authenticated NO puede insertar en la vista vacaciones');

select ok(
  not has_table_privilege('authenticated', 'justificaciones_asistencia', 'INSERT'),
  'authenticated NO puede insertar en la vista justificaciones_asistencia');

-- El cinturón: aunque alguien vuelva a conceder el privilegio, el trigger frena.
select ok(
  (select prosrc from pg_proc where proname = 'fn_trg_vacaciones_insert')
    like '%fn_es_admin_o_lider() is not true%',
  'el trigger de vacaciones tiene su guard adentro, no solo el revoke');

-- ── B · Las cuatro funciones de liquidación ──────────────────────────────────
select is(
  (select coalesce(string_agg(proname, ', ' order by proname), '')
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and proname in ('fn_remuneracion_computable','fn_grati_trunca',
                     'fn_cts_trunca','fn_vacaciones_truncas')
     and prosrc not like '%fn_es_admin_o_lider() is not true%'),
  '',
  'las cuatro funciones de liquidación comprueban permiso antes de entregar montos');

-- Y la prueba de comportamiento: una sesión sin fila en personas no obtiene nada.
select throws_ok($$
  select set_config('request.jwt.claim.sub','99999999-9999-9999-9999-999999999999', true);
  select fn_remuneracion_computable((select id from personas limit 1), '2026-08-31');
$$, 'P0001',
   'Solo un administrador o líder puede ver la liquidación de una persona.',
   'una sesión ajena no puede leer la remuneración de nadie');

-- ── C · La última marca del día ignora las anuladas ─────────────────────────
-- ⚠️ El patrón tiene que acotarse a ESA consulta. La primera versión de esta
-- prueba usaba «like '%anulada_at is null%order by timestamp_marca desc%'» y
-- pasaba igual con el agujero puesto: el `like` cruzaba dos consultas distintas y
-- casaba con el filtro de la anterior. Se descubrió corriendo la prueba contra el
-- código roto — que es la única forma de saber si una prueba sirve.
select ok(
  (select prosrc from pg_proc where proname = 'fn_siguiente_tipo_esperado')
    ~ 'into v_ultimo[^;]*anulada_at is null[^;]*order by timestamp_marca desc',
  'la consulta de la última marca del día filtra las anuladas');

-- Y el comportamiento: con la salida a almuerzo anulada, el sistema deja de
-- pedir el retorno de un almuerzo que ya no existe. Ese era el caso que dejaba
-- a la persona sin poder cerrar su día — y el espejo, que pagaba el refrigerio.
select lives_ok($$
  do $prueba$
  declare
    v_p uuid; v_sede uuid; v_admin uuid; v_marca uuid; v_c1 text; v_c2 text;
  begin
    select id into v_admin from personas where rol = 'admin' limit 1;
    select id, sede_base_id into v_p, v_sede
      from personas where estado = 'activo' and (v_admin is null or id <> v_admin) limit 1;
    if v_p is null or v_admin is null then return; end if;   -- base sin datos

    insert into marcajes (persona_id, sede_id, tipo, timestamp_marca, origen, client_uuid)
    values (v_p, v_sede, 'entrada', '2026-08-02 08:00:00-05', 'terminal', gen_random_uuid());
    insert into marcajes (persona_id, sede_id, tipo, timestamp_marca, origen, client_uuid)
    values (v_p, v_sede, 'salida_almuerzo', '2026-08-02 13:00:00-05', 'terminal', gen_random_uuid())
    returning id into v_marca;

    v_c1 := coalesce(fn_siguiente_tipo_esperado(v_p, '2026-08-02')::text, 'null');
    if v_c1 <> 'retorno_almuerzo' then
      raise exception 'Con la salida a almuerzo viva se esperaba retorno_almuerzo, no %', v_c1;
    end if;

    update marcajes
       set anulada_at = now(), anulada_por = v_admin,
           anulada_motivo = 'prueba 108: anulada a proposito'
     where id = v_marca;

    v_c2 := coalesce(fn_siguiente_tipo_esperado(v_p, '2026-08-02')::text, 'null');
    if v_c2 = 'retorno_almuerzo' then
      raise exception 'Con la salida ANULADA sigue pidiendo retorno_almuerzo: '
        'la persona no puede cerrar su dia y el auto-cierre le inventara la hora.';
    end if;
  end
  $prueba$;
$$, 'con la salida a almuerzo anulada, el día se puede cerrar');

select * from finish();
rollback;
