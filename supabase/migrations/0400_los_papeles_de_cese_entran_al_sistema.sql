-- ============================================================================
-- 0400 — El certificado de trabajo y la constancia de cese entran al sistema
-- ============================================================================
--
-- QUÉ PROMETE
--   Una función de solo lectura, `fn_papeles_cese(p_persona_id)`, con los
--   datos de identidad y de vínculo que hacen falta para imprimir los dos
--   papeles que TODO cese exige entregar, sin importar el motivo (renuncia,
--   fin de contrato, mutuo acuerdo, despido…): el certificado de trabajo y la
--   constancia de cese.
--
--   No es una obligación nueva: ya está en el Reglamento Interno vigente
--   (numeral 59.6, literales a y b) y en la ley que cita — Tercera Disposición
--   Complementaria del D.S. 001-96-TR para el certificado, art. 45 del D.S.
--   001-97-TR para la constancia (es la llave con la que la persona retira su
--   CTS del banco). Hasta hoy, ninguno de los dos existía en ningún lugar del
--   sistema — confirmado por `grep` antes de escribir esta migración.
--
-- QUÉ ASUME
--   · `personas.fecha_cese`, `motivo_cese` (0086) y `documento`, `cargo`,
--     `funcion`, `tipo_vinculo`, `sede_base_id` (0001) ya existen.
--   · `datos_personales.genero` (0369) es la misma fuente que ya usa el
--     convenio de prácticas para "EL/LA PRACTICANTE" — no se inventa un
--     segundo criterio de género para un documento distinto.
--   · El guard `fn_es_admin_o_lider()` (0078, null-safe con `is not true`) es
--     el mismo que ya protege `fn_liquidacion`: esta función expone el mismo
--     nivel de dato sensible (DNI, cargo) y no necesita uno propio.
--
-- POR QUÉ NO EXTIENDE fn_liquidacion NI CREA UNA TABLA
--   Añadirle columnas de identidad a la función que calcula la liquidación
--   mezclaría "cuánto se le debe" con "quién es y qué hizo" en la función más
--   sensible y con más historial del repositorio (24 versiones, dinero real).
--   Una función nueva, de solo lectura, que no toca plata, es más barata de
--   revisar y de revertir.
--
--   Y no hay tabla `certificados_generados`: el documento se arma en vivo con
--   los datos vigentes de la persona y se imprime, igual que la liquidación y
--   el contrato — no se guarda un PDF. Decisión explícita del 2026-09-08: si
--   algún dato de la persona cambia después de emitido, el papel entregado
--   fue el correcto en su momento y no hay nada que versionar.
--
-- POR QUÉ EL MOTIVO DE CESE NO SALE EN NINGÚN PAPEL IMPRESO
--   Se devuelve en el jsonb (le sirve a quien genera el documento para saber
--   qué está mirando en pantalla) pero ningún componente de impresión lo
--   muestra. Ni el certificado de trabajo ni la constancia de cese son el
--   lugar para dejar constancia de por qué alguien se fue — son los dos
--   papeles que existen justamente para que la persona pueda seguir su vida
--   laboral sin cargar con esa explicación por escrito.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_papeles_cese(uuid);
-- ============================================================================

create or replace function fn_papeles_cese(p_persona_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p       personas%rowtype;
  v_sede    text;
  v_genero  text;
  v_edad    interval;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver los papeles de cese de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then
    raise exception 'La persona no existe.';
  end if;

  if v_p.fecha_cese is null then
    raise exception 'Esa persona no tiene fecha de cese. Estos papeles son de cese.';
  end if;

  select nombre into v_sede from sedes where id = v_p.sede_base_id;
  select genero into v_genero from datos_personales where persona_id = p_persona_id;

  v_edad := age(v_p.fecha_cese, v_p.fecha_ingreso);

  return jsonb_build_object(
    'nombre_completo',        v_p.nombres || ' ' || v_p.apellidos,
    'documento',              v_p.documento,
    'genero',                 v_genero,
    'cargo',                  v_p.cargo,
    'funcion',                v_p.funcion,
    'tipo_vinculo',           v_p.tipo_vinculo,
    'sede',                   v_sede,
    'fecha_ingreso',          v_p.fecha_ingreso,
    'fecha_cese',             v_p.fecha_cese,
    'motivo_cese',            v_p.motivo_cese,
    'tiempo_servicio_anios',  extract(year  from v_edad)::int,
    'tiempo_servicio_meses',  extract(month from v_edad)::int,
    'tiempo_servicio_dias',   extract(day   from v_edad)::int
  );
end;
$$;

grant execute on function fn_papeles_cese(uuid) to authenticated;

-- El error que ya costó una pantalla en blanco más de una vez en este
-- repositorio: la función queda bien escrita y nadie puede llamarla.
do $$
begin
  if not has_function_privilege('authenticated', 'fn_papeles_cese(uuid)', 'execute') then
    raise exception '0400 · authenticated NO puede llamar a fn_papeles_cese: la pantalla se queda en blanco.';
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre)
values (400, 'los_papeles_de_cese_entran_al_sistema')
on conflict (numero) do nothing;
