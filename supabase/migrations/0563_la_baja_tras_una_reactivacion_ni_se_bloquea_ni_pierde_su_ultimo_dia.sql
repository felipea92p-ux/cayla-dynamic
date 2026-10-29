-- ============================================================================
-- 0563 · LA BAJA TRAS UNA REACTIVACIÓN NI SE BLOQUEA NI PIERDE SU ÚLTIMO DÍA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que darle de baja a quien se reactivó por error de fecha funcione y quede con
--   el último día que de verdad trabajó. Dos arreglos, cada uno en su función:
--
--   1 · `fn_prueba_cerrar` (0536) busca el último día trabajado DESDE EL INICIO
--       DE LA PRUEBA ABIERTA, no desde el ingreso. Cuando la prueba se reabre
--       —cada vez que alguien se reactiva, el trigger abre una nueva con inicio
--       HOY— las jornadas anteriores dejan de verse, `v_ultima` queda vacía y la
--       baja cae al día de INGRESO. Robert Cabrera (ingreso 19/10, última jornada
--       28/10) quedó con cese el 19/10 y su liquidación pagaba un solo día
--       (S/ 63.72). Ahora busca desde el ingreso.
--
--   2 · `fn_cese_aplicar` (0535) se negaba a cesar si había un tramo de salario
--       u horario que empieza DESPUÉS del último día —«tiene un horario que
--       empieza el …»— y ese es justo el tramo que deja `fn_reactivar_persona`
--       (0327): vuelve desde hoy o desde el día siguiente al cese. Así que el
--       camino natural de corregir una baja mal puesta —reactivar y repetirla—
--       siempre chocaba. Ahora la baja retira esos tramos, y SOLO esos (ver abajo).
--
-- DE DÓNDE SALE
--   Medido en producción el 2026-10-29: Robert Cabrera y Emily Rico, los dos de
--   preselección, los dos reactivados a las 23:01 tras una primera baja. Se
--   arreglaron a mano esa noche (tramos borrados, cese corregido a 28/10), con su
--   rastro en `correcciones_auditoria`. Esta migración es el arreglo general.
--
-- QUÉ ASUME — MEDIDO EN PRODUCCIÓN EL 2026-10-29, ANTES DE ESCRIBIRLA
--   El cuerpo de las dos funciones en producción es el de sus migraciones
--   vigentes, byte por byte, sin \r:
--       fn_prueba_cerrar .... 3 284 caracteres  b8161af754d040005210012d4b8665ee  (0536)
--       fn_cese_aplicar ..... 3 993 caracteres  442ac68023b3567585896bc5bfef5c0e  (0535)
--   La guardia de abajo se NIEGA a pegar sobre otra versión (la 0261 revirtió la
--   maternidad y las vacaciones por copiar de una versión que no era la vigente).
--   Acepta el md5 tal cual y su variante con \r\n (pegar desde Windows).
--   `fn_reactivar_persona` NO se toca: devolver el sueldo desde mañana cuando el
--   cese es de hoy es a propósito (la 0209), para no pisar el día trabajado.
--
-- POR QUÉ ASÍ, Y QUÉ NO HACE
--   · «Solo los que creó la reactivación». Un salario u horario futuro que alguien
--     cargó a propósito sigue frenando la baja, con el mensaje de siempre: esa
--     persona decidió algo y callarlo sería borrarlo. Lo que se retira se
--     reconoce por la constancia que la propia reactivación dejó en
--     `correcciones_auditoria` (`salario_al_reactivar`, `horario_al_reactivar`)
--     con la fecha exacta del tramo, y además hace falta que nadie haya marcado
--     desde ese día y que el día no caiga en un periodo pagado.
--   · No borra sin dejar rastro: cada tramo retirado queda escrito con su sueldo
--     o su horario (`salario_de_reactivacion_retirado`, `horario_de_reactivacion_retirado`).
--   · El tramo que la reactivación había continuado (el que cerró la baja vieja)
--     se lleva al NUEVO último día: se extiende si la baja vieja fue antes
--     (Robert: 19/10 → 28/10) y se recorta si fue después. Sin esto el sueldo
--     quedaba cerrado el día de la baja equivocada y la liquidación seguía corta.
--   · El resto de cada cuerpo es el de producción, sin una coma de más. Cada
--     cambio lleva su marca «CAMBIO 0563».
--   · NO cambia ninguna regla de pago: cambia cuál es el último día de alguien
--     y qué tramos tiene, que la liquidación ya lee.
--
-- CÓMO SE COMPRUEBA
--   Prueba 453 (pgTAP), con los dos casos reales y tres negativos. El `select`
--   del final dice que las dos funciones llevan la marca.
--
-- CÓMO SE REVIERTE
--   Pegar de nuevo la 0536 (fn_prueba_cerrar) y la 0535 (fn_cese_aplicar). Los
--   datos que ya se corrigieron no se vuelven a tocar.
-- ============================================================================

do $guardia$
declare v_a text; v_b text; v_n int;
begin
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('fn_prueba_cerrar', 'fn_cese_aplicar');
  if v_n <> 2 then
    raise exception 'PARA. Se esperaba UNA versión de fn_prueba_cerrar y UNA de fn_cese_aplicar y hay % funciones: pegar esto reemplazaría a ciegas. Nada se modificó.', v_n;
  end if;
  select prosrc into v_a from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_prueba_cerrar';
  select prosrc into v_b from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_cese_aplicar';
  if v_a like '%CAMBIO 0563%' and v_b like '%CAMBIO 0563%' then
    return;  -- repegada: ya está
  end if;
  if md5(replace(v_a, chr(13), '')) <> 'b8161af754d040005210012d4b8665ee' then
    raise exception 'PARA. fn_prueba_cerrar de esta base no es la de la 0536 (md5 %, % caracteres). Pedir el md5 de producción y reconstruir esta migración desde esa versión. Nada se modificó.', md5(v_a), length(v_a);
  end if;
  if md5(replace(v_b, chr(13), '')) <> '442ac68023b3567585896bc5bfef5c0e' then
    raise exception 'PARA. fn_cese_aplicar de esta base no es la de la 0535 (md5 %, % caracteres). Pedir el md5 de producción y reconstruir esta migración desde esa versión. Nada se modificó.', md5(v_b), length(v_b);
  end if;
end;
$guardia$;

create or replace function fn_prueba_cerrar(
  p_persona_id uuid,
  p_resultado  text,
  p_motivo     text,
  p_fecha_cese date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor   uuid;
  v_p       personas%rowtype;
  v_pr      pruebas%rowtype;
  v_hoy     date := fn_hoy_lima();
  v_motivo  text := btrim(coalesce(p_motivo, ''));
  v_ultima  date;
  v_fecha   date;
begin
  if p_resultado is null or p_resultado not in ('no_apto', 'retirado') then
    raise exception 'El resultado de la prueba tiene que ser «no apto» o «se retiró».';
  end if;
  if length(v_motivo) < 3 then
    raise exception 'Escribe el motivo: queda registrado junto con quién decidió.';
  end if;
  if fn_prueba_puede_actuar(p_persona_id) is not true then
    raise exception 'No puedes decidir sobre la prueba de esta persona.';
  end if;

  v_actor := fn_persona_actual_id();
  if v_actor is null then
    raise exception 'No puedo identificar quién decide, así que no puedo dejarlo registrado. Inicia sesión con tu usuario.';
  end if;
  if v_actor = p_persona_id then
    raise exception 'No puedes decidir sobre tu propia prueba.';
  end if;

  -- El mismo candado que el cese, y en el mismo orden: la persona primero. Dos
  -- cierres a la vez (la líder y DO) se turnan aquí, y el segundo ya la ve cerrada.
  select * into v_p from personas where id = p_persona_id for update;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva (cesó el %).', to_char(v_p.fecha_cese, 'DD/MM/YYYY');
  end if;
  if v_p.tipo_vinculo <> 'prueba' then
    raise exception 'Esa persona no está de prueba (su vínculo es «%»).', v_p.tipo_vinculo;
  end if;

  select * into v_pr from pruebas
   where persona_id = p_persona_id and resultado = 'en_curso' for update;
  if not found then
    -- El trigger nunca frena un cambio de vínculo; si no pudo abrirla, se abre aquí.
    insert into pruebas (persona_id, inicio) values (p_persona_id, v_p.fecha_ingreso)
    returning * into v_pr;
  end if;

  -- Fecha de cese = el último día trabajado, salvo que se indique otra; nunca
  -- anterior a él. Sin días trabajados: el día de ingreso (o hoy, si ingresa después).
  select max(j.fecha) into v_ultima from jornadas j
   where j.persona_id = p_persona_id and j.fecha >= v_p.fecha_ingreso and j.entrada_ts is not null;  -- CAMBIO 0563
  v_fecha := coalesce(p_fecha_cese, v_ultima, least(v_hoy, v_p.fecha_ingreso));
  if v_ultima is not null and v_fecha < v_ultima then
    raise exception 'Su último día trabajado fue el %; la baja no puede ser anterior (pusiste %).',
      to_char(v_ultima, 'DD/MM/YYYY'), to_char(v_fecha, 'DD/MM/YYYY');
  end if;

  update pruebas
     set resultado = p_resultado, motivo = v_motivo, cerrada_por = v_actor,
         cerrada_at = now(), cerrada_fecha = v_fecha
   where id = v_pr.id;

  perform fn_cese_aplicar(
    p_persona_id, v_fecha,
    case p_resultado when 'retirado' then 'renuncia' else 'fin_periodo_prueba' end,
    null, v_actor);

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'pruebas.resultado', 'en_curso', p_resultado, v_actor,
     'Prueba cerrada como ' || case p_resultado when 'retirado' then 'SE RETIRÓ' else 'NO APTO' end
       || ', último día trabajado ' || to_char(v_fecha, 'DD/MM/YYYY') || '. Motivo: ' || v_motivo);

  return v_pr.id;
end;
$$;

create or replace function fn_cese_aplicar(
  p_persona_id uuid,
  p_fecha_cese date,
  p_motivo text,
  p_tipo_vinculo text,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_p personas%rowtype; v_hoy date := (now() at time zone 'America/Lima')::date;
        v_desde date; v_n int;  -- CAMBIO 0563: v_n
begin
  -- 0174: toma el candado de la fila ANTES de mirar el estado, para que un
  -- segundo cese simultáneo espere aquí, relea la fila ya cesada y rebote.
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
  if fn_fecha_en_periodo_pagado(p_fecha_cese, p_persona_id) then
    raise exception 'El % cae dentro de un periodo de planilla ya PAGADO. Reabre ese periodo primero (queda rastro) o corrige la fecha.',
      to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;

  -- CAMBIO 0563 · LOS TRAMOS QUE DEJÓ UNA REACTIVACIÓN NO BLOQUEAN LA BAJA.
  -- `fn_reactivar_persona` devuelve salario y horario desde HOY (o desde el día
  -- siguiente al cese). Si la baja era un error de fecha y se reactiva para
  -- rehacerla, esos tramos nuevos empiezan DESPUÉS del último día correcto y la
  -- baja se negaba con «tiene un horario que empieza el …». Aquí se retiran,
  -- pero SOLO los que esa reactivación creó —los reconoce su propia constancia
  -- en `correcciones_auditoria`—, nunca uno que alguien cargó a propósito, y solo
  -- si nadie trabajó desde ese día y el día no cae en un periodo pagado. Lo que se
  -- retira queda escrito, con su sueldo o su horario. Y el tramo que la
  -- reactivación había continuado se recorta o se extiende al nuevo último día:
  -- sin eso el sueldo quedaba cerrado el día de la baja equivocada.
  with b as (
    delete from asignaciones_salario a
     where a.persona_id = p_persona_id
       and a.vigente_desde > p_fecha_cese
       and exists (select 1 from correcciones_auditoria ca
                    where ca.persona_id = a.persona_id
                      and ca.campo_modificado = 'salario_al_reactivar'
                      and ca.valor_nuevo like '% vigente desde ' || a.vigente_desde::text)
       and not exists (select 1 from jornadas j
                        where j.persona_id = a.persona_id and j.fecha >= a.vigente_desde
                          and j.entrada_ts is not null)
       and not fn_fecha_en_periodo_pagado(a.vigente_desde, a.persona_id)
    returning a.vigente_desde, a.salario_mensual_soles
  ), au as (
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    select p_persona_id, 'salario_de_reactivacion_retirado',
           'S/ ' || b.salario_mensual_soles::text || ' vigente desde ' || b.vigente_desde::text,
           'retirado al dar de baja con último día ' || p_fecha_cese::text, p_actor,
           'Baja tras una reactivación: ese tramo lo creó la reactivación y empezaba después del último día trabajado.'
      from b
  )
  select count(*) into v_n from b;
  if v_n > 0 then
    update asignaciones_salario set vigente_hasta = p_fecha_cese
     where persona_id = p_persona_id and vigente_desde <= p_fecha_cese
       and vigente_hasta = (select max(vigente_hasta) from asignaciones_salario where persona_id = p_persona_id);
  end if;

  with b as (
    delete from horarios_asignados h
     where h.persona_id = p_persona_id
       and h.vigente_desde > p_fecha_cese
       and exists (select 1 from correcciones_auditoria ca
                    where ca.persona_id = h.persona_id
                      and ca.campo_modificado = 'horario_al_reactivar'
                      and ca.valor_nuevo = 'horario restituido desde ' || h.vigente_desde::text)
       and not exists (select 1 from jornadas j
                        where j.persona_id = h.persona_id and j.fecha >= h.vigente_desde
                          and j.entrada_ts is not null)
    returning h.vigente_desde
  ), au as (
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    select p_persona_id, 'horario_de_reactivacion_retirado',
           'horario desde ' || b.vigente_desde::text,
           'retirado al dar de baja con último día ' || p_fecha_cese::text, p_actor,
           'Baja tras una reactivación: ese tramo lo creó la reactivación y empezaba después del último día trabajado.'
      from b
  )
  select count(*) into v_n from b;
  if v_n > 0 then
    update horarios_asignados set vigente_hasta = p_fecha_cese
     where persona_id = p_persona_id and vigente_desde <= p_fecha_cese
       and vigente_hasta = (select max(vigente_hasta) from horarios_asignados where persona_id = p_persona_id);
  end if;

  -- 0176: no se puede cerrar un tramo que todavía no empezó. Se avisa acá, con
  -- la fecha concreta y qué hacer, en vez de dejar que reviente el constraint.
  select min(vigente_desde) into v_desde from asignaciones_salario
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un salario que empieza el %, después del último día que pusiste (%). Corrige ese salario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  select min(vigente_desde) into v_desde from horarios_asignados
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un horario que empieza el %, después del último día que pusiste (%). Corrige ese horario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
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

  -- El rastro que faltaba. p_motivo no es texto libre: son los códigos fijos
  -- de `personas_motivo_cese_valido` (0086/0143/0325, p. ej. 'despido'), así
  -- que el texto sale corto — sigue siendo más de lo que había, que era nada.
  -- `||` propaga NULL, así que cuando no vino p_tipo_vinculo el `coalesce` de
  -- afuera cae en '.' — sin `if` aparte.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'personas.estado', 'activo', 'inactivo',
     p_actor,
     'Cese con último día trabajado el ' || to_char(p_fecha_cese, 'DD/MM/YYYY')
       || '. Motivo: ' || p_motivo
       || coalesce('. Vínculo pasa a ' || p_tipo_vinculo || '.', '.'));
end;
$function$;

insert into migraciones_aplicadas (numero, nombre) values (563, 'la_baja_tras_una_reactivacion_ni_se_bloquea_ni_pierde_su_ultimo_dia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
select
  (select prosrc like '%CAMBIO 0563%' from pg_proc where proname = 'fn_prueba_cerrar')  as prueba_cerrar_con_marca,
  (select prosrc like '%CAMBIO 0563%' from pg_proc where proname = 'fn_cese_aplicar')   as cese_aplicar_con_marca,
  (select count(*) from migraciones_aplicadas where numero = 563 and nombre like 'la_baja_tras%') as registrada;
