-- ============================================================================
-- 0525 — Una aprobación de constancia se puede revertir, con motivo y a la vista
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que si Desarrollo Organizacional (DO) aprobó una constancia de estudios que
--   no debía aprobarse, pueda REVERTIR esa aprobación: la constancia pasa a
--   «Rechazada» con un motivo (uno de los de siempre, más «Otro» con un texto de
--   al menos 3 letras y sin máximo), la integrante vuelve a ver que tiene que
--   enviar la corregida, y el historial del estudio cuenta las dos cosas: quién
--   la aprobó y cuándo, y quién la revirtió, cuándo y por qué.
--
--   Y que DO tenga un apartado dentro de Educación —«Aprobadas del ciclo»— con lo
--   aprobado en un periodo de planilla (29 → 28): a quién, quién lo aprobó, su
--   constancia a la vista, y desde ahí el botón de rechazar.
--
-- DECISIONES DE FELIPE (2026-10-17)
--
--   · Revertir una aprobación APAGA el pago de educación si esa era la única
--     constancia aprobada del estudio: el pago nunca debió encenderse. Si hay
--     otra aprobada, el pago sigue y solo cambia cuál es el papel que lo sostiene.
--   · Se BLOQUEA cuando el pago ya salió con esa aprobación (el grupo de la
--     persona tiene un periodo marcado pagado DESPUÉS de aprobarla y no queda
--     otra constancia aprobada): «Reabre el periodo primero», como las hermanas
--     (fn_set_feriado, fn_set_vacaciones…).
--   · El ciclo del apartado es el PERIODO DE PLANILLA (29 al 28), no el mes
--     calendario.
--
-- POR QUÉ ESTA MIGRACIÓN ES COMO ES
--
--   Desde la 0450 lo revisado no se reescribe: un trigger lo impide y su
--   mensaje promete que una constancia aprobada «queda en el historial como
--   sustento de lo que ya se pagó». Esta migración no lo rompe: abre UNA sola
--   puerta —aprobada → rechazada— y solo la cruza `fn_educacion_revertir_
--   aprobacion`. El trigger la reconoce por tres cosas a la vez: el estado
--   anterior y el nuevo, que la escritura venga de una función interna
--   (`current_user = 'postgres'`; un cliente por PostgREST es `authenticated`) y
--   que lleve la marca de la reversión. Sin las tres, sigue rechazando todo.
--
--   Nada se borra: la fila de la constancia es la misma, con su misma fecha de
--   envío y sus mismos archivos. Lo que se agrega son cuatro columnas que
--   guardan la aprobación ORIGINAL (`aprobada_at`, `aprobada_por`) y la reversión
--   (`aprobacion_revertida_at`, `aprobacion_revertida_por`), porque `revisada_*`
--   pasa a decir quién la rechazó. Además queda su fila en `correcciones_auditoria`.
--
--   El pago no se toca desde aquí. El espejo de la 0450 (`fn_educacion_
--   refrescar_espejo`, disparado por el trigger de siempre al cambiar el estado)
--   es quien mira «¿queda alguna aprobada?» y deja o quita el `comprobante_url`
--   en el que se apoya la planilla. Esta migración NO reescribe la planilla ni el
--   espejo, y la planilla sigue preguntando lo mismo de siempre.
--
--   El calendario retrocede solo cuando corresponde: al aprobar, la próxima fecha
--   de pago de la institución avanzó; al revertir, si fue ESA aprobación la que
--   la avanzó y no hay otra más reciente, vuelve a la fecha de ESE pago (hay una
--   constancia que ya no vale y el sistema la vuelve a pedir). Si no la había
--   movido, o hay una aprobada más reciente, el calendario no se mueve.
--
-- QUÉ ASUME
--
--   · md5 de PARTIDA de las dos funciones que se reescriben. LOCAL (= repositorio,
--     0450): fn_educacion_entrega_inmutable dc4ba3e15e995ad1e249a5660cfcca5d ·
--     1045 caracteres; fn_educacion_entregas d4c4fe5bfbcbd5c35112aa4a5a5bfdd1 ·
--     1126. Sus variantes pegadas desde Windows (\r\n): 1ac7fc1069cb615e575133ab20687fd9 y
--     da5a3e20484c423c984ed7fb0fb3895f (los cuerpos no traen comentarios, así que no hay
--     variante «sin comentarios»). PRODUCCIÓN: no medido antes de entregar (2026-10-17, a
--     pedido de Felipe); la sección 0 compara contra esas cuatro y, si producción tiene
--     cualquier otra versión, PARA sin aplicar nada.
--   · Las funciones de pago por grupo (0323): `periodo_grupo_pago.grupo` =
--     `personas.tipo_vinculo`, y una fila `estado = 'pagado'` con su `pagado_at`.
--   · fn_es_admin_o_lider, fn_persona_actual_id (0078) y que el espejo de la 0450
--     sigue colgado del trigger de `educacion_entregas`.
--
-- QUÉ NO HACE
--
--   · No cambia fn_planilla_calcular ni nada de planilla.
--   · No deja revertir una constancia propia: la revisa otra persona de DO.
--   · No revierte constancias pendientes, rechazadas ni retiradas (esas ya
--     tienen su salida), ni toca los archivos.
--   · No manda correos. La integrante lo ve porque su constancia vuelve a
--     «Rechazada», con el motivo que escribió DO.
--
-- CÓMO SE REVIERTE
--
--   Las constancias ya revertidas quedan como «rechazadas» sin su marca si se
--   quitan las columnas: guardar antes `select * from educacion_entregas where
--   aprobacion_revertida_at is not null`.
--
--   drop function if exists fn_educacion_revertir_aprobacion(uuid, text, text);
--   drop function if exists fn_educacion_revertir_efecto(uuid);
--   drop function if exists fn_educacion_aprobadas_del_periodo(uuid);
--   -- fn_educacion_entrega_inmutable y fn_educacion_entregas: volver a pegar de
--   -- la 0450 (la segunda con `drop function` antes: devuelve TABLE).
--   alter table educacion_entregas
--     drop column if exists aprobacion_revertida_por, drop column if exists aprobacion_revertida_at,
--     drop column if exists aprobada_por, drop column if exists aprobada_at;
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ───────────────────────────────────────
-- Mismo patrón que la 0323: si producción no está en la versión de partida
-- declarada arriba, esta migración no aplica NADA. Reescribir desde un cuerpo
-- que no es el vigente revierte en silencio lo que se arregló entre medias.
do $$
declare v_md5 text; v_len int;
begin
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_educacion_entrega_inmutable';
  -- Si ya está esta migración puesta, el cuerpo lleva su marca: repegar es seguro.
  -- Se acepta el cuerpo de la 0450 tal cual o pegado desde Windows (cada salto como \r\n): es el mismo
  -- código (ver CLAUDE.md, la 0401). Sus comentarios no cambian nada: el cuerpo no trae ninguno.
  if v_md5 not in ('dc4ba3e15e995ad1e249a5660cfcca5d', '1ac7fc1069cb615e575133ab20687fd9')
     and not exists (select 1 from pg_proc p where p.proname = 'fn_educacion_entrega_inmutable'
                        and p.prosrc like '%CAMBIO 0525%') then
    raise exception '0525 · PARA. fn_educacion_entrega_inmutable en esta base es % (% caracteres), se esperaba dc4ba3e15e995ad1e249a5660cfcca5d (1045). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_educacion_entrega_inmutable.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_educacion_entregas';
  if v_md5 not in ('d4c4fe5bfbcbd5c35112aa4a5a5bfdd1', 'da5a3e20484c423c984ed7fb0fb3895f')
     and not exists (select 1 from pg_proc p where p.proname = 'fn_educacion_entregas'
                        and p.prosrc like '%CAMBIO 0525%') then
    raise exception '0525 · PARA. fn_educacion_entregas en esta base es % (% caracteres), se esperaba d4c4fe5bfbcbd5c35112aa4a5a5bfdd1 (1126). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_educacion_entregas.', v_md5, v_len;
  end if;
end $$;


-- ── A · Las cuatro columnas ─────────────────────────────────────────────────
-- La aprobación original se conserva aparte: `revisada_*` pasa a decir quién
-- RECHAZÓ. Las dos parejas nacen vacías y solo la función de abajo las llena.
alter table educacion_entregas
  add column if not exists aprobada_at              timestamptz,
  add column if not exists aprobada_por             uuid references personas(id),
  add column if not exists aprobacion_revertida_at  timestamptz,
  add column if not exists aprobacion_revertida_por uuid references personas(id);

alter table educacion_entregas drop constraint if exists educacion_entrega_reversion_completa;
alter table educacion_entregas add constraint educacion_entrega_reversion_completa check (
  (aprobacion_revertida_at is null and aprobacion_revertida_por is null
     and aprobada_at is null and aprobada_por is null)
  or (aprobacion_revertida_at is not null and aprobacion_revertida_por is not null
      and aprobada_at is not null and estado = 'rechazada')
);
comment on column educacion_entregas.aprobacion_revertida_at is
  'Cuándo DO revirtió una aprobación (0525). Solo lo escribe fn_educacion_revertir_aprobacion; una constancia revertida es siempre «rechazada» y conserva aquí y en aprobada_* quién la aprobó y cuándo.';


-- ── B · La única puerta: aprobada → rechazada, por la función ───────────────
-- CAMBIO 0525 respecto de la 0450: el bloque «única puerta» y las cuatro
-- columnas nuevas dentro de lo que no se puede cambiar.
create or replace function fn_educacion_entrega_inmutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception
      'Una entrega de constancia no se borra: se retira mientras está pendiente, o queda en el historial.';
  end if;

  if (new.id, new.fecha_pago, new.tipo, new.proxima_fecha_pago, new.nota, new.origen,
      new.enviada_at, new.enviada_por, new.reemplaza_a)
     is distinct from
     (old.id, old.fecha_pago, old.tipo, old.proxima_fecha_pago, old.nota, old.origen,
      old.enviada_at, old.enviada_por, old.reemplaza_a) then
    raise exception 'Lo que se envió en una constancia no se reescribe. Si hay que corregirlo, se envía otra.';
  end if;

  -- CAMBIO 0525 · la única puerta. Una aprobación se revierte, y solo por
  -- fn_educacion_revertir_aprobacion: las tres condiciones juntas. `current_user`
  -- es 'postgres' dentro de una función SECURITY DEFINER y 'authenticated' para
  -- un cliente por PostgREST.
  if old.estado = 'aprobada' and new.estado = 'rechazada'
     and current_user = 'postgres'
     and old.aprobacion_revertida_at is null
     and new.aprobacion_revertida_at is not null
     and new.aprobacion_revertida_por is not null then
    return new;
  end if;

  if old.estado <> 'pendiente'
     and (new.estado, new.revisada_at, new.revisada_por, new.retirada_at,
          new.motivo_categoria, new.motivo_comentario,
          new.aprobada_at, new.aprobada_por,
          new.aprobacion_revertida_at, new.aprobacion_revertida_por)
         is distinct from
         (old.estado, old.revisada_at, old.revisada_por, old.retirada_at,
          old.motivo_categoria, old.motivo_comentario,
          old.aprobada_at, old.aprobada_por,
          old.aprobacion_revertida_at, old.aprobacion_revertida_por) then
    raise exception 'Esta constancia ya está %: su revisión no se cambia.', old.estado;
  end if;

  return new;
end;
$$;


-- ── C · Qué pasaría si se revirtiera (lo lee la pantalla ANTES de confirmar) ─
-- Una sola definición de «apaga el pago» y de «está bloqueado»: la usan la
-- pantalla, para avisar, y la función que revierte, para decidir.
create or replace function fn_educacion_revertir_efecto(p_id uuid)
returns table (apaga_pago boolean, bloqueada boolean, mensaje text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_e       educacion_entregas%rowtype;
  v_fam     uuid;
  v_persona uuid;
  v_grupo   text;
  v_otras   int;
  v_apaga   boolean;
  v_bloq    boolean := false;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional revisa constancias de educación.';
  end if;

  select * into v_e from educacion_entregas where id = p_id;
  if not found then raise exception 'Esa constancia no existe.'; end if;
  if v_e.estado <> 'aprobada' then
    raise exception 'Solo se revierte una constancia aprobada: esta está %.', v_e.estado;
  end if;

  select a.familia_id, a.persona_id into v_fam, v_persona
    from asignaciones_educacion a where a.id = v_e.asignacion_id;

  select count(*)::int into v_otras
    from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
   where x.familia_id = v_fam and e.estado = 'aprobada' and e.id <> p_id;
  v_apaga := (v_otras = 0);

  if v_apaga then
    select pe.tipo_vinculo into v_grupo from personas pe where pe.id = v_persona;
    -- Sin fila en periodo_grupo_pago = no pagado (0323). Un periodo marcado
    -- pagado ANTES de aprobar esta constancia no la usó; uno marcado después, sí
    -- pudo pagar la educación con ella.
    v_bloq := exists (
      select 1 from periodo_grupo_pago g
       where g.grupo = v_grupo and g.estado = 'pagado'
         and g.pagado_at >= coalesce(v_e.aprobada_at, v_e.revisada_at, v_e.enviada_at));
  end if;

  apaga_pago := v_apaga;
  bloqueada  := v_bloq;
  mensaje := case
    when v_bloq  then 'Esta constancia sostiene el pago de educación y el periodo ya se pagó con ella. Reabre el periodo primero (Planilla → revertir el pago) y vuelve a intentarlo.'
    when v_apaga then 'Es la única constancia aprobada de este estudio: al rechazarla, el apoyo deja de pagarse en la planilla hasta que se apruebe otra.'
    else 'Hay otras constancias aprobadas de este estudio: el pago no cambia, solo deja de contar esta.'
  end;
  return next;
end;
$$;


-- ── D · Revertir ────────────────────────────────────────────────────────────
create or replace function fn_educacion_revertir_aprobacion(
  p_id         uuid,
  p_categoria  text,
  p_comentario text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_e       educacion_entregas%rowtype;
  v_fam     uuid;
  v_persona uuid;
  v_ef      record;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional revisa constancias de educación.';
  end if;

  -- `for update`: dos personas de DO sobre la misma constancia se ordenan.
  select * into v_e from educacion_entregas where id = p_id for update;
  if not found then raise exception 'Esa constancia no existe.'; end if;

  select a.familia_id, a.persona_id into v_fam, v_persona
    from asignaciones_educacion a where a.id = v_e.asignacion_id;

  if v_e.estado <> 'aprobada' then
    raise exception 'Solo se revierte una constancia aprobada: esta está %.', v_e.estado;
  end if;
  if v_persona = v_yo then
    raise exception 'No puedes revisar tu propia constancia: la revisa otra persona de Desarrollo Organizacional.';
  end if;

  if p_categoria is null or p_categoria not in
     ('ilegible', 'no_corresponde_al_pago', 'a_nombre_de_otra_persona',
      'faltan_paginas_o_datos', 'otra_institucion', 'otro') then
    raise exception 'Elige el motivo del rechazo.';
  end if;
  if p_comentario is null or length(trim(p_comentario)) < 3 then
    raise exception 'Escribe qué tiene que corregir: la integrante lo va a leer.';
  end if;

  select * into v_ef from fn_educacion_revertir_efecto(p_id);
  if v_ef.bloqueada then
    raise exception '%', v_ef.mensaje;
  end if;

  update educacion_entregas
     set estado = 'rechazada',
         aprobada_at = v_e.revisada_at, aprobada_por = v_e.revisada_por,
         revisada_at = now(), revisada_por = v_yo,
         motivo_categoria = p_categoria, motivo_comentario = trim(p_comentario),
         aprobacion_revertida_at = now(), aprobacion_revertida_por = v_yo
   where id = p_id;
  -- El trigger de la 0450 recalcula el espejo (comprobante_url) por su cuenta.

  -- El calendario: solo retrocede si fue ESTA aprobación la que lo avanzó (la
  -- próxima fecha de la familia es la que esta constancia declaró) y no hay una
  -- aprobada más reciente. Entonces vuelve al pago que ahora no tiene constancia.
  -- Si no, no se mueve: una constancia que no avanzó el calendario no lo retrasa.
  if not exists (select 1
                   from educacion_entregas e join asignaciones_educacion x on x.id = e.asignacion_id
                  where x.familia_id = v_fam and e.estado = 'aprobada'
                    and e.fecha_pago > v_e.fecha_pago) then
    update asignaciones_educacion
       set proxima_fecha_pago = v_e.fecha_pago
     where familia_id = v_fam
       and proxima_fecha_pago is not distinct from v_e.proxima_fecha_pago
       and proxima_fecha_pago > v_e.fecha_pago;
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_persona, 'educacion_entrega', 'aprobada', 'rechazada · ' || p_categoria, v_yo,
     'Aprobación revertida: ' || trim(p_comentario));
end;
$$;


-- ── E · Lo aprobado en un periodo de planilla ───────────────────────────────
-- «Aprobado en el periodo» es por la FECHA EN QUE DO APROBÓ, no por la del pago:
-- la pregunta de DO es «¿a quién aprobamos en este ciclo?».
create or replace function fn_educacion_aprobadas_del_periodo(p_periodo_id uuid)
returns table (
  entrega_id          uuid,
  familia_id          uuid,
  persona_id          uuid,
  persona             text,
  sede                text,
  institucion         text,
  beneficiario_nombre text,
  fecha_pago          date,
  tipo                text,
  origen              text,
  aprobada_at         timestamptz,
  aprobada_por        text,
  archivos            jsonb,
  apaga_pago          boolean,
  bloqueada           boolean,
  aviso               text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ini timestamptz;
  v_fin timestamptz;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve las constancias aprobadas.';
  end if;

  select (pp.fecha_ini::timestamp) at time zone 'America/Lima',
         ((pp.fecha_fin + 1)::timestamp) at time zone 'America/Lima'
    into v_ini, v_fin
    from periodos_planilla pp where pp.id = p_periodo_id;
  if v_ini is null then raise exception 'Ese periodo no existe.'; end if;

  return query
  select e.id, a.familia_id, a.persona_id,
         pe.nombres || ' ' || pe.apellidos,
         coalesce(s.codigo, '?'),
         a.institucion, a.beneficiario_nombre,
         e.fecha_pago, e.tipo, e.origen,
         e.revisada_at,
         rev.nombres || ' ' || rev.apellidos,
         coalesce((select jsonb_agg(jsonb_build_object(
                     'id', ar.id, 'ruta', ar.storage_path, 'nombre', ar.nombre,
                     'tipo_mime', ar.tipo_mime, 'bytes', ar.bytes) order by ar.orden, ar.id)
                     from educacion_entrega_archivos ar where ar.entrega_id = e.id), '[]'::jsonb),
         ef.apaga_pago, ef.bloqueada, ef.mensaje
    from educacion_entregas e
    join asignaciones_educacion a on a.id = e.asignacion_id
    join personas pe on pe.id = a.persona_id
    left join sedes s on s.id = pe.sede_base_id
    left join personas rev on rev.id = e.revisada_por
    cross join lateral fn_educacion_revertir_efecto(e.id) ef
   where e.estado = 'aprobada'
     and e.revisada_at >= v_ini and e.revisada_at < v_fin
   order by pe.apellidos, pe.nombres, a.institucion, e.fecha_pago desc, e.id desc;
end;
$$;


-- ── F · El historial cuenta las dos cosas ───────────────────────────────────
-- CAMBIO 0525 respecto de la 0450: cuatro columnas al final (la aprobación
-- original y la reversión). Devuelve TABLE, así que no admite `create or
-- replace` con otra forma: se suelta y se vuelve a crear.
drop function if exists fn_educacion_entregas(uuid);
create function fn_educacion_entregas(p_familia_id uuid)
returns table (
  id                 uuid,
  asignacion_id      uuid,
  fecha_pago         date,
  tipo               text,
  proxima_fecha_pago date,
  nota               text,
  estado             text,
  origen             text,
  enviada_at         timestamptz,
  enviada_por        text,
  revisada_at        timestamptz,
  revisada_por       text,
  retirada_at        timestamptz,
  motivo_categoria   text,
  motivo_comentario  text,
  reemplaza_a        uuid,
  archivos           jsonb,
  aprobada_at        timestamptz,
  aprobada_por       text,
  revertida_at       timestamptz,
  revertida_por      text
)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.asignacion_id, e.fecha_pago, e.tipo, e.proxima_fecha_pago, e.nota,
         e.estado, e.origen, e.enviada_at,
         case when fn_es_admin_o_lider() is true then env.nombres || ' ' || env.apellidos end,
         e.revisada_at,
         case when fn_es_admin_o_lider() is true then rev.nombres || ' ' || rev.apellidos end,
         e.retirada_at, e.motivo_categoria, e.motivo_comentario, e.reemplaza_a,
         coalesce((select jsonb_agg(jsonb_build_object(
                     'id', ar.id, 'ruta', ar.storage_path, 'nombre', ar.nombre,
                     'tipo_mime', ar.tipo_mime, 'bytes', ar.bytes) order by ar.orden, ar.id)
                     from educacion_entrega_archivos ar where ar.entrega_id = e.id), '[]'::jsonb),
         -- CAMBIO 0525
         e.aprobada_at,
         case when fn_es_admin_o_lider() is true then apr.nombres || ' ' || apr.apellidos end,
         e.aprobacion_revertida_at,
         case when fn_es_admin_o_lider() is true then rvt.nombres || ' ' || rvt.apellidos end
    from educacion_entregas e
    join asignaciones_educacion a on a.id = e.asignacion_id
    left join personas env on env.id = e.enviada_por
    left join personas rev on rev.id = e.revisada_por
    left join personas apr on apr.id = e.aprobada_por
    left join personas rvt on rvt.id = e.aprobacion_revertida_por
   where a.familia_id = p_familia_id
     and (fn_es_admin_o_lider() is true or a.persona_id = fn_persona_actual_id())
   order by e.fecha_pago desc, e.enviada_at desc, e.id desc;
$$;


-- ── G · Quién puede llamar a qué ────────────────────────────────────────────
grant execute on function fn_educacion_entregas(uuid)                     to authenticated;
grant execute on function fn_educacion_revertir_efecto(uuid)              to authenticated;
grant execute on function fn_educacion_revertir_aprobacion(uuid,text,text) to authenticated;
grant execute on function fn_educacion_aprobadas_del_periodo(uuid)        to authenticated;
revoke execute on function fn_educacion_entregas(uuid)                     from public, anon;
revoke execute on function fn_educacion_revertir_efecto(uuid)              from public, anon;
revoke execute on function fn_educacion_revertir_aprobacion(uuid,text,text) from public, anon;
revoke execute on function fn_educacion_aprobadas_del_periodo(uuid)        from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (525, 'una_aprobacion_de_constancia_se_puede_revertir')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN (un solo select; el SQL Editor corre solo el último) ────────
-- Antes de pegar, md5 de partida contra producción:
--   select p.proname, md5(p.prosrc), length(p.prosrc)
--     from pg_proc p where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('fn_educacion_entrega_inmutable', 'fn_educacion_entregas');
-- Después de pegar:
--   select (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 525) as registro,
--          (select count(*) from information_schema.columns
--            where table_name = 'educacion_entregas'
--              and column_name in ('aprobada_at', 'aprobada_por', 'aprobacion_revertida_at', 'aprobacion_revertida_por')) as columnas,
--          (select count(*) from pg_proc where proname in
--             ('fn_educacion_revertir_aprobacion', 'fn_educacion_revertir_efecto', 'fn_educacion_aprobadas_del_periodo')) as funciones,
--          (select prosrc like '%CAMBIO 0525%' from pg_proc where proname = 'fn_educacion_entrega_inmutable') as el_trigger,
--          (select prosrc like '%CAMBIO 0525%' from pg_proc where proname = 'fn_educacion_entregas') as el_historial;
