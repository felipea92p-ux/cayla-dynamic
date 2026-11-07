-- Datos inventados para mirar Seguros, Objetivos y Casos con contenido. Solo para la base local: `sembrar.mjs` lo corre al crear la base.
-- Pasan por las funciones reales, con la sesión de quien lo haría en la app, para que nada entre por un camino que la pantalla no tiene.
-- Se puede correr dos veces: si ya hay objetivos, no hace nada.
begin;
do $$
declare
  anio int := extract(year from (now() at time zone 'America/Lima'))::int;
  mes int := extract(month from (now() at time zone 'America/Lima'))::int;
  hoy date := (now() at time zone 'America/Lima')::date;
  dana uuid := (select auth_user_id from personas where email = 'do@dynamic.local');
  ana uuid := (select auth_user_id from personas where email = 'integrante@dynamic.local');
  tru uuid := (select id from sedes where codigo = 'TRU');
  quien record;
  frase text;
  orden int;
  item uuid;
begin
  if exists (select 1 from objetivos_items) then
    return;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', dana, 'role', 'authenticated')::text, true);

  -- Objetivos: unos cumplidos, otros no; y la persona con el nombre más largo, que es la que rompe las filas.
  for quien in
    select id, row_number() over (order by nombres) as n
      from personas
     where nombres in ('Ana', 'Rosa', 'Elena', 'Julia', 'María de los Ángeles Concepción', 'Pedro')
  loop
    orden := 0;
    foreach frase in array array[
      'Atender a cada clienta en los primeros dos minutos',
      'Registrar las tallas que faltaron en la semana',
      'Dejar el probador listo antes de abrir',
      'Proponer una mejora para la vitrina del mes'
    ] loop
      item := (fn_objetivo_agregar(quien.id, anio, mes, frase, null)->>'id')::uuid;
      orden := orden + 1;
      if orden <= quien.n % 4 then
        perform fn_objetivo_marcar(item, true);
      end if;
    end loop;
  end loop;

  -- Seguros: Vida Ley al día, una por vencer, una vencida y un FOLA de practicante.
  perform fn_seguro_registrar((select id from personas where nombres = 'Ana'), 'vida_ley', 'Pacífico Seguros', 'VL-2026-0101',
    hoy - 200, hoy + 165, 420, hoy - 170, 'Plan grupal', null, null, true, null);
  perform fn_seguro_registrar((select id from personas where nombres = 'Rosa'), 'vida_ley', 'Pacífico Seguros', 'VL-2026-0102',
    hoy - 340, hoy + 25, 410, hoy - 310, 'Plan grupal', null, null, false, 'Hay que renovarla antes de fin de mes.');
  perform fn_seguro_registrar((select id from personas where nombres = 'Elena'), 'vida_ley', 'Rimac Seguros', 'VL-2025-0877',
    hoy - 380, hoy - 15, 395, hoy - 350, null, null, null, false, null);
  perform fn_seguro_registrar((select id from personas where nombres = 'Camila'), 'salud_practicantes', 'Pacífico Seguros', 'SP-2026-0044',
    hoy - 22, hoy + 343, 610, hoy + 8, 'Salud Practicantes', 15000, 30000, true, null);

  -- Casos: lo que ve la líder de equipo de Trujillo. El relato lo escribiría la integrante desde Lo mío.
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  perform fn_reporte_crear('empresa', 'reclamo', tru, hoy - 3, 'Los turnos del sábado se publicaron el viernes en la noche y no alcancé a organizarme.');
  perform fn_reporte_crear('idea', 'reclamo', tru, hoy - 1, 'Propongo un cartel con las tallas que llegan cada semana, para no preguntar a cada rato.');
  perform fn_reporte_crear('persona', 'convivencia', tru, hoy - 6, 'Hubo un malentendido con una compañera sobre quién atendía a una clienta. Quisiera conversarlo.',
    p_involucradas := array[(select id from personas where nombres = 'Rosa')], p_espera := 'conversar', p_primera_vez := true);
end $$;
commit;
