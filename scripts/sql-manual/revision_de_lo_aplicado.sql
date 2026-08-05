-- ############################################################################
-- ####  SOLO LEE. No cambia nada. Se puede correr las veces que haga falta. ###
-- ############################################################################
--
-- revision_de_lo_aplicado.sql — ¿qué de lo del 4 y 5 de agosto está de verdad
-- en producción?
--
-- MIRA EL ESQUEMA, NO EL REGISTRO. `migraciones_aplicadas` es una lista que se
-- escribe a mano, y este proyecto ya se quemó con eso: la 0089 figuraba como
-- aplicada y su contenido nunca había llegado. Así que cada fila de abajo
-- comprueba el EFECTO —que la función tenga el candado, que la tabla tenga
-- RLS— y al lado pone lo que dice el registro. Si las dos columnas no
-- coinciden, el registro está mintiendo.
-- ############################################################################

select '① EL EFECTO REAL, comprobado en el esquema' as revision;

select '0138 · un día pagado ya no cambia de horas' as que_deberia_estar,
       case when (select prosrc from pg_proc where proname='fn_recalcular_jornada' limit 1)
                 ilike '%CANDADO DE PERIODO PAGADO%' then '✔ SÍ' else '✘ NO' end as en_el_esquema,
       case when exists (select 1 from migraciones_aplicadas where numero=138)
            then 'anotada' else 'sin anotar' end as dice_el_registro
union all
select '0147 · quién firma por CAYLA está guardado',
       case when exists (select 1 from configuracion where clave='firmante_empresa')
            then '✔ SÍ' else '✘ NO' end,
       case when exists (select 1 from migraciones_aplicadas where numero=147) then 'anotada' else 'sin anotar' end
union all
select '0147b · y no se puede apuntar a cualquiera',
       case when exists (select 1 from pg_trigger where tgname='trg_valida_firmante_empresa')
            then '✔ SÍ' else '✘ NO' end,
       '—'
union all
select '0148 · un borrador de memo no sale firmado',
       case when (select prosrc from pg_proc where proname='fn_firma_de_memo' limit 1)
                 ilike '%firmado_at is not null%' then '✔ SÍ' else '✘ NO' end,
       case when exists (select 1 from migraciones_aplicadas where numero=148) then 'anotada' else 'sin anotar' end
union all
select '0151 · el tope de educación, bajo llave',
       case when (select relrowsecurity from pg_class where relname='topes_educacion_rango')
            then '✔ SÍ' else '✘ NO' end,
       case when exists (select 1 from migraciones_aplicadas where numero=151) then 'anotada' else 'sin anotar' end
union all
select '0151b · y el candado del tope sigue viéndolo',
       case when (select prosecdef from pg_proc where proname='fn_educacion_respeta_el_tope' limit 1)
            then '✔ SÍ' else '✘ NO' end,
       '—'
union all
select '0153 · el libro de desembolsos, bajo llave',
       case when (select relrowsecurity from pg_class where relname='desembolsos_beneficios')
            then '✔ SÍ' else '✘ NO' end,
       case when exists (select 1 from migraciones_aplicadas where numero=153) then 'anotada' else 'sin anotar' end
union all
select '0153b · y nadie con login puede escribirlo',
       case when (select count(*) from information_schema.role_table_grants
                   where table_name='desembolsos_beneficios' and grantee in ('authenticated','anon')
                     and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')) = 0
            then '✔ SÍ' else '✘ NO' end,
       case when exists (select 1 from migraciones_aplicadas where numero=155) then 'anotada' else 'sin anotar' end;


-- ── ② Qué hay en el libro de desembolsos ───────────────────────────────────
-- SIN NOMBRES a propósito: para decidir si las provisiones deben descontarlo
-- basta saber QUÉ ventanas y de qué años están registradas. Los nombres son
-- datos personales y no hacen falta para esta decisión.
select '② LAS 5 FILAS DEL LIBRO, sin nombres' as revision;

select ventana, anio, origen,
       count(*)   as cuantas,
       sum(monto) as total,
       min(fecha_pago) as primer_pago,
       max(fecha_pago) as ultimo_pago
from desembolsos_beneficios
group by ventana, anio, origen
order by anio, ventana;


-- ── ③ ¿Coinciden con lo que el sistema cree que debe? ──────────────────────
-- La pregunta que decide si hay que conectar las dos cosas. Si acá salen
-- personas con desembolso registrado, esas son por las que hay que preguntar:
-- ¿las provisiones ya las descuentan por otro lado, o las están contando dos
-- veces?
select '③ CUÁNTAS PERSONAS DISTINTAS TIENEN DESEMBOLSO REGISTRADO' as revision;

select count(distinct persona_id) as personas_con_desembolso,
       (select count(*) from personas where estado='activo') as personas_activas
from desembolsos_beneficios;
