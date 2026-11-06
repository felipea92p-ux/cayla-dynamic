-- Datos inventados para mirar Boletas y Educación con contenido. Solo para la base local: `sembrar.mjs` lo corre al crear la base.
-- Lo que tiene función propia pasa por ella. Una boleta publicada lleva sus archivos y aquí no hay almacenamiento: esas filas entran directo.
-- Se puede correr dos veces: si ya hay apoyos por educación, no hace nada.
begin;
do $$
declare
  hoy date := (now() at time zone 'America/Lima')::date;
  dana uuid := (select auth_user_id from personas where email = 'do@dynamic.local');
  alma uuid := (select id from personas where email = 'admin@dynamic.local');
  periodo uuid := (select id from periodos_planilla where estado = 'pagado' order by fecha_ini desc limit 1);
  -- Un apoyo no puede empezar en un mes ya pagado: la función lo rechaza.
  desde date := (select max(fecha_ini) from periodos_planilla where estado = 'abierto');
  version uuid;
  boleta uuid;
  quien record;
begin
  if exists (select 1 from asignaciones_educacion) then
    return;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', dana, 'role', 'authenticated')::text, true);

  -- Educación: un apoyo para quien estudia y otro por un hijo.
  perform fn_educacion_registrar((select id from personas where nombres = 'Elena'), 'Instituto Textil del Norte', 480, 'trabajador', desde, hoy + 110);
  perform fn_educacion_registrar((select id from personas where nombres = 'Julia'), 'Colegio San Martín', 350, 'hijo', desde, hoy + 60, p_beneficiario_nombre := 'Mateo Paredes');

  -- Boletas del último mes pagado: dos entregadas en papel, una por firmar y una firmada.
  perform fn_boleta_marcar_papel(periodo, (select id from personas where nombres = 'Bruno'));
  perform fn_boleta_marcar_papel(periodo, (select id from personas where nombres = 'Camila'));

  set local session_replication_role = replica;
  for quien in
    select p.id, p.nombres from personas p where p.nombres in ('Luz', 'Carmen')
  loop
    boleta := gen_random_uuid();
    version := gen_random_uuid();
    insert into boletas (id, periodo_id, persona_id, estado, publicada_at, publicada_por, creada_at, creada_por)
    values (boleta, periodo, quien.id, 'publicada', now() - interval '2 days', alma, now() - interval '2 days', alma);
    insert into boletas_versiones (id, boleta_id, n, tipo, avisar, creada_at, creada_por)
    values (version, boleta, 1, 'imagen', false, now() - interval '2 days', alma);
    insert into boletas_partes (id, version_id, tipo, orden, storage_path, mime, bytes)
    values (gen_random_uuid(), version, 'imagen', 1, boleta || '/' || version || '/parte.jpg', 'image/jpeg', 1000);
    if quien.nombres = 'Luz' then
      insert into boletas_acuses (version_id, vista_at, recibida_at, firma)
      select version, now() - interval '1 day', now() - interval '1 day', firma_sancionado
        from expediente_disciplinario where correlativo = 'MEM-2026-0001';
    end if;
  end loop;
end $$;
commit;
