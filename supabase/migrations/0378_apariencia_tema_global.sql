-- Apariencia: tema global (claro/oscuro/automático), configurable desde
-- /admin/apariencia, además del tema personal que cada quien ya podía elegir
-- en su propio navegador con el selector de la barra de navegación.
--
-- QUÉ PROMETE: una fila nueva en la tabla `configuracion` que ya existe desde
-- la 0007 (auto_cierre_horas es su otro habitante), clave 'apariencia_tema',
-- valor jsonb con uno de "claro" | "oscuro" | "automatico". No crea tabla ni
-- política nueva — reutiliza tal cual las que `configuracion` ya tiene:
-- `configuracion_select_autenticados` (cualquier autenticado puede leerla) y
-- `configuracion_write_admin_lider` (solo admin/líder puede escribirla, vía
-- fn_es_admin_o_lider()).
--
-- QUÉ ASUME: que el terminal de marcaje de cada sede cuenta como
-- "authenticated" para Postgres, no como anónimo. Es así: apps/web/lib/
-- terminal/sesion.ts documenta que cada Mac mini se "vincula" una vez y
-- mantiene una sesión de Supabase Auth propia y renovable — no usa la llave
-- anónima. Por eso la misma política de lectura que ya sirve al panel le
-- sirve también al kiosco, sin tocar RLS.
--
-- POR QUÉ ASÍ: es el primer lugar donde cambiar de tema aplica a las 4 sedes
-- y al panel a la vez, en vez de tocar el selector personal de cada Mac mini
-- y de cada admin por separado. Sigue siendo posible elegir un tema personal
-- en el navegador (gana sobre este valor — ver apps/web/lib/use-tema.ts).
--
-- CÓMO SE REVIERTE: `delete from configuracion where clave = 'apariencia_tema';`
-- — el sistema vuelve a comportarse exactamente como antes de esta migración
-- (cada quien sigue el tema de su propio navegador/sistema operativo).
--
-- IDEMPOTENTE: `on conflict do nothing` — se puede pegar más de una vez sin
-- pisar un valor que Felipe ya haya cambiado desde /admin/apariencia.

insert into configuracion (clave, valor, descripcion)
values (
  'apariencia_tema',
  '"claro"',
  'Tema (claro/oscuro/automatico) por defecto para el panel y el terminal, cuando quien mira no tiene una preferencia personal guardada en su propio navegador. Se edita desde /admin/apariencia.'
)
on conflict (clave) do nothing;

insert into migraciones_aplicadas (numero, nombre)
values (378, 'apariencia_tema_global')
on conflict (numero) do nothing;
