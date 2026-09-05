-- ============================================================================
-- 0206_el_descargo_entra_al_legajo_y_la_imputacion_se_puede_cerrar.sql
-- ============================================================================
-- QUÉ PROMETE
--   Dos cosas que el procedimiento del art. 31 necesita y el sistema no tenía:
--
--   1. Que el DESCARGO de la persona se archive en su legajo, junto al memo
--      que lo provocó.
--   2. Que una imputación se pueda CERRAR diciendo qué se resolvió, para que el
--      semáforo deje de pedir una decisión que ya se tomó.
--
-- QUÉ ASUME
--   Nada nuevo. Dos columnas de resolución, un tipo de adjunto más, y una
--   función. Ningún documento existente cambia de estado ni de contenido.
--
-- ── POR QUÉ, Y LOS DOS SE VIERON EL MISMO DÍA ───────────────────────────────
--
-- El 2026-08-10 se firmó y entregó la primera imputación de cargos del sistema.
-- Al preparar el paso siguiente aparecieron los dos huecos, y ninguno es
-- cosmético.
--
-- **EL DESCARGO NO TENÍA DÓNDE VIVIR.** `expediente_adjuntos` solo aceptaba
-- `cargo_firmado` y `acta_negativa`. Pero el descargo es *la* pieza que prueba
-- que se respetó el art. 31 de la LPCL: sin ella, el legajo demuestra que se
-- imputó y no demuestra que se dejó defenderse. Guardarlo en una carpeta suelta
-- es exactamente el problema que este módulo existe para resolver.
--
-- **Y UNA IMPUTACIÓN NO SE PODÍA CERRAR.** Los estados son borrador, firmado,
-- entregado y anulado. No existe «descargos evaluados, se resolvió no
-- sancionar». Como `fn_tardanza_escalon` bloquea mientras haya una imputación
-- vigente, la pantalla habría dicho «decide Gerencia» **durante doce meses**
-- después de que Gerencia ya hubiera decidido.
--
-- Y la salida que quedaba era peor: anular. Anular borra un documento que SÍ se
-- entregó y SÍ produjo efectos — falsear el expediente para acallar un aviso.
-- Un sistema que solo ofrece esa salida acaba enseñando a usarla.
--
-- ── POR QUÉ LA RESOLUCIÓN NO ES UN `estado` NUEVO ───────────────────────────
--
-- Se pensó como `estado = 'resuelto'` y se descartó: `estado` es el ciclo de
-- vida del PAPEL —se redacta, se firma, se entrega— y lo filtran una docena de
-- sitios, incluidas las tres políticas RLS de la 0056. Meter ahí el resultado
-- del procedimiento habría hecho desaparecer el documento de consultas que
-- deben seguir viéndolo: una imputación resuelta sigue estando entregada y
-- sigue siendo un antecedente vigente.
--
-- Son dos ejes distintos y se guardan en dos sitios distintos.
--
-- ── QUÉ CAMBIA EN LA ESCALA ─────────────────────────────────────────────────
--
-- `fn_tardanza_escalon` (0200) bloqueaba con solo ver `nivel = 'imputacion'`.
-- Ahora bloquea únicamente si esa imputación está **sin resolver**. Resuelta,
-- la persona vuelve a tener escalón: `imputacion` con mínimo 1, porque ya está
-- arriba de la escalera y no se baja de ella. El corte se mantiene, así que los
-- hechos ya imputados no se reciclan nunca.
--
-- Si se resolvió CON despido no hay nada que recalcular: la persona queda
-- inactiva y `fn_tardanzas_resumen` ya la excluye por `estado = 'activo'`.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
-- No emite la carta de despido ni la genera nadie. `fn_expediente_resolver` con
-- resultado `despido` solo ANOTA lo que se decidió; la carta se redacta, se
-- firma y se entrega por el mismo camino que todo lo demás. El sistema sigue
-- sin despedir a nadie por su cuenta, que es la regla de este proyecto.
--
-- Tampoco exige el descargo para resolver. Puede no haberlo: el art. 31 da un
-- plazo, no obliga a usarlo, y vencido el plazo se decide igual. Obligarlo
-- dejaría sin cerrar justo los casos en que la persona no contestó.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists public.fn_expediente_resolver(uuid, text, text);
--   alter table expediente_disciplinario
--     drop column if exists resuelto_at, drop column if exists resuelto_por,
--     drop column if exists resuelto_resultado, drop column if exists resuelto_motivo;
--   y devolver fn_tardanza_escalon a su versión de la 0200.
--   Revertir significa volver a pedir una decisión ya tomada durante un año.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final.
-- ============================================================================

-- ── 1 · El descargo entra al legajo ─────────────────────────────────────────
alter table expediente_adjuntos
  drop constraint if exists expediente_adjuntos_tipo_check;

alter table expediente_adjuntos
  add constraint expediente_adjuntos_tipo_check
  check (tipo in ('cargo_firmado', 'acta_negativa', 'descargo'));

comment on column expediente_adjuntos.tipo is
  'cargo_firmado = el acuse de la persona · acta_negativa = se ofreció y no quiso firmar · descargo = su defensa escrita del art. 31 LPCL.';

-- El CHECK de la tabla no basta: `fn_expediente_adjuntar` lleva su propia lista
-- escrita dentro y habría rechazado el descargo antes de llegar al insert. Dos
-- copias de la misma regla, y esta migración las toca a las dos — separarlas
-- sería dejar la trampa puesta para la próxima.
--
-- Va con `create or replace` y la MISMA firma, así que conserva sus permisos.
-- Es la diferencia con la 0189 y la 0198: lo que se lleva los grant es el
-- `drop`, y aquí no hay ninguno.
create or replace function public.fn_expediente_adjuntar(
  p_documento_id uuid,
  p_path text,
  p_tipo text default 'cargo_firmado',
  p_fecha_entrega timestamptz default null,
  p_nota text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare v_id uuid; v_doc expediente_disciplinario%rowtype;
begin
  select * into v_doc from expediente_disciplinario where id = p_documento_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if split_part(p_path, '/', 1) <> p_documento_id::text then
    raise exception 'El archivo no corresponde a este documento.';
  end if;
  if not fn_expediente_puede_adjuntar(p_path) then
    raise exception 'Sin permiso para adjuntar el cargo de este documento.';
  end if;
  if p_tipo not in ('cargo_firmado', 'acta_negativa', 'descargo') then
    raise exception 'Tipo de adjunto inválido: %', p_tipo;
  end if;
  -- Un descargo solo tiene sentido colgando de una imputación entregada: es la
  -- respuesta al plazo del art. 31, y ese plazo no existe en ningún otro nivel.
  if p_tipo = 'descargo' then
    if v_doc.nivel <> 'imputacion' then
      raise exception 'El descargo se archiva contra una imputación de cargos, que es la que abre el plazo del art. 31 (este documento es %).', v_doc.nivel;
    end if;
    if v_doc.estado <> 'entregado' then
      raise exception 'Aún no se puede archivar un descargo: el documento no consta entregado, y el plazo corre desde la recepción.';
    end if;
  end if;

  if p_fecha_entrega is not null then
    if p_fecha_entrega > now() then
      raise exception 'La fecha de entrega no puede ser futura.';
    end if;
    if v_doc.firmado_at is not null and p_fecha_entrega < v_doc.firmado_at then
      raise exception 'La entrega no puede ser anterior a la firma del documento.';
    end if;
  end if;

  insert into expediente_adjuntos (documento_id, storage_path, tipo, nota, subido_por)
  values (p_documento_id, p_path, p_tipo, nullif(trim(p_nota), ''), fn_persona_actual_id())
  returning id into v_id;

  -- Solo si sigue "firmado": si ya se marcó entregado por otra vía, esa fecha
  -- es la buena y no se pisa. fn_expediente_entregar mantiene su blindaje de
  -- Nivel 4 — el medio es 'fisico', que es lo que un papel firmado significa.
  if p_fecha_entrega is not null and v_doc.estado = 'firmado' then
    perform fn_expediente_entregar(p_documento_id, 'fisico', p_fecha_entrega);
  end if;

  return v_id;
end;
$function$;

-- ── 2 · La resolución del procedimiento ─────────────────────────────────────
alter table expediente_disciplinario
  add column if not exists resuelto_at        timestamptz,
  add column if not exists resuelto_por       uuid references personas(id),
  add column if not exists resuelto_resultado text,
  add column if not exists resuelto_motivo    text;

alter table expediente_disciplinario
  drop constraint if exists chk_resuelto_completo;

-- Las cuatro columnas viajan juntas o no viaja ninguna: media resolución es
-- peor que ninguna, porque parece cerrada y no dice qué se decidió.
alter table expediente_disciplinario
  add constraint chk_resuelto_completo check (
    resuelto_at is null
    or (resuelto_por is not null
        and resuelto_resultado in ('archivado', 'despido')
        and length(trim(coalesce(resuelto_motivo, ''))) >= 10));

comment on column expediente_disciplinario.resuelto_resultado is
  'Qué se decidió tras evaluar los descargos: archivado (no se sanciona) o despido. Anotar «despido» NO emite la carta: esa se redacta y se firma por el camino normal.';

-- ── 3 · Quién resuelve, y con qué condiciones ───────────────────────────────
create or replace function public.fn_expediente_resolver(
  p_id uuid, p_resultado text, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $function$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;

  if r.nivel <> 'imputacion' then
    raise exception 'Solo se resuelve una imputación de cargos: es la única que abre un plazo de descargo (este documento es %).', r.nivel;
  end if;
  -- Se exige ENTREGADO y no solo firmado: el plazo del art. 31 corre desde la
  -- recepción. Resolver algo que la persona todavía no recibió sería cerrar un
  -- procedimiento que no llegó a abrirse.
  if r.estado <> 'entregado' then
    raise exception 'Solo se resuelve un documento ya entregado: el plazo de descargo corre desde la recepción (estado actual: %).', r.estado;
  end if;
  if r.resuelto_at is not null then
    raise exception 'Este procedimiento ya se resolvió el % como «%».',
      (r.resuelto_at at time zone 'America/Lima')::date, r.resuelto_resultado;
  end if;
  if p_resultado not in ('archivado', 'despido') then
    raise exception 'Resultado inválido: %. Solo «archivado» o «despido».', p_resultado;
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'El motivo es obligatorio y debe explicar la decisión: es lo que sostiene el expediente si alguien lo revisa.';
  end if;
  if fn_expediente_puede_actuar(r.persona_id, 'imputacion') is not true then
    raise exception 'Sin permiso para resolver una imputación de cargos.';
  end if;

  update expediente_disciplinario
     set resuelto_at        = now(),
         resuelto_por       = fn_persona_actual_id(),
         resuelto_resultado = p_resultado,
         resuelto_motivo    = trim(p_motivo)
   where id = p_id;
end;
$function$;

grant execute on function public.fn_expediente_resolver(uuid, text, text) to authenticated;

-- ── 4 · La escala deja de bloquear lo que ya se decidió ─────────────────────
-- Idéntica a la de la 0200 salvo que `bloqueado` mira además `resuelto_at`.
create or replace function public.fn_tardanza_escalon(p_persona_id uuid)
returns table (nivel_siguiente text, minimo int, corte date, doc_previo uuid, bloqueado boolean)
language sql
stable security definer
set search_path = public
as $function$
  with prev as (
    select e.id, e.nivel, e.periodo_hasta, e.resuelto_at,
           (e.firmado_at >= now() - interval '12 months') as vigente
    from expediente_disciplinario e
    where e.persona_id = p_persona_id
      and e.tipo_causal = 'tardanza'
      and e.estado in ('firmado', 'entregado')
    order by e.firmado_at desc
    limit 1
  )
  select
    case
      when p.vigente and p.nivel = 'imputacion'   then 'imputacion'
      when p.vigente and p.nivel = 'suspension'   then 'imputacion'
      when p.vigente and p.nivel = 'amonestacion' then 'suspension'
      else 'amonestacion'
    end,
    -- Con una imputación SIN resolver no hay número que valga: decide Gerencia.
    -- Resuelta, la persona sigue arriba de la escalera —de ahí no se baja— así
    -- que un solo hecho nuevo vuelve a corresponder imputación.
    case
      when p.vigente and p.nivel = 'imputacion' and p.resuelto_at is null then null::int
      when p.vigente and p.nivel = 'imputacion'                           then 1
      when p.vigente and p.nivel = 'suspension'                           then 1
      when p.vigente and p.nivel = 'amonestacion'                         then 2
      else 3
    end,
    case when p.vigente then p.periodo_hasta end,
    p.id,
    coalesce(p.vigente and p.nivel = 'imputacion' and p.resuelto_at is null, false)
  from (select 1) _
  left join prev p on true;
$function$;

grant execute on function public.fn_tardanza_escalon(uuid) to authenticated;

-- ── 5 · Y el generador respeta lo mismo ─────────────────────────────────────
-- `fn_expediente_generar_tardanza` (0200) ya consulta `bloqueado`, así que
-- hereda el cambio sin tocarla. Se deja dicho para que nadie lo busque.

insert into migraciones_aplicadas (numero, nombre)
values (206, 'el_descargo_entra_al_legajo_y_la_imputacion_se_puede_cerrar')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'expediente_disciplinario'
      and column_name in ('resuelto_at','resuelto_por','resuelto_resultado','resuelto_motivo'))
                                                                   as columnas_de_resolucion,
  (select pg_get_constraintdef(oid) from pg_constraint
    where conrelid = 'expediente_adjuntos'::regclass
      and conname = 'expediente_adjuntos_tipo_check')               as tipos_de_adjunto,
  has_function_privilege('authenticated',
    'public.fn_expediente_resolver(uuid,text,text)'::regprocedure, 'EXECUTE')
                                                                   as puede_resolver,
  has_function_privilege('authenticated',
    'public.fn_tardanza_escalon(uuid)'::regprocedure, 'EXECUTE')    as escalon_ejecutable,
  (select count(*) from expediente_disciplinario
    where nivel = 'imputacion' and estado = 'entregado' and resuelto_at is null)
                                                                   as imputaciones_abiertas;
