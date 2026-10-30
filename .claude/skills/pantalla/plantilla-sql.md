# Plantilla SQL — consulta de solo lectura para una pantalla

Se lee en el Paso 2 de `/pantalla`. Reemplaza `<TABLAS>` y `<FUNCIONES>` por las del mapa del código (`'a','b'`). Felipe la pega en el **SQL Editor de producción** (schema `public`) y pega el resultado. **Antes de entregarla, córrela en el Postgres local** (`docker exec supabase_db_cayla-dynamic psql -U postgres -c "…"`): una consulta con un error de sintaxis le hace perder el turno a Felipe. Nunca la guardes en `supabase/migrations/`.

## Reglas

- **Solo lectura.** Ni `insert`, `update`, `delete`, ni funciones que escriban.
- **Cero datos personales en el resultado que se va a pegar.** Nada de `select *` sobre `personas`, `contratos`, `documentos`, `boletas`: excluye o enmascara nombres, DNI, correos, sueldos por persona y fechas de ingreso. Prefiere conteos y agregados por sede/rol.
- Los bloques van **separados y numerados**, para que Felipe pegue el resultado de cada uno. Pídelos como **un solo JSON** (`select json_build_object(...)`) cuando se pueda: es el formato que Felipe ya pega.
- **El periodo de planilla va del 29 al 28**, no es mes calendario: léelo de `periodos_planilla`. En Trujillo se trabaja domingo.
- Después de recibir el resultado, clasifica cada dato como **hueco** (algo que falta o está roto) o **está bien** (con la evidencia); los dos van al análisis.

## A · Estructura

```sql
-- A1. Columnas
select table_name, ordinal_position, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name in (<TABLAS>)
order by table_name, ordinal_position;

-- A2. Constraints (PK, FK, UNIQUE, CHECK)
select conrelid::regclass::text as tabla, contype, conname, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conrelid in (
  select oid from pg_class
  where relnamespace = 'public'::regnamespace and relname in (<TABLAS>)
)
order by 1, 2, 3;

-- A3. Índices
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename in (<TABLAS>)
order by 1, 2;
```

## B · Volumen real

```sql
-- B1. Filas y crecimiento reciente (quita el filtro si la tabla no tiene created_at)
select 'tabla_1' as tabla, count(*) as filas,
       count(*) filter (where created_at > now() - interval '30 days') as ultimos_30_dias
from public.tabla_1
union all
select 'tabla_2', count(*),
       count(*) filter (where created_at > now() - interval '30 days')
from public.tabla_2;
```

## C · Seguridad y lógica

```sql
-- C1. Políticas RLS
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename in (<TABLAS>)
order by 1, 2;

-- C2. ¿RLS activado?
select relname, relrowsecurity, relforcerowsecurity
from pg_class
where relnamespace = 'public'::regnamespace and relkind = 'r' and relname in (<TABLAS>);

-- C3. Funciones que la pantalla llama: firma, security definer, longitud y md5 del cuerpo
--     (el md5 se compara con ./scripts/donde-vive.sh; si no coincide, mide ANTES de concluir:
--      comentarios, CRLF de Windows o una versión distinta — ver CLAUDE.md)
select p.proname, pg_get_function_identity_arguments(p.oid) as firma,
       p.prosecdef as security_definer, length(p.prosrc) as largo, md5(p.prosrc) as md5
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in (<FUNCIONES>)
order by 1, 2;
```

## D · Huecos

```sql
-- D1. Tablas de la pantalla SIN RLS activado (debería salir vacío)
select relname from pg_class
where relnamespace = 'public'::regnamespace and relkind = 'r'
  and relname in (<TABLAS>) and not relrowsecurity;

-- D2. Funciones security definer SIN search_path fijo (debería salir vacío)
select proname from pg_proc
where pronamespace = 'public'::regnamespace and prosecdef
  and proname in (<FUNCIONES>)
  and (proconfig is null or not exists (select 1 from unnest(proconfig) c where c like 'search_path=%'));

-- D3 y D4 los escribes a la medida de la pantalla:
--   D3. Columnas nullable que el código trata como obligatorias (conteo de NULL por columna).
--   D4. Valores de una columna de estado fuera del vocabulario que la pantalla espera
--       (select estado, count(*) from public.tabla group by 1).
--   Y, si la pantalla ordena por una columna de fecha con `limit 1` o `distinct on`,
--   cuántos empates reales hay (CLAUDE.md, sección «La red de seguridad», explica la
--   familia de pruebas que «van y vienen» por órdenes sin desempate).
```

Cierra tu mensaje con una línea: *"Pega aquí el resultado de A a D (o dime 'sin SQL' y sigo con el código, marcando lo que quede sin datos reales)."*
