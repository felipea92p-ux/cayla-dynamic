-- ============================================================================
-- 0328 — La comisión mixta deja de cobrarse como si fuera comisión sobre flujo
-- ============================================================================
--
-- QUÉ PROMETE
--   Que se pueda decir, por persona, si su AFP le cobra la comisión SOBRE FLUJO
--   o la comisión MIXTA — y que a quien está en mixta se le descuente lo que de
--   verdad le corresponde: 11.37 %, no 12.84 %-13.06 %.
--
-- QUÉ ASUME
--   · Que `tasas_pension` sigue siendo el único sitio donde vive «cuánto se
--     descuenta» (0114/0115), que la pertenencia de cada persona a un régimen
--     está versionada en `asignaciones_regimen_pension` (0261) y que
--     `fn_cambiar_regimen_pension` valida contra `tasas_pension` y no contra una
--     lista escrita a mano (0277). Comprobado en la base antes de escribir.
--   · Que por eso esta migración NO TOCA NINGUNA FUNCIÓN. Ni
--     `fn_planilla_calcular`, ni `fn_provisiones`, ni `fn_cambiar_regimen_pension`.
--     Solo agrega filas de tasa y ensancha dos CHECK. No puede revertir en
--     silencio ningún cálculo, porque no reescribe ningún cálculo.
--   · Que la prima de seguro (1.37 %) y las comisiones sobre flujo (1.47 %
--     Habitat, 1.55 % Integra, 1.60 % Prima, 1.69 % Profuturo) de la 0114 SIGUEN
--     SIENDO CORRECTAS. Se verificaron contra la SBS el 2026-08-31. El defecto
--     no está en los porcentajes: está en que solo existe uno de los dos
--     esquemas de comisión que la ley reconoce.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- La 0114 lo dejó anotado en su propia cabecera, en el apartado «LO QUE NO SE
-- MODELA, Y QUEDA ADVERTIDO», punto 1:
--
--     «COMISIÓN MIXTA. Quien está en comisión mixta paga MENOS sobre el sueldo
--      (AFP Integra llega a cobrar 0 % sobre flujo) [...] Si alguien está en
--      mixta, su descuento real es menor que el de esta tabla. Para modelarlo
--      bastaría agregar filas 'integra_mixta', etc.»
--
-- Era una advertencia correcta y quedó sin hacer. Lo encontró el contador de
-- CAYLA el 2026-08-31 comparando las boletas contra AFPnet.
--
-- Y no es un caso raro. La Ley 29903 creó la comisión mixta en febrero de 2013
-- y desde entonces **quien se afilia por primera vez al SPP entra a mixta de
-- forma obligatoria**: no puede elegir flujo. Solo siguen en flujo quienes ya
-- estaban afiliados antes de 2013 y pidieron quedarse. Como casi todo el equipo
-- de CAYLA empezó a trabajar bastante después de 2013, lo esperable es lo
-- contrario de lo que el sistema supone: la mayoría está en MIXTA.
--
-- Y desde febrero de 2023 el componente sobre la remuneración de la comisión
-- mixta es **0 % definitivo en las cuatro AFP**. O sea que a quien está en
-- mixta, de su sueldo solo salen dos cosas:
--
--     aporte obligatorio al fondo   10.00 %
--     prima de seguro (SBS)          1.37 %
--                                 ─────────
--     total que retiene CAYLA       11.37 %
--
-- La comisión de la mixta NO se retiene del sueldo: la AFP la cobra por su
-- cuenta contra el saldo acumulado (0.68 % anual Profuturo, 0.78 % Integra,
-- 1.25 % Habitat y Prima). Por eso no aparece en esta tabla ni debe aparecer:
-- esta tabla dice qué descuenta el empleador de la boleta, y esa comisión no
-- pasa por la boleta ni por la planilla.
--
-- ── CUÁNTO CUESTA, Y A QUIÉN ────────────────────────────────────────────────
--
-- A quien esté en mixta y el sistema tenga cargado en flujo se le está
-- reteniendo de más, cada mes, su comisión entera:
--
--     Profuturo   13.06 % en vez de 11.37 %  →  1.69 puntos de su base
--     Prima       12.97 % en vez de 11.37 %  →  1.60 puntos
--     Integra     12.92 % en vez de 11.37 %  →  1.55 puntos
--     Habitat     12.84 % en vez de 11.37 %  →  1.47 puntos
--
-- Sobre una base de S/1,000 son entre S/14.70 y S/16.90 al mes POR PERSONA.
-- La cifra exacta, persona por persona y periodo por periodo, sale de la
-- consulta que cierra este archivo: lee las fotos congeladas, así que dice lo
-- que se retuvo de verdad y no lo que se recalcularía hoy.
--
-- ── LO QUE ESTA MIGRACIÓN **NO** HACE, Y ES DELIBERADO ──────────────────────
--
-- **No mueve un céntimo el día que se pega.** Agrega cuatro filas de tasa a las
-- que hoy no apunta nadie y ensancha dos CHECK. Nadie cambia de régimen, así
-- que ninguna boleta cambia. Se puede pegar sin mirar la planilla.
--
-- **No reasigna a nadie a mixta, ni siquiera a quien casi seguro lo está.**
-- Quién está en flujo y quién en mixta es un dato que vive en AFPnet y en el
-- estado de cuenta de cada persona — no se deduce del DNI ni de la fecha de
-- ingreso a CAYLA (alguien pudo afiliarse en un trabajo anterior). Adivinarlo
-- en masa cambiaría el sueldo de veinte personas sobre una suposición, que es
-- exactamente la forma de error que este repositorio trata como la peor.
--
-- El paso que mueve plata va en su propia migración, con la lista confirmada
-- por el contador, y usando la puerta que ya existe:
--
--     select fn_cambiar_regimen_pension(
--              '<uuid de la persona>', 'integra_mixta',
--              '<primer día del periodo ABIERTO>',
--              'Confirmado en AFPnet por el contador el <fecha>');
--
-- Esa función se niega sola si la fecha cae dentro de un periodo ya pagado
-- (freno de la 0203), que es justo lo que protege los meses ya depositados.
--
-- **No decide qué se hace con lo retenido de más en los meses ya pagados.**
-- Eso es plata que salió del sueldo de una persona: se le devuelve o se le
-- compensa, y lo decide Felipe con el contador. El sistema pone el número.
--
-- ── POR QUÉ CÓDIGOS NUEVOS Y NO UN CAMPO APARTE ─────────────────────────────
--
-- Se podría haber agregado una columna `tipo_comision` a `personas`. No se hace
-- porque la tasa que se aplica ya se resuelve por UNA sola llave —el código de
-- régimen— en tres sitios: el lateral de `fn_planilla_calcular`, el historial de
-- `asignaciones_regimen_pension` y la validación de `fn_cambiar_regimen_pension`.
-- Una segunda dimensión obligaría a cruzarla en los tres, y bastaría con que uno
-- se olvidara para volver a tener dos verdades sobre cuánto se descuenta. Con un
-- código por combinación, el historial versionado de la 0261 registra gratis el
-- día que alguien se cambia de esquema, que es un dato que la SBS permite mover.
--
-- Los códigos viejos NO se renombran a `integra_flujo`. Renombrarlos rompería
-- las filas ya escritas en `asignaciones_regimen_pension` y reescribiría el
-- pasado por un gusto de simetría. `integra` significa lo que siempre significó:
-- Integra con comisión sobre flujo.
--
-- ── LA VIGENCIA SE COPIA, NO SE INVENTA ─────────────────────────────────────
--
-- Las filas nuevas nacen con el MISMO `vigente_desde` que ya tienen las filas de
-- AFP en esta base. No con una fecha escrita a mano, y la razón es un modo de
-- fallo silencioso: si una fila de mixta empezara DESPUÉS del día desde el que
-- se le asigna a alguien, el lateral de `fn_planilla_calcular` no encontraría
-- fila, caería al interruptor global `configuracion.tasa_afp` —que vale 0 desde
-- la 0115— y esa persona pasaría a NO APORTAR NADA sin que nadie lo note. Un
-- descuento que desaparece se ve igual que un descuento correcto en una boleta
-- que nadie está mirando con lupa.
--
-- La 0115 movió ese `vigente_desde` al primer periodo abierto de ENTONCES, así
-- que su valor en producción no es el que se ve en esta Mac. Por eso se lee de
-- la propia base en vez de escribirse.
--
-- CÓMO SE REVIERTE
--   1. delete from tasas_pension where regimen like '%\_mixta';
--   2. Restaurar los dos CHECK sin los cuatro códigos nuevos (0190 y 0261).
--   Solo se puede revertir mientras nadie esté asignado a un régimen mixta; si
--   ya lo está, primero hay que devolverlo a su código de flujo con
--   fn_cambiar_regimen_pension. Ninguna función se toca, así que no hay nada más
--   que restaurar.
-- ============================================================================


-- ── 1 · Las cuatro tasas de comisión mixta ──────────────────────────────────
--
-- `comision` va en 0 y eso es el cambio entero. `aporte` y `prima` son los
-- mismos de la 0114 porque no dependen del esquema de comisión: el 10 % lo fija
-- el TUO de la Ley del SPP y la prima la fija la SBS, iguales en las cuatro AFP
-- y en los dos esquemas.
--
-- `grava_subsidio` se deja en su valor por defecto (true), igual que las filas
-- de flujo: el subsidio de EsSalud entra a la base de aporte a la AFP tanto en
-- flujo como en mixta — depende del sistema previsional, no de cómo cobra la
-- comisión.

insert into tasas_pension (regimen, nombre, aporte, comision, prima, vigente_desde, nota)
select v.regimen, v.nombre, 0.10000, 0.00000, 0.01370,
       -- La vigencia que ya tienen las AFP en ESTA base. Ver la cabecera.
       (select min(tp.vigente_desde) from tasas_pension tp
         where tp.regimen in ('integra','prima','profuturo','habitat')),
       v.nota
from (values
  ('profuturo_mixta', 'AFP Profuturo — comisión mixta',
   'Comision sobre flujo 0 % desde febrero de 2023 (Ley 29903). Del sueldo solo '
   || 'salen el aporte de 10 % y la prima de 1.37 %: 11.37 % en total. La comision '
   || 'de la mixta (0.68 % anual) la cobra la AFP contra el saldo acumulado, no '
   || 'pasa por la boleta. Verificado contra la SBS el 2026-08-31.'),
  ('prima_mixta',     'AFP Prima — comisión mixta',
   'Comision sobre flujo 0 % desde febrero de 2023 (Ley 29903). Del sueldo solo '
   || 'salen el aporte de 10 % y la prima de 1.37 %: 11.37 % en total. La comision '
   || 'de la mixta (1.25 % anual) la cobra la AFP contra el saldo acumulado, no '
   || 'pasa por la boleta. Verificado contra la SBS el 2026-08-31.'),
  ('integra_mixta',   'AFP Integra — comisión mixta',
   'Comision sobre flujo 0 % desde febrero de 2023 (Ley 29903). Del sueldo solo '
   || 'salen el aporte de 10 % y la prima de 1.37 %: 11.37 % en total. La comision '
   || 'de la mixta (0.78 % anual) la cobra la AFP contra el saldo acumulado, no '
   || 'pasa por la boleta. Verificado contra la SBS el 2026-08-31.'),
  ('habitat_mixta',   'AFP Habitat — comisión mixta',
   'Comision sobre flujo 0 % desde febrero de 2023 (Ley 29903). Del sueldo solo '
   || 'salen el aporte de 10 % y la prima de 1.37 %: 11.37 % en total. La comision '
   || 'de la mixta (1.25 % anual) la cobra la AFP contra el saldo acumulado, no '
   || 'pasa por la boleta. Verificado contra la SBS el 2026-08-31.')
) as v(regimen, nombre, nota)
where not exists (select 1 from tasas_pension tp where tp.regimen = v.regimen);


-- ── 2 · Los dos CHECK que enumeran los códigos válidos ──────────────────────
--
-- Son dos y hay que mover los dos: `personas.regimen_pension` (0114, ampliado
-- por la 0190) y `asignaciones_regimen_pension.regimen` (0261). Si se mueve solo
-- el primero, `fn_cambiar_regimen_pension` pasa su propia validación —que mira
-- `tasas_pension`— y revienta al insertar el tramo. El error saldría en la
-- pantalla de Datos personales, al guardar, y no diría nada de esto.

alter table personas drop constraint if exists personas_regimen_pension_valido;
alter table personas add constraint personas_regimen_pension_valido
  check (regimen_pension is null
         or regimen_pension in ('onp','profuturo','prima','integra','habitat','jubilada',
                                'profuturo_mixta','prima_mixta','integra_mixta','habitat_mixta'));

alter table asignaciones_regimen_pension
  drop constraint if exists asignaciones_regimen_pension_regimen_valido;
alter table asignaciones_regimen_pension
  add constraint asignaciones_regimen_pension_regimen_valido
  check (regimen in ('onp','profuturo','prima','integra','habitat','jubilada',
                     'profuturo_mixta','prima_mixta','integra_mixta','habitat_mixta'));

comment on column personas.regimen_pension is
  'A que sistema previsional aporta, y con que esquema de comision. Los codigos '
  'sin sufijo (`integra`, `prima`, `profuturo`, `habitat`) son COMISION SOBRE '
  'FLUJO: la AFP cobra su comision del sueldo. Los que terminan en `_mixta` son '
  'COMISION MIXTA: 0 % sobre el sueldo desde febrero de 2023, la comision se '
  'cobra contra el saldo del fondo y no pasa por la boleta (0328). Quien se '
  'afilio al SPP desde 2013 esta en mixta de forma obligatoria (Ley 29903). '
  '`jubilada` = ya percibe pension y por eso NO aporta (0190); es una decision '
  'escrita, no un dato faltante. NULL sigue significando «todavia no se '
  'clasifico» y cae a configuracion.tasa_afp.';


notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (328, 'la_comision_mixta_deja_de_cobrarse_como_flujo')
on conflict (numero) do nothing;


-- ── 3 · La comprobación, y de paso la cuenta de lo retenido de más ──────────
--
-- Un solo SELECT porque el SQL Editor solo devuelve el último. Las tres primeras
-- columnas dicen si la pegada llegó entera; las tres últimas dicen cuánta plata
-- hay en juego HOY, leída de las fotos congeladas —lo que se retuvo de verdad—
-- y no de un recálculo.

select
  (select count(*) = 4 from tasas_pension where regimen like '%\_mixta')
    as las_cuatro_tasas_mixtas_existen,

  (select bool_and(aporte + comision + prima = 0.11370)
     from tasas_pension where regimen like '%\_mixta')
    as todas_descuentan_11_37,

  (select pg_get_constraintdef(oid) like '%integra_mixta%'
     from pg_constraint where conname = 'asignaciones_regimen_pension_regimen_valido')
    as el_historial_acepta_los_codigos_nuevos,

  (select count(distinct persona_id) from planilla_pagada_detalle f
    where f.fila->>'regimen_pension' in ('integra','prima','profuturo','habitat'))
    as personas_hoy_en_comision_sobre_flujo,

  (select count(distinct periodo_id) from planilla_pagada_detalle f
    where f.fila->>'regimen_pension' in ('integra','prima','profuturo','habitat'))
    as periodos_ya_pagados_involucrados,

  -- Cuánto se retuvo de más SI resultara que todas esas personas están en mixta.
  -- Es el techo del problema, no el problema: el número final depende de a
  -- cuántas confirme el contador. La base se despeja del propio descuento
  -- congelado (descuento / tasa) para no depender de recalcular nada.
  (select round(sum(
            f.descuento_pension
            - round((f.descuento_pension / nullif((f.fila->>'tasa_afp')::numeric, 0))
                    * 0.11370, 2)), 2)
     from planilla_pagada_detalle f
    where f.fila->>'regimen_pension' in ('integra','prima','profuturo','habitat')
      and coalesce((f.fila->>'tasa_afp')::numeric, 0) > 0)
    as soles_retenidos_de_mas_si_todas_fueran_mixta;
