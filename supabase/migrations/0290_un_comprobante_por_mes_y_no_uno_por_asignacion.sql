-- ============================================================================
-- 0290 — Un comprobante por mes, y no uno por asignación.
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que una asignación por educación pueda tener TANTOS comprobantes como meses
--   paga, y que el sistema diga cuáles faltan — en la pantalla y en el contador
--   del menú, sin que nadie tenga que acordarse.
--
-- POR QUÉ, CON EL NÚMERO QUE LO MOTIVÓ
--
--   Medido en producción el 2026-08-24: de las trece asignaciones vigentes,
--   **diez tienen una vigencia que abarca dos o tres periodos de planilla y un
--   solo comprobante cargado**. El pago es correcto —una pensión mensual se
--   repite todos los meses— pero el sustento no está completo: si mañana llega
--   una fiscalización y la vigencia cubrió tres meses, lo defendible son tres
--   recibos, no uno. El art. 19 f) del D.S. 001-97-TR pide que la asignación
--   esté «debidamente sustentada», y en la RTF 07222-3-2018 (Albis) el concepto
--   se cayó por eso, con montos que SUNAT aceptó como razonables.
--
--   Y no se podía arreglar aunque alguien quisiera: `asignaciones_educacion`
--   tiene UN `comprobante_url`, uno solo. No había dónde subir el segundo.
--
-- POR QUÉ CADA PAPEL DICE SU MES
--
--   Decidido por Felipe el 2026-08-24. Sin el mes solo se pueden CONTAR papeles,
--   y contar no distingue tres recibos de agosto de un recibo por mes: el aviso
--   se apagaría subiendo tres veces el mismo. Con el mes, el aviso dice cuál
--   falta y la pantalla puede poner el botón al lado.
--
-- POR QUÉ EL MES ES EL DEL PERIODO Y NO EL DEL CALENDARIO
--
--   El periodo de planilla va del 29 al 28, así que un tramo del 29/08 al 28/09
--   toca dos meses del calendario y se paga UNA vez. Pedir dos papeles para un
--   pago sería pedir papel de más. El mes de un comprobante es el mes en que
--   TERMINA el periodo que respalda — el periodo del 29/07 al 28/08 es «agosto»,
--   que además es como lo llama cualquiera.
--
-- POR QUÉ NO SE PIDE EL PAPEL DE UN MES QUE NO HA LLEGADO
--
--   Una vigencia hasta octubre no puede tener todavía el recibo de octubre. Si
--   el aviso los contara, se encendería en casi todas las filas desde el primer
--   día y nadie volvería a mirarlo — que es exactamente por lo que este
--   repositorio descartó un guardián parecido (ver `CLAUDE.md`: 28 aciertos,
--   casi todos legítimos, «se desactiva a la semana»). Sólo se pide el papel de
--   los meses que ya empezaron.
--
-- ── LA DECISIÓN DE DISEÑO QUE EVITA TOCAR LA PLANILLA ───────────────────────
--
--   `asignaciones_educacion.comprobante_url` NO se borra: pasa a ser un ESPEJO
--   que mantiene un trigger, apuntando al papel más reciente de esa asignación.
--   Es el mismo patrón que `jornadas` frente a los marcajes — un resumen
--   derivado, nunca una segunda verdad que alguien pueda editar por su cuenta.
--
--   El motivo es concreto: `fn_planilla_calcular` lee esa columna dos veces para
--   decidir si una asignación devenga. Son 37 000 caracteres y 23 versiones, y
--   es lo que decide lo que cobra la gente. Con el espejo, la regla «sin papel
--   no devenga» sigue funcionando sin que la planilla se entere de que ahora hay
--   una tabla detrás.
--
-- QUÉ ASUME
--
--   · `asignaciones_educacion` (0120) con las reglas de la 0149 y el reparto del
--     techo de la 0281 — de la que se copia el cuerpo de `fn_educacion_registrar`.
--   · El bucket privado «comprobantes» y `fn_educacion_puede_ver` (0136): las
--     rutas siguen siendo `educacion/<persona_id>/<archivo>`, así que el permiso
--     de leer un papel no cambia ni una línea.
--   · `fn_hoy_lima()` (0091), `fn_es_admin_o_lider()`, `fn_persona_actual_id()`.
--
-- QUÉ MUEVE AL PEGARSE
--
--   Ningún pago. Los comprobantes que hoy están en la columna se copian a la
--   tabla nueva —uno por asignación, con el mes del periodo en que empieza su
--   vigencia— y la columna se queda igual, ahora mantenida por el trigger.
--
-- CÓMO SE REVIERTE
--
--   drop trigger trg_educacion_espejo_comprobante on educacion_comprobantes;
--   drop function fn_educacion_espejo_comprobante();
--   drop function fn_educacion_adjuntar_comprobante(uuid, text, date, text);
--   drop function fn_educacion_quitar_comprobante(uuid, text);
--   drop function fn_educacion_papeles(uuid);
--   drop function fn_educacion_meses_del_tramo(date, date);
--   drop function fn_educacion_mes_del_periodo(date);
--   drop table educacion_comprobantes;
--   -- y volver a pegar de la 0149 fn_educacion_listar() y fn_educacion_por_atender(),
--   -- y de la 0281 fn_educacion_registrar(...).
--   Ningún archivo del bucket se toca al revertir.
-- ============================================================================


-- ── A · En qué mes cae un periodo, y qué meses toca un tramo ────────────────
-- Escrito una vez porque lo preguntan tres: el aviso de la pantalla, el
-- contador del menú y la prueba. El periodo que termina el 28 de un mes ES ese
-- mes; a partir del 29 ya se está en el siguiente.
create or replace function fn_educacion_mes_del_periodo(p_fecha date)
returns date
language sql
immutable
as $$
  select date_trunc('month',
           case when extract(day from p_fecha) >= 29
                then p_fecha + interval '1 month'
                else p_fecha::timestamp end)::date;
$$;

comment on function fn_educacion_mes_del_periodo(date) is
  'El mes del periodo de planilla en que cae una fecha. El periodo va del 29 al '
  '28, así que el 29/07 ya es «agosto». Devuelve el primer día de ese mes.';

-- Los meses que un tramo de vigencia va a cobrar. Uno por periodo, no uno por
-- mes del calendario: del 29/08 al 28/09 hay UN periodo, no dos.
create or replace function fn_educacion_meses_del_tramo(p_desde date, p_hasta date)
returns setof date
language sql
immutable
as $$
  select generate_series(
           fn_educacion_mes_del_periodo(p_desde),
           fn_educacion_mes_del_periodo(p_hasta),
           interval '1 month')::date;
$$;

grant execute on function fn_educacion_mes_del_periodo(date)        to authenticated;
grant execute on function fn_educacion_meses_del_tramo(date, date)  to authenticated;


-- ── B · La tabla ────────────────────────────────────────────────────────────
create table if not exists educacion_comprobantes (
  id            uuid primary key default gen_random_uuid(),
  asignacion_id uuid not null references asignaciones_educacion(id) on delete cascade,
  storage_path  text not null,
  -- Primer día del mes de PERIODO que respalda este papel.
  mes_cubierto  date not null,
  nota          text,
  subido_por    uuid references personas(id),
  created_at    timestamptz not null default now(),
  constraint educacion_comprobante_mes_es_el_dia_1
    check (extract(day from mes_cubierto) = 1),
  -- El mismo archivo no se cuelga dos veces de la misma asignación. Dos papeles
  -- distintos del mismo mes SÍ se permiten: una matrícula y una pensión pueden
  -- convivir, y quien decide si eso sostiene el gasto es una persona, no un
  -- índice.
  constraint educacion_comprobante_no_duplicado unique (asignacion_id, storage_path)
);

comment on table educacion_comprobantes is
  'Los papeles que sostienen una asignación por educación, uno por mes de periodo. '
  'Antes vivía uno solo, en asignaciones_educacion.comprobante_url, y por eso una '
  'vigencia de tres meses no podía tener más de un recibo.';

create index if not exists idx_educacion_comprobantes_asignacion
  on educacion_comprobantes (asignacion_id, mes_cubierto);

-- Se lee con la misma regla que la asignación de la que cuelga: DO lo ve todo,
-- y cada persona ve lo suyo. Escribir es sólo por las funciones de más abajo.
alter table educacion_comprobantes enable row level security;

revoke all on educacion_comprobantes from authenticated, anon;
grant select on educacion_comprobantes to authenticated;

drop policy if exists educacion_comprobantes_lectura on educacion_comprobantes;
create policy educacion_comprobantes_lectura on educacion_comprobantes
  for select to authenticated
  using (exists (
    select 1 from asignaciones_educacion a
     where a.id = educacion_comprobantes.asignacion_id
       and (fn_es_admin_o_lider() or a.persona_id = fn_persona_actual_id())));


-- ── C · El espejo, para no tocar la planilla ────────────────────────────────
-- `asignaciones_educacion.comprobante_url` deja de escribirse a mano: apunta
-- siempre al papel más reciente de su asignación, o a null si no queda ninguno.
-- La planilla sigue preguntándole a ella y no se entera del cambio.
create or replace function fn_educacion_espejo_comprobante()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asignacion uuid := coalesce(new.asignacion_id, old.asignacion_id);
begin
  update asignaciones_educacion a
     set comprobante_url = (
       select c.storage_path
         from educacion_comprobantes c
        where c.asignacion_id = v_asignacion
        order by c.mes_cubierto desc, c.created_at desc
        limit 1)
   where a.id = v_asignacion;

  return null;
end;
$$;

drop trigger if exists trg_educacion_espejo_comprobante on educacion_comprobantes;

create trigger trg_educacion_espejo_comprobante
  after insert or update or delete on educacion_comprobantes
  for each row execute function fn_educacion_espejo_comprobante();

comment on column asignaciones_educacion.comprobante_url is
  'DERIVADA desde la 0290: la mantiene un trigger y apunta al papel más reciente '
  'de educacion_comprobantes. No se escribe a mano. Existe porque fn_planilla_calcular '
  'la lee para decidir si la asignación devenga, y esa función no se toca por esto.';


-- ── D · Los papeles que ya estaban ──────────────────────────────────────────
-- Uno por asignación, con el mes del periodo en que empieza su vigencia, que es
-- el único dato que hay para saber qué mes respaldan. Idempotente: repetir la
-- migración no los duplica (lo impide el unique, y el `where not exists` lo
-- dice en voz alta).
insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, nota, subido_por)
select a.id, a.comprobante_url,
       fn_educacion_mes_del_periodo(a.vigente_desde),
       'Cargado antes de la 0290, cuando la asignación solo admitía un papel.',
       a.registrado_por
  from asignaciones_educacion a
 where a.comprobante_url is not null
   and not exists (select 1 from educacion_comprobantes c where c.asignacion_id = a.id);


-- ── E · Adjuntar, quitar y listar los papeles ───────────────────────────────
-- Por función y no por insert directo, igual que todo lo que mueve papeles acá:
-- la tabla no tiene política de escritura a propósito.
create or replace function fn_educacion_adjuntar_comprobante(
  p_asignacion_id uuid,
  p_storage_path  text,
  p_mes_cubierto  date,
  p_nota          text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_asg asignaciones_educacion%rowtype;
  v_mes date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional adjunta comprobantes de educación.';
  end if;

  select * into v_asg from asignaciones_educacion where id = p_asignacion_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_storage_path is null or length(trim(p_storage_path)) < 3 then
    raise exception 'Falta la ruta del archivo.';
  end if;
  if p_mes_cubierto is null then
    raise exception 'Falta decir qué mes respalda este comprobante.';
  end if;

  v_mes := date_trunc('month', p_mes_cubierto)::date;

  -- Que el mes caiga dentro de lo que esa asignación paga. Un recibo de un mes
  -- que la vigencia no cobra no sostiene nada, y colarlo apagaría el aviso de
  -- un mes que sí falta.
  if not exists (
    select 1 from fn_educacion_meses_del_tramo(v_asg.vigente_desde, v_asg.vigente_hasta) m
     where m = v_mes
  ) then
    raise exception
      'Esa asignación no paga el mes de % (va del % al %). Adjunta el comprobante '
      'a la vigencia que sí lo cubre, o corrige las fechas.',
      to_char(v_mes, 'MM/YYYY'), v_asg.vigente_desde, v_asg.vigente_hasta;
  end if;

  insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, nota, subido_por)
  values (p_asignacion_id, trim(p_storage_path), v_mes,
          nullif(trim(coalesce(p_nota, '')), ''), fn_persona_actual_id())
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_asg.persona_id, 'educacion_comprobante', null,
     to_char(v_mes, 'MM/YYYY') || ' · ' || trim(p_storage_path),
     coalesce(fn_persona_actual_id(), v_asg.persona_id),
     'Se adjunta el comprobante del mes que respalda la asignación.');

  return v_id;
end;
$$;

-- Quitar exige motivo: un papel que desaparece cambia lo que se puede probar el
-- día de una fiscalización, y el archivo del bucket NO se borra — solo deja de
-- estar colgado de esta asignación.
create or replace function fn_educacion_quitar_comprobante(p_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c   educacion_comprobantes%rowtype;
  v_asg asignaciones_educacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional quita comprobantes de educación.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se quita el comprobante. Sin él, esa asignación queda sin sustento.';
  end if;

  select * into v_c from educacion_comprobantes where id = p_id;
  if not found then raise exception 'Ese comprobante no existe.'; end if;

  select * into v_asg from asignaciones_educacion where id = v_c.asignacion_id;

  delete from educacion_comprobantes where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_asg.persona_id, 'educacion_comprobante',
     to_char(v_c.mes_cubierto, 'MM/YYYY') || ' · ' || v_c.storage_path, null,
     coalesce(fn_persona_actual_id(), v_asg.persona_id), trim(p_motivo));
end;
$$;

-- Los papeles de una asignación, con los meses que le faltan. Un solo viaje
-- para pintar el detalle de una fila.
create or replace function fn_educacion_papeles(p_asignacion_id uuid)
returns table (
  id           uuid,
  storage_path text,
  mes_cubierto date,
  nota         text,
  subido_por   text,
  created_at   timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.storage_path, c.mes_cubierto, c.nota,
         coalesce(p.nombres || ' ' || p.apellidos, '—'),
         c.created_at
    from educacion_comprobantes c
    join asignaciones_educacion a on a.id = c.asignacion_id
    left join personas p on p.id = c.subido_por
   where c.asignacion_id = p_asignacion_id
     and (fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id())
   order by c.mes_cubierto;
$$;

-- Los meses que esa asignación ya paga y todavía no tienen papel. No incluye
-- los que no han llegado: el recibo de octubre no existe en agosto.
create or replace function fn_educacion_meses_sin_papel(p_asignacion_id uuid)
returns setof date
language sql
stable
security definer
set search_path = public
as $$
  select m
    from asignaciones_educacion a
    cross join lateral fn_educacion_meses_del_tramo(a.vigente_desde, a.vigente_hasta) m
   where a.id = p_asignacion_id
     and fn_es_admin_o_lider() is true
     and m <= fn_educacion_mes_del_periodo(fn_hoy_lima())
     and not exists (
       select 1 from educacion_comprobantes c
        where c.asignacion_id = a.id and c.mes_cubierto = m)
   order by m;
$$;

grant execute on function fn_educacion_adjuntar_comprobante(uuid, text, date, text) to authenticated;
grant execute on function fn_educacion_quitar_comprobante(uuid, text)               to authenticated;
grant execute on function fn_educacion_papeles(uuid)                                to authenticated;
grant execute on function fn_educacion_meses_sin_papel(uuid)                        to authenticated;


-- ── F · La lista, que ahora dice cuántos papeles hay y cuántos faltan ───────
-- Cuerpo de la 0149 con dos columnas nuevas y nada más. Se borra y se crea
-- porque cambia el tipo de retorno: Postgres no deja agregarle una columna a una
-- función que devuelve TABLE con `create or replace`.
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
  paga                boolean,
  papeles             int,
  meses_sin_papel     int
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
    (a.comprobante_url is not null and a.vigente_hasta >= fn_hoy_lima()),
    -- ⇩⇩⇩ CAMBIO 0290 ⇩⇩⇩ Cuántos papeles tiene, y cuántos meses YA PAGADOS
    -- siguen sin uno. Los meses que no han llegado no cuentan: el recibo de
    -- octubre no existe en agosto, y contarlo encendería el aviso en casi todas
    -- las filas desde el primer día.
    (select count(*)::int from educacion_comprobantes c where c.asignacion_id = a.id),
    (select count(*)::int
       from fn_educacion_meses_del_tramo(a.vigente_desde, a.vigente_hasta) m
      where m <= fn_educacion_mes_del_periodo(fn_hoy_lima())
        and not exists (select 1 from educacion_comprobantes c
                         where c.asignacion_id = a.id and c.mes_cubierto = m))
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


-- ── G · El contador del menú suma los papeles que faltan ────────────────────
-- Antes contaba «sin comprobante» y «por vencer». Ahora también las que ya
-- pagaron un mes sin papel — que era el caso invisible: diez de trece en
-- producción, y ninguna aparecía en ningún contador.
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
    and (a.comprobante_url is null
         or a.vigente_hasta <= fn_hoy_lima() + 30
         or exists (
           select 1
             from fn_educacion_meses_del_tramo(a.vigente_desde, a.vigente_hasta) m
            where m <= fn_educacion_mes_del_periodo(fn_hoy_lima())
              and not exists (select 1 from educacion_comprobantes c
                               where c.asignacion_id = a.id and c.mes_cubierto = m)));
$$;

grant execute on function fn_educacion_por_atender() to authenticated;


-- ── H · Registrar y corregir, con los papeles colgando de la tabla ──────────
-- Cuerpo de la 0281 con tres cambios: el papel del alta entra en
-- `educacion_comprobantes` en vez de en la columna; el enlace posterior también;
-- y una corrección que abre vigencia nueva COPIA los papeles a la fila nueva.
--
-- Ese último es el que no se puede olvidar: la tabla cuelga de la asignación con
-- `on delete cascade`, y la rama que reemplaza una vigencia que nunca devengó la
-- BORRA. Sin copiar antes, los papeles se irían con ella y la vigencia nueva
-- nacería sin sustento — que en este sistema significa sin devengar. Una
-- corrección de una errata habría dejado a alguien sin cobrar, en silencio.
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
  v_papeles  jsonb;
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
      nota, registrado_por
    ) values (
      p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
      p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      p_vigente_desde, p_vigente_hasta,
      nullif(trim(coalesce(p_nota, '')), ''), v_yo
    )
    returning id into v_id;

    -- ⇩ CAMBIO 0290 ⇩ El papel ya no se escribe en la columna —es derivada— sino
    -- que entra en educacion_comprobantes, respaldando el mes del periodo en que
    -- empieza la vigencia. El trigger espejo pone la columna al día.
    if p_comprobante_url is not null then
      insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
      values (v_id, p_comprobante_url, fn_educacion_mes_del_periodo(p_vigente_desde), v_yo)
      on conflict do nothing;
    end if;

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
      nota                = nullif(trim(coalesce(p_nota, '')), '')
    where id = p_id;

    -- El comprobante se enlaza en un segundo paso, cuando el archivo terminó de
    -- subir. Desde la 0290 eso es una fila más, no un update de la columna.
    if p_comprobante_url is not null then
      insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
      values (p_id, p_comprobante_url, fn_educacion_mes_del_periodo(v_vieja.vigente_desde), v_yo)
      on conflict do nothing;
    end if;

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

  -- ⇩ CAMBIO 0290 ⇩ Los papeles se copian a la vigencia nueva ANTES de tocar la
  -- vieja: si la vieja se borra, se los llevaría por delante (la tabla cuelga de
  -- ella con `on delete cascade`), y la nueva nacería sin sustento — o sea, sin
  -- devengar. Se COPIAN y no se mueven: los de la vieja siguen sosteniendo lo
  -- que ya se pagó con ella.
  select coalesce(jsonb_agg(jsonb_build_object(
           'ruta', c.storage_path, 'mes', c.mes_cubierto,
           'nota', c.nota, 'quien', c.subido_por)), '[]'::jsonb)
    into v_papeles
    from educacion_comprobantes c
   where c.asignacion_id = p_id;

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
    nota, registrado_por, created_at
  ) values (
    p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
    p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
    greatest(v_desde, p_vigente_desde), p_vigente_hasta,
    nullif(trim(coalesce(p_nota, '')), ''), v_yo, v_vieja.created_at
  )
  returning id into v_id;

  -- Los papeles de la vigencia anterior, y el nuevo si vino uno. Sólo los meses
  -- que la vigencia nueva de verdad paga: un recibo de un mes que ya no cobra no
  -- sostiene nada.
  insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, nota, subido_por)
  select v_id, x->>'ruta', (x->>'mes')::date, x->>'nota', nullif(x->>'quien', '')::uuid
    from jsonb_array_elements(v_papeles) x
   where exists (
     select 1 from fn_educacion_meses_del_tramo(greatest(v_desde, p_vigente_desde), p_vigente_hasta) m
      where m = (x->>'mes')::date)
  on conflict do nothing;

  if p_comprobante_url is not null then
    insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
    values (v_id, p_comprobante_url,
            fn_educacion_mes_del_periodo(greatest(v_desde, p_vigente_desde)), v_yo)
    on conflict do nothing;
  end if;

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


insert into migraciones_aplicadas (numero, nombre)
values (290, 'un_comprobante_por_mes_y_no_uno_por_asignacion')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $fin$
begin
  raise notice '0290 · una asignación ya puede tener un comprobante por cada mes que paga.';
end $fin$;
