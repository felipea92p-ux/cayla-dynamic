-- ============================================================================
-- 0539 · EL TERMINAL SABE QUIÉN ESTÁ DE PRUEBA
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `terminal_roster` —la lista que pinta el kiosco de marcaje de cada sede— traiga,
--   para quien está de prueba, en qué día va: `prueba_dias` (los que ya trabajó) y
--   `prueba_plazo` (cuántos dura la prueba). Para todo el resto de la gente las dos
--   columnas son NULL. Con eso el terminal puede mostrar «Prueba · 2 de 3» junto a la
--   foto, que es lo que pidió Felipe (2026-10-19): «debe aparecer en el terminal para
--   que marque, con una etiqueta de prueba y los días de prueba».
--
-- QUÉ ASUME
--   · La 0536 pegada (`pruebas`, `fn_prueba_dias_trabajados`, `fn_prueba_dias_plazo`; esta última con
--     `execute` para `authenticated`, que es como la dejó la 0536).
--   · `terminal_roster` es la de la 0490: seis columnas
--     `id, nombres, apellidos, foto_url, sede_codigo, sede_nombre`, `security_invoker =
--     false` y su sede delegada en `fn_persona_marca_en_sede` (0382). Se COMPRUEBA abajo
--     y la migración se niega a entrar si no: esta vista ya se ha pisado tres veces
--     (0370 → 0375 → 0381 → 0382) por reescribirla desde un cuerpo viejo.
--
-- QUÉ NO HACE
--   · No cambia a quién ofrece el roster: ni una persona entra ni sale. Agrega DOS
--     columnas al final, que `create or replace view` permite sin tocar permisos.
--   · No le da al terminal lectura de `pruebas` ni de `jornadas`, y entrega SOLO dos
--     números. Ojo con una trampa que la prueba 432 encontró: una vista lee SUS TABLAS con
--     los permisos de su dueño, pero ejecuta las FUNCIONES con los de quien consulta. Si la
--     vista llamara a `fn_prueba_dias_trabajados`, el terminal necesitaría poder ejecutarla
--     —y con ella contar las jornadas de cualquier persona por su id—. Por eso la vista llama a
--     `fn_terminal_prueba_dias`, que solo contesta por la gente de la sede de ESE terminal;
--     `fn_prueba_dias_trabajados` sigue cerrada para él.
--   · No muestra el resultado de ninguna decisión ni que alguien «se retiró»: quien ya
--     no está activo ni aparece en el roster.
--   · No decide nada: es una etiqueta que avisa. Marcar sigue sin pedir nada más.
--
-- POR QUÉ UNA COLUMNA EN LA VISTA Y NO UNA FUNCIÓN APARTE
--   El roster se guarda en el dispositivo (IndexedDB) para marcar sin red. Una
--   segunda consulta tendría su propia caché y su propio momento de fallar, y el terminal
--   mostraría una persona sin su etiqueta justo cuando no hay conexión. En la misma fila,
--   viaja y se cachea junta.
--
-- QUÉ SE ROMPE SI
--   Alguien pega esta migración antes que la 0536 (la guardia lo frena), o redefine la
--   vista desde un cuerpo anterior a la 0490 (se llevaría `not p.cuenta_de_servicio` y
--   las estaciones de caja volverían a ofrecerse para marcar).
--
-- CÓMO SE REVIERTE
--   Volver a pegar el bloque `create or replace view terminal_roster` de la 0490 NO
--   funciona (`create or replace` no quita columnas): hace falta `drop view
--   terminal_roster;` y luego ese bloque, con su `revoke`/`grant`; después
--   `drop function fn_terminal_prueba_dias(uuid);`. El terminal dejaría de
--   recibir las dos columnas y el kiosco simplemente no pintaría la etiqueta.
-- ============================================================================

do $guardia$
declare
  v_vista oid := to_regclass('public.terminal_roster');
  v_cols  text;
  v_opts  text;
begin
  if to_regclass('public.pruebas') is null or to_regprocedure('fn_prueba_dias_trabajados(uuid, date, date)') is null then
    raise exception 'PARA. Falta la 0536: no existen pruebas ni fn_prueba_dias_trabajados. Pega primero la 0536.';
  end if;
  if v_vista is null then
    raise exception 'PARA. La vista terminal_roster no existe. Esta migración la reescribe; falta la 0382.';
  end if;

  select string_agg(attname, ',' order by attnum) into v_cols
    from pg_attribute where attrelid = v_vista and attnum > 0 and not attisdropped;
  if v_cols = 'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre,prueba_dias,prueba_plazo' then
    return;   -- ya pegada: repegar es seguro
  end if;
  if v_cols <> 'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre' then
    raise exception using
      message = 'PARA. terminal_roster no tiene las seis columnas de la 0490. Tiene: ' || v_cols || '.',
      hint    = 'Alguien la cambió después. Pegar esto la reemplazaría, y es la que pinta el '
             || 'roster de las Mac mini. Corre ./scripts/donde-vive.sh terminal_roster.';
  end if;

  select array_to_string(reloptions, ',') into v_opts from pg_class where oid = v_vista;
  if coalesce(v_opts, '') not like '%security_invoker=false%' then
    raise exception 'PARA. terminal_roster ya no es security_invoker = false (%). Revísalo antes.',
      coalesce(v_opts, '(ninguna)');
  end if;
  if position('fn_persona_marca_en_sede' in pg_get_viewdef(v_vista, true)) = 0 then
    raise exception 'PARA. terminal_roster ya no delega la sede en fn_persona_marca_en_sede (0382). Revísalo antes.';
  end if;
  if position('cuenta_de_servicio' in pg_get_viewdef(v_vista, true)) = 0 then
    raise exception 'PARA. terminal_roster ya no excluye las cuentas de servicio (0490). Pegar esto las volvería a ofrecer para marcar.';
  end if;
end
$guardia$;

-- La única pregunta que el terminal puede hacerle a las jornadas: «¿cuántos días de prueba lleva
-- ESTA persona?», y solo por quien ofrece su propio roster. Cualquier otra, NULL.
create or replace function fn_terminal_prueba_dias(p_persona_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
           when p.tipo_vinculo = 'prueba' and p.estado = 'activo'
            and fn_sede_actual_terminal() is not null
            and fn_persona_marca_en_sede(p.id, fn_sede_actual_terminal())
           then fn_prueba_dias_trabajados(p.id, coalesce(pr.inicio, p.fecha_ingreso))
         end
    from personas p
    left join pruebas pr on pr.persona_id = p.id and pr.resultado = 'en_curso'
   where p.id = p_persona_id;
$$;

revoke execute on function fn_terminal_prueba_dias(uuid) from public, anon;
grant  execute on function fn_terminal_prueba_dias(uuid) to authenticated;

comment on function fn_terminal_prueba_dias(uuid) is
  'Cuántos días de prueba lleva una persona, SOLO si está de prueba y su sede es la del terminal que pregunta (0539). '
  'Para cualquier otra persona o sesión, NULL. Existe para que terminal_roster pueda traer el número sin darle al terminal '
  'permiso de ejecutar fn_prueba_dias_trabajados, que cuenta las jornadas de cualquiera.';

-- El cuerpo es EXACTAMENTE el de la 0490; solo se agregan las dos columnas al final.
create or replace view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  p.foto_url,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre,
  -- CAMBIO 0539 · cuántos días de prueba lleva, o NULL si no está de prueba. Si la fila de la
  -- prueba no existe (el trigger de la 0536 nunca frena un cambio de vínculo), cuenta desde su ingreso.
  fn_terminal_prueba_dias(p.id) as prueba_dias,
  case when p.tipo_vinculo = 'prueba' then fn_prueba_dias_plazo() end as prueba_plazo
from personas p
join sedes s on s.id = p.sede_base_id
where p.estado = 'activo'
  and not p.cuenta_de_servicio   -- CAMBIO 0490: una estación de retail no marca asistencia
  and fn_sede_actual_terminal() is not null
  and fn_persona_marca_en_sede(p.id, fn_sede_actual_terminal());

comment on view terminal_roster is
  'Lo unico que el kiosco de marcaje necesita ver de una persona: como se llama, su foto (0381), de '
  'que sede es y, si esta de prueba, en que dia va (0539). Existe porque RLS filtra filas y no columnas, asi que mientras el terminal leyera '
  '`personas` su token alcanzaba el DNI y la remuneracion (0285). Desde la 0375 tampoco lleva '
  '`pin_hash`: el terminal ya no pide PIN. Desde la 0382 su condicion de sede la responde '
  'fn_persona_marca_en_sede, la misma que usan el disparador de escritura y '
  'fn_persona_en_roster_terminal. Desde la 0490 no ofrece cuentas de servicio (estaciones de retail).';

revoke all    on terminal_roster from public, anon;
grant  select on terminal_roster to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (539, 'el_terminal_sabe_quien_esta_de_prueba')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────
select
  (select string_agg(attname, ',' order by attnum) from pg_attribute
    where attrelid = 'public.terminal_roster'::regclass and attnum > 0 and not attisdropped)
  = 'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre,prueba_dias,prueba_plazo'   as ocho_columnas,
  has_table_privilege('authenticated', 'public.terminal_roster', 'select')             as el_terminal_la_lee,
  not has_table_privilege('anon', 'public.terminal_roster', 'select')                  as sin_sesion_no;
