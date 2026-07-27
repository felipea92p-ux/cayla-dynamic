-- ============================================================================
-- Corrige el registro de migraciones tras renumerar la 0085/0086 a 0088/0089
-- ============================================================================
-- QUÉ PASÓ. Dos migraciones se escribieron con números que ya estaban usados
-- (0085_tipo_de_vinculo y 0086_fecha_de_cese existían antes). Se renumeraron los
-- archivos a 0088 y 0089, pero en producción ya estaban APLICADAS con los
-- números viejos — y como el registro usa `on conflict (numero) do nothing` y
-- `numero` es la clave, aquellos inserts no llegaron a escribir nada.
--
-- Resultado: la base tiene los cambios puestos, pero el registro no lo dice.
-- Este script solo arregla el registro. NO toca ninguna función ni ningún dato.
--
-- CÓMO SABER SI HACE FALTA: si esta consulta devuelve filas, sí.
--   select numero, nombre from migraciones_aplicadas where numero between 85 and 89;
--   Si salen 85=tipo_de_vinculo y 86=fecha_de_cese pero NO salen 88 ni 89,
--   estás en el caso que este script corrige.
-- ============================================================================

-- 1) Comprobar antes de tocar nada: ¿están de verdad aplicadas?
--    Las dos condiciones tienen que dar `true`.
select
  (select count(*) = 1 from pg_proc p
     where p.proname = 'fn_grati_cts_periodo'
       and pg_get_functiondef(p.oid) like '%generate_series(extract(year from v_ini)%')
    as la_0088_esta_aplicada,
  (select count(*) = 1 from pg_proc p
     where p.proname = 'fn_reactivar_marcaje'
       and pg_get_functiondef(p.oid) like '%ya tiene otra salida final activa%')
    as la_0089_esta_aplicada;

-- 2) Si las dos dieron true, registrar. Si alguna dio false, NO sigas: esa
--    migración no está puesta y hay que aplicarla primero desde
--    supabase/migrations/.
insert into migraciones_aplicadas (numero, nombre) values
  (88, 'grati_en_periodos_que_cruzan_el_ano'),
  (89, 'lo_que_encontro_la_auditoria_del_26')
on conflict (numero) do nothing;

-- 3) Cómo debe quedar: 84, 85, 86, 87, 88, 89 — sin huecos ni repeticiones.
select numero, nombre, to_char(aplicada_at, 'DD/MM HH24:MI') as aplicada
from migraciones_aplicadas
where numero >= 84
order by numero;
