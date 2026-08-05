-- ============================================================================
-- 0148 — Un memo en borrador no sale firmado
-- ============================================================================
--
-- QUÉ PROMETE
--   La firma escaneada de un memo solo se entrega cuando ese memo ya está
--   firmado en el sistema (`firmado_at`). Un borrador impreso sale con la raya
--   en blanco.
--
-- QUÉ ASUME
--   · `firmado_at` se llena al firmar y no antes. Es la marca que la 0071 dejó
--     para eso, y desde la 0131 volver a borrador la limpia.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--   `fn_firma_de_memo` devolvía la rúbrica de `firmante_id` sin mirar si el
--   documento estaba firmado. Y `firmante_id` se elige al redactar, no al
--   firmar. Resultado: un borrador impreso para revisarlo salía con una firma
--   escaneada de verdad — indistinguible de un memo firmado, porque el aviso
--   de «borrador» de la pantalla lleva `no-print` y no sale en el papel.
--
--   El daño no es de pantalla. Un memo es la pieza que arma el expediente
--   disciplinario (D.S. 003-97-TR art. 25), y su valor depende de que la fecha
--   y la firma digan la verdad. Un papel con firma que el sistema registra como
--   no firmado es lo contrario de un expediente: es la prueba de que los
--   papeles de esta empresa no son confiables.
--
--   VA EN LA FUNCIÓN Y NO EN LA PANTALLA. La pantalla del memo es una de las
--   que imprime, pero la firma se pide por RPC y cualquier otra pantalla podría
--   pedirla mañana. Poner la regla donde se sirve el dato la deja cumplida para
--   todas — el mismo criterio de la 0138 con el recálculo de jornadas.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar la definición anterior, que es esta misma sin la línea
--   `and d.firmado_at is not null`. No hay cambio de datos ni de esquema.
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
    and d.nivel in ('verbal','amonestacion','suspension')
    -- LA LÍNEA NUEVA. Sin ella un borrador sale con rúbrica: `firmante_id` se
    -- elige al redactar y `firmado_at` recién al firmar, así que entre esos dos
    -- momentos el documento tenía firma sin estar firmado.
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
values (148, 'un_borrador_no_sale_firmado')
on conflict (numero) do nothing;
