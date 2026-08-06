-- ============================================================================
-- 0167 — La liquidación pagada se congela, y avisa si deja de cuadrar
-- ============================================================================
--
-- QUÉ PROMETE
--   Que lo que se le pagó a una persona que ya se fue no pueda cambiar de cifra
--   por su cuenta. Al marcar PAGADA se guarda copia intacta de cada concepto; si
--   un recálculo posterior da distinto, el sistema lo DICE en vez de cambiar el
--   número.
--
-- QUÉ ASUME
--   La 0164: `fn_liquidacion` devuelve el cálculo completo con su desglose.
--
-- POR QUÉ ESTO IMPORTA MÁS ACÁ QUE EN LA PLANILLA
--   Un error en la planilla lo reclama quien lo cobra: son 22 personas mirando
--   su boleta todos los meses. Un error en una liquidación no lo reclama nadie —
--   la persona ya no está, no tiene cuenta, y en muchos casos ni sabe cómo se
--   calculó. El único control posible es que la cifra no se mueva sola.
--
--   Y se mueve con facilidad: basta que alguien corrija un marcaje viejo, cargue
--   una vacación con retraso, anote un depósito de CTS que faltaba —o CORRIJA LA
--   FECHA DE CESE, que es el más frecuente de los cuatro— y el mismo
--   `fn_liquidacion` devuelve otra cosa un mes después. Sin foto, no habría forma
--   de saber cuál de las dos cifras se transfirió.
--
--   Ese cuarto motivo faltaba en esta lista, y por faltar acá también se escapó
--   del código: la comparación recalculaba con la fecha CONGELADA, así que era
--   ciega justo al caso más común. Corregido antes de aplicar esta migración —ver
--   el comentario largo dentro de `fn_liquidacion_diferencias`— y fijado por la
--   prueba 133.
--
-- POR QUÉ SE VERSIONA EN VEZ DE SOBRESCRIBIR
--   Mismo criterio que `planilla_pagada_detalle` (0096): si hubo que rehacer un
--   pago, la versión anterior queda como histórico en vez de desaparecer. Dos
--   filas con la fecha en que se congeló cada una explican qué pasó; una fila
--   reescrita no explica nada.
--
-- POR QUÉ LA FOTO GUARDA EL JSONB ENTERO Y ADEMÁS LAS COLUMNAS
--   Las columnas son para consultar y sumar. El `detalle` es para poder REIMPRIMIR
--   la hoja exactamente como se entregó, aunque mañana cambie la plantilla o la
--   fórmula. El papel que la persona firmó tiene que poder reconstruirse tal cual.
--
-- LO QUE NO DECIDE
--   Qué hacer cuando la foto y el cálculo difieren. El sistema lo NOMBRA, persona
--   por persona y concepto por concepto; si se paga la diferencia, se ajusta o se
--   deja constancia, es una decisión de negocio. Misma postura que la 0096 tomó
--   con la planilla, y sigue sin reabrirse acá.
--
-- CÓMO SE REVIERTE
--   drop table liquidacion_pagada;  (se pierden las fotos: no hay vuelta atrás
--   para eso, que es justamente el punto de una foto)
--   drop function fn_liquidacion_pagar(uuid, text), fn_liquidacion_diferencias(uuid);
-- ============================================================================


create table if not exists liquidacion_pagada (
  persona_id     uuid not null references personas(id) on delete restrict,
  version        int  not null,

  congelada_at   timestamptz not null default now(),
  congelada_por  uuid not null references personas(id),
  nota           text,

  -- Los datos de quién y cuándo, copiados: si mañana se corrige la fecha de cese
  -- de esa persona, la foto tiene que seguir diciendo con qué fecha se pagó.
  persona        text not null,
  fecha_ingreso  date,
  fecha_cese     date not null,

  -- Las cuatro líneas, para poder sumar y comparar sin abrir el jsonb.
  monto_periodo  numeric(12,2) not null default 0,
  monto_vacaciones numeric(12,2) not null default 0,
  monto_grati    numeric(12,2) not null default 0,
  monto_cts      numeric(12,2) not null default 0,
  total          numeric(12,2) not null,

  -- El cálculo completo tal como se entregó. Reimprimir la hoja de un pago de
  -- hace un año no puede depender de que la fórmula de hoy dé lo mismo.
  detalle        jsonb not null,

  primary key (persona_id, version)
);

comment on table liquidacion_pagada is
  'Copia intacta de la liquidación con la que se pagó a cada persona que cesó. No '
  'se edita ni se borra: si un recálculo posterior ya no coincide, el sistema lo '
  'dice (fn_liquidacion_diferencias) y la cifra pagada no se mueve. Un error acá '
  'no lo reclama nadie — la persona ya no está.';

alter table liquidacion_pagada enable row level security;

drop policy if exists liquidacion_pagada_lectura on liquidacion_pagada;
create policy liquidacion_pagada_lectura on liquidacion_pagada
  for select to authenticated
  using (fn_es_admin_o_lider() is true or persona_id = fn_persona_actual_id());

-- La escritura no se concede: pasa por función, como marcajes, expedientes y
-- salarios. Y una vez escrita, ni el propio DO la toca.
create or replace function fn_trg_liquidacion_es_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'La liquidación con la que se pagó no se modifica ni se borra. Si el cálculo '
    'estaba mal, vuelve a marcarla como pagada: se guarda una versión nueva y esta '
    'queda como histórico, con la fecha en que se congeló cada una.';
end;
$$;

drop trigger if exists trg_liquidacion_pagada_inmutable on liquidacion_pagada;
create trigger trg_liquidacion_pagada_inmutable
  before update or delete on liquidacion_pagada
  for each row execute function fn_trg_liquidacion_es_inmutable();


-- ── Congelar ───────────────────────────────────────────────────────────────
create or replace function fn_liquidacion_pagar(p_persona_id uuid, p_nota text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_l   jsonb;
  v_ver int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder marca una liquidación como pagada.';
  end if;

  -- Se congela lo que la función calcula AHORA, no un número que venga de la
  -- pantalla: si el monto viajara desde el navegador, la foto podría guardar algo
  -- que el sistema nunca calculó — y sería indistinguible de un cálculo real.
  v_l := fn_liquidacion(p_persona_id, null);

  select coalesce(max(version), 0) + 1 into v_ver
  from liquidacion_pagada where persona_id = p_persona_id;

  insert into liquidacion_pagada (
    persona_id, version, congelada_por, nota,
    persona, fecha_ingreso, fecha_cese,
    monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle
  ) values (
    p_persona_id, v_ver, fn_persona_actual_id(), nullif(trim(coalesce(p_nota, '')), ''),
    v_l->>'persona',
    (v_l->>'fecha_ingreso')::date,
    (v_l->>'fecha_cese')::date,
    coalesce((v_l->'periodo'->>'monto')::numeric, 0),
    coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0),
    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0),
    coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0),
    (v_l->>'total')::numeric,
    v_l
  );

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'liquidacion_pagada', null,
     'S/' || to_char((v_l->>'total')::numeric, 'FM999999.00') || ' · version ' || v_ver,
     fn_persona_actual_id(),
     coalesce(nullif(trim(coalesce(p_nota, '')), ''), 'Liquidación marcada como pagada'));

  return jsonb_build_object('version', v_ver, 'total', (v_l->>'total')::numeric);
end;
$$;

grant execute on function fn_liquidacion_pagar(uuid, text) to authenticated;


-- ── ¿Sigue cuadrando? ──────────────────────────────────────────────────────
-- Nombra la diferencia concepto por concepto. Un «no cuadra» sin decir dónde
-- obliga a rehacer la cuenta entera a mano, que es lo que esto viene a evitar.
create or replace function fn_liquidacion_diferencias(p_persona_id uuid)
returns table (
  concepto  text,
  pagado    numeric,
  ahora     numeric,
  diferencia numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_f       liquidacion_pagada%rowtype;
  v_l       jsonb;
  v_cese_hoy date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede comparar una liquidación.';
  end if;

  select * into v_f from liquidacion_pagada
   where persona_id = p_persona_id
   order by version desc limit 1;
  if not found then return; end if;   -- sin foto no hay nada que comparar

  -- ⇩⇩⇩ SE RECALCULA CON LA FECHA DE CESE DE HOY, NO CON LA CONGELADA.
  --
  -- Acá decía `fn_liquidacion(p_persona_id, v_f.fecha_cese)`, o sea que volvía a
  -- calcular con la MISMA fecha con la que se pagó. Con eso la comparación no
  -- podía ver el caso más frecuente de todos: que alguien corrija el último día
  -- que la persona trabajó.
  --
  -- Medido contra el Postgres local el 2026-08-06, con una persona real de
  -- laboratorio: se paga con cese el 15/06 → S/ 3,444.31. Se descubre que trabajó
  -- hasta el 20/06 y se corrige la fecha. Le corresponden S/ 3,465.60, o sea
  -- S/ 21.29 más. `fn_liquidacion_diferencias` devolvía CERO filas y la pantalla
  -- mostraba `descuadra = false`: la fila quedaba diciendo «cesó el 20/06 ·
  -- S/ 3,444.31 · cuadra», y esas tres cosas no pueden ser ciertas a la vez.
  --
  -- La cabecera de esta migración enumera tres motivos por los que un recálculo
  -- puede dar distinto —un marcaje corregido, una vacación cargada tarde, un
  -- depósito de CTS anotado después— y la fecha de cese no estaba en la lista.
  -- Se quedó fuera por olvido, no por decisión.
  --
  -- LA FOTO NO SE TOCA: sigue guardando la fecha con la que se pagó, que es lo
  -- que hay que poder reimprimir. Lo que cambia es contra qué se compara, y para
  -- responder «¿cuánto le debemos HOY?» la fecha buena es la de hoy.
  --
  -- El `coalesce` es para quien fue reactivada: al volver a estado activo el
  -- esquema le exige `fecha_cese` en null (constraint `personas_cese_coherente`),
  -- y sin este respaldo `fn_liquidacion` abortaría con «no tiene fecha de cese».
  -- Un error ahí dejaría la lista de pendientes sin cargar entera por una sola
  -- persona.
  select p.fecha_cese into v_cese_hoy from personas p where p.id = p_persona_id;
  v_l := fn_liquidacion(p_persona_id, coalesce(v_cese_hoy, v_f.fecha_cese));

  -- La diferencia se calcula acá y no en la pantalla: es la cifra que alguien va
  -- a mirar para decidir si paga un ajuste, y no debería depender de una resta
  -- hecha en el navegador.
  return query
  select t.concepto, t.pagado, t.ahora, round(t.ahora - t.pagado, 2)
  from (values
    ('Sueldo del periodo', v_f.monto_periodo,    coalesce((v_l->'periodo'->>'monto')::numeric, 0)),
    ('Vacaciones truncas', v_f.monto_vacaciones, coalesce((v_l->'vacaciones_truncas'->>'monto')::numeric, 0)),
    ('Gratificación trunca', v_f.monto_grati,    coalesce((v_l->'gratificacion_trunca'->>'monto')::numeric, 0)),
    ('CTS trunca',         v_f.monto_cts,        coalesce((v_l->'cts_trunca'->>'monto')::numeric, 0)),
    ('TOTAL',              v_f.total,            coalesce((v_l->>'total')::numeric, 0))
  ) as t(concepto, pagado, ahora)
  where round(t.pagado, 2) <> round(t.ahora, 2);
end;
$$;

grant execute on function fn_liquidacion_diferencias(uuid) to authenticated;


-- ── La lista pendiente ahora sabe qué se pagó ──────────────────────────────
-- Si hay foto, el total que se muestra es el CONGELADO, no el recalculado: lo
-- que se transfirió no puede cambiar de cifra en pantalla.
--
-- El drop es obligatorio: se le agregan dos columnas al retorno, y `create or
-- replace` no puede cambiar el tipo de retorno de una función que ya existe
-- («cannot change return type of existing function»). Sin esto, pegar la
-- migración en una base que ya tiene la 0164 aborta.
drop function if exists fn_liquidaciones_pendientes();

create or replace function fn_liquidaciones_pendientes()
returns table (
  persona_id     uuid,
  persona        text,
  sede           text,
  fecha_ingreso  date,
  fecha_cese     date,
  vence_el       date,
  dias_restantes int,
  vencido        boolean,
  total          numeric,
  pagada         boolean,
  descuadra      boolean
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
    p.fecha_ingreso,
    p.fecha_cese,
    (p.fecha_cese + 2),
    (p.fecha_cese + 2 - fn_hoy_lima())::int,
    (fn_hoy_lima() > p.fecha_cese + 2 and f.persona_id is null),
    round(coalesce(f.total, (fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric, 0), 2),
    (f.persona_id is not null),
    (f.persona_id is not null
      and exists (select 1 from fn_liquidacion_diferencias(p.id)))
  from personas p
  left join sedes s on s.id = p.sede_base_id
  left join lateral (
    select lp.* from liquidacion_pagada lp
    where lp.persona_id = p.id order by lp.version desc limit 1
  ) f on true
  where p.estado = 'inactivo'
    and p.fecha_cese is not null
    and fn_es_admin_o_lider() is true
  order by (f.persona_id is not null), p.fecha_cese desc;
$$;

grant execute on function fn_liquidaciones_pendientes() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (167, 'la_liquidacion_pagada_se_congela')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_n int;
begin
  select count(*) into v_n from liquidacion_pagada;
  raise notice '0167 · liquidaciones congeladas: % (la tabla nace vacia)', v_n;
  raise notice '0167 · esta migracion no cambia ningun calculo: solo permite guardar el que se pago.';
end $mig$;
