-- Los papeles que el entorno local no trae de fábrica: unos cargos, una política publicada, una norma y una boleta con su constancia. TODO inventado, y solo existe mientras dura
-- la toma de tema/papel.mjs --con-inventados, que al terminar corre el bloque del final. No va en la semilla porque se notaría: una política publicada le pide acuse a todo el mundo
-- y cambiaría lo que Felipe ve en las demás pantallas.
--
-- Alma Reyes (admin) y Ana Torres (integrante) quedan con sus acuses hechos: si no, la ventana de «tienes algo por leer» taparía lo que se quiere medir. Dos personas quedan sin
-- acusar, para que las constancias muestren también la lista de quien falta.

set session_replication_role = replica; -- los frenos de la base (firmas, estados, inmutables) no aplican a unas filas que se borran en un minuto

insert into politica_salarial (version, documento, huella_cuadro, notas, publicada_por, publicada_at)
select 1, 'Política salarial inventada para el entorno local.', 'inventada', 'Inventada', id, timestamptz '2026-11-03 09:00-05' from personas where nombres = 'Alma' and apellidos = 'Reyes Soto'
on conflict do nothing;

insert into politica_salarial_acuses (persona_id, version, nombre_declarado, acusado_at)
select p.id, 1, p.nombres || ' ' || p.apellidos, timestamptz '2026-11-03 11:00-05' from personas p
 where p.estado = 'activo' and p.nombres not in ('Bruno', 'Camila')
on conflict do nothing;

insert into documentos_institucionales (id, tipo, version, titulo, documento, vigente_desde, publicado_por, publicado_at)
select '00000000-0000-4000-8000-0000000000a1', 'rit', 99, 'Reglamento inventado', 'Reglamento inventado para el entorno local.', date '2026-10-27', id, timestamptz '2026-10-27 11:00-05'
  from personas where nombres = 'Alma' and apellidos = 'Reyes Soto'
on conflict do nothing;

insert into documentos_acuses (documento_id, persona_id, via, nombre_declarado, acusado_at)
select '00000000-0000-4000-8000-0000000000a1', p.id, 'sistema', p.nombres || ' ' || p.apellidos, timestamptz '2026-11-03 11:00-05' from personas p
 where p.estado = 'activo' and p.nombres not in ('Bruno', 'Camila')
on conflict do nothing;

insert into expediente_disciplinario (id, correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, firmante_id, firmado_at, creado_por,
                                      cargos_comunicados_at, descargo_vence_at, enviado_a_info_at, enviado_a_info_por)
select '00000000-0000-4000-8000-0000000000a2', 'MEM-2026-0090', persona_id, 'tardanza', 'amonestacion', 'firmado', periodo_desde, periodo_hasta, hechos -> 'tardanzas', firmante_id, timestamptz '2026-11-04 10:00-05', creado_por,
       timestamptz '2026-11-04 10:00-05', timestamptz '2026-11-10 18:00-05', timestamptz '2026-11-04 10:00-05', firmante_id
  from expediente_disciplinario where correlativo = 'MEM-2026-0001'
on conflict do nothing;

insert into boletas (id, periodo_id, persona_id, estado, publicada_at, publicada_por, creada_at, creada_por)
select '00000000-0000-4000-8000-0000000000a3', (select id from periodos_planilla order by fecha_ini desc limit 1), a.id, 'publicada', timestamptz '2026-11-03 09:00-05', d.id, timestamptz '2026-11-03 09:00-05', d.id
  from personas a, personas d where a.nombres = 'Ana' and a.apellidos = 'Torres Ruiz' and d.nombres = 'Alma' and d.apellidos = 'Reyes Soto'
on conflict do nothing;

insert into boletas_versiones (id, boleta_id, n, tipo, avisar, creada_at, creada_por)
select '00000000-0000-4000-8000-0000000000a4', '00000000-0000-4000-8000-0000000000a3', 1, 'imagen', false, timestamptz '2026-11-03 09:00-05', publicada_por
  from boletas where id = '00000000-0000-4000-8000-0000000000a3'
on conflict do nothing;

insert into boletas_acuses (version_id, vista_at, recibida_at, firma)
select '00000000-0000-4000-8000-0000000000a4', timestamptz '2026-11-04 10:00-05', timestamptz '2026-11-04 10:00-05', firma_sancionado
  from expediente_disciplinario where correlativo = 'MEM-2026-0001'
on conflict do nothing;

insert into boletas_partes (id, version_id, tipo, orden, storage_path, mime, bytes)
select '00000000-0000-4000-8000-0000000000a5', '00000000-0000-4000-8000-0000000000a4', 'imagen', 1,
       '00000000-0000-4000-8000-0000000000a3/00000000-0000-4000-8000-0000000000a4/00000000-0000-4000-8000-0000000000a5.jpg', 'image/jpeg', 1000
on conflict do nothing;

-- Alguien que cesó ayer, con su liquidación por cobrar. Quien ya está de baja en los datos inventados tiene el total en cero, y esa no llega a la lista.
update personas set estado = 'inactivo', fecha_cese = current_date - 1 where nombres = 'Marta' and apellidos = 'Silva León';

set session_replication_role = origin;

-- ---------- BORRAR ----------
-- set session_replication_role = replica;
-- update personas set estado = 'activo', fecha_cese = null where nombres = 'Marta' and apellidos = 'Silva León';
-- delete from recepciones_cargos where expediente_id = '00000000-0000-4000-8000-0000000000a2';
-- delete from boletas_partes where id = '00000000-0000-4000-8000-0000000000a5';
-- delete from boletas_acuses where version_id = '00000000-0000-4000-8000-0000000000a4';
-- delete from boletas_versiones where id = '00000000-0000-4000-8000-0000000000a4';
-- delete from boletas where id = '00000000-0000-4000-8000-0000000000a3';
-- delete from expediente_disciplinario where id = '00000000-0000-4000-8000-0000000000a2';
-- delete from documentos_acuses where documento_id = '00000000-0000-4000-8000-0000000000a1';
-- delete from documentos_institucionales where id = '00000000-0000-4000-8000-0000000000a1';
-- delete from politica_salarial_acuses where version = 1;
-- delete from politica_salarial where version = 1;
-- set session_replication_role = origin;
