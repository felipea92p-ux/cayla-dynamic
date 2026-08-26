-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 247_un_mes_pagado_se_lee_de_su_foto.test.sql — la 0313
-- ============================================================================
-- Lo que hay que proteger no es que la boleta calcule bien: eso lo cuidan
-- treinta pruebas. Es que un mes YA PAGADO deje de calcularse.
--
-- El defecto que cierra la 0313 se medió en producción el 2026-08-26: 17
-- personas cuya boleta diría hoy un número distinto del que cobraron, porque
-- `fn_planilla_calcular` se reescribió cinco veces ese mismo día y la pantalla
-- la vuelve a llamar cada vez que alguien reimprime julio.
--
-- ── CÓMO SE FALSEA UN CAMBIO DE REGLAS EN UN LABORATORIO ────────────────────
--
-- No se puede reescribir `fn_planilla_calcular` dentro de una prueba. Pero el
-- efecto que interesa es el mismo por el otro lado: se congela la foto, y
-- DESPUÉS se cambia el dato del que el cálculo depende. A partir de ahí el
-- recálculo y la foto dicen cosas distintas — exactamente la situación de julio
-- — y se puede comprobar cuál de las dos entrega la función.
--
-- Aquí el dato que se mueve es un movimiento de planilla: un bono que aparece
-- después del cierre. El recálculo lo suma; la foto, que es de antes, no.
--
-- ── LAS DOS DIRECCIONES ─────────────────────────────────────────────────────
--
-- Comprueba lo que debe cambiar Y lo que NO debe cambiar. Un arreglo que
-- devolviera la foto SIEMPRE pasaría la mitad de esta prueba y rompería la
-- planilla del mes en curso, que es la que se usa todos los días.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000031300', 'ZZFOT', 'Sede de laboratorio 313', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000313ad', 'FotAdmin', 'Lab',
        '00000000-0000-0000-0000-000000031300', 'admin', 'x',
        '00000000-0000-0000-0000-0000000313ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000031301', 'FotAna',  'Lab', '00000000-0000-0000-0000-000000031300', 'x', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000031302', 'FotBeto', 'Lab', '00000000-0000-0000-0000-000000031300', 'x', '2024-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950, '2026-03-01' from personas where apellidos = 'Lab' and nombres like 'Fot%' and rol is distinct from 'admin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30', array[1,2,3,4,5]
from personas where apellidos = 'Lab' and nombres like 'Fot%' and rol is distinct from 'admin';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000313a1', '2026-03-01', '2026-03-31', 'abierto'),
       ('00000000-0000-0000-0000-0000000313a2', '2026-04-01', '2026-04-30', 'abierto');

insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select p.id, d::date, p.sede_base_id, 6.5, 'cerrada'
from personas p
cross join generate_series('2026-03-01'::timestamp, '2026-04-30'::timestamp, interval '1 day') d
where p.apellidos = 'Lab' and p.nombres like 'Fot%' and p.rol is distinct from 'admin'
  and extract(dow from d) between 1 and 5;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000313ff', true);


-- ── 1 · Un periodo ABIERTO se calcula, y lo dice ────────────────────────────
select is(
  fn_proyeccion_periodo('00000000-0000-0000-0000-0000000313a1') ->> 'fuente',
  'calculo',
  'ABIERTO · el mes en curso se sigue calculando, que es para lo que sirve');


-- ── Se congela marzo y se marca pagado ──────────────────────────────────────
select fn_planilla_congelar('00000000-0000-0000-0000-0000000313a1', 'pago',
                            '00000000-0000-0000-0000-0000000313ad');
update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id = '00000000-0000-0000-0000-0000000313a1';

-- Lo que se le pagó a Ana, según la foto. Es el número que su boleta tiene que
-- decir para siempre.
create temporary table t_pagado on commit drop as
select total from planilla_pagada_detalle
 where periodo_id = '00000000-0000-0000-0000-0000000313a1'
   and persona_id = '00000000-0000-0000-0000-000000031301';


-- ── AHORA CAMBIA EL MUNDO ───────────────────────────────────────────────────
-- Un feriado que se declara DESPUÉS del cierre. El recálculo de hoy lo paga; la
-- foto, que es de antes, no lo conoce. Es el equivalente de laboratorio a las
-- cinco migraciones que el 2026-08-26 reescribieron `fn_planilla_calcular`.
--
-- Se eligió un feriado y no un movimiento de planilla porque el candado del mes
-- pagado (0203/0307) impide agregar movimientos a un periodo cerrado — y hace
-- bien. Los feriados son una tabla global sin ese candado, que es justo la
-- forma en que el mundo cambia por debajo de un mes ya pagado.
insert into feriados (fecha, nombre)
values ('2026-03-18', 'Feriado declarado despues del cierre');


-- ── 2 y 3 · El laboratorio de verdad divergió ───────────────────────────────
-- Va antes que todo lo demás y no es burocracia: si el bono no hubiera entrado,
-- foto y recálculo darían lo mismo y las comprobaciones de abajo pasarían sin
-- haber medido nada. Es la misma trampa que el «Bad plan» de pgTAP.
select ok(
  (select count(*) from t_pagado) = 1,
  'LABORATORIO · la foto guardó la fila de Ana');

select isnt(
  (select round((f->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-03-01','2026-03-31',
                                 '00000000-0000-0000-0000-0000000313a1') -> 'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-000000031301'),
  (select round(total, 2) from t_pagado),
  'LABORATORIO · y el recálculo de hoy YA dice otro número: hay divergencia que medir');


-- ── 4 y 5 · La boleta de un mes pagado dice lo que se pagó ──────────────────
select is(
  fn_proyeccion_periodo('00000000-0000-0000-0000-0000000313a1') ->> 'fuente',
  'foto',
  'PAGADO · la respuesta viene de la foto, y lo dice');

select is(
  (select round((f->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_proyeccion_periodo('00000000-0000-0000-0000-0000000313a1') -> 'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-000000031301'),
  (select round(total, 2) from t_pagado),
  'PAGADO · y el total de Ana es el que cobró, no el que diría el cálculo de hoy');


-- ── 6 · El sobre sigue entero ───────────────────────────────────────────────
-- Las dos pantallas leen `mes_etiqueta`, `anio_etiqueta` y el resto del sobre.
-- Si la 0313 los hubiera perdido al reemplazar `filas`, la boleta no imprimiría.
select is(
  (select count(*)::int from (
     select jsonb_object_keys(fn_proyeccion_periodo('00000000-0000-0000-0000-0000000313a1')) k
     intersect
     select unnest(array['filas','dias','base_horas','feriados','mes_etiqueta',
                         'anio_etiqueta','fecha_ini','fecha_fin',
                         'factores_provision','asignacion_monto'])) x),
  10,
  'PAGADO · el sobre del periodo llega completo: reemplaza `filas`, no lo demás');


-- ── 7 · LA TRAMPA DE LAS VERSIONES ──────────────────────────────────────────
-- Se congela una versión 2 en la que Beto YA NO SALE (se le quitan sus
-- jornadas). Su fila pagada queda viva en la versión 1. Con el `max(version)`
-- del periodo, Beto desaparecería de la boleta; con la última versión DE CADA
-- PERSONA, sigue estando.
-- El caso es el que `fn_liquidacion` describe con esas palabras: «una cesada
-- sin jornadas dentro del rango». Con las jornadas borradas y nada más, Beto
-- seguía saliendo del recálculo con cero horas — comprobado, la prueba lo
-- delató. Hace falta además que ya no esté.
delete from jornadas
 where persona_id = '00000000-0000-0000-0000-000000031302'
   and fecha between '2026-03-01' and '2026-03-31';

update personas set estado = 'inactivo', fecha_cese = '2026-02-28'
 where id = '00000000-0000-0000-0000-000000031302';

select fn_planilla_congelar('00000000-0000-0000-0000-0000000313a1', 'retroactivo',
                            '00000000-0000-0000-0000-0000000313ad');

select ok(
  (select count(*) from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-0000000313a1'
      and persona_id = '00000000-0000-0000-0000-000000031302'
      and version = (select max(version) from planilla_pagada_detalle
                      where periodo_id = '00000000-0000-0000-0000-0000000313a1')) = 0,
  'LABORATORIO · Beto ya no sale en la ultima version de la foto');

select is(
  (select count(*)::int
     from jsonb_array_elements(
            fn_proyeccion_periodo('00000000-0000-0000-0000-0000000313a1') -> 'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-000000031302'),
  1,
  'VERSIONES · pero su boleta sigue saliendo: se toma la ultima version DE CADA PERSONA');


-- ── 8 · Un pagado SIN foto lo dice, no lo disfraza ──────────────────────────
update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id = '00000000-0000-0000-0000-0000000313a2';

select is(
  fn_proyeccion_periodo('00000000-0000-0000-0000-0000000313a2') ->> 'fuente',
  'recalculo_sin_foto',
  'SIN FOTO · un mes pagado de antes del registro congelado avisa en vez de dar un recalculo como si fuera el original');


select * from finish();
rollback;
