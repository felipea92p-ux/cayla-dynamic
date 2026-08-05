-- ============================================================================
-- 0145 — La escala que publica el cuadro es la declarada, y solo cuenta planilla
-- ============================================================================
--
-- QUÉ PROMETE
--   · Que la columna «Remuneración» del cuadro de categorías muestre el monto
--     que la empresa DECLARA para cada categoría —uno por categoría— y no el
--     sueldo real de quien hoy esté en ella.
--   · Que «Personas hoy» y la brecha entre el sueldo más alto y el más bajo
--     cuenten únicamente a quien está en planilla.
--
-- QUÉ ASUME
--   · `categorias_laborales` (0140) tiene las seis categorías con su orden.
--   · `personas.tipo_vinculo` distingue 'planilla', 'prueba', 'rxh' y
--     'no_trabajador' (0119). Acá se cuenta SOLO 'planilla'.
--
-- ── EL ERROR QUE CORRIGE, Y CÓMO SE VEÍA ────────────────────────────────────
--
-- La versión de la 0140 armaba la remuneración de cada categoría con el mínimo
-- y el máximo de los sueldos vigentes, filtrando solo por `p.estado = 'activo'`.
-- Un locador está activo, así que su honorario entraba al cálculo como si fuera
-- una remuneración de planilla. En producción eso produjo un documento legal que
-- decía, textualmente:
--
--     Aurora       S/ 1360.00 a S/ 1800.00      3 personas
--     Oráculo      S/ 1800.00                   1 persona
--     ArchiCayla   S/ 1500.00                   1 persona
--
-- O sea: la categoría MÁS ALTA publicada por debajo de la anterior, y 25
-- personas contadas donde hay 22 activas. Un cuadro de categorías que se
-- contradice a sí mismo es peor que no tenerlo: la Ley 30709 pide criterios
-- objetivos, y ese documento probaba por escrito que no los había.
--
-- ── POR QUÉ LA ESCALA SE DECLARA Y NO SE DEDUCE ─────────────────────────────
--
-- Deducir la escala de los sueldos reales invierte la relación: el cuadro debe
-- decir cuánto vale cada categoría, y los contratos ajustarse a él. Al revés, un
-- solo sueldo negociado por encima de su categoría reescribe la política de la
-- empresa sin que nadie lo decida — que es exactamente lo que pasó.
--
-- Por eso el monto vive en una columna de `categorias_laborales`: la tabla que
-- ya existe, ya tiene el orden y ya se publica. No se crea una tabla versionada
-- aparte porque el historial ya lo guarda el documento congelado al publicarse
-- (0141): cada versión publicada conserva su escala con su fecha, que es
-- justamente lo que hay que poder mostrarle a una inspección.
--
-- ── POR QUÉ 'planilla' ESTRICTO Y NO `en_planilla` ──────────────────────────
--
-- `en_planilla` es una columna generada que incluye 'prueba'. Para movilidad y
-- EsSalud eso es correcto: quien está en periodo de prueba los devenga. Para
-- este cuadro, decisión de Felipe (2026-08-04): se cuentan solo los puestos
-- consolidados. Una persona en prueba todavía no define el tamaño de una
-- categoría.
--
-- CÓMO SE REVIERTE
--   alter table categorias_laborales drop column salario_declarado;
--   y volver a aplicar el bloque de fn_cuadro_categorias de la 0140.
-- ============================================================================

-- ── 1 · El monto declarado de cada categoría ────────────────────────────────
alter table categorias_laborales
  add column if not exists salario_declarado numeric(10,2);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'categorias_laborales_salario_declarado_positivo'
  ) then
    alter table categorias_laborales
      add constraint categorias_laborales_salario_declarado_positivo
      check (salario_declarado is null or salario_declarado > 0);
  end if;
end $$;

comment on column categorias_laborales.salario_declarado is
  'Lo que la empresa declara que vale esta categoria. Es LA POLITICA: lo que se publica en el cuadro de la Ley 30709 y lo que se aplica a nuevas incorporaciones y cambios de categoria. No se deduce de los sueldos vigentes, porque un sueldo negociado por encima de su categoria reescribiria la politica sin que nadie lo decida.';

-- Los seis montos acordados el 2026-08-04. Idempotente: se pega a mano.
update categorias_laborales set salario_declarado = v.monto
  from (values
    ('colibri',    1130.00),
    ('cayla',      1185.00),
    ('support',    1260.00),
    ('aurora',     1360.00),
    ('oraculo',    1440.00),
    ('archicaylo', 1500.00)
  ) as v(rango, monto)
 where categorias_laborales.rango = v.rango
   and categorias_laborales.salario_declarado is distinct from v.monto;

-- La escala tiene que subir con la categoría. No se pone como CHECK —decisión
-- de Felipe: el sistema avisa en pantalla y no bloquea la carga—, pero sí se
-- comprueba al aplicar, que es cuando hay alguien mirando.
do $$
declare v_mal int;
begin
  select count(*) into v_mal
  from categorias_laborales a
  join categorias_laborales b on b.orden = a.orden + 1
  where a.salario_declarado is not null
    and b.salario_declarado is not null
    and b.salario_declarado <= a.salario_declarado;

  if v_mal > 0 then
    raise warning '0145 · ATENCION: % categoria(s) valen igual o menos que la anterior. El cuadro va a mostrar el aviso.', v_mal;
  else
    raise notice '0145 · la escala sube con la categoria: 1130 - 1185 - 1260 - 1360 - 1440 - 1500';
  end if;
end $$;

-- ── 2 · El cuadro, leyendo la escala declarada y contando solo planilla ─────
create or replace function fn_cuadro_categorias()
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_out jsonb; v_hay_topes boolean;
begin
  -- Sin guard de rol: la ley obliga a informarlo a todo el equipo. Solo trae
  -- categorías, funciones y el monto declarado por categoría — nunca cuánto
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
        -- Lo que se publica. Sale de la política, no de los contratos.
        'salario_declarado', c.salario_declarado,
        -- Se siguen trayendo para la pantalla de administracion (permiten ver
        -- si alguien quedó por debajo del monto declarado de su categoría),
        -- pero YA NO son lo que el documento publica.
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
          -- LA CORRECCIÓN. Un locador está activo y tiene rango, pero su
          -- honorario no es una remuneración: contarlo inflaba la categoría y
          -- desordenaba la escala publicada.
          and p.tipo_vinculo = 'planilla'
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
    -- POR QUÉ `to_jsonb(pl.*)->>'sede_codigo'` Y NO `pl.sede_codigo`: la columna
    -- puede no existir todavía en una base que no aplicó la tarifa por sede.
    -- Buscada por nombre en tiempo de ejecución, ausente devuelve null y el
    -- documento habla de una tarifa única en vez de reventar.
    'movilidad', coalesce((
      select jsonb_agg(jsonb_build_object(
               'sede',  to_jsonb(pl.*)->>'sede_codigo',
               'valor', pl.valor)
             order by pl.vigente_desde desc)
      from parametros_laborales pl
      where pl.clave = 'movilidad_diaria'
        and pl.vigente_desde <= fn_hoy_lima()
        and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima())
    ), '[]'::jsonb),

    -- La proporción entre lo más alto y lo más bajo que se paga hoy. Mismo
    -- filtro que arriba, y por la misma razón: un honorario alto de un locador
    -- hacía que el documento declarara una desigualdad que no existe entre
    -- las remuneraciones de la empresa.
    'brecha', (
      select case when min(a.salario_mensual_soles) > 0
                  then round(max(a.salario_mensual_soles) / min(a.salario_mensual_soles), 2)
             end
      from asignaciones_salario a
      join personas p on p.id = a.persona_id
      where a.vigente_hasta is null
        and p.estado = 'activo'
        and p.tipo_vinculo = 'planilla'
    )
  ) into v_out;

  return v_out;
end;
$fn$;

grant  execute on function fn_cuadro_categorias() to authenticated;
revoke execute on function fn_cuadro_categorias() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (145, 'la_escala_declarada_y_solo_planilla')
on conflict (numero) do nothing;
