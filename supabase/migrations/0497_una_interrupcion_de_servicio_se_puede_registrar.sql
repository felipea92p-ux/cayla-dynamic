-- ============================================================================
-- 0497 · Una interrupción de servicio se puede registrar
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el sistema tenga DÓNDE escribir «esta persona estuvo fuera del servicio
--   del día A al día B, por acuerdo y sin goce de haber», y una sola función que
--   conteste «¿cuántos días de esos hay entre estas dos fechas?». Nada más.
--   Ningún cálculo existente cambia con esta migración: los días de vacaciones,
--   la liquidación y la reserva dan hoy lo mismo que ayer. La 0498 es la que hace
--   que el contador lea esto, y por eso son dos migraciones (ver abajo).
--
-- QUÉ ASUME
--   · La 0101 (`tipos_ausencia`, `ausencias` y su restricción `ausencias_sin_solape`).
--   · Que NO hace falta ninguna tabla nueva: una interrupción de servicio es una
--     ausencia más, con su aprobación, su anulación con motivo y su rastro. Es la
--     misma decisión de la 0101 —«ausencias, un solo lugar»— y se respeta.
--
-- ── EL CASO REAL (producción, 2026-09-29) ────────────────────────────────────
--   La pantalla de Provisiones mostraba 15.0 días de vacaciones para una
--   integrante que cumple su primer año en esos días. Los datos: ingreso hace un
--   año, sin cese, con sueldo continuo — y SETENTA Y UN DÍAS seguidos sin una sola
--   marca en el medio (diez semanas), sin ninguna ausencia escrita que los
--   explique. (Fechas y nombre no se commitean: son datos personales.)
--   La cuenta de días es `15 × días de calendario ÷ 365` (`fn_vacaciones_saldo_
--   interno`, 0357): no lee `ausencias`, así que aunque alguien hubiera registrado
--   esos 71 días como lo que fueran, el contador habría seguido diciendo 15.0. Y
--   la liquidación al cesar paga desde ese mismo contador.
--
--   El defecto no es aritmético: es que el modelo no tenía cómo representar «estuvo
--   fuera». Esta migración le da esa forma; la 0498 le enseña al contador a leerla.
--
-- ── POR QUÉ DOS MIGRACIONES (y no una) ───────────────────────────────────────
--   Esta solo AGREGA: una columna, una fila de catálogo, dos funciones internas.
--   No reescribe ninguna función existente, así que no necesita el md5 de partida
--   de producción, se puede pegar sola y se revierte borrando lo que agregó. La
--   0498 SÍ reescribe funciones que tocan plata, y ahí sí corre el protocolo
--   completo. Mezclarlas obligaría a esperar el protocolo para poder registrar
--   lo que pasó, que es justo lo que no depende de nada.
--
-- ── EL INTERRUPTOR NACE APAGADO, Y ES A PROPÓSITO ────────────────────────────
--   `licencia_sin_goce.suspende_record` se crea en FALSE. Si los días de una
--   licencia sin goce restan del año de servicio es una regla legal (¿cómputo
--   como días efectivos de trabajo?) que se le consulta al laboralista, no una
--   regla que un ingeniero decida por su cuenta. Con el interruptor apagado se
--   puede REGISTRAR desde hoy —queda el rastro— y no cambia ni un día ni un
--   sol. Cuando la respuesta llegue, se enciende con una línea, SIN migración:
--
--     update tipos_ausencia set suspende_record = true where codigo = 'licencia_sin_goce';
--
--   y todo lo ya registrado cuenta desde ese momento, sin volver a escribir nada.
--   Se apaga con la misma línea al revés. Es el mismo criterio de la 0101: la
--   política de permisos vive en el catálogo, no en el esquema.
--
-- ── LOS DOS ESTADOS IMPOSIBLES, HECHOS IMPOSIBLES EN EL ESQUEMA ──────────────
--   1. `suspende_record` y `paga` a la vez. Un día PAGADO es un día de servicio:
--      si un tipo suspendiera el año y además pagara, la persona cobraría por un
--      tiempo que la cuenta dice que no existió. Constraint, no validación.
--   2. `suspende_record` y `descuenta_vacaciones` a la vez. Las vacaciones son
--      servicio (por eso `descuenta_vacaciones` gasta el saldo, no el año).
--   Dos ausencias que se pisan (y por tanto días contados dos veces) ya eran
--   imposibles desde la 0101 (`ausencias_sin_solape`): el conteo no necesita
--   deduplicar nada porque el esquema no deja que haya nada que deduplicar.
--
-- ── SOLO CUENTAN LAS APROBADAS ───────────────────────────────────────────────
--   Una licencia sin goce `requiere_aprobacion = true`: recorta vacaciones de una
--   persona, así que la decide un humano de DO. Mientras esté pendiente no cuenta
--   —mismo criterio que la 0306 para el descanso médico y la maternidad— y si se
--   anula (con motivo, como cualquier ausencia) deja de contar.
--   El registro de una ausencia que cruza un periodo YA PAGADO sigue bloqueado
--   por `fn_registrar_ausencia` (0327); esta migración no lo toca. Es el freno
--   correcto en general; para un caso retroactivo puntual hay un camino aparte,
--   que se hace a mano y con rastro, y no vive en git porque nombra a una persona.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ────────────────────────────────────────────
--   · No cambia `fn_vacaciones_saldo_interno`, `fn_vacaciones_truncas`,
--     `fn_vacaciones_resumen` ni `fn_provisiones` — eso es la 0498.
--   · No decide qué son los 71 días del caso real. Eso lo sabe DO, no el sistema.
--   · No paga ni descuenta nada: la planilla no lee `ausencias` (medido en la
--     0247), así que registrar esto no mueve un sol. Para quien cobra por horas
--     marcadas, un día sin marca ya pagaba cero; para un sueldo fijo habría que
--     mirar aparte (no es el caso que motiva esto).
--
-- CÓMO SE REVIERTE (en este orden, solo si nadie usó todavía el tipo):
--   drop function if exists fn_fecha_ingreso_efectiva(uuid, date);
--   drop function if exists fn_dias_suspendidos(uuid, date, date);
--   delete from tipos_ausencia where codigo = 'licencia_sin_goce';
--   alter table tipos_ausencia drop constraint if exists tipos_ausencia_suspension_no_descuenta;
--   alter table tipos_ausencia drop constraint if exists tipos_ausencia_suspension_no_paga;
--   alter table tipos_ausencia drop column if exists suspende_record;
--   (`ausencias.tipo` tiene FK contra el catálogo: con filas registradas el
--   delete falla en vez de dejarlas huérfanas — es la protección buscada.)
-- ============================================================================

-- ── 1 · La columna, y lo que no puede pasar con ella ────────────────────────
alter table tipos_ausencia
  add column if not exists suspende_record boolean not null default false;

comment on column tipos_ausencia.suspende_record is
  'Si es true, los días de una ausencia APROBADA de este tipo NO cuentan como servicio para ganar vacaciones (el año se corre tantos días como dure). Nace apagado en licencia_sin_goce hasta que el laboralista confirme la regla; se enciende con un update, sin migración. No puede convivir con paga ni con descuenta_vacaciones (ver constraints).';

alter table tipos_ausencia drop constraint if exists tipos_ausencia_suspension_no_paga;
alter table tipos_ausencia add constraint tipos_ausencia_suspension_no_paga
  check (not (suspende_record and paga));

alter table tipos_ausencia drop constraint if exists tipos_ausencia_suspension_no_descuenta;
alter table tipos_ausencia add constraint tipos_ausencia_suspension_no_descuenta
  check (not (suspende_record and descuenta_vacaciones));

-- ── 2 · El tipo ─────────────────────────────────────────────────────────────
-- paga=false            no devenga nada esos días: no hay pago que devengar.
-- requiere_documento    false: el acuerdo lo firma la empresa, no lo trae ella.
-- requiere_aprobacion   true: recorta el año de servicio de una persona.
-- descuenta_vacaciones  false: no le gasta saldo, es otra cosa.
-- suspende_record       FALSE al nacer (ver «El interruptor nace apagado»).
-- orden = 65            con los que no pagan, después del permiso personal (60).
--
-- `do nothing` y no `do update`: se pega dos veces y la segunda NO pisa el
-- interruptor si alguien ya lo encendió desde la base. Es la forma de la 0101 y
-- de la 0247 y aquí importa más que allá.
insert into tipos_ausencia
  (codigo, nombre, paga, requiere_documento, requiere_aprobacion,
   descuenta_vacaciones, suspende_record, alerta_desde, ventana_alerta_dias, orden)
values
  ('licencia_sin_goce', 'Licencia sin goce de haber',
   false, false, true, false, false, null, null, 65)
on conflict (codigo) do nothing;

-- ── 3 · Cuántos días de interrupción hay entre dos fechas ───────────────────
-- CONTRATO
--   Promete: los días de calendario de [p_desde, p_hasta] cubiertos por
--            ausencias APROBADAS, NO anuladas, de un tipo con suspende_record.
--   Asume:   que ninguna ausencia de la persona se pisa con otra
--            (`ausencias_sin_solape`), así que sumar longitudes no cuenta un
--            día dos veces.
--   Da 0 si p_desde > p_hasta, si no hay ninguna, o si el interruptor está
--   apagado en todos los tipos.
--
-- INTERNA: sin ningún permiso para `authenticated`. Contestar «cuánto estuvo
-- fuera fulana» a quien no debe verlo sería el mismo agujero que la 0357 cerró
-- en el saldo de vacaciones. Las funciones que la llaman son SECURITY DEFINER
-- con su propia guardia, y esas sí pueden ejecutarla.
create or replace function fn_dias_suspendidos(p_persona_id uuid, p_desde date, p_hasta date)
returns integer
language sql stable security definer set search_path = public
as $fn$
  select coalesce(sum(
           greatest(0, least(a.fecha_fin, p_hasta) - greatest(a.fecha_inicio, p_desde) + 1)
         ), 0)::integer
    from ausencias a
    join tipos_ausencia t on t.codigo = a.tipo
   where a.persona_id = p_persona_id
     and a.anulada_at is null
     and a.aprobada_at is not null
     and t.suspende_record
     and a.fecha_fin >= p_desde
     and a.fecha_inicio <= p_hasta;
$fn$;
revoke all on function fn_dias_suspendidos(uuid, date, date) from public, anon, authenticated;

-- ── 4 · La fecha desde la que corre el servicio efectivo ────────────────────
-- CONTRATO
--   Promete: `fecha_ingreso` corrida hacia adelante tantos días como haya estado
--            fuera del servicio hasta p_as_of. Es la fecha que TENDRÍA de ingreso
--            si esos días no hubieran existido — por eso restar días y correr el
--            aniversario son la misma cuenta, y no dos reglas distintas.
--   Asume:   nada más que lo de fn_dias_suspendidos.
--   Nunca es posterior a p_as_of (quien estuvo fuera todo el tiempo tiene cero
--   servicio, no servicio negativo) ni anterior al ingreso real.
--   Sin ninguna interrupción devuelve EXACTAMENTE `fecha_ingreso`: por eso la
--   0498 puede reemplazar `fecha_ingreso` por esta función sin cambiarle el
--   resultado a nadie que no tenga una.
create or replace function fn_fecha_ingreso_efectiva(p_persona_id uuid, p_as_of date)
returns date
language sql stable security definer set search_path = public
as $fn$
  select least(
           p.fecha_ingreso + fn_dias_suspendidos(p.id, p.fecha_ingreso, p_as_of),
           greatest(p_as_of, p.fecha_ingreso)
         )
    from personas p
   where p.id = p_persona_id;
$fn$;
revoke all on function fn_fecha_ingreso_efectiva(uuid, date) from public, anon, authenticated;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (497, 'una_interrupcion_de_servicio_se_puede_registrar')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
