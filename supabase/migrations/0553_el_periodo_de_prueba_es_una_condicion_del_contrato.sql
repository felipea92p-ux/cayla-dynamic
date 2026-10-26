-- ============================================================================
-- 0553 · EL PERIODO DE PRUEBA ES UNA CONDICIÓN DEL CONTRATO, NO UN VÍNCULO
-- ============================================================================
--
-- QUÉ PROMETE
--   En «Parámetros» (0552):
--     1. «Días de prueba antes del contrato» DEJA DE SER EDITABLE. Se retira del
--        catálogo (o, si ya tiene historial, queda como fila fija «retirado»).
--     2. Aparece «Periodo de prueba · 3 meses» como fila NORMATIVA de solo
--        lectura, con su base legal (art. 10 del D.S. 003-97-TR). No tiene
--        botón y la base rechaza cualquier valor distinto de 3: se muestra para
--        que se sepa de dónde sale el número, igual que el tope de 20 días de
--        descanso médico del RIT.
--     3. Aparece «Días desde el ingreso en que se avisa un feriado trabajado»,
--        parámetro OPERATIVO (1–30, hoy 15) que lee Turnos, y la función que lo
--        entrega, `fn_feriado_aviso_dias()`.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-26)
--   · «Es prácticamente ilegal tener a alguien de prueba, o que comience a
--     laborar, sin contrato previo.» El vínculo «prueba» (tres días trabajados,
--     sin contrato y sin alta, y «si pasa, recién ahí se hace el contrato») no
--     existe en la ley peruana: el periodo de prueba es una cláusula DENTRO de un
--     contrato de trabajo (art. 10 del D.S. 003-97-TR), tres meses sin
--     protección contra el despido arbitrario. Quien trabaja se registra desde
--     el primer día. «De prueba» pasa a ser una condición que se deriva del
--     ingreso (packages/shared, `periodoDePrueba`), no un vínculo ni una fecha
--     guardada.
--   · Por eso los «días de prueba» ya no son un número que DO pueda mover: lo
--     fija la ley. Se MUESTRA en Parámetros y no se cambia.
--   · El aviso de feriado a quien ingresó hace poco (decisión del 2026-10-24)
--     dejaba de tener a quién avisar al desaparecer el vínculo «prueba». Su
--     criterio pasa a ser la antigüedad: menos de N días CALENDARIO desde el
--     ingreso, medidos a la fecha del feriado (Felipe, 2026-10-26: «días
--     calendario desde el ingreso»; el umbral de 15 días es política de CAYLA,
--     no ley, por eso es un parámetro operativo).
--
-- QUÉ ASUME
--   · La 0552 pegada: existen `parametros_catalogo`, `parametros_historial`,
--     `fn_parametro_numero_en` y el candado sobre `configuracion`. Se comprueba
--     abajo y la migración se NIEGA a entrar si no.
--
-- QUÉ NO HACE (cada cosa es la siguiente etapa, no un olvido)
--   · NO TOCA LA PLANILLA ni ninguna función de pago. Ni una línea de
--     `fn_planilla_calcular*`. No hay md5 de planilla que pedir a producción.
--   · NO CAMBIA A NADIE DE VÍNCULO. Quien hoy figure como «prueba» sigue así
--     hasta la 0554, que sí mueve plata (EsSalud, asignación, beneficios) y por
--     eso se entrega aparte, después de medir.
--   · NO CIERRA LA PUERTA a asignar «prueba» por `fn_set_tipo_vinculo`. Las
--     pantallas ya no lo ofrecen, pero veintisiete pruebas pgTAP crean personas
--     «prueba» para defender reglas que siguen vivas mientras quede alguien así;
--     la puerta se cierra en la limpieza, junto con esas pruebas.
--   · NO TOCA `fn_prueba_dias_plazo()` ni `configuracion.prueba_dias`: la
--     maquinaria vieja (0536) los lee mientras queden personas «prueba». La
--     clave se queda; solo deja de poder cambiarse desde la pantalla.
--
-- POR QUÉ ASÍ
--   · La fila del periodo de prueba tiene valor_min = valor_max = 3: el candado
--     de la 0552 rechaza por CUALQUIER camino —también el SQL Editor— un valor
--     que no sea 3. Un número mostrado que alguien pudiera mover sin que el
--     sistema lo use sería un dato sin dueño; así no puede divergir.
--   · «Retirar» el parámetro viejo borra su fila del catálogo SOLO si no tiene
--     historial (`parametros_historial` es inmutable y referencia al catálogo).
--     Si alguien ya lo cambió, la fila queda como normativa, fija, y dice que
--     está retirada: borrar rastro nunca es una opción.
--   · Las claves de `configuracion` se siembran ANTES que sus filas del
--     catálogo, como en la 0552: la siembra no es un cambio y no escribe
--     historial.
--
-- CÓMO SE REVIERTE
--   delete from parametros_catalogo
--    where parametro in ('periodo_prueba_meses', 'feriado_aviso_antiguedad_dias');
--   drop function if exists fn_feriado_aviso_dias();
--   -- y, si se había borrado el parámetro viejo, repegar su fila de la 0552 (sección 5).
--   Las claves configuracion.periodo_prueba_meses / feriado_aviso_antiguedad_dias
--   pueden quedarse: sin catálogo nadie las lee.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 445.
-- ============================================================================

-- ── Guardia: la 0552 tiene que estar ────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.parametros_catalogo') is null
     or to_regclass('public.parametros_historial') is null
     or to_regprocedure('public.fn_parametro_numero_en(jsonb,text[])') is null then
    raise exception 'PARA. Falta la 0552 (Parámetros): no existe parametros_catalogo, parametros_historial o fn_parametro_numero_en. Pega primero la 0552.';
  end if;
end
$guardia$;

-- ── 1 · Las claves donde viven los valores ──────────────────────────────────
-- Antes que el catálogo: la siembra no es un cambio y no deja historial.
insert into configuracion (clave, valor, descripcion)
values
  ('periodo_prueba_meses', '3'::jsonb,
   'Meses del periodo de prueba (art. 10, D.S. 003-97-TR). Lo fija la ley: el catálogo rechaza cualquier otro valor. 0553.'),
  ('feriado_aviso_antiguedad_dias', '15'::jsonb,
   'Días calendario desde el ingreso por debajo de los cuales Turnos recomienda dar descanso en un feriado. 0553.')
on conflict (clave) do nothing;

-- ── 2 · «Días de prueba antes del contrato» se retira del catálogo ──────────
do $retiro$
begin
  if exists (select 1 from parametros_historial where parametro = 'prueba_dias') then
    -- Ya lo movió alguien: el historial es inmutable y apunta a esta fila. Se queda, fija y dicha.
    update parametros_catalogo
       set nombre      = 'Días de prueba antes del contrato (retirado)',
           descripcion = 'Ya no se usa para nada nuevo: «de prueba» dejó de ser un vínculo (0553). Se conserva solo porque tiene historial.',
           clase       = 'normativo',
           editable    = false,
           orden       = 900
     where parametro = 'prueba_dias';
  else
    delete from parametros_catalogo where parametro = 'prueba_dias';
  end if;
end
$retiro$;

-- ── 3 · Las dos filas nuevas ────────────────────────────────────────────────
insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen_clave, ruta, editable, base, orden)
values
  ('periodo_prueba_meses',
   'Periodo de prueba',
   'Meses desde el ingreso en los que CAYLA puede decidir no continuar sin expresión de causa ni indemnización, y la persona todavía no está protegida contra el despido arbitrario. Corre desde el primer día, dentro de un contrato ya firmado y con la persona dada de alta. Lo fija la ley: se muestra, no se cambia.',
   'meses', 'normativo', 'entero', 3, 3, 3,
   'periodo_prueba_meses', null, false,
   'Art. 10 del D.S. 003-97-TR (migración 0553)', 10),
  ('feriado_aviso_antiguedad_dias',
   'Días desde el ingreso en que se avisa un feriado trabajado',
   'Si alguien lleva menos de estos días calendario desde su ingreso a la fecha de un feriado, Turnos recomienda darle descanso ese día: trabajarlo sin un día libre a cambio se paga con sobretasa. Solo avisa. No cambia ningún pago, y darle descanso no es dejar de pagarle el feriado.',
   'días', 'operativo', 'entero', 1, 30, 15,
   'feriado_aviso_antiguedad_dias', null, true,
   'Decisión de CAYLA (2026-10-26, migración 0553)', 15)
on conflict (parametro) do update
   set nombre = excluded.nombre, descripcion = excluded.descripcion, unidad = excluded.unidad,
       clase = excluded.clase, tipo_valor = excluded.tipo_valor,
       valor_min = excluded.valor_min, valor_max = excluded.valor_max, valor_defecto = excluded.valor_defecto,
       almacen_clave = excluded.almacen_clave, ruta = excluded.ruta,
       editable = excluded.editable, base = excluded.base, orden = excluded.orden;

-- ── 4 · La función que lee Turnos ───────────────────────────────────────────
-- Mismo molde que `fn_prueba_dias_plazo()` (0552): stable, security definer
-- porque lee una tabla, y el 15 del final es el valor de partida del catálogo;
-- la prueba 445 comprueba que coincidan.
create or replace function fn_feriado_aviso_dias()
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    (select fn_parametro_numero_en(c.valor, null)::integer
       from configuracion c where c.clave = 'feriado_aviso_antiguedad_dias'),
    15);
$fn$;

comment on function fn_feriado_aviso_dias() is
  'Desde cuántos días calendario de ingreso Turnos recomienda dar descanso en un feriado (Parámetros). Solo avisa: no cambia ningún pago. 0553.';

revoke execute on function fn_feriado_aviso_dias() from public, anon;
grant  execute on function fn_feriado_aviso_dias() to authenticated;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (553, 'el_periodo_de_prueba_es_una_condicion_del_contrato')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: true · true · true · 15 · true · «553 · el_periodo_de_prueba_…»
select
  (select count(*) = 0 from parametros_catalogo
    where parametro = 'prueba_dias' and editable)                              as prueba_dias_ya_no_se_edita,
  (select editable is false and clase = 'normativo' and valor_min = 3 and valor_max = 3
     from parametros_catalogo where parametro = 'periodo_prueba_meses')        as el_periodo_de_prueba_es_fijo,
  (select count(*) = 1 from parametros_catalogo
    where parametro = 'feriado_aviso_antiguedad_dias' and editable)            as el_aviso_de_feriado_es_operativo,
  fn_feriado_aviso_dias()                                                      as dias_del_aviso_hoy,
  (select count(*) = 2 from configuracion
    where clave in ('periodo_prueba_meses', 'feriado_aviso_antiguedad_dias'))  as las_dos_claves_existen,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 553) as registro;
