-- ############################################################################
-- ####  ESTE ES EL ARCHIVO QUE SE PEGA EN EL SQL EDITOR DE SUPABASE.      ####
-- ####  Ningún otro. Los de `supabase/tests/` NO se pegan nunca.          ####
-- ############################################################################
--
-- aplicar_0153.sql — La tabla de desembolsos, bajo llave
--
-- CÓMO SE USA
--   1. Copia TODO este archivo y pégalo en el SQL Editor.
--   2. Run.
--   3. Abajo salen cinco comprobaciones. Las cinco tienen que decir OK.
--
-- QUÉ HACE, en una línea
--   `desembolsos_beneficios` —el libro de a quién se le pagó qué CTS o qué
--   gratificación— estaba en producción sin ninguna protección, con los mismos
--   permisos que una tabla recién creada. Esto la deja como el resto de las
--   tablas que mueven plata: se lee con permiso, se escribe por migración.
--
-- QUÉ **NO** HACE
--   No borra ni mueve ni una fila. No cambia ninguna columna. Solo permisos.
--
-- SE PUEDE CORRER DOS VECES SIN PROBLEMA.
--
-- Fuente: supabase/migrations/0153_la_tabla_de_desembolsos_bajo_llave.sql
-- ############################################################################

begin;

-- ============================================================================
-- 0153 — La tabla de desembolsos, bajo llave
-- ============================================================================
--
-- QUÉ PROMETE
--   Si `desembolsos_beneficios` existe en esta base, queda con RLS activo, sin
--   permiso de escritura para ninguna sesión de la aplicación, y legible solo
--   por admin o líder de DO. Si no existe, esta migración no hace nada y lo
--   dice en voz alta.
--
-- QUÉ ASUME
--   · Nada de la aplicación escribe en esa tabla. Comprobado el 2026-08-05:
--     cero coincidencias de `desembolsos_beneficios` en todo el repositorio, en
--     las nueve ramas y en la historia completa de commits. Si mañana alguna
--     pantalla la necesita, escribirá por una función `security definer`, como
--     el resto del sistema.
--   · `fn_es_admin_o_lider()` no devuelve null desde la 0078.
--
-- DE DÓNDE SALE ESTA MIGRACIÓN
--   Del comparador `comparar_funciones.sql`, corrido contra producción el
--   2026-08-05. Reportó siete candados que «sobran en produccion»: todos de una
--   tabla llamada `desembolsos_beneficios` que el repositorio no conoce.
--
--   Sus columnas —persona_id, ventana, anio, monto, fecha_pago, origen, nota,
--   registrado_por— dicen lo que es: el libro de a quién se le pagó qué
--   beneficio, de qué ventana y de qué año. CTS de mayo, gratificación de
--   julio. Alguien la creó a mano en el SQL Editor y nunca llegó al repositorio.
--
--   Y sus permisos son, letra por letra, los de una tabla recién creada sin
--   proteger: `anon` con REFERENCES, TRIGGER y TRUNCATE; `authenticated` con
--   DELETE, INSERT, SELECT, TRUNCATE y UPDATE. Comparado contra una tabla nueva
--   en blanco y contra `tasas_pension`, que sí está protegida (0115) y solo
--   concede SELECT.
--
-- POR QUÉ ESTO VA PRIMERO, Y SEPARADO DE DESCRIBIRLA
--   Faltan dos datos que solo se leen en producción: si la tabla tiene RLS y
--   cuántas filas guarda. Sin ellos no se puede escribir un `create table` fiel,
--   y escribir uno inventado sería peor que no tener ninguno.
--
--   Pero proteger no necesita saber nada de eso. Se separa a propósito: esta
--   migración cierra la puerta hoy; la siguiente describirá la tabla cuando se
--   conozca su forma exacta. Dos promesas, dos archivos, dos reversas.
--
-- POR QUÉ LLEVA GUARDA
--   La base local y la de GitHub se construyen desde cero aplicando todas las
--   migraciones, y ahí esa tabla NO existe. Un `alter table` a secas rompería
--   las pruebas de todo el mundo. Con la guarda, la migración es correcta en las
--   dos realidades — y el aviso deja constancia de en cuál se aplicó.
--
-- CÓMO SE REVIERTE
--   alter table desembolsos_beneficios disable row level security;
--   drop policy if exists desembolsos_lectura_admin on desembolsos_beneficios;
--   grant select, insert, update, delete on desembolsos_beneficios to authenticated;
--   No toca ni una fila de datos.
-- ============================================================================

do $mig$
begin
  if to_regclass('public.desembolsos_beneficios') is null then
    raise notice
      '0153: `desembolsos_beneficios` no existe en esta base — nada que proteger. '
      'Es lo esperado en el laboratorio y en GitHub: la tabla solo está en producción.';
    return;
  end if;

  -- Mismo tratamiento que la 0115 le dio a `tasas_pension` y la 0151 a
  -- `topes_educacion_rango`. Tres tablas, un solo criterio: lo que mueve plata
  -- se lee con permiso y se escribe por migración.
  execute 'alter table desembolsos_beneficios enable row level security';
  execute 'revoke all on desembolsos_beneficios from authenticated, anon';
  execute 'drop policy if exists desembolsos_lectura_admin on desembolsos_beneficios';
  execute $pol$
    create policy desembolsos_lectura_admin on desembolsos_beneficios
      for select using (fn_es_admin_o_lider())
  $pol$;
  execute 'grant select on desembolsos_beneficios to authenticated';

  execute $com$
    comment on table desembolsos_beneficios is
      'Libro de beneficios desembolsados (CTS, gratificación): a quién, de qué ventana '
      'y de qué año, cuánto y cuándo. Creada a mano en producción antes de la 0153 y '
      'ausente del repositorio hasta entonces. Solo lectura para admin o líder de DO; '
      'la escritura va por migración. Ninguna pantalla la usa todavía.'
  $com$;

  raise notice '0153: `desembolsos_beneficios` protegida — RLS activo, sin escritura desde la aplicación.';
end
$mig$;

insert into migraciones_aplicadas (numero, nombre)
values (153, 'la_tabla_de_desembolsos_bajo_llave')
on conflict (numero) do nothing;

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
select 'La tabla existe en esta base' as comprobacion,
       case when to_regclass('public.desembolsos_beneficios') is not null
            then 'OK' else 'REVISAR — ¿la borraron?' end as resultado
union all
select 'Tiene RLS activo',
       case when (select relrowsecurity from pg_class where relname='desembolsos_beneficios')
            then 'OK' else 'REVISAR' end
union all
select 'Ninguna sesión puede escribirla',
       case when (select count(*) from information_schema.role_table_grants
                   where table_name='desembolsos_beneficios' and grantee='authenticated'
                     and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')) = 0
            then 'OK' else 'REVISAR' end
union all
select 'Sin sesión no se ve nada',
       case when (select count(*) from information_schema.role_table_grants
                   where table_name='desembolsos_beneficios' and grantee='anon') = 0
            then 'OK' else 'REVISAR' end
union all
select 'Quedó anotada como aplicada',
       case when exists (select 1 from migraciones_aplicadas where numero = 153)
            then 'OK' else 'REVISAR' end;

commit;

-- ############################################################################
-- Lo de abajo va DESPUÉS del commit a propósito: son consultas de lectura para
-- la migración siguiente, y si alguna fallara dentro de la transacción se
-- llevaría por delante la protección que acaba de aplicarse. Ya está guardada.
-- ############################################################################

-- Y lo que hace falta para la migración SIGUIENTE, la que va a describir la
-- tabla en el repositorio. Mándame estas dos tablas junto con las comprobaciones.
select 'CUÁNTAS FILAS TIENE' as dato;
select count(*) as filas from desembolsos_beneficios;

select 'SU FORMA EXACTA' as dato;
select column_name as columna, data_type as tipo,
       coalesce(character_maximum_length::text, numeric_precision || ',' || numeric_scale, '—') as tamano,
       is_nullable as acepta_nulo, coalesce(column_default, '—') as por_defecto
from information_schema.columns
where table_name = 'desembolsos_beneficios' order by ordinal_position;

select 'SUS REGLAS' as dato;
select con.conname as regla, pg_get_constraintdef(con.oid) as definicion
from pg_constraint con join pg_class c on c.oid = con.conrelid
where c.relname = 'desembolsos_beneficios' order by 1;
