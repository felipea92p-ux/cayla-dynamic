-- ============================================================================
-- 0140 — El cuadro de categorías y funciones.
--
-- QUÉ PROMETE
--
-- Que CAYLA tenga el cuadro de categorías que la Ley 30709 y su reglamento
-- (D.S. 002-2018-TR) exigen a TODO empleador privado, sin umbral de tamaño:
-- los puestos agrupados por valor equivalente, qué hace cada categoría, qué se
-- necesita para estar en ella, y POR QUÉ se remunera por encima de la anterior.
--
-- No tenerlo es infracción MUY GRAVE — numeral 25.22 del RLGIT. Hoy CAYLA está
-- incursa en ella: los rangos existían, pero vivían en un archivo de TypeScript
-- como valor por defecto. Un valor por defecto no es una categoría; falta la
-- descripción de funciones y falta el criterio.
--
-- QUÉ TRAE, Y POR QUÉ CADA PIEZA
--
--   categorias_laborales   las seis categorías, con propósito, funciones,
--                          requisitos y criterio. Sembradas con contenido real,
--                          extraído de los manuales de rango que Felipe escribió
--                          en 2025 y simplificado para que sea exigible.
--
--   factores_categoria     los SEIS criterios objetivos que separan una
--                          categoría de la siguiente, con el nivel de cada
--                          categoría en cada factor. Esto es el corazón legal:
--                          la Ley 30709 no pide una lista de puestos, pide poder
--                          demostrar que la diferencia salarial responde a algo
--                          objetivo. Los seis salen de los propios manuales y
--                          coinciden con los métodos de valuación de puestos que
--                          usa el mercado.
--
-- POR QUÉ NO HAY ESCALONES DENTRO DE CADA CATEGORÍA
--
-- Se diseñaron (Inicio · Dominio · Maestría, +5 % cada uno) y se descartaron el
-- 2026-08-04, con el número delante. La escala del 29/07 dejó las seis
-- categorías dentro de un rango de S/370, con saltos de 4.2 % a 7.9 % entre
-- ellas. Para que dos escalones cupieran en el salto más chico sin que las
-- categorías se pisaran, cada uno tenía que ser de 2.1 % — S/23 al mes para un
-- Colibrí, que no motiva a nadie. Y con 22 personas, seis categorías ya dan
-- suficiente granularidad: dieciocho puntos salariales en S/370 es maquinaria
-- que nadie va a usar.
--
-- Si algún día la escala se abre, esto se reabre. Queda escrito para no volver
-- a discutirlo desde cero.
--
-- QUÉ ASUME
--
--   · Que 'caylo' deja de existir como categoría. Dos categorías con la misma
--     banda separadas solo por género es exactamente lo que la Ley 30709 vino a
--     corregir: aunque paguen igual, institucionalizan una distinción por sexo
--     en la estructura de puestos. Cayla pasa a ser categoría única y neutra.
--     Los tramos VIGENTES en 'caylo' se mueven a 'cayla' — mismo monto, cero
--     efecto en la planilla. Los tramos ya cerrados NO se tocan: son historia y
--     la historia no se reescribe. El check de asignaciones_salario sigue
--     aceptando 'caylo' a propósito, para que esos tramos sigan siendo válidos.
--
--   · Que el tope de educación por rango ya existe (migración 0132) con los
--     montos 90 · 180 · 270 · 360 · 420 · 480. Esta migración NO los repite:
--     los lee. Repetirlos sería tener la misma cifra en dos sitios y que un día
--     dejaran de coincidir.
--
-- POR QUÉ ASÍ Y NO DE OTRA FORMA
--
--   Las bandas NO se guardan en esta tabla. Se calculan de asignaciones_salario.
--   Una cifra copiada aquí se desactualizaría el día que alguien cambie un
--   salario, y el papel quedaría diciendo algo que la planilla desmiente — que
--   es justo lo primero que busca una inspección.
--
-- NO MUEVE NINGÚN PAGO. Ni un céntimo cambia de lugar.
--
-- CÓMO SE REVIERTE:
--   drop table factores_categoria, categorias_laborales;
--   (los tramos movidos de 'caylo' a 'cayla' quedan; revertirlos a mano si hiciera falta)
-- ============================================================================

-- ── 1 · Las categorías ──────────────────────────────────────────────────────

create table if not exists categorias_laborales (
  rango       text primary key,
  orden       int  not null unique,
  proposito   text,
  funciones   text,
  requisitos  text,
  criterio    text,

  actualizado_por uuid references personas(id),
  actualizado_at  timestamptz not null default now()
);

comment on table categorias_laborales is
  'Cuadro de categorias y funciones que exige la Ley 30709 y el D.S. 002-2018-TR. No tenerlo es infraccion muy grave (25.22 RLGIT); no informarlo, la 25.23.';
comment on column categorias_laborales.proposito is
  'Para que existe la categoria, en una frase. Es lo que abre la conversacion cuando alguien pregunta que se espera de el.';
comment on column categorias_laborales.funciones is
  'Que hace esta categoria. Es lo que permite comparar dos puestos y sostener que valen lo mismo.';
comment on column categorias_laborales.requisitos is
  'Que se necesita para estar en ella. Criterio objetivo que justifica quien entra.';
comment on column categorias_laborales.criterio is
  'Por que esta categoria se remunera por encima de la anterior. La norma no lo nombra asi, pero es lo primero que pregunta una inspeccion.';

-- ── 2 · Los seis factores objetivos ─────────────────────────────────────────
-- Esta es la tabla que sostiene legalmente al resto. Cada fila dice, para una
-- categoría y un factor, qué nivel asume. Leída en fila se ve por qué una
-- categoría vale más que la anterior; leída en columna, qué se espera del nivel.

create table if not exists factores_categoria (
  factor       text not null,
  factor_orden int  not null,
  rango        text not null references categorias_laborales(rango) on delete cascade,
  nivel        text not null,
  primary key (factor, rango)
);

comment on table factores_categoria is
  'Los seis criterios objetivos que separan una categoria de la siguiente. Es lo que la Ley 30709 pide poder demostrar: que la diferencia salarial responde a algo verificable y no a la persona.';

-- ── 3 · Caylo deja de existir ───────────────────────────────────────────────
-- Solo los tramos VIGENTES. Los cerrados son historia y no se reescriben.
do $caylo$
declare v_movidos int;
begin
  update asignaciones_salario
     set rango = 'cayla'
   where rango = 'caylo' and vigente_hasta is null;
  get diagnostics v_movidos = row_count;
  raise notice '0140 · tramos vigentes movidos de caylo a cayla: % (mismo monto, cero efecto en planilla)', v_movidos;
end $caylo$;

-- Y del catálogo de topes de educación, si la 0132 ya está aplicada. Se hace
-- con `if exists` porque esta migración no depende de aquella: si todavía no
-- está pegada, esto no hace nada y no falla.
do $topes$
begin
  if to_regclass('public.topes_educacion_rango') is not null then
    delete from topes_educacion_rango where rango = 'caylo';
    raise notice '0140 · caylo retirado del catalogo de topes de educacion';
  else
    raise notice '0140 · topes_educacion_rango no existe todavia (falta la 0132); caylo se retira cuando se aplique';
  end if;
end $topes$;

-- ── 4 · El contenido ────────────────────────────────────────────────────────
-- Sale de los manuales de rango que Felipe escribió en 2025, simplificado: los
-- manuales pedían métricas que CAYLA hoy no puede medir, y un cuadro que promete
-- lo que no se mide se vuelve prueba en contra. Se conserva la exigencia; se
-- quita lo que no era verificable.

insert into categorias_laborales (rango, orden, proposito, funciones, requisitos, criterio) values

('colibri', 1,
 'Aprender el oficio de CAYLA y ejecutarlo con orden, cuidado y buen trato.',
 E'Ejecuta la apertura y el cierre de su sede o taller según el procedimiento.\n'
 'Atiende a la clienta en lo cotidiano y deriva lo que excede su nivel.\n'
 'Mantiene el orden, la limpieza y la presentación del espacio.\n'
 'Reporta cualquier incidencia a su Support el mismo día.\n'
 'Apoya en campañas y en momentos de alta demanda.\n'
 'Completa las capacitaciones que se le asignan.',
 E'No se exige experiencia previa.\n'
 'Secundaria completa.\n'
 'Disposición a aprender y a seguir procedimientos.',
 'Es la categoría de entrada. Su remuneración es la base sobre la que se construyen las demás y no puede ser inferior a la remuneración mínima vital.'),

('cayla', 2,
 'Sostener la operación del día a día sin que nadie tenga que estar encima.',
 E'Cumple sus metas diarias y semanales sin supervisión directa.\n'
 'Atiende a la clienta de principio a fin, incluida la posventa.\n'
 'Resuelve las situaciones habituales de su puesto sin escalarlas.\n'
 'Acompaña a quien recién entra y le enseña el procedimiento.\n'
 'Cuida el inventario a su cargo y reporta diferencias.\n'
 'Propone mejoras a lo que hace todos los días.',
 E'Al menos seis meses como Colibrí en CAYLA, o experiencia equivalente en otra empresa.\n'
 'Dominio demostrado del procedimiento de su puesto.',
 'Trabaja sin supervisión directa y responde por el resultado de su puesto. El Colibrí trabaja acompañado; la Cayla responde sola.'),

('support', 3,
 'Hacer que un equipo funcione todos los días, y que sus personas crezcan.',
 E'Conduce la reunión corta de inicio de jornada.\n'
 'Organiza turnos, tareas y cobertura de su sede o equipo.\n'
 'Supervisa que el procedimiento se cumpla y corrige en el momento.\n'
 'Es el primer respondedor ante una incidencia, y la registra.\n'
 'Es el puente entre su equipo y la jefatura de su área.\n'
 'Asegura que el equipo tenga lo que necesita para trabajar.\n'
 'Reporta los números de su equipo con la periodicidad acordada.',
 E'Al menos un año como Cayla en CAYLA, o experiencia equivalente conduciendo un equipo pequeño.\n'
 'Capacidad demostrada para dar y recibir retroalimentación.',
 'Responde por el trabajo de otras personas, no solo por el suyo. Ese es el salto: de responder por lo que uno hace a responder por lo que hace un equipo.'),

('aurora', 4,
 'Dirigir un área completa y responder por su resultado.',
 E'Dirige un área o unidad y responde por su resultado económico.\n'
 'Fija los objetivos del periodo y los reparte entre sus Supports.\n'
 'Gestiona el presupuesto de su área.\n'
 'Conduce a los Supports y evalúa su desempeño.\n'
 'Representa a su área ante la Gerencia.\n'
 'Cuida el clima y el desarrollo de las personas de su área.',
 E'Al menos dos años como Support en CAYLA, o experiencia equivalente dirigiendo un área.\n'
 'Manejo de números: presupuesto, márgenes y costos.',
 'Responde por el resultado económico de un área completa y conduce a quienes conducen equipos. Deja de administrar tareas y pasa a administrar un negocio.'),

('oraculo', 5,
 'Traducir hacia dónde va CAYLA en un plan que su dominio pueda ejecutar.',
 E'Traduce la visión de CAYLA en un plan de uno a tres años para su dominio.\n'
 'Responde por el resultado económico de su dominio.\n'
 'Conduce a los Auroras y forma a los siguientes líderes.\n'
 'Participa en las decisiones de dirección de la empresa.\n'
 'Representa a CAYLA ante aliados, proveedores e instituciones.\n'
 'Impulsa proyectos que cambian cómo trabaja la empresa.',
 E'Al menos tres años como Aurora en CAYLA, o experiencia equivalente en dirección.\n'
 'Formación en gestión, o trayectoria que la sustituya.',
 'Decide a plazo de uno a tres años sobre varias áreas a la vez, y forma a los directivos que vienen. Su error o su acierto no se ve este mes.'),

('archicaylo', 6,
 'Responder por CAYLA entera: hacia dónde va, qué es y qué deja.',
 E'Define la visión, la estrategia y la identidad de CAYLA.\n'
 'Decide sobre el portafolio, la inversión y la apertura de sedes.\n'
 'Conduce al equipo directivo.\n'
 'Responde ante la propiedad por el resultado y el patrimonio.\n'
 'Cuida la reputación de la marca y conduce las situaciones críticas.\n'
 'Asegura que existan personas capaces de sucederle.',
 E'Designación de la propiedad.',
 'Responde ante la propiedad por la totalidad de la empresa y por su patrimonio. Es el único nivel donde no hay a quién escalar una decisión.')

on conflict (rango) do nothing;

insert into factores_categoria (factor, factor_orden, rango, nivel) values

('Autonomía', 1, 'colibri',    'Trabaja acompañado y sigue procedimientos establecidos.'),
('Autonomía', 1, 'cayla',      'Trabaja sin supervisión directa dentro de su puesto.'),
('Autonomía', 1, 'support',    'Organiza el trabajo de otras personas y decide en el día a día.'),
('Autonomía', 1, 'aurora',     'Decide sobre su área completa dentro del marco acordado.'),
('Autonomía', 1, 'oraculo',    'Decide sobre su dominio y fija sus prioridades.'),
('Autonomía', 1, 'archicaylo', 'Decide sobre la empresa. No escala decisiones.'),

('Personas a cargo', 2, 'colibri',    'Responde por su propio trabajo.'),
('Personas a cargo', 2, 'cayla',      'Responde por el suyo y acompaña a quien recién entra.'),
('Personas a cargo', 2, 'support',    'Responde por un equipo de sede o de turno.'),
('Personas a cargo', 2, 'aurora',     'Responde por varios equipos, a través de sus Supports.'),
('Personas a cargo', 2, 'oraculo',    'Responde por varias áreas, a través de sus Auroras.'),
('Personas a cargo', 2, 'archicaylo', 'Responde por toda la organización.'),

('Responsabilidad económica', 3, 'colibri',    'Cuida los recursos y los materiales que usa.'),
('Responsabilidad económica', 3, 'cayla',      'Cumple las metas de venta o producción que se le asignan.'),
('Responsabilidad económica', 3, 'support',    'Cumple las metas de su equipo y controla mermas y diferencias.'),
('Responsabilidad económica', 3, 'aurora',     'Responde por el resultado económico de su área y su presupuesto.'),
('Responsabilidad económica', 3, 'oraculo',    'Responde por el resultado de su dominio y por la inversión que pide.'),
('Responsabilidad económica', 3, 'archicaylo', 'Responde por el resultado y el patrimonio de CAYLA.'),

('Horizonte de sus decisiones', 4, 'colibri',    'El día y la semana.'),
('Horizonte de sus decisiones', 4, 'cayla',      'La semana y el mes.'),
('Horizonte de sus decisiones', 4, 'support',    'El mes y el trimestre.'),
('Horizonte de sus decisiones', 4, 'aurora',     'El trimestre y el año.'),
('Horizonte de sus decisiones', 4, 'oraculo',    'De uno a tres años.'),
('Horizonte de sus decisiones', 4, 'archicaylo', 'De tres a nueve años.'),

('Conocimiento requerido', 5, 'colibri',    'Los procedimientos de su puesto y el trato con la clienta.'),
('Conocimiento requerido', 5, 'cayla',      'Su oficio completo, los productos y la posventa.'),
('Conocimiento requerido', 5, 'support',    'Su oficio, el de su equipo, y cómo conducir personas.'),
('Conocimiento requerido', 5, 'aurora',     'Su área, sus números, y cómo dirigir a quienes dirigen.'),
('Conocimiento requerido', 5, 'oraculo',    'Su dominio, el mercado, y cómo construir una estrategia.'),
('Conocimiento requerido', 5, 'archicaylo', 'El negocio entero, el mercado y el entorno en que opera.'),

('Complejidad de lo que resuelve', 6, 'colibri',    'Situaciones previstas, con procedimiento escrito.'),
('Complejidad de lo que resuelve', 6, 'cayla',      'Situaciones habituales para las que no hay procedimiento exacto.'),
('Complejidad de lo que resuelve', 6, 'support',    'Situaciones que su equipo no logró resolver.'),
('Complejidad de lo que resuelve', 6, 'aurora',     'Situaciones sin precedente dentro de su área.'),
('Complejidad de lo que resuelve', 6, 'oraculo',    'Situaciones ambiguas, de alcance amplio y efecto diferido.'),
('Complejidad de lo que resuelve', 6, 'archicaylo', 'Situaciones sin precedente para la empresa.')

on conflict (factor, rango) do nothing;

-- ── 5 · Permisos ────────────────────────────────────────────────────────────

alter table categorias_laborales enable row level security;
alter table factores_categoria   enable row level security;

-- Lectura para CUALQUIER persona autenticada, no solo admin. Es deliberado: la
-- Ley 30709 obliga a INFORMAR el cuadro al trabajador, y un documento que solo
-- la gerencia puede ver no informa a nadie — ese es justo el numeral 25.23.
-- Aquí no hay dato personal de nadie: son categorías y funciones.
drop policy if exists categorias_lectura on categorias_laborales;
create policy categorias_lectura on categorias_laborales
  for select to authenticated using (true);

drop policy if exists factores_lectura on factores_categoria;
create policy factores_lectura on factores_categoria
  for select to authenticated using (true);

-- ── 6 · Escritura por RPC, con rastro ───────────────────────────────────────
-- Este documento se entrega al equipo y se enseña en una inspección: tiene que
-- tener autor y fecha.

create or replace function fn_set_categoria(
  p_rango      text,
  p_proposito  text,
  p_funciones  text,
  p_requisitos text,
  p_criterio   text
)
returns void
language plpgsql volatile security definer set search_path = public
as $fn$
declare v_yo uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede editar el cuadro de categorias.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien hace el cambio, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  update categorias_laborales
     set proposito  = nullif(btrim(coalesce(p_proposito, '')), ''),
         funciones  = nullif(btrim(coalesce(p_funciones, '')), ''),
         requisitos = nullif(btrim(coalesce(p_requisitos, '')), ''),
         criterio   = nullif(btrim(coalesce(p_criterio, '')), ''),
         actualizado_por = v_yo,
         actualizado_at  = now()
   where rango = p_rango;

  if not found then
    raise exception 'Ese rango no existe en el cuadro de categorias.';
  end if;
end;
$fn$;

grant  execute on function fn_set_categoria(text, text, text, text, text) to authenticated;
revoke execute on function fn_set_categoria(text, text, text, text, text) from public, anon;

-- ── 7 · El cuadro completo, listo para pintar ───────────────────────────────
-- Las bandas se CALCULAN de asignaciones_salario y el tope de educación se LEE
-- de topes_educacion_rango. Nada de eso se copia acá: una cifra copiada se
-- desactualiza el día que alguien cambie un salario o un tope, y el papel queda
-- diciendo algo que la planilla desmiente.

create or replace function fn_cuadro_categorias()
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_out jsonb; v_hay_topes boolean;
begin
  -- Sin guard de rol: la ley obliga a informarlo a todo el equipo. Solo trae
  -- categorías, funciones y el rango de sueldos por categoría — nunca cuánto
  -- gana una persona concreta.
  if fn_persona_actual_id() is null then
    raise exception 'Inicia sesion para ver el cuadro de categorias.';
  end if;

  v_hay_topes := to_regclass('public.topes_educacion_rango') is not null;

  select jsonb_build_object(
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rango',       c.rango,
        'orden',       c.orden,
        'proposito',   c.proposito,
        'funciones',   c.funciones,
        'requisitos',  c.requisitos,
        'criterio',    c.criterio,
        'personas',    coalesce(b.n, 0),
        'salario_min', b.minimo,
        'salario_max', b.maximo,
        'tope_educacion', case when v_hay_topes then te.tope else null end,
        'factores', coalesce((
          select jsonb_agg(jsonb_build_object('factor', f.factor, 'nivel', f.nivel)
                           order by f.factor_orden)
          from factores_categoria f where f.rango = c.rango
        ), '[]'::jsonb)
      ) order by c.orden)
      from categorias_laborales c
      left join lateral (
        select count(*)::int as n,
               min(a.salario_mensual_soles) as minimo,
               max(a.salario_mensual_soles) as maximo
        from asignaciones_salario a
        join personas p on p.id = a.persona_id
        where a.rango = c.rango
          and a.vigente_hasta is null
          and p.estado = 'activo'
      ) b on true
      left join lateral (
        select case when v_hay_topes then (
          select t.tope_mensual from topes_educacion_rango t where t.rango = c.rango
        ) end as tope
      ) te on true
    ), '[]'::jsonb),

    -- Las tarifas de movilidad vigentes. Se leen igual que todo lo demás: si
    -- mañana sube el pasaje, el documento lo dice solo.
    --
    -- POR QUÉ `to_jsonb(pl.*)->>'sede_codigo'` Y NO `pl.sede_codigo`. La tarifa
    -- POR SEDE (AQP 10 · TRU 10 · LIM 12) se diseñó en una migración que quedó
    -- huérfana: se escribió como 0130 y ese número lo tomó otra cosa, así que la
    -- columna `sede_codigo` de parametros_laborales NO EXISTE todavía. Nombrarla
    -- directo hace que esta función reviente con «column does not exist» en
    -- cualquier base que no la tenga.
    --
    -- Con `to_jsonb` la columna se busca por nombre en tiempo de ejecución: si
    -- está, sale la sede; si no está, sale null y el documento habla de una
    -- tarifa única. Así esta migración no depende de aquella, y el día que se
    -- aplique la de por sede el documento se parte solo en tres líneas.
    'movilidad', coalesce((
      select jsonb_agg(jsonb_build_object(
               'sede',  to_jsonb(pl.*)->>'sede_codigo',
               'valor', pl.valor)
             order by pl.vigente_desde desc)
      from parametros_laborales pl
      -- fn_hoy_lima() y no la fecha desnuda del servidor: Supabase corre en UTC,
      -- y de 19:00 a medianoche de Lima la fecha de UTC ya es la del dia
      -- siguiente. La prueba 92 del repo falla a proposito si alguna funcion usa
      -- la fecha del servidor sin convertir.
      where pl.clave = 'movilidad_diaria'
        and pl.vigente_desde <= fn_hoy_lima()
        and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima())
    ), '[]'::jsonb),

    -- La proporción entre lo más alto y lo más bajo que se paga hoy. Se calcula
    -- para que el documento no pueda mentir: si mañana se contrata a alguien
    -- caro, la cifra sube sola y la declaración de horizontalidad deja de ser
    -- cierta antes de que nadie tenga que descubrirlo.
    'brecha', (
      select case when min(a.salario_mensual_soles) > 0
                  then round(max(a.salario_mensual_soles) / min(a.salario_mensual_soles), 2)
             end
      from asignaciones_salario a
      join personas p on p.id = a.persona_id
      where a.vigente_hasta is null and p.estado = 'activo'
    )
  ) into v_out;

  return v_out;
end;
$fn$;

grant  execute on function fn_cuadro_categorias() to authenticated;
revoke execute on function fn_cuadro_categorias() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (140, 'el_cuadro_de_categorias')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Verificación ────────────────────────────────────────────────────────────
do $mig$
declare
  v_cats int; v_fact int; v_sin_desc int; v_caylo int; v_huerfanas int;
begin
  select count(*) into v_cats from categorias_laborales;
  select count(*) into v_fact from factores_categoria;
  select count(*) into v_sin_desc from categorias_laborales where funciones is null or criterio is null;
  select count(*) into v_caylo from asignaciones_salario where rango = 'caylo' and vigente_hasta is null;

  if v_cats <> 6 then
    raise exception '0140 · se esperaban 6 categorias y hay %', v_cats;
  end if;
  if v_fact <> 36 then
    raise exception '0140 · se esperaban 36 filas de factores (6 factores x 6 categorias) y hay %', v_fact;
  end if;
  if v_sin_desc > 0 then
    raise exception '0140 · hay % categorias sin funciones o sin criterio; el cuadro no cumpliria la Ley 30709', v_sin_desc;
  end if;
  if v_caylo > 0 then
    raise exception '0140 · quedan % tramos vigentes en caylo', v_caylo;
  end if;

  -- Que cada codigo de categoria EXISTA de verdad en el check de
  -- asignaciones_salario. Sin esto se puede sembrar una categoria con un codigo
  -- inventado: la tabla la acepta, el cuadro la pinta, y su banda sale siempre
  -- vacia porque ningun salario puede apuntar a ella. Paso por aqui: se escribio
  -- 'archicayla' cuando el codigo real es 'archicaylo'.
  select count(*) into v_huerfanas
  from categorias_laborales c
  where not exists (
    select 1 from pg_constraint pc
    where pc.conrelid = 'asignaciones_salario'::regclass
      and pc.contype = 'c'
      and pg_get_constraintdef(pc.oid) ilike '%rango%'
      and pg_get_constraintdef(pc.oid) like '%''' || c.rango || '''%'
  );
  if v_huerfanas > 0 then
    raise exception '0140 · hay % categorias cuyo codigo no acepta asignaciones_salario; su banda saldria vacia para siempre', v_huerfanas;
  end if;

  raise notice '0140 · categorias: 6 (caylo eliminado, cayla es unica y neutra)';
  raise notice '0140 · factores objetivos: 6 x 6 = 36 filas';
  raise notice '0140 · sin escalones: la escala del 29/07 es demasiado compacta para que quepan';
  raise notice '0140 · el cuadro ya cumple el 25.22. Falta informarlo: eso es la 0141.';
end $mig$;
