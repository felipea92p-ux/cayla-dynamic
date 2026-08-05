-- ============================================================================
-- 0152 — La tarifa de movilidad no puede pasarse de su techo.
--
-- QUÉ PROMETE
--
-- Que nadie pueda cargar una tarifa diaria de movilidad por encima del 4 % de la
-- RMV vigente en la fecha desde la que empieza a regir. Hoy son S/45.20 diarios
-- (4 % de S/1,130). Si mañana la RMV sube a S/1,300, el techo sube solo a S/52.
--
-- QUÉ NO CAMBIA. Ningún pago. Las tres tarifas vivas —AQP S/10, TRU S/10,
-- LIM S/12— están a menos de un cuarto del techo. Habría que cuadruplicarlas
-- para que este candado se active. Es una restricción preventiva, no una
-- corrección.
--
-- DE DÓNDE SALE EL 4 %, Y POR QUÉ LO USAMOS AUNQUE PROBABLEMENTE NO NOS OBLIGUE
--
-- El número viene del artículo 37 inciso a1) de la Ley del Impuesto a la Renta,
-- que topa en 4 % de la RMV diaria los gastos de movilidad sustentados con
-- planilla de movilidad. Ese inciso, leído completo, muy probablemente NO nos
-- alcanza: regula la movilidad como condición de trabajo y se autoexcluye al
-- decir que aplica a gastos «que no constituyan beneficio o ventaja patrimonial
-- directa» del trabajador. Los S/10 diarios de CAYLA sí son beneficio directo:
-- le entran al bolsillo de la persona por haber venido a trabajar. Lo nuestro es
-- el artículo 19 inciso e) del D.S. 001-97-TR, otra figura y otra base legal.
-- Está preguntado al contador (ver docs/movilidad-y-codigos-plame-para-el-contador.md).
--
-- Entonces, ¿por qué poner el candado igual? Porque el límite que SÍ nos rige
-- siempre no es un número, es una frase: el artículo 19 e) exige que el monto
-- «razonablemente cubra el respectivo traslado». Una tarifa desproporcionada
-- respecto del pasaje real se reclasifica como remuneración, y con ella cae el
-- concepto entero — no solo el exceso. El Expediente 01038-2019 de Lima Norte
-- tumbó una movilidad completa por eso mismo, y la 0142 ya lo tiene anotado.
--
-- «Razonablemente» no se puede escribir en SQL. El 4 % de la RMV sí, y sirve de
-- proxy generoso: S/45.20 diarios son S/1,175 al mes de movilidad, más que un
-- sueldo entero de rango colibrí. Cualquier tarifa que se acerque a ese número
-- ya es indefendible bajo el 19 e), venga o no el a1) a topearla. El techo no lo
-- acatamos: lo usamos.
--
-- POR QUÉ UN TRIGGER Y NO UN CHECK
--
-- Un CHECK de tabla en Postgres tiene que ser inmutable: no puede leer otra fila
-- para decidir. El techo depende de la RMV, que vive en otra fila de esta misma
-- tabla y cambia con el tiempo. Un CHECK con el número quemado (`valor <= 45.20`)
-- quedaría falso el día que suba la RMV, y peor: quedaría falso en silencio.
--
-- QUÉ ASUME
--
--   · Que si no hay RMV vigente para esa fecha, no hay techo que aplicar y la
--     fila pasa. Falla abierto a propósito, igual que fn_educacion_respeta_el_tope
--     de la 0149: bloquear una carga legítima por la ausencia de un dato de
--     referencia sería peor que dejarla entrar. En la práctica solo alcanza a
--     la fila semilla de la 0118 (valor 0.00, vigente desde 2020-03-01), que es
--     anterior a la RMV más vieja cargada.
--   · Que las filas YA existentes no se revalidan. Un trigger mira lo que entra,
--     no lo que está. Es deliberado: una migración que falla por datos
--     históricos no se puede pegar en producción, y este archivo tiene que
--     poder pegarse dos veces sin drama.
--
-- QUÉ NO TOCA. fn_planilla_calcular, las provisiones, el EsSalud, la
-- bonificación de la Ley 30334, el divisor de 6.5 h ni ninguna de las tarifas
-- cargadas. Solo agrega una puerta a la entrada de parametros_laborales.
--
-- CÓMO SE REVIERTE:
--   drop trigger if exists trg_movilidad_no_supera_el_techo on parametros_laborales;
--   drop function if exists fn_movilidad_no_supera_el_techo();
-- ============================================================================


-- ── La guarda ───────────────────────────────────────────────────────────────
-- SECURITY DEFINER porque tiene que leer la fila de la RMV para saber el techo,
-- y parametros_laborales tiene RLS: quien escribe desde una RPC podría no poder
-- leerla. Sin esto el trigger no fallaría — devolvería NULL y dejaría pasar
-- todo, que es el peor de los dos errores: un candado que parece puesto y no lo
-- está.
create or replace function fn_movilidad_no_supera_el_techo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rmv   numeric;
  v_techo numeric;
begin
  -- La RMV vigente EN LA FECHA EN QUE ESTA TARIFA EMPIEZA A REGIR, no la de hoy.
  -- Cargar en agosto una tarifa que rige desde enero se mide contra la RMV de
  -- enero, que es la que el inspector va a mirar para ese periodo.
  select pl.valor into v_rmv
    from parametros_laborales pl
   where pl.clave = 'rmv'
     and pl.vigente_desde <= new.vigente_desde
     and (pl.vigente_hasta is null or pl.vigente_hasta >= new.vigente_desde)
   order by pl.vigente_desde desc
   limit 1;

  if v_rmv is null then
    return new;  -- sin RMV de referencia no hay techo que aplicar
  end if;

  v_techo := round(v_rmv * 0.04, 2);

  if new.valor > v_techo then
    raise exception
      'La movilidad diaria no puede ser S/%. El techo es S/% (4%% de la RMV de S/% '
      'vigente al %). Una tarifa por encima de eso deja de «cubrir razonablemente el '
      'traslado» y se reclasifica como sueldo, con lo que el concepto entero pasa a '
      'pagar EsSalud, AFP, CTS y gratificaciones — no solo el exceso. Si el pasaje '
      'realmente subió tanto, carga primero la RMV nueva; si es otro concepto, no va '
      'en la clave movilidad_diaria.',
      to_char(new.valor, 'FM999999.00'),
      to_char(v_techo,   'FM999999.00'),
      to_char(v_rmv,     'FM999999.00'),
      to_char(new.vigente_desde, 'DD/MM/YYYY')
      using errcode = 'check_violation';
  end if;

  return new;
end
$$;

comment on function fn_movilidad_no_supera_el_techo() is
  'Impide cargar una tarifa de movilidad diaria por encima del 4% de la RMV vigente '
  'en su fecha de inicio. El número sale del art. 37 a1) de la LIR; la razón para '
  'usarlo es el art. 19 e) del D.S. 001-97-TR, que exige que el monto cubra '
  'razonablemente el traslado. Ver el encabezado de la migración 0152.';


-- ── La puerta ───────────────────────────────────────────────────────────────
-- El WHEN filtra en el motor: las escrituras de RMV, tasa de EsSalud, asignación
-- familiar y demás claves ni siquiera entran a la función.
drop trigger if exists trg_movilidad_no_supera_el_techo on parametros_laborales;

create trigger trg_movilidad_no_supera_el_techo
  before insert or update on parametros_laborales
  for each row
  when (new.clave = 'movilidad_diaria')
  execute function fn_movilidad_no_supera_el_techo();


-- ── Verificación: ¿alguna tarifa viva ya se pasa? ───────────────────────────
-- No corrige nada, solo avisa. Si esto imprime una fila hay que mirarla a mano,
-- porque el trigger no la va a tocar mientras nadie la edite.
do $mig$
declare
  r record;
  v_encontradas int := 0;
begin
  for r in
    select m.sede_codigo, m.valor, m.vigente_desde,
           (select pl.valor from parametros_laborales pl
             where pl.clave = 'rmv'
               and pl.vigente_desde <= m.vigente_desde
               and (pl.vigente_hasta is null or pl.vigente_hasta >= m.vigente_desde)
             order by pl.vigente_desde desc limit 1) as rmv
      from parametros_laborales m
     where m.clave = 'movilidad_diaria'
  loop
    if r.rmv is not null and r.valor > round(r.rmv * 0.04, 2) then
      v_encontradas := v_encontradas + 1;
      raise warning '0152 · REVISAR: movilidad de % en S/% desde % supera el techo de S/%',
        coalesce(r.sede_codigo, '(todas las sedes)'), r.valor, r.vigente_desde,
        round(r.rmv * 0.04, 2);
    end if;
  end loop;

  if v_encontradas = 0 then
    raise notice '0152 · Ninguna tarifa de movilidad supera su techo. Candado puesto.';
  end if;
end
$mig$;
