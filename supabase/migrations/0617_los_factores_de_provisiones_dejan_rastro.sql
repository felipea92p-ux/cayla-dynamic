-- ============================================================================
-- 0617 · LOS FACTORES DE PROVISIONES DEJAN RASTRO
-- ============================================================================
--
-- QUÉ PROMETE (el contrato, en tres líneas)
--   1. Los cuatro números que deciden la gratificación, la CTS y las vacaciones
--      de todo el equipo —`configuracion.planilla_provisiones`: gratificacion,
--      cts, vacaciones y sexto_cts— aparecen en «Parámetros», en SOLO LECTURA.
--   2. Cualquier cambio a esos cuatro, venga de donde venga (también el SQL
--      Editor), queda en `parametros_historial`: valor anterior, nuevo, cuándo.
--   3. Una escritura directa desde el navegador sobre esa clave queda rechazada.
--
-- POR QUÉ (2026-11-13)
--   Revisando la CTS de noviembre se preguntó cuándo se encendió el sexto de la
--   gratificación (`sexto_cts` = 0.083333; la 0112 lo dejó apagado y nunca una
--   migración lo encendió). No hubo forma de saberlo: `configuracion` no guarda
--   fecha ni autor, y Postgres no registra la hora de cada transacción
--   (track_commit_timestamp apagado). Un `update` de una línea cambia la CTS de
--   todo el equipo sin dejar huella. La 0552 ya construyó el rastro; faltaba
--   apuntarlo a esta clave.
--
-- POR QUÉ NORMATIVO Y NO EDITABLE
--   Son factores de la ley para la pequeña empresa (D. Leg. 1086 / D.S.
--   013-2013-PRODUCE): media remuneración de grati por semestre (0.08333 al
--   mes), media de CTS al año (0.04167) y quince días de vacaciones (0.04167);
--   el sexto es el art. 16 del D.S. 001-97-TR. No son decisiones de DO. Si
--   CAYLA cambiara de régimen, se cambian con una migración que lo diga, no
--   desde una pantalla. Y no son «plata» en el sentido de la 0574 —esa clase
--   exige vigencias por fecha— porque fn_provisiones lee un solo valor para
--   todo el año; darles vigencia es otra obra (rebanada 2), no esta.
--
-- QUÉ ASUME
--   · La 0552 (catálogo, historial y su trigger), la 0571 (roles_cambia) y la
--     0574 (almacen, alcance) pegadas. La guardia de abajo se niega si no.
--   · Nadie escribe `planilla_provisiones` desde el navegador. Medido en el repo:
--     ningún código de apps/ ni packages/ la toca; solo migraciones y pruebas,
--     que corren como `postgres`. Si en producción alguna función pegada a mano
--     la escribiera como otro rol, el trigger la frena: la consulta de ANTES DE
--     PEGAR lo busca.
--
-- QUÉ NO TOCA
--   Ningún valor. Los cuatro números quedan exactamente como estén en la base;
--   `valor_defecto` es lo que el código usa si la clave falta (0 para el sexto,
--   como fn_provisiones desde la 0112). Ninguna función cambia.
--
-- ANTES DE PEGAR (una consulta, un resultado)
--   select (select valor from configuracion where clave = 'planilla_provisiones') as valor_hoy,
--          (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--            where n.nspname = 'public' and p.prosrc ilike '%planilla_provisiones%'
--              and p.prosrc ~* '(update|insert)[^;]*configuracion') as funciones_que_la_escriben,
--          (select count(*) from parametros_catalogo) as parametros_hoy;
--   «funciones_que_la_escriben» tiene que dar 0.
--
-- CÓMO SE REVIERTE
--   delete from parametros_catalogo where parametro like 'provision\_%';
--   (el historial que se haya escrito se queda: el rastro no se borra.)
--   Si ya hay historial, la fila no se puede borrar por la llave foránea: se
--   deja, como hizo la 0559 con las suyas.
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================

-- ── 0 · Guardia ────────────────────────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.parametros_historial') is null
     or not exists (select 1 from information_schema.columns
                     where table_name = 'parametros_catalogo' and column_name = 'roles_cambia')
     or not exists (select 1 from information_schema.columns
                     where table_name = 'parametros_catalogo' and column_name = 'alcance') then
    raise exception 'PARA. Faltan la 0552, la 0571 o la 0574: el catálogo no tiene la forma que esta migración espera.';
  end if;
  if not exists (select 1 from configuracion where clave = 'planilla_provisiones') then
    raise exception 'PARA. No existe configuracion.planilla_provisiones en esta base.';
  end if;
end
$guardia$;

-- ── 1 · Los cuatro factores, en solo lectura ───────────────────────────────
insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen, almacen_clave, ruta, editable, base, orden, roles_cambia)
values
  ('provision_gratificacion', 'Factor de la gratificación',
   'Parte de lo pagado cada mes que se reserva para la gratificación. En pequeña empresa la gratificación es media remuneración por semestre: 0.5 ÷ 6 = 0.08333.',
   'por sol pagado', 'normativo', 'decimal', null, null, 0.08333,
   'configuracion', 'planilla_provisiones', array['gratificacion'], false,
   'Pequeña empresa: D.S. 013-2013-PRODUCE', 500, array['admin']),
  ('provision_cts', 'Factor de la CTS',
   'Parte de lo pagado cada mes que se reserva para la CTS. En pequeña empresa la CTS es media remuneración al año: 0.5 ÷ 12 = 0.04167.',
   'por sol pagado', 'normativo', 'decimal', null, null, 0.04167,
   'configuracion', 'planilla_provisiones', array['cts'], false,
   'Pequeña empresa: D.S. 013-2013-PRODUCE', 510, array['admin']),
  ('provision_sexto_cts', 'Sexto de la gratificación en la CTS',
   'Lo que la base de la CTS suma por la gratificación: un sexto de una gratificación de media remuneración, 0.5 ÷ 6 = 0.083333. En 0, la CTS se calcula sin el sexto.',
   'de la remuneración', 'normativo', 'decimal', null, null, 0,
   'configuracion', 'planilla_provisiones', array['sexto_cts'], false,
   'D.S. 001-97-TR art. 16 (migración 0112)', 520, array['admin']),
  ('provision_vacaciones', 'Factor de las vacaciones',
   'Parte de lo pagado cada mes que se reserva para las vacaciones. En pequeña empresa son quince días al año: 0.5 ÷ 12 = 0.04167.',
   'por sol pagado', 'normativo', 'decimal', null, null, 0.04167,
   'configuracion', 'planilla_provisiones', array['vacaciones'], false,
   'Pequeña empresa: D.S. 013-2013-PRODUCE', 530, array['admin'])
on conflict (parametro) do update
   set nombre = excluded.nombre, descripcion = excluded.descripcion, unidad = excluded.unidad,
       clase = excluded.clase, tipo_valor = excluded.tipo_valor,
       valor_min = excluded.valor_min, valor_max = excluded.valor_max, valor_defecto = excluded.valor_defecto,
       almacen = excluded.almacen, almacen_clave = excluded.almacen_clave, ruta = excluded.ruta,
       editable = excluded.editable, base = excluded.base, orden = excluded.orden,
       roles_cambia = excluded.roles_cambia;

-- ── 2 · Registro ───────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (617, 'los_factores_de_provisiones_dejan_rastro')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── DESPUÉS DE PEGAR (una consulta, un resultado) ──────────────────────────
--   select (select string_agg(parametro || '=' || coalesce(fn_parametro_numero_en(c.valor, p.ruta)::text, '—'), ' · '
--                             order by orden)
--             from parametros_catalogo p join configuracion c on c.clave = p.almacen_clave
--            where p.parametro like 'provision\_%') as factores,
--          (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 617) as registro;
--   Tiene que decir los cuatro valores de hoy (sexto_cts = 0.083333) y «617 · los_factores_…».
