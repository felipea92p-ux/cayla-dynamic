-- ============================================================================
-- 0205_la_carta_de_despido_lleva_su_fecha_de_cese.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que una carta de despido pueda decir CUÁNDO termina el vínculo. Hoy no
--   puede: no hay dónde guardar esa fecha.
--
-- QUÉ ASUME
--   Nada. Una columna nueva, anulable, sin valor por defecto. Ningún documento
--   existente cambia.
--
-- ── POR QUÉ ─────────────────────────────────────────────────────────────────
--
-- El **artículo 32 de la LPCL** exige que la carta de despido indique de modo
-- preciso **la causa y la fecha del cese**. La plantilla del panel tenía la
-- causa y no tenía la fecha, y no por descuido de redacción: no existía la
-- columna donde ponerla.
--
-- No se resuelve escribiéndola a mano sobre el papel impreso. El documento se
-- imprime desde la base cada vez que se abre, así que un dato que solo esté en
-- la copia de papel no está en el sistema: no se puede reimprimir igual, ni
-- auditar, ni cruzar con `personas.fecha_cese` el día que se registre la baja.
--
-- ── POR QUÉ NO SE REUSA `personas.fecha_cese` ───────────────────────────────
--
-- Porque son dos hechos distintos y pueden no coincidir. `personas.fecha_cese`
-- es la baja EFECTIVA, la que mueve la liquidación (0176). Esta es la fecha que
-- **la carta declaró**, y queda congelada en el documento aunque la baja se
-- registre después, se corrija o no llegue a registrarse nunca. Guardar una
-- sola sería perder justo la comparación que importa si alguien discute el
-- despido: qué dijo el papel contra qué hizo la empresa.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
-- No obliga a que esté puesta. Un CHECK que exigiera `fecha_cese` en todo
-- documento de nivel `despido` rompería cualquier borrador a medio hacer, y el
-- borrador es exactamente donde se decide esa fecha. El panel avisa en rojo
-- dentro del propio memo —«FALTA LA FECHA DE CESE»— para que sea imposible
-- firmarlo sin verlo. Avisar donde se está mirando vale más que un candado que
-- salta cuando ya no se puede hacer nada.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   alter table expediente_disciplinario drop column if exists fecha_cese;
--   Revertir significa volver a emitir cartas de despido sin la fecha que el
--   art. 32 exige.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final: la columna existe y ninguna carta de despido firmada
--   se quedó sin fecha.
-- ============================================================================

alter table expediente_disciplinario
  add column if not exists fecha_cese date;

comment on column expediente_disciplinario.fecha_cese is
  'Fecha de cese DECLARADA en la carta de despido (art. 32 LPCL). Distinta de personas.fecha_cese, que es la baja efectiva: se conservan las dos para poder comparar lo que dijo el papel con lo que hizo la empresa.';

-- ── Y quien la fija: el editor del borrador ─────────────────────────────────
--
-- ⚠️ ESTE BLOQUE ES LA LECCIÓN DE AYER APLICADA A SÍ MISMA. Añadir un parámetro
-- NO reemplaza una función: crea otra, con otra firma y sin los permisos de la
-- anterior. Eso es exactamente lo que hizo la 0198 con `fn_set_datos_personales`
-- y lo que dejó rota la ficha personal hasta la 0204. Así que aquí:
--
--   1. se suelta la firma vieja, para no dejar dos sobrecargas conviviendo;
--   2. se crea la nueva;
--   3. **se vuelve a otorgar el execute**, que el drop se lleva por delante.
--
-- Los seis parámetros anteriores conservan nombre y orden, así que la llamada
-- que ya está desplegada —que manda solo `p_id` y los tres de suspensión—
-- sigue resolviendo a esta función sin tocar el panel.
drop function if exists public.fn_expediente_editar_borrador(uuid, int, date, date, text, jsonb);

create or replace function public.fn_expediente_editar_borrador(
  p_id uuid,
  p_suspension_dias int default null, p_suspension_desde date default null, p_suspension_hasta date default null,
  p_observacion text default null, p_hechos jsonb default null,
  p_fecha_cese date default null)
returns void language plpgsql security definer set search_path = public as $function$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then raise exception 'Solo se puede editar un borrador (estado actual: %).', r.estado; end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then raise exception 'Sin permiso.'; end if;

  -- La fecha de cese solo tiene sentido en una carta de despido. Dejarla poner
  -- en una amonestación sería guardar un dato que después alguien leería como
  -- si la empresa hubiera decidido un cese que nunca decidió.
  if p_fecha_cese is not null and r.nivel <> 'despido' then
    raise exception 'La fecha de cese solo se fija en una carta de despido (este documento es %).', r.nivel;
  end if;

  update expediente_disciplinario set
    suspension_dias  = coalesce(p_suspension_dias, suspension_dias),
    suspension_desde = coalesce(p_suspension_desde, suspension_desde),
    suspension_hasta = coalesce(p_suspension_hasta, suspension_hasta),
    observacion      = coalesce(p_observacion, observacion),
    hechos           = coalesce(p_hechos, hechos),
    fecha_cese       = coalesce(p_fecha_cese, fecha_cese)
  where id = p_id;
end;
$function$;

grant execute on function public.fn_expediente_editar_borrador(uuid, int, date, date, text, jsonb, date) to authenticated;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (205, 'la_carta_de_despido_lleva_su_fecha_de_cese')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'expediente_disciplinario'
      and column_name = 'fecha_cese')                          as columna_creada,
  (select count(*) from expediente_disciplinario
    where nivel = 'despido' and estado in ('firmado', 'entregado')
      and fecha_cese is null)                                  as cartas_firmadas_sin_fecha,
  (select count(*) from expediente_disciplinario
    where nivel = 'despido')                                   as cartas_de_despido_en_total,
  -- La comprobación que la 0204 enseñó a hacer: que el drop de arriba no haya
  -- dejado la función sin permiso. Tiene que decir 1 sobrecarga y `true`.
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_editar_borrador')
                                                               as sobrecargas_del_editor,
  has_function_privilege('authenticated',
    'public.fn_expediente_editar_borrador(uuid,int,date,date,text,jsonb,date)'::regprocedure,
    'EXECUTE')                                                 as authenticated_puede_editar;
