-- ============================================================================
-- 0517 — La persona ve cómo va con sus tardanzas este mes
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que una integrante pueda preguntar, desde «Lo mío», cuántas tardanzas le
-- cuenta el sistema este mes y cuántas harían falta para el siguiente paso del
-- Reglamento, ANTES de que exista un documento. `fn_mi_cuenta_de_tardanzas`
-- devuelve esas dos cifras y el nombre del paso, solo de quien tiene la sesión.
--
-- Es el «cómo vas» de la pestaña Disciplina: el sistema avisa y previene, no
-- sanciona (RIT 52.9 y 52.10). Si una persona se entera el día 10 de que lleva
-- dos tardanzas, todavía puede pedir que se justifique la que corresponda
-- (RIT 18.2) o cuidar la tercera. Si se entera por la amonestación, ya no.
--
-- ── DE QUIÉN ES LA DECISIÓN ─────────────────────────────────────────────────
--
-- De la usuaria, el 2026-10-06: sí mostrarlo, con tono neutro. Y la condición
-- con la que se le planteó: que el número salga de la MISMA cuenta que usa la
-- pantalla de Disciplina, para que lo que ve la persona y lo que ve DO no
-- discrepen.
--
-- ── DECIDÍ / DESCARTÉ / SE ROMPE SI ─────────────────────────────────────────
--
-- DECIDÍ: una función propia para la persona, que repite la cuenta del mes de
--   `fn_tardanzas_resumen` (0311) —las mismas cinco condiciones— y toma el
--   escalón de `fn_tardanza_escalon_al`, la misma función que usa Disciplina.
--   Una prueba (412) compara su resultado con el de `fn_tardanzas_resumen` en
--   seis casos.
-- DESCARTÉ: sacar la cuenta a una función compartida y reescribir
--   `fn_tardanzas_resumen`. Es la función de la que cuelga la pantalla de
--   Disciplina y la que decide qué se le documenta a quién; en este repo
--   reescribir las que tocan sanciones es donde ya se revirtieron cosas en
--   silencio (la 0261). Dos copias de la cuenta con una prueba que las ata son
--   un riesgo menor que una reescritura sin necesidad.
-- SE ROMPE SI: alguien cambia una regla de la cuenta —por ejemplo, qué
--   tardanzas se justifican— en `fn_tardanzas_resumen` y no aquí. La prueba 412
--   falla ese mismo día: es el freno, y por eso está en el repositorio.
--
-- ── POR QUÉ NO USAR `fn_tardanzas_resumen` DIRECTAMENTE ─────────────────────
--
-- Filtra por rol (DO ve todo, la líder su sede): a una integrante le devuelve
-- cero filas. Y además descarta a quien está lejos del umbral —tiene que haber
-- llegado a «mínimo menos uno»—, justo a quien más le interesa saber que va
-- bien. Y `fn_tardanza_escalon` está cerrada a las sesiones con login (0311):
-- nadie puede preguntar el escalón de otra persona.
--
-- ── QUÉ MUESTRA Y QUÉ CALLA ─────────────────────────────────────────────────
--
--   · A quien no se le mide la puntualidad —por honorarios, practicante, con
--     sueldo fijo, inactiva— no se le muestra nada: no hay cuenta (devuelve
--     null) y la pantalla oculta el recuadro, en vez de decirle «llevas 0».
--   · A quien tiene una imputación de cargos abierta no se le muestra un
--     número: hay un procedimiento en curso que decide DO, no un contador
--     (devuelve null).
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que la 0311 es la versión vigente de `fn_tardanzas_resumen` y de
--     `fn_tardanza_escalon_al` — verificado en producción por la prueba de las
--     funciones de la 0510 (idénticas al repo el 2026-10-06).
--   · Que `p_al` nulo es hoy; con una fecha, la cuenta es la de ese mes (así se
--     prueba sin depender del día en que corra el CI).
--
-- No reescribe ninguna función existente: no hay md5 de partida que declarar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop function if exists fn_mi_cuenta_de_tardanzas(date);
-- La pantalla oculta el recuadro cuando no la encuentra.
-- ============================================================================

create or replace function fn_mi_cuenta_de_tardanzas(p_al date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_yo  uuid := fn_persona_actual_id();
  v_al  date := coalesce(p_al, fn_hoy_lima());
  p     personas%rowtype;
  esc   record;
  v_n   int;
begin
  if v_yo is null then return null; end if;

  select * into p from personas where id = v_yo;
  -- A quien no se le mide la puntualidad no se le muestra cuenta: la misma
  -- condición con la que `fn_tardanzas_resumen` decide a quién medir.
  if p.estado <> 'activo' or p.en_planilla is not true or p.sueldo_fijo is true then
    return null;
  end if;

  select * into esc from fn_tardanza_escalon_al(v_yo, p_al);
  -- Imputación abierta: lo decide DO, no un contador.
  if esc.bloqueado is true then return null; end if;

  -- LA CUENTA DEL MES. Las mismas condiciones que el CTE `conteo` de
  -- `fn_tardanzas_resumen` (0311); si cambia una, cambia la otra, y la prueba
  -- 412 lo comprueba.
  select count(distinct j.fecha) into v_n
    from jornadas j
   where j.persona_id = v_yo
     and j.fecha >= date_trunc('month', v_al)::date
     and j.fecha <= v_al
     and (esc.corte is null or j.fecha > esc.corte)        -- no cuenta lo ya sancionado
     and not fn_tardanza_ya_documentada(v_yo, j.fecha)     -- ni lo citado en un documento
     and fn_tardanza_es_medible(j.minutos_tarde)           -- ni lo que pasa de tres horas
     and j.minutos_tarde is not null and j.minutos_tarde > 0
     and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = v_yo and tj.fecha = j.fecha);

  return jsonb_build_object(
    'mes', date_trunc('month', v_al)::date,
    'tardanzas_mes', coalesce(v_n, 0),
    'minimo', esc.minimo,
    'nivel_siguiente', esc.nivel_siguiente);
end;
$$;

grant execute on function fn_mi_cuenta_de_tardanzas(date) to authenticated;
revoke execute on function fn_mi_cuenta_de_tardanzas(date) from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (517, 'la_persona_ve_como_va_con_sus_tardanzas')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
