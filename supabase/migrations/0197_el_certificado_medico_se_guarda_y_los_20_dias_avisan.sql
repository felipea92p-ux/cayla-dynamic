-- ============================================================================
-- 0197 — El certificado médico se puede guardar, y los 20 días avisan
-- ============================================================================
--
-- QUÉ PROMETE
--   Dos cosas que hoy no existen:
--     A. Un sitio donde guardar el certificado de un descanso médico o de una
--        maternidad — OPCIONAL, y visible solo para admin y líder de DO.
--     B. Un aviso cuando alguien se acerca a los 20 días de descanso médico en
--        el año, que es el umbral a partir del cual EsSalud subsidia.
--
-- QUÉ ASUME
--   Nada nuevo del cálculo. No toca `fn_planilla_calcular` ni ninguna función de
--   plata: solo agrega una columna, un almacén y una consulta.
--
-- ── DE DÓNDE SALE ───────────────────────────────────────────────────────────
--
-- El 2026-08-08 Felipe preguntó «¿dónde diablos subo el documento de descanso
-- médico?». La respuesta era «en ningún sitio, a propósito»: la 0101 decidió
-- guardar quién firmó y su colegiatura en vez del papel, con un razonamiento
-- bueno —un número de CMP se verifica contra el registro; una foto no prueba
-- nada por sí sola— y con una restricción de la época: **no había dónde
-- guardarlo**. Hoy hay cuatro almacenes funcionando.
--
-- Y hay un caso concreto donde el papel sirve para algo que el número no cubre:
-- **el reembolso de EsSalud**. Los primeros 20 días de incapacidad del año los
-- asume el empleador; a partir del día 21 EsSalud otorga el subsidio, y ese
-- reclamo se sustenta con el CITT. Sin el documento, hay plata que no se
-- reclama — y nadie se entera, porque no aparece en ningún reporte.
--
-- Que la pregunta la haya hecho quien mandó construir la pantalla es el dato que
-- ordena esta migración: si el operador del sistema se pierde ahí, cualquier
-- otra persona se pierde seguro.
--
-- ── POR QUÉ EL AVISO CUENTA SOLO EL DESCANSO MÉDICO ─────────────────────────
--
-- La maternidad TAMBIÉN exige documento y por eso entra en la parte A. Pero
-- **no** entra en el conteo de los 20 días, y confundirlas daría avisos falsos:
--
--   · descanso médico → incapacidad temporal. El empleador paga los primeros
--     20 días del año calendario; desde el 21 subsidia EsSalud.
--   · maternidad → subsidio propio de 98 días, cubierto por EsSalud desde el
--     primer día. No consume el cupo de los 20.
--
-- Sumarlas haría saltar el aviso por una licencia que ya está subsidiada.
--
-- ── POR QUÉ DÍAS CALENDARIO Y NO LABORABLES ─────────────────────────────────
--
-- El resto del sistema cuenta ausencias en días que a la persona le tocaba
-- trabajar — así se miden las faltas y las vacaciones. Acá NO: el CITT se emite
-- en días corridos, domingos incluidos, y el cupo de 20 que EsSalud lleva es en
-- esos mismos días. Contar laborables daría un número más bajo que el de
-- EsSalud, y el aviso llegaría tarde — que es justo cuando ya no sirve.
--
-- Es una inconsistencia deliberada con el resto del sistema, y por eso está
-- escrita: la referencia acá es EsSalud, no nuestra manera de contar.
--
-- ── POR QUÉ AVISA A LOS 15 Y NO A LOS 20 ────────────────────────────────────
--
-- Un aviso en el día 21 llega cuando el gasto ya ocurrió: solo permite
-- reaccionar. A los 15 quedan días para reunir el CITT y preparar el reclamo.
-- El umbral vive en `configuracion` para poder moverlo sin tocar código.
--
-- ── PRIVACIDAD ──────────────────────────────────────────────────────────────
--
-- Un certificado dice el diagnóstico de una persona. Solo lo abren admin y
-- líder de DO. La encargada de sede necesita saber que alguien no vino y que
-- está justificado —eso ya lo ve en la lista— pero no de qué está enferma. Es
-- el mismo criterio que la 0179 aplicó al motivo de cese: el dato viaja a quien
-- decide, no a quien opera.
--
-- ── LO QUE NO CAMBIA ────────────────────────────────────────────────────────
--
-- Subir el certificado es OPCIONAL. Los tres datos que la 0101 exige —quién
-- firmó, su colegiatura y la fecha— siguen siendo lo obligatorio. Hacer
-- obligatorio el papel dejaría a DO bloqueada cuando alguien avisa por teléfono
-- y trae el certificado al día siguiente, y entonces se registraría como otra
-- cosa: peor que no tenerlo.
--
-- Y las ausencias ya registradas se quedan como están. Exigir hacia atrás un
-- dato que no se pedía fabrica una lista de pendientes que nadie provocó.
--
-- CÓMO SE REVIERTE
--   alter table ausencias drop column doc_storage_path;
--   drop function fn_ausencias_subsidio(int);
--   delete from storage.buckets where id = 'certificados';
-- ============================================================================


-- ── A · Dónde vive el certificado ───────────────────────────────────────────

alter table ausencias add column if not exists doc_storage_path text;

comment on column ausencias.doc_storage_path is
  'Ruta del certificado en el almacen `certificados`. OPCIONAL: lo obligatorio '
  'siguen siendo doc_profesional, doc_colegiatura y doc_fecha (0101). Existe por '
  'el reembolso de EsSalud, que se sustenta con el CITT. Solo lo ven admin y '
  'lider de DO: es dato de salud.';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('certificados', 'certificados', false, 52428800,
        array['image/jpeg','image/png','image/heic','image/heif','image/webp','application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Las CUATRO políticas, no una. Supabase Storage escribe con
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, que necesita INSERT por la
-- fila, SELECT por el RETURNING y UPDATE por el ON CONFLICT. Faltando una, la
-- subida falla con un error que nombra la tabla y no dice cuál política faltó —
-- es lo que costó medio día el 2026-08-06 con los papeles firmados (0172).
drop policy if exists certificados_insert on storage.objects;
drop policy if exists certificados_select on storage.objects;
drop policy if exists certificados_update on storage.objects;
drop policy if exists certificados_delete on storage.objects;

create policy certificados_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'certificados' and fn_es_admin_o_lider() is true);

create policy certificados_select on storage.objects
  for select to authenticated
  using (bucket_id = 'certificados' and fn_es_admin_o_lider() is true);

create policy certificados_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'certificados' and fn_es_admin_o_lider() is true)
  with check (bucket_id = 'certificados' and fn_es_admin_o_lider() is true);

create policy certificados_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'certificados' and fn_es_admin_o_lider() is true);


-- ── B · El aviso de los 20 días ─────────────────────────────────────────────

insert into configuracion (clave, valor)
values ('descanso_medico_aviso_dias', '{"avisar_desde": 15, "umbral_essalud": 20}'::jsonb)
on conflict (clave) do nothing;

-- Quién se acerca al umbral. Devuelve SIEMPRE a quien tenga días en el año, con
-- su cuenta: así la pantalla puede mostrar «lleva 4 de 20» sin alarmar, y el
-- aviso es solo un campo más. Una función que devolviera únicamente a los que
-- pasan el umbral obligaría a una segunda consulta para lo demás.
create or replace function fn_ausencias_subsidio(p_anio int default null)
returns table (persona_id uuid, nombre text, dias_calendario int,
               umbral int, avisar_desde int, hay_que_avisar boolean,
               dias_para_el_umbral int, con_certificado int, sin_certificado int)
language sql stable security definer set search_path = public as $fn$
  with cfg as (
    select coalesce((valor->>'avisar_desde')::int, 15)   as avisar_desde,
           coalesce((valor->>'umbral_essalud')::int, 20) as umbral
    from configuracion where clave = 'descanso_medico_aviso_dias'
  ),
  anio as (select coalesce(p_anio, extract(year from fn_hoy_lima())::int) as a),
  -- Días CALENDARIO dentro del año, recortando la ausencia a sus bordes: un
  -- descanso del 28/12 al 05/01 aporta 4 días a un año y 5 al siguiente, que es
  -- como lo cuenta EsSalud.
  dias as (
    select a.persona_id,
           sum(
             least(a.fecha_fin,   make_date((select a from anio), 12, 31))
             - greatest(a.fecha_inicio, make_date((select a from anio), 1, 1))
             + 1
           )::int as dias,
           count(*) filter (where a.doc_storage_path is not null)::int as con_doc,
           count(*) filter (where a.doc_storage_path is null)::int     as sin_doc
    from ausencias a
    -- SOLO descanso médico. La maternidad tiene subsidio propio desde el primer
    -- día y no consume este cupo: sumarla haría saltar el aviso por una licencia
    -- que EsSalud ya está pagando.
    where a.tipo = 'descanso_medico'
      and a.anulada_at is null
      and a.fecha_fin    >= make_date((select a from anio), 1, 1)
      and a.fecha_inicio <= make_date((select a from anio), 12, 31)
    group by a.persona_id
  )
  select d.persona_id,
         pe.nombres || ' ' || pe.apellidos,
         d.dias,
         c.umbral,
         c.avisar_desde,
         d.dias >= c.avisar_desde,
         greatest(c.umbral - d.dias, 0),
         d.con_doc,
         d.sin_doc
  from dias d
  join personas pe on pe.id = d.persona_id
  cross join cfg c
  where fn_es_admin_o_lider()
     or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona())
  order by d.dias desc, 2;
$fn$;

grant execute on function fn_ausencias_subsidio(int) to authenticated;
revoke execute on function fn_ausencias_subsidio(int) from public, anon;


-- ── C · Enlazar el archivo con la ausencia ──────────────────────────────────
--
-- Función propia y NO un parámetro más en `fn_registrar_ausencia`. Dos razones:
--
--   1. La ruta se conoce DESPUÉS de crear la fila —lleva su id dentro— así que
--      un parámetro obligaría a inventar el id antes o a subir a una ruta que no
--      lo nombra. Es el mismo orden que usa el comprobante de educación.
--   2. `fn_registrar_ausencia` la llaman otras pantallas. Ampliar su contrato
--      para un caso que solo dos tipos usan las obliga a todas a conocerlo.
create or replace function fn_ausencia_adjuntar_certificado(
  p_ausencia_id uuid,
  p_storage_path text
) returns void
language plpgsql security definer set search_path = public as $fn$
declare
  v_tipo text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede adjuntar un certificado médico.';
  end if;

  select tipo into v_tipo from ausencias where id = p_ausencia_id;
  if not found then
    raise exception 'Esa ausencia no existe.';
  end if;

  -- Solo donde el documento tiene sentido. Un permiso personal no lleva
  -- certificado, y aceptar uno abriría un sitio para guardar papeles de salud
  -- fuera del único que se revisa.
  if v_tipo not in ('descanso_medico', 'maternidad') then
    raise exception 'El certificado solo va en un descanso médico o una maternidad; esta ausencia es «%».', v_tipo;
  end if;

  update ausencias set doc_storage_path = p_storage_path where id = p_ausencia_id;
end $fn$;

grant execute on function fn_ausencia_adjuntar_certificado(uuid, text) to authenticated;
revoke execute on function fn_ausencia_adjuntar_certificado(uuid, text) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (197, 'el_certificado_medico_se_guarda_y_los_20_dias_avisan')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_pol int;
  v_col boolean;
begin
  select count(*) into v_pol from pg_policies
   where tablename = 'objects' and policyname like 'certificados_%';
  select exists (select 1 from information_schema.columns
                  where table_name = 'ausencias' and column_name = 'doc_storage_path')
    into v_col;

  if v_pol <> 4 then
    raise warning '0197 · hay % politicas del almacen y deberian ser 4. Sin las cuatro, subir un archivo falla.', v_pol;
  elsif not v_col then
    raise warning '0197 · la columna doc_storage_path NO quedo creada.';
  else
    raise notice '0197 · listo. El certificado es OPCIONAL y solo lo ven admin y lider DO.';
    raise notice '0197 · el aviso salta a los 15 dias de descanso medico en el anio; el umbral de EsSalud son 20.';
  end if;
end $mig$;
