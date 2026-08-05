-- ############################################################################
-- ####  SOLO LEE. No cambia nada. Se puede correr las veces que haga falta. ###
-- ############################################################################
--
-- revision_de_lo_aplicado.sql — ¿qué de lo del 4 y 5 de agosto está de verdad
-- en producción, y qué hay en el libro de desembolsos?
--
-- ES UNA SOLA CONSULTA A PROPÓSITO. La primera versión eran tres consultas
-- separadas y de las cuatro veces que se corrió llegó de vuelta solo la última:
-- el SQL Editor de Supabase abre un panel de resultados por sentencia, así que
-- copiar «el resultado» copia uno de tres. Con una sola sentencia hay un solo
-- panel y no hay forma de mandar media respuesta.
--
-- MIRA EL ESQUEMA, NO EL REGISTRO. `migraciones_aplicadas` es una lista escrita
-- a mano, y este proyecto ya se quemó con eso: la 0089 figuraba como aplicada y
-- su contenido nunca había llegado. Cada fila comprueba el EFECTO —que la
-- función tenga el candado, que la tabla tenga RLS— y al lado pone lo que dice
-- el registro. Si las dos columnas no coinciden, el registro miente.
-- ############################################################################

with revision(orden, seccion, detalle, esta, registro) as (

  -- ① ¿Está aplicado de verdad?
  select 1, '① APLICADO', '0138 · un día pagado ya no cambia de horas',
         case when (select prosrc from pg_proc where proname='fn_recalcular_jornada' limit 1)
                   ilike '%CANDADO DE PERIODO PAGADO%' then '✔ SI' else '✘ NO' end,
         case when exists (select 1 from migraciones_aplicadas where numero=138) then 'anotada' else 'SIN ANOTAR' end
  union all
  select 2, '① APLICADO', '0147 · quién firma por CAYLA está guardado',
         case when exists (select 1 from configuracion where clave='firmante_empresa') then '✔ SI' else '✘ NO' end,
         case when exists (select 1 from migraciones_aplicadas where numero=147) then 'anotada' else 'SIN ANOTAR' end
  union all
  select 3, '① APLICADO', '0147b · y el firmante no puede ser cualquiera',
         case when exists (select 1 from pg_trigger where tgname='trg_valida_firmante_empresa') then '✔ SI' else '✘ NO' end,
         '—'
  union all
  select 4, '① APLICADO', '0148 · un borrador de memo no sale firmado',
         case when (select prosrc from pg_proc where proname='fn_firma_de_memo' limit 1)
                   ilike '%firmado_at is not null%' then '✔ SI' else '✘ NO' end,
         case when exists (select 1 from migraciones_aplicadas where numero=148) then 'anotada' else 'SIN ANOTAR' end
  union all
  select 5, '① APLICADO', '0151 · el tope de educación, bajo llave',
         case when (select relrowsecurity from pg_class where relname='topes_educacion_rango') then '✔ SI' else '✘ NO' end,
         case when exists (select 1 from migraciones_aplicadas where numero=151) then 'anotada' else 'SIN ANOTAR' end
  union all
  select 6, '① APLICADO', '0151b · y el candado del tope sigue viéndolo',
         case when (select prosecdef from pg_proc where proname='fn_educacion_respeta_el_tope' limit 1) then '✔ SI' else '✘ NO' end,
         '—'
  union all
  select 7, '① APLICADO', '0153 · el libro de desembolsos, bajo llave',
         case when (select relrowsecurity from pg_class where relname='desembolsos_beneficios') then '✔ SI' else '✘ NO' end,
         case when exists (select 1 from migraciones_aplicadas where numero=153) then 'anotada' else 'SIN ANOTAR' end
  union all
  select 8, '① APLICADO', '0153b · y nadie con login puede escribirlo',
         case when (select count(*) from information_schema.role_table_grants
                     where table_name='desembolsos_beneficios' and grantee in ('authenticated','anon')
                       and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')) = 0
              then '✔ SI' else '✘ NO' end,
         case when exists (select 1 from migraciones_aplicadas where numero=155) then 'anotada' else 'SIN ANOTAR' end

  -- ② Qué hay en el libro. Sin nombres: para decidir si las provisiones deben
  -- descontarlo basta saber qué ventanas y de qué años están registradas.
  union all
  select 20, '② EL LIBRO',
         d.ventana || ' ' || d.anio || '  ·  por ' || d.origen,
         count(*) || ' fila(s) · S/ ' || to_char(sum(d.monto), 'FM999999.00'),
         'pagado entre ' || min(d.fecha_pago) || ' y ' || max(d.fecha_pago)
  from desembolsos_beneficios d
  group by d.ventana, d.anio, d.origen

  -- ③ El tamaño del asunto.
  union all
  select 30, '③ ALCANCE', 'personas con algún desembolso registrado',
         (select count(distinct persona_id)::text from desembolsos_beneficios),
         'de ' || (select count(*)::text from personas where estado='activo') || ' activas'
)
select seccion, detalle, esta as valor, registro as nota
from revision
order by orden, detalle;
