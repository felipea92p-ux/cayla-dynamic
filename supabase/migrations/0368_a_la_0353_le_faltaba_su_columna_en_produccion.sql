-- ============================================================================
-- 0368 — A la 0353 le faltaba su columna en producción
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que exista en producción la columna
-- `marcajes.confirmo_sin_refrigerio` que la 0353 agregó localmente
-- (`alter table marcajes add column if not exists confirmo_sin_refrigerio
-- boolean`, primera sección de esa migración).
--
-- EL DEFECTO, mismo día que la 0367 y mismo origen: la 0353 trae TRES partes
-- —el `alter table` de la columna, el `drop function` de la firma vieja de 8
-- argumentos, y el `create or replace` de la nueva de 9— y en producción solo
-- llegó a aplicarse la tercera. La 0367 ya arregló la segunda (dejó una sola
-- firma). Con eso, el terminal dejó de chocar por ambigüedad de firmas y
-- empezó a chocar más adentro: la función de 9 argumentos SIEMPRE escribe en
-- `confirmo_sin_refrigerio` —está en el `insert` y en el `update` de
-- reconciliación de salida_final—, y esa columna no existe en la tabla de
-- producción. Confirmado en el panel de Incidencias, con marcas reales de
-- Daniel Ruiz (OTRU) y Felipe Alvarez (CCO) del 2026-09-04 rechazadas con
-- exactamente:
--
--   column "confirmo_sin_refrigerio" of relation "marcajes" does not exist
--
-- Y de paso, el efecto en cadena que se ve en la misma pantalla: como la
-- `salida_almuerzo` nunca llegó a insertarse, la jornada quedó sin ese tramo
-- y el siguiente toque —`retorno_almuerzo`— lo rechazó `fn_siguiente_tipo_
-- esperado` con "la jornada ya está cerrada o requiere elegir un tipo de
-- salida". No es un segundo defecto: es la misma columna faltante golpeando
-- dos marcas seguidas de la misma persona.
--
-- QUÉ ASUME: que el resto del cuerpo de la 0353 (la función en sí, ya con 9
-- argumentos) SÍ quedó bien en producción — la 0367 la dejó como única firma
-- viva y el error de ahora es justo el que se espera de una función correcta
-- escribiendo en una columna que no está. Esta migración no toca la función,
-- solo la tabla.
--
-- POR QUÉ SE ELIGIÓ ASÍ: un `alter table ... add column if not exists` es
-- aditivo e idempotente — no reescribe filas existentes (todas quedan con
-- `null`, que es exactamente lo que la 0353 documenta como "nunca se le
-- preguntó"), y si alguien ya la agregó a mano entre que esto se escribe y se
-- pega, el `if not exists` lo vuelve inofensivo pegarla de todas formas.
--
-- SE REVIERTE: `alter table marcajes drop column if exists
-- confirmo_sin_refrigerio` — se pierde el dato de esa columna (aceptable, ya
-- que es evidencia de apoyo y no la fuente de verdad del marcaje, tal como
-- documenta la 0353).
--
-- No aplica el chequeo de md5 de partida: esto no reescribe el cuerpo de
-- ninguna función, es un `alter table` sobre una columna que hoy no existe en
-- producción. Antes de pegar, comprobar con la consulta que trae el propio
-- encabezado de abajo que sigue faltando.
-- ============================================================================

-- Para comprobar antes de pegar (solo lee):
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'marcajes'
--      and column_name = 'confirmo_sin_refrigerio';
-- Si devuelve una fila, alguien ya la agregó — pegar esto de todas formas no
-- hace nada (if not exists).

alter table marcajes add column if not exists confirmo_sin_refrigerio boolean;

comment on column marcajes.confirmo_sin_refrigerio is
  'Solo en marcajes de salida_final cuando ese día no había ninguna salida_almuerzo marcada. true = la persona confirmó, al marcar, que trabajó corrido sin parar a almorzar. false = dijo que sí almorzó pero olvidó marcar la salida a refrigerio. null = no se le preguntó (ese día sí marcó su salida a refrigerio, o el marcaje es de otro tipo).';

insert into migraciones_aplicadas (numero, nombre)
values (368, 'a_la_0353_le_faltaba_su_columna_en_produccion')
on conflict (numero) do nothing;
