-- ============================================================================
-- 0270 — Los días de selección pagados no piden el Reglamento
-- ----------------------------------------------------------------------------
-- PROMETE: que `tipo_vinculo = 'prueba'` deje de contar en la población que
--   debe recibir el RIT, el RISST, la política de hostigamiento y la política
--   salarial —y deje de aparecer en la alerta de Disciplina que avisa a quién
--   le falta el Reglamento—, sin tocar `en_planilla` ni ninguno de los otros
--   catorce sitios que la leen para nómina, sobretiempo y asistencia.
--
-- ASUME: que 'prueba' sigue significando exactamente lo que fijó la 0085 —
--   días de selección, pagados por hora, con asistencia medida, ANTES de
--   firmar contrato— y no un periodo de prueba dentro de un contrato ya
--   firmado (art. 10 del D.S. 003-97-TR), que es un vínculo distinto y sí
--   está obligado a recibir estos documentos desde el día uno.
--
-- ── DECISIÓN DE FELIPE, 2026-08-18 ──────────────────────────────────────────
-- Kerin Guevara está en esos días de selección. Se le pidió la hoja de
-- constancias del RIT/RISST/política salarial y la respuesta fue que mientras
-- no firme contrato no debería salir en esa hoja.
--
-- ⚠ ESTO NO CIERRA EL RIESGO DE FONDO, LO ACOTA. La primacía de la realidad
-- —el mismo principio que la 0085 ya citó para 'prueba'— dice que un
-- inspector no lee `tipo_vinculo`: mira los hechos. Y los hechos que este
-- mismo sistema registra para alguien en selección —marca en el terminal,
-- pago por hora, atención de tienda real— son los que la 003-97-TR usa para
-- reconocer subordinación, con o sin contrato firmado. Esta migración decide
-- una sola cosa: que estos CUATRO documentos institucionales no se le exigen
-- mientras esté en esa etapa. No decide que la relación no sea laboral, y no
-- reduce el riesgo de trabajar sin registrar —el que la propia pantalla de
-- Equipo ya advierte, num. 25.20 del RLGIT— si esos días se alargan. Ese
-- riesgo se resuelve acortando el proceso de selección de verdad —sin marcar
-- asistencia, sin pago por hora, sin atender sola—, una decisión de negocio
-- pendiente y no de esta migración.
--
-- POR QUÉ CUATRO FUNCIONES Y NO UNA. La pregunta «a quién obliga el Reglamento
-- y los documentos institucionales» ya se contestaba en tres sitios más allá
-- de `fn_poblacion_obligada()` —la función que la 0265 creó para que hubiera
-- una sola respuesta— porque nacieron antes que ella y nunca se migraron a
-- usarla:
--
--   · fn_acuses_documento(uuid)          — 0208, alimenta la hoja de
--     constancias de Normas y el «quién falta» de esa pantalla.
--   · fn_acuses_politica_salarial()      — 0141, alimenta la hoja de
--     constancias de Política salarial.
--   · fn_sin_constancia_del_reglamento() — 0229, alimenta la alerta de
--     Disciplina antes de abrir un expediente (numeral 60.5).
--
-- Cambiar solo `fn_poblacion_obligada()` habría dejado tres respuestas
-- distintas a la misma pregunta —exactamente lo que la 0265 se creó para
-- evitar—, con Kerin desapareciendo de una hoja y reapareciendo en otra. Las
-- cuatro pasan a responder desde el mismo sitio.
--
-- `fn_documentos_vigentes()` NO se toca: desde la 0265 ya llama a
-- `fn_poblacion_obligada()`, así que el contador «N de M» de Normas se
-- corrige solo.
--
-- `fn_reglamento_no_acusado(persona_id, fecha)` TAMPOCO se toca: es el freno
-- del numeral 60.5 antes de sancionar a una persona CONCRETA, no una lista de
-- población. Seguir bloqueando ahí protege a cualquiera —esté o no en la
-- población obligada— de que se le sancione con un Reglamento que no se le
-- entregó. Quitarle ese freno a quien está en selección sería peor, no mejor.
--
-- CÓMO SE REVIERTE: volver los cuerpos de las cuatro funciones a los de su
-- migración anterior —0265 para `fn_poblacion_obligada`, 0208 para
-- `fn_acuses_documento`, 0141 para `fn_acuses_politica_salarial`, 0229 para
-- `fn_sin_constancia_del_reglamento`— con `create or replace`, sin `drop`:
-- ninguna cambió su firma.
-- ============================================================================

-- ── 1 · La única fuente: quién tiene contrato de trabajo ────────────────────
create or replace function fn_poblacion_obligada()
returns setof uuid
language sql stable security definer set search_path = public
as $fn$
  select id from personas
  where estado = 'activo' and tipo_vinculo = 'planilla';
$fn$;

comment on function fn_poblacion_obligada() is
  'Las personas a las que el Reglamento y los demas documentos institucionales obligan. Contrato de trabajo firmado: tipo_vinculo = planilla. NO incluye a quien esta en dias de selecion pagados (prueba, 0085) ni a locadoras (rxh) ni a quien no trabaja (no_trabajador). Vive en una sola funcion porque la misma pregunta se respondia con la misma frase escrita a mano en varios sitios, y dos respuestas distintas a una sola pregunta es lo que este repositorio prohibe.';

-- ── 2 · La hoja de constancias de Normas (RIT, RISST, hostigamiento…) ───────
create or replace function fn_acuses_documento(p_documento_id uuid)
returns table (
  persona_id uuid,
  nombre     text,
  sede       text,
  tiene_cuenta boolean,
  acusado_at timestamptz,
  via        text
)
language sql stable security definer set search_path = public
as $fn$
  -- Devuelve vacio para quien no puede verlo, en vez de fallar: la pantalla
  -- sigue funcionando y simplemente no muestra el panel de seguimiento.
  select p.id, p.nombres || ' ' || p.apellidos, s.codigo,
         p.auth_user_id is not null,
         a.acusado_at, a.via
  from personas p
  join sedes s on s.id = p.sede_base_id
  left join documentos_acuses a
         on a.persona_id = p.id and a.documento_id = p_documento_id
  where p.id in (select fn_poblacion_obligada())
    and fn_es_admin_o_lider() is true
  order by (a.acusado_at is not null), s.codigo, p.nombres;
$fn$;

-- ── 3 · La hoja de constancias de Política salarial ─────────────────────────
create or replace function fn_acuses_politica_salarial()
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_version int; v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver quien acuso la politica.';
  end if;

  select version into v_version from politica_salarial order by version desc limit 1;
  if v_version is null then
    return jsonb_build_object('version', null, 'personas', '[]'::jsonb);
  end if;

  select jsonb_build_object(
    'version', v_version,
    'personas', coalesce(jsonb_agg(jsonb_build_object(
      'persona_id', p.id,
      'nombre',     p.nombres || ' ' || p.apellidos,
      'rango',      s.rango,
      'acusado_at', a.acusado_at,
      'nombre_declarado', a.nombre_declarado
    ) order by (a.acusado_at is not null), p.apellidos, p.nombres), '[]'::jsonb)
  ) into v_out
  from personas p
  left join politica_salarial_acuses a
         on a.persona_id = p.id and a.version = v_version
  left join asignaciones_salario s
         on s.persona_id = p.id and s.vigente_hasta is null
  where p.id in (select fn_poblacion_obligada());

  return v_out;
end;
$fn$;

-- ── 4 · La alerta de Disciplina antes de abrir un expediente (numeral 60.5) ─
create or replace function fn_sin_constancia_del_reglamento()
returns table(persona_id uuid, motivo text)
language sql stable security definer set search_path = public as $$
  select p.id, fn_reglamento_no_acusado(p.id, fn_hoy_lima())
  from personas p
  where p.id in (select fn_poblacion_obligada())
    and fn_reglamento_no_acusado(p.id, fn_hoy_lima()) is not null
    -- Solo lo ve quien puede actuar sobre un expediente. Es una lista de quién
    -- no ha firmado algo: no es secreta, pero tampoco es de todos.
    and fn_es_admin_o_lider() is true;
$$;

comment on function fn_sin_constancia_del_reglamento() is
  'Quien tiene contrato de trabajo (fn_poblacion_obligada) y no tiene constancia del Reglamento vigente hoy, para avisar en Disciplina antes de empezar un procedimiento (numeral 60.5).';

insert into migraciones_aplicadas (numero, nombre)
values (270, 'los_dias_de_seleccion_pagados_no_piden_el_reglamento')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
-- Un solo select, porque el SQL Editor solo devuelve el último.
-- Tienen que salir las cuatro en `true`.
select
  (select position('tipo_vinculo' in p.prosrc) > 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_poblacion_obligada')
                                                          as poblacion_usa_tipo_vinculo,
  (select position('fn_poblacion_obligada' in p.prosrc) > 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_acuses_documento')
                                                          as acuses_documento_consolidada,
  (select position('fn_poblacion_obligada' in p.prosrc) > 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_acuses_politica_salarial')
                                                          as acuses_salarial_consolidada,
  (select position('fn_poblacion_obligada' in p.prosrc) > 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_sin_constancia_del_reglamento')
                                                          as sin_constancia_consolidada;
