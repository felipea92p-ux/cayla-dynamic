-- ============================================================================
-- 0560 · EL AVISO DE «LLEVA MÁS DE UN MES» DICE «PRESELECCIÓN»
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_avisos_vinculo()` (0169) —la que alimenta el cartel rojo de Liquidaciones
--   cuando alguien lleva más de un mes en el vínculo `prueba`— deja de decir
--   «prueba» en el texto que ve DO y pasa a decir «preselección»:
--     «Lleva más de un mes como «preselección». …porque el vínculo «preselección»
--      no devenga…»   /   «…la etiqueta «preselección» no le quita nada…»
--   Es lo único: las mismas columnas, los mismos filtros, la misma cuenta de
--   días. El valor interno del vínculo sigue siendo `prueba`.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-27)
--   «Todas las pantallas que digan algo acerca de los de prueba serán
--   preselección.» El título del cartel ya está en el código; el cuerpo lo escribe
--   esta función, así que sin esto el cartel diría las dos palabras a la vez.
--
-- QUÉ ASUME — y la guardia que lo comprueba
--   Que producción tiene EXACTAMENTE la `fn_avisos_vinculo` de la 0169 (es la única
--   migración que la define). La guardia compara el md5 del cuerpo y se NIEGA a
--   reemplazar cualquier otra versión: reescribirla desde acá borraría el cambio de
--   quien la tocó después. Acepta el cuerpo tal cual y el que deja pegar desde
--   Windows (un \r por línea, mismo código):
--       tal cual ............ 036e01d3446dcb467d213bba23426536  (1 223 caracteres)
--       \r\n tal cual ....... 663b3d976d2fd30678009a06db5ad4ba
--   (El cuerpo no tiene comentarios, así que la variante «sin comentarios» es la misma.)
--   Si la guardia frena, pide el md5 a PRODUCCIÓN:
--       select md5(prosrc), length(prosrc) from pg_proc
--        where proname = 'fn_avisos_vinculo' and pronamespace = 'public'::regnamespace;
--   y dime lo que devuelve: esta migración se reconstruye desde la versión vigente.
--
-- QUÉ NO HACE
--   · NO TOCA LA PLANILLA ni ninguna función de pago. Es un texto que lee DO.
--   · NO CAMBIA a quién avisa: mismas personas, mismos días.
--
-- CÓMO SE REVIERTE
--   Pegar de nuevo el cuerpo de `0169_un_mes_en_prueba_deja_de_ser_gratis.sql`
--   (solo la sección `create or replace function fn_avisos_vinculo`).
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 451.
-- ============================================================================

-- ── Guardia: solo sobre la versión de la 0169 ───────────────────────────────
do $guardia$
declare
  v_n   integer;
  v_src text;
begin
  select count(*) into v_n from pg_proc
   where proname = 'fn_avisos_vinculo' and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then
    raise exception 'PARA. fn_avisos_vinculo tiene % versiones (se esperaba 1): reemplazarla a ciegas crearía una sobrecarga o pisaría un cambio. Reconstruye desde la vigente con donde-vive.sh.', v_n;
  end if;

  select prosrc into v_src from pg_proc
   where proname = 'fn_avisos_vinculo' and pronamespace = 'public'::regnamespace;

  -- Ya pegada: repegar es seguro.
  if position('preselección' in v_src) > 0 then
    return;
  end if;

  if md5(v_src) not in ('036e01d3446dcb467d213bba23426536', '663b3d976d2fd30678009a06db5ad4ba') then
    raise exception 'PARA. fn_avisos_vinculo de esta base no es la de la 0169 (md5 %, % caracteres). Reemplazarla desde acá revertiría en silencio lo que se hizo después. Pide el md5 a producción y reconstruye desde la vigente.',
      md5(v_src), length(v_src);
  end if;
end
$guardia$;

-- ── La función: el mismo cuerpo de la 0169, con las palabras nuevas ─────────
create or replace function fn_avisos_vinculo()
returns table (
  persona_id    uuid,
  persona       text,
  sede          text,
  tipo_vinculo  text,
  fecha_ingreso date,
  dias          int,
  cumple_el_mes date,
  ya_devenga    boolean,
  aviso         text
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
    p.tipo_vinculo,
    p.fecha_ingreso,
    (fn_hoy_lima() - p.fecha_ingreso)::int,
    (p.fecha_ingreso + interval '1 month')::date,
    (fn_hoy_lima() >= (p.fecha_ingreso + interval '1 month')::date),
    case
      when fn_hoy_lima() >= (p.fecha_ingreso + interval '1 month')::date then
        'Lleva más de un mes como «preselección». Desde el '
        || to_char((p.fecha_ingreso + interval '1 month')::date, 'DD/MM/YYYY')
        || ' devenga CTS, gratificación y vacaciones que el sistema NO está calculando, '
        || 'porque el vínculo «preselección» no devenga (decisión del 26/07/2026). '
        || 'Pásala a «planilla» en Equipo, o revisa si corresponde registrar su cese.'
      else
        'Cumple un mes el '
        || to_char((p.fecha_ingreso + interval '1 month')::date, 'DD/MM/YYYY')
        || '. Hasta entonces la etiqueta «preselección» no le quita nada: las truncas '
        || 'exigen un mes de servicios de todas formas.'
    end
  from personas p
  left join sedes s on s.id = p.sede_base_id
  where p.estado = 'activo'
    and p.tipo_vinculo = 'prueba'
    and fn_es_admin_o_lider() is true
  order by p.fecha_ingreso;
$$;

comment on function fn_avisos_vinculo() is
  'Quién sigue en el vínculo «prueba» (en pantalla: «preselección») y desde cuándo. La decisión de que no '
  'devengue beneficios (0085, 26/07/2026) se tomó porque por debajo de un mes '
  'las truncas dan cero igual. Pasado el mes deja de ser cierto, y esto lo dice.';

grant execute on function fn_avisos_vinculo() to authenticated;

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (560, 'el_aviso_de_un_mes_dice_preseleccion')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: true · true · «560 · el_aviso_de_un_mes_dice_preseleccion»
select
  (select prosrc like '%«preselección»%' and prosrc not like '%«prueba»%'
     from pg_proc where proname = 'fn_avisos_vinculo' and pronamespace = 'public'::regnamespace) as el_texto_dice_preseleccion,
  (select prosecdef from pg_proc
    where proname = 'fn_avisos_vinculo' and pronamespace = 'public'::regnamespace)               as sigue_security_definer,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 560)               as registro;
