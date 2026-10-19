-- ============================================================================
-- 0536 · LA PRUEBA DE TRES DÍAS
-- ============================================================================
--
-- QUÉ PROMETE (el contrato, en tres líneas)
--   1. Toda persona activa con vínculo «Prueba» tiene UNA prueba abierta
--      (`pruebas`), con su fecha de inicio. Sus días se cuentan de las
--      jornadas cerradas desde esa fecha; nunca se guardan.
--   2. La prueba se cierra por una sola puerta, `fn_prueba_cerrar`, que la
--      pueden usar DO, administración y la líder de equipo DE LA SEDE de la
--      persona. Cerrar = registrar el resultado («no apto» o «se retiró»), el
--      motivo y quién lo decidió, y dar de baja a la persona en el mismo acto
--      (todo o nada).
--   3. Lo que NO promete: no cambia un sol de lo que se paga. Quién cobra qué
--      cuando una prueba se cierra es la migración siguiente (ver «QUÉ NO
--      HACE»).
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-19, con preguntas)
--   · «Para los que están de prueba no se hace contrato: tienen 3 días de
--     prueba; si pasan, recién ahí se hace contrato, y ese plazo debe avisarse.»
--   · Los tres días son DÍAS TRABAJADOS (con jornada cerrada), no de calendario.
--   · Durante la prueba se puede marcar «no apto» (se le paga lo trabajado) o
--     «se retiró» (no se le paga). Después de los tres días: contrato.
--   · Si pasa el plazo y nadie decidió: alerta a DO, y la persona sigue
--     marcando — no se corta a nadie por un olvido de papeleo.
--   · Decide DO, administración o la líder de equipo, SOLA, sin confirmación
--     de DO.
--   · Fecha de cese = el último día trabajado (editable, nunca anterior).
--
--   Objeción registrada de quien lo construyó: negar el pago de lo trabajado a
--   quien se retira es una deuda remunerativa reclamable (Constitución art. 23),
--   y que una líder lo decida sola sin hoja firmada por la persona deja sin
--   prueba que conocía la regla. Felipe lo decidió así; la mitigación que sí se
--   construyó es el rastro: cada cierre queda en `correcciones_auditoria` con
--   su motivo y su autora, y (migración siguiente) sale en la Bandeja de DO.
--
-- QUÉ ASUME
--   · La 0535 pegada: `fn_cese_aplicar` existe. Esta migración se NIEGA a
--     entrar si no (ver el bloque de guardia justo debajo). Y hace falta
--     comprobar ANTES de pegar que la 0535 esté aplicada:
--         select count(*) from pg_proc where proname = 'fn_cese_aplicar';  -- 1
--   · `personas.tipo_vinculo = 'prueba'` ya existe (0085) y la planilla ya la
--     trata como «en planilla sin beneficios», sin EsSalud (0484).
--   · `jornadas.estado` ∈ abierta · en_pausa · cerrada · auto_cerrada_pendiente
--     · revisada. Un día cuenta cuando la jornada YA NO está abierta ni en
--     pausa: incluye la auto-cerrada (quien olvidó marcar la salida sí vino).
--
-- ESTADOS QUE NUNCA DEBEN EXISTIR (y cómo los hace imposibles el esquema)
--   · Dos pruebas abiertas de la misma persona .......... índice único parcial
--   · Una prueba cerrada sin quién ni cuándo ............. check de coherencia
--   · «No apto» o «se retiró» sin motivo ................. check (≥ 3 letras)
--   · Una prueba abierta con resultado, o cerrada sin él .. check de coherencia
--   · Escribir `pruebas` desde el navegador ............... sin `grant` de
--       escritura (solo `select`, y por fila): no hay UPDATE directo que cerrar
--
-- POR QUÉ ASÍ
--   · SE REUSA EL VÍNCULO «PRUEBA», no se inventa otro concepto: el terminal, la
--     planilla y las etiquetas ya entienden «prueba». `pruebas` solo guarda los
--     HECHOS de cada prueba (inicio, resultado, motivo, quién), para que
--     `personas` —la tabla central— no engorde y para que quien vuelva a probar
--     deje historia.
--   · LOS DÍAS SE DERIVAN. Guardar «lleva 2 días» obligaría a mantenerlo cuando
--     se corrige una marca; las marcas son la fuente de verdad (CLAUDE.md).
--   · UN TRIGGER ABRE Y CIERRA LA PRUEBA cuando cambia el vínculo o el estado
--     —igual que el de Seguros (0528): escucha la columna y NUNCA frena el cambio
--     de vínculo, porque ese cambio mueve la planilla de una persona real—. Si
--     por lo que fuera no abre la fila, `fn_pruebas_abiertas` igual lista a esa
--     persona («sin registrar») y `fn_prueba_cerrar` la crea al vuelo.
--   · CERRAR REUTILIZA EL CESE (`fn_cese_aplicar`, 0535): no hay una segunda
--     forma de dar de baja. «Se retiró» cierra como `renuncia` y «no apto» como
--     `fin_periodo_prueba`: son dos hechos distintos y quien arma la
--     liquidación los lee así. (Hasta hoy las 13 salidas de prueba medidas en
--     producción dicen `fin_periodo_prueba`: no se sabe cuántas fueron retiros.)
--   · LA LÍDER SOLO DECIDE EN SU SEDE (`sede_base_id` igual que el de ella), por
--     el mismo molde de `fn_expediente_puede_actuar` (0510). Y nadie decide
--     sobre su propia prueba.
--   · CINCO RESULTADOS, no cuatro: además de `no_apto`, `retirado` y
--     `contratada`, está `cesada` — la persona se dio de baja por la puerta
--     general (`fn_cesar_persona`) sin pasar por aquí. No se adivina si fue no
--     apta o se retiró: queda dicho que no se registró. Sin esto quedaría una
--     prueba «abierta» de alguien inactivo.
--
-- QUÉ NO HACE (cada cosa es la siguiente etapa, no un olvido)
--   · NO TOCA LA PLANILLA. ⚠ Esta migración sola NO deja a nadie sin pago:
--     `retirado` se registra pero la planilla sigue pagando las horas, y la
--     asignación familiar sigue entera. Por eso ninguna pantalla ofrece
--     «Se retiró» hasta que la etapa de planilla (0537) esté pegada: el sistema
--     no puede decir «no se paga» mientras paga.
--   · No guarda las fotos del DNI ni los nombres (viven en `personas` y
--     `datos_personales`; los pide el formulario de Contratos → Nuevo documento →
--     Prueba, que es una pantalla).
--   · No hace el contrato. «Pasar a Planilla» cuando el contrato queda firmado
--     es de la pantalla de Contratos; aquí solo se registra (`contratada`) que
--     el vínculo dejó de ser «Prueba».
--   · No crea nada visible: ninguna pantalla lee `pruebas` todavía.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_pruebas_vinculo on personas;
--   drop function if exists fn_trg_pruebas_vinculo();
--   drop function if exists fn_prueba_cerrar(uuid, text, text, date);
--   drop function if exists fn_pruebas_abiertas();
--   drop function if exists fn_prueba_puede_actuar(uuid);
--   drop function if exists fn_prueba_dias_trabajados(uuid, date, date);
--   drop function if exists fn_prueba_dias_plazo();
--   drop table if exists pruebas;      -- solo si aún no hay cierres que conservar
--   Ninguna persona cambia: `personas` no se toca. Los ceses ya hechos por
--   `fn_prueba_cerrar` quedan hechos (son ceses normales, con su rastro).
--   ⚠ Si la 0537 ya está pegada, revertirla PRIMERO (volver al cuerpo de la 0524):
--   desde la 0537 el cálculo de la planilla LEE `pruebas`, y borrar la tabla con
--   ella puesta hace fallar la planilla de todo el equipo.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 429.
-- ============================================================================

-- ── Guardia: sin la 0535 no se entra ─────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'fn_cese_aplicar') then
    raise exception 'PARA. Falta la 0535: fn_cese_aplicar no existe, y fn_prueba_cerrar no tendría con qué dar de baja. Pega primero la 0535.';
  end if;
end $$;

-- ── 1 · La tabla ─────────────────────────────────────────────────────────────
create table if not exists pruebas (
  id           uuid primary key default gen_random_uuid(),
  persona_id   uuid not null references personas(id),
  inicio       date not null,
  resultado    text not null default 'en_curso'
    check (resultado in ('en_curso', 'no_apto', 'retirado', 'contratada', 'cesada')),
  motivo       text,
  cerrada_por  uuid references personas(id),
  cerrada_at   timestamptz,
  cerrada_fecha date,
  creada_at    timestamptz not null default now(),
  constraint pruebas_cierre_coherente check (
       (resultado = 'en_curso'
          and cerrada_at is null and cerrada_por is null
          and cerrada_fecha is null and motivo is null)
    or (resultado in ('no_apto', 'retirado')
          and cerrada_at is not null and cerrada_por is not null
          and cerrada_fecha is not null
          and length(btrim(coalesce(motivo, ''))) >= 3)
    or (resultado in ('contratada', 'cesada')
          and cerrada_at is not null)
  )
);

comment on table pruebas is
  'Los hechos de cada prueba de tres días de una persona (0536): inicio, resultado, motivo y quién decidió. '
  'Los días trabajados NO se guardan: se cuentan de las jornadas cerradas desde `inicio`. '
  'Se escribe solo por fn_prueba_cerrar y por el trigger de personas; el navegador solo lee.';
comment on column pruebas.resultado is
  'en_curso · no_apto (se le paga lo trabajado) · retirado (se fue por su cuenta) · contratada (el vínculo dejó de ser «prueba») · '
  'cesada (se dio de baja por la puerta general sin decidir aquí cuál de los dos fue).';
comment on column pruebas.cerrada_fecha is
  'El último día trabajado, que es también la fecha de cese. Solo para no_apto y retirado.';

-- Una persona, una prueba abierta. Este índice es lo que hace imposible el
-- estado «dos pruebas abiertas»; no hay un `if` que lo detecte.
create unique index if not exists pruebas_una_abierta_por_persona
  on pruebas (persona_id) where resultado = 'en_curso';
create index if not exists pruebas_por_persona on pruebas (persona_id, inicio desc);

-- ── 2 · Quién puede actuar sobre la prueba de quién ──────────────────────────
-- DO y administración, sobre cualquiera; la líder de equipo, solo sobre la gente
-- de SU sede. Null-safe: sin sesión, o sin sede, la respuesta es «no».
create or replace function fn_prueba_puede_actuar(p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(fn_es_admin_o_lider(), false)
      or coalesce(
           fn_rol_actual() = 'supervisor_sede'
           and (select p.sede_base_id from personas p where p.id = p_persona_id) = fn_sede_actual_persona(),
           false);
$$;

revoke execute on function fn_prueba_puede_actuar(uuid) from public, anon;
grant  execute on function fn_prueba_puede_actuar(uuid) to authenticated;

comment on function fn_prueba_puede_actuar(uuid) is
  'true si quien llama puede ver y cerrar la prueba de esa persona: admin y líder DO sobre cualquiera; '
  'la líder de equipo solo si la persona es de su sede (0536). Mismo molde que fn_expediente_puede_actuar (0510).';

-- ── 3 · Seguridad de la tabla ────────────────────────────────────────────────
alter table pruebas enable row level security;

drop policy if exists pruebas_select on pruebas;
create policy pruebas_select on pruebas
  for select to authenticated using (fn_prueba_puede_actuar(persona_id) is true);

revoke all on pruebas from anon, authenticated, public;
grant  select on pruebas to authenticated;

-- ── 4 · El plazo y los días ──────────────────────────────────────────────────
-- Los tres días se dicen una sola vez. Las pantallas lo reciben como columna
-- (`dias_plazo`) y no lo repiten.
create or replace function fn_prueba_dias_plazo()
returns integer
language sql
immutable
as $$ select 3; $$;

revoke execute on function fn_prueba_dias_plazo() from public, anon;
grant  execute on function fn_prueba_dias_plazo() to authenticated;

-- Cuántos días trabajó la persona entre `p_desde` y `p_hasta`. Interna: ninguna
-- sesión del navegador la llama (cuenta jornadas de cualquiera).
create or replace function fn_prueba_dias_trabajados(p_persona_id uuid, p_desde date, p_hasta date default null)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from jornadas j
   where j.persona_id = p_persona_id
     and j.fecha >= p_desde
     and (p_hasta is null or j.fecha <= p_hasta)
     and j.entrada_ts is not null
     and j.estado in ('cerrada', 'auto_cerrada_pendiente', 'revisada');
$$;

revoke execute on function fn_prueba_dias_trabajados(uuid, date, date) from public, anon, authenticated;

comment on function fn_prueba_dias_trabajados(uuid, date, date) is
  'Días con jornada cerrada (incluye la auto-cerrada y la revisada) desde `p_desde` (0536). Interna.';

-- ── 5 · Quién está de prueba hoy y en qué día va ─────────────────────────────
-- «situacion»: en_curso (le faltan días) · cumplida (ya trabajó los tres: toca
-- decidir) · vencida (trabajó más de tres y nadie decidió). La ve DO (todas) y la
-- líder (las de su sede). Incluye a quien está en vínculo «Prueba» pero no tiene
-- fila (`registrada = false`): el trigger nunca frena un cambio, así que esa
-- persona no se puede quedar sin aparecer.
create or replace function fn_pruebas_abiertas()
returns table (
  prueba_id       uuid,
  persona_id      uuid,
  nombres         text,
  apellidos       text,
  sede_id         uuid,
  sede_codigo     text,
  inicio          date,
  dias_trabajados integer,
  dias_plazo      integer,
  situacion       text,
  ultima_jornada  date,
  registrada      boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select pr.id,
         p.id,
         p.nombres,
         p.apellidos,
         p.sede_base_id,
         s.codigo,
         coalesce(pr.inicio, p.fecha_ingreso),
         d.dias,
         fn_prueba_dias_plazo(),
         case when d.dias < fn_prueba_dias_plazo() then 'en_curso'
              when d.dias = fn_prueba_dias_plazo() then 'cumplida'
              else 'vencida' end,
         d.ultima,
         pr.id is not null
    from personas p
    left join sedes s  on s.id = p.sede_base_id
    left join pruebas pr on pr.persona_id = p.id and pr.resultado = 'en_curso'
    cross join lateral (
      select fn_prueba_dias_trabajados(p.id, coalesce(pr.inicio, p.fecha_ingreso)) as dias,
             (select max(j.fecha) from jornadas j
               where j.persona_id = p.id
                 and j.fecha >= coalesce(pr.inicio, p.fecha_ingreso)
                 and j.entrada_ts is not null) as ultima
    ) d
   where p.estado = 'activo'
     and p.tipo_vinculo = 'prueba'
     and not coalesce(p.cuenta_de_servicio, false)
     and fn_prueba_puede_actuar(p.id) is true
   order by case when d.dias > fn_prueba_dias_plazo() then 0
                 when d.dias = fn_prueba_dias_plazo() then 1
                 else 2 end,
            coalesce(pr.inicio, p.fecha_ingreso),
            p.apellidos, p.nombres, p.id;
$$;

revoke execute on function fn_pruebas_abiertas() from public, anon;
grant  execute on function fn_pruebas_abiertas() to authenticated;

comment on function fn_pruebas_abiertas() is
  'Las personas activas en vínculo «Prueba» que quien llama puede ver, con su día de prueba y su situación '
  '(en_curso · cumplida · vencida). Primero las vencidas (0536).';

-- ── 6 · Cerrar la prueba: la única puerta ───────────────────────────────────
-- Todo o nada: el resultado y la baja se escriben juntos o no se escribe nada.
-- Si el cese rebota (periodo ya pagado, un tramo futuro…), el `update` de
-- `pruebas` se deshace con él.
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
   where j.persona_id = p_persona_id and j.fecha >= v_pr.inicio and j.entrada_ts is not null;
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

revoke execute on function fn_prueba_cerrar(uuid, text, text, date) from public, anon;
grant  execute on function fn_prueba_cerrar(uuid, text, text, date) to authenticated;

comment on function fn_prueba_cerrar(uuid, text, text, date) is
  'Única forma de cerrar una prueba: registra el resultado (no_apto · retirado), el motivo y quién decidió, y da de baja a la persona '
  'con fn_cese_aplicar en el mismo acto. La puede usar DO, administración y la líder de equipo de la sede de la persona (0536). '
  'No cambia lo que se paga: eso es de la etapa de planilla.';

-- ── 7 · El trigger: abrir cuando entra a prueba, cerrar cuando sale ─────────
-- Escucha el vínculo y el estado de `personas`. NUNCA frena el cambio: un error
-- suyo es un aviso (`raise warning`), no un fallo — igual que el de Seguros
-- (0528), porque ese cambio mueve la planilla de una persona real.
create or replace function fn_trg_pruebas_vinculo()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  begin
    if tg_op = 'UPDATE'
       and old.tipo_vinculo is not distinct from new.tipo_vinculo
       and old.estado is not distinct from new.estado then
      return new;
    end if;

    if new.estado = 'activo' and new.tipo_vinculo = 'prueba'
       and not coalesce(new.cuenta_de_servicio, false) then
      -- Al crear a la persona la prueba arranca el día de su ingreso; si el
      -- vínculo cambia después, arranca hoy (no se le cuentan días de cuando no
      -- estaba de prueba).
      insert into pruebas (persona_id, inicio)
      values (new.id, case when tg_op = 'INSERT' then new.fecha_ingreso else fn_hoy_lima() end)
      on conflict (persona_id) where resultado = 'en_curso' do nothing;
    else
      -- Dejó de estar de prueba activa. Inactiva = se la dio de baja por otra
      -- puerta; activa con otro vínculo = se la contrató (o se le dio otro vínculo).
      update pruebas
         set resultado = case when new.estado <> 'activo' then 'cesada' else 'contratada' end,
             cerrada_at = now()
       where persona_id = new.id and resultado = 'en_curso';
    end if;
  exception when others then
    raise warning 'pruebas: no se pudo actualizar la prueba de la persona %: % (%)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$fn$;

drop trigger if exists trg_pruebas_vinculo on personas;
create trigger trg_pruebas_vinculo
  after insert or update of tipo_vinculo, estado on personas
  for each row
  execute function fn_trg_pruebas_vinculo();

-- ── 8 · Quien ya está de prueba hoy entra al flujo ───────────────────────────
-- Medido en producción el 2026-10-19: 2 personas activas con vínculo «Prueba»
-- (ingresaron el 16/10). Las 14 inactivas NO se rellenan: su historia ya está en
-- `fecha_cese` y `motivo_cese`, y nadie leería esas filas.
insert into pruebas (persona_id, inicio)
select p.id, p.fecha_ingreso
  from personas p
 where p.estado = 'activo'
   and p.tipo_vinculo = 'prueba'
   and not coalesce(p.cuenta_de_servicio, false)
   and not exists (select 1 from pruebas x where x.persona_id = p.id and x.resultado = 'en_curso');

-- ── Cómo se comprueba que entró ──────────────────────────────────────────────
select
  case
    when to_regclass('public.pruebas') is not null
     and exists (select 1 from pg_trigger where tgname = 'trg_pruebas_vinculo')
     and has_table_privilege('authenticated', 'pruebas', 'select')
     and not has_table_privilege('authenticated', 'pruebas', 'update')
     and not has_table_privilege('authenticated', 'pruebas', 'insert')
     and not has_table_privilege('authenticated', 'pruebas', 'delete')
     and (select count(*) from pg_proc where proname = 'fn_prueba_cerrar') = 1
      then '✅ la prueba de tres días entró: abiertas hoy = '
           || (select count(*) from pruebas where resultado = 'en_curso')
    else '❌ no entró completo'
  end as resultado;

insert into migraciones_aplicadas (numero, nombre) values (536, 'la_prueba_de_tres_dias')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
