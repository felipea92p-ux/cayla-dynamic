-- ============================================================================
-- 0207_una_marca_que_cae_en_un_periodo_pagado_deja_de_entrar_muda.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que una marca cuya fecha cae dentro de un periodo YA PAGADO entre igual
--   —jamás se pierde una marca real— pero sellada `pendiente_revision`, para
--   que aparezca en Correcciones en vez de aterrizar en silencio.
--
-- QUÉ ASUME
--   Nada nuevo. Ni una tabla, ni una columna, ni un permiso. Reusa el mismo
--   mecanismo de sellado que la función ya aplica cuando el día queda incoherente.
--
-- ── QUÉ SE MIDIÓ ANTES DE ESCRIBIR ESTO, Y POR QUÉ IMPORTA ──────────────────
--
-- `docs/hallazgos-abiertos.md` describe este hueco así: «el trigger recalcula la
-- jornada sin decir nada… el número de una planilla ya pagada cambia solo».
--
-- **Eso es FALSO, y se comprobó.** Reproducido el 2026-08-10 contra el esquema
-- completo, dentro de BEGIN … ROLLBACK: periodo 29-jun→28-jul en estado
-- `pagado`, una jornada de 8.00 h ya calculada dentro de él, y una marca
-- rezagada de la cola offline con fecha 15-jul.
--
--     ANTES   horas_trabajadas = 8.00
--     DESPUÉS horas_trabajadas = 8.00      ← no se movió
--     marca   estado_revision  = normal    ← y nadie se enteró
--
-- El pago NO cambia: `fn_recalcular_jornada` lleva desde la 0138 el candado que
-- se niega a recalcular un periodo pagado, y aguanta. Lo que falla es lo otro:
-- **la marca entra muda.** A partir de ese momento los marcajes de ese día
-- dicen una cosa y la jornada que se pagó dice otra, y no hay nada que lo
-- señale a nadie.
--
-- La diferencia entre las dos versiones no es de matiz. Una pide reabrir un
-- periodo y revisar pagos; la otra pide que alguien mire una marca. Escribir la
-- primera cuando la verdad es la segunda es cómo se gasta el crédito de un
-- documento de hallazgos — y este repositorio ya perdió horas hoy por dos
-- entradas suyas que describían defectos que estaban arreglados.
--
-- ── POR QUÉ SELLAR Y NO RECHAZAR ────────────────────────────────────────────
--
-- Rechazar es lo que NO se puede hacer, y la 0068 ya lo dejó escrito: este
-- cuerpo lo ejecuta la terminal, que reintenta seis veces y acaba descartando
-- la marca. Perder el registro de un hecho —alguien que sí estuvo ahí— es peor
-- que tener un día pagado que no coincide con sus marcas. Los marcajes son la
-- fuente de verdad y son append-only.
--
-- Así que entra, y se sella. Es el mismo trato que la función ya le da al día
-- que queda incoherente: no se pierde nada, pero deja de estar en silencio.
--
-- ── LOS DOS CAMINOS, Y EL SEGUNDO SE OLVIDA FÁCIL ───────────────────────────
--
-- Hay DOS salidas por las que una marca llega a existir en esta función:
--
--   1. El `insert` del final — el caso normal.
--   2. La RECONCILIACIÓN: una `salida_final` real que llega después de un
--      auto-cierre sintético del mismo día no se duplica, PISA el registro
--      sintético con `update` y **retorna antes**, sin pasar por el insert.
--
-- El camino 2 es el más delicado de los dos: cambia la hora de una marca que ya
-- existía dentro del periodo pagado, y encima le pone `estado_revision =
-- 'normal'` explícitamente — borrando cualquier sello previo. Sellar solo el
-- camino 1 habría dejado el peor caso sin cubrir.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
-- No toca `fn_auto_cierre`, que es la otra puerta que corre sin una persona
-- delante. Ahí el arreglo es distinto —saltarse la candidata y alertar, no
-- sellar— y merece su propia migración con su propia prueba.
--
-- No sella el día entero, solo la marca recién llegada. El día ya se pagó y su
-- jornada es correcta como foto de lo que se pagó; lo anómalo es la visita.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Volver a pegar la definición de la 0082. Revertir significa que una marca
--   dentro de un periodo pagado vuelva a entrar sin que nadie se entere.
--
-- ── ⚠️ ANTES DE PEGAR ───────────────────────────────────────────────────────
--   Esta función se reescribe partiendo de la 0082, que es la vigente según
--   `./scripts/donde-vive.sh fn_registrar_marcaje`. El md5 del Postgres local
--   reconstruido desde las migraciones es 5a477b781d4dbbc639b8621ba8b3c7be.
--   Confírmalo contra PRODUCCIÓN antes de pegar — el md5 se le pregunta a
--   producción, nunca se copia del local:
--
--     select md5(prosrc) from pg_proc where proname = 'fn_registrar_marcaje';
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final, y la prueba 161.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_registrar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_timestamp_cliente timestamp with time zone, p_client_uuid uuid, p_origen origen_marca DEFAULT 'terminal'::origen_marca, p_terminal_id uuid DEFAULT NULL::uuid, p_sede_id uuid DEFAULT NULL::uuid, p_motivo_otro text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sede_id uuid;
  v_marcaje marcajes;
  v_existente marcajes;
  v_fecha date;
  v_esperado tipo_marca;
  v_caller_rol rol_usuario;
  v_terminal_auth uuid;
  v_ultimo_ts timestamptz;
  v_atrasada boolean;
  v_en_pagado boolean;     -- 0207: ¿esta marca cae dentro de un periodo ya pagado?
begin
  -- Idempotencia: reintentos offline con el mismo client_uuid no duplican.
  select * into v_existente from marcajes where client_uuid = p_client_uuid;
  if found then
    return v_existente;
  end if;

  if p_origen = 'terminal' then
    if p_terminal_id is null then
      raise exception 'p_terminal_id es obligatorio cuando origen = terminal';
    end if;
    select sede_id, auth_user_id into v_sede_id, v_terminal_auth
    from terminales where id = p_terminal_id and activo;
    if v_sede_id is null then
      raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
    end if;
    if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then
      raise exception 'el terminal autenticado no coincide con p_terminal_id';
    end if;
  else
    if p_sede_id is null then
      raise exception 'p_sede_id es obligatorio cuando origen != terminal';
    end if;
    select rol into v_caller_rol from personas where auth_user_id = auth.uid();
    if v_caller_rol is null or v_caller_rol not in ('admin', 'lider_do', 'supervisor_sede') then
      raise exception 'no autorizado para registrar marcajes con origen %', p_origen;
    end if;
    if v_caller_rol = 'supervisor_sede' then
      if not exists (
        select 1 from personas
        where auth_user_id = auth.uid() and sede_base_id = p_sede_id
      ) then
        raise exception 'un supervisor_sede solo puede corregir marcajes de su propia sede';
      end if;
    end if;
    v_sede_id := p_sede_id;
  end if;

  if p_tipo = 'salida_otro' and (p_motivo_otro is null or length(trim(p_motivo_otro)) < 3) then
    raise exception 'motivo_otro es obligatorio para salida_otro';
  end if;

  v_fecha := (p_timestamp_cliente at time zone 'America/Lima')::date;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ ¿Cae dentro de un periodo ya pagado?
  -- Se calcula acá arriba, una sola vez, porque hace falta en los DOS caminos
  -- por los que esta función deja una marca: el insert del final y la
  -- reconciliación del auto-cierre, que retorna antes de llegar a él.
  --
  -- Lo que NO se hace con esto es rechazar. La 0068 ya lo dejó escrito: la
  -- terminal reintenta seis veces y acaba descartando la marca. Perder el
  -- registro de alguien que sí estuvo es peor que un día pagado que no cuadra.
  select exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) into v_en_pagado;

  -- ¿LLEGA ATRASADA? Su hora es anterior a la última ya registrada de ese día:
  -- viene de la cola offline. No se le puede aplicar la validación de secuencia
  -- (se juzgaría contra un presente que no le corresponde, se rechazaría, y la
  -- terminal acabaría borrándola tras 6 reintentos). Se acepta siempre.
  select max(timestamp_marca) into v_ultimo_ts
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and anulada_at is null;

  v_atrasada := v_ultimo_ts is not null and p_timestamp_cliente < v_ultimo_ts;

  -- Marcas EN VIVO: candado anti-doble-marcado de siempre, intacto.
  if p_origen = 'terminal' and not v_atrasada then
    v_esperado := fn_siguiente_tipo_esperado(p_persona_id, v_fecha);
    if v_esperado is not null and v_esperado <> p_tipo then
      raise exception 'tipo % no válido en el estado actual (se esperaba %)', p_tipo, v_esperado;
    end if;
    if v_esperado is null and p_tipo not in (
      'salida_final', 'salida_almuerzo', 'salida_personal', 'salida_tramite', 'salida_medico', 'salida_otro'
    ) then
      raise exception 'tipo % no válido: la jornada ya está cerrada o requiere elegir un tipo de salida', p_tipo;
    end if;
  end if;

  -- Reconciliación: una salida_final real que llega después de un auto-cierre
  -- sintético del mismo día reemplaza el registro sintético, no lo duplica.
  if p_tipo = 'salida_final' then
    select * into v_existente
    from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and origen = 'auto_cierre'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null;

    if found then
      update marcajes set
        timestamp_marca = p_timestamp_cliente,
        origen = p_origen,
        -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ Este es el camino delicado, y el que se olvida:
        -- cambia la HORA de una marca que ya existía dentro del periodo pagado,
        -- y además ponía 'normal' a secas, borrando cualquier sello previo.
        estado_revision = case when v_en_pagado then 'pendiente_revision'::estado_revision
                               else 'normal'::estado_revision end,
        client_uuid = p_client_uuid,
        terminal_id = p_terminal_id,
        server_received_at = now()
      where id = v_existente.id
      returning * into v_marcaje;

      return v_marcaje;
    end if;
  end if;

  insert into marcajes (
    client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen
  ) values (
    p_client_uuid, p_persona_id, v_sede_id, p_terminal_id, p_tipo, p_motivo_otro, p_timestamp_cliente, p_origen
  )
  returning * into v_marcaje;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ La marca entra, pero no entra muda.
  -- Solo se sella ELLA y no el día entero: el día ya se pagó y su jornada es
  -- correcta como foto de lo que se pagó — lo anómalo es la recién llegada.
  if v_en_pagado then
    update marcajes set estado_revision = 'pendiente_revision' where id = v_marcaje.id;
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  -- ¿El día quedó IMPOSIBLE al ordenarlo por hora? Entonces se sella para que
  -- aparezca en Correcciones. No se pierde nada, pero deja de estar en silencio.
  -- Solo se sella si de verdad quedó roto: una marca atrasada que encaja bien
  -- en la secuencia no genera ninguna alarma.
  if fn_dia_incoherente(p_persona_id, v_fecha) then
    update marcajes
      set estado_revision = 'pendiente_revision'
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and estado_revision = 'normal';
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  return v_marcaje;
end;
$function$;

-- El `create or replace` conserva los permisos porque NO hay `drop` y la firma
-- no cambia. Se re-declaran igual, que es lo que la propia 0082 dejó escrito al
-- final —«una función reemplazada sin su grant se manifiesta como permission
-- denied»— y lo que la 0189 olvidó, dejando el semáforo ciego dos días.
grant execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text) to authenticated;
revoke execute on function fn_registrar_marcaje(uuid, tipo_marca, timestamptz, uuid, origen_marca, uuid, uuid, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (207, 'una_marca_que_cae_en_un_periodo_pagado_deja_de_entrar_muda')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- ⚠️ ESTA CONSULTA SE CORRIGIÓ EL MISMO 2026-08-10, DESPUÉS DE PEGARLA. Nada de
-- lo que está arriba cambió —ni el cuerpo de la función, ni un permiso, ni el
-- md5— pero la consulta de abajo preguntaba lo que no era, y en producción
-- devolvió **1.323**, un número que parecía una catástrofe y no lo era.
--
-- Preguntaba «cuántas marcas dentro de un periodo pagado no están señaladas».
-- Eso es, prácticamente, TODA la asistencia normal de cada mes ya cerrado: 23
-- personas por 22 días por 2-4 marcas. Con un solo periodo pagado, 1.323 es
-- exactamente lo que tenía que salir, y no señala nada.
--
-- Lo que había que preguntar es cuántas marcas **llegaron al servidor DESPUÉS**
-- de que ese periodo se pagara, que es lo único anómalo. La respuesta está en
-- comparar `marcajes.server_received_at` con `periodos_planilla.pagado_at`, y
-- eso es lo que hace la versión de abajo.
--
-- Se deja escrito en vez de borrarlo: un número tranquilizador que asusta gasta
-- la misma confianza que uno alarmante que no avisa.
select
  -- Las anómalas de verdad: su fecha cae en un periodo pagado Y entraron al
  -- servidor después de pagarlo.
  (select count(*) from marcajes m
     join periodos_planilla p
       on p.estado = 'pagado'
      and (m.timestamp_marca at time zone 'America/Lima')::date
          between p.fecha_ini and p.fecha_fin
    where m.anulada_at is null
      and p.pagado_at is not null
      and m.server_received_at > p.pagado_at)                      as marcas_llegadas_tarde,
  -- Y de esas, las que además nadie señaló: el pasado que la 0207 no arregla,
  -- porque cambia lo que viene, no lo que ya pasó.
  (select count(*) from marcajes m
     join periodos_planilla p
       on p.estado = 'pagado'
      and (m.timestamp_marca at time zone 'America/Lima')::date
          between p.fecha_ini and p.fecha_fin
    where m.anulada_at is null
      and p.pagado_at is not null
      and m.server_received_at > p.pagado_at
      and m.estado_revision = 'normal')                            as y_sin_ninguna_senal,
  (select count(*) from periodos_planilla where estado = 'pagado')  as periodos_pagados,
  (select case when prosrc ilike '%v_en_pagado%' then 'sí' else '⚠ NO' end
     from pg_proc where proname = 'fn_registrar_marcaje')           as la_0207_esta_viva,
  has_function_privilege('authenticated',
    'public.fn_registrar_marcaje(uuid,tipo_marca,timestamptz,uuid,origen_marca,uuid,uuid,text)'::regprocedure,
    'EXECUTE')                                                      as terminal_puede_marcar;
