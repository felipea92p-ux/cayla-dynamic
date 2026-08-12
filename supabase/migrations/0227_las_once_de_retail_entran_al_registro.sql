-- ============================================================================
-- 0227 — Las once migraciones de retail entran al registro
-- ============================================================================
--
-- QUÉ PROMETE
--   Después de esta migración, `migraciones_aplicadas` incluye las once que
--   crearon el schema `retail` en esta base. La consulta de
--   `./scripts/que-falta-pegar.sh` vuelve a poder leerse literal: lo que diga
--   «FALTA PEGAR» falta de verdad.
--
-- QUÉ ASUME
--   Que las 0216 a 0226 ya corrieron en esta base. Es cierto en producción: se
--   pegaron el 2026-07-23 desde el repositorio `cayla-retail`, y sobre ellas
--   opera hoy `cayla-retail.vercel.app`. La comprobación del final mide cada
--   una contra el objeto que deja, y avisa si alguna no está.
--
-- POR QUÉ EXISTE, Y POR QUÉ ES URGENTE QUE EXISTA
--   El 2026-07-23 el ERP de tiendas se mudó a esta base, en su propio schema
--   (`retail`), para dejar de tener sedes y personas duplicadas en dos
--   proyectos. La mudanza se hizo bien y funciona. Lo que no se hizo fue
--   registrarla acá: los once scripts vivían solo en `cayla-retail`, y este
--   historial —que es el que describe esta base— no sabía que el cajón existe.
--
--   El costo era concreto: quien reconstruyera la base desde
--   `supabase/migrations` habría obtenido asistencia y planilla completas, y
--   ningún ERP de tiendas. Sin ningún error, sin ninguna alarma. Y en el otro
--   sentido, el aparato de control de este repo (el registro, la consulta de qué
--   falta pegar, la auditoría de huecos) era ciego a un tercio de lo que la base
--   realmente tiene.
--
--   Ahora los once archivos están en `supabase/migrations` (0216-0226, con su
--   procedencia en la cabecera) y esta migración los anota.
--
-- POR QUÉ EL INSERT VA ACÁ Y NO DENTRO DE CADA UNA
--   Mismo criterio que la 0146. A una migración ya aplicada no se le cambia el
--   cuerpo: si se le agrega el insert, el archivo del repositorio deja de ser lo
--   que se pegó, que es justo la divergencia que esto viene a cerrar. Las once
--   entran tal cual se corrieron; el registro se arregla desde afuera.
--
--   Con una excepción declarada, la 0217. Ese paso —crear el schema, mudar
--   `retail_sede_meta` adentro, otorgar los grants— nunca se escribió: se corrió
--   a mano en el SQL Editor y no quedó archivo. Se reconstruyó el 2026-08-11 a
--   partir de lo que los pasos siguientes daban por hecho, y es idempotente:
--   sobre esta base no cambia nada. Es la única de las once cuyo archivo no es
--   una copia literal de lo que se pegó, y por eso se dice acá.
--
-- LO QUE ESTA MIGRACIÓN NO ARREGLA
--   Que `retail` esté expuesto en la API es configuración del proyecto
--   (Settings → API → Exposed schemas), no SQL. Ningún archivo de este historial
--   puede restaurarla, y sin ella el ERP de tiendas responde «schema must be one
--   of the following: public» en cada consulta. Queda dicho, no resuelto.
--
--   Y sigue faltando lo que la 0146 ya dejó propuesto: una prueba que compare
--   los archivos contra `migraciones_aplicadas` después de un `db reset` y falle
--   si alguno no se anotó. Mientras el registro dependa de que alguien se
--   acuerde, esto vuelve a pasar.
--
-- CÓMO SE REVIERTE
--   `delete from migraciones_aplicadas where numero between 216 and 227;`
--   No hay cambio de esquema ni de datos: esta migración solo escribe en el
--   registro.
-- ============================================================================

insert into migraciones_aplicadas (numero, nombre) values
  (216, 'el_tipo_de_cada_sede_que_retail_necesita'),
  (217, 'el_cajon_retail_y_sus_permisos'),
  (218, 'retail_lee_la_identidad_de_dynamic'),
  (219, 'el_catalogo_de_tiendas_entra_al_cajon'),
  (220, 'la_operacion_de_tiendas_entra_al_cajon'),
  (221, 'contabilidad_y_produccion_entran_al_cajon'),
  (222, 'las_funciones_que_mueven_stock_caja_y_ventas'),
  (223, 'las_funciones_de_finanzas_del_cajon'),
  (224, 'las_funciones_de_produccion_del_taller'),
  (225, 'el_buzon_de_fotos_de_producto'),
  (226, 'el_material_del_modelo_y_las_seis_etapas')
on conflict (numero) do nothing;

insert into migraciones_aplicadas (numero, nombre)
values (227, 'las_once_de_retail_entran_al_registro')
on conflict (numero) do nothing;

-- ── Que el registro no mienta ───────────────────────────────────────────────
-- Cada una deja un objeto reconocible. Si el objeto no está, la fila que
-- acabamos de escribir es falsa y hay que saberlo AHORA.
do $mig$
declare
  v_falta text := '';
  v_existe boolean;
begin
  if to_regclass('retail.sede_meta') is null then v_falta := v_falta || ' 0216'; end if;

  select exists (select 1 from information_schema.schemata where schema_name = 'retail')
    into v_existe;
  if not v_existe then v_falta := v_falta || ' 0217'; end if;

  if to_regclass('retail.sedes') is null then v_falta := v_falta || ' 0218'; end if;
  if to_regclass('retail.productos') is null then v_falta := v_falta || ' 0219'; end if;
  if to_regclass('retail.movimientos') is null then v_falta := v_falta || ' 0220'; end if;
  if to_regclass('retail.ordenes_produccion') is null then v_falta := v_falta || ' 0221'; end if;

  -- Las funciones se buscan por nombre dentro del schema y no por firma: una
  -- firma escrita a mano que no coincida daría «no existe» sobre algo que sí
  -- está, y eso es peor que no comprobar.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'retail' and p.proname = 'fn_aplicar_movimiento')
    then v_falta := v_falta || ' 0222'; end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'retail' and p.proname = 'recibir_lote')
    then v_falta := v_falta || ' 0223'; end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'retail' and p.proname = 'cerrar_produccion')
    then v_falta := v_falta || ' 0224'; end if;

  if not exists (select 1 from storage.buckets where id = 'fotos-productos')
    then v_falta := v_falta || ' 0225'; end if;

  -- La 0226 hace dos cosas; se mide la que no se puede confundir con otra.
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'retail' and table_name = 'productos'
                   and column_name = 'material')
    then v_falta := v_falta || ' 0226'; end if;

  if v_falta <> '' then
    raise warning '0227 · OJO: se anotaron migraciones cuyo objeto NO existe en esta base:%', v_falta;
    raise warning '0227 · revisa si se saltearon, y borra su fila si no se aplicaron.';
  else
    raise notice '0227 · las once estan aplicadas de verdad: el registro quedo honesto.';
  end if;

  raise notice '0227 · migraciones anotadas ahora: %', (select count(*) from migraciones_aplicadas);
end $mig$;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las cuatro deben decir true.
select
  (select count(*) from migraciones_aplicadas where numero between 216 and 227) = 12
    as las_doce_anotadas,
  to_regclass('retail.sede_meta') is not null
    as el_cajon_esta_armado,
  (select count(*) from information_schema.tables where table_schema = 'retail') >= 25
    as estan_las_tablas_de_retail,
  has_schema_privilege('authenticated', 'retail', 'usage')
    as authenticated_puede_entrar;
