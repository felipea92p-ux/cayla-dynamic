-- ============================================================================
-- 0209_reactivar_devuelve_el_sueldo_desde_el_dia_que_vuelve.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que reactivar a quien se cesó por error no la deje activa, marcando todos
--   los días y cobrando S/0.00. Al volver se le abre un tramo de salario y uno
--   de horario NUEVOS, con lo que tenía, vigentes DESDE EL DÍA QUE VUELVE.
--
-- QUÉ ASUME
--   Ni una tabla, ni una columna, ni un permiso cambian. Se reescribe una sola
--   función, `fn_reactivar_persona`, cuyo cuerpo vigente son 417 caracteres.
--
--   md5 de partida, confirmado en el SQL Editor de PRODUCCIÓN el 2026-08-10:
--     fn_reactivar_persona   417 car.   b0fd63db156a1a20219e3c0d2df5abf8
--     fn_cesar_persona      3476 car.   727eb1ba7c62ead765c45e41c3357c92  (no se toca)
--   Producción, repositorio y Postgres local coinciden byte a byte. Si al pegar
--   esto el md5 de partida fuera otro, PARA: significaría que producción tiene
--   una versión que el repositorio no conoce, y esto la borraría en silencio.
--
-- ── EL PROBLEMA, REPRODUCIDO ────────────────────────────────────────────────
--
-- `fn_cesar_persona` (0176) cierra los tramos abiertos de `asignaciones_salario`
-- y `horarios_asignados` poniéndoles `vigente_hasta = fecha_cese`.
-- `fn_reactivar_persona` (0086) devuelve `estado='activo'` y limpia `fecha_cese`,
-- y no reabre ninguno. Medido con las funciones reales, dos personas idénticas:
--
--     sana        S/2,254.64      reactivada   S/0.00      mismas 195.00 h
--     faltas: 5                   faltas: 0                misma semana sin marcar
--
-- Queda activa y marcando, sin salario vigente y sin horario vigente: la
-- planilla le paga cero y el motor de faltas y tardanzas deja de verla. Y la
-- propia 0086 dice que reactivar existe «porque a veces la baja fue un error»:
-- es exactamente ese caso el que rompe.
--
-- ── POR QUÉ UN TRAMO NUEVO Y NO REABRIR EL VIEJO ────────────────────────────
--
-- El primer diseño era simétrico y elegante: reabrir lo que el cese cerró,
-- poniendo `vigente_hasta = null` en esas mismas filas. **Se midió antes de
-- escribirlo y habría metido un defecto peor que el que arregla.**
--
-- `vigente_hasta = null` no dice «vigente desde que volvió». Dice «vigente desde
-- su vigente_desde HASTA EL INFINITO», así que cubre retroactivamente todo el
-- hueco entre el cese y hoy. Reproducido en BEGIN … ROLLBACK:
--
--   · reescribe planillas YA PAGADAS — S/2,420.63 en un periodo; con un cese en
--     abril, S/3,390.00 repartidos en tres. Y pasa MUDO: no hay ningún trigger
--     sobre estas dos tablas, y el candado de periodo pagado vive DENTRO de
--     `fn_set_salario`, así que un update desde otra función lo esquiva.
--   · sobrepaga el periodo EN CURSO — un sueldo fijo cobra el mes entero,
--     S/1,130.00, sin haber trabajado un día. Ningún candado de «periodo
--     pagado» lo atrapa, porque el periodo en curso no está pagado.
--   · devenga grati, CTS y vacaciones de todo el hueco — +S/719.52 en una
--     persona. Y no se queda en la boleta: `fn_grati_cts_periodo` lo desembolsa.
--   · fabrica 89 faltas no justificadas, que alimentan
--     `fn_expediente_generar_falta`. Ochenta y nueve días seguidos sin marcar
--     es el supuesto de abandono del art. 25 inc. h) del D.S. 003-97-TR. Es el
--     falso positivo que este proyecto define como su peor error.
--
-- Un tramo que empieza el día de la reactivación no puede tocar el PASADO: lo ya
-- pagado se queda como está, y la prueba 173 lo exige llamando a
-- `fn_planilla_calcular` sobre un periodo pagado antes y después.
--
-- ⚠️ PERO EL PERIODO EN CURSO SÍ SE MUEVE PARA UN SUELDO FIJO, y la primera
-- versión de esta cabecera prometía que no. `fn_planilla_calcular` resuelve esa
-- rama con un lateral que toma CUALQUIER tramo que solape el periodo, sin
-- prorratear: el tramo nuevo enciende el mes entero — S/1,130.00 sin un día
-- trabajado. Por eso hay un segundo candado, abajo. No es un defecto que
-- introduzca esta migración: a quien INGRESA a mitad de periodo le pasa igual
-- desde siempre. Lo que sí hace esta migración es convertirlo en un camino
-- cómodo, así que se para y se dice qué hacer.
--
-- Y el hueco sin salario y sin horario **es la verdad de lo que pasó**: esa
-- persona no trabajó esos días.
--
-- La llave por fecha tampoco era fiable: en `horarios_asignados` puede
-- seleccionar DOS filas, porque `fn_set_horario_semanal` no recorta los tramos
-- ya cerrados como sí hace `fn_set_salario`. Medido en producción el
-- 2026-08-10: hoy ninguna de las 8 personas inactivas tiene ese caso, pero es
-- estructural y aparecería solo.
--
-- ── EL CANDADO DE PERIODO PAGADO, Y POR QUÉ ES ESTRECHO ─────────────────────
--
-- Volver a `estado='activo'` mueve, por sí solo y sin tocar ningún tramo, el
-- total de las planillas ya pagadas de quien tiene hijos: la asignación
-- familiar se paga con `case when pe.con_hijos then …`, sin mirar tramos ni
-- jornadas, y lo único que mete a la persona en el cálculo es el filtro
-- `where p.estado = 'activo'`. Medido: **S/98.31 en cada periodo pagado**
-- posterior al cese.
--
-- El candado NO se pone sobre «hay un periodo pagado después del cese», y esto
-- se decidió con datos: de las 8 personas inactivas de producción, **seis
-- tienen un periodo pagado posterior** y para las seis el daño es CERO (son
-- RxH, sin hijos, sin sueldo fijo). Un candado así rechazaría seis
-- reactivaciones legítimas de ocho. No protegería: prohibiría. Y un candado que
-- cierra siempre lo quita cualquiera en la primera urgencia.
--
-- Se pone donde el daño está medido, y son DOS condiciones, no una:
--
--   1. `con_hijos` con un periodo PAGADO detrás — la asignación familiar.
--   2. `sueldo_fijo` con cualquier periodo que solape entre el cese y hoy — el
--      mes completo. Esta la destapó la revisión adversaria de la 0209 después
--      de que la primera versión de esta cabecera prometiera lo contrario.
--
-- Con los datos de producción del 2026-08-10 las dos juntas bloquean **0 de 8**
-- casos reales: ninguna de las ocho personas inactivas tiene hijos ni sueldo
-- fijo.
--
--   ⚠️ ESA LISTA HAY QUE REVISARLA. Dice «qué se paga sin mirar las horas que
--   trabajó». Hoy son dos cosas. El día que se agregue un tercer concepto así,
--   estas condiciones se quedan cortas sin avisar.
--
-- ── LO QUE NO HACE, Y ES DELIBERADO ─────────────────────────────────────────
--
--   · NO devuelve la educación. El trigger `trg_educacion_cerrar_al_cesar`
--     (0149) también cierra `asignaciones_educacion`, pero su fila de auditoría
--     guarda **solo el conteo** de tramos cerrados, no las fechas originales:
--     la vigencia anterior ya no existe en ninguna parte y no se puede
--     restituir. Recargarla a mano es el único camino, y por eso el aviso de la
--     pantalla de Equipo tiene que seguir existiendo.
--   · NO toca `fn_cesar_persona`.
--   · NO arregla a quien ya fue reactivado antes de esta migración. No se puede:
--     la reactivación pone `fecha_cese` en null, así que la fecha con la que se
--     cerraron sus tramos ya no está escrita en ninguna parte. Medido en
--     producción el 2026-08-10: **no hay nadie en ese estado** — las 4 personas
--     activas sin tramo abierto lo están por motivos legítimos (los tres RxH no
--     llevan horario desde la 0191, y la cuarta es dirección).
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Volver a crear la función con el cuerpo de la 0086. Revertir significa
--   volver a dejar que quien se reactiva cobre S/0.00.
-- ============================================================================

create or replace function public.fn_reactivar_persona(p_persona_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_cese      date;
  v_hijos     boolean;
  v_fijo      boolean;
  v_hoy       date := (now() at time zone 'America/Lima')::date;
  v_actor     uuid;
  v_desde     date;
  v_sal       record;
  v_hor       record;
  v_n_sal     int := 0;
  v_n_hor     int := 0;
  r           record;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede reactivar a una persona.';
  end if;

  -- La fecha de cese se LEE ANTES del update, porque el update la borra. Es la
  -- llave con la que se reconoce qué tramos cerró ese cese. El orden importa:
  -- si algún día un refactor mueve el update arriba, esto compararía contra
  -- null, no encontraría nada y fallaría EN SILENCIO.
  select fecha_cese, con_hijos, sueldo_fijo into v_cese, v_hijos, v_fijo
    from personas
   where id = p_persona_id and estado = 'inactivo'
   for update;
  if not found then
    raise exception 'Esa persona no existe o ya está activa.';
  end if;

  -- ── Los dos candados: donde reactivar movería plata que no se trabajó ─────
  -- Ver la cabecera. Los dos son ESTRECHOS a propósito: de las 8 personas
  -- inactivas de producción, seis tienen un periodo pagado detrás y para las
  -- seis el daño es cero. Un candado ancho rechazaría seis reactivaciones
  -- legítimas de ocho, y eso no protege: prohíbe.

  -- 1 · La asignación familiar se paga por tener hijos, sin mirar tramos ni
  --     jornadas. Volver a 'activo' basta para que aparezca en una planilla ya
  --     pagada. Medido: S/98.31 por periodo.
  if v_hijos is true and exists (
       select 1 from periodos_planilla
        where estado = 'pagado' and fecha_fin >= v_cese) then
    raise exception
      'Reactivarla ahora cambiaría el total de una planilla YA PAGADA: cobra asignación familiar, '
      'y esa se paga por tener hijos, sin depender de si trabajó. Reabre primero el periodo con '
      'Revertir pago, que deja constancia del motivo.';
  end if;

  -- 2 · El sueldo fijo cobra el periodo COMPLETO con que un tramo suyo roce el
  --     periodo: `fn_planilla_calcular` no prorratea esa rama. Reactivar a
  --     mitad de mes le entrega el mes entero — medido, S/1,130.00 sin un solo
  --     día trabajado, más S/196.81 de provisiones y S/101.70 de EsSalud.
  --     No se prorratea aquí: eso es un cambio en `fn_planilla_calcular` que
  --     movería también a quien INGRESA a mitad de periodo, y esa es una
  --     decisión aparte (Crítico 1 del catálogo, que Felipe ya evaluó una vez).
  --     Aquí se para y se dice qué hacer.
  if v_fijo is true and exists (
       select 1 from periodos_planilla
        where fecha_fin >= v_cese and fecha_ini <= v_hoy) then
    raise exception
      'Tiene sueldo fijo, y el sueldo fijo se paga por periodo completo en cuanto tiene un tramo '
      'que lo toque: reactivarla hoy le pagaría el periodo entero sin haberlo trabajado. '
      'Reactívala el primer día del periodo siguiente, o hazlo igual y registra el ajuste como '
      'movimiento con su motivo.';
  end if;

  update personas
     set estado = 'activo', fecha_cese = null, motivo_cese = null,
         fecha_estado_cambio = now()
   where id = p_persona_id;

  v_actor := coalesce(fn_persona_actual_id(), p_persona_id);

  -- ── El salario vuelve, desde hoy ──────────────────────────────────────────
  -- Solo si NO tiene ya un tramo abierto: entre el cese y la reactivación
  -- alguien pudo asignarle salario —`fn_set_salario` no mira `personas.estado`,
  -- pese a lo que dice la cabecera de la 0176, que en eso es una errata—. Si ya
  -- lo tiene, el suyo manda y aquí no se toca nada.
  -- La pregunta es «¿le llega algún tramo hasta hoy?», NO «¿tiene alguno
  -- abierto?». No es lo mismo, y la diferencia la cazó la prueba 173: un tramo
  -- CERRADO el 2099-12-31 está vigente hoy igual que uno sin fecha de fin, y es
  -- así como `fn_planilla_calcular` elige el suyo. Preguntando solo por
  -- `vigente_hasta is null` no se veía, y se le creaba un tramo encima que —para
  -- no chocar con el antisolape— arrancaba en el año 2100: no le devolvía el
  -- sueldo, se lo prometía para dentro de setenta y seis años.
  --
  -- Con esta condición, si nada le llega a hoy es que todos sus tramos
  -- terminaron ANTES de hoy, así que uno nuevo desde hoy no puede solaparse con
  -- ninguno y el EXCLUDE `asignacion_salario_sin_solape` no tiene nada que decir.
  if not exists (select 1 from asignaciones_salario
                  where persona_id = p_persona_id
                    and (vigente_hasta is null or vigente_hasta > v_hoy)) then

    select a.rango, a.salario_mensual_soles, a.base_provision
      into v_sal
      from asignaciones_salario a
     where a.persona_id = p_persona_id and a.vigente_hasta = v_cese
     order by a.vigente_desde desc
     limit 1;

    if found then
      -- Nunca encima de un tramo que ya termina hoy. Cuando el cese es de HOY
      -- —el caso más probable, porque un cese por error se nota el mismo día—
      -- `fn_cesar_persona` acaba de cerrar el tramo con `vigente_hasta = hoy`,
      -- y el EXCLUDE `asignacion_salario_sin_solape` usa un daterange con los
      -- dos extremos cerrados: arrancar hoy chocaría contra él. Se restituye
      -- desde MAÑANA, y el día del cese queda cubierto por el tramo viejo, que
      -- es lo correcto: ese día sí trabajó.
      select greatest(v_hoy, max(a.vigente_hasta) + 1)
        into v_desde
        from asignaciones_salario a
       where a.persona_id = p_persona_id;

      insert into asignaciones_salario
        (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta,
         asignado_por, nota, base_provision)
      values
        (p_persona_id, v_sal.rango, v_sal.salario_mensual_soles, v_desde, null,
         v_actor, 'Reactivación: vuelve con el salario que tenía al cesar.', v_sal.base_provision);
      v_n_sal := 1;

      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (p_persona_id, 'salario_al_reactivar',
         'sin tramo vigente desde el cese del ' || v_cese::text,
         'S/ ' || v_sal.salario_mensual_soles::text || ' vigente desde ' || v_desde::text,
         v_actor,
         'Reactivación: se le devuelve el salario desde el día que vuelve, no desde el cese.');
    end if;
  end if;

  -- ── El horario vuelve, desde hoy ──────────────────────────────────────────
  -- Se copian las columnas en vez de delegar en `fn_set_horario_semanal`:
  -- esa función exige un jsonb, y `horario_por_dia` es NULLABLE — los tramos
  -- viejos la tienen vacía y delegar fallaría justo con los más antiguos.
  -- Misma pregunta que con el salario, y por el mismo motivo.
  if not exists (select 1 from horarios_asignados
                  where persona_id = p_persona_id
                    and (vigente_hasta is null or vigente_hasta > v_hoy)) then

    select h.hora_entrada, h.hora_salida, h.almuerzo_min_minutos, h.almuerzo_max_minutos,
           h.dias_laborables, h.horas_semana_objetivo, h.horario_por_dia
      into v_hor
      from horarios_asignados h
     where h.persona_id = p_persona_id and h.vigente_hasta = v_cese
     order by h.vigente_desde desc
     limit 1;

    if found then
      select greatest(v_hoy, max(h.vigente_hasta) + 1)
        into v_desde
        from horarios_asignados h
       where h.persona_id = p_persona_id;

      insert into horarios_asignados
        (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
         almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables,
         horas_semana_objetivo, horario_por_dia)
      values
        (p_persona_id, v_desde, null, v_hor.hora_entrada, v_hor.hora_salida,
         v_hor.almuerzo_min_minutos, v_hor.almuerzo_max_minutos, v_hor.dias_laborables,
         v_hor.horas_semana_objetivo, v_hor.horario_por_dia);
      v_n_hor := 1;

      -- Devolver el horario sin recalcular es devolver la mitad del hecho: si
      -- ya marcó hoy, su jornada se midió contra un horario que no existía.
      -- Solo desde `v_desde` hacia adelante — el hueco NO se toca a propósito.
      for r in select j.fecha from jornadas j
                where j.persona_id = p_persona_id and j.fecha >= v_desde loop
        perform fn_recalcular_jornada(p_persona_id, r.fecha);
      end loop;

      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (p_persona_id, 'horario_al_reactivar',
         'sin horario vigente desde el cese del ' || v_cese::text,
         'horario restituido desde ' || v_desde::text,
         v_actor,
         'Reactivación: se le devuelve el horario desde el día que vuelve, no desde el cese.');
    end if;
  end if;

  -- ── Cero filas es un resultado legítimo, y también es el resultado roto ────
  -- Legítimo: le corrigieron el sueldo estando inactiva, o nunca tuvo horario
  -- (los RxH no llevan, desde la 0191). Roto: se cesó, se reactivó sin que esto
  -- existiera, y se volvió a cesar — el segundo cese no cerró nada, así que no
  -- hay nada que copiar. Los dos casos se ven iguales desde aquí, y callarse
  -- sería apagar la sospecha. Queda escrito para que alguien lo mire.
  if v_n_sal = 0 then
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (p_persona_id, 'reactivacion_sin_salario_que_devolver',
       'cese del ' || coalesce(v_cese::text, '—'), 'sigue sin salario vigente', v_actor,
       'Reactivación: no se encontró un tramo cerrado por ese cese. Hay que asignarle salario a mano.');
  end if;
end;
$function$;

comment on function public.fn_reactivar_persona(uuid) is
  'Reactiva a quien se cesó y le devuelve salario y horario DESDE EL DÍA QUE VUELVE, con un tramo '
  'nuevo — nunca reabriendo el viejo, que cubriría el hueco hacia atrás y reescribiría planillas ya '
  'pagadas. No devuelve la educación: el cese no guardó su vigencia original. Deja rastro en '
  'correcciones_auditoria, incluso cuando no encuentra nada que devolver.';

insert into migraciones_aplicadas (numero, nombre)
values (209, 'reactivar_devuelve_el_sueldo_desde_el_dia_que_vuelve')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
