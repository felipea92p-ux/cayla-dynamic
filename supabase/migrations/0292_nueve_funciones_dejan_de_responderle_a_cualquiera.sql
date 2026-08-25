-- ============================================================================
-- 0292 · NUEVE FUNCIONES DEJAN DE RESPONDERLE A CUALQUIERA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que nueve funciones auxiliares —pensadas para que otras funciones las
--   usaran por dentro— dejen de poder llamarse directo desde el navegador con
--   el id de OTRA persona. Hoy cualquiera de las ~30 cuentas del sistema
--   puede pedir por RPC directo la banda salarial, la suspensión vigente o
--   las fechas exactas de las faltas de cualquier compañera.
--
-- EL DEFECTO, EN UNA LÍNEA
--   Las nueve son `SECURITY DEFINER` (corren como `postgres`, sin RLS),
--   reciben un `p_persona_id` que manda quien llama, no preguntan quién es
--   quien pregunta, y tienen `grant execute … to authenticated`. El esquema
--   `public` está expuesto en la Data API, así que se llaman con un POST a
--   `/rest/v1/rpc/<nombre>` usando la sesión propia — no hace falta ser admin
--   ni encargada, alcanza con tener una cuenta.
--
-- LAS NUEVE, Y POR QUÉ NO SE TOCA SU CUERPO
--   fn_falta_contadores · fn_tardanza_escalon · fn_dia_suspendido ·
--   fn_dias_suspension · fn_beneficio_ya_depositado · fn_educacion_monto ·
--   fn_es_dia_laborable · fn_reglamento_no_acusado · fn_dcs_por_que_no_compensa
--
--   Ninguna la llama el panel por `rpc()` — verificado con grep sobre
--   `apps/web`: los únicos hits son comentarios. Son piezas internas que usan
--   otras funciones, y esas otras SÍ tienen guard (`fn_es_admin_o_lider()`,
--   comparación contra `fn_persona_actual_id()`, etc.) antes de llamarlas.
--   El defecto no está en lo que calculan: está en que además de responderle
--   a su envoltorio con guard, le responden a cualquiera que las llame directo.
--
-- POR QUÉ EL ARREGLO NO ROMPE A QUIEN SÍ DEBE SEGUIR FUNCIONANDO
--   Una función `SECURITY DEFINER` que llama a otra lo hace como SU DUEÑO
--   (`postgres`), no como el rol de quien originó la petición. `revoke
--   execute … from authenticated` cierra el POST directo y no toca en
--   absoluto las llamadas internas, que nunca pasaron por el permiso de
--   `authenticated` para empezar. Se comprobó uno por uno, antes de escribir
--   esta migración, quién llama a cada una por dentro:
--
--     fn_falta_contadores        ← fn_expediente_generar_falta
--     fn_tardanza_escalon        ← fn_expediente_generar_tardanza, fn_tardanzas_resumen
--     fn_dia_suspendido          ← fn_falta_contadores, fn_faltas, fn_faltas_resumen
--     fn_dias_suspension         ← fn_expediente_generar_tardanza, fn_expediente_set_suspension
--     fn_beneficio_ya_depositado ← fn_cts_trunca, fn_grati_trunca, fn_provisiones, fn_vacaciones_truncas
--     fn_educacion_monto         ← fn_educacion_registrar
--     fn_es_dia_laborable        ← fn_dias_suspension
--     fn_reglamento_no_acusado   ← fn_expediente_comunicar_cargos, fn_expediente_declarar_cargos_comunicados,
--                                   fn_expediente_firmar, fn_sin_constancia_del_reglamento
--     fn_dcs_por_que_no_compensa ← fn_dcs_validar_dia_laborable, fn_feriados_laborados
--
-- QUÉ NO SE TOCA
--   `execute` de `postgres` y de `service_role` sigue igual — esta migración
--   solo quita el permiso de `authenticated`. Ninguna firma cambia, ningún
--   cuerpo se reescribe: es puro `revoke`, sin `create or replace`.
--
-- CÓMO SE REVIERTE
--   `grant execute on function <nombre>(<firma>) to authenticated;` en cada
--   una — las firmas exactas están en el `select` de comprobación de abajo.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final. Y que el panel siga funcionando igual: nada de lo
--   que usa el panel llama a estas nueve directo.
-- ============================================================================

revoke execute on function fn_falta_contadores(uuid, date) from authenticated;
revoke execute on function fn_tardanza_escalon(uuid) from authenticated;
revoke execute on function fn_dia_suspendido(uuid, date) from authenticated;
revoke execute on function fn_dias_suspension(uuid, date, integer) from authenticated;
revoke execute on function fn_beneficio_ya_depositado(uuid, text, integer) from authenticated;
revoke execute on function fn_educacion_monto(uuid, numeric, date, date, uuid) from authenticated;
revoke execute on function fn_es_dia_laborable(uuid, date) from authenticated;
revoke execute on function fn_reglamento_no_acusado(uuid, date) from authenticated;
revoke execute on function fn_dcs_por_que_no_compensa(uuid, date, date) from authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (292, '0292_nueve_funciones_dejan_de_responderle_a_cualquiera')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as firma,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as sigue_ejecutable_por_authenticated
from pg_proc p
where p.proname in (
  'fn_falta_contadores','fn_tardanza_escalon','fn_dia_suspendido',
  'fn_dias_suspension','fn_beneficio_ya_depositado','fn_educacion_monto',
  'fn_es_dia_laborable','fn_reglamento_no_acusado','fn_dcs_por_que_no_compensa'
)
order by 1;
