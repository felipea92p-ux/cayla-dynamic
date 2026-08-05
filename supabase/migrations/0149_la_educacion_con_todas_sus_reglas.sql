-- ============================================================================
-- 0149 — La asignación por educación, con todas sus reglas
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una asignación por educación no pueda existir en un estado que la
--   empresa no pueda defender ante una fiscalización, ni pagar un céntimo que
--   un comprobante no sostenga. Nueve reglas, decididas por Felipe el
--   2026-08-04, que hasta hoy vivían en su cabeza y no en la base:
--
--     1 · el monto lo calcula el sistema, nadie lo teclea
--     2 · la cobertura es 75 % y no se negocia caso por caso
--     3 · el techo del rango se mide sobre la SUMA de lo que cobra la persona
--     4 · toda asignación dice hasta cuándo vale
--     5 · un comprobante a nombre de un hijo dice de qué hijo
--     6 · no se registra ni se corrige dentro de un periodo ya pagado
--     7 · corregir lo que mueve plata abre una vigencia nueva, no reescribe
--     8 · toda corrección deja motivo y rastro
--     9 · quien cesa deja de devengar el día que cesa
--
-- QUÉ ASUME
--   · `asignaciones_educacion` (0120), su techo por rango (0132) y las funciones
--     de la 0136. La tabla está VACÍA hoy (0 filas, comprobado), que es lo que
--     permite poner `not null` sin migrar nada.
--   · `fn_hoy_lima()` (0091) y `fn_persona_actual_id()` (0078).
--   · Que la planilla suma las filas y exige comprobante — eso lo hace la 0150,
--     que va encima de ésta. Aplicar sólo la 0149 no cambia ningún pago.
--
-- POR QUÉ EL MONTO NO SE TECLEA
--   Es `min(costo del comprobante × 75 %, techo del rango)` y punto. Si sale por
--   debajo del techo es porque el 75 % del curso ya es menor — nunca porque
--   alguien decidió pagar menos. Dejarlo escribible obligaba a DO a hacer esa
--   cuenta 22 veces y a acordarse del techo de cada rango; el primer error de
--   cuenta llegaba el primer mes, y no sería un error de la persona sino del
--   diseño. Con esto el formulario pide lo único que DO puede saber leyendo el
--   papel: cuánto cuesta y hasta cuándo vale.
--
-- POR QUÉ EL TECHO VA SOBRE LA SUMA Y NO SOBRE CADA FILA
--   El diseño acordado dice que la asignación vale para el trabajador **y/o sus
--   hijos**. Con el techo medido fila por fila, dos filas de S/170 pasaban un
--   techo de S/180 y se pagaban S/340: el techo dejaba de ser un techo. Ahora se
--   suman las vigencias que se solapan y el techo se mide sobre ese total.
--
-- POR QUÉ CORREGIR ABRE UNA VIGENCIA NUEVA
--   Mismo criterio que la 0115 usó con la pensión: los periodos pagados quedaron
--   intactos, comprobado. Si corregir reescribiera la fila, un periodo ya pagado
--   cambiaría de monto retroactivamente y la foto del pago (0096) empezaría a
--   discrepar sin que nadie lo hubiera pedido. Sólo lo que mueve plata —el costo
--   declarado y las fechas— abre vigencia nueva; la institución, el nombre del
--   beneficiario, el comprobante y la nota se corrigen en la misma fila, porque
--   no cambian un céntimo.
--
-- LO QUE ESTA MIGRACIÓN NO DECIDE, Y CONVIENE MIRAR
--   La regla de vigencia acordada es «paga el mes completo si estaba vigente al
--   INICIAR el periodo». Eso resuelve el ciclo que termina a mitad de mes, y
--   deja abierto el simétrico: quien se matricula el día 10 no cobra ese mes.
--   Es evitable operativamente —DO pone `vigente_desde` en el primer día del
--   periodo, que es cuando la institución cobró la pensión— y por eso no se
--   fuerza acá. Si mañana se prefiere pagar también el mes que empieza a mitad,
--   es una sola condición en la 0150, no un rediseño.
--
-- CÓMO SE REVIERTE
--   Los `alter table` se deshacen quitando los tres constraints nuevos, la
--   columna `beneficiario_nombre` y el `not null` de `vigente_hasta`. Las
--   funciones vuelven a su cuerpo de la 0136. La 0150 depende de ésta: revertir
--   sólo la 0149 deja a la planilla sumando filas cuyo techo ya no se valida.
-- ============================================================================


-- ── A · El esquema no deja construir un estado indefendible ─────────────────
-- Un constraint vale más que diez validaciones en la pantalla: la pantalla se
-- puede saltar llamando la función, y la función se puede reescribir mal.

alter table asignaciones_educacion
  add column if not exists beneficiario_nombre text;

comment on column asignaciones_educacion.beneficiario_nombre is
  'Nombre de la persona a la que pertenece el comprobante. Obligatorio cuando el '
  'beneficiario es un hijo: sin él, un comprobante a nombre de un tercero no tiene '
  'cómo atarse a quien cobra, que es el hueco por el que estos conceptos se '
  'desconocen en fiscalización. Dato personal: no sale en la boleta.';

-- La tabla está vacía, así que el not null no rompe ninguna fila existente.
alter table asignaciones_educacion alter column vigente_hasta set not null;

alter table asignaciones_educacion alter column cobertura_pct set default 75;

do $mig$
begin
  -- 75 % fijo. Si mañana la política cambia, se cambia acá y queda el rastro de
  -- cuándo cambió — que es exactamente lo que no pasa cuando el número es un
  -- campo que cada quien llena a su criterio.
  if not exists (select 1 from pg_constraint where conname = 'educacion_cobertura_es_75') then
    alter table asignaciones_educacion
      add constraint educacion_cobertura_es_75 check (cobertura_pct = 75);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'educacion_hijo_lleva_nombre') then
    alter table asignaciones_educacion
      add constraint educacion_hijo_lleva_nombre check (
        beneficiario <> 'hijo'
        or (beneficiario_nombre is not null and length(trim(beneficiario_nombre)) >= 3)
      );
  end if;
end $mig$;


-- ── A bis · El índice que impedía el caso que el diseño promete ────────────
-- La 0120 puso `unique (persona_id, vigente_desde)` para que nadie duplicara la
-- misma asignación. Con una sola por persona era correcto; con «vale para el
-- trabajador Y/O sus hijos» dejó de serlo: madre e hija registradas el mismo día
-- —el caso normal, se cargan juntas— chocaban contra ese índice. Encontrado
-- ejecutando la prueba 115, no leyendo: el esquema decía una cosa y el diseño
-- acordado otra.
--
-- Se reemplaza por una unicidad que sigue impidiendo el duplicado literal —la
-- misma persona, el mismo beneficiario, la misma institución, el mismo día— y
-- deja convivir dos beneficiarios distintos. Quien controla que no se pague de
-- más ya no es este índice sino el techo sobre la suma, que es su lugar.
drop index if exists idx_asignaciones_educacion_unica;

create unique index if not exists idx_asignaciones_educacion_unica
  on asignaciones_educacion (
    persona_id, vigente_desde, beneficiario,
    coalesce(beneficiario_nombre, ''), institucion
  );


-- ── B · El techo del rango, medido sobre la suma ────────────────────────────
create or replace function fn_educacion_respeta_el_tope()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_rango text;
  v_tope  numeric;
  v_suma  numeric;
begin
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

  -- ⇩ CAMBIO 0149 ⇩ La suma, no la fila. Se cuentan las asignaciones de esa
  -- persona cuya vigencia SE SOLAPA con la de la fila que entra: dos cursos en
  -- meses distintos no compiten por el mismo techo, dos cursos en el mismo mes
  -- sí. Se excluye la propia fila para que corregir no se sume a sí misma.
  select coalesce(sum(a.monto), 0) into v_suma
    from asignaciones_educacion a
   where a.persona_id   = new.persona_id
     and a.id          <> new.id
     and a.vigente_desde <= new.vigente_hasta
     and a.vigente_hasta >= new.vigente_desde;

  if v_suma + new.monto > v_tope then
    raise exception
      'La suma de las asignaciones por educación de esta persona (S/%) supera el tope '
      'del rango % (S/%). Ya tiene S/% vigente en esas fechas. Cierra la otra asignación, '
      'ajusta el monto, o sube el tope en topes_educacion_rango si la política cambió.',
      to_char(v_suma + new.monto, 'FM999999.00'), v_rango,
      to_char(v_tope, 'FM999999.00'), to_char(v_suma, 'FM999999.00');
  end if;

  return new;
end;
$$;


-- ── C · Dos ayudas que se usan en varios sitios ─────────────────────────────

-- ¿Esta fecha cae en un periodo ya pagado? Se pregunta al registrar y al
-- corregir, y la respuesta tiene que ser la misma en los dos. Escrita una vez.
create or replace function fn_educacion_fecha_pagada(p_fecha date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  );
$$;

-- Desde cuándo puede regir un cambio: el primer día que NO cae en un periodo
-- pagado, contando desde hoy. Si hoy está dentro de un periodo abierto, devuelve
-- el inicio de ese periodo — el cambio alcanza al pago que todavía no se hizo.
create or replace function fn_educacion_desde_cuando_puede_regir()
returns date
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select min(pp.fecha_ini)
       from periodos_planilla pp
      where pp.estado <> 'pagado'
        and pp.fecha_fin >= fn_hoy_lima()),
    fn_hoy_lima());
$$;

-- El monto no es un dato de entrada: es una consecuencia del comprobante y del
-- rango. Vive en una función para que la pantalla pueda mostrar la misma cifra
-- que la base va a guardar, sin reimplementar la cuenta en TypeScript — que es
-- cómo se fabrican las dos copias que después discrepan.
create or replace function fn_educacion_monto(p_persona_id uuid, p_costo numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select least(
    round(p_costo * 75 / 100.0, 2),
    coalesce(
      (select t.tope_mensual
         from asignaciones_salario a
         join topes_educacion_rango t on t.rango = a.rango
        where a.persona_id = p_persona_id and a.vigente_hasta is null
        order by a.vigente_desde desc limit 1),
      round(p_costo * 75 / 100.0, 2)));   -- sin rango o sin techo: manda el 75 %
$$;

grant execute on function fn_educacion_fecha_pagada(date)          to authenticated;
grant execute on function fn_educacion_desde_cuando_puede_regir()  to authenticated;
grant execute on function fn_educacion_monto(uuid, numeric)        to authenticated;


-- ── D · Registrar y corregir, por una sola puerta ───────────────────────────
-- La firma cambia respecto de la 0136: ya no entran `p_monto` (se calcula) ni
-- `p_cobertura_pct` (es 75), y entran el nombre del beneficiario, la fecha de
-- fin y el motivo. Se borra la anterior para que no queden dos puertas.
drop function if exists fn_educacion_registrar(uuid,numeric,text,numeric,numeric,text,date,text,text,uuid);

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

  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado);

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

  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado);

  if v_desde > v_vieja.vigente_desde then
    update asignaciones_educacion
       set vigente_hasta = v_desde - 1
     where id = p_id;
  else
    -- La fila vieja nunca llegó a devengar en un periodo pagado: se reemplaza
    -- entera en vez de dejar un tramo de un día que no significa nada.
    delete from asignaciones_educacion where id = p_id;
  end if;

  insert into asignaciones_educacion (
    persona_id, monto, institucion, costo_declarado, cobertura_pct,
    beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
    comprobante_url, nota, registrado_por
  ) values (
    p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
    p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
    greatest(v_desde, p_vigente_desde), p_vigente_hasta,
    coalesce(p_comprobante_url, v_vieja.comprobante_url),
    nullif(trim(coalesce(p_nota, '')), ''), v_yo
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


-- ── E · Cerrar a mano sigue existiendo, con motivo ──────────────────────────
create or replace function fn_educacion_cerrar(p_id uuid, p_hasta date, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r asignaciones_educacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional cierra asignaciones por educación.';
  end if;

  select * into r from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_hasta < r.vigente_desde then
    raise exception 'La fecha de cierre (%) es anterior al inicio (%).', p_hasta, r.vigente_desde;
  end if;

  if fn_educacion_fecha_pagada(p_hasta) is true then
    raise exception
      'Esa fecha de cierre (%) cae en un periodo ya PAGADO: acortar la vigencia ahí '
      'cambiaría una planilla cerrada.', p_hasta;
  end if;

  update asignaciones_educacion set vigente_hasta = p_hasta where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id, 'educacion_cierre', r.vigente_hasta::text, p_hasta::text,
     fn_persona_actual_id(),
     coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Cierre de asignación por educación'));
end;
$$;

grant execute on function fn_educacion_cerrar(uuid,date,text) to authenticated;


-- ── F · Quien cesa deja de devengar el día que cesa ─────────────────────────
-- No se borra la fila: sostiene lo que ya se pagó, y borrarla dejaría esos pagos
-- sin sustento el día de una fiscalización. Sólo se le pone fin.
--
-- Va en un trigger y no en la pantalla de cese porque el cese se registra desde
-- tres sitios distintos, y una regla escrita en la pantalla es una regla que las
-- otras dos no cumplen — el patrón que este repositorio ya pagó tres veces.
create or replace function fn_educacion_cerrar_al_cesar()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_n int;
begin
  if new.estado = 'inactivo' and new.fecha_cese is not null
     and (old.estado is distinct from new.estado or old.fecha_cese is distinct from new.fecha_cese) then

    update asignaciones_educacion
       set vigente_hasta = new.fecha_cese
     where persona_id = new.id
       and vigente_hasta > new.fecha_cese;

    get diagnostics v_n = row_count;

    if v_n > 0 then
      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (new.id, 'educacion_cierre_por_cese', v_n::text || ' asignación(es) abierta(s)',
         'cerradas al ' || new.fecha_cese::text,
         coalesce(fn_persona_actual_id(), new.id),
         'Cierre automático: la persona cesó el ' || new.fecha_cese::text);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_educacion_cerrar_al_cesar on personas;
create trigger trg_educacion_cerrar_al_cesar
  after update on personas
  for each row execute function fn_educacion_cerrar_al_cesar();


-- ── G · La lista, con su semáforo ───────────────────────────────────────────
-- El semáforo se calcula en la base y no en la pantalla: es la misma pregunta
-- que se va a querer hacer desde el contador del menú y desde un reporte, y
-- tres copias de «cuándo vence» es cómo empiezan a discrepar.
drop function if exists fn_educacion_listar();

create or replace function fn_educacion_listar()
returns table (
  id                  uuid,
  persona_id          uuid,
  persona             text,
  sede                text,
  rango               text,
  monto               numeric,
  institucion         text,
  costo_declarado     numeric,
  cobertura_pct       numeric,
  beneficiario        text,
  beneficiario_nombre text,
  comprobante_url     text,
  vigente_desde       date,
  vigente_hasta       date,
  nota                text,
  registrada_por      text,
  dias_para_vencer    int,
  semaforo            text,
  paga                boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id, a.persona_id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    coalesce(sal.rango, '—'),
    a.monto, a.institucion, a.costo_declarado, a.cobertura_pct,
    a.beneficiario, a.beneficiario_nombre, a.comprobante_url,
    a.vigente_desde, a.vigente_hasta, a.nota,
    reg.nombres || ' ' || reg.apellidos,
    (a.vigente_hasta - fn_hoy_lima())::int,
    case
      when a.comprobante_url is null              then 'sin_comprobante'
      when a.vigente_hasta <  fn_hoy_lima()       then 'vencida'
      when a.vigente_hasta <= fn_hoy_lima() + 30  then 'por_vencer'
      else 'vigente'
    end,
    -- Lo que de verdad decide si esta fila entra en la planilla. La pantalla lo
    -- muestra tal cual para que nadie tenga que deducirlo.
    (a.comprobante_url is not null and a.vigente_hasta >= fn_hoy_lima())
  from asignaciones_educacion a
  join personas p on p.id = a.persona_id
  left join sedes s on s.id = p.sede_base_id
  left join personas reg on reg.id = a.registrado_por
  left join lateral (
    select rango from asignaciones_salario x
    where x.persona_id = a.persona_id and x.vigente_hasta is null
    order by x.vigente_desde desc limit 1
  ) sal on true
  where fn_es_admin_o_lider() is true
     or a.persona_id = fn_persona_actual_id()
  order by (a.vigente_hasta < fn_hoy_lima()), p.apellidos, a.vigente_desde desc;
$$;

grant execute on function fn_educacion_listar() to authenticated;

-- Cuántas necesitan atención: alimenta el contador del menú de una sola consulta
-- en vez de traer la lista entera para contarla en el navegador.
create or replace function fn_educacion_por_atender()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from asignaciones_educacion a
  where fn_es_admin_o_lider() is true
    and (a.comprobante_url is null or a.vigente_hasta <= fn_hoy_lima() + 30);
$$;

grant execute on function fn_educacion_por_atender() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (149, 'la_educacion_con_todas_sus_reglas')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_filas int;
begin
  select count(*) into v_filas from asignaciones_educacion;
  raise notice '0149 · reglas activas. Filas de educacion en esta base: %', v_filas;
  raise notice '0149 · el monto ya no se teclea: es min(costo x 75%%, tope del rango).';
  raise notice '0149 · esta migracion NO cambia ningun pago. Eso lo hace la 0150.';
end $mig$;
