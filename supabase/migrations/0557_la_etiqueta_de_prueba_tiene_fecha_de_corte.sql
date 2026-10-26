-- ============================================================================
-- 0557 · LA ETIQUETA «EN PERIODO DE PRUEBA» TIENE FECHA DE CORTE
-- ============================================================================
--
-- QUÉ PROMETE
--   En «Parámetros» aparece «La etiqueta de prueba alcanza a quien ingresó desde»,
--   una fecha EDITABLE (operativa), y la función que la entrega,
--   `fn_prueba_etiqueta_desde()`. Equipo rotula «en periodo de prueba» solo a quien
--   ingresó en esa fecha o después, y solo mientras dure su periodo.
--     · POR DEFECTO es el día en que se pega esta migración: la etiqueta alcanza a
--       las altas NUEVAS, y a nadie de los que ya estaban.
--     · Llevarla atrás rotula también a quien ya trabaja y lleva menos de tres meses:
--       con la fecha de hace tres meses, a TODA la gente reciente; con otra
--       intermedia, a quien ingresó desde ahí.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-26)
--   «Que sea la etiqueta para todos los nuevos a partir de esta fecha en adelante, o
--   todos los que tienen contrato: revisar cuánto tiempo llevan y, si tienen menos de
--   3 meses, categorizarlos también como prueba. Por defecto, a partir de hoy.»
--
-- ⚠ ES UNA ETIQUETA, NO UN DERECHO NI UN PAGO
--   El periodo de prueba legal (art. 10, D.S. 003-97-TR) es una cláusula del contrato
--   de CADA persona y existe o no existe con independencia de esta fecha. Esta fecha
--   solo decide a quién le pone el rótulo la pantalla. No toca la planilla, ni las
--   alertas de feriado (que miran la antigüedad), ni el texto del contrato.
--
-- POR QUÉ ES UN ENTERO «AAAAMMDD»
--   El catálogo de Parámetros (0552) solo guarda números, y abrirlo a otro tipo de
--   valor toca el trigger de historial y la función de cambio — la puerta que
--   protege los parámetros de PLATA. Una fecha como 20261026 cabe en el molde tal
--   cual (mismo candado, mismo motivo obligatorio, mismo historial) y la pantalla la
--   dibuja como fecha (unidad «fecha»). `fn_prueba_etiqueta_desde()` valida que sea
--   una fecha real y, si no lo es, devuelve la de partida: un dato raro nunca apaga
--   ni enciende la etiqueta a todos.
--
-- QUÉ ASUME
--   · La 0552 y la 0553 pegadas. Se comprueba abajo.
--
-- QUÉ NO HACE
--   · NO TOCA LA PLANILLA ni ninguna función de pago. No hay md5 de planilla.
--   · NO CAMBIA A NADIE: solo se agrega una clave, una fila de catálogo y una función.
--
-- CÓMO SE REVIERTE
--   delete from parametros_catalogo where parametro = 'prueba_etiqueta_desde';
--   drop function if exists fn_prueba_etiqueta_desde();
--   (la clave de `configuracion` puede quedarse; sin catálogo nadie la lee).
--   ⚠ Si ya se cambió desde la pantalla, `parametros_historial` la referencia y el
--   borrado fallará: es a propósito, el rastro no se borra.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 449.
-- ============================================================================

-- ── Guardia ─────────────────────────────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.parametros_catalogo') is null
     or to_regprocedure('public.fn_parametro_numero_en(jsonb,text[])') is null then
    raise exception 'PARA. Falta la 0552 (Parámetros). Pega primero la 0552.';
  end if;
  if not exists (select 1 from migraciones_aplicadas where numero = 553) then
    raise exception 'PARA. Falta la 0553 (el periodo de prueba como condición del contrato). Pega primero la 0553.';
  end if;
end
$guardia$;

-- ── 1 · La clave: por defecto, HOY (fecha de Lima) ──────────────────────────
-- Antes que el catálogo: la siembra no es un cambio y no deja historial. `do nothing`
-- a propósito: repegar esta migración NO mueve una fecha que alguien ya eligió.
insert into configuracion (clave, valor, descripcion)
values ('prueba_etiqueta_desde',
        to_jsonb(to_char((now() at time zone 'America/Lima')::date, 'YYYYMMDD')::integer),
        'Fecha AAAAMMDD desde la cual Equipo rotula «en periodo de prueba» a quien ingresa. Solo etiqueta: no cambia pagos ni derechos. 0557.')
on conflict (clave) do nothing;

-- ── 2 · La fila del catálogo ────────────────────────────────────────────────
-- valor_defecto 20261026 = el día en que se escribió; solo se usa si la clave no
-- existiera, y la siembra de arriba la deja siempre. Los topes 20260101–20301231 son
-- un seguro contra un tecleo (un 2062 por un 2026), no una regla de negocio: una fecha
-- futura es legítima (que la etiqueta empiece el mes que viene), una de 2062 no.
insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen_clave, ruta, editable, base, orden)
values
  ('prueba_etiqueta_desde',
   'La etiqueta de prueba alcanza a quien ingresó desde',
   'Equipo muestra «En periodo de prueba hasta…» a quien ingresó en esta fecha o después y sigue dentro de su periodo. Por defecto es el día en que se activó: solo las altas nuevas. Llevarla atrás rotula también a quien ya trabaja y lleva menos de tres meses. Es solo una etiqueta: el periodo de prueba legal lo fija el contrato de cada persona, y esta fecha no cambia ningún pago ni ningún derecho.',
   'fecha', 'operativo', 'entero', 20260101, 20301231, 20261026,
   'prueba_etiqueta_desde', null, true,
   'Decisión de CAYLA (2026-10-26, migración 0557)', 12)
on conflict (parametro) do update
   set nombre = excluded.nombre, descripcion = excluded.descripcion, unidad = excluded.unidad,
       clase = excluded.clase, tipo_valor = excluded.tipo_valor,
       valor_min = excluded.valor_min, valor_max = excluded.valor_max, valor_defecto = excluded.valor_defecto,
       almacen_clave = excluded.almacen_clave, ruta = excluded.ruta,
       editable = excluded.editable, base = excluded.base, orden = excluded.orden;

-- ── 3 · La función que lee Equipo ───────────────────────────────────────────
-- Una fecha inventada (20261340) o un valor ausente cae en la de partida, en vez de
-- reventar la pantalla o rotular a nadie / a todos por un dato raro.
create or replace function fn_prueba_etiqueta_desde()
returns date
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_n     integer;
  v_fecha date;
begin
  select fn_parametro_numero_en(c.valor, null)::integer into v_n
    from configuracion c where c.clave = 'prueba_etiqueta_desde';
  v_n := coalesce(v_n, 20261026);
  begin
    v_fecha := to_date(v_n::text, 'YYYYMMDD');
    -- to_date acepta 20261340 corriéndolo al año siguiente: se exige que vuelva igual.
    if to_char(v_fecha, 'YYYYMMDD')::integer <> v_n then
      v_fecha := null;
    end if;
  exception when others then
    v_fecha := null;
  end;
  return coalesce(v_fecha, date '2026-10-26');
end;
$fn$;

comment on function fn_prueba_etiqueta_desde() is
  'Fecha desde la cual Equipo rotula «en periodo de prueba» a quien ingresa (Parámetros). Solo etiqueta: no cambia ningún pago. Un valor ilegible cae en la fecha de partida. 0557.';

revoke execute on function fn_prueba_etiqueta_desde() from public, anon;
grant  execute on function fn_prueba_etiqueta_desde() to authenticated;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (557, 'la_etiqueta_de_prueba_tiene_fecha_de_corte')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: true · true · «la fecha de hoy en Lima» · true · «557 · la_etiqueta_de_prueba_…»
select
  (select count(*) = 1 from parametros_catalogo
    where parametro = 'prueba_etiqueta_desde' and editable and clase = 'operativo') as esta_en_el_catalogo,
  (select count(*) = 1 from configuracion where clave = 'prueba_etiqueta_desde')    as la_clave_existe,
  fn_prueba_etiqueta_desde()                                                        as la_etiqueta_alcanza_desde,
  (select pronamespace = 'public'::regnamespace and prosecdef from pg_proc
    where proname = 'fn_prueba_etiqueta_desde')                                     as la_funcion_es_security_definer,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 557) as registro;
