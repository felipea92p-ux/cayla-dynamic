-- ############################################################################
-- ####  ESTE ES EL ARCHIVO QUE SE PEGA EN EL SQL EDITOR DE SUPABASE.      ####
-- ############################################################################
--
-- aplicar_pendientes_0138_0155.sql — lo último que le falta a producción
--
-- CÓMO SE USA
--   1. Copia TODO y pégalo en el SQL Editor.  2. Run.
--   3. Abajo sale un cuadro. Todas las filas tienen que decir OK, y la última
--      te dice cuántas filas tiene el libro de desembolsos.
--
-- QUÉ TRAE, y por qué faltaba
--
--   0138 · UN PERIODO PAGADO NO CAMBIA DE HORAS POR SU CUENTA.
--          Medido el 2026-08-04: un día 16/06 pagado con 9.00 h pasaba a 8.00 h
--          cuando la cola offline de una Mac mini subía tarde el par de marcas
--          del almuerzo. La marca real SIEMPRE entra —nunca se pierde el
--          registro de que alguien estuvo— pero el número ya pagado se queda
--          quieto hasta que alguien revierta el pago a propósito.
--          Se escribió el 4 de agosto y nunca se pegó acá.
--
--   0155 · EL LIBRO DE DESEMBOLSOS, DESCRITO EN EL REPOSITORIO.
--          En producción esta tabla YA existe y la 0153 ya la protegió, así que
--          acá casi todo es no-op. Se pega para que el registro de migraciones
--          diga la verdad y para dejarle su comentario explicativo.
--
-- LAS DOS SON IDEMPOTENTES. Correrlo dos veces no hace daño: comprobado contra
-- el Postgres local aplicando la 0155 sobre una tabla que ya existía.
--
-- QUÉ **NO** HACE: no borra, no mueve ni cambia una sola fila de datos.
-- ############################################################################

begin;

-- ============================================================================
-- 0138 — Un periodo pagado no cambia de horas por su cuenta
-- ============================================================================
--
-- QUÉ PROMETE
--   Ninguna jornada de un día que cae dentro de un periodo PAGADO se vuelve a
--   escribir. El número de horas con el que se pagó un día se queda quieto
--   hasta que alguien revierta el pago a propósito.
--
-- QUÉ ASUME
--   · `periodos_planilla` no se solapa: una fecha pertenece a lo sumo a un
--     periodo.
--   · Revertir un pago se hace por `fn_revertir_pago`, con motivo obligatorio
--     (0095). Ese es el único camino para volver a mover un día pagado.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--   Medido contra el Postgres local, en BEGIN … ROLLBACK, el 2026-08-04:
--   un día 16/06 pagado con 9.00 h pasaba a 8.00 h cuando la cola offline
--   subía tarde el par de marcas del almuerzo. La foto del pago (0096) sostenía
--   el monto, así que nadie cobraba de menos — pero `jornadas` dejaba de
--   coincidir con lo que se pagó, y esa diferencia no la explicaba nadie.
--
--   El candado NO va en `fn_registrar_marcaje`. Once funciones llaman al
--   recálculo (los dos triggers de marcajes, el auto-cierre, las cinco de
--   horarios y turnos, reabrir día y el bono de puntualidad). Poner la regla en
--   la puerta de entrada la deja fuera de las otras diez, y ese es exactamente
--   el error que este repositorio ya pagó tres veces: la misma regla escrita en
--   dos sitios y una corrección que arregla solo uno. Va en el único sitio por
--   donde pasan todas.
--
--   Y sale en silencio en vez de lanzar excepción porque quien la ejecuta es un
--   trigger de INSERT: una excepción haría que la terminal descartara la marca
--   tras seis reintentos. La marca real siempre entra. Lo que no se mueve es el
--   número ya pagado.
--
-- DE QUÉ VERSIÓN PARTE, Y POR QUÉ IMPORTA
--   Del cuerpo que dejó la **0081** (marcas que se anulan, no se borran), que es
--   el vigente — comprobado byte a byte contra `pg_get_functiondef` del Postgres
--   local. La búsqueda ingenua encuentra la 0013, 0014, 0016 y 0017 y **no** la
--   0081, porque esta la escribe como `CREATE OR REPLACE FUNCTION public.…` en
--   mayúsculas. Partir de la 0017 —64 migraciones atrás— revierte en silencio
--   toda la lógica de marcas anuladas. Las pruebas 81 y 82 lo cazan; si tocas
--   esta función, córrelas.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar la definición de `fn_recalcular_jornada` que trae la
--   migración 0081, que es esta misma sin el bloque marcado «CANDADO DE PERIODO
--   PAGADO». No hay cambio de datos ni de esquema que deshacer.
--
-- POR QUÉ ES LA 0138 Y NO LA 0136
--   Los tres números anteriores están reclamados por trabajo que no está en
--   `main`, y por eso se saltan a propósito (la convención del repo pide
--   documentar todo salto):
--
--     0133 · no existe en ningún archivo, rama ni commit. Se saltó al crear la
--            0134 el 2026-08-04. Hueco real, sin dueño.
--     0136 · la toma `origin/educacion-con-comprobante` (commit f1b1fa7,
--            empujado a GitHub) con la pantalla de educación y su comprobante.
--     0137 · **ya no es un hueco.** Era `fn_reabrir_dia`, aplicada a mano al
--            Postgres local el 2026-08-04 a las 21:04 y nunca commiteada. Se
--            recuperó verbatim desde `pg_get_functiondef` y hoy vive en
--            `0137_reabrir_el_dia_sin_dejarlo_a_medias.sql`, con su prueba 112.
--
--   Y la 0108 sigue existiendo solo en `movilidad-supeditada-a-asistencia`, sin
--   fusionar. Los huecos que quedan (0031, 0033, 0108, 0133) no se cierran acá;
--   quedan anotados para que nadie los reutilice creyéndolos libres.
--
--   Hay además dos colisiones vivas que este archivo no causa pero que conviene
--   mirar antes de fusionar nada: `origin/cuadro-de-categorias` numera 0131 y
--   0132 con contenido distinto al que `main` llama 0131 y 0132.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_recalcular_jornada(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_marcaje record;
  v_entrada_ts timestamptz;
  v_salida_final_ts timestamptz;
  v_salida_final_origen origen_marca;
  v_salida_final_revision estado_revision;
  v_ausencia_inicio timestamptz;
  v_total_ausencia interval := interval '0';
  v_abierta_temporal boolean := false;
  v_sede_id uuid;
  v_hora_entrada_prog time;
  v_hora_salida_prog time;
  v_refri_prog int := 0;
  v_es_descanso boolean := false;
  v_hpd jsonb;
  v_hora_entrada_legacy time;
  v_hora_salida_legacy time;
  v_dow text;
  v_minutos_tarde int;
  v_minutos_temprano int;
  v_horas_prog numeric;
  v_horas_extra numeric(6,2) := 0;
  v_horas_trabajadas numeric(6,2);
  v_estado estado_jornada;
  v_hora_entrada_esperada timestamptz;
  v_hora_salida_esperada timestamptz;
  v_n_marcajes int;
begin
  -- ── CANDADO DE PERIODO PAGADO ──────────────────────────────────────────────
  -- Un día que cae dentro de un periodo con estado 'pagado' NO se vuelve a
  -- calcular. Ni por una marca que sube tarde desde la cola offline, ni porque
  -- alguien cambie un horario que abarca meses hacia atrás.
  --
  -- Se SALE en silencio en vez de lanzar excepción, y es a propósito: este
  -- cuerpo lo ejecuta un trigger sobre `marcajes`. Lanzar aquí abortaría el
  -- INSERT, la terminal reintentaría seis veces y acabaría descartando una
  -- marca REAL de una persona que sí estuvo. Perder el registro de un hecho es
  -- peor que tener un día pagado que no coincide con él: los marcajes son la
  -- fuente de verdad y son append-only. La marca entra; lo que no se mueve es
  -- el número que ya se pagó.
  --
  -- El día no queda mudo: la marca atrasada rompe la secuencia del día,
  -- fn_dia_incoherente lo sella y aparece en Correcciones. Probado en la 110.
  --
  -- El candado se levanta solo: lee el estado del periodo en cada llamada, así
  -- que revertir el pago (fn_revertir_pago, con motivo obligatorio) devuelve el
  -- recálculo sin tocar nada más.
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and p_fecha between fecha_ini and fecha_fin
  ) then
    return;
  end if;

  select count(*) into v_n_marcajes
  from marcajes
  where persona_id = p_persona_id and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
    and anulada_at is null;

  if v_n_marcajes = 0 then
    delete from jornadas where persona_id = p_persona_id and fecha = p_fecha;
    return;
  end if;

  for v_marcaje in
    select * from marcajes
    where persona_id = p_persona_id and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and anulada_at is null
    order by timestamp_marca asc
  loop
    v_sede_id := coalesce(v_sede_id, v_marcaje.sede_id);
    if v_marcaje.tipo = 'entrada' then
      v_entrada_ts := coalesce(v_entrada_ts, v_marcaje.timestamp_marca);
    elsif v_marcaje.tipo = 'salida_final' then
      v_salida_final_ts := v_marcaje.timestamp_marca;
      v_salida_final_origen := v_marcaje.origen;
      v_salida_final_revision := v_marcaje.estado_revision;
    elsif v_marcaje.tipo::text like 'salida\_%' escape '\' then
      v_ausencia_inicio := v_marcaje.timestamp_marca;
      v_abierta_temporal := true;
    elsif v_marcaje.tipo::text like 'retorno\_%' escape '\' then
      if v_abierta_temporal and v_ausencia_inicio is not null then
        v_total_ausencia := v_total_ausencia + (v_marcaje.timestamp_marca - v_ausencia_inicio);
      end if;
      v_abierta_temporal := false;
      v_ausencia_inicio := null;
    end if;
  end loop;

  -- horario programado del día: turno → horario por día (jsonb) → hora única legacy.
  v_dow := extract(dow from p_fecha)::int::text; -- 0=domingo … 6=sábado
  select hora_entrada, hora_salida, es_descanso
    into v_hora_entrada_prog, v_hora_salida_prog, v_es_descanso
  from turnos where persona_id = p_persona_id and fecha = p_fecha;
  if not found then
    select horario_por_dia, hora_entrada, hora_salida
      into v_hpd, v_hora_entrada_legacy, v_hora_salida_legacy
    from horarios_asignados
    where persona_id = p_persona_id and vigente_desde <= p_fecha
      and (vigente_hasta is null or vigente_hasta >= p_fecha)
    order by vigente_desde desc limit 1;
    if found then
      if v_hpd is not null then
        v_hora_entrada_prog := (v_hpd -> v_dow ->> 'e')::time; -- null si ese día es descanso
        v_hora_salida_prog  := (v_hpd -> v_dow ->> 's')::time;
        v_refri_prog        := coalesce((v_hpd -> v_dow ->> 'r')::int, 0);
      else
        v_hora_entrada_prog := v_hora_entrada_legacy;
        v_hora_salida_prog  := v_hora_salida_legacy;
      end if;
    end if;
  elsif v_es_descanso then
    v_hora_entrada_prog := null; -- descanso del turno: no se mide nada
    v_hora_salida_prog := null;
  end if;

  -- tardanza de entrada (SIN tolerancia, pero por MINUTO: los segundos dentro del
  -- minuto de entrada no cuentan — 07:45:00–07:45:59 es puntual, 07:46:00 es 1 min).
  v_minutos_tarde := null;
  if v_entrada_ts is not null and v_hora_entrada_prog is not null then
    v_hora_entrada_esperada := (p_fecha + v_hora_entrada_prog) at time zone 'America/Lima';
    v_minutos_tarde := greatest(0, floor(extract(epoch from (v_entrada_ts - v_hora_entrada_esperada)) / 60)::int);
    if v_minutos_tarde > 180 then v_minutos_tarde := null; end if;
  end if;

  v_horas_trabajadas := null;
  if v_entrada_ts is not null and v_salida_final_ts is not null then
    v_horas_trabajadas := round(extract(epoch from ((v_salida_final_ts - v_entrada_ts) - v_total_ausencia)) / 3600.0, 2);
  end if;

  -- salida anticipada: cerró el día antes de su hora de salida programada.
  -- Tolerancia de 15 min: dentro de 15 min de su hora no se marca (queda en 0).
  -- No se mide mientras el auto-cierre siga SIN REVISAR: esa hora la inventó el
  -- sistema y medir contra ella sería acusar con un dato falso. En cuanto una
  -- persona la confirma o la corrige, la hora es real y el día se mide entero.
  v_minutos_temprano := null;
  if v_salida_final_ts is not null and v_hora_salida_prog is not null
     and not (v_salida_final_origen = 'auto_cierre'
              and v_salida_final_revision = 'pendiente_revision') then
    v_hora_salida_esperada := (p_fecha + v_hora_salida_prog) at time zone 'America/Lima';
    v_minutos_temprano := greatest(0, round(extract(epoch from (v_hora_salida_esperada - v_salida_final_ts)) / 60)::int);
    if v_minutos_temprano > 180 then v_minutos_temprano := null; -- turno distinto / anomalía
    elsif v_minutos_temprano <= 15 then v_minutos_temprano := 0; -- dentro de la tolerancia
    end if;
  end if;

  -- tiempo adicional: trabajó más que sus horas programadas del día (neto de refrigerio).
  -- Tolerancia de 15 min (0.25 h): dentro de eso no se marca (queda en 0).
  -- Misma regla que arriba: sin revisar no se mide; revisada, sí.
  v_horas_extra := 0;
  if v_horas_trabajadas is not null and v_hora_entrada_prog is not null and v_hora_salida_prog is not null
     and not (v_salida_final_origen = 'auto_cierre'
              and v_salida_final_revision = 'pendiente_revision') then
    v_horas_prog := greatest(0, (extract(epoch from (v_hora_salida_prog - v_hora_entrada_prog)) / 3600.0) - (v_refri_prog / 60.0));
    v_horas_extra := greatest(0, round((v_horas_trabajadas - v_horas_prog)::numeric, 2));
    if v_horas_extra <= 0.25 then v_horas_extra := 0; end if; -- dentro de la tolerancia
  end if;

  if v_salida_final_ts is not null then
    if v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'pendiente_revision' then
      v_estado := 'auto_cerrada_pendiente';
    elsif v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'revisada' then
      v_estado := 'revisada';
    else
      v_estado := 'cerrada';
    end if;
  elsif v_abierta_temporal then
    v_estado := 'en_pausa';
  else
    v_estado := 'abierta';
  end if;

  insert into jornadas (
    persona_id, fecha, sede_id, entrada_ts, salida_final_ts,
    minutos_tarde, minutos_salida_temprana, horas_trabajadas, horas_extra_detectadas,
    estado, tiene_salida_no_retornada, updated_at
  ) values (
    p_persona_id, p_fecha, v_sede_id, v_entrada_ts, v_salida_final_ts,
    v_minutos_tarde, v_minutos_temprano, v_horas_trabajadas, v_horas_extra,
    v_estado, v_abierta_temporal, now()
  )
  on conflict (persona_id, fecha) do update set
    sede_id = excluded.sede_id,
    entrada_ts = excluded.entrada_ts,
    salida_final_ts = excluded.salida_final_ts,
    minutos_tarde = excluded.minutos_tarde,
    minutos_salida_temprana = excluded.minutos_salida_temprana,
    horas_trabajadas = excluded.horas_trabajadas,
    horas_extra_detectadas = excluded.horas_extra_detectadas,
    estado = excluded.estado,
    tiene_salida_no_retornada = excluded.tiene_salida_no_retornada,
    updated_at = now();
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (138, 'un_periodo_pagado_no_cambia_de_horas')
on conflict (numero) do nothing;


-- ============================================================================
-- 0155 — El libro de desembolsos entra al repositorio
-- ============================================================================
--
-- QUÉ PROMETE
--   `desembolsos_beneficios` queda descrita en el esquema, con la forma exacta
--   que ya tiene en producción, y protegida igual en todas las bases. Después de
--   esta migración, una base construida desde cero es idéntica a producción en
--   esta tabla.
--
-- QUÉ ASUME
--   · En producción la tabla YA existe: la 0153 la protegió el 2026-08-05. Acá
--     el `create table if not exists` no hace nada allá y sí en el laboratorio.
--   · Su forma se leyó de `information_schema` en producción ese mismo día. No
--     hay ni un tipo adivinado.
--
-- DE DÓNDE SALE ESTA TABLA
--   No de una migración: alguien la creó a mano en el SQL Editor. El comparador
--   la encontró el 2026-08-05 porque sus siete candados aparecieron como «sobran
--   en produccion». Cero coincidencias en el código, en las nueve ramas y en la
--   historia completa de commits.
--
--   Es el libro de a quién se le entregó qué beneficio: las cinco ventanas del
--   año peruano —las dos gratificaciones, los dos depósitos de CTS y las
--   vacaciones—, de qué año, cuánto, cuándo y por dónde salió la plata.
--
-- LO QUE ESTA MIGRACIÓN NO RESUELVE, Y HAY QUE DECIDIR
--   Ninguna función del sistema lee esta tabla. Comprobado: cero.
--
--   El sistema calcula lo que se DEBE (fn_cts_trunca, fn_grati_trunca,
--   fn_provisiones) y esta tabla registra lo que se PAGÓ, y no se hablan. La
--   0123 ya arregló que lo pagado dejara de acumularse en Provisiones, pero lo
--   hizo mirando los movimientos de la PLANILLA. Los valores de `origen`
--   —`plame`, `transferencia`, `otro`— sugieren que esta tabla anota justamente
--   lo que salió POR FUERA de la planilla, que es lo que la 0123 no puede ver.
--
--   Si eso es así, hoy hay dinero entregado que las provisiones no descuentan.
--   Es una decisión de negocio, no técnica, y no se toma en una migración.
--
-- POR QUÉ REPITE LA PROTECCIÓN DE LA 0153
--   Porque el orden manda. La 0153 corre ANTES y en el laboratorio no encuentra
--   la tabla, así que no hace nada; si esta solo la creara, el laboratorio
--   quedaría con la tabla abierta y producción con ella cerrada, y el comparador
--   marcaría esa diferencia para siempre. Con las dos, las dos bases convergen:
--   allá el `create` no hace nada y la protección es idempotente; acá se crea y
--   se protege en el mismo acto.
--
-- UNA DIVERGENCIA QUE SE CONSERVA A PROPÓSITO
--   `monto` es `numeric` SIN precisión, mientras el resto del sistema usa
--   `numeric(10,2)`. Se reproduce tal cual: el trabajo de esta migración es que
--   el repositorio describa la realidad, no corregirla de contrabando. Ajustar
--   el tipo cambia cómo se redondea plata ya registrada y merece su propia
--   migración, su propia prueba y su propia decisión.
--
-- CÓMO SE REVIERTE
--   En el laboratorio: drop table desembolsos_beneficios.
--   En producción NO se revierte: la tabla tiene datos y es anterior al repo.
-- ============================================================================

create table if not exists desembolsos_beneficios (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id),
  -- Las cinco ventanas del año laboral peruano. No es una lista arbitraria:
  -- son los momentos en que la ley obliga a entregar algo.
  ventana        text not null check (ventana = any (array['grati_s1','grati_s2','cts_may','cts_nov','vacaciones'])),
  anio           integer not null check (anio >= 2020 and anio <= 2100),
  monto          numeric not null check (monto > 0),
  fecha_pago     date not null,
  -- Por dónde salió: declarado en la PLAME, transferido al banco, u otro.
  origen         text not null check (origen = any (array['plame','transferencia','otro'])),
  nota           text,
  registrado_por uuid references personas(id),
  created_at     timestamptz not null default now()
);

-- Misma protección que la 0153 dejó en producción. Idempotente: allá no cambia
-- nada, acá deja el laboratorio igual que producción.
alter table desembolsos_beneficios enable row level security;
revoke all on desembolsos_beneficios from authenticated, anon;
drop policy if exists desembolsos_lectura_admin on desembolsos_beneficios;
create policy desembolsos_lectura_admin on desembolsos_beneficios
  for select using (fn_es_admin_o_lider());
grant select on desembolsos_beneficios to authenticated;

comment on table desembolsos_beneficios is
  'Libro de beneficios desembolsados: las cinco ventanas del año (dos gratificaciones, '
  'dos CTS, vacaciones), de qué año, cuánto, cuándo y por dónde salió. Creada a mano en '
  'producción antes de la 0153 y descrita en el repositorio recién en la 0155. Solo lectura '
  'para admin o líder de DO. NINGUNA función del sistema la lee todavía: lo que se debe y '
  'lo que se pagó se calculan por separado y no se descuentan entre sí.';

insert into migraciones_aplicadas (numero, nombre)
values (155, 'el_libro_de_desembolsos_entra_al_repositorio')
on conflict (numero) do nothing;

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
select 'El día pagado ya no cambia de horas' as comprobacion,
       case when (select prosrc from pg_proc where proname='fn_recalcular_jornada' limit 1)
                 ilike '%CANDADO DE PERIODO PAGADO%'
            then 'OK' else 'REVISAR' end as resultado
union all
select 'El libro de desembolsos existe y está descrito',
       case when to_regclass('public.desembolsos_beneficios') is not null
            then 'OK' else 'REVISAR' end
union all
select 'Y sigue cerrado (RLS activo)',
       case when (select relrowsecurity from pg_class where relname='desembolsos_beneficios')
            then 'OK' else 'REVISAR' end
union all
select 'Ninguna sesión puede escribirlo',
       case when (select count(*) from information_schema.role_table_grants
                   where table_name='desembolsos_beneficios' and grantee='authenticated'
                     and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')) = 0
            then 'OK' else 'REVISAR' end
union all
select 'Migración 138 anotada',
       case when exists (select 1 from migraciones_aplicadas where numero=138) then 'OK' else 'REVISAR' end
union all
select 'Migración 155 anotada',
       case when exists (select 1 from migraciones_aplicadas where numero=155) then 'OK' else 'REVISAR' end;

commit;

-- ############################################################################
-- Después del commit: el único dato que falta de todo el día.
-- ############################################################################
select count(*) as filas_en_desembolsos from desembolsos_beneficios;
