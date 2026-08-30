-- ============================================================================
-- 0323 — Pagar planilla y RxH por separado
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que "Marcar como PAGADO" deje de ser un único interruptor para el periodo
--   ENTERO y pase a ser independiente por grupo (`personas.tipo_vinculo`:
--   planilla, prueba, rxh, no_trabajador, practicante — 5 valores, 0085/0322).
--   Felipe paga RxH más tarde que a planilla (los honorarios se demoran), y
--   hoy el sistema lo obliga a fingir que pagó a todos el mismo día, o a dejar
--   el periodo "abierto" indefinidamente mientras espera a RxH.
--
--   Decidido con Felipe por AskUserQuestion (sesión 2026-08-29-30):
--     · el candado de pago es por CADA tipo_vinculo, no solo planilla-vs-RxH;
--     · crear el periodo siguiente NO se bloquea por esto — hoy no revisa el
--       estado del anterior y se queda así, a propósito;
--     · esta es la ENTREGA 1 de dos. Retrofit del candado que bloquea EDITAR
--       horas/marcajes (~25 funciones en ~19 migraciones — fn_anular_marcaje,
--       fn_corregir_marca, fn_recalcular_jornada, fn_set_horario_semanal, y
--       compañía) queda para una migración aparte. Hasta esa segunda entrega,
--       las horas de un grupo ya pagado siguen protegidas solo cuando TODOS
--       los grupos del periodo están pagados — igual que hoy. Se explica por
--       qué abajo, en "CÓMO SIGUE FUNCIONANDO EL CANDADO DE HORAS".
--
-- QUÉ ASUME
--
--   · Que `personas.tipo_vinculo` (0085) es una de las 5 anteriores, y que
--     `personas.en_planilla` es la columna GENERADA `tipo_vinculo in
--     ('planilla','prueba')` — sin cambios, no se toca.
--   · Que el jsonb de cada fila de `fn_planilla_calcular` trae la clave
--     `tipo_vinculo` — viaja desde la 0117, confirmado leyendo el código de
--     `fn_planilla_congelar` (0284) y expuesto en la pantalla desde la 0322.
--   · Que dos periodos no se solapan (`periodos_sin_solape`), así que un
--     `persona_id` nunca puede estar en dos periodos que compartan fecha.
--
--   md5 DE PARTIDA de las 7 funciones que esta migración reescribe — PEDIDOS
--   A PRODUCCIÓN antes de pegar, no copiados del local (regla de la casa: el
--   árbol se mueve con ~20 sesiones activas). Los de abajo son los de ESTA
--   Mac, confirmados contra un `supabase db reset` limpio hasta la 0322; el
--   bloque 1 de esta migración los vuelve a comprobar EN PRODUCCIÓN antes de
--   tocar nada — si alguno no coincide, la migración entera no aplica NADA.
--
--     fn_periodo_pagado                ba09a250d6496084f093dccb2bd9108b ·  945
--     fn_planilla_congelar              645667b844f2e977534fbad6829632c5 · 15503
--     fn_revertir_pago                 76e13c78f37272a0fcb549b87c224947 · 2353
--     fn_repagar_periodo               ae86e4e9204325dec278ff2617083bb0 · 1788
--     fn_planilla_congelar_pendientes  433bebcadda139cfb3a723e269f9b0b6 ·  514
--     fn_proyeccion_periodo            0c9718e51240a97b809495c28a68ce93 · 2272
--     fn_costos_planilla               939e5ef4840e6ca088b08a17d2084e74 · 7186
--
--   `fn_planilla_foto_diferencias` NO se toca: compara `v_planilla_pagada`
--   contra un recálculo fresco de TODA la gente, y con la vista arreglada
--   (abajo) sigue funcionando exactamente igual sin cambiar una línea suya.
--
-- ── EL DISEÑO, EN UN PÁRRAFO ─────────────────────────────────────────────────
--
--   Tabla nueva `periodo_grupo_pago(periodo_id, grupo, estado, pagado_at,
--   pagado_por)` — el estado de pago vive AHÍ, no en `periodos_planilla`. La
--   foto (`planilla_pagada_detalle`) gana una columna `grupo` en su llave
--   primaria: sin eso, congelar RxH después de planilla le sube el `version`
--   al periodo entero y `v_planilla_pagada` (que hoy hace `max(version) where
--   periodo_id = ...`) esconde en silencio las filas de planilla ya
--   congeladas — el mismo bug, en miniatura, que la 0127 ya corrigió una vez
--   para otro motivo. `periodos_planilla.estado`/`pagado_at` SIGUEN
--   existiendo, pero pasan a ser un valor DERIVADO: "pagado" cuando TODOS los
--   grupos con gente en ese periodo ya están pagados en la tabla nueva, y
--   vuelve a "abierto" en cuanto se reabre cualquiera de ellos.
--
-- CÓMO SIGUE FUNCIONANDO EL CANDADO DE HORAS (sin que esta migración lo toque)
--
--   `fn_recalcular_jornada`, `fn_anular_marcaje`, `fn_set_horario_semanal` y
--   el resto de las ~25 funciones que bloquean editar marcajes/jornadas siguen
--   mirando `periodos_planilla.estado = 'pagado'` exactamente como hoy — CERO
--   líneas tocadas ahí. Como ese estado sigue siendo el AGREGADO de los 5
--   grupos (ver arriba), el resultado práctico durante esta entrega es:
--
--     · Mientras quede al menos un grupo sin pagar (RxH esperando su
--       transferencia), las horas de TODOS —incluida la gente de planilla ya
--       pagada— siguen editables. La foto de planilla ya está protegida
--       (congelada, inmutable, con su propio botón de pago); lo que NO está
--       protegido todavía es la jornada de origen. Cerrar ese hueco es
--       exactamente la ENTREGA 2.
--     · En cuanto el ÚLTIMO grupo se paga, `periodos_planilla.estado` pasa a
--       'pagado' solo (ver `fn_periodo_pagado` abajo) y el candado de horas
--       existente se activa para todo el periodo, como siempre lo ha hecho.
--     · Reabrir CUALQUIER grupo (`fn_revertir_pago`) siempre vuelve a poner
--       `periodos_planilla.estado = 'abierto'` — si un grupo se reabre, el
--       periodo ya no está "completo" — y si el candado de horas SÍ estaba
--       activo (es decir, si de verdad se habían pagado los 5 grupos), se
--       recalculan las jornadas de TODO el periodo, no solo las del grupo
--       reabierto: el candado que se levanta es el de todos, porque hasta la
--       entrega 2 el candado sigue siendo uno solo para el periodo entero.
--
-- QUÉ NO SE TOCA EN ESTA MIGRACIÓN, Y ES DELIBERADO
--
--   · `fn_crear_periodo` — hoy no revisa `estado` del periodo anterior para
--     nada, y Felipe confirmó dejarlo así: RxH atrasado nunca bloquea abrir
--     el mes siguiente, porque nada lo bloquea hoy.
--   · `fn_liquidacion` y `fn_planilla_variacion` — ya leen la foto por
--     `(periodo_id, persona_id)` sin pasar por `v_planilla_pagada`, o no
--     dependen de esta tabla (confirmado leyendo su código).
--   · `fn_set_feriado`/`fn_quitar_feriado`/`fn_eliminar_periodo` — no tienen
--     una persona a la que atarles un grupo (el feriado es del calendario
--     entero, no de alguien en concreto) y se quedan con la regla de siempre:
--     bloqueados si CUALQUIER grupo del periodo ya está pagado. Sin cambios.
--   · Los ~25 sitios del candado de horas — entrega 2, aparte.
--
-- UN PERIODO PAGADO ANTES DE ESTA MIGRACIÓN, SIN NINGUNA FOTO
--   Son los anteriores a que existiera `planilla_pagada_detalle` (0096). Ahí
--   no hay de dónde derivar `grupo`, así que el backfill de abajo no puede
--   crearles fila en `periodo_grupo_pago` — medido en 0 casos el 2026-08-26
--   (cabecera de la 0313). Si alguno apareciera, `fn_planilla_congelar_
--   pendientes` (reescrita abajo) los recoge la próxima vez que se ejecute.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_periodo_pagado(uuid, boolean, text);
--   drop function if exists fn_planilla_congelar(uuid, text, uuid, text);
--   drop function if exists fn_revertir_pago(uuid, text, text);
--   drop function if exists fn_repagar_periodo(uuid, text, text);
--   drop function if exists fn_periodo_grupos_estado(uuid);
--   -- y volver a pegar los cuerpos de fn_periodo_pagado (0096), fn_planilla_
--   -- congelar (0284), fn_revertir_pago (0203), fn_repagar_periodo (0098),
--   -- fn_planilla_congelar_pendientes (0096), fn_proyeccion_periodo (0313) y
--   -- fn_costos_planilla (0260). La tabla `periodo_grupo_pago`, la columna
--   -- `grupo` de `planilla_pagada_detalle` y `reversas_pago` se pueden dejar
--   -- sin usar: nada las vuelve a leer si se revierten las funciones.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final. Todas las columnas booleanas en `true`.
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ────────────────────────────────────────
-- Si producción no está en las versiones de partida declaradas arriba, esta
-- migración no aplica NADA. Mismo patrón que la 0313 y la 0284: reescribir
-- partiendo de un cuerpo que no es el vigente revierte en silencio todo lo
-- que se arregló entre medias.
do $$
declare v_md5 text; v_len int;
begin
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_periodo_pagado';
  if v_md5 is distinct from 'ba09a250d6496084f093dccb2bd9108b' then
    raise exception '0323 · PARA. fn_periodo_pagado en esta base es % (% caracteres), se esperaba ba09a250d6496084f093dccb2bd9108b (945). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_periodo_pagado.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_congelar';
  if v_md5 is distinct from '645667b844f2e977534fbad6829632c5' then
    raise exception '0323 · PARA. fn_planilla_congelar en esta base es % (% caracteres), se esperaba 645667b844f2e977534fbad6829632c5 (15503). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_planilla_congelar.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_revertir_pago';
  if v_md5 is distinct from '76e13c78f37272a0fcb549b87c224947' then
    raise exception '0323 · PARA. fn_revertir_pago en esta base es % (% caracteres), se esperaba 76e13c78f37272a0fcb549b87c224947 (2353). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_revertir_pago.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_repagar_periodo';
  if v_md5 is distinct from 'ae86e4e9204325dec278ff2617083bb0' then
    raise exception '0323 · PARA. fn_repagar_periodo en esta base es % (% caracteres), se esperaba ae86e4e9204325dec278ff2617083bb0 (1788). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_repagar_periodo.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_congelar_pendientes';
  if v_md5 is distinct from '433bebcadda139cfb3a723e269f9b0b6' then
    raise exception '0323 · PARA. fn_planilla_congelar_pendientes en esta base es % (% caracteres), se esperaba 433bebcadda139cfb3a723e269f9b0b6 (514). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_planilla_congelar_pendientes.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo';
  if v_md5 is distinct from '0c9718e51240a97b809495c28a68ce93' then
    raise exception '0323 · PARA. fn_proyeccion_periodo en esta base es % (% caracteres), se esperaba 0c9718e51240a97b809495c28a68ce93 (2272). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_proyeccion_periodo.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_costos_planilla';
  if v_md5 is distinct from '939e5ef4840e6ca088b08a17d2084e74' then
    raise exception '0323 · PARA. fn_costos_planilla en esta base es % (% caracteres), se esperaba 939e5ef4840e6ca088b08a17d2084e74 (7186). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_costos_planilla.', v_md5, v_len;
  end if;
end
$$;


-- ── 1 · La tabla del estado de pago por grupo ───────────────────────────────
create table if not exists periodo_grupo_pago (
  periodo_id  uuid not null references periodos_planilla(id),
  grupo       text not null check (grupo in ('planilla','prueba','rxh','no_trabajador','practicante')),
  estado      text not null default 'abierto' check (estado in ('abierto','pagado')),
  pagado_at   timestamptz,
  pagado_por  uuid references personas(id),
  primary key (periodo_id, grupo)
);

comment on table periodo_grupo_pago is
  'Estado de pago INDEPENDIENTE por grupo (tipo_vinculo) dentro de un periodo — 0323: RxH se paga más tarde que planilla, y cada uno se congela y se marca pagado por su cuenta. La fila de un grupo se crea recién cuando ese grupo se paga por primera vez (no hace falta tocar fn_crear_periodo). periodos_planilla.estado sigue existiendo sin cambios de significado para el candado de horas: pasa a pagado solo cuando TODOS los grupos con gente en el periodo están aquí como pagado, y vuelve a abierto en cuanto se reabre cualquiera.';

alter table periodo_grupo_pago enable row level security;
revoke all on periodo_grupo_pago from anon, public;
grant select on periodo_grupo_pago to authenticated;

drop policy if exists periodo_grupo_pago_select_admin_lider on periodo_grupo_pago;
create policy periodo_grupo_pago_select_admin_lider on periodo_grupo_pago
  for select to authenticated using (fn_es_admin_o_lider());
-- Escritura: NINGUNA política, igual que planilla_pagada_detalle — solo entra
-- por fn_periodo_pagado / fn_revertir_pago / fn_repagar_periodo /
-- fn_planilla_congelar_pendientes, que corren SECURITY DEFINER y ya
-- comprueban admin/líder antes de tocar nada.


-- ── 2 · `grupo` en la foto, y su llave primaria lo aprende ──────────────────
-- Sin esto, congelar RxH después de planilla sube el `version` del PERIODO
-- entero y `v_planilla_pagada` (que hoy toma el max(version) por periodo_id a
-- secas) esconde en silencio las filas de planilla ya congeladas.
--
-- Apagar el candado de inmutabilidad SOLO para este backfill, y volver a
-- encenderlo enseguida en la misma migración — es la única manera de rellenar
-- una columna nueva en una tabla append-only que además es NOT NULL.
drop trigger if exists trg_foto_es_inmutable on planilla_pagada_detalle;

alter table planilla_pagada_detalle add column if not exists grupo text;

-- El propio jsonb congelado (inmutable, es la fuente de verdad de lo que se
-- pagó) trae `tipo_vinculo` desde la 0117. Si una foto vieja no lo trajera
-- (no medido, pero por si acaso), el respaldo es `en_planilla`: no distingue
-- rxh de practicante/no_trabajador, pero antes de la 0322 esa distinción no
-- existía, así que no hay información que perder.
update planilla_pagada_detalle
   set grupo = coalesce(
         fila->>'tipo_vinculo',
         case when (fila->>'en_planilla')::boolean is not false then 'planilla' else 'rxh' end
       )
 where grupo is null;

alter table planilla_pagada_detalle alter column grupo set not null;
-- Cualquier insert futuro que no diga grupo (una prueba, un script viejo que
-- nadie actualizó) cae en 'planilla' — el bucket que existía antes de que
-- esta migración distinguiera nada. No tapa un error real: un insert que SÍ
-- sabe su grupo lo sigue declarando, como hace fn_planilla_congelar.
alter table planilla_pagada_detalle alter column grupo set default 'planilla';

alter table planilla_pagada_detalle drop constraint if exists chk_foto_grupo_valido;
alter table planilla_pagada_detalle add constraint chk_foto_grupo_valido
  check (grupo in ('planilla','prueba','rxh','no_trabajador','practicante'));

alter table planilla_pagada_detalle drop constraint if exists planilla_pagada_detalle_pkey;
alter table planilla_pagada_detalle add primary key (periodo_id, grupo, persona_id, version);

comment on column planilla_pagada_detalle.grupo is
  'tipo_vinculo de la persona AL MOMENTO de congelar esta fila — 0323. Es lo que separa el version de planilla del de RxH dentro del mismo periodo: cada grupo tiene su propia secuencia de versiones.';

create trigger trg_foto_es_inmutable
  before update or delete on planilla_pagada_detalle
  for each row execute function fn_trg_foto_es_inmutable();


-- ── 3 · La vista "vigente" pasa a ser por (periodo, grupo) ──────────────────
drop view if exists v_planilla_pagada;
create view v_planilla_pagada with (security_invoker = true) as
select d.*
from planilla_pagada_detalle d
where d.version = (
  select max(x.version) from planilla_pagada_detalle x
   where x.periodo_id = d.periodo_id and x.grupo = d.grupo
);

comment on view v_planilla_pagada is
  'Solo la foto vigente de cada (periodo, grupo) — la de mayor version DENTRO de ese grupo, no del periodo entero (0323). Lo que hay que sumar para contabilidad.';


-- ── 4 · Backfill de `periodo_grupo_pago` para lo que ya estaba pagado ───────
-- Todo periodo ya `estado = 'pagado'` que SÍ tiene foto: cada (periodo, grupo)
-- distinto que aparece en su foto se declara pagado, con el `pagado_at` del
-- periodo como fecha histórica (no se guardó una fecha por grupo antes de
-- hoy, así que es la mejor aproximación que hay). Los pagados sin ninguna
-- foto (0 casos medidos, 0313) quedan para `fn_planilla_congelar_pendientes`.
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at, pagado_por)
select distinct d.periodo_id, d.grupo, 'pagado', pp.pagado_at, null::uuid
from planilla_pagada_detalle d
join periodos_planilla pp on pp.id = d.periodo_id
where pp.estado = 'pagado'
on conflict (periodo_id, grupo) do nothing;


-- ── 5 · `reversas_pago` aprende qué grupo se reabrió o se repagó ────────────
alter table reversas_pago add column if not exists grupo text;
alter table reversas_pago drop constraint if exists chk_reversa_grupo_valido;
alter table reversas_pago add constraint chk_reversa_grupo_valido
  check (grupo is null or grupo in ('planilla','prueba','rxh','no_trabajador','practicante'));

comment on column reversas_pago.grupo is
  'Grupo (tipo_vinculo) que se reabrió o se repagó — 0323. NULL en las filas anteriores a esta migración, cuando reabrir siempre afectaba al periodo entero de una sola vez.';


-- ── 6 · fn_planilla_congelar gana `p_grupo` ──────────────────────────────────
-- Cuerpo de la 0284 (confirmado arriba), con el filtro de grupo añadido en
-- las tres consultas que hoy miran "todas las filas del periodo": los dos
-- frenos (0243 liquidación ya cobrada, 0284 días pendientes) y el insert
-- final. Ni una palabra de comentario original se quita.
drop function if exists fn_planilla_congelar(uuid, text, uuid);

CREATE OR REPLACE FUNCTION public.fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid, p_grupo text DEFAULT 'planilla')
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_per record;
  v_calc jsonb;
  v_ver int;
  v_n int;
  v_cobradas text;   -- CAMBIO 0243
  v_pendientes text;   -- CAMBIO 0284
begin
  -- CAMBIO 0323 · esta función ahora congela UN grupo a la vez, no el
  -- periodo entero. p_grupo decide qué personas de `v_calc->'filas'` entran.
  if p_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'Grupo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador, practicante.', p_grupo;
  end if;

  -- `for update` sobre el periodo: dos personas pulsando «Pagado» a la vez no
  -- pueden calcular ambas la versión 1 y chocar contra la llave primaria.
  select * into v_per from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_calc := fn_planilla_calcular(v_per.fecha_ini, v_per.fecha_fin, p_periodo_id);

  -- ── CAMBIO 0243 · el freno del orden inverso ────────────────────────────────
  -- Si alguien de este periodo YA cobró su liquidación —y esa liquidación
  -- incluía el sueldo de este mismo mes, que es lo que dice `monto_periodo`—
  -- congelar ahora volvería a registrarle ese mes. El dinero de este cierre
  -- todavía no salió, así que frenar no le quita nada a nadie: obliga a
  -- registrar el descuento antes, y eso además le deja rastro en su boleta.
  --
  -- ACTÚA EN LOS DOS ESTADOS, a propósito. Con el periodo abierto es el cierre
  -- normal (`fn_periodo_pagado` congela antes de marcar pagado, 0096:276-280).
  -- Con el periodo ya pagado es `fn_repagar_periodo` (0098), que escribe una
  -- versión nueva con el total recalculado: apagarlo ahí dejaría entrar el mismo
  -- doble pago por la otra puerta. Lo que cambia según el estado es el CAMINO
  -- que el mensaje manda a seguir, porque con el periodo pagado
  -- `fn_agregar_movimiento` rechaza el descuento (0181:67-71) y mandar al botón
  -- sería mandar a una puerta cerrada.
  --
  -- La última versión de la liquidación manda (`distinct on … order by version
  -- desc`), igual que en la 0210 y en la pantalla. Y `monto_periodo > 0` es la
  -- condición exacta: desde esta misma migración, una liquidación pagada DESPUÉS
  -- del congelamiento guarda 0 ahí —ya restó—, y entonces no hay nada que
  -- frenar.
  --
  -- ── CAMBIO 0244 ───────────────────────────────────────────────────────────
  -- LA CONDICIÓN QUE LEVANTA EL FRENO ES EL DESCUENTO, NO QUE LA FILA QUEDE EN
  -- CERO. La 0243 salía por `total > 0`, o sea solo si la fila quedaba EN CERO.
  -- Esto costó tres casos medidos, y los tres tenían la misma forma: la
  -- persona hacía EXACTAMENTE lo que el mensaje manda —descontar `monto_periodo`—
  -- y el freno volvía a saltar con la frase idéntica, porque quedaba un saldo que
  -- la cesada SÍ había ganado.
  --   · un feriado dentro del periodo pero posterior al cese —el que fija la
  --     prueba 185—: su liquidación cobró S/500.00, el periodo le calcula
  --     S/519.23, así que descontados los S/500.00 que el mensaje NOMBRA quedan
  --     S/19.23 legítimos y el mes no cerraba;
  --   · una reincorporación dentro del mismo periodo: sobre ese mismo montaje, si
  --     vuelve el 16 y trabaja hasta el 30, el periodo le calcula S/1,348.08 y
  --     descontados los mismos S/500.00 le quedan S/848.08 trabajados de verdad;
  --   · un marcaje que se cerró tarde y añadió un día después del descuento.
  -- Con `total > 0` como única salida, las dos únicas maneras de cerrar el mes
  -- eran quitarle dinero ganado o volver a congelar su liquidación falseando un
  -- registro inmutable. Por eso la condición mira si el DESCUENTO ya está puesto:
  -- `descuentos` es la suma de los movimientos de tipo descuento de esa persona
  -- en este periodo (fn_planilla_calcular), y el botón «💸 Ya le pagué aparte»
  -- escribe justo uno de esos (planilla/page.tsx:1357-1363). Registrado el
  -- importe que el mensaje nombra, el freno se levanta y el saldo se paga.
  --
  -- Su punto ciego, medido y aceptado: si esa persona ya arrastraba OTROS
  -- descuentos que por sí solos igualan o superan `monto_periodo` —un adelanto
  -- grande—, el freno no llega a morder. Se prefiere a acoplar la condición al
  -- texto del concepto: un freno que solo se levanta con una frase literal deja
  -- de levantarse el día que alguien reescribe el botón, y un freno del que no se
  -- puede salir se termina saltando con `--no-verify`. La red principal contra el
  -- doble pago es la parte (A), que cubre el otro orden entero.
  -- ── fin CAMBIO 0244 ───────────────────────────────────────────────────────
  --
  -- CAMBIO 0323 · `f->>'tipo_vinculo' = p_grupo` en las tres consultas de este
  -- freno y del siguiente: un pendiente o una liquidación de OTRO grupo no
  -- debe frenar congelar este.
  select string_agg(x.frase, ' · ' order by x.frase) into v_cobradas
  from (
    select 'A ' || lq.persona || ' ya se le pagó su liquidación el '
           || to_char(lq.congelada_at at time zone 'America/Lima', 'DD/MM/YYYY')
           || ' e incluye S/' || to_char(lq.monto_periodo, 'FM999999990.00')
           || ' de este mismo periodo' as frase
    from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
    join lateral (
      select distinct on (lp.persona_id) lp.*
      from liquidacion_pagada lp
      where lp.persona_id = (f->>'persona_id')::uuid
      order by lp.persona_id, lp.version desc
    ) lq on true
    -- Solo si el cese cae DENTRO de este periodo se solapa el mismo mes.
    -- Quien cesó en un periodo anterior ya cobró aquel mes: avisar de él sería
    -- ruido. Mismo criterio y mismo patrón que la 0210, sostenido por el
    -- EXCLUDE `periodos_sin_solape`: a lo sumo un periodo contiene esa fecha.
    where lq.fecha_cese between v_per.fecha_ini and v_per.fecha_fin
      and lq.monto_periodo > 0
      and coalesce((f->>'total')::numeric, 0) > 0
      and coalesce((f->>'descuentos')::numeric, 0) < lq.monto_periodo   -- CAMBIO 0244
      and f->>'tipo_vinculo' = p_grupo   -- CAMBIO 0323
  ) x;

  if v_cobradas is not null then
    -- Una sola frase corrida, sin saltos de línea: la pantalla imprime el texto
    -- de un P0001 tal cual, sin `whitespace-pre-line`, así que un `\n` se
    -- colapsaría en un espacio (apps/web/lib/admin/mensaje-error.ts:81).
    -- CAMBIO 0244 · la rama del retroactivo es nueva, y las dos frases de abajo
    -- añaden la salida del saldo («si tras el descuento le queda un saldo…»).
    -- La 0243 tenía solo el if/else de los dos estados.
    if p_origen = 'retroactivo' then
      -- LA FOTO RETROACTIVA NO SE FRENA, Y ES LO CONTRARIO DE UNA EXCEPCIÓN
      -- CÓMODA. `fn_planilla_congelar_pendientes` (0096) documenta periodos que
      -- ya están pagados y no tienen foto: meses transferidos hace tiempo, de
      -- antes de que la foto existiera. Ahí la premisa del freno —«el dinero de
      -- este cierre todavía no salió»— es falsa por construcción, y seguir su
      -- instrucción inventaría un descuento que nunca ocurrió sobre el registro
      -- de un pago viejo. Medido: sin esto, esa función aborta entera y deja los
      -- periodos históricos sin foto para siempre.
      -- No puede usarse como escape: solo alcanza periodos SIN ninguna foto, así
      -- que nunca vuelve a congelar nada, y `origen` está acotado por CHECK a
      -- 'pago' | 'retroactivo'.
      raise warning '0244 · foto retroactiva de un periodo ya transferido: %. No se frena —ese dinero salió hace tiempo— pero conviene mirarlo.', v_cobradas;
    elsif v_per.estado = 'abierto' then
      raise exception '%. Cerrar así pagaría ese mes por segunda vez. Antes de cerrar, entra a su fila en Planilla y usa el botón «💸 Ya le pagué aparte» por ESE importe y con esa fecha; si el filtro «Mostrar» no la enseña, cámbialo a «Todos» o pulsa «Verlas» en el aviso de quienes ya no están. Si tras ese descuento le queda un saldo, ese saldo es suyo y se paga con la planilla: no hace falta dejar su fila en cero. El periodo sigue ABIERTO: no se congeló nada.', v_cobradas;
    else
      raise exception '%. Volver a congelarlo así registraría ese mes por segunda vez. Este periodo ya está PAGADO, así que el descuento no se puede anotar sin reabrirlo: usa «Revertir pago» con su motivo (ojo, eso levanta los candados de los marcajes de este periodo mientras esté abierto), registra el descuento con «💸 Ya le pagué aparte» por ESE importe y con esa fecha, y vuelve a marcarlo como pagado. Si tras el descuento le queda un saldo, ese saldo es suyo y se paga: no hace falta dejar su fila en cero. Nada se congeló: la foto anterior sigue intacta.', v_cobradas;
    end if;
  end if;
  -- ── fin CAMBIO 0243 ─────────────────────────────────────────────────────────

  -- ── CAMBIO 0284 · el freno de la hora que nadie marcó ───────────────────────
  --
  -- Cuando alguien olvida marcar su salida, `fn_auto_cierre` cierra el día con
  -- una hora que calcula el sistema, y la jornada queda en
  -- `auto_cerrada_pendiente` esperando que una encargada la confirme.
  --
  -- `fn_recalcular_jornada` se NIEGA a medir tardanza o salida temprana contra
  -- esa hora (0249): «esa hora la inventó el sistema y medir contra ella sería
  -- acusar con un dato falso». Pero esa MISMA hora sí entra a `horas_trabajadas`
  -- y de ahí al ciclo de 48 h que paga recargo del 25/35 % — que además entra a
  -- la base de EsSalud y pensión (0193) y se declara en la PLAME con código
  -- propio. La misma hora es demasiado dudosa para una conversación y
  -- suficientemente buena para una transferencia.
  --
  -- MEDIDO EN PRODUCCIÓN el 2026-08-23, antes de escribir esto:
  --   · 49 auto-cierres entre el 15/07 y el 22/08 — 19 en julio, 30 en agosto.
  --   · 12 de los 49 ANULADOS: la hora inventada se equivoca 1 de cada 4 veces.
  --   · 0 sin revisar en ese momento, y 0 soles de recargo apoyados en una hora
  --     inventada. HOY NO CUESTA NADA. Lo que tapa el agujero es que alguien
  --     entra a Correcciones y las confirma — no el sistema.
  --
  -- Este freno convierte esa disciplina en garantía. Y como el equipo ya las
  -- revisa todas, en la práctica no va a saltar: solo el mes que nadie alcance
  -- a mirarlas. Un freno que no estorba y que solo aparece cuando hace falta es
  -- lo contrario del guardián que chilla siempre.
  --
  -- POR QUÉ AQUÍ Y NO EN `fn_periodo_pagado`: esta función es el cuello por el
  -- que pasan las dos puertas —`fn_periodo_pagado` (0096) y `fn_repagar_periodo`
  -- (0098)— más cualquier llamada por `service_role`. Y no en la pantalla, por
  -- el mismo argumento con el que la 0244 se negó a acoplar su condición al
  -- texto de un botón: se levanta el día que alguien lo reescribe.
  --
  -- POR QUÉ MIRA LA JORNADA Y NO EL MARCAJE: `dias_pendientes` ya viaja en
  -- `v_calc->'filas'` (0276), así que no hace falta consulta nueva. Que no se
  -- pierde nada por ahí está medido: el cruce marcaje × jornada de
  -- `scripts/sql-manual/cuantas_veces_cierra_el_cron.sql`, corrido en producción
  -- ese mismo día, salió limpio — todo marcaje sin revisar tenía su jornada en
  -- `auto_cerrada_pendiente`.
  --
  -- LO QUE NO MIRA, A PROPÓSITO: las jornadas `abierta` y `en_pausa`. No las
  -- trae `v_calc` y exigirían una consulta nueva dentro de esta función,
  -- multiplicando la superficie del atasco. Queda como pendiente deliberado.
  select case when count(*) = 0 then null
              else string_agg(x.frase, ' · ' order by x.frase)
                     filter (where x.rn <= 6)
                   || case when count(*) > 6
                           then ' · y ' || (count(*) - 6)::text || ' más'
                           else '' end
         end into v_pendientes
  from (
    select (f->>'nombre') || ' (' || (f->>'dias_pendientes') || ' día(s))' as frase,
           row_number() over (order by (f->>'nombre')) as rn
    from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
    where coalesce((f->>'dias_pendientes')::int, 0) > 0
      and f->>'tipo_vinculo' = p_grupo   -- CAMBIO 0323
  ) x;

  if v_pendientes is not null then
    -- Una sola frase corrida, sin saltos de línea, por lo mismo que la 0244:
    -- la pantalla imprime el texto de un P0001 tal cual (mensaje-error.ts:81).
    if p_origen = 'retroactivo' then
      -- Misma razón que la rama retroactiva de la 0244:
      -- `fn_planilla_congelar_pendientes` (0096) documenta meses transferidos
      -- hace años. Abortar ahí dejaría los periodos históricos sin foto para
      -- siempre — está medido en la cabecera de la 0244.
      raise warning '0284 · foto retroactiva con días auto-cerrados sin revisar: %. No se frena —ese mes se pagó hace tiempo— pero conviene mirarlo.', v_pendientes;
    elsif v_per.estado = 'abierto' then
      raise exception 'Hay días cuya hora de salida la puso el sistema y todavía nadie la confirmó: %. Esa hora no la marcó ninguna persona, y si cruza las 48 h de la semana se paga recargo sobre ella. Entra a Correcciones, confirma o corrige esas salidas, y vuelve a cerrar. El periodo sigue ABIERTO: no se congeló nada.', v_pendientes;
    else
      raise exception 'Hay días cuya hora de salida la puso el sistema y nadie la confirmó: %. Este periodo ya está PAGADO, así que para arreglarlo hay que usar «Revertir pago» con su motivo (ojo, eso levanta los candados de los marcajes de este periodo mientras esté abierto), confirmar esas salidas en Correcciones, y volver a marcarlo como pagado. Nada se congeló: la foto anterior sigue intacta.', v_pendientes;
    end if;
  end if;
  -- ── fin CAMBIO 0284 ─────────────────────────────────────────────────────────

  -- CAMBIO 0323 · el version es por (periodo, grupo), no por periodo a secas.
  select coalesce(max(version), 0) + 1 into v_ver
  from planilla_pagada_detalle where periodo_id = p_periodo_id and grupo = p_grupo;

  insert into planilla_pagada_detalle (
    periodo_id, grupo, persona_id, version, congelada_por, origen,
    nombre, sede_codigo, area_codigo, rango, salario_ref,
    horas_mes, dias_trabajados,
    pago_base, monto_feriados, monto_plus, asignacion_familiar,
    bonos, descuentos,
    monto_movilidad, monto_educacion, descuento_pension, aporte_essalud,   -- CAMBIO 0127
    monto_sobretiempo,                                                     -- CAMBIO 0201
    monto_descanso_semanal,                                                -- CAMBIO 0280
    total,
    provision_gratificacion, provision_bonif_extraordinaria, provision_cts, provision_vacaciones, provision_total,   -- CAMBIO 0134
    fila
  )
  select
    p_periodo_id,
    p_grupo,   -- CAMBIO 0323
    (f->>'persona_id')::uuid,
    v_ver,
    p_autor,
    p_origen,
    f->>'nombre',
    f->>'sede',
    pe.funcion,
    f->>'rango',
    (f->>'salario_ref')::numeric,
    coalesce((f->>'horas_mes')::numeric, 0),
    coalesce((f->>'dias_trabajados')::int, 0),
    coalesce((f->>'pago_base')::numeric, 0),
    coalesce((f->>'monto_feriados')::numeric, 0),
    coalesce((f->>'monto_plus')::numeric, 0),
    coalesce((f->>'asignacion_familiar')::numeric, 0),
    coalesce((f->>'bonos')::numeric, 0),
    coalesce((f->>'descuentos')::numeric, 0),
    -- CAMBIO 0127 — los tres conceptos que entraron al total en la 0110 y la
    -- 0120, mas el EsSalud como dato. Sin esto la foto no puede cuadrar.
    coalesce((f->>'monto_movilidad')::numeric, 0),
    coalesce((f->>'monto_educacion')::numeric, 0),
    coalesce((f->>'descuento_afp')::numeric, 0),
    coalesce((f->>'aporte_essalud')::numeric, 0),
    -- CAMBIO 0201 — el recargo del sobretiempo, que la 0185 metio al total.
    -- Mismo motivo que la linea de arriba: sin columna, la foto no cuadra.
    coalesce((f->>'monto_sobretiempo')::numeric, 0),
    coalesce((f->>'monto_descanso_semanal')::numeric, 0),                  -- CAMBIO 0280
    coalesce((f->>'total')::numeric, 0),
    coalesce((f->>'provision_gratificacion')::numeric, 0),
    coalesce((f->>'provision_bonif_extraordinaria')::numeric, 0),   -- CAMBIO 0134
    coalesce((f->>'provision_cts')::numeric, 0),
    coalesce((f->>'provision_vacaciones')::numeric, 0),
    coalesce((f->>'provision_total')::numeric, 0),
    f
  from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
  left join personas pe on pe.id = (f->>'persona_id')::uuid
  where f->>'tipo_vinculo' = p_grupo;   -- CAMBIO 0323

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke all on function fn_planilla_congelar(uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function fn_planilla_congelar(uuid, text, uuid, text) to service_role;

comment on function fn_planilla_congelar(uuid, text, uuid, text) is
  'Congela la foto de UN grupo (tipo_vinculo) del periodo — 0323, antes congelaba el periodo entero. Interna: solo la llaman fn_periodo_pagado, fn_repagar_periodo y fn_planilla_congelar_pendientes.';


-- ── 7 · fn_periodo_pagado gana `p_grupo` ─────────────────────────────────────
-- Marca UN grupo como pagado. Cuando el ÚLTIMO grupo con gente en el periodo
-- queda pagado, además marca `periodos_planilla.estado = 'pagado'` — así el
-- candado de horas existente (entrega 2) sigue activándose exactamente cuando
-- antes se activaba: cuando TODO el periodo está, de verdad, completo.
drop function if exists fn_periodo_pagado(uuid, boolean);

create or replace function fn_periodo_pagado(p_periodo_id uuid, p_pagado boolean, p_grupo text default 'planilla')
returns void language plpgsql security definer set search_path = public as $fn$
declare
  v_per record;
  v_n int;
  v_grupos_con_gente text[];
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede marcar un pago.';
  end if;

  if coalesce(p_pagado, false) is not true then
    raise exception 'Para reabrir un pago usa Revertir pago: la regla del sistema es que quede el motivo, quién lo hizo y cuándo. Reabrir levanta los candados que protegen los marcajes de ese periodo.';
  end if;

  if p_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'Grupo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador, practicante.', p_grupo;
  end if;

  select * into v_per from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;

  -- CAMBIO 0323 · COMPATIBILIDAD CON LO DE ANTES DE ESTA MIGRACIÓN: un
  -- periodo que diga periodos_planilla.estado = 'pagado' y que NUNCA se haya
  -- tocado por grupo (cero filas en periodo_grupo_pago, el backfill del
  -- bloque 4 no alcanzó porque no tenía foto, o es de antes de existir esta
  -- tabla) se trata como si TODOS sus grupos ya estuvieran pagados — es
  -- exactamente el bucket único que existía antes de esta migración.
  if exists (
    select 1 from periodo_grupo_pago
     where periodo_id = p_periodo_id and grupo = p_grupo and estado = 'pagado'
  ) or (
    v_per.estado = 'pagado'
    and not exists (select 1 from periodo_grupo_pago where periodo_id = p_periodo_id)
  ) then
    raise exception 'El grupo % de este periodo ya está pagado. Su desglose quedó congelado; para cambiarlo hay que reabrirlo con Revertir pago.', p_grupo;
  end if;

  v_n := fn_planilla_congelar(p_periodo_id, 'pago', fn_persona_actual_id(), p_grupo);

  insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at, pagado_por)
  values (p_periodo_id, p_grupo, 'pagado', now(), fn_persona_actual_id())
  on conflict (periodo_id, grupo)
  do update set estado = 'pagado', pagado_at = now(), pagado_por = excluded.pagado_por;

  -- CAMBIO 0323 · ¿ya están pagados TODOS los grupos que de verdad tienen
  -- gente en este periodo? Se recalcula aquí y no se asume de
  -- `planilla_pagada_detalle`, porque un grupo con gente que TODAVÍA no se ha
  -- pagado nunca no aparece ahí — y "no aparece" no puede leerse como "ya
  -- está pagado".
  select array_agg(distinct f->>'tipo_vinculo') into v_grupos_con_gente
  from jsonb_array_elements(
    coalesce(fn_planilla_calcular(v_per.fecha_ini, v_per.fecha_fin, p_periodo_id)->'filas', '[]'::jsonb)
  ) f;

  if v_grupos_con_gente is not null and not exists (
    select 1 from unnest(v_grupos_con_gente) g(grupo)
     where not exists (
       select 1 from periodo_grupo_pago
        where periodo_id = p_periodo_id and grupo = g.grupo and estado = 'pagado'
     )
  ) then
    update periodos_planilla set estado = 'pagado', pagado_at = now() where id = p_periodo_id;
  end if;
end;
$fn$;

grant execute on function fn_periodo_pagado(uuid, boolean, text) to authenticated;
revoke execute on function fn_periodo_pagado(uuid, boolean, text) from public, anon;

comment on function fn_periodo_pagado(uuid, boolean, text) is
  'Marca UN grupo (tipo_vinculo) del periodo como pagado — 0323, antes marcaba el periodo entero. Cuando el último grupo con gente queda pagado, también marca periodos_planilla.estado = pagado, para que el candado de horas existente siga activándose igual que siempre.';


-- ── 8 · fn_revertir_pago gana `p_grupo` ──────────────────────────────────────
-- Reabre UN grupo. SIEMPRE vuelve a poner periodos_planilla.estado =
-- 'abierto' (si un grupo se reabre, el periodo ya no está "completo"). El
-- recálculo de jornadas del final SOLO corre si el periodo estaba
-- efectivamente 'pagado' antes de este reabrir —es decir, si el candado de
-- horas de verdad había llegado a activarse— y en ese caso sigue recalculando
-- TODO el rango de fechas, no solo el grupo reabierto: hasta la entrega 2 el
-- candado de horas es uno solo para el periodo entero, así que reabrir
-- cualquier grupo lo levanta para todos, exactamente como hacía antes de esta
-- migración.
drop function if exists fn_revertir_pago(uuid, text);

create or replace function fn_revertir_pago(p_periodo_id uuid, p_motivo text, p_grupo text default 'planilla')
returns void language plpgsql security definer set search_path = public as $$
declare
  v_estado_grupo text; v_pagado_at_grupo timestamptz;
  v_estado_periodo_antes text; v_pagado_at_periodo timestamptz;
  v_ini date; v_fin date;
  v_dia record; v_dias int := 0;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede revertir un pago.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo de la reapertura es obligatorio (mínimo 4 caracteres).';
  end if;
  if p_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'Grupo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador, practicante.', p_grupo;
  end if;

  select estado, fecha_ini, fecha_fin, pagado_at
    into v_estado_periodo_antes, v_ini, v_fin, v_pagado_at_periodo
  from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;

  select estado, pagado_at into v_estado_grupo, v_pagado_at_grupo
  from periodo_grupo_pago where periodo_id = p_periodo_id and grupo = p_grupo for update;

  -- CAMBIO 0323 · COMPATIBILIDAD: sin fila en periodo_grupo_pago (nunca se
  -- tocó por grupo) y el periodo entero dice 'pagado', es el bucket único de
  -- antes de esta migración — se trata este grupo como pagado también, con
  -- la fecha del periodo como aproximación (nunca se guardó una por grupo).
  if not found and v_estado_periodo_antes = 'pagado' then
    v_estado_grupo := 'pagado';
    v_pagado_at_grupo := v_pagado_at_periodo;
  end if;

  if coalesce(v_estado_grupo, 'abierto') <> 'pagado' then
    raise exception 'El grupo % de este periodo no está pagado (estado actual: %).', p_grupo, coalesce(v_estado_grupo, 'abierto');
  end if;

  insert into reversas_pago (periodo_id, revertido_por, motivo, pagado_at_previo, grupo)
    values (p_periodo_id, fn_persona_actual_id(), trim(p_motivo), v_pagado_at_grupo, p_grupo);

  -- Upsert, no update: la fila puede no existir todavía (el caso de
  -- compatibilidad de arriba). A partir de aquí este (periodo, grupo) ya
  -- queda con seguimiento propio.
  insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at, pagado_por)
  values (p_periodo_id, p_grupo, 'abierto', null, null)
  on conflict (periodo_id, grupo)
  do update set estado = 'abierto', pagado_at = null, pagado_por = null;

  -- Si un grupo se reabre, el periodo deja de estar "completo" — sin importar
  -- si antes de este reabrir estaba pagado o no.
  update periodos_planilla set estado = 'abierto', pagado_at = null where id = p_periodo_id;

  -- ── Y ahora sí, se descongela ─────────────────────────────────────────────
  -- SOLO si el periodo estaba de verdad 'pagado' antes de este reabrir: es la
  -- única situación en la que el candado de horas (que hasta la entrega 2
  -- sigue siendo uno solo para el periodo entero) había llegado a activarse.
  -- Si todavía faltaba pagar otro grupo, el candado nunca se encendió y no
  -- hay nada que recalcular — hacerlo igual sería trabajo redundante sobre
  -- jornadas que ya se venían calculando en vivo.
  --
  -- EL ORDEN IMPORTA Y NO ES CASUAL: los dos updates de arriba tienen que
  -- estar hechos antes de llegar aquí. `fn_recalcular_jornada` lee el estado
  -- del periodo en cada llamada, así que si se recalculara antes saldría en
  -- silencio por su propio candado y este bucle no haría absolutamente nada —
  -- sin fallar, sin avisar, y con toda la pinta de estar funcionando.
  --
  -- SOLO DÍAS CON MARCAJES. Un día sin ninguna marca es historia cargada a mano
  -- (la 0045 tiene 1.427 así, todo 2025 de siete personas) y recalcularlo la
  -- borraría, porque fn_recalcular_jornada elimina la jornada de un día que se
  -- quedó sin marcas. Las personas nunca se borran y su historial tampoco.
  --
  -- Sin filtrar por `anulada_at`: un día cuyas marcas se anularon todas SÍ tuvo
  -- marcas, su jornada es derivada, y le toca desaparecer.
  if v_estado_periodo_antes = 'pagado' then
    for v_dia in
      select distinct m.persona_id,
             (m.timestamp_marca at time zone 'America/Lima')::date as fecha
      from marcajes m
      where (m.timestamp_marca at time zone 'America/Lima')::date between v_ini and v_fin
    loop
      perform fn_recalcular_jornada(v_dia.persona_id, v_dia.fecha);
      v_dias := v_dias + 1;
    end loop;
  end if;

  raise notice 'Grupo % reabierto: % jornadas recalculadas entre % y %.', p_grupo, v_dias, v_ini, v_fin;
end;
$$;

grant execute on function fn_revertir_pago(uuid, text, text) to authenticated;
revoke execute on function fn_revertir_pago(uuid, text, text) from public, anon;

comment on function fn_revertir_pago(uuid, text, text) is
  'Reabre UN grupo (tipo_vinculo) del periodo — 0323, antes reabría el periodo entero. Siempre vuelve a poner periodos_planilla.estado = abierto. El recálculo de jornadas del rango entero solo corre si el periodo estaba de verdad pagado (todos los grupos) antes de este reabrir.';


-- ── 9 · fn_repagar_periodo gana `p_grupo` ────────────────────────────────────
-- Recalcula y vuelve a congelar UN grupo YA pagado, sin pasar por abierto.
-- El periodo nunca se toca (sigue como estaba): esta función es exactamente
-- lo que promete la 0098, ahora acotada al grupo que se repaga.
drop function if exists fn_repagar_periodo(uuid, text);

create or replace function fn_repagar_periodo(p_periodo_id uuid, p_motivo text, p_grupo text default 'planilla')
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  v_estado_grupo text;
  v_pagado_at_grupo timestamptz;
  v_estado_periodo text; v_pagado_at_periodo timestamptz;
  v_antes numeric;
  v_ahora numeric;
  v_ver int;
  v_n int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede volver a pagar un periodo.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo es obligatorio (mínimo 4 caracteres): volver a pagar cambia una cifra que ya se entregó.';
  end if;
  if p_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'Grupo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador, practicante.', p_grupo;
  end if;

  select estado, pagado_at into v_estado_periodo, v_pagado_at_periodo
  from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  select estado, pagado_at into v_estado_grupo, v_pagado_at_grupo
  from periodo_grupo_pago where periodo_id = p_periodo_id and grupo = p_grupo for update;

  -- CAMBIO 0323 · COMPATIBILIDAD: mismo criterio que fn_revertir_pago — sin
  -- fila propia y el periodo entero dice 'pagado', se trata este grupo como
  -- pagado también (el bucket único de antes de esta migración).
  if not found and v_estado_periodo = 'pagado' then
    v_estado_grupo := 'pagado';
    v_pagado_at_grupo := v_pagado_at_periodo;
  end if;

  if coalesce(v_estado_grupo, 'abierto') <> 'pagado' then
    raise exception 'El grupo % no está pagado (estado actual: %). Para marcarlo por primera vez usa el botón de esa pestaña.', p_grupo, coalesce(v_estado_grupo, 'abierto');
  end if;

  -- El antes se lee ANTES de congelar: después, la vigente ya sería la nueva.
  select coalesce(sum(total), 0) into v_antes
  from v_planilla_pagada where periodo_id = p_periodo_id and grupo = p_grupo;

  insert into reversas_pago (periodo_id, revertido_por, motivo, pagado_at_previo, tipo, grupo)
  values (p_periodo_id, fn_persona_actual_id(), trim(p_motivo), v_pagado_at_grupo, 'repago', p_grupo);

  v_n := fn_planilla_congelar(p_periodo_id, 'pago', fn_persona_actual_id(), p_grupo);

  -- Upsert: la fila puede no existir todavía (el caso de compatibilidad).
  insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at, pagado_por)
  values (p_periodo_id, p_grupo, 'pagado', now(), fn_persona_actual_id())
  on conflict (periodo_id, grupo) do update set pagado_at = now();

  select coalesce(sum(total), 0), max(version) into v_ahora, v_ver
  from v_planilla_pagada where periodo_id = p_periodo_id and grupo = p_grupo;

  return jsonb_build_object(
    'version',     v_ver,
    'personas',    v_n,
    'neto_antes',  round(v_antes, 2),
    'neto_ahora',  round(v_ahora, 2),
    'diferencia',  round(v_ahora - v_antes, 2)
  );
end;
$fn$;

grant execute on function fn_repagar_periodo(uuid, text, text) to authenticated;
revoke execute on function fn_repagar_periodo(uuid, text, text) from public, anon;

comment on function fn_repagar_periodo(uuid, text, text) is
  'Recalcula UN grupo YA pagado y guarda una copia nueva de SU foto, sin pasar por abierto — 0323, antes recalculaba el periodo entero. Exige motivo y deja rastro en reversas_pago con tipo = repago y el grupo.';


-- ── 10 · fn_planilla_congelar_pendientes ahora es por (periodo, grupo) ─────
-- Misma función-red que la 0096, extendida: para cada periodo YA marcado
-- pagado, mira CADA grupo que de verdad tiene gente en él (no todos los 5 a
-- ciegas) y, si a ESE grupo le falta su fila en `periodo_grupo_pago`, lo
-- congela y la crea — usando el `pagado_at` del periodo como fecha histórica,
-- igual que el backfill del bloque 4.
create or replace function fn_planilla_congelar_pendientes()
returns int language plpgsql security definer set search_path = public as $fn$
declare r record; v_calc jsonb; v_grupo text; v_total int := 0;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede tomar la foto de un pago.';
  end if;

  for r in
    select p.id, p.fecha_ini, p.fecha_fin, p.pagado_at from periodos_planilla p
    where p.estado = 'pagado'
    order by p.fecha_ini
  loop
    v_calc := fn_planilla_calcular(r.fecha_ini, r.fecha_fin, r.id);

    for v_grupo in
      select distinct f->>'tipo_vinculo'
      from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
    loop
      if not exists (
        select 1 from periodo_grupo_pago where periodo_id = r.id and grupo = v_grupo
      ) then
        v_total := v_total + fn_planilla_congelar(r.id, 'retroactivo', fn_persona_actual_id(), v_grupo);
        insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at, pagado_por)
        values (r.id, v_grupo, 'pagado', r.pagado_at, null::uuid)
        on conflict (periodo_id, grupo) do nothing;
      end if;
    end loop;
  end loop;

  return v_total;
end;
$fn$;
grant execute on function fn_planilla_congelar_pendientes() to authenticated;
revoke execute on function fn_planilla_congelar_pendientes() from public, anon;

comment on function fn_planilla_congelar_pendientes() is
  'Red de seguridad: congela el (periodo, grupo) que figura pagado y no tiene foto todavía — 0323, antes miraba el periodo entero de una sola vez.';


-- ── 11 · fn_proyeccion_periodo lee cada persona según SU grupo ──────────────
-- Antes (0313): todo el periodo se leía de la foto o se recalculaba en
-- bloque, según un solo interruptor. Ahora cada persona se lee de la foto
-- SOLO SI SU GRUPO está pagado en `periodo_grupo_pago`; si su grupo sigue
-- abierto, sale en vivo del mismo cálculo que ya se hizo arriba. Un periodo
-- con planilla pagada y RxH todavía pendiente devuelve las dos cosas
-- mezcladas en la misma respuesta — es lo que la pantalla necesita para
-- dibujar cada pestaña con lo que le corresponde.
create or replace function fn_proyeccion_periodo(p_periodo_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_p record;
  v_out jsonb;
  v_filas jsonb;
  v_congelada_at timestamptz;
  v_personas int;
  v_grupos_pagados text[];   -- CAMBIO 0323
  v_grupos_pendientes int;  -- CAMBIO 0323
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la planilla.';
  end if;
  select * into v_p from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_out := fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, v_p.id);

  -- ⇩⇩⇩ CAMBIO 0323 ⇩⇩⇩
  select array_agg(grupo) into v_grupos_pagados
  from periodo_grupo_pago
  where periodo_id = v_p.id and estado = 'pagado';

  if (v_grupos_pagados is null or array_length(v_grupos_pagados, 1) = 0)
     and v_p.estado <> 'pagado' then
    -- Ningún grupo pagado todavía, y el periodo tampoco lo dice a la vieja
    -- usanza: todo en vivo, igual que antes de la 0313 para este periodo.
    return v_out || jsonb_build_object(
      'periodo_id', v_p.id,
      'estado',     v_p.estado,
      'pagado_at',  v_p.pagado_at,
      'simulacion', false,
      'fuente',     'calculo');
  end if;

  if v_grupos_pagados is null or array_length(v_grupos_pagados, 1) = 0 then
    -- CAMBIO 0323 · COMPATIBILIDAD: el periodo entero dice 'pagado' (a la
    -- vieja usanza, de antes de esta migración) pero periodo_grupo_pago no
    -- tiene ninguna fila para él. Se toman como "pagados" los grupos que
    -- de verdad aparecen en su foto — el bucket único de antes.
    select array_agg(distinct grupo) into v_grupos_pagados
      from planilla_pagada_detalle where periodo_id = v_p.id;

    if v_grupos_pagados is null then
      -- Pagado y sin absolutamente ninguna foto: un periodo de antes de que
      -- existiera `planilla_pagada_detalle` (0096). No hay de dónde leer,
      -- así que se recalcula — pero se DICE, para que la pantalla avise en
      -- vez de dar un recálculo disfrazado de original. Mismo contrato que
      -- la 0313.
      return v_out || jsonb_build_object(
        'periodo_id', v_p.id,
        'estado',     v_p.estado,
        'pagado_at',  v_p.pagado_at,
        'simulacion', false,
        'fuente',     'recalculo_sin_foto');
    end if;
  end if;

  -- La foto: la última versión DE CADA PERSONA cuyo grupo está pagado.
  -- `distinct on (persona_id)` sigue bastando aunque el version ahora sea por
  -- (periodo, grupo): una persona pertenece a un solo grupo a la vez, así que
  -- nunca compite consigo misma entre dos secuencias de version distintas.
  with foto as (
    select distinct on (d.persona_id)
           d.persona_id, d.fila, d.congelada_at
      from planilla_pagada_detalle d
     where d.periodo_id = v_p.id
       and d.grupo = any(v_grupos_pagados)
     order by d.persona_id, d.version desc
  ),
  vivo as (
    -- Cualquiera cuyo grupo sigue abierto, y —por seguridad— cualquiera que
    -- la foto no haya encontrado (grupo marcado pagado pero sin foto para esa
    -- persona en concreto: un periodo pre-0096 nunca tuvo esta tabla, ver
    -- 0313, medido en 0 casos el 2026-08-26).
    select f as fila
      from jsonb_array_elements(coalesce(v_out->'filas', '[]'::jsonb)) f
     where not (f->>'tipo_vinculo' = any(v_grupos_pagados))
        or (f->>'persona_id')::uuid not in (select persona_id from foto)
  )
  select jsonb_agg(x.fila order by x.fila->>'nombre'),
         (select max(congelada_at) from foto),
         (select count(*) from foto)
    into v_filas, v_congelada_at, v_personas
    from (
      select fila from foto
      union all
      select fila from vivo
    ) x;

  -- ¿Queda algún grupo con gente que TODAVÍA no se pagó? Si no queda ninguno
  -- es "foto" de punta a punta, igual que la 0313 para el periodo entero. Si
  -- queda al menos uno, es una mezcla real y la pantalla necesita saberlo
  -- para no decir "esto ya se pagó" de algo que en parte sigue en vivo.
  select count(distinct f->>'tipo_vinculo') into v_grupos_pendientes
    from jsonb_array_elements(coalesce(v_out->'filas', '[]'::jsonb)) f
   where not (f->>'tipo_vinculo' = any(v_grupos_pagados));

  return v_out || jsonb_build_object(
    'filas',             coalesce(v_filas, v_out->'filas'),
    'periodo_id',        v_p.id,
    'estado',            v_p.estado,
    'pagado_at',         v_p.pagado_at,
    'simulacion',        false,
    'fuente',            case when coalesce(v_grupos_pendientes, 0) = 0 then 'foto' else 'mixto' end,
    'foto_congelada_at', v_congelada_at,
    'foto_personas',     coalesce(v_personas, 0));
end;
$function$;

comment on function fn_proyeccion_periodo(uuid) is
  'La planilla de un periodo, persona por persona: quien pertenece a un grupo pagado sale de su foto congelada, quien no sale del cálculo en vivo — 0323. `fuente` = calculo (nadie pagado) | mixto (algunos grupos sí, otros no) | foto (todos). Antes (0313) era un solo interruptor para el periodo entero.';

grant execute on function fn_proyeccion_periodo(uuid) to authenticated;
revoke execute on function fn_proyeccion_periodo(uuid) from public, anon;


-- ── 12 · fn_costos_planilla cuenta cada grupo en cuanto SU grupo se paga ────
-- Antes: `pp.estado = 'pagado'` — el periodo entero, o nada. Ahora: cada fila
-- de `v_planilla_pagada` entra en cuanto SU (periodo, grupo) está pagado en
-- `periodo_grupo_pago`, sin esperar a los demás grupos de ese periodo. NO
-- cambia ninguna cifra existente para un periodo donde todo se pagó junto
-- (que es el 100% de lo que hay hoy): solo deja de esconder a planilla
-- mientras RxH sigue pendiente.
create or replace function fn_costos_planilla(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver los costos de planilla.';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'El rango de fechas no es válido.';
  end if;

  with base as (
    select
      f.*,
      pp.fecha_ini,
      pp.fecha_fin,
      pp.pagado_at,
      extract(year  from pp.fecha_fin)::int as anio,
      extract(month from pp.fecha_fin)::int as mes,
      coalesce(se.tipo, 'tienda') as sede_tipo,
      coalesce(se.nombre, f.sede_codigo) as sede_nombre,
      coalesce((f.fila->>'descuento_afp')::numeric, 0)  as pension_remitida,
      coalesce((f.fila->>'aporte_essalud')::numeric, 0) as essalud_empresa,
      coalesce((f.fila->>'retencion_4ta')::numeric, 0)  as retencion_remitida
    from v_planilla_pagada f
    join periodos_planilla pp on pp.id = f.periodo_id
    left join sedes se on se.codigo = f.sede_codigo
    where pp.fecha_fin between p_desde and p_hasta
      -- CAMBIO 0323 · antes: pp.estado = 'pagado' (el periodo entero de una
      -- sola vez). Ahora, el grupo de ESTA fila tiene que estar pagado —
      -- planilla entra en cuanto se paga, sin esperar a que RxH también lo
      -- esté. COMPATIBILIDAD: un periodo sin ninguna fila en
      -- periodo_grupo_pago (de antes de esta migración) sigue el criterio
      -- viejo — pp.estado = 'pagado' a secas — porque ahí nunca hubo grupos
      -- que distinguir.
      and (
        exists (
          select 1 from periodo_grupo_pago g
           where g.periodo_id = f.periodo_id
             and g.grupo = f.grupo
             and g.estado = 'pagado'
        )
        or (
          pp.estado = 'pagado'
          and not exists (select 1 from periodo_grupo_pago g2 where g2.periodo_id = f.periodo_id)
        )
      )
  )
  select jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,

    'periodos_retroactivos', (
      select count(distinct periodo_id)::int from base where origen = 'retroactivo'
    ),

    'totales', (
      select jsonb_build_object(
        'personas',    count(distinct persona_id),
        'periodos',    count(distinct periodo_id),
        'neto',        coalesce(round(sum(total), 2), 0),
        'provisiones', coalesce(round(sum(provision_total), 2), 0),
        'costo',       coalesce(round(sum(costo_total), 2), 0),
        'salio_del_banco', coalesce(round(sum(total + pension_remitida + essalud_empresa + retencion_remitida), 2), 0)
      ) from base
    ),

    'por_periodo', (
      select coalesce(jsonb_agg(x order by x->>'fecha_fin' desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'periodo_id',  b.periodo_id,
          'fecha_ini',   b.fecha_ini,
          'fecha_fin',   b.fecha_fin,
          'anio',        b.anio,
          'mes',         b.mes,
          'pagado_at',   max(b.pagado_at),
          'congelada_at', max(b.congelada_at),
          'version',     max(b.version),
          'reconstruida', bool_or(b.origen = 'retroactivo'),
          'personas',    count(*),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)
        ) as x
        from base b
        group by b.periodo_id, b.fecha_ini, b.fecha_fin, b.anio, b.mes
      ) s
    ),

    'por_sede', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'sede',        b.sede_codigo,
          'nombre',      b.sede_nombre,
          'tipo',        b.sede_tipo,
          'personas',    count(distinct b.persona_id),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2),
          'costo_por_persona', round(sum(b.costo_total) / nullif(count(distinct b.persona_id), 0), 2),
          'costo_por_hora',    round(sum(b.costo_total) / nullif(sum(b.horas_mes), 0), 2)
        ) as x
        from base b
        group by b.sede_codigo, b.sede_nombre, b.sede_tipo
      ) s
    ),

    'por_tipo', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'tipo',        b.sede_tipo,
          'sedes',       count(distinct b.sede_codigo),
          'personas',    count(distinct b.persona_id),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2),
          'costo_por_persona', round(sum(b.costo_total) / nullif(count(distinct b.persona_id), 0), 2),
          'costo_por_hora',    round(sum(b.costo_total) / nullif(sum(b.horas_mes), 0), 2)
        ) as x
        from base b
        group by b.sede_tipo
      ) s
    ),

    'por_area', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'area',        b.area_codigo,
          'nombre',      coalesce(ar.nombre, b.area_codigo, 'Sin área'),
          'operativa',   coalesce(ar.operativa, false),
          'personas',    count(distinct b.persona_id),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)
        ) as x
        from base b
        left join areas ar on ar.codigo = b.area_codigo
        group by b.area_codigo, ar.nombre, ar.operativa
      ) s
    ),

    'por_persona', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'persona_id',  b.persona_id,
          'nombre',      max(b.nombre),
          'sede',        max(b.sede_codigo),
          'area',        max(b.area_codigo),
          'periodos',    count(*),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)
        ) as x
        from base b
        group by b.persona_id
      ) s
    )
  ) into v_out;

  return v_out;
end;
$fn$;

grant execute on function fn_costos_planilla(date, date) to authenticated;
revoke execute on function fn_costos_planilla(date, date) from public, anon;

comment on function fn_costos_planilla(date, date) is
  'Costos de planilla en un rango. Cuenta una fila en cuanto SU grupo (tipo_vinculo) está pagado — 0323, antes esperaba a que TODO el periodo lo estuviera.';


-- ── 13 · Función nueva: el estado de pago por grupo, para la pantalla ───────
create or replace function fn_periodo_grupos_estado(p_periodo_id uuid)
returns table (
  grupo             text,
  estado            text,
  pagado_at         timestamptz,
  pagado_por_nombre text,
  personas          int
)
language plpgsql stable security definer set search_path = public as $fn$
declare v_p record; v_calc jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver el estado de pago por grupo.';
  end if;
  select * into v_p from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_calc := fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, p_periodo_id);

  return query
  with conteo as (
    select f->>'tipo_vinculo' as grupo, count(*)::int as personas
    from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
    group by 1
  ),
  grupos as (
    select unnest(array['planilla','prueba','rxh','no_trabajador','practicante']) as grupo
  )
  select
    g.grupo,
    coalesce(gp.estado, 'abierto'),
    gp.pagado_at,
    nullif(trim(coalesce(pe.nombres, '') || ' ' || coalesce(pe.apellidos, '')), ''),
    coalesce(c.personas, 0)
  from grupos g
  left join periodo_grupo_pago gp on gp.periodo_id = p_periodo_id and gp.grupo = g.grupo
  left join conteo c on c.grupo = g.grupo
  left join personas pe on pe.id = gp.pagado_por
  order by g.grupo;
end;
$fn$;

grant execute on function fn_periodo_grupos_estado(uuid) to authenticated;
revoke execute on function fn_periodo_grupos_estado(uuid) from public, anon;

comment on function fn_periodo_grupos_estado(uuid) is
  'El estado de pago de los 5 grupos (tipo_vinculo) de un periodo — 0323. Siempre devuelve las 5 filas, existan o no en periodo_grupo_pago (los que nunca se pagaron salen "abierto"), con cuánta gente tiene cada uno en este periodo.';

notify pgrst, 'reload schema';


-- ── 14 · Rastro ──────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (323, 'pagar_planilla_y_rxh_por_separado')
on conflict (numero) do nothing;


-- ── 15 · Comprobación de que la pegada llegó entera ─────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado del
-- último select. Todas las columnas tienen que salir en `true` (o el número
-- que se indica).
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_periodo_pagado' and p.pronargs = 3)
    = 1 as periodo_pagado_tiene_3_argumentos,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_congelar' and p.pronargs = 4)
    = 1 as planilla_congelar_tiene_4_argumentos,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_revertir_pago' and p.pronargs = 3)
    = 1 as revertir_pago_tiene_3_argumentos,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_repagar_periodo' and p.pronargs = 3)
    = 1 as repagar_periodo_tiene_3_argumentos,
  (select count(*) from information_schema.columns
    where table_name = 'planilla_pagada_detalle' and column_name = 'grupo')
    = 1 as foto_tiene_columna_grupo,
  (select count(*) from pg_constraint where conname = 'planilla_pagada_detalle_pkey'
     and conrelid = 'planilla_pagada_detalle'::regclass and array_length(conkey, 1) = 4)
    = 1 as la_llave_primaria_tiene_4_columnas,
  (select to_regclass('public.periodo_grupo_pago') is not null) as tabla_periodo_grupo_pago_existe,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_periodo_grupos_estado')
    = 1 as funcion_de_lectura_existe,
  (select count(*) from migraciones_aplicadas where numero = 323) = 1 as quedo_el_rastro;
