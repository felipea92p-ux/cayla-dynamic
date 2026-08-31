-- ============================================================================
-- 0333 · El generador de contratos hace convenios de prácticas
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `/admin/contratos` deje de ser estructuralmente invisible para una
--   practicante (0322). Tres cambios, todos de ADMISIÓN — ninguno reescribe
--   una regla que ya existía:
--
--     1. `contratos_generados.tipo` acepta un cuarto valor:
--        'convenio_practicas'.
--     2. `fn_contrato_registrar` lo valida y lo deja disparar el mismo
--        recálculo de `fecha_fin_contrato` que ya dispara un contrato firmado.
--     3. `fn_contratos_tablero` deja de exigir `en_planilla`: una practicante
--        con convenio por vencer también aparece en el tablero de "qué
--        necesita atención".
--
--   No se crea ninguna tabla ni columna nueva. La institución educativa y el
--   plan de capacitación específico (Ley 28518, art. 15) se piden como texto
--   en pantalla y entran ya redactados al `documento_html` — exactamente como
--   ya funciona la causa objetiva y las funciones del cargo de un contrato de
--   planilla desde la 0223. Ver `apps/web/lib/admin/contrato-texto.ts` y
--   `apps/web/app/(admin)/admin/contratos/page.tsx` para la parte de pantalla.
--
-- QUÉ ASUME
--
--   Que la 0312 es la versión vigente de `fn_contrato_registrar` (comprobar
--   con `./scripts/donde-vive.sh fn_contrato_registrar` antes de pegar — es
--   una función con varias versiones repartidas, y copiar de otra revierte en
--   silencio lo que se arregló entre medias) y que la 0287 es la vigente de
--   `fn_contratos_tablero`.
--
-- POR QUÉ 'convenio_practicas' Y NO REUTILIZAR 'nuevo'
--
--   Un convenio de modalidad formativa no es un contrato de trabajo (0322,
--   Ley 28518 art. 47) — el documento que se genera para él no comparte una
--   sola cláusula de fondo con "CONTRATO DE TRABAJO SUJETO A MODALIDAD
--   TEMPORAL... Art. 57" (D.Leg. 728). Etiquetarlo 'nuevo' declararía en la
--   base un vínculo laboral que nunca existió — el mismo error de lenguaje
--   que la 0143 evitó al no reciclar 'despido' para un contrato vencido, y que
--   la 0325 evitó al no reciclar 'fin_contrato' para el cese de un convenio.
--
-- POR QUÉ SE ENSANCHA fn_contratos_tablero EN VEZ DE UN TABLERO NUEVO
--
--   El criterio "qué necesita atención" (sin firmar, por vencer, trámite
--   pendiente, desnaturalizado) es el mismo para un convenio que para un
--   contrato — lo único que cambiaba era el filtro de entrada. Un tablero
--   aparte habría duplicado esa lógica para volver a decir lo mismo.
--
-- CÓMO SE REVIERTE
--   alter table contratos_generados drop constraint contratos_generados_tipo_check;
--   alter table contratos_generados add constraint contratos_generados_tipo_check
--     check (tipo in ('nuevo', 'renovacion', 'adendum'));
--   Y correr de nuevo el cuerpo de `fn_contrato_registrar` y
--   `fn_contratos_tablero` tal como quedaron en la 0312 y la 0287.
-- ============================================================================

-- ── 1 · El CHECK de tipo ─────────────────────────────────────────────────────
-- Idempotente: se reconstruye completo, así pegarla dos veces no rompe nada.
-- Solo AGREGA un valor — ninguna fila existente deja de ser válida.
alter table contratos_generados drop constraint if exists contratos_generados_tipo_check;

alter table contratos_generados add constraint contratos_generados_tipo_check
  check (tipo in (
    'nuevo',
    'renovacion',
    'adendum',
    'convenio_practicas'  -- ⇦ 0333: convenio de modalidad formativa, Ley 28518
  ));

comment on column contratos_generados.tipo is
  'Tipo de documento generado. nuevo/renovacion/adendum son contratos de trabajo '
  '(D.Leg. 728). convenio_practicas (0333) NO es un contrato de trabajo: es un '
  'convenio de modalidad formativa (Ley 28518) para tipo_vinculo=''practicante''. '
  'No se funden: un convenio no tiene causa objetiva, periodo de prueba ni '
  'régimen disciplinario laboral.';

-- ── 2 · fn_contrato_registrar admite el cuarto tipo ─────────────────────────
-- Cuerpo vigente: 0312_un_contrato_anulado_no_deja_su_fecha_puesta.sql. Dos
-- líneas cambian, marcadas CAMBIO 0333; el resto es idéntico.
create or replace function fn_contrato_registrar(
  p_persona_id            uuid    default null,
  p_tipo                  text    default null,
  p_cargo                 text    default null,
  p_sede_id               uuid    default null,
  p_remuneracion_mensual  numeric default null,
  p_fecha_inicio          date    default null,
  p_fecha_fin             date    default null,
  p_horas_semanales       numeric default null,
  p_documento_html        text    default null,
  p_id                    uuid    default null,   -- no nulo = adjuntar firma a un borrador existente
  p_storage_path          text    default null,
  p_fecha_firma           date    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  v_yo      uuid := fn_persona_actual_id();
  v_nota    text := '';
  r         contratos_generados%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional genera contratos.';
  end if;

  -- ── Adjuntar la firma a un borrador ya generado ──
  if p_id is not null then
    select * into r from contratos_generados where id = p_id;
    if not found then raise exception 'Ese contrato no existe.'; end if;
    if r.anulado_at is not null then raise exception 'Ese contrato está anulado.'; end if;
    if r.storage_path is not null then raise exception 'Ese contrato ya tiene un escaneo registrado.'; end if;
    if p_storage_path is null then raise exception 'Falta el escaneo firmado.'; end if;
    if p_fecha_firma is null then raise exception 'Falta la fecha en que se firmó.'; end if;
    if p_fecha_firma > fn_hoy_lima() then raise exception 'La fecha de firma no puede ser futura.'; end if;

    -- El archivo tiene que ser EL DE ESTE CONTRATO. `p_storage_path` es texto
    -- libre, y `fn_contrato_puede_ver` resuelve el permiso por el uuid que va
    -- en el nombre del archivo: apuntar la fila de una persona al escaneo de
    -- otra dejaría a la primera sin poder abrir su propio contrato y a la
    -- segunda viéndolo. Se cierra acá, que es donde se elige el path.
    if p_storage_path !~ ('^contratos/' || p_id::text || '\.') then
      raise exception 'La ruta del escaneo no corresponde a este contrato.';
    end if;

    update contratos_generados
       set storage_path = p_storage_path, fecha_firma = p_fecha_firma, registrado_por = v_yo
     where id = p_id;

    -- La fecha de vencimiento se mueve recién con la firma puesta: un borrador
    -- descartado nunca debe haber tocado este dato.
    --
    -- PERO NO SE DEJA CAER EL REGISTRO SI LA PERSONA YA NO ESTÁ ACTIVA. Ese era
    -- el defecto: `fn_set_fin_contrato` corta con «ya está inactiva», y quien
    -- cesó entre imprimir y firmar se quedaba SIN PODER ARCHIVAR su contrato
    -- firmado — justo el papel que hay que conservar. Para alguien cesado la
    -- fecha de vencimiento no significa nada; el documento sí.
    -- La fecha se recalcula, no se escribe a ciegas (0312). Antes se le ponía
    -- la fecha DE ESTE contrato sin más. Firmar un borrador viejo después de
    -- haber firmado el nuevo movía el vencimiento HACIA ATRÁS, y ese es el
    -- dato que `fn_contratos_desnaturalizados` usa para avisar del riesgo del
    -- artículo 77: retrocederlo fabrica una desnaturalización que no ocurrió,
    -- o esconde una que sí.
    --
    -- Se recalcula DESPUÉS del update de arriba, así que el contrato que se
    -- acaba de firmar ya cuenta como firmado y compite en igualdad. Si es el
    -- más reciente firmado, la fecha es la suya; si no, gana el otro y la suya
    -- no toca nada. Nunca borra: acaba de aparecer un contrato firmado.
    -- ⇩⇩⇩ CAMBIO 0333 ⇩⇩⇩ un convenio firmado también mueve fecha_fin_contrato —
    -- es el mismo dato (0333 lo reusa como fecha de fin de convenio, ver el
    -- encabezado de esta migración), y el recálculo ya sabe quedarse con el
    -- más reciente firmado sea cual sea su tipo.
    if r.tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas') then
      v_nota := fn_contrato_refrescar_vencimiento(
                  r.persona_id, 'Contrato firmado — generador de contratos');
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'contrato_firmado', null,
       r.tipo || ' · firmado el ' || p_fecha_firma::text, v_yo,
       'Escaneo del contrato firmado registrado' || v_nota);

    return p_id;
  end if;

  -- ── Generar el borrador ──
  -- ⇩⇩⇩ CAMBIO 0333 ⇩⇩⇩ admite 'convenio_practicas'.
  if p_tipo not in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas') then
    raise exception 'Tipo de contrato inválido: «%».', p_tipo;
  end if;
  if p_persona_id is null or not exists (
    select 1 from personas where id = p_persona_id and estado = 'activo'
  ) then
    raise exception 'Esa persona no existe o no está activa.';
  end if;
  if p_cargo is null or btrim(p_cargo) = '' then
    raise exception 'Falta el cargo.';
  end if;
  if p_sede_id is null then
    raise exception 'Falta la sede.';
  end if;
  if p_remuneracion_mensual is null or p_remuneracion_mensual < 0 then
    raise exception 'Falta la remuneración, o es inválida.';
  end if;
  if p_fecha_inicio is null or p_fecha_fin is null or p_fecha_fin <= p_fecha_inicio then
    raise exception 'Las fechas del contrato son inválidas.';
  end if;
  if p_documento_html is null or btrim(p_documento_html) = '' then
    raise exception 'Falta el texto del contrato.';
  end if;

  insert into contratos_generados (
    persona_id, tipo, cargo, sede_id, remuneracion_mensual,
    fecha_inicio, fecha_fin, horas_semanales, documento_html, generado_por
  ) values (
    p_persona_id, p_tipo, trim(p_cargo), p_sede_id, p_remuneracion_mensual,
    p_fecha_inicio, p_fecha_fin, p_horas_semanales, p_documento_html, v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'contrato_generado', null,
     p_tipo || ' · generado el ' || fn_hoy_lima()::text, v_yo,
     'Alta de borrador de contrato');

  return v_id;
end;
$$;

grant execute on function fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, uuid, text, date
) to authenticated;
revoke execute on function fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, uuid, text, date
) from public, anon;

-- ── 3 · fn_contratos_tablero deja de exigir en_planilla ─────────────────────
-- Cuerpo vigente: 0287_el_contrato_firmado_se_registra_y_sus_plazos_se_miden.sql.
-- Devuelve TABLE, así que no admite `create or replace` con el mismo shape de
-- columnas si cambiara — pero acá el shape NO cambia, solo el WHERE, así que
-- basta con `create or replace` (mismo patrón que ya usa esta función desde
-- que existe: no toca columnas).
create or replace function fn_contratos_tablero()
returns table (
  persona_id            uuid,
  persona               text,
  sede                  text,
  fecha_fin_contrato    date,
  dias_restantes        int,
  contrato_id           uuid,
  tipo                  text,
  fecha_firma           date,
  copia_entregada_at    date,
  comunicado_mtpe_at    date,
  copia_vence           date,
  mtpe_vence            date,
  dias_marcados_despues int,
  estado                text
)
language sql
stable
security definer
set search_path = public
as $$
  with ultimo as (
    -- El contrato que manda por persona: el más reciente sin anular.
    select distinct on (c.persona_id)
           c.persona_id, c.id, c.tipo, c.fecha_firma, c.fecha_inicio,
           c.copia_entregada_at, c.comunicado_mtpe_at
      from contratos_generados c
     where c.anulado_at is null
     order by c.persona_id, c.generado_at desc
  ),
  -- Marcó días DESPUÉS de su fecha de fin: el riesgo del art. 77 que la 0231
  -- ya sabe calcular y que hasta hoy no miraba ninguna pantalla.
  desn as (select * from fn_contratos_desnaturalizados())
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '—'),
    p.fecha_fin_contrato,
    (p.fecha_fin_contrato - fn_hoy_lima())::int,
    u.id, u.tipo, u.fecha_firma,
    u.copia_entregada_at, u.comunicado_mtpe_at,
    -- Los dos plazos de la cláusula décima octava. El de la copia corre desde
    -- el inicio de la prestación y es en días HÁBILES; se aproxima con días
    -- calendario + 2, que es lo que puede hacer una consulta sin calendario de
    -- feriados delante — y para avisar con tiempo basta.
    (u.fecha_inicio + 5)::date,
    (u.fecha_firma + 15)::date,
    coalesce(d.dias_marcados_despues, 0),
    case
      when d.persona_id is not null                     then 'desnaturalizado'
      when u.id is null                                 then 'sin_contrato'
      when u.fecha_firma is null                        then 'sin_firmar'
      when p.fecha_fin_contrato is null                 then 'sin_vencimiento'
      when p.fecha_fin_contrato < fn_hoy_lima()         then 'vencido'
      when p.fecha_fin_contrato - fn_hoy_lima() <= 60   then 'por_vencer'
      when u.copia_entregada_at is null
        or u.comunicado_mtpe_at is null                 then 'tramite_pendiente'
      else 'ok'
    end
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join ultimo u on u.persona_id = p.id
  left join desn d on d.persona_id = p.id
  where p.estado = 'activo'
    -- ⇩⇩⇩ CAMBIO 0333 ⇩⇩⇩ una practicante también entra al tablero. El guarda es
    -- `tipo_vinculo = 'practicante'` y NO `not en_planilla`: un locador RxH no
    -- tiene contrato ni convenio que generar y sigue fuera, igual que antes.
    and (p.en_planilla or p.tipo_vinculo = 'practicante')
    and fn_es_admin_o_lider() is true
  -- Lo que urge primero: quien ya está en riesgo, y después por vencimiento.
  order by
    case
      when d.persona_id is not null then 0
      when u.id is null then 1
      when u.fecha_firma is null then 2
      else 3
    end,
    p.fecha_fin_contrato nulls last,
    p.apellidos;
$$;

grant execute on function fn_contratos_tablero() to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (333, 'el_generador_de_contratos_hace_convenios_de_practicas')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0333 · contratos_generados.tipo acepta convenio_practicas. fn_contrato_registrar y fn_contratos_tablero actualizados.';
end $$;
