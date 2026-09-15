-- ============================================================================
-- 0453 — La Bandeja vuelve a reconocer los ítems de educación
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: `fn_bandeja_marcar_visto` vuelve a aceptar los dos tipos de ítem
-- que agregó la 0450 —`entrega_educacion` y `aviso_fin_educacion`—, así que
-- las constancias de estudios y los avisos de fin de estudios de la Bandeja
-- dejan de quedarse marcados como «nuevo» para siempre.
--
-- QUÉ PASÓ. El 2026-09-15 la 0436 y la 0450 se pegaron en ese orden, que es el
-- correcto: la 0450 amplía el check de `bandeja_vistos` y reescribe esta
-- función sobre el cuerpo de la 0436. A las 16:00 de ese mismo día la 0436 se
-- volvió a pegar, siguiendo una auditoría de migraciones pendientes que la daba
-- por segura — y que había caducado: cuando se hizo, la 0450 todavía no estaba
-- en `main`. El veredicto no se re-verificó antes de darlo.
--
-- `dame-el-sql.sh 0436` lo avisó en rojo («esto REVIERTE funciones que una
-- migración posterior ya arregló: fn_bandeja_marcar_visto, la redefine después
-- la 0450»), y el aviso era exacto. Casi todo lo que hace la 0436 es
-- idempotente —`create table if not exists`, `drop policy if exists` más la
-- misma política, los grants—, así que el re-pegado no tocó nada más. Pero su
-- `create or replace function` devolvió esta función a la versión de la 0436,
-- que no conoce los dos tipos nuevos y los rechaza con excepción.
--
-- Medido contra producción justo después, solo lecturas: el check de
-- `bandeja_vistos` SÍ es el de la 0450 (siete tipos: sobrevivió porque la 0436
-- no toca una tabla que ya existe), pero la función NO — md5
-- 2acf861c9961c9d81dce9bcb7958d51f, 593 caracteres, exactamente el cuerpo de la
-- 0436. Un estado contradictorio: la tabla admite lo que la función se niega a
-- escribir.
--
-- EL SÍNTOMA NO SE VE, Y POR ESO IMPORTA. `/admin/bandeja` llama a esta función
-- con `void supabase.rpc(...)`, así que la excepción se traga sin avisar a
-- nadie. Nada se rompe en pantalla: los ítems de educación simplemente nunca
-- se marcan como vistos y en cada visita vuelven a salir como nuevos. Medido:
-- cero filas de `bandeja_vistos` con esos dos tipos.
--
-- UN SEGUNDO RASTRO QUE SE PERDIÓ. La línea de registro de la 0436 hace
-- `on conflict (numero) do update set aplicada_at = now()`, así que el
-- re-pegado pisó la fecha de su aplicación original. En `migraciones_aplicadas`
-- la 0436 figura hoy como aplicada DESPUÉS de la 0450, cosa imposible —la 0450
-- altera una tabla que crea la 0436—. La fecha que se ve es la del re-pegado.
--
-- QUÉ ASUME:
--   · Que la 0450 es la versión vigente de esta función. Comprobado con
--     `git grep` sobre `main` en el momento de escribir esto —no al empezar—:
--     solo la definen la 0436 y la 0450, no hay migraciones por encima de la
--     0452, y ni la 0451 ni la 0452 la mencionan.
--   · MD5 DE PARTIDA, pedido a PRODUCCIÓN el 2026-09-15 al escribir:
--     2acf861c9961c9d81dce9bcb7958d51f · 593 — el cuerpo de la 0436.
--   · MD5 DE LLEGADA: 5a80418516d4a6d60dad579ef8542cf8 · 725 — el cuerpo de la
--     0450 copiado byte a byte, marcador «CAMBIO 0450» incluido, para que el md5
--     de producción vuelva a coincidir con el del repositorio.
--
-- POR QUÉ ASÍ Y NO RE-PEGANDO LA 0450. La 0450 no es re-pegable: trece `insert`
-- sin `on conflict`, además de tablas, triggers, políticas y un bucket de
-- almacenamiento. Repetirla entera para arreglar una sola función arriesga
-- fallar a media ejecución o duplicar datos. Aquí va SOLO la función.
--
-- LOS PERMISOS. `create or replace` conserva los que la función ya tiene, y
-- producción ya tiene `execute` para `authenticated` (verificado). El grant y el
-- revoke de la 0436 se repiten igual porque son idempotentes y dejan esta
-- migración correcta también en una base nueva.
--
-- CÓMO SE REVIERTE: no hay una reversión que tenga sentido — volver al cuerpo
-- de la 0436 es volver al defecto. Si hiciera falta, se pega la sentencia
-- `create or replace function fn_bandeja_marcar_visto` de la 0436.
-- ============================================================================

create or replace function fn_bandeja_marcar_visto(p_tipo_item text, p_item_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;
  -- ⇩ CAMBIO 0450 ⇩ entrega_educacion y aviso_fin_educacion.
  if p_tipo_item not in ('revision', 'revision_movilidad', 'revision_contrato',
                          'solicitud_vacacion', 'solicitud_perfil',
                          'entrega_educacion', 'aviso_fin_educacion') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$$;

grant execute on function fn_bandeja_marcar_visto(text, uuid) to authenticated;
revoke execute on function fn_bandeja_marcar_visto(text, uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (453, 'la_bandeja_vuelve_a_reconocer_educacion')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- Comprobación: las tres tienen que salir true.
select
  (select prosrc like '%CAMBIO 0450%' from pg_proc
    where proname = 'fn_bandeja_marcar_visto') as es_la_version_de_la_0450,
  (select count(*) = 1 from pg_proc
    where proname = 'fn_bandeja_marcar_visto') as una_sola_version,
  (select md5(prosrc) = '5a80418516d4a6d60dad579ef8542cf8' from pg_proc
    where proname = 'fn_bandeja_marcar_visto') as md5_de_llegada_coincide;
