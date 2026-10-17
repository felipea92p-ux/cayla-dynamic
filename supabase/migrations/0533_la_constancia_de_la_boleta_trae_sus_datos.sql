-- ============================================================================
-- 0533 — La constancia de una boleta firmada trae sus propios datos
-- ============================================================================
--
-- ── QUÉ PROMETE ──────────────────────────────────────────────────────────────
--
-- Una función nueva, `fn_boleta_datos_de_constancia(version)`, que devuelve lo
-- que la hoja «Constancia de recepción de boleta de pago» dice de la persona:
-- su nombre, el nombre tal como figura en su DNI, su documento, su sede, su
-- cargo y la FECHA DE PAGO de ese periodo para su grupo (planilla o RxH).
--
-- La hoja junta en un solo papel la boleta, esos datos y, debajo, la firma que
-- la persona copió al firmarla (0532). DO la ve y la descarga desde el tablero;
-- desde esta migración la persona también, desde «Lo mío» → Boletas.
--
-- Solo LEE. No cambia ninguna tabla ni reescribe ninguna función.
--
-- ── QUÉ ASUME ────────────────────────────────────────────────────────────────
--
--  · La 0482 (boletas y sus versiones), la 0323 (`periodo_grupo_pago`) y la
--    0061 (`datos_personales`).
--  · `fn_es_admin_o_lider()` es «DO» (0078) y `fn_persona_actual_id()` dice
--    quién llama.
--
-- ── POR QUÉ ASÍ, Y NO DE OTRA FORMA ──────────────────────────────────────────
--
--  · LA PERSONA NO PUEDE LEER LA FECHA DE PAGO DE SU GRUPO. `periodo_grupo_pago`
--    solo la lee DO (0323), y la fecha que sí ve todo el mundo,
--    `periodos_planilla.pagado_at` (0234), NO es la suya: se escribe cuando se
--    paga el ÚLTIMO grupo del periodo. Con planilla pagada el 30 y RxH el 5, la
--    hoja de una persona de planilla diría «pagado el 5». En un papel que se
--    entrega, una fecha falsa es peor que ninguna. Por eso la fecha sale de
--    aquí, por grupo, igual que la calculan `fn_boletas_tablero` y
--    `fn_mis_boletas` (grupo = `tipo_vinculo`).
--
--  · QUIÉN LA VE ES EXACTAMENTE QUIÉN VE LA FIRMA: DO, cualquiera; la persona,
--    solo la de su boleta publicada; nadie más —tampoco la líder de equipo—. Es
--    la misma condición de `fn_boleta_constancia` (0532), copiada y no
--    inventada: la hoja muestra las dos cosas juntas, y no puede pasar que una
--    se vea y la otra no.
--
--  · UNA SOLA FUNCIÓN PARA LAS DOS PANTALLAS. DO leía estos datos con tres
--    consultas sueltas desde el navegador; la persona no puede hacer esas tres
--    (la tercera es la fecha de pago). Si cada pantalla armara la hoja por su
--    cuenta, «qué dice la constancia de Ana» tendría dos respuestas. Ahora las
--    dos preguntan aquí.
--
--  · DEVUELVE UNA FILA O NINGUNA, y nunca inventa: un dato que no está
--    registrado (sin DNI, sin nombre del DNI, grupo sin pagar) vuelve en NULL y
--    la hoja dice «—» o «Sin registrar».
--
-- ── LO QUE ESTO NO ES ────────────────────────────────────────────────────────
--
--  No le abre a la persona `periodo_grupo_pago` ni `datos_personales` de nadie:
--  devuelve SUS datos y la fecha de SU grupo, y solo para una boleta suya ya
--  publicada.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--
--     drop function if exists fn_boleta_datos_de_constancia(uuid);
--
--  Sin ella, la hoja se sigue viendo y descargando, pero sin DNI, sin sede y
--  sin fecha de pago, con un aviso de que no se pudieron leer.
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================


-- ── 0 · EL FRENO ─────────────────────────────────────────────────────────────
do $freno$
begin
  if to_regclass('public.boletas_versiones') is null then
    raise exception 'FALTA LA 0482. Las tablas de boletas no existen; pégala antes que esta.';
  end if;
  if to_regclass('public.periodo_grupo_pago') is null then
    raise exception 'FALTA LA 0323. periodo_grupo_pago no existe; pégala antes que esta.';
  end if;
  -- Otra función con este nombre y OTROS argumentos haría convivir dos puertas
  -- para la misma pregunta (el accidente de la 0297 y la 0299). Se para.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'fn_boleta_datos_de_constancia'
                and pg_get_function_identity_arguments(p.oid) <> 'p_version_id uuid') then
    raise exception 'PARA. Ya existe otra fn_boleta_datos_de_constancia con otros argumentos: corre ./scripts/donde-vive.sh fn_boleta_datos_de_constancia.';
  end if;
end
$freno$;


-- ── 1 · Los datos de la hoja ─────────────────────────────────────────────────
create or replace function fn_boleta_datos_de_constancia(p_version_id uuid)
returns table (
  nombre text, nombre_dni text, documento text, tipo_documento text,
  sede_codigo text, cargo text, pagado_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_yo      uuid := fn_persona_actual_id();
  v_persona uuid;
  v_periodo uuid;
  v_estado  text;
begin
  select b.persona_id, b.periodo_id, b.estado into v_persona, v_periodo, v_estado
    from boletas_versiones v join boletas b on b.id = v.boleta_id
   where v.id = p_version_id;
  if not found then
    raise exception 'Esa boleta no existe.';
  end if;
  -- La misma condición que fn_boleta_constancia (0532): quien ve la firma ve esto.
  if fn_es_admin_o_lider() is not true
     and not (v_yo is not null and v_persona = v_yo and v_estado = 'publicada') then
    raise exception 'Esa boleta no está disponible.';
  end if;

  return query
  select btrim(pe.nombres || ' ' || pe.apellidos),
         nullif(btrim(dp.nombre_dni), ''),
         nullif(btrim(pe.documento), ''),
         nullif(btrim(pe.tipo_documento), ''),
         s.codigo,
         pe.cargo,
         -- La de SU grupo, no la del periodo: ver «POR QUÉ ASÍ».
         (select g.pagado_at from periodo_grupo_pago g
           where g.periodo_id = v_periodo and g.grupo = pe.tipo_vinculo and g.estado = 'pagado')
    from personas pe
    left join sedes s on s.id = pe.sede_base_id
    left join datos_personales dp on dp.persona_id = pe.id
   where pe.id = v_persona;
end;
$fn$;

comment on function fn_boleta_datos_de_constancia(uuid) is
  'Lo que la constancia de una boleta firmada dice de la persona: nombre, nombre del DNI, documento, sede, cargo y la fecha de pago de SU grupo en ese periodo. La ve quien ve la firma (fn_boleta_constancia): DO, o la persona sobre su boleta publicada. 0533.';

revoke all on function fn_boleta_datos_de_constancia(uuid) from public, anon;
grant execute on function fn_boleta_datos_de_constancia(uuid) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (533, 'la_constancia_de_la_boleta_trae_sus_datos')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────────
-- Una función, que puede llamar quien inició sesión y nadie más; el registro
-- tiene que ser el de esta migración (si dice otro nombre, alguien más tenía el 533).
select
  (select count(*) from pg_proc where proname = 'fn_boleta_datos_de_constancia') as funcion_de_1,
  (select has_function_privilege('authenticated', 'fn_boleta_datos_de_constancia(uuid)', 'EXECUTE')) as la_llama_quien_inicio_sesion,
  (select not has_function_privilege('anon', 'fn_boleta_datos_de_constancia(uuid)', 'EXECUTE')) as no_la_llama_anon,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 533) as registro;
