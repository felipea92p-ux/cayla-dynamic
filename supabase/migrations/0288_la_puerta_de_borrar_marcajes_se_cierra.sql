-- ============================================================================
-- 0288 — La puerta de borrar marcajes se cierra
-- ============================================================================
--
-- QUÉ PROMETE
--   Que ninguna sesión del navegador pueda BORRAR un marcaje. Anularlo sí —esa
--   es la puerta buena y sigue abierta—; borrarlo no.
--
-- QUÉ ASUME
--   · Que `fn_eliminar_marcaje` es la de la **0188**, confirmada con
--     `./scripts/donde-vive.sh fn_eliminar_marcaje`. No se toca su cuerpo: esta
--     migración solo cambia QUIÉN puede ejecutarla, así que su md5 no cambia y
--     no hay md5 de partida que declarar.
--   · Que `fn_anular_marcaje` y `fn_reactivar_marcaje` siguen siendo las que usa
--     la pantalla de Correcciones (`apps/web/app/(admin)/admin/correcciones/page.tsx:310,314,336`).
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- La 0081 dejó escrita la regla de la casa: **las marcas se anulan, no se
-- borran.** Un marcaje es el hecho observable del que cuelga todo lo demás —la
-- jornada es un resumen derivado, y la planilla se calcula de ahí—, así que
-- destruir uno destruye la única prueba de lo que pasó ese día.
--
-- Y sin embargo `fn_eliminar_marcaje` hace exactamente eso: un `delete from
-- marcajes`. No es una función descuidada —exige motivo, escribe en
-- `correcciones_auditoria` antes de borrar, se niega si el día cae en un
-- periodo pagado, y resella el día después—, pero al final la fila desaparece.
-- Lo que queda es la nota de que existió, no el marcaje.
--
-- El agujero no es que exista: es **quién puede llamarla**. La 0009 le dio
-- `grant execute … to authenticated` (0009:271) y nadie se lo quitó nunca. O
-- sea que cualquier sesión del panel con permiso de corrector puede borrar un
-- marcaje por REST, sin pasar por ninguna pantalla.
--
-- ── MEDIDO ANTES DE TOCAR NADA ──────────────────────────────────────────────
--
--   · Llamadas desde `apps/` y `packages/`: **CERO**. La función no la usa
--     ninguna pantalla; solo aparece en los tipos generados.
--   · Lo que sí usa el panel para lo mismo es `fn_anular_marcaje`, que marca la
--     fila como anulada y la conserva, con `fn_reactivar_marcaje` para
--     deshacerlo. Ese camino no se toca.
--   · Permisos actuales de `fn_eliminar_marcaje`: postgres, service_role **y
--     authenticated**.
--
-- Así que cerrar la puerta no le quita nada a nadie: es permiso vivo sobre una
-- función muerta, que es la peor combinación posible.
--
-- ── POR QUÉ REVOCAR Y NO BORRAR LA FUNCIÓN ──────────────────────────────────
--
-- Porque sigue habiendo un caso legítimo, aunque raro: un marcaje que nunca
-- debió existir —una prueba, un duplicado de una integración— y que anular no
-- resuelve del todo. Ese caso se atiende a mano desde el SQL Editor, donde la
-- sesión es `postgres`, y ahí la función sigue disponible.
--
-- Lo que se cierra es el camino automático. La diferencia entre «alguien puede
-- hacerlo desde el navegador sin querer» y «alguien tiene que entrar a
-- producción a propósito» es toda la diferencia.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   `grant execute on function fn_eliminar_marcaje(uuid, text) to authenticated;`
--   No toca datos ni cuerpos de función: revertir no pierde nada.
--
-- ============================================================================

revoke all on function fn_eliminar_marcaje(uuid, text) from public;
revoke all on function fn_eliminar_marcaje(uuid, text) from authenticated;

comment on function fn_eliminar_marcaje(uuid, text) is
  'BORRA un marcaje de verdad, y por eso desde la 0288 NO la puede ejecutar '
  '`authenticated`: solo postgres/service_role, o sea a mano desde el SQL Editor. '
  'La puerta buena es fn_anular_marcaje, que conserva la fila — la regla de la '
  '0081 es que las marcas se anulan, no se borran. Ninguna pantalla la llama.';


insert into migraciones_aplicadas (numero, nombre)
values (288, 'la_puerta_de_borrar_marcajes_se_cierra')
on conflict (numero) do nothing;
