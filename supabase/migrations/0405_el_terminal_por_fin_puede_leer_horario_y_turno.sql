-- ============================================================================
-- El terminal por fin puede leer horarios_asignados y turnos: sus dos
-- policies "_select_terminal" nunca funcionaron.
--
-- QUÉ PROMETE: una sesión de terminal (auth_user_id de una fila activa en
-- `terminales`) puede leer las filas de `horarios_asignados` y `turnos` de
-- las personas que marcan en su sede — lo mismo que ya puede hacer con
-- `marcajes` desde el día uno.
--
-- QUÉ ASUME: que "puede ver el horario de quien puede ver el marcaje" es la
-- regla correcta — son la misma pregunta ("¿esta persona marca en mi sede?"),
-- y separarlas sería la misma regla escrita dos veces con dos suertes
-- distintas.
--
-- POR QUÉ SE ESCRIBE ASÍ: `horarios_select_terminal` y `turnos_select_terminal`
-- (0003, 0013) filtran con
--     persona_id in (select id from personas where sede_base_id = fn_sede_actual_terminal())
-- —un subselect que consulta `personas` DIRECTO. `personas` tiene RLS propio
-- (0285/0291, tras la auditoría que retiró la policy ancha del terminal
-- sobre esa tabla) y tab NO le da al rol de terminal ningún SELECT directo,
-- solo `terminal_roster` —una vista angosta que puede saltarse ese RLS
-- porque una vista corre con los privilegios de quien la creó, no de quien
-- la consulta—. Un subselect dentro de OTRA policy no es una vista: corre
-- con los privilegios de quien hace la consulta, así que ese subselect
-- siempre devolvía cero filas para el terminal. Las dos policies existían,
-- pasaban cualquier lectura superficial de "¿existe la policy?", y nunca
-- dejaron pasar una fila — exactamente el síntoma que parece "no hay
-- policy" y es en realidad "hay una policy muerta".
--
-- Se descubrió construyendo la sugerencia inteligente de refrigerio del
-- terminal (necesita leer el horario asignado de cada persona para saber su
-- hora de salida esperada): la consulta volvía `[]` sin ningún error, ni en
-- Postgres ni en PostgREST — un 200 limpio con cero filas, indistinguible de
-- "esta persona no tiene horario". Se cazó recién al simular la sesión del
-- terminal a mano contra Postgres local.
--
-- LA CORRECCIÓN: usar `fn_persona_en_roster_terminal(persona_id)` en vez del
-- subselect — la misma función `security definer` que ya prueba
-- `marcajes_select_terminal` (0082) y que por eso SÍ funciona: al ser
-- `security definer`, corre con los privilegios de quien la creó y su lectura
-- interna de `personas` no choca con el RLS de `personas`.
--
-- CÓMO SE REVIERTE: recrear las dos policies con su `using` original
-- (el subselect de arriba) — vuelven a quedar rotas, pero el archivo queda
-- documentado si hace falta deshacerlo por algún motivo no previsto acá.
-- ============================================================================

drop policy if exists horarios_select_terminal on horarios_asignados;
create policy horarios_select_terminal on horarios_asignados
  for select to authenticated
  using (fn_persona_en_roster_terminal(persona_id));

drop policy if exists turnos_select_terminal on turnos;
create policy turnos_select_terminal on turnos
  for select to authenticated
  using (fn_persona_en_roster_terminal(persona_id));
