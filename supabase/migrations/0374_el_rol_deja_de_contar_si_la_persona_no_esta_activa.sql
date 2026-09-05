-- ============================================================================
-- 0374 — el rol deja de contar cuando la persona ya no está activa
-- ============================================================================
-- QUÉ PROMETE
--
--   Que dar de baja a alguien (fn_cesar_persona, 0176) corte TODO el poder que
--   su rol le daba sobre datos ajenos, en el mismo instante en que `estado`
--   pasa a 'inactivo' — sin esperar a que alguien le resetee la clave a mano.
--
-- QUÉ HALLAZGO CIERRA ESTO
--
--   fn_cesar_persona nunca tocó Supabase Auth ni la columna `rol`: solo marca
--   `estado='inactivo'`. Y fn_rol_actual() —el ÚNICO punto por el que pasan
--   fn_es_admin_o_lider() y toda política que compara contra 'supervisor_sede'—
--   nunca miraba `estado`. Resultado real: una persona cesada con rol admin,
--   lider_do o supervisor_sede conservaba, indefinidamente, acceso completo a
--   sueldos, datos personales e identidad de todo el equipo — hasta que
--   alguien entrara a Cuentas y le reseteara la clave a mano, paso que hoy
--   nada recuerda pedir.
--
-- CÓMO SE CONSIGUE SIN TOCAR AUTH NI LAS OTRAS FUNCIONES
--
--   fn_rol_actual() es el único lugar de todo el esquema donde «cuál es mi
--   rol» se traduce en poder: fn_es_admin_o_lider() y cada política que
--   compara contra 'supervisor_sede' ya pasan por acá. Agregarle
--   `and estado = 'activo'` corta el poder en la raíz sin reescribir ninguna
--   política, y sin depender de una llamada a la Admin API que pueda fallar en
--   silencio — la alternativa que se descartó (revocar Auth vía Edge
--   Function/webhook) agrega una pieza que puede no dispararse justo cuando
--   más importa, y no resuelve nada que esto no resuelva ya en la práctica:
--   sin rol, no hay nada que ver ni que hacer.
--
-- QUÉ ASUME
--
--   Que fn_persona_actual_id() —que NO cambia acá— sigue devolviendo su propio
--   id aunque esté inactiva. Es a propósito: su historial (jornadas, boletas,
--   correcciones) sigue siendo suyo, y las políticas «_propia» filtran por
--   fn_persona_actual_id(), no por fn_rol_actual(). Lo que se corta es el
--   poder sobre datos AJENOS, no su propio registro.
--
--   Que el panel de admin puede verse «roto» —bandejas vacías, botones sin
--   efecto— si una persona cesada con rol admin/lider_do/supervisor_sede
--   entra a /admin, porque el frontend sigue leyendo su `rol` directo de
--   `personas` (`personas_select_propia` no filtra por estado) sin saber que
--   ya no tiene poder. Eso queda para un cambio de UI aparte, no bloqueante:
--   el riesgo real —poder sobre datos ajenos— ya queda cerrado con esto.
--
-- SE ROMPE SI
--
--   Alguna política de RLS compara `personas.rol` directo en vez de pasar por
--   fn_rol_actual(). No se encontró ninguna al escribir esto (grep sobre las
--   373 migraciones existentes), pero si aparece una en el futuro, esta
--   migración no la protege — hay que enrutarla por acá también.
--
-- CÓMO SE REVIERTE
--
--   Volver al cuerpo de la 0005: `select rol from personas where
--   auth_user_id = auth.uid();`, sin el filtro de estado. No hay datos que
--   perder — es una función, no una tabla.
--
-- ⚠️ ANTES DE PEGAR: fn_rol_actual() no se toca desde la 0005 (373 migraciones
-- atrás), así que el riesgo de copiar una versión intermedia es bajo — pero
-- pide igual el md5 de producción antes de pegar, como manda la casa. Esta
-- sesión no tiene acceso al SQL Editor y no pudo pedirlo.
-- ============================================================================

create or replace function fn_rol_actual()
returns rol_usuario
language sql stable security definer set search_path = public
as $$
  select rol from personas where auth_user_id = auth.uid() and estado = 'activo';
$$;

insert into migraciones_aplicadas (numero, nombre)
values (374, '0374_el_rol_deja_de_contar_si_la_persona_no_esta_activa')
on conflict (numero) do nothing;
