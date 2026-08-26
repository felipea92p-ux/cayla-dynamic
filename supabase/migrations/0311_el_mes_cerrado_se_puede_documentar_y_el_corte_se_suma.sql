-- ============================================================================
-- 0311 — El mes cerrado se puede documentar, y el corte se SUMA al mes
-- ============================================================================
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
-- 1. Un documento de tardanzas se emite sobre un MES CALENDARIO CONCRETO, que
--    puede estar cerrado. El numeral 19.4 del Reglamento lo dice con todas sus
--    letras: el cierre del mes «no impide emitir el documento» por hechos de un
--    mes concluido. Hasta hoy el sistema lo impedía.
--
-- 2. Dentro de ese mes se cuentan SOLO las tardanzas nuevas: las posteriores a
--    la última fecha que ya cubrió un documento entregado. Las dos condiciones
--    SE SUMAN; hasta hoy se fundían en un `greatest` y ganaba la más tardía.
--
-- 3. Un día ya reprochado no vuelve a contarse NUNCA, aunque el documento que
--    lo reprochó haya caducado como antecedente (numeral 52.5). El agravante
--    caduca a los doce meses; el non bis in idem no caduca.
--
-- ── EL DEFECTO, EN CONCRETO ─────────────────────────────────────────────────
--
-- `fn_expediente_generar_tardanza` filtraba así:
--
--     j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)
--
-- De ahí salían dos averías distintas:
--
--   (a) El corte por antecedente SUSTITUÍA al corte mensual en vez de sumarse.
--       `greatest` se queda con UNA de las dos fechas, así que la otra dejaba de
--       hacer su trabajo. Con un documento anterior que cubría hasta el 20 de
--       julio, en agosto el límite era el 21 de julio: entraban al conteo los
--       diez días de julio que NO son del mes que se documenta.
--
--   (b) EL DÍA 1 DE CADA MES, LAS TARDANZAS DEL MES ANTERIOR DESAPARECÍAN.
--       `date_trunc('month', hoy)` es el día 1, así que a las 00:00 del primero
--       el mes entero que acababa de cerrar salía de la ventana y ya no se podía
--       documentar nunca. Doce veces al año, y sin ningún aviso: la pantalla
--       decía «lleva 0», que es lo mismo que dice cuando de verdad no hay nada.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que produce el mismo resultado que hoy cuando no se elige mes. El camino
--     por defecto (`p_mes` nulo, `p_al` nulo) está medido y es idéntico salvo el
--     corte, que a propósito deja de caducar.
--   · Que `hechos` guarda un array de objetos con clave `fecha` en formato
--     `YYYY-MM-DD`. Si viniera malformado, la guardia nominal devuelve `false`
--     en vez de reventar: protege menos, pero no rompe el generador.
--   · Que la suspensión se cumple en el futuro aunque los hechos sean de un mes
--     pasado. No se tocó: fijarla sobre el mes documentado la pondría en días
--     que ya ocurrieron.
--
-- ── POR QUÉ SE ELIGIÓ ASÍ ───────────────────────────────────────────────────
--
-- · `fn_tardanza_escalon_al` es una función NUEVA en vez de un argumento más en
--   `fn_tardanza_escalon`. La prueba 159 afirma la lista COMPLETA de argumentos
--   de esa función; cambiarle la aridad obliga a editar el freno para que quepa
--   el cambio, que es exactamente lo que un freno no debe permitir. La vieja
--   queda como envoltorio de una línea y conserva sus permisos.
--
-- · El generador va con `drop` + `create` y NO con `create or replace`. Añadir
--   un argumento con `create or replace` no reemplaza: CREA UNA SEGUNDA
--   función. La llamada de la pantalla encajaría en las dos y PostgREST
--   respondería «could not choose the best candidate function» — que no falla al
--   pegar la migración, falla AL ABRIR LA PANTALLA. Es el accidente 0297/0299,
--   que dejó el aviso de vacaciones muerto en producción.
--
-- · El corte del non bis in idem sale de TODOS los documentos entregados y no
--   solo de los vigentes. Antes bastaba con que un documento cumpliera doce
--   meses para que el corte cayera y sus días volvieran al conteo. Mientras la
--   ventana estuvo clavada al mes en curso eso casi no se alcanzaba; con el mes
--   por parámetro se alcanza con un clic.
--
-- · `fn_tardanza_ya_documentada` es cinturón y tirantes del corte. El corte es
--   UNA FECHA; esto es la lista NOMINAL de días. Hace falta porque
--   `periodo_hasta` es NULLABLE —`fn_expediente_crear_borrador` lo deja en null
--   por defecto— y con un documento así `max(periodo_hasta)` vale null y el
--   corte no protege nada.
--
-- · `fn_expediente_set_suspension` deja de medir la suspensión previa contra
--   `now()` y la mide contra el cierre del periodo que el documento cubre. El
--   numeral 19.1 c) dice que el antecedente agrava si fue notificado dentro de
--   los doce meses anteriores AL HECHO QUE SE EVALÚA. Documentando un mes ya
--   cerrado, una suspensión entregada DESPUÉS de ese mes no puede graduar unos
--   hechos que, cuando ocurrieron, no la tenían encima. Sin esto, el generador
--   calculaba 1 día y esta función exigía 2: un borrador imposible de arreglar
--   desde la pantalla, cuya única salida era un día sin goce de más para una
--   persona real, por un atraso de la empresa en entregar el documento anterior.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop function if exists fn_expediente_generar_tardanza(uuid, date);
--   drop function if exists fn_tardanza_escalon_al(uuid, date);
--   drop function if exists fn_tardanza_ya_documentada(uuid, date);
--   y volver a pegar la 0235 (generador), la 0246 (escalón), la 0200 (semáforo)
--   y la 0294 (días de suspensión) tal como están en el repositorio.
--
-- ── MD5 DE PARTIDA ──────────────────────────────────────────────────────────
--
-- Esta migración NO SE FÍA de que alguien haya preguntado: lo comprueba ella
-- misma más abajo y ABORTA si producción no tiene el cuerpo del que se copió.
-- La regla de la casa —pedir el md5 antes de escribir— existe porque la 0276 se
-- construyó entera sobre un cuerpo que ya no era el vigente. Un comentario no
-- frena eso; un `raise exception` sí.
--
--   fn_expediente_generar_tardanza  d16b349dfa9b0c3dccdb882c5eaf09dc  (0235)
--   fn_tardanza_escalon             1a3b4f7a4a81cb7ca54d1a6949604b28  (0246)
--   fn_tardanzas_resumen            16f4991abc454d9ddbc400be5d15defc  (0200)
--   fn_expediente_set_suspension    bdb7b70fa53698c8e8f3e61f35d7b2e4  (0294)
--
-- Se acepta también el md5 SIN COMENTARIOS de cada una: la mitad de las
-- funciones de producción se pegaron sin ellos, y eso es benigno y está
-- documentado en CLAUDE.md.
-- ============================================================================

-- ── 0 · EL FRENO: ¿producción tiene el cuerpo del que se copió esto? ────────
do $freno$
declare
  v_fn    text;
  v_tal   text;
  v_sin   text;
  v_falla text := '';
begin
  -- Si esta migración YA se aplicó, no hay nada que comprobar: las funciones son
  -- las de llegada y sus md5 no pueden ser los de partida. Sin esta salida, un
  -- segundo pegado —que una mano hace, y por eso la casa pide migraciones
  -- idempotentes— daría una alarma grave por algo que está bien.
  if exists (select 1 from migraciones_aplicadas where numero = 311) then
    raise notice '0311 ya estaba aplicada: no se comprueban los md5 de partida.';
    return;
  end if;

  for v_fn, v_tal, v_sin in
    select * from (values
      ('fn_expediente_generar_tardanza','d16b349dfa9b0c3dccdb882c5eaf09dc','281aad2810df7beb74b2a7091b7c881b'),
      ('fn_tardanza_escalon',           '1a3b4f7a4a81cb7ca54d1a6949604b28','d8e3589fbba699d0aaf4135651133ae2'),
      ('fn_tardanzas_resumen',          '16f4991abc454d9ddbc400be5d15defc','49b3cf99111e44a62bbb8b59dde44f3e'),
      ('fn_expediente_set_suspension',  'bdb7b70fa53698c8e8f3e61f35d7b2e4','ebd7d774b5f7a2e72f81fb2ed56b15e9')
    ) as t(fn, tal_cual, sin_comentarios)
  loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_fn
         and (md5(p.prosrc) = v_tal
              or md5(array_to_string(array(
                   select regexp_replace(l, '[[:space:]]*--.*$', '')
                   from unnest(string_to_array(p.prosrc, chr(10))) as l
                   where btrim(l) not like '--%'
                 ), chr(10))) = v_sin))
    then
      v_falla := v_falla || '  · ' || v_fn || chr(10);
    end if;
  end loop;

  if v_falla <> '' then
    raise exception E'PARA. Esta base no tiene el cuerpo del que se copió esta migración:\n%\nPegarla revertiría en silencio lo que haya entre medias. Corre ./scripts/donde-vive.sh sobre cada una y vuelve a construirla desde la versión vigente. (Nada se ha modificado: esto abortó antes de tocar nada.)', v_falla;
  end if;
end
$freno$;


-- ── 1 · El cierre de un día en Lima, dicho una sola vez ────────────────────
-- La medianoche que CIERRA una fecha peruana, como instante. Hace falta en tres
-- sitios de esta migración para comparar un `timestamptz` (cuándo se entregó un
-- documento) contra una `date` (hasta cuándo llega un periodo).
--
-- Va como función y no escrita tres veces por la misma razón por la que
-- `America/Lima` no se escribe fuera de `fecha-lima.ts` en el panel: ese corte
-- decide de qué lado de una frontera cae un hecho, y no puede tener dos
-- versiones. Comprobado con `donde-vive.sh` antes de crearla.
create or replace function fn_cierre_lima(p_fecha date)
returns timestamptz language sql immutable set search_path = public as $$
  select (p_fecha + 1)::timestamp at time zone 'America/Lima';
$$;

comment on function fn_cierre_lima(date) is
  'El instante en que cierra una fecha de Lima. Para comparar un timestamptz contra una date sin escribir el huso en cada sitio.';

grant  execute on function fn_cierre_lima(date) to authenticated, service_role;
revoke execute on function fn_cierre_lima(date) from public, anon;


-- ── 2 · Non bis in idem por día (arts. 52.5 y 19.1 b) ──────────────────────
-- El corte es UNA FECHA; esto es la lista NOMINAL de días ya citados.
--
-- Hace falta porque `periodo_hasta` es NULLABLE y `fn_expediente_crear_borrador`
-- lo deja en null por defecto: con un documento así, `max(periodo_hasta)` vale
-- null y el corte no protege NADA.
--
-- `firmado` entra a propósito: un documento firmado y pendiente de entrega ya
-- cita esos días en un papel con número. Es más estricto que el 52.5, y en la
-- dirección segura.
--
-- La comparación es TEXTUAL y con `jsonb_typeof` delante: un `hechos`
-- malformado deja de proteger ese día, pero no hace reventar al generador.
create or replace function fn_tardanza_ya_documentada(p_persona_id uuid, p_fecha date)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from expediente_disciplinario e
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(e.hechos) = 'array' then e.hechos else '[]'::jsonb end) h
    where e.persona_id = p_persona_id
      and e.tipo_causal = 'tardanza'
      and e.estado in ('firmado', 'entregado')
      -- ART. 19.2 a): el acta verbal no altera ningún cómputo.
      and e.nivel <> 'verbal'
      and h->>'fecha' = to_char(p_fecha, 'YYYY-MM-DD'));
$$;

comment on function fn_tardanza_ya_documentada(uuid, date) is
  'Non bis in idem por dia (arts. 52.5 y 19.1 b): un dia ya citado en un documento firmado o entregado no vuelve a citarse, aunque ese documento haya caducado como antecedente.';

grant  execute on function fn_tardanza_ya_documentada(uuid, date) to service_role;
revoke execute on function fn_tardanza_ya_documentada(uuid, date) from public, anon, authenticated;


-- ── 3 · El escalón, medido a una fecha de referencia ───────────────────────
-- Nombre NUEVO en vez de un argumento más en `fn_tardanza_escalon`: la prueba
-- 159 afirma la lista COMPLETA de argumentos de esa función, y cambiarle la
-- aridad obliga a editar el freno para que quepa el cambio. Una implementación,
-- dos puertas; la vieja queda de envoltorio y conserva su ACL, porque
-- `create or replace` no se lleva los permisos por delante.
create or replace function fn_tardanza_escalon_al(p_persona_id uuid, p_al date)
returns table(
  nivel_siguiente        text,
  minimo                 integer,
  corte                  date,
  doc_previo             uuid,
  bloqueado              boolean,
  suspension_previa_dias integer
)
language sql stable security definer set search_path = public as $$
  with al as (
    -- `p_al` nulo → `now()`, para que el camino por defecto quede idéntico al de
    -- la 0246. Con un mes cerrado, la referencia es la medianoche que lo cierra.
    select case when p_al is null then now() else fn_cierre_lima(p_al) end as ts
  ),
  docs as (
    select e.id, e.nivel, e.periodo_hasta, e.resuelto_at, e.entregado_at,
           e.suspension_dias,
           -- ART. 19.1 c): el antecedente agrava si estaba notificado «dentro de
           -- los doce meses anteriores AL HECHO QUE SE EVALÚA». Documentando un
           -- mes cerrado, un documento entregado DESPUÉS de ese mes no puede
           -- subir el escalón de unos hechos que, cuando ocurrieron, no lo
           -- tenían encima.
           --
           -- El borde es `<=` y no `<`: un documento notificado EN el instante de
           -- referencia está notificado. Con `<`, un documento entregado con
           -- `now()` dentro de la misma transacción quedaba fuera —dentro de una
           -- transacción `now()` es constante— y la escalera entera se aplanaba.
           -- Medido: siete asertos de las pruebas 174 y 238 caían, y se leían
           -- como si este cambio revirtiera la 0232/0246.
           (e.entregado_at <= al.ts)                        as ya_entregado,
           (e.entregado_at >= al.ts - interval '12 months') as vigente
    from expediente_disciplinario e cross join al
    where e.persona_id = p_persona_id
      and e.tipo_causal = 'tardanza'
      -- ART. 56: un documento firmado y NO entregado no está vigente, no agrava
      -- y no habilita el escalón siguiente.
      and e.estado = 'entregado'
      -- ART. 19.2 a): el acta de llamada de atención verbal «no es sanción, no
      -- constituye antecedente agravante y no es peldaño previo».
      and e.nivel <> 'verbal'
  ),
  vig as (select * from docs where ya_entregado and vigente),
  cuenta as (
    select
      count(*) filter (where nivel = 'imputacion')             as n_imp,
      count(*) filter (where nivel = 'suspension')             as n_susp,
      count(*) filter (where nivel = 'amonestacion')           as n_amon,
      max(suspension_dias) filter (where nivel = 'suspension') as dias_susp,
      bool_or(nivel = 'imputacion' and resuelto_at is null)    as imp_abierta
    from vig
  ),
  nobis as (
    -- EL CORTE NO CADUCA, y esto es lo que cambia respecto de la 0246: sale de
    -- TODOS los documentos entregados, no solo de los vigentes.
    --
    -- Antes bastaba con que un documento cumpliera doce meses para que el corte
    -- cayera a null y sus días volvieran al conteo. Con la ventana clavada al
    -- mes en curso eso casi no se alcanzaba; con el mes por parámetro se alcanza
    -- con un clic. El numeral 56.6 habla del «último documento ENTREGADO», no
    -- del vigente, y el 52.5 dice que los hechos ya sancionados no se recomputan
    -- «aunque el documento que los sancionó siga vigente como antecedente». El
    -- agravante caduca; el non bis in idem no.
    select max(periodo_hasta) as corte from docs
  ),
  legajo as (
    -- Las suspensiones NOTIFICADAS, hayan caducado o no: es lo que el numeral
    -- 19.6 (i) exige acreditar «obrantes en el legajo», y el legajo no caduca.
    select count(*) as n_susp from docs where nivel = 'suspension' and ya_entregado
  ),
  ultimo as (
    select id from docs where ya_entregado
     order by entregado_at desc, periodo_hasta desc, id desc limit 1
  )
  select
    case
      -- Dos suspensiones vigentes: la escalera está completa y toca imputar.
      when c.n_susp >= 2                        then 'imputacion'
      -- Ya hubo imputación Y la escalera de abajo está completa: de ahí no se
      -- baja, aunque la imputación se haya archivado.
      when c.n_imp > 0 and l.n_susp >= 2        then 'imputacion'
      -- Una imputación con la escalera INCOMPLETA no tapa el escalón que falta.
      -- Es el caso de Arequipa: se imputó saltándose el literal d).
      when c.n_susp = 1 and l.n_susp >= 2       then 'imputacion'
      when c.n_susp = 1                         then 'suspension'
      when c.n_amon > 0 or c.n_imp > 0          then 'suspension'
      else                                           'amonestacion'
    end,
    case
      when c.imp_abierta                        then null::int
      when c.n_susp >= 1 or c.n_imp > 0         then 1
      when c.n_amon > 0                         then 2
      else                                           3
    end,
    nb.corte,
    (select id from ultimo),
    coalesce(c.imp_abierta, false),
    c.dias_susp::int
  from cuenta c cross join legajo l cross join nobis nb;
$$;

comment on function fn_tardanza_escalon_al(uuid, date) is
  'El escalon del art. 19.2 medido a una fecha de referencia. p_al nulo = ahora, que es el camino de siempre.';

grant  execute on function fn_tardanza_escalon_al(uuid, date) to service_role;
revoke execute on function fn_tardanza_escalon_al(uuid, date) from public, anon, authenticated;


-- ── 4 · La puerta de siempre, ahora envoltorio ─────────────────────────────
-- `create or replace` SIN `drop`: la firma y la tabla de salida no cambian, así
-- que la ACL sobrevive y la prueba 159 —que nombra la lista completa de
-- argumentos— sigue en verde. Ese es justamente el motivo del envoltorio.
create or replace function fn_tardanza_escalon(p_persona_id uuid)
returns table(
  nivel_siguiente        text,
  minimo                 integer,
  corte                  date,
  doc_previo             uuid,
  bloqueado              boolean,
  suspension_previa_dias integer
)
language sql stable security definer set search_path = public as $$
  select * from fn_tardanza_escalon_al(p_persona_id, null);
$$;


-- ── 5 · El generador ───────────────────────────────────────────────────────
-- ⚠️ EL `drop` VA PRIMERO Y NO ES OPCIONAL. `create or replace` con un argumento
-- de más NO reemplaza: crea una SEGUNDA función. La llamada de la pantalla
-- encajaría en las dos y PostgREST respondería «could not choose the best
-- candidate function» — que no falla al pegar esta migración, falla AL ABRIR LA
-- PANTALLA. Es el accidente 0297/0299, que dejó muerto el aviso de vacaciones.
drop function if exists public.fn_expediente_generar_tardanza(uuid);
drop function if exists public.fn_expediente_generar_tardanza(uuid, date);

create function fn_expediente_generar_tardanza(
  p_persona_id uuid,
  -- CUALQUIER día del mes que se documenta; nulo = el mes en curso, que es el
  -- comportamiento de siempre. Se normaliza con `date_trunc`, así que no tiene
  -- modo de fallo silencioso por valor.
  p_mes date default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_esc     record;
  v_ini     date;
  v_fin     date;
  v_mes_hoy date;
  v_al      date;
  v_mes_txt text;
  v_n       int;
  v_hechos  jsonb;
  v_desde   date;
  v_hasta   date;
  v_dias    int;
  v_fechas  date[];
  v_id      uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- ── EL PERIODO MENSUAL CALENDARIO (arts. 19.1 a y 19.4) ──────────────────
  -- «Del día primero al último día de cada mes», y el 19.4 dice que su cierre
  -- «no impide emitir el documento». El mes es un dato del documento, no la hora
  -- a la que alguien pulsó el botón. `least(..., hoy)` para no citar un futuro.
  v_mes_hoy := date_trunc('month', fn_hoy_lima())::date;
  v_ini     := date_trunc('month', coalesce(p_mes, fn_hoy_lima()))::date;
  v_fin     := least((v_ini + interval '1 month')::date - 1, fn_hoy_lima());
  -- `to_char(..., 'TMMonth')` NO sirve acá: `lc_time` es en_US.UTF-8 y devuelve
  -- «July». El mes se nombra en español o el mensaje no sirve para nadie.
  v_mes_txt := (array['enero','febrero','marzo','abril','mayo','junio','julio',
                      'agosto','septiembre','octubre','noviembre','diciembre'])
                 [extract(month from v_ini)::int] || ' de ' || extract(year from v_ini)::int;

  if v_ini > v_mes_hoy then
    raise exception 'No se puede emitir por %: ese mes todavía no ha empezado.', v_mes_txt;
  end if;

  -- Mes en curso → nulo: la vigencia se mide contra el reloj, como hasta hoy.
  -- Mes cerrado → contra su último día.
  v_al := case when v_ini = v_mes_hoy then null else (v_ini + interval '1 month')::date - 1 end;

  select * into v_esc from fn_tardanza_escalon_al(p_persona_id, v_al);

  if v_esc.bloqueado then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  end if;

  -- ART. 19.1 a), párrafo 2: «El literal e) del numeral 19.2 NO se cuenta por
  -- periodo mensual calendario». Su supuesto i) computa toda tardanza nueva
  -- posterior a la notificación de la segunda suspensión, y el ii) tiene ventana
  -- propia de treinta días corridos. Hoy el código lo acota al mes igual
  -- —defecto preexistente— pero acotarlo a un mes ELEGIDO sería escribirlo como
  -- si fuera la regla. Se para en vez de emitir: falla cerrado.
  --
  -- La condición mira EL MES, no la forma de la llamada. Escrita como
  -- `p_mes is not null` se disparaba también sobre el mes en curso —el mismo mes
  -- que el camino por defecto documenta sin problema— y dejaba el cuarto escalón
  -- inalcanzable desde una pantalla que siempre nombra el mes.
  if v_esc.nivel_siguiente = 'imputacion' and v_ini <> v_mes_hoy then
    raise exception
      'La imputación de cargos del numeral 19.2 e) NO se cuenta por periodo mensual calendario '
      '(numeral 19.1 a): computa toda tardanza nueva posterior a la notificación de la segunda '
      'suspensión. Genérala sobre el mes en curso, no sobre uno ya cerrado.';
  end if;

  -- ART. 56.6. Se dice aparte porque «lleva 0» deja a quien lo lee sin saber qué
  -- hacer: no es que falten tardanzas, es que ese mes ya no se documenta.
  if v_esc.corte is not null and v_esc.corte >= v_fin then
    raise exception
      'El último documento de tardanzas de esta persona cubre hasta el %, y en % ya no queda '
      'ningún hecho nuevo que reprochar (numeral 56.6). Los meses se emiten del más viejo al '
      'más nuevo: este ya no alcanza.',
      to_char(v_esc.corte, 'DD/MM/YYYY'), v_mes_txt;
  end if;

  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      -- ── 1 · LA VENTANA ES EL MES CALENDARIO que se documenta (19.1 a) ────
      and j.fecha >= v_ini
      and j.fecha <= v_fin
      -- ── 2 · Y DENTRO DE ESE MES, SOLO LO NUEVO (19.1 b, 52.5, 56.6) ──────
      -- Las dos condiciones SE SUMAN. El `greatest(inicio de mes, corte + 1)`
      -- que había acá las fundía en un solo límite: ganaba la más tardía y la
      -- otra se quedaba sin ningún trabajo que hacer. De ahí salían las dos
      -- averías: el corte por antecedente sustituía al mensual, y el día 1 el
      -- mes anterior entero desaparecía del generador.
      and (v_esc.corte is null or j.fecha > v_esc.corte)
      -- Cinturón y tirantes: el corte es una fecha y puede ser null; esto es la
      -- lista nominal de días ya citados.
      and not fn_tardanza_ya_documentada(p_persona_id, j.fecha)
      -- El papel disciplinario NUNCA se arma con una medición dudosa.
      and fn_tardanza_es_medible(j.minutos_tarde) and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  if v_n < v_esc.minimo then
    raise exception 'Aún no corresponde %: en % lleva % tardanza(s) nueva(s) y su escalón exige %.%',
      v_esc.nivel_siguiente, v_mes_txt, v_n, v_esc.minimo,
      case when v_esc.corte is null then ''
           else format(' El documento anterior cubre hasta el %s; solo cuentan las posteriores a esa fecha.',
                       to_char(v_esc.corte, 'DD/MM/YYYY')) end;
  end if;

  if v_esc.nivel_siguiente = 'suspension' then
    if v_esc.suspension_previa_dias is null then
      v_dias := 1;
    elsif v_esc.suspension_previa_dias >= 3 then
      raise exception
        'La primera suspensión se registró con % días, y el numeral 19.2 c) la topa en dos. '
        'La segunda tiene que ser mayor y caber en el tope de tres del numeral 54.5, y con esa '
        'primera no hay ningún número que cumpla las dos cosas. Revisa la primera suspensión '
        'antes de seguir con la escalera.',
        v_esc.suspension_previa_dias;
    else
      v_dias := v_esc.suspension_previa_dias + 1;
    end if;
  end if;

  if v_dias is not null then
    -- OJO: arranca MAÑANA, y no en el mes documentado. La suspensión se cumple
    -- en el futuro aunque los hechos sean de junio; fijarla sobre el mes
    -- documentado la pondría en días que ya pasaron.
    begin
      select array_agg(fecha order by fecha) into v_fechas
        from fn_dias_suspension(p_persona_id, fn_hoy_lima() + 1, v_dias);
    exception when others then
      raise exception
        'No puedo fijar los días de la suspensión: esta persona no tiene un horario vigente, '
        'y sin él no se sabe qué días son laborables. El numeral 54.5 exige comunicar «los días '
        'concretos en que se cumplirá», y no se pueden poner días de descanso. Asígnale su '
        'horario en Equipo y vuelve a intentarlo.';
    end;
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_esc.nivel_siguiente, v_hechos, v_desde, v_hasta,
    v_esc.doc_previo, v_dias,
    case when v_fechas is not null then v_fechas[1] end,
    case when v_fechas is not null then v_fechas[array_length(v_fechas, 1)] end,
    null);

  if v_fechas is not null then
    update expediente_disciplinario set suspension_fechas = v_fechas where id = v_id;
  end if;

  return v_id;
end;
$$;

-- ⚠️ EL GRANT NO ES OPCIONAL: el `drop` se llevó los permisos y la firma nueva
-- nace sin ninguno. Es la trampa que costó días de semáforo ciego con la 0189.
grant  execute on function fn_expediente_generar_tardanza(uuid, date) to authenticated, service_role;
revoke execute on function fn_expediente_generar_tardanza(uuid, date) from public, anon;


-- ── 6 · El semáforo ────────────────────────────────────────────────────────
-- `create or replace` SIN `drop`: la firma y la tabla de salida no cambian, así
-- que la ACL sobrevive intacta. Dos cambios, y el segundo es el que importa: si
-- el semáforo se quedara con el corte que caduca, el día que un documento cumple
-- doce meses la pantalla empezaría a mostrar como pendientes días ya
-- sancionados. Que el botón luego se niegue no arregla nada — ese número es el
-- que una persona de DO mira antes de decidir.
CREATE OR REPLACE FUNCTION public.fn_tardanzas_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, tardanzas_mes integer, umbral text, ultima_fecha date, sin_medir integer, minimo integer, nivel_siguiente text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
           -- El corte y el escalón salen de la MISMA función que usa el
           -- generador. Antes el corte se recalculaba aquí con su propia
           -- subconsulta: dos sitios donde escribir la misma regla.
           esc.corte, esc.minimo, esc.nivel_siguiente, esc.bloqueado
    from personas pe
    join sedes s on s.id = pe.sede_base_id
    -- CAMBIO 0311 · el escalón se mide a la MISMA fecha que se está mirando.
    -- Mirar julio desde agosto daba el conteo de julio con el umbral de agosto.
    cross join lateral fn_tardanza_escalon_al(pe.id, p_as_of) esc
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  conteo as (
    select m.id as pid,
           count(distinct j.fecha) filter (
             where fn_tardanza_es_medible(j.minutos_tarde)) as n,
           -- Los días cuya tardanza pasa de tres horas. No suman al umbral legal
           -- —no se puede sancionar con una medición dudosa— pero no son
           -- invisibles.
           count(distinct j.fecha) filter (
             where not fn_tardanza_es_medible(j.minutos_tarde)) as sm,
           max(j.fecha) filter (
             where fn_tardanza_es_medible(j.minutos_tarde)) as ult
    from medibles m
    join jornadas j on j.persona_id = m.id
      and j.fecha >= date_trunc('month', coalesce(p_as_of, fn_hoy_lima()))::date
      and j.fecha <= coalesce(p_as_of, fn_hoy_lima())
      and (m.corte is null or j.fecha > m.corte)   -- no cuenta lo ya sancionado
      -- CAMBIO 0311 · y tampoco los días citados NOMINALMENTE en un documento.
      -- El corte es una fecha y puede ser null; esto es la lista de días. Sin
      -- ello, el día que un documento cumple doce meses la pantalla empezaría a
      -- mostrar como pendientes días ya sancionados — y ese número es el que una
      -- persona de DO mira antes de decidir. Un falso positivo en pantalla es un
      -- falso positivo.
      and not fn_tardanza_ya_documentada(m.id, j.fecha)
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (
        select 1 from tardanzas_justificadas tj
        where tj.persona_id = m.id and tj.fecha = j.fecha)
    group by m.id
  )
  select m.id, m.nombre, m.sede, c.n::int,
    -- `umbral` deja de ser «amonestación o aviso» y pasa a nombrar el escalón
    -- ALCANZADO. Los tres consumidores comparaban contra 'amonestacion' para
    -- pintar el rojo; ahora comparan contra 'aviso'.
    case
      when m.bloqueado          then 'bloqueado'
      when c.n >= m.minimo      then m.nivel_siguiente
      else 'aviso'
    end as umbral,
    c.ult, c.sm::int, m.minimo, m.nivel_siguiente
  from medibles m join conteo c on c.pid = m.id
  -- Se asoma un escalón antes de su propio umbral, nunca por debajo de 1.
  -- Con mínimo 3 eso son 2, que es exactamente lo que hacía antes.
  where c.n >= greatest(coalesce(m.minimo, 1) - 1, 1) or c.sm > 0
  order by
    case when m.bloqueado then 2 when c.n >= m.minimo then 1 else 0 end desc,
    c.n desc, c.sm desc, m.nombre;
$function$;


-- ── 7 · Los días de la suspensión, medidos al periodo del documento ────────
CREATE OR REPLACE FUNCTION public.fn_expediente_set_suspension(p_id uuid, p_dias integer, p_desde date)
 RETURNS TABLE(fecha date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r        expediente_disciplinario%rowtype;
  v_fechas date[];
  v_previa int;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede ajustar la suspensión de un borrador (estado actual: %).', r.estado;
  end if;
  if r.nivel <> 'suspension' then
    raise exception 'Este documento no es una suspensión.';
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso sobre este documento.';
  end if;

  -- ── El tope del Reglamento ────────────────────────────────────────────────
  if p_dias is null or p_dias < 1 then
    raise exception 'Los días de suspensión deben ser al menos 1.';
  end if;

  -- NUMERAL 54.5: el techo absoluto, cualquiera sea la causal y el escalón.
  if p_dias > 3 then
    raise exception
      'El numeral 54.5 del Reglamento topa toda suspensión en TRES días, y se pidieron %. '
      'Si Gerencia quiere un tope mayor, eso se cambia reformando el Reglamento y volviéndolo '
      'a entregar con acuse — no en este campo: un memo que se funda en el Reglamento y lo '
      'incumple en su parte resolutiva no sirve como sanción previa el día que haga falta.',
      p_dias;
  end if;

  -- ── Y la escalera del numeral 19.2, que es SOLO la de tardanzas ───────────
  --
  -- Los literales c) y d) gradúan la escala de impuntualidad: primera de uno a
  -- dos días, segunda de mayor duración. La escala de FALTAS es otra y tiene un
  -- solo peldaño de suspensión —amonestación, suspensión, imputación—, y su
  -- generador la emite siempre de un día (0237). Aplicarle el 19.2 le prohibiría
  -- a una segunda suspensión por faltas repetir ese día, que es justo lo que su
  -- propia escala manda: se rechazaría al mover la FECHA de un borrador legítimo,
  -- porque cambiar la fecha reenvía los mismos días.
  --
  -- El techo de tres del numeral 54.5, en cambio, sí es de toda suspensión y ya
  -- se aplicó arriba, antes de esta distinción.
  if r.tipo_causal = 'tardanza' then
    -- La suspensión anterior de la MISMA causal, entregada y vigente. Se mide
    -- igual que en `fn_tardanza_escalon` — si las dos contaran distinto, el
    -- generador propondría un número que esta función rechaza.
    select max(e.suspension_dias) into v_previa
    from expediente_disciplinario e
    where e.persona_id  = r.persona_id
      and e.tipo_causal = r.tipo_causal
      and e.nivel       = 'suspension'
      and e.estado      = 'entregado'
      and e.id         <> r.id
      -- CAMBIO 0311 · la referencia es el CIERRE DEL PERIODO QUE ESTE DOCUMENTO
      -- CUBRE, no «ahora». El numeral 19.1 c) dice que el antecedente agrava si
      -- fue notificado dentro de los doce meses anteriores AL HECHO QUE SE
      -- EVALÚA. Documentando un mes ya cerrado —que desde el 19.4 se puede—, una
      -- suspensión entregada DESPUÉS de ese mes no gradúa hechos que, cuando
      -- ocurrieron, no la tenían encima.
      --
      -- Medido contra `now()` el generador calculaba 1 día y esta función exigía
      -- 2: un borrador que la pantalla pintaba en rojo y que no se podía
      -- corregir —mover la fecha reenvía los mismos días—, cuya única salida era
      -- un día sin goce de más para una persona real, por un atraso de la
      -- empresa en entregar el documento anterior.
      and e.entregado_at <= fn_cierre_lima(coalesce(r.periodo_hasta, fn_hoy_lima()))
      and e.entregado_at >= fn_cierre_lima(coalesce(r.periodo_hasta, fn_hoy_lima()))
                            - interval '12 months';

    if v_previa is null then
      -- NUMERAL 19.2 c): la primera es de uno a dos días. El tope de dos existe
      -- para que quepa una segunda mayor debajo del techo de tres.
      if p_dias > 2 then
        raise exception
          'Es la PRIMERA suspensión por tardanzas de esta persona, y el numeral 19.2 c) del '
          'Reglamento la topa en dos días. Se pidieron %. Si la conducta amerita más, el camino '
          'es la segunda suspensión del literal d) cuando corresponda, no alargar esta.',
          p_dias;
      end if;
    else
      -- NUMERAL 19.2 d): «en todo caso de mayor duración que la primera».
      if p_dias <= v_previa then
        raise exception
          'Su suspensión anterior por tardanzas fue de % día(s), y el numeral 19.2 d) exige que la '
          'siguiente sea de MAYOR duración. Se pidieron %. Con el techo de tres días del numeral '
          '54.5, lo que cabe acá es entre % y 3.',
          v_previa, p_dias, v_previa + 1;
      end if;
    end if;
  end if;

  select array_agg(d.fecha order by d.fecha) into v_fechas
  from fn_dias_suspension(r.persona_id, p_desde, p_dias) d;

  update expediente_disciplinario
    set suspension_dias = p_dias,
        suspension_fechas = v_fechas,
        suspension_desde = v_fechas[1],
        suspension_hasta = v_fechas[array_length(v_fechas, 1)]
    where id = p_id;

  return query select unnest(v_fechas) order by 1;
end;
$function$;


-- ── 8 · El rastro ──────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (311, 'el_mes_cerrado_se_puede_documentar_y_el_corte_se_suma')
on conflict (numero) do nothing;


-- ── 9 · Comprobación ───────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las seis deben decir true.
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_generar_tardanza') = 1
                                                        as no_quedo_sobrecargada,
  has_function_privilege('authenticated', 'public.fn_expediente_generar_tardanza(uuid,date)', 'EXECUTE')
                                                        as el_boton_puede_generar,
  has_function_privilege('authenticated', 'public.fn_tardanzas_resumen(date)', 'EXECUTE')
                                                        as el_semaforo_sigue_abierto,
  not has_function_privilege('authenticated', 'public.fn_tardanza_escalon_al(uuid,date)', 'EXECUTE')
                                                        as el_escalon_sigue_cerrado,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_cierre_lima', 'fn_tardanza_ya_documentada', 'fn_tardanza_escalon_al')) = 3
                                                        as estan_las_tres_nuevas,
  (select count(*) from migraciones_aplicadas where numero = 311) = 1
                                                        as quedo_el_rastro;
