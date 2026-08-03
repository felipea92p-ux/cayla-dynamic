-- ============================================================================
-- 0128 — La base declarada por rango, en los dos campos que la sostienen.
--
-- QUÉ PROMETE. Que fijar la base declarada de un rango baje LOS DOS campos que
-- intervienen en el pago —`asignaciones_salario.salario_mensual_soles` y
-- `personas.sueldo_base_legal`— al mismo monto, versionando el salario y sin
-- tocar los periodos ya pagados.
--
-- ── POR QUÉ DOS CAMPOS Y NO UNO ─────────────────────────────────────────────
--
-- Porque la auditoría empírica del 2026-08-01 (contra Postgres local, en
-- BEGIN … ROLLBACK) encontró que el pago NO sale de la base declarada:
--
--     pago_base = horas × salario_mensual_soles / v_base
--     basica    = horas × least(sueldo_base_legal, salario) / v_base
--
-- O sea: bajar solo `sueldo_base_legal` cambia el DESGLOSE de la boleta y no
-- cambia un céntimo de lo que se paga. Sumarle encima movilidad, educación y
-- bono sobrepagaría por el monto entero de esos conceptos —del orden de
-- S/4,900 al mes entre el equipo—. Lo que Felipe eligió al decir «base = lo
-- declarado» exige tocar los dos campos a la vez; lo que faltaba era saberlo.
--
-- ── ⚠️ ESTA MIGRACIÓN NO SE APLICA SOLA, Y ES A PROPÓSITO ───────────────────
--
-- Crear la función no mueve ningún pago. Bajar las bases SÍ los mueve, y hacia
-- abajo: el diseño remunerativo compensa esa baja con movilidad + educación +
-- bono de cumpleaños. Estado de los tres al 2026-08-02:
--
--     movilidad   ENCENDIDA · S/10.00/día desde el 29/07 (parametros_laborales)
--     educación   vacía     · cero asignaciones cargadas (0120)
--     bono        no existe · S/180 decidido, sin implementar
--
-- O sea: uno de tres. Ejecutar `fn_fijar_base_declarada` hoy significa pagar de
-- menos, y la cifra no es una estimación — MEDIDA contra Postgres local el
-- 2026-08-02, bajando cayla de 1,450 a 1,130 sobre el periodo 29/07–28/08 con la
-- movilidad encendida:
--
--     antes    S/1,887.14
--     después  S/1,519.77
--     pierde   S/  367.37   en un periodo de cuatro días marcados
--
-- Proyectado a un mes completo son los S/320 de salario que se bajan, y que la
-- asignación por educación tendría que reponer. Por rango, lo que hace falta:
--
--     cayla      191.90     aurora     310.00
--     support    252.70     oráculo    400.30     archicaylo  402.10
--
-- Y ahí está el freno que hace que esto NO pueda ser una llamada por rango a
-- ciegas: LA EDUCACIÓN ES POR PERSONA Y CONTRA COMPROBANTE. Quien no estudia no
-- tiene el concepto, así que bajarle la base le recorta el sueldo sin nada que lo
-- reemplace. Para esa persona el rango se llama con `p_omitir`, o su base se fija
-- en un monto propio más alto.
--
-- Por eso la migración deja la herramienta y NO la usa: la llamada va aparte, el
-- día que los conceptos que compensan estén vivos y por las personas que de
-- verdad los tengan. Mismo criterio que la 0110 a la 0118.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- · `fn_set_salario` (0019) versiona el salario: cierra el tramo anterior el
--   día previo a la vigencia y abre uno nuevo. No se reimplementa ese versionado
--   acá — se llama, para que exista un solo lugar donde el salario se escribe.
-- · `fn_set_sueldo_base_legal` (0106) valida y escribe la básica legal.
-- · Ambas exigen sesión de admin o líder, y el SQL Editor no la trae. El
--   prólogo de `docs/estado.md` (set_config de request.jwt.claim.sub) es
--   obligatorio antes de llamar a esta función.
-- · El candado de periodo pagado (0037 / 0115) sigue vigente: la vigencia tiene
--   que caer en el primer periodo ABIERTO, nunca dentro de uno ya pagado.
--
-- ── LÍMITE CONOCIDO Y HEREDADO DE LA 0106 ───────────────────────────────────
--
-- `personas.sueldo_base_legal` NO está versionado: vive en `personas`, no por
-- periodo. Cambiarlo cambia el DESGLOSE de las boletas pasadas de esa persona
-- —no sus totales, que la foto del pago (0096) congela—. La 0106 ya lo dejó
-- anotado y sigue sin resolverse. Se acepta a sabiendas: la alternativa es
-- versionar la básica por periodo, y eso es una migración propia.
--
-- ── POR QUÉ NO HAY NI UN NOMBRE NI UN MONTO INDIVIDUAL ACÁ ──────────────────
--
-- Porque el `CLAUDE.md` prohíbe commitear sueldos por persona. La función toma
-- el rango y el monto como parámetros y acepta una lista de personas a OMITIR;
-- las excepciones nominales viven en `scripts/sql-manual/`, que está en el
-- .gitignore.
--
-- CÓMO SE REVIERTE. `drop function fn_fijar_base_declarada(text, numeric, date,
-- uuid[])`. Si ya se llamó y hay que deshacer el efecto, se vuelve a llamar con
-- el salario anterior del rango y la MISMA fecha de vigencia — `fn_set_salario`
-- borra los tramos que arrancan en esa fecha, así que no quedan solapados.
-- ============================================================================

create or replace function fn_fijar_base_declarada(
  p_rango          text,
  p_monto          numeric,
  p_vigente_desde  date,
  p_omitir         uuid[] default '{}'
)
returns table (persona_id uuid, salario_anterior numeric, base_anterior numeric)
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_p record;
begin
  -- Guard DENTRO de la función, no en un revoke (lección de la 0090), y en la
  -- forma "is not true" que exige el CLAUDE.md: fn_es_admin_o_lider() devuelve
  -- null para una identidad autenticada sin fila en personas, y "if not null"
  -- no lanza — fallaría abierto.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede fijar la base declarada.';
  end if;

  if p_rango is null or p_rango not in
     ('colibri','cayla','caylo','support','aurora','oraculo','archicaylo') then
    raise exception 'Rango inválido: %', coalesce(p_rango, '(vacío)');
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'La base declarada debe ser mayor que cero.';
  end if;
  if p_vigente_desde is null then
    raise exception 'La fecha de vigencia es obligatoria.';
  end if;

  -- Quién queda alcanzado: quien tenga ESE rango vigente hoy, esté activo y sea
  -- trabajador. Un locador no tiene remuneración que declarar (0117), y a una
  -- persona cesada no se le reescribe el salario: su historial sostiene los
  -- reportes de los periodos en que sí trabajó.
  for v_p in
    select p.id,
           a.salario_mensual_soles as salario_ant,
           p.sueldo_base_legal     as base_ant
      from personas p
      join asignaciones_salario a
        on a.persona_id = p.id and a.vigente_hasta is null
     where a.rango = p_rango
       and p.estado = 'activo'
       and p.en_planilla is true
       and not (p.id = any (coalesce(p_omitir, '{}'::uuid[])))
     order by p.apellidos, p.nombres
  loop
    -- Idempotente: si ya está en el monto pedido, no se abre un tramo nuevo ni
    -- se ensucia la auditoría. Esta migración se pega a mano, y una mano repite.
    if v_p.salario_ant is distinct from p_monto
       or v_p.base_ant is distinct from p_monto then

      perform fn_set_salario(
        v_p.id, p_rango, p_monto, p_vigente_desde,
        'Base declarada del rango ' || p_rango || ' (0128). El salario baja al monto '
        || 'declarado porque el pago se calcula sobre este campo, no sobre '
        || 'sueldo_base_legal; la diferencia hasta el rango se compone con movilidad, '
        || 'asignación por educación y bono.'
      );

      perform fn_set_sueldo_base_legal(v_p.id, p_monto);

      persona_id       := v_p.id;
      salario_anterior := v_p.salario_ant;
      base_anterior    := v_p.base_ant;
      return next;
    end if;
  end loop;
end;
$$;

comment on function fn_fijar_base_declarada(text, numeric, date, uuid[]) is
  'Baja la base declarada de un rango en LOS DOS campos que intervienen en el pago '
  '(asignaciones_salario.salario_mensual_soles y personas.sueldo_base_legal), versionando '
  'el salario vía fn_set_salario. Devuelve una fila por persona modificada con sus montos '
  'anteriores, para poder deshacer. NO la llama la migración: bajar las bases sin la '
  'movilidad, la educación y el bono encendidos paga de menos.';

grant execute on function fn_fijar_base_declarada(text, numeric, date, uuid[]) to authenticated;
revoke execute on function fn_fijar_base_declarada(text, numeric, date, uuid[]) from public, anon;
