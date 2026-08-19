-- ============================================================================
-- 0271 — La base declarada dice desde qué contrato se disparó.
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_fijar_base_declarada` (0128) acepte un `p_nota_extra` opcional que
--   se anexa a la nota que ya escribe en `asignaciones_salario` vía
--   `fn_set_salario`. Sin este parámetro, la nota es fija y no dice DESDE
--   DÓNDE se disparó el cambio — y con el generador de contratos (2026-08-18)
--   la base de cada persona se va a bajar de a una, al momento de renovar su
--   contrato, no de a un rango entero de una vez. Sin este dato, reconstruir
--   "qué contrato causó qué baja de sueldo" exige cruzar por fecha a ojo.
--
-- POR QUÉ ASÍ Y NO DE OTRA FORMA
--   No se agrega una tabla ni una columna nueva: `asignaciones_salario.nota`
--   ya es el lugar donde este tipo de rastro vive (ver su propio historial de
--   vigencias). Concatenar un texto ahí es coherente con cómo ya se audita
--   cualquier otro cambio de salario en este sistema.
--
-- QUÉ ASUME
--   · `fn_fijar_base_declarada(text, numeric, date, uuid[])` (0128), única
--     definición existente — no fue tocada desde que se creó.
--   · `fn_set_salario` (0019) sigue recibiendo la nota como texto libre.
--
-- COMPATIBILIDAD
--   `p_nota_extra` tiene default `null`: cualquier llamada existente que use
--   4 argumentos posicionales sigue funcionando igual, nota incluida.
--
--   Y por qué el `drop function` de abajo NO es opcional: Postgres identifica
--   una función por su nombre Y su lista de TIPOS de parámetros, no por si
--   tienen default. `create or replace` con un parámetro nuevo al final NO
--   reemplaza la función existente — crea una SEGUNDA función sobrecargada
--   (misma razón por la que la 0161 usa `drop` para `fn_documentos_tablero`
--   al agregarle una columna, aunque ahí el problema es el tipo de retorno y
--   acá la lista de parámetros). Comprobado contra Postgres local: sin el
--   `drop`, quedaban las DOS firmas a la vez —la de 4 argumentos con el
--   cuerpo viejo, sin el rastro del contrato, y la de 5 con el cuerpo
--   nuevo— y una llamada con 4 argumentos habría seguido cayendo en la
--   vieja en silencio.
--
-- MD5 DE PARTIDA (a confirmar contra producción antes de pegar)
--   Local, contra el cuerpo de la 0128 sin modificar: 053869326ca87177a32fb772bc64442e
--   (`./scripts/donde-vive.sh fn_fijar_base_declarada`, 2026-08-18). Esta
--   migración solo se pega si el SQL Editor de producción devuelve el MISMO
--   valor para:
--     select md5(prosrc) from pg_proc where proname = 'fn_fijar_base_declarada';
--   Si no coincide, hay que medir la diferencia (posición del primer
--   substring que difiere) antes de seguir — nunca reescribir a ciegas.
--
-- CÓMO SE REVIERTE
--   Volver a pegar el cuerpo exacto de la 0128 con
--   `create or replace function fn_fijar_base_declarada(text, numeric, date, uuid[])`
--   (mismos 4 parámetros, sin `p_nota_extra`) restaura el comportamiento
--   anterior byte por byte. No hay dato nuevo que limpiar: `p_nota_extra` no
--   crea columna ni tabla, solo se concatena al texto de una nota existente.
-- ============================================================================

drop function if exists fn_fijar_base_declarada(text, numeric, date, uuid[]);

create or replace function fn_fijar_base_declarada(
  p_rango          text,
  p_monto          numeric,
  p_vigente_desde  date,
  p_omitir         uuid[] default '{}',
  p_nota_extra     text default null
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
        || coalesce(' | ' || nullif(trim(p_nota_extra), ''), '')
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

comment on function fn_fijar_base_declarada(text, numeric, date, uuid[], text) is
  'Baja la base declarada de un rango en LOS DOS campos que intervienen en el pago '
  '(asignaciones_salario.salario_mensual_soles y personas.sueldo_base_legal), versionando '
  'el salario vía fn_set_salario. p_nota_extra (0271) se anexa a la nota para dejar '
  'rastro de qué disparó el cambio (ej. qué contrato). Devuelve una fila por persona '
  'modificada con sus montos anteriores, para poder deshacer.';

grant execute on function fn_fijar_base_declarada(text, numeric, date, uuid[], text) to authenticated;
revoke execute on function fn_fijar_base_declarada(text, numeric, date, uuid[], text) from public, anon;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (271, 'la_base_declarada_dice_desde_que_contrato_se_disparo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
