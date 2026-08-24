-- ============================================================================
-- 0281 — El techo de educación se reparte entre los estudios, y sigue al rango.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1 · Que un segundo comprobante que no cabe entero bajo el techo se pueda
--       registrar por el saldo que queda, en vez de rebotar entero.
--   2 · Que el techo deje de ser una foto del día que se cargó el papel: si el
--       rango cambia, la asignación se realinea sola —hacia abajo y hacia
--       arriba— desde el primer periodo que todavía no se pagó.
--   3 · Que el candado del techo nunca impida ARREGLAR: bajar un monto que ya
--       está por encima del techo tiene que poder hacerse, y hoy no se puede.
--
-- POR QUÉ, CON EL CASO QUE LO MOTIVÓ
--
--   Rango cayla, techo S/180. La colaboradora estudia (pensión S/200 → el 75 %
--   son S/150) y su hija también (colegio S/200 → S/150). La segunda fila suma
--   300 contra un techo de 180 y el trigger de la 0149 la rechaza. Como el monto
--   NO se teclea —lo calcula el sistema desde la 0149—, DO no tiene manera de
--   registrar el segundo comprobante: ni entero ni parcial. Los S/30 que
--   quedaban libres bajo el techo no los podía usar nadie, y el papel de la hija
--   se quedaba fuera del sistema.
--
--   Decidido por Felipe el 2026-08-22: se paga el saldo. El monto pasa a ser
--
--       min( costo × 75 % , techo − lo que ya usan las asignaciones que se
--                                    SOLAPAN con esas fechas )
--
--   Sigue sin poder pagar más de lo que el comprobante sostiene —ese es el
--   candado legal (CHECK `educacion_no_excede_el_comprobante`, 0120)— y ahora
--   tampoco deja libre un pedazo de techo por no saber repartirlo.
--
--   Y no contradice a la 0132. Lo que aquella prohibió es un monto que sale de
--   una RESTA PARA CUADRAR EL NETO: pagar de más y llamarlo educación. Acá la
--   resta solo puede bajar la cifra: el comprobante siempre sostiene más de lo
--   que se paga, que es el lado seguro de la regla.
--
--   El orden es el de registro (`created_at`), no a prorrata: la primera
--   asignación conserva su monto y la siguiente se queda con el saldo. Es el
--   mismo criterio que rige el alta —quien llega segundo recibe lo que queda—,
--   y un solo criterio es uno que se puede explicar en una sala.
--
-- POR QUÉ EL TECHO AHORA SIGUE AL RANGO
--
--   La 0132 lo dejó abierto a propósito: «si a una persona la bajan de rango con
--   una asignación ya vigente, esa asignación queda por encima del techo nuevo
--   hasta que se la toque». En la práctica nadie la toca —no hay pantalla que lo
--   avise— y el techo de política se vuelve una foto del día que se cargó el
--   papel. Decidido por Felipe el 2026-08-22: se realinea sola, en las dos
--   direcciones, porque el monto «es una consecuencia del comprobante y del
--   rango» (0149) y una consecuencia que solo se actualiza cuando alguien se
--   acuerda no es una consecuencia.
--
--   Nunca reescribe lo ya pagado: rige desde `fn_educacion_desde_cuando_puede_regir()`
--   —el primer día que no cae en un periodo pagado—, y si la fila venía de antes
--   se cierra el día anterior y nace una nueva, que es exactamente lo que hace
--   una corrección a mano desde la 0149. Todo movimiento deja rastro en
--   `correcciones_auditoria` con el motivo escrito.
--
-- POR QUÉ EL CANDADO PASA A MIRAR SI EMPEORA, Y NO SOLO SI PASA
--
--   El trigger de la 0149 rechaza cualquier fila cuya suma pase el techo. Con un
--   techo que ya se pasó —porque bajó el rango— eso hace imposible el arreglo:
--   bajar de S/150 a S/90 con otra fila de S/150 vigente sigue sumando 240 sobre
--   un techo de 90, y el candado rechaza el intento de arreglarlo pidiendo…
--   subir el techo. Un guardián que impide reparar el daño que él detecta.
--
--   Ahora la condición es: se rechaza si pasa el techo Y ADEMÁS la suma SUBE.
--   Para un alta es idéntico a lo de hoy (lo que entra siempre suma). Para una
--   corrección hacia abajo, deja arreglar. El techo sigue siendo infranqueable
--   hacia arriba, que es lo único que tenía que impedir.
--
-- MD5 DE PARTIDA — pedidos a PRODUCCIÓN el 2026-08-22, no al Postgres local
--
--   fn_educacion_monto            3c8e59c3d476a7c2335f0497c3caaad6   (0149)
--   fn_educacion_registrar        468ac92ce5cdcfff0331e40da1fab210   (0149)
--   fn_educacion_candidatos       906b7714b5c859e2d2f62dd4637e5de6   (0136)
--   fn_educacion_respeta_el_tope  2e58508026b474248e9dba065239614f   (0151)
--
--   Los tres primeros son los que esta migración esperaba. El cuarto NO: esta
--   migración se había escrito copiando el trigger de la 0149, y producción
--   corre el de la **0151**, que le agregó `security definer` cuando puso RLS
--   sobre `topes_educacion_rango`. Pegarla así habría apagado el candado del
--   techo en silencio — el trigger habría dejado de ver la tabla y su regla de
--   fallar abierto lo habría leído como «este rango no tiene techo».
--
-- QUÉ ASUME
--
--   · `asignaciones_educacion` con su CHECK del comprobante (0120), el techo por
--     rango (0132), las nueve reglas de la 0149 —de la que se copia el cuerpo de
--     `fn_educacion_registrar`— y la 0151, de la que se copia el trigger.
--   · `fn_educacion_desde_cuando_puede_regir()` y `fn_educacion_fecha_pagada()`
--     (0149), `fn_persona_actual_id()` (0078), `fn_es_admin_o_lider()`.
--   · Que `fn_set_salario` sigue impidiendo cambiar un salario dentro de un
--     periodo pagado (0037): por eso la realineación puede confiar en que el
--     cambio de rango cae siempre en terreno todavía no pagado.
--
-- QUÉ MUEVE AL PEGARSE
--
--   Nada por sí sola: no recorre las filas existentes. La realineación se
--   dispara cuando alguien cambia un rango DESPUÉS de esta migración. Las filas
--   que hoy estén por encima de su techo siguen igual hasta que se toque su
--   rango o se corrija a mano — y eso último, desde ahora, se puede.
--
-- CÓMO SE REVIERTE
--
--   drop trigger trg_educacion_sigue_al_rango on asignaciones_salario;
--   drop function fn_educacion_sigue_al_rango();
--   drop function fn_educacion_realinear(uuid, date);
--   drop function fn_educacion_monto(uuid, numeric, date, date, uuid);
--   drop function fn_educacion_saldo(uuid, date, date, uuid);
--   drop function fn_educacion_tope(uuid, date);
--   -- y volver a pegar de la 0149: fn_educacion_monto(uuid,numeric),
--   -- fn_educacion_registrar(...) y fn_educacion_respeta_el_tope();
--   -- y de la 0136: fn_educacion_candidatos().
--   Ninguna fila se borra al revertir.
-- ============================================================================


-- ── A · El techo de una persona en una fecha ────────────────────────────────
-- Escrito una sola vez porque lo preguntan dos: el saldo (abajo) y la
-- realineación por cambio de rango (más abajo). El techo se lee del rango
-- vigente EN esa fecha, no del tramo abierto: una asignación que empieza en
-- octubre tiene que medirse contra el rango que la persona tendrá en octubre.
-- Si en esa fecha no hay tramo —aún no tiene salario cargado— se cae al tramo
-- abierto, para no dejar sin techo un alta normal.
--
-- `null` significa «no hay techo que aplicar»: la persona no tiene rango, o su
-- rango no tiene techo cargado. Falla abierto igual que la 0132, porque un techo
-- de política que bloquea por falta de configuración deja a alguien sin cobrar
-- lo que ya justificó.
create or replace function fn_educacion_tope(p_persona_id uuid, p_fecha date)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select t.tope_mensual
       from asignaciones_salario a
       join topes_educacion_rango t on t.rango = a.rango
      where a.persona_id = p_persona_id
        and a.vigente_desde <= p_fecha
        and (a.vigente_hasta is null or a.vigente_hasta >= p_fecha)
      order by a.vigente_desde desc
      limit 1),
    (select t.tope_mensual
       from asignaciones_salario a
       join topes_educacion_rango t on t.rango = a.rango
      where a.persona_id = p_persona_id
        and a.vigente_hasta is null
      order by a.vigente_desde desc
      limit 1));
$$;

grant execute on function fn_educacion_tope(uuid, date) to authenticated;


-- ── B · Cuánto techo queda libre en unas fechas ─────────────────────────────
-- El dato que faltaba, y el que la pantalla necesita para no prometer un monto
-- que la base va a rechazar. `null` = no hay techo y manda el comprobante.
create or replace function fn_educacion_saldo(
  p_persona_id uuid,
  p_desde      date,
  p_hasta      date,
  p_excluir    uuid default null
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tope  numeric;
  v_usado numeric;
begin
  -- Guard: cuánto estudia una persona y cuánto cobra por ello es dato de DO.
  -- `is not true` y no `not (...)`: un null no debe pasar como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional consulta el techo de educación.';
  end if;

  v_tope := fn_educacion_tope(p_persona_id, p_desde);

  if v_tope is null then
    return null;   -- sin rango o sin techo cargado: manda el comprobante
  end if;

  -- Lo que ya usan las asignaciones que se solapan con estas fechas. Dos cursos
  -- en meses distintos no compiten por el mismo techo; dos en el mismo mes sí.
  select coalesce(sum(e.monto), 0) into v_usado
    from asignaciones_educacion e
   where e.persona_id = p_persona_id
     and (p_excluir is null or e.id <> p_excluir)
     and e.vigente_desde <= p_hasta
     and e.vigente_hasta >= p_desde;

  -- Nunca negativo: una fila heredada por encima del techo (rango bajado antes
  -- de esta migración) diría «quedan S/-120», que no significa nada en pantalla.
  return greatest(v_tope - v_usado, 0);
end;
$$;

grant execute on function fn_educacion_saldo(uuid, date, date, uuid) to authenticated;

comment on function fn_educacion_saldo(uuid, date, date, uuid) is
  'Techo de educación que le queda libre a una persona en un tramo de fechas. '
  'null = no hay techo que aplicar y manda el comprobante. Es la única cuenta '
  'del saldo: la pantalla la pregunta, no la reimplementa.';


-- ── C · El monto, que ahora sabe del saldo ──────────────────────────────────
-- Cambia la firma: sin las fechas no se puede saber contra qué otras
-- asignaciones compite, y sin `p_excluir` una corrección competiría consigo
-- misma. Se BORRA la de dos argumentos en vez de dejarla: dos puertas para la
-- misma cuenta es cómo se fabrican las dos versiones que después discrepan.
drop function if exists fn_educacion_monto(uuid, numeric);

create or replace function fn_educacion_monto(
  p_persona_id uuid,
  p_costo      numeric,
  p_desde      date,
  p_hasta      date,
  p_excluir    uuid default null
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select least(
    round(p_costo * 75 / 100.0, 2),
    coalesce(
      fn_educacion_saldo(p_persona_id, p_desde, p_hasta, p_excluir),
      round(p_costo * 75 / 100.0, 2)));   -- sin techo: manda el 75 %
$$;

grant execute on function fn_educacion_monto(uuid, numeric, date, date, uuid) to authenticated;


-- ── D · El candado deja de impedir el arreglo ───────────────────────────────
-- Copiado de la **0151**, no de la 0149, y esa distinción casi cuesta el candado
-- entero: la 0151 le puso `security definer` porque en esa misma migración
-- `topes_educacion_rango` pasó a tener RLS. Sin definer, el trigger deja de VER
-- el tope y su primera regla —«sin tope cargado, dejo pasar»— lo lee como «no hay
-- techo». El candado se apaga solo, en silencio, y nadie se entera hasta que
-- alguien cobre de más. Se descubrió pidiendo el md5 a producción: 2e585080…
-- (0151) contra 476f663c… (0149), 16 caracteres de diferencia.
--
-- Con una sola condición nueva. Antes: «si la suma pasa el
-- techo, rechaza». Ahora: «si la suma pasa el techo Y ADEMÁS sube, rechaza».
-- Para un alta es lo mismo de siempre. Para una corrección hacia abajo, es la
-- diferencia entre poder arreglar una fila heredada y no poder.
create or replace function fn_educacion_respeta_el_tope()
returns trigger
language plpgsql
security definer          -- ⇦ de la 0151, y NO es decorativo: ver arriba
set search_path = public
as $$
declare
  v_rango  text;
  v_tope   numeric;
  v_otros  numeric;
  v_previo numeric;
begin
  -- La realineación (sección F) mueve VARIAS filas para llegar a un estado final
  -- que sí respeta el techo, y en el camino pasa por estados intermedios que no
  -- lo respetan — bajar la primera fila mientras la segunda todavía está alta.
  -- Este candado juzga una fila contra una foto, así que no puede juzgar eso:
  -- rechazaría el arreglo a mitad de camino. Le cede el paso, y a cambio la
  -- realineación comprueba el estado final ELLA MISMA, día por día, que es una
  -- comprobación más estricta que ésta.
  --
  -- La marca es de transacción (`is_local` = true en set_config): no sobrevive a
  -- la llamada, así que nadie puede dejarla puesta para saltarse el techo.
  if current_setting('cayla.educacion_realineando', true) is not distinct from '1' then
    return new;
  end if;

  select a.rango into v_rango
    from asignaciones_salario a
   where a.persona_id = new.persona_id
     and a.vigente_hasta is null
   order by a.vigente_desde desc
   limit 1;

  if v_rango is null then
    return new;  -- sin rango vigente no hay techo que aplicar
  end if;

  select t.tope_mensual into v_tope
    from topes_educacion_rango t
   where t.rango = v_rango;

  if v_tope is null then
    return new;  -- rango sin techo cargado: falla abierto a propósito
  end if;

  -- Las OTRAS asignaciones de esa persona cuya vigencia se solapa con la de la
  -- fila que entra. Se excluye la propia fila para que corregir no se sume a sí
  -- misma (0149).
  select coalesce(sum(a.monto), 0) into v_otros
    from asignaciones_educacion a
   where a.persona_id   = new.persona_id
     and a.id          <> new.id
     and a.vigente_desde <= new.vigente_hasta
     and a.vigente_hasta >= new.vigente_desde;

  -- Lo que esta misma fila aportaba antes del cambio. En un alta es cero, y por
  -- eso un alta que pase el techo se sigue rechazando igual que siempre.
  v_previo := case
                when tg_op = 'UPDATE' and old.persona_id = new.persona_id then old.monto
                else 0
              end;

  if v_otros + new.monto > v_tope and new.monto > v_previo then
    raise exception
      'La suma de las asignaciones por educación de esta persona (S/%) supera el tope '
      'del rango % (S/%). Ya tiene S/% vigente en esas fechas. Cierra la otra asignación, '
      'ajusta las fechas, o sube el tope en topes_educacion_rango si la política cambió.',
      to_char(v_otros + new.monto, 'FM999999.00'), v_rango,
      to_char(v_tope, 'FM999999.00'), to_char(v_otros, 'FM999999.00');
  end if;

  return new;
end;
$$;


-- ── E · Registrar y corregir: el monto ahora se calcula con las fechas ──────
-- Cuerpo de la 0149 con tres cambios y ni uno más:
--   · las dos llamadas a `fn_educacion_monto` pasan las fechas y el id de la
--     fila que se corrige, para que compita contra las otras y no contra sí
--     misma;
--   · si el saldo del techo es cero, se rechaza con un mensaje que dice por qué,
--     en vez de guardar una fila de S/0 que no paga nada y que nadie entendería
--     al verla en la lista;
--   · la fila que nace de una corrección hereda el `created_at` de la que
--     reemplaza, porque desde esta migración ese campo decide el orden en que
--     las asignaciones se reparten el techo.
create or replace function fn_educacion_registrar(
  p_persona_id          uuid,
  p_institucion         text,
  p_costo_declarado     numeric,
  p_beneficiario        text,
  p_vigente_desde       date,
  p_vigente_hasta       date,
  p_beneficiario_nombre text default null,
  p_comprobante_url     text default null,
  p_nota                text default null,
  p_id                  uuid default null,   -- no nulo = corregir
  p_motivo              text default null    -- obligatorio al corregir
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id       uuid;
  v_yo       uuid := fn_persona_actual_id();
  v_monto    numeric;
  v_vieja    asignaciones_educacion%rowtype;
  v_mueve    boolean;
  v_desde    date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra asignaciones por educación.';
  end if;

  if p_institucion is null or length(trim(p_institucion)) < 3 then
    raise exception 'Falta la institución que emite el comprobante.';
  end if;
  if p_beneficiario not in ('trabajador', 'hijo') then
    raise exception 'El beneficiario es «trabajador» o «hijo» (llegó «%»).', p_beneficiario;
  end if;
  if p_beneficiario = 'hijo'
     and (p_beneficiario_nombre is null or length(trim(p_beneficiario_nombre)) < 3) then
    raise exception 'Si el comprobante es de un hijo, escribe a nombre de quién está.';
  end if;
  if p_costo_declarado is null or p_costo_declarado <= 0 then
    raise exception 'El costo que dice el comprobante tiene que ser mayor que cero.';
  end if;
  if p_vigente_hasta is null then
    raise exception 'Falta hasta cuándo vale el comprobante. Una matrícula cubre un ciclo, no la eternidad.';
  end if;
  if p_vigente_hasta < p_vigente_desde then
    raise exception 'La fecha de fin (%) es anterior a la de inicio (%).', p_vigente_hasta, p_vigente_desde;
  end if;

  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no existe o no está activa.';
  end if;

  -- ⇩ CAMBIO 0281 ⇩ con las fechas y excluyendo la fila que se corrige.
  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado,
                                p_vigente_desde, p_vigente_hasta, p_id);

  if v_monto <= 0 then
    raise exception
      'No queda techo libre para esas fechas: las asignaciones que ya tiene vigentes '
      'agotan el tope de su rango. Cierra o acorta la otra asignación, mueve estas '
      'fechas, o sube el tope en topes_educacion_rango si la política cambió.';
  end if;

  -- ── Alta ────────────────────────────────────────────────────────────────
  if p_id is null then
    if fn_educacion_fecha_pagada(p_vigente_desde) is true then
      raise exception
        'Esa fecha de inicio (%) cae en un periodo ya PAGADO: registrarla cambiaría una '
        'planilla cerrada. Registra desde el periodo abierto, o reabre el periodo primero.',
        p_vigente_desde;
    end if;

    insert into asignaciones_educacion (
      persona_id, monto, institucion, costo_declarado, cobertura_pct,
      beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
      comprobante_url, nota, registrado_por
    ) values (
      p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
      p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      p_vigente_desde, p_vigente_hasta,
      p_comprobante_url, nullif(trim(coalesce(p_nota, '')), ''), v_yo
    )
    returning id into v_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (p_persona_id, 'educacion_alta', null,
       trim(p_institucion) || ' · S/' || to_char(v_monto, 'FM999999.00') ||
       ' · ' || p_vigente_desde::text || ' a ' || p_vigente_hasta::text,
       v_yo, coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Alta de asignación por educación'));

    return v_id;
  end if;

  -- ── Corrección ──────────────────────────────────────────────────────────
  select * into v_vieja from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se corrige. Esto mueve lo que cobra una persona.';
  end if;

  -- ¿La corrección mueve plata? Sólo el costo y las fechas lo hacen. Cambiar el
  -- nombre de la institución o subir el comprobante que faltaba no cambia un
  -- céntimo, y obligar a abrir vigencia nueva por eso llenaría la lista de filas
  -- cerradas por erratas.
  v_mueve := (v_vieja.costo_declarado is distinct from p_costo_declarado)
          or (v_vieja.vigente_desde   is distinct from p_vigente_desde)
          or (v_vieja.vigente_hasta   is distinct from p_vigente_hasta)
          or (v_vieja.persona_id      is distinct from p_persona_id);

  if not v_mueve then
    update asignaciones_educacion set
      institucion         = trim(p_institucion),
      beneficiario        = p_beneficiario,
      beneficiario_nombre = nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      -- null no borra el comprobante ya cargado: se enlaza en un segundo paso,
      -- después de que el archivo terminó de subir.
      comprobante_url     = coalesce(p_comprobante_url, comprobante_url),
      nota                = nullif(trim(coalesce(p_nota, '')), '')
    where id = p_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_vieja.persona_id, 'educacion_datos', v_vieja.institucion,
       trim(p_institucion), v_yo, trim(p_motivo));

    return p_id;
  end if;

  -- Mueve plata: la fila vieja se cierra el día anterior al que rige el cambio y
  -- nace una nueva. Lo ya pagado queda escrito tal como se pagó.
  v_desde := greatest(fn_educacion_desde_cuando_puede_regir(), v_vieja.vigente_desde);

  if fn_educacion_fecha_pagada(v_desde) is true then
    raise exception
      'No hay ningún periodo abierto desde el que aplicar esta corrección: todos los que '
      'tocan esta asignación están pagados. Reabre el periodo primero.';
  end if;

  -- ⇩ CAMBIO 0281 ⇩ el tramo que de verdad va a regir, no el que se escribió.
  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado,
                                greatest(v_desde, p_vigente_desde), p_vigente_hasta, p_id);

  if v_monto <= 0 then
    raise exception
      'No queda techo libre para esas fechas: las asignaciones que ya tiene vigentes '
      'agotan el tope de su rango. Cierra o acorta la otra asignación, mueve estas '
      'fechas, o sube el tope en topes_educacion_rango si la política cambió.';
  end if;

  if v_desde > v_vieja.vigente_desde then
    update asignaciones_educacion
       set vigente_hasta = v_desde - 1
     where id = p_id;
  else
    -- La fila vieja nunca llegó a devengar en un periodo pagado: se reemplaza
    -- entera en vez de dejar un tramo de un día que no significa nada.
    delete from asignaciones_educacion where id = p_id;
  end if;

  -- ⇩ CAMBIO 0281 ⇩ `created_at` viaja con la fila. Desde esta migración ese
  -- campo decide el orden en que las asignaciones se reparten el techo, así que
  -- corregir una no puede mandarla al final de la cola.
  insert into asignaciones_educacion (
    persona_id, monto, institucion, costo_declarado, cobertura_pct,
    beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
    comprobante_url, nota, registrado_por, created_at
  ) values (
    p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
    p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
    greatest(v_desde, p_vigente_desde), p_vigente_hasta,
    coalesce(p_comprobante_url, v_vieja.comprobante_url),
    nullif(trim(coalesce(p_nota, '')), ''), v_yo, v_vieja.created_at
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'educacion_nueva_vigencia',
     'S/' || to_char(v_vieja.monto, 'FM999999.00') || ' desde ' || v_vieja.vigente_desde::text,
     'S/' || to_char(v_monto, 'FM999999.00') || ' desde ' || greatest(v_desde, p_vigente_desde)::text,
     v_yo, trim(p_motivo));

  return v_id;
end;
$$;

grant execute on function fn_educacion_registrar(uuid,text,numeric,text,date,date,text,text,text,uuid,text)
  to authenticated;


-- ── F · La realineación: el techo deja de ser una foto ──────────────────────
-- Recalcula las asignaciones de educación vivas de una persona contra el techo
-- que rige desde `p_desde`, en orden de registro, y aplica solo las que cambian.
--
-- TRES COSAS QUE HACE Y CONVIENE LEER ANTES DE TOCARLA:
--
--   · No reescribe lo pagado. Rige desde el primer día que no cae en un periodo
--     pagado; si la fila venía de antes, se cierra el día anterior y nace una
--     nueva. Es el mismo movimiento que hace una corrección a mano (0149), y por
--     eso la foto del pago (0096) sigue cuadrando con lo que se pagó.
--
--   · Baja primero y sube después, y con el candado de la sección D en pausa.
--     Mover varias filas obliga a pasar por estados intermedios que no respetan
--     el techo —bajar una mientras la otra sigue alta—, y ese candado juzga una
--     fila contra una foto. A cambio, acá se comprueba el estado FINAL día por
--     día, que es más estricto que él: el techo es mensual y se comparte, así
--     que lo que no puede pasar es que en un día cualquiera la suma lo supere.
--     La pausa es una marca de transacción: no sobrevive a la llamada.
--
--   · Solapamiento, no calendario. El saldo que consume cada fila solo cuenta
--     las ANTERIORES que comparten fechas con ella: dos cursos en meses
--     distintos no compiten por el mismo techo.
--
-- Devuelve cuántas filas movió, que es lo que hace fácil probarla.
create or replace function fn_educacion_realinear(
  p_persona_id uuid,
  p_desde      date,
  p_actor      uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_desde    date;
  v_tope     numeric;
  v_actor    uuid;
  v_plan     jsonb := '[]'::jsonb;
  v_usado    numeric;
  v_objetivo numeric;
  v_movidas  integer := 0;
  v_pasada   integer;
  r          record;
  e          asignaciones_educacion%rowtype;
begin
  v_desde := greatest(p_desde, fn_educacion_desde_cuando_puede_regir());
  v_tope  := fn_educacion_tope(p_persona_id, v_desde);

  -- Sin techo no hay nada que realinear, y bajar montos por una configuración
  -- que falta sería justo lo contrario de lo que la 0132 decidió.
  if v_tope is null then
    return 0;
  end if;

  -- 1 · El plan, en orden de registro. Cada fila se queda con lo que el
  --     comprobante sostiene, hasta donde el techo alcance después de las que
  --     se registraron antes y comparten fechas con ella.
  for r in
    select x.id, x.monto, x.costo_declarado,
           greatest(x.vigente_desde, v_desde) as desde,
           x.vigente_hasta                    as hasta
      from asignaciones_educacion x
     where x.persona_id = p_persona_id
       and x.vigente_hasta >= v_desde
     order by x.created_at, x.id
  loop
    select coalesce(sum((y->>'objetivo')::numeric), 0) into v_usado
      from jsonb_array_elements(v_plan) y
     where (y->>'desde')::date <= r.hasta
       and (y->>'hasta')::date >= r.desde;

    v_objetivo := least(round(r.costo_declarado * 75 / 100.0, 2),
                        greatest(v_tope - v_usado, 0));

    v_plan := v_plan || jsonb_build_object(
      'id', r.id, 'objetivo', v_objetivo, 'actual', r.monto,
      'desde', r.desde, 'hasta', r.hasta);
  end loop;

  v_actor := coalesce(p_actor, fn_persona_actual_id(), p_persona_id);

  -- 2 · Aplicar: primero las bajadas, después las subidas.
  perform set_config('cayla.educacion_realineando', '1', true);
  for v_pasada in 1..2 loop
    for r in
      select (y->>'id')::uuid       as id,
             (y->>'objetivo')::numeric as objetivo
        from jsonb_array_elements(v_plan) y
       where (v_pasada = 1 and (y->>'objetivo')::numeric < (y->>'actual')::numeric)
          or (v_pasada = 2 and (y->>'objetivo')::numeric > (y->>'actual')::numeric)
    loop
      select * into e from asignaciones_educacion where id = r.id;
      if not found then continue; end if;

      if e.vigente_desde >= v_desde then
        -- Nunca devengó en un periodo pagado: se corrige en su sitio.
        update asignaciones_educacion set monto = r.objetivo where id = e.id;
      else
        update asignaciones_educacion set vigente_hasta = v_desde - 1 where id = e.id;

        -- `created_at` VIAJA con la fila, y no es un detalle: es lo que define
        -- el orden de reparto del techo. Si la fila que continúa naciera con la
        -- fecha de hoy, cada realineación cambiaría quién tiene prioridad y el
        -- reparto dejaría de ser estable. La fila es la misma asignación
        -- siguiendo su curso; el rastro de que se partió está en la auditoría.
        insert into asignaciones_educacion (
          persona_id, monto, institucion, costo_declarado, cobertura_pct,
          beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
          comprobante_url, nota, registrado_por, created_at
        ) values (
          e.persona_id, r.objetivo, e.institucion, e.costo_declarado, 75,
          e.beneficiario, e.beneficiario_nombre, v_desde, e.vigente_hasta,
          e.comprobante_url, e.nota, v_actor, e.created_at
        );
      end if;

      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (e.persona_id, 'educacion_realineada',
         'S/' || to_char(e.monto, 'FM999999.00'),
         'S/' || to_char(r.objetivo, 'FM999999.00') || ' desde ' || v_desde::text,
         v_actor,
         'Cambió el rango: el techo de educación pasó a S/' ||
         to_char(v_tope, 'FM999999.00') || ' y la asignación se realineó sola.');

      v_movidas := v_movidas + 1;
    end loop;
  end loop;

  perform set_config('cayla.educacion_realineando', '0', true);

  -- 3 · La comprobación que sustituye al candado, y es más estricta que él.
  --     El techo es MENSUAL y se comparte: lo que no puede pasar es que en un
  --     día cualquiera la suma de lo vigente supere el techo. Se mira en cada
  --     fecha en que algo empieza, que son los únicos días en que la suma puede
  --     subir. Si algo no cuadra, revienta acá y se cae la transacción entera
  --     —incluido el cambio de rango que la disparó—, que es el desenlace
  --     correcto: nadie debería quedarse con un reparto que no cierra.
  for r in
    select x.vigente_desde as dia
      from asignaciones_educacion x
     where x.persona_id = p_persona_id
       and x.vigente_hasta >= v_desde
     group by x.vigente_desde
  loop
    select coalesce(sum(x.monto), 0) into v_usado
      from asignaciones_educacion x
     where x.persona_id = p_persona_id
       and x.vigente_desde <= r.dia
       and x.vigente_hasta >= r.dia;

    if v_usado > fn_educacion_tope(p_persona_id, r.dia) then
      raise exception
        'La realineación de educación dejó S/% vigentes el % para esta persona, por '
        'encima del techo de su rango. No se aplica nada.',
        to_char(v_usado, 'FM999999.00'), r.dia;
    end if;
  end loop;

  return v_movidas;
end;
$$;

comment on function fn_educacion_realinear(uuid, date, uuid) is
  'Recalcula las asignaciones por educación de una persona contra el techo de su '
  'rango, desde el primer periodo no pagado. La llama el trigger de '
  'asignaciones_salario; no se llama a mano desde una pantalla.';


-- ── G · Y el gatillo: cambiar de rango realinea ─────────────────────────────
-- En la tabla y no en `fn_set_salario` porque hay más de una puerta que escribe
-- un tramo de salario —la reactivación de la 0209 es otra— y una regla que vive
-- en una sola de ellas es una regla que se olvida en la siguiente.
--
-- Se dispara también cuando cambia el sueldo sin cambiar el rango: ahí el plan
-- da los mismos montos, no se aplica nada y no queda rastro. Que sea idempotente
-- es lo que permite colgarlo del INSERT sin pensar en cada caso.
create or replace function fn_educacion_sigue_al_rango()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_educacion_realinear(
    new.persona_id,
    new.vigente_desde,
    coalesce(fn_persona_actual_id(), new.asignado_por, new.persona_id));
  return null;
end;
$$;

drop trigger if exists trg_educacion_sigue_al_rango on asignaciones_salario;

create trigger trg_educacion_sigue_al_rango
  after insert or update of rango on asignaciones_salario
  for each row execute function fn_educacion_sigue_al_rango();


-- ── H · La pantalla deja de tener un aviso que nunca se enciende ────────────
-- `ya_tiene` preguntaba por `vigente_hasta is null`, y la 0149 dejó esa columna
-- en NOT NULL: desde entonces devuelve SIEMPRE falso, así que el desplegable
-- nunca dijo «ya tiene una vigente» y el aviso ámbar de la pantalla no se ha
-- visto nunca. Su texto además envejeció —decía «cierra primero la anterior, si
-- no se le pagarían las dos»— cuando desde la 0149 dos asignaciones conviven a
-- propósito bajo un mismo techo.
--
-- Se cae la columna en vez de arreglarla: lo que la pantalla necesita saber no
-- es «tiene otra», es «cuánto techo le queda», y eso lo responde
-- `fn_educacion_saldo` para las fechas exactas del formulario.
--
-- Se borra y se crea porque cambia el tipo de retorno: Postgres no deja quitarle
-- una columna a una función que devuelve TABLE con `create or replace`.
drop function if exists fn_educacion_candidatos();

create or replace function fn_educacion_candidatos()
returns table (
  persona_id uuid,
  persona    text,
  sede       text,
  rango      text,
  tope       numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    t.tope_mensual      -- null = rango sin techo cargado; la pantalla lo dice
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = p.id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  left join topes_educacion_rango t on t.rango = sal.rango
  where p.estado = 'activo'
    and fn_es_admin_o_lider() is true
  order by p.apellidos, p.nombres;
$$;

grant execute on function fn_educacion_candidatos() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (281, 'el_techo_de_educacion_se_reparte_y_sigue_al_rango')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0281 · el techo se reparte entre los estudios que se solapan, y sigue al rango.';
end $fin$;
