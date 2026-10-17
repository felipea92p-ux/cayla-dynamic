-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 396_la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230.test.sql — migración 0502
-- ============================================================================
-- La 0501 subió la RMV a S/ 1,230 el 2026-10-01 pero NO alcanzó a los
-- practicantes (`fn_fijar_base_declarada` exige `en_planilla`). La 0502 alinea la
-- subvención PACTADA de ellos a la RMV, por regla —practicante activo, subvención
-- bajo su referencia— y nunca por rango. Esta prueba mide lo que esa migración
-- PROMETE (y no dice nada de lo que NO promete: que la boleta llegue a esa cifra
-- es consulta abierta con el laboralista).
--
--   A · LA REGLA: quién sube, a cuánto, y quién queda como está. Es la vista
--       `v0502` de la migración, PALABRA POR PALABRA (la compara
--       tests/practicantes-subvencion-misma-regla.test.ts), sobre una veintena
--       de practicantes que cubren cada rama: jornada completa supuesta, convenio
--       de 20 h (referencia proporcional 820), de 30 h y de 40 h (el tope en
--       30 h), un borrador con horas que también protege, el convenio ANULADO que
--       no cuenta, convenios EN CONFLICTO (horas distintas entre sí; uno firmado
--       con horas y otro posterior sin ellas) que la migración no resuelve a
--       ciegas, quien ya cobra su referencia o más (NO baja), sin modalidad, sin
--       tramo, ingreso posterior al 1-oct, y cuentas de servicio, inactivos y
--       personas de otros vínculos, que la regla ni mira.
--
--   B · LA ACCIÓN, como la hace la migración: `fn_set_salario` por persona con
--       el rango que ya tiene, y la base legal solo si era menor. El tramo viejo
--       se cierra el 30-sep, el nuevo abre el 1-oct, nadie baja, y repetirlo no
--       abre tramos.
--
--   C · LA PLANILLA LO LEE BIEN: un practicante que marca 6.5 h los 31 días del
--       periodo 28-sep → 28-oct cobra 3/31 × 1,130 + 28/31 × 1,230 → 1,220.32,
--       no 1,230: tres días de septiembre al sueldo de septiembre. Y su EsSalud
--       no aparece: desde la 0504 el practicante no genera EsSalud (antes era el
--       piso puro, 110.70; la prueba lo afirmaba así y la 0504 lo cambió a propósito).
--
--   D · EL TRAMO QUE EMPIEZA EL 1-OCT: `fn_set_salario` BORRA todo tramo con
--       vigente_desde >= la fecha. Quien ingresó HOY y cobra menos que su
--       referencia perdería el único tramo que tiene, y la reversión lo dejaría
--       sin ninguno: la regla lo marca (`desde_oct`) y la migración se detiene.
--
--   E · EL CANDADO ES POR GRUPO: con el grupo «planilla» pagado, el sueldo de un
--       practicante todavía se puede subir; con el grupo «practicante» pagado,
--       no. Es la premisa de «pegar antes de pagar».
--
-- NOTA HONESTA SOBRE QUÉ NO PUEDE VER: el bloque que ejecuta la subida en la
-- migración es un `do $$` anónimo y esta prueba no puede ejecutarlo (pgTAP no lee
-- archivos del servidor, y un `\i` metería su begin/commit dentro de la
-- transacción de la prueba y haría persistir los datos). Lo que sí comprueba es
-- la REGLA, que es la misma que ejecuta la migración —incluida la clasificación
-- «conflicto_convenios», que es lo que la hace detenerse—, y cada pieza sobre la
-- que se apoya la subida. El ensayo del bloque completo —los casos que lo
-- detienen, el candado de una sola pegada a la vez, la idempotencia, «nadie baja»,
-- la guardia y las mutaciones que la hacen fallar— se hizo contra la cadena
-- completa en una base desechable y está descrito en docs/estado.md.
--
-- Cuando salga el segundo tramo de la RMV (S/ 1,300) esta prueba se actualiza A
-- PROPÓSITO: es parte del recordatorio de que la referencia vuelve a subir.
-- ============================================================================
begin;
select plan(48);

-- ── El laboratorio ──────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre)
values ('11111111-1111-1111-1111-111111111396', 'Z396', 'Sede de prueba 396')
on conflict do nothing;

-- Sesión de admin: `replica` salta la clave foránea contra auth.users, que acá no existe.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('d0396000-0000-0000-0000-0000000000aa', 'Admin', 'Prueba', '11111111-1111-1111-1111-111111111396',
        'admin', 'x', 'aaaaaaaa-3960-0000-0000-00000000aaaa', date '2020-01-01');
set session_replication_role = origin;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('22222222-3960-0000-0000-000000000001', date '2026-08-29', date '2026-09-27', 'pagado'),
  ('22222222-3960-0000-0000-000000000002', date '2026-09-28', date '2026-10-28', 'abierto');

-- Alta de un practicante (o de cualquier otro vínculo, como control).
create or replace function pg_temp.prac(
  p_n int, p_modalidad text, p_sal numeric, p_base numeric,
  p_ingreso date default date '2026-03-02', p_estado text default 'activo',
  p_cs boolean default false, p_rango text default 'colibri',
  p_desde date default date '2026-03-02', p_vinculo text default 'practicante')
returns void language plpgsql as $$
declare v uuid := ('d0396000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
begin
  insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, estado, tipo_vinculo,
                        practicante_modalidad, sueldo_base_legal, fecha_ingreso,
                        cuenta_de_servicio, fecha_cese)
  values (v, 'Prac' || lpad(p_n::text, 2, '0'), 'Lab', '11111111-1111-1111-1111-111111111396', 'x',
          p_estado, p_vinculo, p_modalidad, p_base, p_ingreso, p_cs,
          case when p_estado = 'inactivo' then date '2026-08-31' end);
  if p_sal is not null then
    insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
    values (v, p_rango, p_sal, p_desde);
  end if;
end $$;

-- Un convenio de prácticas NO anulado (con horas, o sin ellas si p_horas es nulo),
-- firmado o en borrador. La fecha de inicio ya no decide «cuál manda»: valen todos.
create or replace function pg_temp.conv(
  p_n int, p_horas numeric, p_inicio date default date '2026-03-02',
  p_anulado boolean default false, p_firmado boolean default false)
returns void language plpgsql as $$
declare v uuid := ('d0396000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
begin
  insert into contratos_generados
    (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin,
     horas_semanales, documento_html, generado_por, anulado_at, anulado_por, anulado_motivo,
     fecha_firma, registrado_por)
  values (v, 'convenio_practicas', 'Practicante', '11111111-1111-1111-1111-111111111396', 1130,
          p_inicio, p_inicio + 365, p_horas, '<p>x</p>', 'd0396000-0000-0000-0000-0000000000aa',
          case when p_anulado then now() end,
          case when p_anulado then 'd0396000-0000-0000-0000-0000000000aa'::uuid end,
          case when p_anulado then 'laboratorio 396' end,
          case when p_firmado then p_inicio + 2 end,
          case when p_firmado then 'd0396000-0000-0000-0000-0000000000aa'::uuid end);
end $$;

select pg_temp.prac(1,  'profesional',    1130, 1130);                                 -- sube a 1230
select pg_temp.prac(2,  'profesional',    1130, null, p_rango => 'cayla');             -- sube; base nula se queda nula; rango cayla
select pg_temp.prac(3,  'preprofesional', 1130, 1130);                                 -- sube: jornada completa SUPUESTA
select pg_temp.prac(4,  'preprofesional', 1130, 1130);                                 -- convenio 20 h: piso 820, NO se toca
select pg_temp.prac(5,  'preprofesional',  700,  700);                                 -- convenio 20 h: sube a 820, no a 1230
select pg_temp.prac(6,  'preprofesional', 1130, 1130);                                 -- convenio 30 h: sube a 1230
select pg_temp.prac(7,  'profesional',    1230, 1230);                                 -- ya cumple
select pg_temp.prac(8,  'profesional',    1300, 1300);                                 -- cobra por encima: NO baja
select pg_temp.prac(9,  null,             1130, 1130);                                 -- sin modalidad: omitida
select pg_temp.prac(10, 'profesional',    null, null);                                 -- sin tramo: omitida
select pg_temp.prac(11, 'profesional',    1130, 1130, p_cs => true);                   -- cuenta de servicio: la regla ni la mira
select pg_temp.prac(12, 'profesional',    1130, 1130, p_estado => 'inactivo');         -- inactivo: la regla ni lo mira
select pg_temp.prac(13, 'profesional',    1130, 1130, p_ingreso => date '2026-10-05',
                        p_desde => date '2026-10-05');                                 -- ingreso posterior sin horas: omitida
select pg_temp.prac(14, 'preprofesional', 1130, 1130, p_ingreso => date '2026-10-05',
                        p_desde => date '2026-10-05');                                 -- ingreso posterior CON horas (20): su piso proporcional
select pg_temp.prac(15, 'preprofesional', 1130, 1130);                                 -- dos convenios con horas DISTINTAS (20 y 30): CONFLICTO
select pg_temp.prac(16, 'profesional',    1130, 1130, p_rango => 'oraculo');           -- rango oráculo: para probar que la 0501 no los alcanza
select pg_temp.prac(17, 'preprofesional', 1130, 1130);                                 -- convenio FIRMADO de 20 h y otro POSTERIOR sin horas: CONFLICTO
select pg_temp.prac(18, 'preprofesional',  700,  700);                                 -- un BORRADOR (sin firmar) con 20 h: también protege
select pg_temp.prac(19, 'preprofesional', 1130, 1130);                                 -- dos convenios de 20 h (renovación) + uno sin horas ANULADO: no es conflicto
select pg_temp.prac(27, 'preprofesional', 1300, 1300);                                 -- convenio de 40 h (más que la jornada máxima de su modalidad): tope en 30 h
-- Controles: personas que la 0502 NO debe mover.
select pg_temp.prac(20, null, 1130, 1130, p_vinculo => 'planilla');                    -- integrante en planilla
select pg_temp.prac(21, null, 1130, 1130, p_vinculo => 'rxh');                         -- locador
select pg_temp.prac(22, null, 1130, 1130, p_vinculo => 'prueba');                      -- en periodo de prueba

select pg_temp.conv(4, 20);
select pg_temp.conv(5, 20);
select pg_temp.conv(6, 30);
select pg_temp.conv(14, 20, date '2026-10-05');
select pg_temp.conv(3, 20, date '2026-03-02', true);                                   -- ANULADO con 20 h: no cuenta
select pg_temp.conv(15, 20, date '2026-03-02');                                        -- uno dice 20 h…
select pg_temp.conv(15, 30, date '2026-09-01');                                        -- …el otro dice 30 h: se contradicen, no manda «el más reciente»
select pg_temp.conv(17, 20, date '2026-03-02', false, true);                           -- FIRMADO, 20 h…
select pg_temp.conv(17, null, date '2026-09-01');                                      -- …y un borrador posterior SIN horas: se contradicen
select pg_temp.conv(18, 20, date '2026-03-02');                                        -- borrador con 20 h: cuenta
select pg_temp.conv(27, 40);                                                           -- 40 h: el piso proporcional tiene tope en 30 h (RMV entera, nunca más)
select pg_temp.conv(19, 20, date '2026-03-02');                                        -- 20 h…
select pg_temp.conv(19, 20, date '2026-09-01');                                        -- …y 20 h otra vez: coinciden, no hay conflicto
select pg_temp.conv(19, null, date '2026-06-01', true);                                -- un convenio sin horas ANULADO: no cuenta
select pg_temp.conv(1, null);                                                          -- un convenio sin horas (profesional: el generador no las guarda)…
select pg_temp.conv(1, null, date '2026-09-01');                                       -- …y otro: dos sin horas NO son conflicto, solo suposición

-- Un practicante que marca 6.5 h los 31 días del periodo abierto (asistencia completa).
insert into jornadas (persona_id, fecha, horas_trabajadas)
select 'd0396000-0000-0000-0000-000000000001', d::date, 6.5
  from generate_series(date '2026-09-28', date '2026-10-28', interval '1 day') d;

select set_config('request.jwt.claim.sub', 'aaaaaaaa-3960-0000-0000-00000000aaaa', true);

-- ── La regla: LA MISMA que la migración y que el script de comprobación ─────
create temporary view v0502 as
-- >>> REGLA 0502
with
conv as (
  -- Los convenios de prácticas NO anulados de cada persona que TRAEN horas
  -- pactadas, firmados o en borrador: equivocarse hacia «protegerlo» se arregla
  -- pegando de nuevo; subir de más no se deshace. Valen todos juntos, no «el más
  -- reciente»: si dicen cosas distintas esa persona es un CONFLICTO (abajo).
  select c.persona_id,
         min(c.horas_semanales)                as horas,
         count(distinct c.horas_semanales) > 1 as horas_distintas
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
     and c.horas_semanales is not null
   group by c.persona_id
),
sin_horas as (
  -- Los NO anulados que NO traen horas: el generador no pudo determinarlas, o es
  -- el convenio de un profesional, a quien nunca se le guardan.
  select distinct c.persona_id
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
     and c.horas_semanales is null
),
rmv as (
  -- La RMV tal como la lee la planilla: la fila vigente en esa fecha.
  select pl.valor
    from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null
     and pl.vigente_desde <= date '2026-10-01'
     and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-01')
   order by pl.vigente_desde desc
   limit 1
),
base as (
  select p.id as persona_id,
         a.rango,
         a.salario_mensual_soles as sal,
         p.sueldo_base_legal     as base,
         a.base_provision        as bp,
         p.sueldo_fijo           as sfijo,
         p.fecha_ingreso         as ingreso,
         p.practicante_modalidad as modalidad,
         cv.horas                as horas,
         (cv.horas is null)      as asumida,
         -- Dos convenios vigentes que se CONTRADICEN: horas distintas entre sí, o
         -- uno con horas y otro sin ellas. No se elige cuál «manda»: la migración
         -- se detiene y Felipe decide a mano.
         (coalesce(cv.horas_distintas, false)
          or (cv.persona_id is not null and sh.persona_id is not null)) as conflicto,
         (select r.valor from rmv r)  as rmv,
         -- Un tramo de sueldo que EMPIEZA el 1-oct o después: programado, o el de
         -- quien ingresó hoy o más tarde. fn_set_salario BORRA todo tramo con
         -- vigente_desde >= la fecha, y la reversión —que reabre el tramo cerrado
         -- el 30-sep— lo dejaría sin ninguno.
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde >= date '2026-10-01') as desde_oct,
         -- Un cambio de sueldo ya programado: un tramo CERRADO que todavía cubre
         -- el 1-oct. Lo que se pagará ese día no es el tramo abierto que lee la
         -- regla sino ese, y no se resuelve a ciegas.
         exists (select 1 from asignaciones_salario f
                  where f.persona_id = p.id
                    and f.vigente_desde <= date '2026-10-01'
                    and f.vigente_hasta >= date '2026-10-01') as programado
    from personas p
    left join asignaciones_salario a
      on a.persona_id = p.id and a.vigente_hasta is null
    left join conv cv on cv.persona_id = p.id
    left join sin_horas sh on sh.persona_id = p.id
   where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
     and coalesce(p.cuenta_de_servicio, false) = false
),
con_piso as (
  select b.*,
         case when b.conflicto then null
              when b.modalidad = 'preprofesional' and b.horas is not null
              then round(b.rmv * least(b.horas, 30) / 30, 2)
              else b.rmv end as piso
    from base b
)
select c.persona_id, c.rango, c.modalidad, c.horas, c.asumida, c.conflicto,
       c.sal, c.base, c.bp, c.sfijo, c.desde_oct, c.programado, c.rmv, c.piso,
       case
         when c.conflicto then 'conflicto_convenios'
         when c.modalidad is null then 'omitida_sin_modalidad'
         when c.rango is null then 'omitida_sin_tramo'
         when c.asumida and c.ingreso > date '2026-10-01' then 'omitida_ingreso_posterior'
         when c.sal >= c.piso
           then case when c.piso < c.rmv then 'cumple_jornada_reducida' else 'cumple' end
         when c.sal < c.piso then 'sube'
         else 'sin_dato'
       end as accion
  from con_piso c
-- <<< REGLA 0502
;

-- Lo que la regla dice de la persona N del laboratorio.
create or replace function pg_temp.dice(p_n int) returns text language sql as $$
  select coalesce((select accion || ' · piso ' || coalesce(piso::numeric(10,2)::text, 'sin calcular') from v0502
                    where persona_id = ('d0396000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid),
                  'fuera de la regla')
$$;
-- Los tramos de la persona N, en orden: «salario:desde:hasta».
create or replace function pg_temp.tramos(p_n int) returns text[] language sql as $$
  select coalesce(array_agg(salario_mensual_soles::text || ':' || vigente_desde::text || ':'
                            || coalesce(vigente_hasta::text, 'abierto') order by vigente_desde), '{}')
    from asignaciones_salario
   where persona_id = ('d0396000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid
$$;
create or replace function pg_temp.base(p_n int) returns numeric language sql as $$
  select sueldo_base_legal from personas
   where id = ('d0396000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid
$$;

-- ── Lo que deja la cadena de migraciones ────────────────────────────────────
select is(
  (select nombre from migraciones_aplicadas where numero = 502),
  'la_subvencion_pactada_de_los_practicantes_sigue_a_la_rmv_de_1230',
  'la 0502 dejó su fila en el registro con su nombre (no solo con su número)');

select is(
  (select pl.valor from parametros_laborales pl
    where pl.clave = 'rmv' and pl.sede_codigo is null
      and pl.vigente_desde <= date '2026-10-01'
      and (pl.vigente_hasta is null or pl.vigente_hasta >= date '2026-10-01')
    order by pl.vigente_desde desc limit 1),
  1230::numeric(12,5),
  'la 0502 está atada a la 0501: la RMV que la regla lee el 1-oct es S/ 1,230');

-- ── A · La regla: quién sube, y a cuánto ────────────────────────────────────
select is(pg_temp.dice(1),  'sube · piso 1230.00',
  'profesional sin convenio bajo 1,230: SUBE a la RMV entera (jornada completa SUPUESTA)');
select is(pg_temp.dice(2),  'sube · piso 1230.00',
  'el rango NO decide: un practicante de rango cayla también sube');
select is(pg_temp.dice(3),  'sube · piso 1230.00',
  'preprofesional sin horas pactadas: sube a 1,230; su convenio ANULADO de 20 h no cuenta');
select is(pg_temp.dice(4),  'cumple_jornada_reducida · piso 820.00',
  'preprofesional con convenio de 20 h cobrando 1,130: ya está sobre su piso proporcional (820) y NO se toca');
select is(pg_temp.dice(5),  'sube · piso 820.00',
  'preprofesional de 20 h cobrando 700: sube a 820, NO a 1,230 (subirle de más no se puede deshacer)');
select is(pg_temp.dice(6),  'sube · piso 1230.00',
  'preprofesional con convenio de 30 h (la jornada máxima): su piso es la RMV entera');
select is(pg_temp.dice(7),  'cumple · piso 1230.00',
  'quien ya cobra 1,230 cumple: no se le abre un tramo');
select is(pg_temp.dice(8),  'cumple · piso 1230.00',
  'quien cobra 1,300 cumple: la migración solo sube, nunca iguala');
select is(pg_temp.dice(9),  'omitida_sin_modalidad · piso 1230.00',
  'sin modalidad no se sabe si su piso podría ser proporcional: queda FUERA y se cuenta');
select is(pg_temp.dice(10), 'omitida_sin_tramo · piso 1230.00',
  'sin subvención cargada no se inventa un monto: queda FUERA y se cuenta');
select is(pg_temp.dice(13), 'omitida_ingreso_posterior · piso 1230.00',
  'quien ingresó después del 1-oct y no tiene horas pactadas queda FUERA: la suposición no lo cubre');
select is(pg_temp.dice(14), 'cumple_jornada_reducida · piso 820.00',
  'quien ingresó después del 1-oct pero SÍ tiene horas en su convenio no es suposición: se evalúa con su piso proporcional');
select is(pg_temp.dice(15), 'conflicto_convenios · piso sin calcular',
  'dos convenios vigentes con horas DISTINTAS (20 y 30): conflicto. No manda «el más reciente»: la migración se detiene y Felipe decide a mano');
select is(pg_temp.dice(17), 'conflicto_convenios · piso sin calcular',
  'un convenio FIRMADO de 20 h y otro posterior SIN horas: conflicto, no «asumida». Antes subía a 1,230 a quien firmó 20 h');
select is(pg_temp.dice(18), 'sube · piso 820.00',
  'un BORRADOR (sin firmar) con 20 h también protege: sube a 820, no a 1,230 (equivocarse hacia «protegerlo» se arregla pegando de nuevo)');
select is(pg_temp.dice(19), 'cumple_jornada_reducida · piso 820.00',
  'dos convenios de 20 h que coinciden no son conflicto, y un convenio sin horas ANULADO no cuenta: queda en su referencia proporcional (820) y no se toca');
select is(pg_temp.dice(27), 'cumple · piso 1230.00',
  'un convenio de 40 h NO sube la referencia por encima de la RMV: el piso proporcional tiene tope en 30 h');
select is(
  (select count(*)::int from v0502
    where persona_id in ('d0396000-0000-0000-0000-000000000011',
                         'd0396000-0000-0000-0000-000000000012',
                         'd0396000-0000-0000-0000-000000000020',
                         'd0396000-0000-0000-0000-000000000021',
                         'd0396000-0000-0000-0000-000000000022')),
  0,
  'la regla ni mira una cuenta de servicio, un inactivo, un integrante en planilla, un locador ni uno en prueba');

-- ── Por qué existe la 0502: la 0501 no los alcanzaba ────────────────────────
select lives_ok(
  $$select * from fn_fijar_base_declarada('oraculo', 1440.00, date '2026-10-01', '{}')$$,
  'la función de la 0501 corre sobre el rango de un practicante sin fallar…');
select is(pg_temp.tramos(16), array['1130.00:2026-03-02:abierto'],
  '…y no lo alcanza: exige en_planilla, y un practicante no está en planilla (por eso hace falta la 0502)');

-- ── C · La planilla lee bien lo de antes (antes de subir) ───────────────────
select is(
  (select (f->>'pago_base')::numeric
     from jsonb_array_elements(fn_planilla_calcular(date '2026-09-28', date '2026-10-28')->'filas') f
    where f->>'nombre' = 'Prac01 Lab'),
  1130.00,
  'ANTES: con 6.5 h los 31 días del periodo, el practicante cobra su subvención entera, 1,130');

-- ── B · La acción, como la hace la migración ────────────────────────────────
-- La foto de quién sube se toma ANTES de subir: la regla es una vista viva y
-- después de subir ya no los encontraría.
create temporary table suben on commit drop as
select * from v0502 where accion = 'sube';

select is((select count(*)::int from suben), 7,
  'suben siete: 1, 2, 3, 5, 6, 16 y 18 (y solo ellos; los dos conflictos de convenios NO suben)');

create temporary table tramos_antes on commit drop as
select count(*)::int as n from asignaciones_salario;

select lives_ok($$
  select fn_set_salario(s.persona_id, s.rango, s.piso, date '2026-10-01', 'prueba 396 · Migración 0502.')
    from suben s order by s.persona_id;
  select fn_set_sueldo_base_legal(s.persona_id, s.piso)
    from suben s where s.base is not null and s.base < s.piso order by s.persona_id
$$, 'subir a cada uno hasta su piso, con el rango que ya tiene, pasa el candado de periodo pagado');

select is(pg_temp.tramos(1), array['1130.00:2026-03-02:2026-09-30', '1230.00:2026-10-01:abierto'],
  'el tramo viejo se cierra el 30-sep y el nuevo abre el 1-oct: el 28, 29 y 30 de septiembre se pagan al sueldo de septiembre');
select is(pg_temp.base(1), 1230.00,
  'la base legal sube con la subvención, para que la constancia diga lo que se paga');
select is(
  (select rango from asignaciones_salario
    where persona_id = 'd0396000-0000-0000-0000-000000000002' and vigente_hasta is null),
  'cayla',
  'el rango NO cambia: solo se abre un tramo nuevo con el mismo rango');
select is(pg_temp.base(2), null::numeric,
  'una base legal nula («sin confirmar») se queda nula: no se inventa');
select is(pg_temp.tramos(5), array['700.00:2026-03-02:2026-09-30', '820.00:2026-10-01:abierto'],
  'el de 20 h pasa de 700 a 820 —su piso proporcional— y NO a 1,230');
select is(pg_temp.base(5), 820.00, 'y su base legal sube a 820, no a 1,230');
select is(pg_temp.tramos(4), array['1130.00:2026-03-02:abierto'],
  'el de 20 h que ya cobraba 1,130 queda EXACTAMENTE como estaba, sin un tramo nuevo');
select is(pg_temp.tramos(7) || pg_temp.tramos(8),
  array['1230.00:2026-03-02:abierto', '1300.00:2026-03-02:abierto'],
  'quien ya cobraba 1,230 y quien cobraba 1,300 no se tocan: nadie baja y nadie se iguala');
select is(
  pg_temp.tramos(9) || pg_temp.tramos(10) || pg_temp.tramos(11) || pg_temp.tramos(12) || pg_temp.tramos(13),
  array['1130.00:2026-03-02:abierto', '1130.00:2026-03-02:abierto',
        '1130.00:2026-03-02:abierto', '1130.00:2026-10-05:abierto'],
  'los omitidos (sin modalidad, sin tramo, ingreso posterior) y la cuenta de servicio y el inactivo no se mueven');
select is(
  pg_temp.tramos(20) || pg_temp.tramos(21) || pg_temp.tramos(22),
  array['1130.00:2026-03-02:abierto', '1130.00:2026-03-02:abierto', '1130.00:2026-03-02:abierto'],
  'ni el integrante en planilla, ni el locador, ni quien está en prueba: la 0502 es solo de practicantes');
select is(pg_temp.tramos(15) || pg_temp.tramos(17),
  array['1130.00:2026-03-02:abierto', '1130.00:2026-03-02:abierto'],
  'los dos conflictos de convenios quedan EXACTAMENTE como estaban: ninguna subida a ciegas');
select is(pg_temp.tramos(18), array['700.00:2026-03-02:2026-09-30', '820.00:2026-10-01:abierto'],
  'el del borrador de 20 h pasa de 700 a 820 y NO a 1,230');
select is(pg_temp.tramos(19), array['1130.00:2026-03-02:abierto'],
  'el de los dos convenios de 20 h que coinciden y ya cobra 1,130 queda como estaba, sin un tramo nuevo');
select is((select count(*)::int from v0502 where accion = 'sube'), 0,
  'y la regla, vuelta a preguntar DESPUÉS, no encuentra a nadie bajo su piso');

-- ── C · La planilla lee bien lo de después ──────────────────────────────────
-- 3 días × 6.5 h a 1,130 + 28 días × 6.5 h a 1,230, sobre 201.5 h de base.
select is(
  (select (f->>'pago_base')::numeric
     from jsonb_array_elements(fn_planilla_calcular(date '2026-09-28', date '2026-10-28')->'filas') f
    where f->>'nombre' = 'Prac01 Lab'),
  1220.32,
  'DESPUÉS: asistencia completa = 3/31 × 1,130 + 28/31 × 1,230 = 1,220.32: el 28, 29 y 30 de septiembre al sueldo de septiembre');
select is(
  (select (f->>'aporte_essalud')::numeric
     from jsonb_array_elements(fn_planilla_calcular(date '2026-09-28', date '2026-10-28')->'filas') f
    where f->>'nombre' = 'Prac01 Lab'),
  0.00,
  '0504: el practicante ya no genera EsSalud (lo cubre el seguro privado FOLA): queda en 0.00, y la 0502 tampoco lo mueve. Antes era el piso puro, 9 % de 1,230 = 110.70');

-- ── Idempotencia ────────────────────────────────────────────────────────────
select lives_ok($$
  select fn_set_salario(s.persona_id, s.rango, s.piso, date '2026-10-01', 'prueba 396 · Migración 0502.')
    from suben s order by s.persona_id
$$, 'repetir la subida no falla…');
select is((select count(*)::int from asignaciones_salario), (select n from tramos_antes) + 7,
  '…y no abre tramos de más: solo los siete de la primera vez (el tramo del 1-oct se reemplaza, no se apila)');

-- ── D · El tramo que EMPIEZA el 1-oct: la regla lo marca y la migración se detiene ──
-- Quien ingresó el 1-oct y cobra menos que su referencia tiene un único tramo, que
-- empieza ese día. fn_set_salario borra todo tramo con vigente_desde >= la fecha.
select pg_temp.prac(24, 'profesional', 1130, 1130,
                    p_ingreso => date '2026-10-01', p_desde => date '2026-10-01');
select is(
  (select desde_oct and accion = 'sube' from v0502
    where persona_id = 'd0396000-0000-0000-0000-000000000024'),
  true,
  'quien ingresó el 1-oct y cobra menos que su referencia: la regla lo marca «desde_oct» y la migración se DETIENE (no lo sube a ciegas)');
select lives_ok(
  $$select fn_set_salario('d0396000-0000-0000-0000-000000000024', 'colibri', 1230, date '2026-10-01', 'borde 396')$$,
  'si la migración lo subiera igual, fn_set_salario lo aceptaría…');
select is(pg_temp.tramos(24), array['1230.00:2026-10-01:abierto'],
  '…y BORRARÍA su único tramo (el de 1,130 que empezaba el 1-oct): no quedaría ningún tramo cerrado el 30-sep que la reversión pudiera reabrir');

-- ── E · El candado de periodo pagado es por GRUPO ───────────────────────────
select pg_temp.prac(30, 'profesional', 1130, 1130);
insert into periodo_grupo_pago (periodo_id, grupo, estado)
values ('22222222-3960-0000-0000-000000000002', 'planilla', 'pagado');

select lives_ok(
  $$select fn_set_salario('d0396000-0000-0000-0000-000000000030', 'colibri', 1230, date '2026-10-01', 'candado 396')$$,
  'con el grupo PLANILLA pagado, el sueldo de un practicante todavía se puede subir');

insert into periodo_grupo_pago (periodo_id, grupo, estado)
values ('22222222-3960-0000-0000-000000000002', 'practicante', 'pagado');

select throws_like(
  $$select fn_set_salario('d0396000-0000-0000-0000-000000000030', 'colibri', 1240, date '2026-10-01', 'candado 396')$$,
  '%PAGADO%',
  'con el grupo PRACTICANTE pagado ya no: por eso la 0502 se pega ANTES de pagarlos');

select * from finish();
rollback;
