-- ============================================================================
-- 0582_lo_comunicado_no_cambia_y_el_descargo_se_lee_antes.sql
-- ============================================================================
-- QUÉ PROMETE
--   Dos cosas que la 0581 dejó abiertas y que una revisión adversarial
--   reprodujo en el Postgres local (2026-11-03), cada una capaz de dejar
--   anulable una sanción:
--
--   1. LO QUE SE LE COMUNICÓ NO CAMBIA DESPUÉS. Comunicados los cargos, un
--      borrador ya no admite cambiar sus hechos, su falta, su causal, su
--      periodo ni su nivel. Antes se podía: `fn_expediente_editar_borrador`
--      (0059) o `fn_expediente_elevar_a_suspension` (0567) cambiaban la fila y
--      la comunicación que ella YA había confirmado en su Info pasaba a decir
--      otra cosa, con la misma constancia y el mismo plazo. El 55.2 exige
--      comunicar «los hechos… con sus fechas, su calificación… y la sanción
--      que podría corresponder», y el 52.7 que no se sancione con una
--      calificación distinta de la comunicada.
--
--   2. EL DESCARGO SE LEE ANTES DE DECIDIR. Un descargo no se valora mientras
--      corre su plazo, ni como «no presentó descargo» cuando ella sí lo
--      escribió en su Info; y no se firma un borrador valorado así. Antes la
--      base dejaba las tres cosas: el único freno era el reloj del navegador
--      de quien tramita (`etapaDelBorrador`), y una pestaña abierta desde el
--      día de la comunicación mostraba «no presentó descargo» días después de
--      que ella lo escribiera. El 55.2 dice «La Empresa evalúa el descargo
--      antes de decidir».
--
-- POR QUÉ TRIGGERS Y NO REESCRIBIR LAS FUNCIONES
--   Los tres caminos que tocan esas columnas son tres funciones con historia
--   (0059, 0212, 0567, y la firma en la 0455). Un trigger BEFORE UPDATE las
--   cubre a todas, y a la que venga, sin copiar ningún cuerpo: no hay md5 de
--   partida que pedir ni versión vigente que se pueda revertir.
--
--   No frena SIN SESIÓN (`auth.uid() is null`): el SQL Editor y las
--   migraciones quedan como la salida para una corrección a mano, que es lo
--   que la casa ya hace en otras guardas. Desde la app —donde siempre hay
--   sesión, también dentro de las funciones `security definer`— frena siempre.
--
-- QUÉ NO HACE
--   · No toca la suspensión (días y fechas): la comunicación dice el rango del
--     escalón, no los días, y esos se fijan después del descargo.
--   · No toca anular ni firmar en sí (salvo el caso de «sin descargo» con un
--     descargo escrito).
--   · No cambia nada de lo que ya está guardado.
--
-- SI ALGO SE COMUNICÓ MAL
--   Se anula el borrador y se genera otro: así se le comunica de nuevo, con su
--   propio plazo. Es lo que dice el mensaje del freno.
--
-- QUÉ ASUME
--   Que la 0581 está pegada (`descargos_presentados`). Se comprueba abajo.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_expediente_lo_comunicado_no_cambia on expediente_disciplinario;
--   drop trigger if exists trg_expediente_descargo_se_lee_antes on expediente_disciplinario;
--   drop function if exists fn_expediente_lo_comunicado_no_cambia();
--   drop function if exists fn_expediente_descargo_se_lee_antes();
-- ============================================================================

do $$
begin
  if not exists (select 1 from migraciones_aplicadas where numero = 581) then
    raise exception 'Falta la 0581 (los cargos en la Info de la persona). Pégala primero.';
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · Lo comunicado no cambia
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_expediente_lo_comunicado_no_cambia()
returns trigger language plpgsql set search_path = public as $$
begin
  -- Sin sesión (SQL Editor, migración): la salida para corregir a mano.
  if auth.uid() is null then return new; end if;

  if old.estado = 'borrador' and new.estado = 'borrador'
     and old.cargos_comunicados_at is not null
     and (new.hechos            is distinct from old.hechos
       or new.nivel             is distinct from old.nivel
       or new.tipo_causal       is distinct from old.tipo_causal
       or new.periodo_desde     is distinct from old.periodo_desde
       or new.periodo_hasta     is distinct from old.periodo_hasta
       or new.falta_rit_version is distinct from old.falta_rit_version
       or new.falta_numeral     is distinct from old.falta_numeral
       or new.falta_literal     is distinct from old.falta_literal) then
    raise exception 'Ya se le comunicaron estos cargos el % y lo que se le comunicó no se cambia. Para corregir los hechos, la falta o el nivel, anula este borrador y genera otro: así se le comunican de nuevo, con su propio plazo (RIT 55.2 y 52.7).',
      to_char(old.cargos_comunicados_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI');
  end if;
  return new;
end;
$$;

create or replace trigger trg_expediente_lo_comunicado_no_cambia
  before update on expediente_disciplinario
  for each row execute function fn_expediente_lo_comunicado_no_cambia();


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · El descargo se lee antes de decidir
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_expediente_descargo_se_lee_antes()
returns trigger language plpgsql set search_path = public as $$
declare
  v_escrito boolean := exists (select 1 from descargos_presentados where expediente_id = new.id);
begin
  if auth.uid() is null then return new; end if;

  -- Valorar (o cambiar la valoración).
  if new.descargo_acogido is not null
     and (new.descargo_acogido is distinct from old.descargo_acogido
          or new.descargo_valoracion is distinct from old.descargo_valoracion) then
    if new.descargo_vence_at is not null and now() <= new.descargo_vence_at then
      raise exception 'Su plazo de descargo vence el %: se valora después, cuando ya pudo decir todo lo que quería (RIT 55.2).',
        to_char(new.descargo_vence_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI');
    end if;
    if new.descargo_acogido = 'sin_descargo' and v_escrito then
      raise exception 'Presentó su descargo por escrito en su Info: no se puede valorar como «no presentó descargo». Léelo en el caso y valóralo (RIT 19.3).';
    end if;
  end if;

  -- Firmar algo que quedó valorado como «sin descargo» con un descargo escrito.
  if old.estado = 'borrador' and new.estado = 'firmado'
     and new.descargo_acogido = 'sin_descargo' and v_escrito then
    raise exception 'Este borrador dice que no presentó descargo, pero lo presentó por escrito en su Info. Vuelve a valorarlo antes de firmar (RIT 55.2).';
  end if;
  return new;
end;
$$;

create or replace trigger trg_expediente_descargo_se_lee_antes
  before update on expediente_disciplinario
  for each row execute function fn_expediente_descargo_se_lee_antes();


insert into migraciones_aplicadas (numero, nombre) values (582, 'lo_comunicado_no_cambia_y_el_descargo_se_lee_antes')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
-- Tienen que salir los dos triggers, y el registro con su nombre.
select t.tgname, (select nombre from migraciones_aplicadas where numero = 582) as registro
  from pg_trigger t
 where t.tgrelid = 'expediente_disciplinario'::regclass
   and t.tgname in ('trg_expediente_lo_comunicado_no_cambia', 'trg_expediente_descargo_se_lee_antes')
 order by t.tgname;
