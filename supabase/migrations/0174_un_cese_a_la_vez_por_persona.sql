-- ============================================================================
-- 0174 — Un cese a la vez por persona
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que dos ceses de la MISMA persona lanzados en el mismo instante no puedan
--      pasar los dos: el segundo espera al primero, ve que ya está inactiva y
--      falla con el mensaje de siempre ("Esa persona ya está inactiva (cesó
--      el …)"). Hoy los dos pasan.
--   2. Que `personas.fecha_cese` y el cierre de sus tramos de salario y horario
--      lleven SIEMPRE la misma fecha. Hoy pueden quedar con dos fechas distintas
--      sin que nada falle.
-- ASUME: la 0086, que creó `fn_cesar_persona` y es su única definición vigente
--   (comprobado con `./scripts/donde-vive.sh fn_cesar_persona`).
--
-- EL DEFECTO. La 0086 lee la persona sin candado:
--     select * into v_p from personas where id = p_persona_id;
--     if v_p.estado <> 'activo' then raise exception ...
-- Entre esa lectura y el `update personas` del final pasan cinco comprobaciones
-- y dos updates. En ese hueco cabe otra llamada. Con dos ceses simultáneos —dos
-- clics, o un clic y un reintento del navegador— pasa esto:
--
--   A lee: activo. B lee: activo. Las dos siguen.
--   A cierra sus tramos con SU fecha:
--       update asignaciones_salario set vigente_hasta = <fecha de A>
--        where persona_id = … and vigente_hasta is null
--   B corre el mismo update y ya no encuentra tramos abiertos: actualiza CERO
--   filas y no se entera, porque un `update 0` no es un error.
--   B escribe SU fecha en personas.fecha_cese, que es la que queda.
--
-- Resultado: `fecha_cese` dice una fecha y el salario terminó en otra. Ninguna
-- excepción, ningún constraint violado, nada en los registros. De `fecha_cese`
-- viven `fn_grati_trunca`, `fn_cts_trunca` y `fn_vacaciones_truncas` (0129): la
-- liquidación se calcularía sobre un día en que esa persona, según sus propios
-- tramos, ya no tenía salario vigente. Es plata mal pagada a una persona real,
-- y se ve exactamente igual que un cálculo bueno.
--
-- POR QUÉ `for update` Y NO OTRA COSA. Se descartaron tres alternativas:
--
--   · Un índice único parcial que impida dos ceses. No existe tal cosa: el cese
--     no crea una fila, cambia una columna de una fila que ya está ahí.
--   · Un CHECK o un disparador que compare la fecha contra los tramos. Llegaría
--     tarde y al revés: cuando B escribe su fecha, los tramos YA están cerrados
--     con la de A, así que el disparador solo podría rechazar a B por un dato
--     que A dejó válido. Además convierte una carrera en un error de negocio
--     confuso para quien está en la pantalla.
--   · `advisory lock` sobre el id de la persona. Funciona, pero es un candado
--     que vive fuera de la tabla: nadie que lea `personas` se entera de que
--     existe, y hay que acordarse de tomarlo en cada función futura que toque
--     un cese. El candado de fila lo toma Postgres y lo respeta todo el mundo.
--
-- `for update` es además el candado MÁS BARATO posible aquí: bloquea una fila,
-- por el tiempo que dura una transacción de ~6 sentencias, y solo a quien quiera
-- tocar ESA persona. Cesar a dos personas distintas a la vez sigue sin esperar.
-- Con ~30 integrantes y un puñado de ceses al año, la contención es cero.
--
-- CÓMO SE COMPORTA EL SEGUNDO. En `read committed` —el nivel que usa PostgREST,
-- y por tanto la pantalla— el `for update` de B espera a que A termine y VUELVE
-- A LEER la fila ya modificada. Por eso B ve `estado = 'inactivo'` y sale por la
-- excepción que ya existía: no hubo que inventar un mensaje nuevo. Si A falla y
-- deshace, B toma el candado y cesa normalmente; el candado no deja a nadie sin
-- poder cesar, solo ordena la fila.
--
-- SE ROMPE SI alguien vuelve a escribir un `update personas set estado =
-- 'inactivo'` por fuera de esta función. El candado protege a esta función de
-- sí misma, no a la tabla de todo el mundo. Hoy no queda ninguno de esos updates
-- —la pantalla de Equipo dejó de hacerlo—, y el constraint `personas_cese_
-- coherente` (0086) frena al que lo intente sin fecha, pero no al que la ponga.
--
-- QUÉ NO TOCA. El resto del cuerpo es idéntico al de la 0086, palabra por
-- palabra: las mismas validaciones, en el mismo orden, con los mismos mensajes.
-- La única diferencia entre las dos versiones es `for update` al final de la
-- línea 118. `fn_reactivar_persona` no necesita candado: su `update … where
-- estado = 'inactivo'` ya es atómico —Postgres re-evalúa ese `where` contra la
-- fila fresca al soltarse el bloqueo— y por eso el `if not found` funciona.
--
-- REVERTIR: correr el bloque `create or replace function fn_cesar_persona` tal
-- como está en `supabase/migrations/0086_fecha_de_cese.sql` (líneas 105-158) y
-- borrar la fila 174 de `migraciones_aplicadas`. No hay datos que deshacer: esta
-- migración no escribe una sola fila.
-- ============================================================================

create or replace function fn_cesar_persona(
  p_persona_id uuid,
  p_fecha_cese date,
  p_motivo text,
  p_tipo_vinculo text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_p personas%rowtype; v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un cese.';
  end if;

  -- `for update` es lo único que cambia respecto de la 0086. Toma el candado de
  -- la fila ANTES de mirar el estado, así que un segundo cese simultáneo espera
  -- aquí, relee la fila ya cesada y sale por la excepción de abajo.
  select * into v_p from personas where id = p_persona_id for update;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva (cesó el %).', to_char(v_p.fecha_cese, 'DD/MM/YYYY');
  end if;

  -- La fecha tiene que ser posible.
  if p_fecha_cese > v_hoy then
    raise exception 'El último día trabajado no puede ser futuro (pusiste %).', to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;
  if p_fecha_cese < v_p.fecha_ingreso then
    raise exception 'El último día trabajado (%) no puede ser anterior a su ingreso (%).',
      to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_p.fecha_ingreso, 'DD/MM/YYYY');
  end if;

  -- No se cesa dentro de un periodo ya pagado: eso cambiaría el cálculo de una
  -- planilla cerrada. Mismo criterio que fn_set_fecha_ingreso (0037), acotado a
  -- esta persona para no congelar al equipo entero.
  if exists (select 1 from periodos_planilla pp
              where pp.estado = 'pagado'
                and p_fecha_cese between pp.fecha_ini and pp.fecha_fin) then
    raise exception 'El % cae dentro de un periodo de planilla ya PAGADO. Reabre ese periodo primero (queda rastro) o corrige la fecha.',
      to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;

  -- Sus tramos se cierran. Hoy quedan abiertos para siempre y eso hace que un
  -- salario "vigente" siga apareciendo años después de que la persona se fue.
  update asignaciones_salario set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;
  update horarios_asignados  set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;

  update personas
     set estado = 'inactivo',
         fecha_cese = p_fecha_cese,
         motivo_cese = p_motivo,
         tipo_vinculo = coalesce(p_tipo_vinculo, tipo_vinculo),
         fecha_estado_cambio = now()
   where id = p_persona_id;
end;
$$;

-- Se repiten aunque `create or replace` conserva los permisos: si alguna vez la
-- función se recrea desde cero, nace cerrada igual que la dejó la 0076.
grant  execute on function fn_cesar_persona(uuid, date, text, text) to authenticated;
revoke execute on function fn_cesar_persona(uuid, date, text, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (174, 'un_cese_a_la_vez_por_persona')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- Comprobación en el acto: un `create or replace` que no llega a aplicarse deja
-- la función anterior en pie y no falla, así que aquí se le pregunta a Postgres
-- por la definición que quedó VIVA en vez de confiar en que la sentencia corrió.
do $mig$
declare v_tiene boolean;
begin
  select bool_or(prosrc like '%for update%') into v_tiene
    from pg_proc where proname = 'fn_cesar_persona';
  if v_tiene is not true then
    raise exception '0174 · el candado NO quedo en la definicion viva de fn_cesar_persona. Revisa la salida de arriba antes de dar esto por aplicado.';
  end if;
  raise notice '0174 · candado puesto: dos ceses simultaneos de la misma persona ya no pasan los dos.';
  raise notice '0174 · no cambia ningun calculo y no escribe una sola fila de datos.';
end $mig$;
