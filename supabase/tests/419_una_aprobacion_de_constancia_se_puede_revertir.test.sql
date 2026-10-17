-- ============================================================================
-- 419_una_aprobacion_de_constancia_se_puede_revertir.test.sql
-- ============================================================================
-- Lo que promete la 0525, contado desde las dos puntas:
--   · DO revierte una aprobación con motivo (categoría + texto de 3 o más letras)
--     y la constancia queda «rechazada», con quién la aprobó y quién la revirtió;
--   · si era la ÚNICA aprobada, el pago se apaga (el espejo de la 0450); si había
--     otra, el pago sigue;
--   · si el pago ya salió con ella, se niega: «Reabre el periodo primero»;
--   · el calendario vuelve al pago que ya no tiene constancia;
--   · la única puerta es la función: un UPDATE directo, de quien sea, sigue negado;
--   · nadie revierte su propia constancia, y quien no es DO no revierte nada;
--   · «Aprobadas del ciclo» lista lo aprobado en el periodo y nada de lo revertido.
--
-- Las fechas se anclan a fn_hoy_lima(): una fecha fija caduca el día que el
-- reloj real la pasa.
-- ============================================================================
begin;
select plan(53);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000525a00', 'ZZ525', 'Sede de laboratorio 525', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000525d01', 'RevDO',    'Laboratorio', '00000000-0000-0000-0000-000000525a00', 'lider_do',   'test-hash', '00000000-0000-0000-0000-000000525f01', '2020-01-01'),
  ('00000000-0000-0000-0000-000000525d02', 'RevAna',   'Laboratorio', '00000000-0000-0000-0000-000000525a00', 'integrante', 'test-hash', '00000000-0000-0000-0000-000000525f02', '2025-01-02'),
  ('00000000-0000-0000-0000-000000525d03', 'RevBea',   'Laboratorio', '00000000-0000-0000-0000-000000525a00', 'integrante', 'test-hash', '00000000-0000-0000-0000-000000525f03', '2025-01-02'),
  ('00000000-0000-0000-0000-000000525d04', 'RevAdmin', 'Laboratorio', '00000000-0000-0000-0000-000000525a00', 'admin',      'test-hash', '00000000-0000-0000-0000-000000525f04', '2020-01-01');
set session_replication_role = origin;

insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por, frecuencia_pago, proxima_fecha_pago)
values
  ('00000000-0000-0000-0000-000000525b01', '00000000-0000-0000-0000-000000525d02',
   90, 'UPN de laboratorio', 120, 75, 'trabajador', fn_hoy_lima() - 60, fn_hoy_lima() + 200,
   '00000000-0000-0000-0000-000000525d01', 'mensual', null),
  ('00000000-0000-0000-0000-000000525b02', '00000000-0000-0000-0000-000000525d01',
   90, 'Curso de la DO', 120, 75, 'trabajador', fn_hoy_lima() - 60, fn_hoy_lima() + 200,
   '00000000-0000-0000-0000-000000525d04', 'mensual', null),
  ('00000000-0000-0000-0000-000000525b03', '00000000-0000-0000-0000-000000525d03',
   90, 'Instituto de Bea', 120, 75, 'trabajador', fn_hoy_lima() - 60, fn_hoy_lima() + 200,
   '00000000-0000-0000-0000-000000525d01', 'mensual', null);

insert into storage.objects (bucket_id, name, metadata)
select 'comprobantes',
       'educacion/00000000-0000-0000-0000-000000525d0' || x.p || '/entregas/00000000-0000-0000-0000-00000525e' || x.e || '/hoja.jpg',
       '{"mimetype":"image/jpeg","size":1000}'
  from (values ('2','001'), ('2','002'), ('2','005'), ('3','003'), ('1','004')) as x(p, e);

-- Un envío de Ana, de Bea o de la DO, tal cual lo haría la pantalla.
create function public.t419_enviar(p_persona text, p_sub text, p_entrega text, p_asig text,
                               p_fecha date, p_proxima date) returns void
language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f0' || p_sub, true);
  perform fn_educacion_enviar_entrega(
    ('00000000-0000-0000-0000-00000525e' || p_entrega)::uuid,
    ('00000000-0000-0000-0000-000000525b0' || p_asig)::uuid,
    p_fecha, 'cuota_mensual', p_proxima,
    jsonb_build_array(jsonb_build_object(
      'ruta', 'educacion/00000000-0000-0000-0000-000000525d0' || p_persona
              || '/entregas/00000000-0000-0000-0000-00000525e' || p_entrega || '/hoja.jpg',
      'nombre', 'hoja.jpg')));
end $f$;

grant execute on function public.t419_enviar(text, text, text, text, date, date) to authenticated;


-- ── 1 · Esquema ─────────────────────────────────────────────────────────────
select has_column('educacion_entregas', 'aprobacion_revertida_at', 'ESQUEMA · la reversión se guarda');
select has_column('educacion_entregas', 'aprobada_por', 'ESQUEMA · y quién aprobó de verdad');


-- ── 2 · Ana envía y DO aprueba ──────────────────────────────────────────────
set local role authenticated;
select t419_enviar('2', '2', '001', '1', fn_hoy_lima() - 5, fn_hoy_lima() + 25);

-- La aprueba la OTRA persona de DO (admin), para distinguir después quién aprobó
-- y quién revirtió.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f04', true);
select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000525e001', true);
reset role;

select isnt((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000525b01'),
  null, 'PUNTO DE PARTIDA · una constancia aprobada enciende el pago');
select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000525b01'),
  fn_hoy_lima() + 25, 'PUNTO DE PARTIDA · al aprobar, el calendario avanza');


-- ── 3 · Quién no puede ──────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f02', true);

select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', 'ilegible', 'No se lee bien') $$,
  '%Solo Desarrollo Organizacional%', 'PERMISO · una integrante no revierte aprobaciones');
select throws_like($$ select * from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e001') $$,
  '%Solo Desarrollo Organizacional%', 'PERMISO · ni mira qué pasaría');
select throws_like($$ select * from fn_educacion_aprobadas_del_periodo('00000000-0000-0000-0000-000000000001') $$,
  '%Solo Desarrollo Organizacional%', 'PERMISO · ni ve lo aprobado del ciclo');

reset role;
set local role anon;
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', 'ilegible', 'No se lee bien') $$,
  '%permission denied%', 'PERMISO · sin sesión no se llama a la función');
reset role;


-- ── 4 · DO: lo que pasaría, y los dos motivos mal puestos ───────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);

select is((select apaga_pago from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e001')), true,
  'EFECTO · es la única aprobada: apagaría el pago');
select is((select bloqueada from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e001')), false,
  'EFECTO · y todavía no hay un periodo pagado con ella');
select alike((select mensaje from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e001')),
  '%deja de pagarse%', 'EFECTO · lo dice en castellano');

select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', null, 'No se lee bien') $$,
  '%Elige el motivo%', 'MOTIVO · sin categoría no se revierte');
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', 'inventado', 'No se lee bien') $$,
  '%Elige el motivo%', 'MOTIVO · una categoría que no existe tampoco');
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', 'otro', 'ab') $$,
  '%qué tiene que corregir%', 'MOTIVO · menos de 3 letras no alcanza');
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', 'otro', '   ') $$,
  '%qué tiene que corregir%', 'MOTIVO · ni espacios');
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e999', 'otro', 'abc') $$,
  '%no existe%', 'CONSTANCIA · una que no existe se dice');


-- ── 5 · DO revierte la única aprobada ───────────────────────────────────────
select lives_ok($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', 'otro', '  Es de otro mes  ') $$,
  'REVERTIR · DO revierte la aprobación con «Otro» y un texto libre');
reset role;

select is((select estado from educacion_entregas where id = '00000000-0000-0000-0000-00000525e001'),
  'rechazada', 'REVERTIR · la constancia queda rechazada');
select is((select motivo_categoria || '|' || motivo_comentario from educacion_entregas where id = '00000000-0000-0000-0000-00000525e001'),
  'otro|Es de otro mes', 'REVERTIR · con su motivo, sin los espacios de los bordes');
select is((select aprobada_por from educacion_entregas where id = '00000000-0000-0000-0000-00000525e001'),
  '00000000-0000-0000-0000-000000525d04'::uuid, 'REVERTIR · se conserva quién la aprobó');
select isnt((select aprobada_at from educacion_entregas where id = '00000000-0000-0000-0000-00000525e001'),
  null, 'REVERTIR · y cuándo');
select is((select aprobacion_revertida_por from educacion_entregas where id = '00000000-0000-0000-0000-00000525e001'),
  '00000000-0000-0000-0000-000000525d01'::uuid, 'REVERTIR · y quién la revirtió');
select is((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000525b01'),
  null, 'PAGO · era la única aprobada: el pago se apaga');
select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000525b01'),
  fn_hoy_lima() - 5, 'CALENDARIO · vuelve al pago que ya no tiene constancia');
select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000525d02' and campo_modificado = 'educacion_entrega'
              and valor_anterior = 'aprobada' and valor_nuevo = 'rechazada · otro'
              and motivo like 'Aprobación revertida: Es de otro mes'),
  1, 'AUDITORÍA · queda su fila en el libro');
select is((select count(*)::int from educacion_entrega_archivos where entrega_id = '00000000-0000-0000-0000-00000525e001'),
  1, 'ARCHIVOS · la constancia conserva su hoja');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e001', 'otro', 'otra vez') $$,
  '%está rechazada%', 'REVERTIR · no se revierte dos veces');
select is((select revertida_por from fn_educacion_entregas('00000000-0000-0000-0000-000000525b01') where id = '00000000-0000-0000-0000-00000525e001'),
  'RevDO Laboratorio', 'HISTORIAL · DO lee quién la revirtió');
select is((select aprobada_por from fn_educacion_entregas('00000000-0000-0000-0000-000000525b01') where id = '00000000-0000-0000-0000-00000525e001'),
  'RevAdmin Laboratorio', 'HISTORIAL · y quién la había aprobado');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f02', true);
select is((select aprobada_por from fn_educacion_entregas('00000000-0000-0000-0000-000000525b01') where id = '00000000-0000-0000-0000-00000525e001'),
  null, 'HISTORIAL · la integrante no ve el nombre de quien aprobó');
select isnt((select revertida_at from fn_educacion_entregas('00000000-0000-0000-0000-000000525b01') where id = '00000000-0000-0000-0000-00000525e001'),
  null, 'HISTORIAL · pero sí ve que se revirtió');
reset role;


-- ── 6 · La única puerta ─────────────────────────────────────────────────────
set local role authenticated;
select t419_enviar('2', '2', '002', '1', fn_hoy_lima() - 4, fn_hoy_lima() + 26);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000525e002', true);
reset role;

select throws_like($$
  update educacion_entregas set estado = 'rechazada', motivo_categoria = 'otro', motivo_comentario = 'por la puerta de atrás',
         revisada_at = now()
   where id = '00000000-0000-0000-0000-00000525e002' $$,
  '%su revisión no se cambia%', 'PUERTA · un UPDATE directo, sin la marca, sigue negado');
select throws_like($$
  update educacion_entregas set aprobacion_revertida_at = now(), aprobacion_revertida_por = '00000000-0000-0000-0000-000000525d01'
   where id = '00000000-0000-0000-0000-00000525e002' $$,
  '%su revisión no se cambia%', 'PUERTA · poner solo la marca, sin cambiar el estado, también');
select throws_like($$
  update educacion_entregas set estado = 'aprobada'
   where id = '00000000-0000-0000-0000-00000525e001' $$,
  '%su revisión no se cambia%', 'PUERTA · una rechazada no vuelve a aprobarse por UPDATE');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select throws_like($$ update educacion_entregas set estado = 'rechazada' where id = '00000000-0000-0000-0000-00000525e002' $$,
  '%permission denied%', 'PUERTA · un cliente no escribe la tabla');
reset role;


-- ── 7 · Con otra aprobada, el pago sigue ────────────────────────────────────
set local role authenticated;
select t419_enviar('2', '2', '005', '1', fn_hoy_lima() - 2, fn_hoy_lima() + 28);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000525e005', true);

select is((select apaga_pago from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e005')), false,
  'EFECTO · hay otra aprobada: el pago no cambia');
select alike((select mensaje from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e005')),
  '%pago no cambia%', 'EFECTO · y lo dice');
select lives_ok($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e005', 'faltan_paginas_o_datos', 'Falta la segunda hoja') $$,
  'REVERTIR · con otra aprobada se puede');
reset role;

select isnt((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000525b01'),
  null, 'PAGO · el apoyo sigue pagándose con la otra constancia');
select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000525b01'),
  fn_hoy_lima() + 26, 'CALENDARIO · esa constancia no lo había movido: no lo retrasa');


-- ── 8 · El pago ya salió: se bloquea ────────────────────────────────────────
set local role authenticated;
select t419_enviar('3', '3', '003', '3', fn_hoy_lima() - 3, fn_hoy_lima() + 27);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000525e003', true);
reset role;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at) values
  ('00000000-0000-0000-0000-000000525c01', '2031-01-01', '2031-01-30', 'pagado', now());
-- Pagado ANTES de aprobar esta constancia: no la pudo usar.
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at)
values ('00000000-0000-0000-0000-000000525c01', 'planilla', 'pagado', now() - interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select is((select bloqueada from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e003')), false,
  'BLOQUEO · un periodo pagado antes de aprobarla no la usó');
reset role;

update periodo_grupo_pago set pagado_at = now() + interval '1 minute'
 where periodo_id = '00000000-0000-0000-0000-000000525c01';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select is((select bloqueada from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e003')), true,
  'BLOQUEO · un periodo pagado después de aprobarla sí');
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e003', 'otro', 'Se aprobó por error') $$,
  '%Reabre el periodo primero%', 'BLOQUEO · no se revierte y dice qué hacer');
reset role;

select is((select estado from educacion_entregas where id = '00000000-0000-0000-0000-00000525e003'),
  'aprobada', 'BLOQUEO · la constancia sigue aprobada');
select isnt((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000525b03'),
  null, 'BLOQUEO · y el pago sigue encendido');

-- Otro grupo pagado no bloquea a Bea (planilla): el pago es por grupo.
update periodo_grupo_pago set grupo = 'rxh'
 where periodo_id = '00000000-0000-0000-0000-000000525c01';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select is((select bloqueada from fn_educacion_revertir_efecto('00000000-0000-0000-0000-00000525e003')), false,
  'BLOQUEO · el pago es por grupo: otro grupo pagado no la frena');
reset role;


-- ── 9 · Nadie revierte lo propio ────────────────────────────────────────────
set local role authenticated;
select t419_enviar('1', '1', '004', '2', fn_hoy_lima() - 1, fn_hoy_lima() + 29);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f04', true);
select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000525e004', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);
select throws_like($$ select fn_educacion_revertir_aprobacion('00000000-0000-0000-0000-00000525e004', 'otro', 'abc') $$,
  '%tu propia constancia%', 'PROPIA · DO no revierte la aprobación de su propia constancia');
reset role;


-- ── 10 · Aprobadas del ciclo ────────────────────────────────────────────────
-- El periodo de hoy: si la base ya tiene uno que cruza estas fechas, se usa ese (los periodos no
-- se solapan); si no, se crea. Así la prueba no depende de qué periodos traiga la base.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
select '00000000-0000-0000-0000-000000525c02', fn_hoy_lima() - 10, fn_hoy_lima() + 20, 'abierto'
 where not exists (select 1 from periodos_planilla
                    where daterange(fecha_ini, fecha_fin, '[]') && daterange(fn_hoy_lima() - 10, fn_hoy_lima() + 20, '[]'));
create function public.t419_periodo_de_hoy() returns uuid language sql stable as $f$
  select id from periodos_planilla where fn_hoy_lima() between fecha_ini and fecha_fin order by fecha_ini, id limit 1
$f$;
grant execute on function public.t419_periodo_de_hoy() to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000525f01', true);

select is((select count(*)::int from fn_educacion_aprobadas_del_periodo(t419_periodo_de_hoy())
            where persona like 'Rev%'),
  3, 'CICLO · lista lo aprobado en el periodo: la de Ana, la de Bea y la de la DO');
select is((select count(*)::int from fn_educacion_aprobadas_del_periodo(t419_periodo_de_hoy())
            where entrega_id in ('00000000-0000-0000-0000-00000525e001', '00000000-0000-0000-0000-00000525e005')),
  0, 'CICLO · lo revertido ya no está');
select is((select aprobada_por from fn_educacion_aprobadas_del_periodo(t419_periodo_de_hoy())
            where entrega_id = '00000000-0000-0000-0000-00000525e002'),
  'RevDO Laboratorio', 'CICLO · dice quién la aprobó');
select is((select apaga_pago from fn_educacion_aprobadas_del_periodo(t419_periodo_de_hoy())
            where entrega_id = '00000000-0000-0000-0000-00000525e002'),
  true, 'CICLO · y que revertir esa apagaría el pago (era la única que quedó aprobada)');
select is((select count(*)::int from fn_educacion_aprobadas_del_periodo('00000000-0000-0000-0000-000000525c01')),
  0, 'CICLO · un periodo en el que no se aprobó nada sale vacío');
select throws_like($$ select * from fn_educacion_aprobadas_del_periodo('00000000-0000-0000-0000-000000525c99') $$,
  '%no existe%', 'CICLO · un periodo que no existe se dice');
reset role;

select * from finish();
rollback;
