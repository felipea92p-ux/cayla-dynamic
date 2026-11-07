-- Datos inventados para mirar el Archivo de la empresa con contenido: cinco papeles, uno por vencer y uno vencido. Solo para la base local:
-- `sembrar.mjs` lo corre al crear la base. Los números y las notas son inventados.
--
-- Cada papel entra por `fn_archivo_subir`, como Dana (DO), la misma puerta que usa la pantalla. Esa función toma el peso y el tipo del archivo desde el
-- almacén, y en local no hay almacén de verdad: por eso primero se deja en `storage.objects` una fila que hace de archivo. Abrir el papel desde la
-- pantalla no va a funcionar en local, igual que una boleta publicada.
--
-- Se puede correr dos veces: si el archivo ya tiene papeles, no hace nada.
begin;
do $$
declare
  dana uuid := (select auth_user_id from personas where email = 'do@dynamic.local');
  hoy date := (now() at time zone 'America/Lima')::date;
  papel record;
begin
  if exists (select 1 from archivo_empresa) then
    return;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', dana, 'role', 'authenticated')::text, true);

  for papel in
    select * from (values
      ('00000000-0000-4000-8000-0000000000e1.pdf', 'Constancia de inscripción en el REMYPE', 'Ministerio de Trabajo y Promoción del Empleo', 'REMYPE-0000000-2025',
       date '2025-03-10', null::date, null::text, 'constancia-remype.pdf', 'Inventada para el entorno local.'),
      ('00000000-0000-4000-8000-0000000000e2.pdf', 'Licencia de funcionamiento', 'Municipalidad Provincial de Trujillo', 'LF-0000-2024',
       date '2024-06-01', null::date, 'TRU', 'licencia-tru.pdf', null::text),
      ('00000000-0000-4000-8000-0000000000e3.pdf', 'Certificado de inspección técnica de seguridad', 'Municipalidad Provincial de Arequipa', 'ITSE-0000-2024',
       hoy - 705, hoy + 25, 'AQP', 'itse-aqp.pdf', 'Vence pronto: se renueva cada dos años.'),
      ('00000000-0000-4000-8000-0000000000e4.pdf', 'Certificado de inspección técnica de seguridad', 'Municipalidad Metropolitana de Lima', 'ITSE-0000-2024',
       hoy - 740, hoy - 10, 'LIM', 'itse-lim.pdf', null::text),
      ('00000000-0000-4000-8000-0000000000e5.jpg', 'Inscripción del banco de datos personales', 'Autoridad Nacional de Protección de Datos Personales', 'RNPDP-0000',
       date '2025-08-20', null::date, null::text, 'banco-de-datos.jpg', null::text)
    ) as t(ruta, titulo, entidad, numero, fecha, vence, sede, archivo, nota)
  loop
    insert into storage.objects (bucket_id, name, owner, metadata)
    values ('archivo-empresa', papel.ruta, dana,
            jsonb_build_object('mimetype', case when papel.ruta like '%.jpg' then 'image/jpeg' else 'application/pdf' end, 'size', 184320))
    on conflict do nothing;
    perform fn_archivo_subir(papel.ruta, papel.archivo, papel.titulo, papel.entidad, papel.numero, papel.fecha, papel.vence,
                             (select id from sedes where codigo = papel.sede), papel.nota);
  end loop;
end $$;
commit;
