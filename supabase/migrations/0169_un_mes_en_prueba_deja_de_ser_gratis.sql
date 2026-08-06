-- ============================================================================
-- 0169 — Un mes en «prueba» deja de ser gratis, y el sistema lo dice
-- ============================================================================
--
-- QUÉ PROMETE
--   Que nadie se quede en el vínculo `prueba` más de un mes sin que alguien se
--   entere. Pasado ese mes, la etiqueta empieza a costar dinero real y hoy no
--   hay nada que lo señale.
--
-- QUÉ ASUME
--   La decisión de Felipe del 2026-07-26, registrada en la cabecera de la 0085:
--   `prueba` NO devenga beneficios. Esta migración **no la revierte** — la hace
--   visible cuando deja de ser inocua.
--
-- POR QUÉ HACE FALTA, Y POR QUÉ RECIÉN AHORA
--   La 0085 dejó escrito el argumento legal completo: en la ley peruana el
--   periodo de prueba no es un vínculo distinto, es un contrato de trabajo
--   común, y quien presta servicios va a planilla desde el primer día. Se le
--   informó a Felipe y decidió que `prueba` no devengara, con este razonamiento
--   textual: «que por los mínimos legales casi siempre daría cero de todas
--   formas».
--
--   Ese «casi siempre» es la clave, y tiene una fecha de caducidad exacta. Las
--   tres funciones de truncas —CTS, gratificación y vacaciones— exigen **un mes
--   de servicios** por su cuenta: por debajo de eso devuelven cero devengue o no
--   devengue el vínculo. O sea que la decisión no costaba nada mientras «prueba»
--   significara unos días.
--
--   El 2026-08-05 se vio el caso que rompe el supuesto: una persona llevaba diez
--   días como `prueba` y seguía trabajando. Al cumplir el mes, el sistema
--   empezaría a decir que no devenga algo que legalmente sí devenga — y nadie se
--   enteraría hasta que cesara y su liquidación saliera en cero.
--
-- POR QUÉ UN AVISO Y NO UN CAMBIO DE REGLA
--   Cambiar `fn_devenga_beneficios` es una línea, pero revierte una decisión que
--   Felipe tomó informado y con su fecha. El sistema no revierte decisiones de
--   negocio por su cuenta: las hace visibles cuando cambian los hechos que las
--   sostenían. La decisión de qué hacer —pasar a planilla, cesar y recontratar, o
--   cambiar la regla— sigue siendo suya, y ahora la toma a tiempo.
--
-- POR QUÉ MIDE DESDE `fecha_ingreso` Y NO DESDE EL PRIMER MARCAJE
--   La antigüedad corre con el contrato, no con la asistencia: alguien ausente
--   con permiso sigue acumulando. Medirlo por marcajes diría que el reloj se
--   detiene cuando alguien falta, y no se detiene.
--
-- CÓMO SE REVIERTE
--   drop function fn_avisos_vinculo();  No hay cambio de esquema ni de datos, y
--   ninguna otra función depende de ella.
-- ============================================================================


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
        'Lleva más de un mes como «prueba». Desde el '
        || to_char((p.fecha_ingreso + interval '1 month')::date, 'DD/MM/YYYY')
        || ' devenga CTS, gratificación y vacaciones que el sistema NO está calculando, '
        || 'porque el vínculo «prueba» no devenga (decisión del 26/07/2026). '
        || 'Pásala a «planilla» en Equipo, o revisa si corresponde registrar su cese.'
      else
        'Cumple un mes el '
        || to_char((p.fecha_ingreso + interval '1 month')::date, 'DD/MM/YYYY')
        || '. Hasta entonces la etiqueta «prueba» no le quita nada: las truncas '
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
  'Quién sigue en el vínculo «prueba» y desde cuándo. La decisión de que «prueba» '
  'no devengue beneficios (0085, 26/07/2026) se tomó porque por debajo de un mes '
  'las truncas dan cero igual. Pasado el mes deja de ser cierto, y esto lo dice.';

grant execute on function fn_avisos_vinculo() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (169, 'un_mes_en_prueba_deja_de_ser_gratis')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare r record;
begin
  for r in select * from fn_avisos_vinculo() loop
    if r.ya_devenga then
      raise warning '0169 · % lleva % dias como prueba: YA devenga beneficios que no se calculan.', r.persona, r.dias;
    else
      raise notice '0169 · % lleva % dias como prueba (cumple el mes el %).', r.persona, r.dias, r.cumple_el_mes;
    end if;
  end loop;
end $mig$;
