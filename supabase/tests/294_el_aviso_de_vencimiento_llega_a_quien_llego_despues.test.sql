-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 294_el_aviso_de_vencimiento_llega_a_quien_llego_despues.test.sql
--   defiende la 0371
-- ============================================================================
-- QUÉ DEFIENDE ESTE ARCHIVO
--   Que el aviso de un contrato o unas vacaciones por vencer le llegue a cada
--   persona de DO, incluida la que entró DESPUÉS de que ese vencimiento se
--   avisara por primera vez — y que a nadie le llegue dos veces.
--
--   Si esto se pone rojo, volvió el defecto que la 0371 arregló: la nueva
--   líder de DO no recibe el aviso de un contrato que vence en doce días, y
--   no se entera nunca. No llega tarde: no llega. Nadie ve un error; alguien
--   simplemente no recibe un correo que jamás supo que debía llegarle.
--
-- LAS DOS MITADES, que es lo que hace que esto sea una prueba y no un deseo:
--   · que la puerta se ABRA para quien llegó después (aserciones 6 a 9), y
--   · que siga CERRADA para quien ya recibió el aviso (4, 5 y 10).
--   Un anti-duplicado que deja pasar todo no es un anti-duplicado; uno que no
--   deja pasar nada es este mismo defecto con otro nombre.
--
-- POR QUÉ SE PRUEBAN LOS DOS TIPOS Y NO UNO
--   `fn_generar_alertas_vencimiento` lleva DOS `insert` con el mismo `not
--   exists` copiado. El defecto estaba en los dos. Probar solo contratos
--   dejaría la mitad de vacaciones libre de volver a romperse — y ahí duele
--   más: un récord vencido sigue siendo el mismo hecho durante todo un año,
--   con una indemnización de una remuneración entera corriendo (art. 23 del
--   D. Leg. 713).
--
-- POR QUÉ TAMBIÉN SE PRUEBA EL CANAL, Y POR QUÉ EN LOS DOS TIPOS
--   Porque `alertas.canal` admite 'push' desde la 0001, así que una fila de
--   push es una fila legítima — y sin el canal en la comparación, un push ya
--   anotado se toma por el correo y lo cancela. Hoy nada escribe push, o sea
--   que esas dos líneas de la 0371 no las defiende ningún otro caso: quien las
--   borre en un refactor no vería nada ponerse rojo.
--
--   La versión anterior de este archivo sembraba UN solo push, de contrato. Con
--   eso, quitarle a la 0371 el `and a.canal = 'email'` de la rama de VACACIONES
--   dejaba las once aserciones en verde: se aplicaba a la mitad el mismo
--   razonamiento que el encabezado usaba para justificar probar los dos tipos.
--   Por eso ahora Nora tiene un push de CADA tipo.
--
-- POR QUÉ CADA CUENTA LLEVA SUS DOS FILTROS
--   `alertas` es una tabla compartida y esta función mira a TODAS las personas
--   activas, así que su VALOR DE RETORNO es global: comparar contra él hacía
--   que una sola persona ajena con contrato por vencer —una fila de seed, un
--   fixture de otra prueba— pusiera cinco aserciones rojas con la MISMA
--   redacción con la que salen cuando el defecto vuelve. Un fallo que no se
--   distingue del que uno busca no es una prueba: es una trampa.
--
--   Así que aquí no se cuenta ni un retorno ni un total: se cuentan las filas
--   cuyo DESTINATARIO y cuyo SUJETO son los dos de este archivo. Correr la
--   función se hace en un `do … perform`, tirando el retorno a propósito.
-- ============================================================================
begin;
select plan(11);

-- ── Fixtures ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000028700', 'ZZ287', 'Sede de laboratorio', true);

-- Dos personas de DO con correo. `devenga_vacaciones = false` a propósito:
-- si devengaran, ellas mismas generarían avisos de vacaciones y las cuentas
-- de cada tipo se mezclarían con el sujeto de la prueba.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, email,
                      fecha_ingreso, estado, devenga_vacaciones)
values
  ('00000000-0000-0000-0000-000000028701', 'Dora', 'DeOrg287',
   '00000000-0000-0000-0000-000000028700', 'admin', 'x', 'dora287@cayla.test',
   fn_hoy_lima() - 20, 'activo', false),
  ('00000000-0000-0000-0000-000000028702', 'Lidia', 'DeOrg287',
   '00000000-0000-0000-0000-000000028700', 'lider_do', 'x', 'lidia287@cayla.test',
   fn_hoy_lima() - 20, 'activo', false);

-- Una persona con contrato que vence dentro de la ventana de 30 días. Su
-- ingreso reciente hace que NO genere además aviso de vacaciones.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, fecha_fin_contrato, estado)
values ('00000000-0000-0000-0000-000000028710', 'Carla', 'Contrato287',
        '00000000-0000-0000-0000-000000028700', 'x',
        fn_hoy_lima() - 20, fn_hoy_lima() + 12, 'activo');

-- Una persona con dos récords de vacaciones sin gozar (uno ya vencido) y sin
-- contrato a plazo: solo genera aviso de vacaciones.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado)
values ('00000000-0000-0000-0000-000000028720', 'Vera', 'Vacaciones287',
        '00000000-0000-0000-0000-000000028700', 'x',
        (fn_hoy_lima() - interval '30 months')::date, 'activo');

-- Las filas de este archivo, y solo ellas: destinatario mío y sujeto mío.
-- Todas las cuentas de abajo se leen de acá.
-- Vista TEMPORAL: nace y muere dentro del `begin … rollback` de este archivo,
-- así que no puede chocar con otra prueba ni dejar rastro en la base que
-- comparten los worktrees.
create temporary view mis_alertas as
select a.* from alertas a
 where a.persona_id::text like '00000000-0000-0000-0000-0000000287%'
   and a.payload ->> 'persona_id' in ('00000000-0000-0000-0000-000000028710',
                                      '00000000-0000-0000-0000-000000028720');

-- ── 1a corrida: el hecho se reparte a cada destinatario que existe hoy ──────
select lives_ok(
  $$ do $corre$ begin perform fn_generar_alertas_vencimiento(); end $corre$ $$,
  'PRIMERA CORRIDA · la cola se llena sin pelea');

select is(
  (select count(*)::int from mis_alertas
    where tipo = 'contrato_por_vencer'
      and payload ->> 'persona_id' = '00000000-0000-0000-0000-000000028710'),
  2,
  'CONTRATO · un solo contrato por vencer genera UNA fila por cada persona de DO, no una sola en total');

select is(
  (select count(*)::int from mis_alertas
    where tipo = 'vacaciones_por_vencer'
      and payload ->> 'persona_id' = '00000000-0000-0000-0000-000000028720'),
  2,
  'VACACIONES · y la otra rama de la función hace exactamente lo mismo');

-- ── Correr otra vez no puede duplicar nada ──────────────────────────────────
do $segunda$ begin perform fn_generar_alertas_vencimiento(); end $segunda$;

select is(
  (select count(*)::int from mis_alertas),
  4,
  'NO SE DUPLICA · una segunda corrida el mismo día no vuelve a avisar de lo mismo');

-- Despachar el correo tampoco reabre la puerta: una alerta ya enviada sigue
-- siendo prueba de que ese hecho ya se avisó a esa persona.
update alertas set estado = 'enviado', enviado_at = now()
 where id in (select id from mis_alertas);
do $tercera$ begin perform fn_generar_alertas_vencimiento(); end $tercera$;

select is(
  (select count(*)::int from mis_alertas),
  4,
  'DESPACHAR NO REABRE · marcar los correos como enviados no regenera la cola');

-- ── EL HALLAZGO: llega alguien nuevo a DO, después del primer aviso ─────────
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, email,
                      fecha_ingreso, estado, devenga_vacaciones)
values ('00000000-0000-0000-0000-000000028703', 'Tere', 'DeOrg287',
        '00000000-0000-0000-0000-000000028700', 'lider_do', 'x', 'tere287@cayla.test',
        fn_hoy_lima() - 20, 'activo', false);

do $cuarta$ begin perform fn_generar_alertas_vencimiento(); end $cuarta$;

select is(
  (select count(*)::int from mis_alertas
    where persona_id = '00000000-0000-0000-0000-000000028703'),
  2,
  'HALLAZGO · quien entra a DO después SÍ recibe los avisos ya dados: uno por tipo, y ninguno más');

select is(
  (select count(*)::int from mis_alertas),
  6,
  'HALLAZGO · y las dos filas nuevas son SUYAS — no se le repitió el aviso a nadie más');

-- ── EL CANAL TAMBIÉN ES PARTE DE LA IDENTIDAD ──────────────────────────────
-- Llega una cuarta persona a DO y, antes de que corra el cron, ya existen
-- filas de ESOS MISMOS hechos para ELLA, pero por push (el canal que la 0001
-- dejó admitido y que todavía nadie usa). Los correos tienen que salir igual:
-- un push anotado no es un correo mandado. Van los DOS tipos porque la 0371
-- lleva el `and a.canal = 'email'` en sus dos ramas, y una sola de ellas
-- dejaría la otra sin nada que la defienda.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, email,
                      fecha_ingreso, estado, devenga_vacaciones)
values ('00000000-0000-0000-0000-000000028704', 'Nora', 'DeOrg287',
        '00000000-0000-0000-0000-000000028700', 'lider_do', 'x', 'nora287@cayla.test',
        fn_hoy_lima() - 20, 'activo', false);

insert into alertas (persona_id, tipo, canal, payload)
select '00000000-0000-0000-0000-000000028704', 'contrato_por_vencer', 'push',
       jsonb_build_object('evento', p.id::text || '|' || p.fecha_fin_contrato::text,
                          'persona_id', p.id)
  from personas p where p.id = '00000000-0000-0000-0000-000000028710';

-- El mismo push, para la rama de vacaciones. El `evento` se compone igual que
-- lo compone la función: id de la persona, barra, la fecha de vencimiento que
-- devuelve el cálculo — si no coincidiera, esta fila no chocaría con nada y la
-- aserción de abajo pasaría sin medir el canal.
insert into alertas (persona_id, tipo, canal, payload)
select '00000000-0000-0000-0000-000000028704', 'vacaciones_por_vencer', 'push',
       jsonb_build_object('evento', p.id::text || '|' ||
                            (fn_vacaciones_saldo_interno(p.id, fn_hoy_lima()) ->> 'vence_el'),
                          'persona_id', p.id)
  from personas p where p.id = '00000000-0000-0000-0000-000000028720';

do $quinta$ begin perform fn_generar_alertas_vencimiento(); end $quinta$;

select is(
  (select count(*)::int from mis_alertas
    where persona_id = '00000000-0000-0000-0000-000000028704'
      and canal = 'email' and tipo = 'contrato_por_vencer'),
  1,
  'CANAL · el push de contrato ya anotado no cancela el correo de contrato de Nora');

select is(
  (select count(*)::int from mis_alertas
    where persona_id = '00000000-0000-0000-0000-000000028704'
      and canal = 'email' and tipo = 'vacaciones_por_vencer'),
  1,
  'CANAL · y el push de vacaciones tampoco cancela el suyo — la otra rama, que quedaba sin defensa');

-- ── La identidad completa: (tipo, hecho, destinatario, canal) es única ──────
select is(
  (select coalesce(max(veces), 0)::int
     from (select tipo, payload ->> 'evento' as ev, persona_id, canal, count(*) as veces
             from mis_alertas group by 1, 2, 3, 4) t),
  1,
  'IDENTIDAD · ningún (tipo, hecho, destinatario, canal) aparece dos veces');

select is(
  (select count(*)::int from mis_alertas where canal = 'email'),
  8,
  'CUENTA FINAL · dos hechos × cuatro personas de DO = ocho correos, ni uno más ni uno menos');

select * from finish();
rollback;
