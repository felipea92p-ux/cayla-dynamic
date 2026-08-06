-- ============================================================================
-- 0165 — El bono de onomástico rige desde que existe, no hacia atrás
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el tablero deje de reclamar el cargo del bono a quien cumplió años ANTES
--   de que el bono existiera. Decisión de Felipe (2026-08-05): la asignación por
--   onomástico es política nueva, rige desde el 29/07/2026, y a quien ya cumplió
--   este año le toca recién en su cumpleaños de 2027.
--
-- QUÉ ASUME
--   · La 0161 (`fn_documentos_tablero` con las columnas del bono) y la 0162, que
--     es de donde se copia el cuerpo — no de la 0161, que ya no es la vigente.
--   · `parametros_laborales` (0118), versionada por `vigente_desde`.
--
-- EL PROBLEMA QUE ARREGLA, TAL COMO SE VIO EN PANTALLA
--   El 2026-08-05, recién desplegado, el tablero mostraba SEIS personas en rojo:
--   «cumplió en mayo y no hay cargo», «cumplió en marzo y no hay cargo». Ninguna
--   de las seis debía nada. Cuando cumplieron años, este bono no existía: no se
--   les dejó de entregar nada, no hay papel que falte, y no hay pago que
--   acreditar. Era el falso positivo que la 0161 escribió tres párrafos para
--   evitar, colándose por una puerta que no se miró — la 0161 preguntó «¿entró
--   después de su onomástico?» y nunca «¿EXISTÍA EL BONO en su onomástico?».
--
--   Seis acusaciones falsas de golpe en una pantalla recién estrenada es la forma
--   más rápida de que nadie vuelva a creerle a esa columna.
--
-- POR QUÉ LA FECHA VIVE EN `parametros_laborales` Y NO EN LA FUNCIÓN
--   Porque el monto del bono ya tenía que mudarse ahí de todos modos: estaba
--   escrito a mano en la pantalla (`BONO_CUMPLEANOS = 180`), que es exactamente
--   la clase de constante que este repo prohíbe desde que un `SEDES = [...]` se
--   volvió falso al abrir Central. Una sola fila resuelve las dos cosas: `valor`
--   es el monto y `vigente_desde` es la fecha desde la que rige. Y queda
--   versionada, así que el día que el bono suba a S/ 200 se abre una fila nueva
--   y los cargos ya firmados siguen describiendo correctamente su año.
--
-- POR QUÉ NO SE INVENTA UN ESTADO NUEVO
--   Quien cumplió antes del arranque cae en `no_aplica`, el mismo estado de quien
--   entró después de su onomástico. Son el mismo hecho de negocio —«a esta
--   persona no le correspondía nada este año»— y merecen la misma respuesta.
--   Un estado nuevo por cada motivo obliga a la pantalla a tener una rama por
--   cada uno y no le dice nada distinto a quien mira.
--
-- QUÉ NO HACE
--   No condiciona ningún pago y no toca la planilla. El bono no se devenga por
--   este camino: se entrega en mano y se acredita con el cargo firmado.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar el bloque A de la 0162 tal cual, y
--   `delete from parametros_laborales where clave = 'bono_onomastico';`
-- ============================================================================


-- ── A · El bono, con su monto y su fecha de arranque ───────────────────────
-- Idempotente: si ya existe la clave no se toca, para que pegarla dos veces no
-- abra una segunda fila que compita con la primera.
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
select 'bono_onomastico', 180, '2026-07-29',
       'Asignación por onomástico. Monto decidido por Felipe el 2026-07-31 tras '
       'comparar cinco alternativas: igual para todos y sin condición de antigüedad, '
       'porque escalarlo por rango o atarlo al tiempo de servicio lo devuelve a ser '
       'remuneración. La fecha es la del arranque de la política (2026-07-29, la '
       'misma que la movilidad): quien cumplió años antes no tenía este beneficio, '
       'y le corresponde recién en su onomástico de 2027.'
where not exists (
  select 1 from parametros_laborales where clave = 'bono_onomastico'
);


-- ── B · El tablero deja de reclamar lo que no existía ──────────────────────
-- Cuerpo copiado de la 0162, que es la vigente. OJO: `./scripts/donde-vive.sh`
-- responde «0157» para esta función porque la 0161 la redefinió con
-- `drop function` + `create function` y el script solo reconoce
-- `create or replace`. Copiar de la 0157 —lo que el script indica— borraría en
-- silencio las columnas del bono. Es el mismo agujero que la 0162 documentó.
create or replace function fn_documentos_tablero()
returns table (
  persona_id        uuid,
  persona           text,
  sede              text,
  fecha_ingreso     date,
  ruta_id           uuid,
  ruta_firmada_el   date,
  ruta_monto        numeric,
  ruta_negativa     boolean,
  ruta_desfasada    boolean,
  bono_id           uuid,
  bono_anio         integer,
  bono_firmada_el   date,
  bono_mes          integer,
  bono_estado       text,
  estado            text
)
language sql
stable
security definer
set search_path = public
as $$
  with hoy as (
    select fn_hoy_lima()                             as dia,
           extract(year  from fn_hoy_lima())::int    as anio,
           extract(month from fn_hoy_lima())::int    as mes,
           -- El último día calendario de este mes. Se calcula acá y no en el
           -- `where` para que el corte sea UNO solo en toda la consulta.
           (date_trunc('month', fn_hoy_lima()) + interval '1 month - 1 day')::date
                                                     as fin_de_mes,
           -- CAMBIO 0165 · desde cuándo existe el bono. Si la fila no está, cae a
           -- una fecha remota: sin parámetro, el tablero se comporta como antes
           -- de esta migración en vez de dejar a todos en gris. Un valor que
           -- falta no puede apagar un aviso por su cuenta.
           coalesce(
             (select min(vigente_desde) from parametros_laborales
               where clave = 'bono_onomastico' and valor > 0),
             '1900-01-01'::date)                     as bono_desde
  ),
  ruta as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.fecha_firma, d.monto_declarado, d.es_negativa
    from documentos_firmados d
    where d.tipo = 'ruta' and d.anulado_at is null
    order by d.persona_id, d.fecha_firma desc, d.created_at desc
  ),
  bono as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.anio, d.fecha_firma
    from documentos_firmados d, hoy
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = hoy.anio
    order by d.persona_id, d.fecha_firma desc
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    r.id, r.fecha_firma, r.monto_declarado, coalesce(r.es_negativa, false),
    -- La tarifa es POR SEDE desde la 0142, así que se compara contra la de SU
    -- sede: compararla contra el máximo marcaría como desfasadas todas las de
    -- TRU y AQP el día que LIM tenga otra cifra.
    (r.monto_declarado is not null
      and tar.valor is not null
      and r.monto_declarado <> tar.valor),
    b.id, b.anio, b.fecha_firma,
    dp.mes_nacimiento,
    case
      when b.id is not null            then 'ok'
      when dp.mes_nacimiento is null   then 'sin_fecha'
      -- CAMBIO 0165 · su onomástico de este año cayó antes de que el bono
      -- existiera. No se le dejó de entregar nada: le toca recién el año que
      -- viene. Va ANTES de la comparación de meses, porque si no esa misma
      -- persona caería en 'vencido' y saldría acusada.
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', hoy.bono_desde)::date then 'no_aplica'
      -- Entró después de su onomástico: tampoco había nada que entregarle.
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', p.fecha_ingreso)::date then 'no_aplica'
      when dp.mes_nacimiento = hoy.mes then 'este_mes'
      when dp.mes_nacimiento <  hoy.mes then 'vencido'
      else                                  'proximo'
    end,
    case
      when r.id is null                    then 'sin_ruta'
      when coalesce(r.es_negativa, false)  then 'se_nego'
      else 'ok'
    end
  from personas p
  cross join hoy
  left join sedes s on s.id = p.sede_base_id
  left join ruta r on r.persona_id = p.id
  left join bono b on b.persona_id = p.id
  -- Solo el MES sale de la ficha personal: la fecha de nacimiento completa es
  -- dato sensible y esta consulta la ve una pantalla.
  left join lateral (
    select extract(month from d.fecha_nacimiento)::int as mes_nacimiento
    from datos_personales d
    where d.persona_id = p.id and d.fecha_nacimiento is not null
  ) dp on true
  left join lateral (
    select pl.valor
    from parametros_laborales pl
    where pl.clave = 'movilidad_diaria'
      and pl.vigente_desde <= hoy.dia
      and (pl.vigente_hasta is null or pl.vigente_hasta >= hoy.dia)
      and (pl.sede_codigo = s.codigo or pl.sede_codigo is null)
    order by (pl.sede_codigo is null), pl.vigente_desde desc
    limit 1
  ) tar on true
  where p.estado = 'activo'
    and p.en_planilla
    and fn_es_admin_o_lider() is true
    -- Quien firma por CAYLA no se pide el papel a sí mismo (0162).
    and p.id is distinct from (
      select (c.valor->>'persona_id')::uuid
      from configuracion c
      where c.clave = 'firmante_empresa'
    )
    -- Y quien termina contrato este mes o antes (0162).
    and (p.fecha_fin_contrato is null or p.fecha_fin_contrato > hoy.fin_de_mes)
  order by (r.id is not null), p.apellidos;
$$;

grant execute on function fn_documentos_tablero() to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (165, 'el_bono_de_onomastico_rige_desde_que_existe')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_desde date;
  v_monto numeric;
begin
  select min(vigente_desde), min(valor) into v_desde, v_monto
  from parametros_laborales where clave = 'bono_onomastico';

  raise notice '0165 · el bono de onomastico rige desde % y vale S/ %', v_desde, v_monto;
  raise notice '0165 · quien cumplio anios antes de esa fecha ya NO aparece en rojo: le toca en 2027';
  raise notice '0165 · ningun pago cambia.';
end $mig$;
