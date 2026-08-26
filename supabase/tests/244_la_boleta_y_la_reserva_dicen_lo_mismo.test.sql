-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 244_la_boleta_y_la_reserva_dicen_lo_mismo.test.sql
-- ============================================================================
-- EL FRENO QUE NO EXISTÍA.
--
-- `fn_planilla_calcular` (la boleta) y `fn_provisiones` (la reserva de la
-- pantalla de Provisiones) responden la misma pregunta —cuánto devengó esta
-- persona este mes— por caminos distintos. Son dos mitades del mismo par, y hay
-- que tocarlas juntas.
--
-- Cinco veces no se tocaron juntas, y las cinco costaron plata:
--
--     0276   la reserva no conocía el feriado
--     0286   un día fichado se pagaba también como ausencia
--     0293   el feriado dentro de un descanso médico no se pagaba
--     0302   la reserva contaba días de calendario y la boleta laborables
--     0308   la 0306 exigió la firma de DO solo en la boleta
--
-- Las cinco tienen la misma forma: alguien arregla una mitad con buen criterio,
-- sus pruebas pasan, el CI queda verde, y el par termina diciendo dos cosas
-- distintas sobre la misma persona el mismo mes. **Ninguna herramienta de la
-- casa lo veía.** Se encontraban a mano, de casualidad, y siempre después.
--
-- Esta prueba es esa herramienta. Y se ganó el sueldo el día que se escribió:
-- la primera vez que se corrió encontró la 0310 —el feriado dentro de un
-- descanso médico no lo contaba NADIE, S/5,24 por feriado, contra la persona—
-- que nadie estaba buscando.
--
-- ── POR QUÉ ES UNA MATRIZ Y NO UN «TIENEN QUE DAR SIEMPRE LO MISMO» ─────────
--
-- Porque hay divergencias legítimas, y un guardián que chilla por ellas se
-- desactiva a la semana. Cada escenario declara su veredicto esperado, y la
-- prueba comprueba LAS DOS DIRECCIONES:
--
--   · que no se separe lo que debe cuadrar   → el defecto que se repite
--   · que no cuadre lo que debe divergir     → para que nadie «arregle» una
--     divergencia correcta sin darse cuenta
--
-- ── POR QUÉ NO COMPARA IMPORTES ────────────────────────────────────────────
--
-- No hay ni un número esperado en las comprobaciones: solo la relación entre
-- los dos lados. Así la prueba sobrevive a cualquier migración que cambie
-- legítimamente cuánto se paga, y solo se pone roja cuando el par se separa.
-- Una prueba con importes escritos a mano habría que reescribirla cada vez, y
-- una prueba que se reescribe seguido deja de leerse.
--
-- ── DOS DECISIONES DE LABORATORIO QUE COSTARON UN RATO ──────────────────────
--
-- 1 · EL PERIODO ES EL MES CALENDARIO, no el 29→28 real de CAYLA. La diferencia
--     de divisor entre las dos funciones es una divergencia declarada y abierta
--     desde la 0276. Con el periodo real, la prueba mediría las dos cosas a la
--     vez y no distinguiría cuál se rompió.
--
-- 2 · EL SUELDO EMPIEZA EL 01/03/2026 para todos. `grati_s1` acumula el
--     SEMESTRE, y quien tiene sueldo fijo devenga por calendario aunque no
--     marque: con el sueldo vigente desde 2024 la reserva traía enero y febrero
--     y la boleta de marzo no, y salía una diferencia de S/324,98 que parecía un
--     defecto grave y era del laboratorio. Sin sueldo vigente nadie devenga,
--     así que esto encierra la medición dentro de marzo.
-- ============================================================================
begin;
select plan(3);

insert into feriados (fecha, nombre) values
  ('2026-03-11', 'Feriado de laboratorio, en miercoles'),
  ('2026-03-08', 'Feriado de laboratorio, en domingo');

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000024400', 'ZZMTZ', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000244ad', 'ZAdmin', 'Mtz',
        '00000000-0000-0000-0000-000000024400', 'admin', 'x',
        '00000000-0000-0000-0000-0000000244ff', '2024-01-01');
set session_replication_role = origin;

-- Doce personas idénticas salvo por lo que les pasó en marzo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo) values
  ('00000000-0000-0000-0000-000000024401', 'E01Entero',      'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024402', 'E02Vacas',       'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024403', 'E03ParteFirm',   'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024404', 'E04ParteSin',    'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024405', 'E05MaterFirm',   'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024406', 'E06MaterSin',    'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024407', 'E07Trujillo',    'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024408', 'E08Solape',      'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024409', 'E09LicGoce',     'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024410', 'E10SueldoFijo',  'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', true),
  ('00000000-0000-0000-0000-000000024411', 'E11ParteFeriado','Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false),
  ('00000000-0000-0000-0000-000000024412', 'E12TruParteDom', 'Mtz', '00000000-0000-0000-0000-000000024400', 'x', '2024-01-01', 'planilla', false);

-- Ver la decisión 2 de la cabecera: sin sueldo vigente nadie devenga, y eso
-- encierra toda la medición dentro de marzo.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950, '2026-03-01'
from personas where apellidos = 'Mtz' and nombres like 'E%';

-- Trujillo trabaja domingo y descansa miércoles. Es la sede que impide que un
-- arreglo «restarle los domingos» pase por bueno.
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '15:30',
       case when nombres in ('E07Trujillo','E12TruParteDom') then array[0,1,2,4,5,6]
            else array[1,2,3,4,5] end
from personas where apellidos = 'Mtz' and nombres like 'E%';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000024499', '2026-03-01', '2026-03-31', 'abierto');

insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select p.id, d::date, p.sede_base_id, 6.5, 'cerrada'
from personas p
join horarios_asignados h on h.persona_id = p.id
cross join generate_series('2026-03-01'::timestamp, '2026-03-31'::timestamp, interval '1 day') d
where p.apellidos = 'Mtz' and p.nombres like 'E%'
  and extract(dow from d)::int = any(h.dias_laborables)
  and not (p.nombres in ('E02Vacas','E03ParteFirm','E04ParteSin','E05MaterFirm',
                         'E06MaterSin','E07Trujillo','E09LicGoce')
           and d::date between '2026-03-02' and '2026-03-20')
  -- E08 esta de vacaciones 02-20 pero SI ficho tres dias adentro: es el solape
  -- que la 0286 arreglo, y que se paga una sola vez.
  and not (p.nombres = 'E08Solape' and d::date between '2026-03-02' and '2026-03-20'
           and d::date not in ('2026-03-03','2026-03-04','2026-03-05'))
  -- E11: descanso medico 09-13, justo encima del feriado del miercoles 11.
  and not (p.nombres = 'E11ParteFeriado' and d::date between '2026-03-09' and '2026-03-13')
  -- E12: de Trujillo, descanso medico 06-10 encima del feriado del DOMINGO 08,
  -- que para ellos si es dia laborable.
  and not (p.nombres = 'E12TruParteDom' and d::date between '2026-03-06' and '2026-03-10');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000244ff', true);

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000024403', 'descanso_medico',  '2026-03-02','2026-03-20','prueba','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024404', 'descanso_medico',  '2026-03-02','2026-03-20','prueba','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024405', 'maternidad',       '2026-03-02','2026-03-20','prueba','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024406', 'maternidad',       '2026-03-02','2026-03-20','prueba','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024409', 'licencia_con_goce','2026-03-02','2026-03-20','prueba','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024411', 'descanso_medico',  '2026-03-09','2026-03-13','prueba','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024412', 'descanso_medico',  '2026-03-06','2026-03-10','prueba','00000000-0000-0000-0000-0000000244ad');

-- Las vacaciones entran por SU tabla; un trigger crea la ausencia, y la deja
-- sin `aprobada_at`. Ese es el estado real en el que llegan y no se toca.
insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por) values
  ('00000000-0000-0000-0000-000000024402', '2026-03-02','2026-03-20','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024407', '2026-03-02','2026-03-20','00000000-0000-0000-0000-0000000244ad'),
  ('00000000-0000-0000-0000-000000024408', '2026-03-02','2026-03-20','00000000-0000-0000-0000-0000000244ad');

-- Firma DO todas menos las dos que llevan «Sin» en el nombre.
update ausencias set aprobada_at = now(), aprobada_por = '00000000-0000-0000-0000-0000000244ad'
where persona_id in ('00000000-0000-0000-0000-000000024403','00000000-0000-0000-0000-000000024405',
                     '00000000-0000-0000-0000-000000024409','00000000-0000-0000-0000-000000024411',
                     '00000000-0000-0000-0000-000000024412');

-- ── LA MATRIZ ───────────────────────────────────────────────────────────────
create temporary table t_matriz on commit drop as
with esperado(escenario, veredicto, porque) as (values
  ('E01Entero',       'cuadran',  'mes entero trabajado, sin nada raro'),
  ('E02Vacas',        'cuadran',  'vacaciones, que entran sin firma y no la necesitan'),
  ('E03ParteFirm',    'cuadran',  'descanso medico firmado, con un feriado dentro (0310)'),
  ('E04ParteSin',     'cuadran',  'descanso medico SIN firmar: ninguno de los dos paga (0308)'),
  ('E05MaterFirm',    'divergen', 'CORRECTO: el subsidio lo paga EsSalud, no CAYLA, y la boleta marca esos dias dias_maternidad_sin_monto; la reserva devenga por el art. 3.2 c) del D.S. 005-2002-TR. Miden cosas distintas.'),
  ('E06MaterSin',     'cuadran',  'maternidad SIN firmar: ninguno de los dos paga (0308)'),
  ('E07Trujillo',     'cuadran',  'seis dias laborables CON domingo, de vacaciones'),
  ('E08Solape',       'cuadran',  'ficho tres dias dentro de sus vacaciones: se paga una sola vez (0286)'),
  ('E09LicGoce',      'divergen', 'DEFECTO CONOCIDO, sin lote: licencia_con_goce esta en el catalogo como que paga y fn_planilla_calcular no la paga por ningun camino. Cuando se arregle, esta fila pasa a cuadran.'),
  ('E10SueldoFijo',   'cuadran',  'sueldo fijo: devenga por calendario en las dos'),
  ('E11ParteFeriado', 'cuadran',  'descanso medico justo encima de un feriado en miercoles (0310)'),
  ('E12TruParteDom',  'cuadran',  'ídem en Trujillo, con el feriado en DOMINGO, que alli si es laborable (0310)')
), bol as (
  select replace(e->>'nombre', ' Mtz', '') as escenario,
         (e->>'provision_gratificacion')::numeric as grati
  from jsonb_array_elements(
         fn_planilla_calcular('2026-03-01','2026-03-31',
                              '00000000-0000-0000-0000-000000024499') -> 'filas') e
  where e->>'nombre' like 'E%Mtz'
), res as (
  select replace(e->>'nombre', ' Mtz', '') as escenario,
         (e->>'grati_s1')::numeric as grati
  from jsonb_array_elements(fn_provisiones('2026-03-31') -> 'personas') e
  where e->>'nombre' like 'E%Mtz'
)
select x.escenario, x.veredicto as esperado, x.porque,
       b.grati as boleta, r.grati as reserva,
       round(r.grati - b.grati, 2) as dif
from esperado x
join bol b on b.escenario = x.escenario
join res r on r.escenario = x.escenario;

-- ── 1 · La matriz corrió entera ─────────────────────────────────────────────
-- Va primera y no es burocracia: las dos comprobaciones de abajo son `is_empty`,
-- y un `is_empty` sobre una tabla vacía pasa. Sin esta linea, un laboratorio que
-- no se construyera dejaria la prueba en verde sin haber comprobado nada — que
-- es la misma trampa que el «Bad plan» de pgTAP, y se lee igual de discreta.
select is(
  (select count(*)::int from t_matriz), 12,
  'los doce escenarios de la matriz se construyeron y se midieron'
);

-- ── 2 · Lo que debe cuadrar, cuadra ─────────────────────────────────────────
-- `is_empty` y no un conteo: cuando falla, pgTAP imprime QUÉ escenario se
-- separó y por cuánto. Un «esperaba 0, hubo 3» obligaría a ir a buscarlos.
select is_empty(
  $$ select escenario, boleta, reserva, dif, porque
       from t_matriz where esperado = 'cuadran' and dif <> 0 order by 1 $$,
  'ningun escenario que debe cuadrar se separo: la boleta y la reserva dicen lo mismo'
);

-- ── 3 · Y lo que debe divergir, sigue divergiendo ───────────────────────────
-- La otra direccion. Si alguien «arregla» la maternidad para que coincida, le
-- estaria quitando a la persona un devengo que la ley le da; y si arregla la
-- licencia con goce —que hace falta—, esta fila se lo va a decir para que
-- actualice la matriz a sabiendas en vez de por accidente.
select is_empty(
  $$ select escenario, boleta, reserva, porque
       from t_matriz where esperado = 'divergen' and dif = 0 order by 1 $$,
  'ninguna divergencia declarada desaparecio en silencio'
);

select * from finish();
rollback;
