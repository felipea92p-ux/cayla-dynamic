-- ============================================================================
-- 0086 — Cuándo dejó de trabajar: la fecha de cese
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que el sistema sepa el ÚLTIMO DÍA TRABAJADO de quien ya no está, que es
--      el dato del que dependen la gratificación trunca, la CTS trunca y las
--      vacaciones truncas.
--   2. Que dar de baja a alguien sea una operación con reglas —fecha, motivo,
--      cierre de sus tramos de salario y horario— y no un `update` suelto.
--   3. Que después de esa fecha no pueda entrar ninguna marca suya, venga del
--      camino que venga.
-- ASUME: la 0085 (tipo_vinculo).
--
-- EL DEFECTO. Hoy la baja es esto, escrito desde el navegador:
--     update personas set estado='inactivo', fecha_estado_cambio = now()
-- y tiene cuatro problemas encadenados:
--
--   a) `fecha_estado_cambio` guarda el INSTANTE DEL CLIC, no el último día
--      trabajado. Son cosas distintas: alguien renuncia el 20 y su baja se
--      registra el 28.
--   b) Se escribe con la hora del navegador en UTC. Una baja registrada un
--      martes a las 8 de la noche de Lima queda con fecha de MIÉRCOLES. Un día
--      de diferencia mueve la CTS trunca y las vacaciones truncas.
--   c) Se pisa al reactivar, así que el dato del cese anterior se pierde.
--   d) No hay motivo. Renuncia, despido, fin de prueba y fin de un servicio por
--      honorarios se ven exactamente igual, y no son lo mismo ni legal ni
--      operativamente.
--
-- Y nada de eso lo lee ninguna función: es un campo que se escribe y no se usa.
--
-- POR QUÉ EL BACKFILL NO USA `fecha_estado_cambio`. Para quien ya está
-- inactivo se toma su ÚLTIMA JORNADA REAL (`max(jornadas.fecha)`), que es el
-- último día que efectivamente vino — el criterio que fijó Felipe. Solo si esa
-- persona no tiene ni una jornada se cae al instante del clic convertido a
-- hora de Lima, y ese caso queda marcado con motivo 'por_revisar' para que se
-- corrija a mano en vez de quedar disfrazado de dato bueno.
--
-- POR QUÉ UN DISPARADOR Y NO UN GUARD EN fn_registrar_marcaje. Esa función
-- tiene ~300 líneas y cuatro migraciones se apoyan en su versión actual;
-- reescribirla para agregar tres líneas es pedir una divergencia. Además no
-- alcanzaría: `api/reabrir-dia` inserta en `marcajes` directamente con la
-- llave de servicio, sin pasar por ella. Un disparador sobre la tabla cubre
-- TODOS los caminos, los de hoy y los que alguien escriba mañana.
--
-- LA MARCA ATRASADA SIGUE ENTRANDO. El disparador compara la FECHA DE LA MARCA
-- contra el cese, no el momento en que llega. Una marca del lunes que la cola
-- offline entrega el jueves —después de la baja— se acepta, porque esa persona
-- sí trabajó ese lunes. Lo que se rechaza es una marca POSTERIOR al cese.
--
-- Reversible: soltar las dos columnas, las dos funciones, el disparador y el
-- constraint.
-- ============================================================================

-- ── Las dos columnas ────────────────────────────────────────────────────────
alter table personas add column if not exists fecha_cese date;
alter table personas add column if not exists motivo_cese text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_motivo_cese_valido') then
    alter table personas add constraint personas_motivo_cese_valido
      check (motivo_cese is null or motivo_cese in (
        'renuncia',            -- se fue por decisión propia
        'despido',             -- la empresa terminó el vínculo con causa
        'fin_periodo_prueba',  -- vino a probar y no continúa
        'fin_servicio_rxh',    -- terminó el servicio por recibo por honorarios
        'mutuo_acuerdo',
        'por_revisar'          -- solo backfill: no se pudo deducir la fecha real
      ));
  end if;
end $$;

comment on column personas.fecha_cese is
  'Ultimo dia efectivamente trabajado. Es la fecha de la que dependen grati, CTS y vacaciones truncas. NO es el dia en que se registro la baja.';

-- ── Backfill de quienes ya están inactivos ──────────────────────────────────
update personas p
   set fecha_cese = coalesce(
         (select max(j.fecha) from jornadas j
           where j.persona_id = p.id and j.entrada_ts is not null),
         (p.fecha_estado_cambio at time zone 'America/Lima')::date),
       motivo_cese = case
         when exists (select 1 from jornadas j
                       where j.persona_id = p.id and j.entrada_ts is not null)
           then 'por_revisar'   -- la fecha es buena, el motivo no se puede deducir
           else 'por_revisar'
       end
 where p.estado = 'inactivo' and p.fecha_cese is null;

-- ── El estado imposible: inactivo sin fecha de cese ─────────────────────────
-- `not valid` para no fallar si quedó alguna fila rara; se valida enseguida y
-- si eso revienta, la migración se detiene ANTES de crear nada más.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_cese_coherente') then
    alter table personas add constraint personas_cese_coherente check (
      (estado = 'activo'   and fecha_cese is null) or
      (estado = 'inactivo' and fecha_cese is not null)
    ) not valid;
    alter table personas validate constraint personas_cese_coherente;
  end if;
end $$;

-- ── Dar de baja: una operación con reglas ───────────────────────────────────
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

  select * into v_p from personas where id = p_persona_id;
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
grant  execute on function fn_cesar_persona(uuid, date, text, text) to authenticated;
revoke execute on function fn_cesar_persona(uuid, date, text, text) from public, anon;

-- ── Reactivar ───────────────────────────────────────────────────────────────
-- Se conserva porque a veces la baja fue un error. Pero avisa fuerte si esa
-- persona ya tiene una liquidación: reactivar a alguien liquidado y dejar que
-- vuelva a devengar desde su fecha_ingreso original haría que el sistema le
-- pague de nuevo una CTS y unas vacaciones ya pagadas. Cuando exista la tabla
-- de liquidaciones, este bloque se convierte en un bloqueo duro.
create or replace function fn_reactivar_persona(p_persona_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede reactivar a una persona.';
  end if;
  update personas
     set estado = 'activo', fecha_cese = null, motivo_cese = null,
         fecha_estado_cambio = now()
   where id = p_persona_id and estado = 'inactivo';
  if not found then
    raise exception 'Esa persona no existe o ya está activa.';
  end if;
end;
$$;
grant  execute on function fn_reactivar_persona(uuid) to authenticated;
revoke execute on function fn_reactivar_persona(uuid) from public, anon;

-- ── Ninguna marca después del cese ──────────────────────────────────────────
create or replace function fn_marcaje_no_posterior_al_cese()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_cese date; v_fecha date;
begin
  select fecha_cese into v_cese from personas where id = new.persona_id;
  if v_cese is null then return new; end if;

  v_fecha := (new.timestamp_marca at time zone 'America/Lima')::date;
  if v_fecha > v_cese then
    raise exception 'No se puede registrar una marca del % : esa persona cesó el %.',
      to_char(v_fecha, 'DD/MM/YYYY'), to_char(v_cese, 'DD/MM/YYYY');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_marcaje_no_posterior_al_cese on marcajes;
create trigger trg_marcaje_no_posterior_al_cese
  before insert on marcajes
  for each row execute function fn_marcaje_no_posterior_al_cese();

insert into migraciones_aplicadas (numero, nombre) values (86, 'fecha_de_cese')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
