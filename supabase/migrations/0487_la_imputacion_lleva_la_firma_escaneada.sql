-- ============================================================================
-- 0487 — La imputación de cargos lleva la firma escaneada de quien la firma
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_firma_de_memo` entrega la rúbrica escaneada de quien suscribe un
--   documento disciplinario YA FIRMADO, y ahora también cuando ese documento es
--   una IMPUTACIÓN DE CARGOS. Lo que no cambia:
--     · un borrador sigue saliendo con la raya en blanco (0148);
--     · la CARTA DE DESPIDO sigue sin firma escaneada: esa la firma Gerencia a
--       mano, en persona;
--     · quién puede pedirla es exactamente lo de antes (admin/DO, líder de
--       equipo de la sede de la persona, o la propia persona).
--
-- QUÉ ASUME
--   · `firmado_at` se llena al firmar y no antes (0148).
--   · Una imputación se entrega EN FÍSICO o por vía notarial, nunca por correo
--     (docs/disciplina-tardanzas-faltas/06-manual-v2-suplemento.md). La firma
--     escaneada sale en el papel que se entrega; no reemplaza ese cargo de
--     recepción, y la pantalla del memo sigue dejando en blanco el «Recibí
--     conforme» de la persona.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--   La 0065 (2026-07-22) dejó imputación y despido fuera con esta razón:
--   «línea a mano — firma digital certificada o manuscrita». Esa decisión la
--   tomó una sesión de trabajo, no el laboralista, y quien firma estas cartas
--   pidió estamparla. El efecto práctico: quien firma la imputación ya no tiene
--   que imprimir, firmar a mano y volver a escanear; el papel sale firmado.
--
--   LO QUE ESTA MIGRACIÓN NO RESUELVE, y hay que decirlo: una imagen escaneada
--   de una firma NO es una firma digital certificada (Ley 27269). Su valor
--   probatorio en una imputación que fundamente un despido es menor que el de
--   la firma manuscrita, y la Consulta 8 de
--   docs/disciplina-tardanzas-faltas/10-consulta-al-laboralista.md —quién
--   estampa la firma— sigue sin respuesta. Esta migración mueve la línea entre
--   «se estampa» y «se firma a mano»; no la legitima. Si el laboralista dice que
--   una imputación va a mano, se revierte con una línea (ver abajo).
--
--   VA EN LA FUNCIÓN Y NO EN LA PANTALLA (mismo criterio de la 0148): la
--   pantalla del memo dejó de repetir la regla —quitó su `!esNivel4`— y pregunta
--   a la función. Una sola fuente de verdad para «a qué documentos se les
--   estampa firma».
--
--   Se conserva `despido` fuera. No por un argumento distinto —el de fondo es el
--   mismo— sino porque el pedido fue por la imputación, y ampliar a la carta que
--   termina la relación laboral es una decisión que no se toma de pasada.
--
-- MD5 DE PARTIDA
--   Producción (`fn_firma_de_memo`), pedido al SQL Editor el 2026-09-27:
--     md5 de partida: f1c0ab05e73ef79f39332c08164d3799  (736 caracteres)
--   Coincide byte por byte con la 0148 y con el Postgres local: producción tiene
--   la versión vigente del repositorio, con sus comentarios.
--
-- CÓMO SE REVIERTE
--   Volver a la lista de la 0148: `d.nivel in ('verbal','amonestacion',
--   'suspension')`. No hay cambio de datos ni de esquema.
-- ============================================================================

create or replace function public.fn_firma_de_memo(p_doc_id uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select f.imagen
  from expediente_disciplinario d
  join firmas_escaneadas f on f.persona_id = d.firmante_id
  where d.id = p_doc_id
    -- LA LISTA. `imputacion` entra en la 0487; `despido` se queda fuera a
    -- propósito (la carta de despido la firma Gerencia a mano).
    and d.nivel in ('verbal','amonestacion','suspension','imputacion')
    -- Sin firma en el sistema no hay rúbrica: `firmante_id` se elige al
    -- redactar y `firmado_at` recién al firmar (0148).
    and d.firmado_at is not null
    and (coalesce(fn_es_admin_o_lider(), false)
         or (fn_rol_actual() = 'supervisor_sede'
             and d.persona_id in (select id from personas
                                  where sede_base_id = fn_sede_actual_persona()))
         or d.persona_id = fn_persona_actual_id());
$function$;

-- La 0076 dejó dicho que nada nace abierto: una función reemplazada sin su
-- grant se manifiesta como «permission denied for function».
grant execute on function fn_firma_de_memo(uuid) to authenticated;
revoke execute on function fn_firma_de_memo(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (487, 'la_imputacion_lleva_la_firma_escaneada')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
