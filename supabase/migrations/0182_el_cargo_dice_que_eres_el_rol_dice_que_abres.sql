-- ============================================================================
-- 0182 — El cargo dice qué eres; el rol sigue diciendo qué puedes abrir
-- ============================================================================
--
-- QUÉ PROMETE
--   Un campo donde escribir **qué es** una persona para CAYLA —«Socia»,
--   «Asesor», «Asesora»— sin tocar lo que puede ver. Cuando está vacío, las
--   pantallas siguen mostrando la etiqueta del rol, exactamente como hasta hoy.
--
-- QUÉ ASUME
--   Nada nuevo. Es una columna añadida y una función de escritura; ninguna
--   política de seguridad cambia y ningún cálculo la mira.
--
-- ── EL PROBLEMA QUE RESUELVE ────────────────────────────────────────────────
--
-- Tres personas cobran por honorarios —Carlos Espejo, Catherine Pereyra y
-- Claudia Pereyra— y la pantalla de Equipo las presenta como «Líder de equipo
-- (encargada)» y «Admin». Felipe confirmó el 2026-08-07 lo que son de verdad:
-- Catherine es SOCIA y trabaja en el horario que ella decide; Carlos y Claudia
-- son ASESORES, y ninguno de los tres trabaja bajo subordinación.
--
-- Que la pantalla los llame encargados no es un detalle cosmético. Cargo de
-- mando, área, sede, rango de la escala y monto fijo mensual son los indicios
-- que convierten una locación de servicios en un contrato de trabajo, y el
-- expediente lo estaba armando el propio sistema.
--
-- ── POR QUÉ UN CAMPO NUEVO Y NO UN ROL NUEVO ────────────────────────────────
--
-- Lo primero que se pensó fue agregar «socio» y «asesor» al enum `rol_usuario`.
-- Se midió antes de hacerlo y se descartó: en este sistema `rol` NO es un cargo,
-- es un permiso. Lo consultan **88 políticas RLS** y 21 comprobaciones en
-- `packages/shared/src/permisos.ts`. Un valor nuevo en el enum no pertenece a
-- ningún grupo, así que por defecto no pasa ninguna: Carlos habría perdido el
-- acceso a Desarrollo Organizacional —que su trabajo necesita— el mismo día, y
-- devolvérselo obligaba a revisar las 88 a mano.
--
-- Y el fondo importa más que el costo: mezclar «qué eres» con «qué puedes abrir»
-- es el mismo enredo que ya tiene `asignaciones_salario`, donde una sola tabla
-- dice a la vez qué lugar ocupas en la escala publicada y cuánto se te
-- transfiere. Una cosa que sirve para dos fines termina mintiendo sobre uno.
-- Acá se separan desde el principio.
--
-- ── POR QUÉ TEXTO LIBRE Y NO UN CATÁLOGO ────────────────────────────────────
--
-- Un catálogo de cargos exigiría decidir hoy la lista completa de lo que alguien
-- puede ser para CAYLA, y hay tres casos. Se empieza por el campo; si algún día
-- son quince y se repiten, entonces vale una tabla. Al revés —tabla primero— se
-- paga el costo antes de saber si hace falta.
--
-- El CHECK impide lo único que sí importa: que quede una cadena vacía o de puros
-- espacios, que en pantalla se ve igual que «sin cargo» pero se comporta distinto.
--
-- ── QUIÉN PUEDE ESCRIBIRLO ──────────────────────────────────────────────────
--
-- Solo admin o líder DO, por `fn_es_admin_o_lider()`, y en la forma
-- `is not true` que exige el CLAUDE.md: un null no puede pasar como autorizado.
-- Queda rastro en `correcciones_auditoria` — cambiar cómo se nombra a alguien no
-- debe ser silencioso aunque no mueva un céntimo.
--
-- CÓMO SE REVIERTE
--   alter table personas drop column cargo;
--   drop function fn_set_cargo(uuid, text);
--   Las pantallas vuelven solas a mostrar la etiqueta del rol: es lo que hacen
--   cuando el cargo está vacío.
-- ============================================================================

alter table personas add column if not exists cargo text;

do $mig$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_cargo_no_vacio') then
    alter table personas
      add constraint personas_cargo_no_vacio
      check (cargo is null or length(btrim(cargo)) > 0);
  end if;
end $mig$;

comment on column personas.cargo is
  'Que ES esta persona para CAYLA: Socia, Asesor, Encargada de tienda. Es lo que se MUESTRA. No decide ningun permiso — eso es `rol`, que lo consultan 88 politicas RLS. Vacio = la pantalla muestra la etiqueta del rol, como antes de la 0182.';

-- ── La función de escritura ─────────────────────────────────────────────────
create or replace function fn_set_cargo(p_persona_id uuid, p_cargo text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_antes text;
  v_nuevo text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede fijar el cargo.';
  end if;

  -- Vacío y solo-espacios se guardan como NULL, no como cadena vacía: las dos se
  -- ven igual en pantalla y solo una se comporta como «sin cargo».
  v_nuevo := nullif(btrim(coalesce(p_cargo, '')), '');

  select cargo into v_antes from personas where id = p_persona_id;
  if not found then
    raise exception 'No existe esa persona.';
  end if;

  if v_antes is not distinct from v_nuevo then
    return;   -- idempotente: sin cambio, sin fila de auditoría
  end if;

  update personas set cargo = v_nuevo where id = p_persona_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'cargo', coalesce(v_antes, '(sin cargo)'), coalesce(v_nuevo, '(sin cargo)'),
     coalesce(fn_persona_actual_id(), p_persona_id),
     'Cambio de cómo se nombra a esta persona en pantalla. No altera permisos ni pagos.');
end;
$$;

comment on function fn_set_cargo(uuid, text) is
  'Fija el cargo visible de una persona. Solo admin o lider DO. Deja rastro en correcciones_auditoria. No toca permisos ni pagos.';

grant execute on function fn_set_cargo(uuid, text) to authenticated;
revoke execute on function fn_set_cargo(uuid, text) from public, anon;

-- ── Y la pantalla de Equipo necesita recibirlo ──────────────────────────────
-- Copiada entera de la 0179 —la vigente, comprobada con `donde-vive.sh`— con un
-- solo cambio: se agrega `cargo` al objeto. El resto es byte por byte lo mismo.
--
-- El cargo lo ve QUIEN YA VE LA FILA, sin guard propio: es cómo se llama a una
-- persona en pantalla, no un dato sensible. El motivo de cese sí lo tiene, y esa
-- diferencia es a propósito.
create or replace function fn_personas_funciones()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos,
           'es_encargada_piso', p.es_encargada_piso,
           'visible_todas_sedes', p.visible_todas_sedes,
           'tipo_vinculo', p.tipo_vinculo,
           'en_planilla', p.en_planilla,
           -- CAMBIO 0182 · qué ES esta persona, para que la pantalla no tenga
           -- que deducirlo de su rol —que es un permiso, no un cargo—.
           'cargo', p.cargo,
           -- CAMBIO 0179 · cuándo se fue: lo ve quien ya veía la fila.
           'fecha_cese', p.fecha_cese,
           -- CAMBIO 0179 · por qué se fue: solo administración. `is not true`
           -- y no `not (...)`, por el estándar del repo: un null no pasa como
           -- autorizado.
           'motivo_cese', case when fn_es_admin_o_lider() is not true
                               then null else p.motivo_cese end)), '[]'::jsonb)
  from personas p
  where
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
    or p.auth_user_id = auth.uid()
    or (p.estado = 'activo'
        and fn_sede_actual_terminal() is not null
        and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true));
$$;

grant  execute on function fn_personas_funciones() to authenticated;
revoke execute on function fn_personas_funciones() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (182, 'el_cargo_dice_que_eres_el_rol_dice_que_abres')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
