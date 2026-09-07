-- ============================================================================
-- 0387 · El tablero de documentos desempata la ruta
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `fn_documentos_tablero` elija SIEMPRE el mismo documento de ruta como
--   «el que vale» para una persona, aunque dos de sus documentos empaten en
--   `fecha_firma` y en `created_at`. Es la hermana de la 0386, que hizo lo
--   mismo con `fn_contratos_tablero`, y por el mismo motivo.
--
--     ruta, antes:  order by d.persona_id, d.fecha_firma desc, d.created_at desc
--     ruta, ahora:  order by d.persona_id, d.fecha_firma desc, d.created_at desc,
--                            d.id desc
--
--     bono, antes:  order by d.persona_id, d.fecha_firma desc
--     bono, ahora:  order by d.persona_id, d.fecha_firma desc, d.created_at desc,
--                            d.id desc
--
--   Nada más cambia. Mismas columnas, mismos estados, mismo orden de salida.
--
-- QUÉ ASUME
--
--   Que la 0165 es la versión vigente de `fn_documentos_tablero` — comprobado
--   con `./scripts/donde-vive.sh fn_documentos_tablero` (4 versiones repartidas:
--   0157, 0161, 0162, 0165) y con `git grep` sobre todas las ramas. El cuerpo de
--   abajo es el de la 0165 íntegro, con esas dos líneas cambiadas y marcadas
--   CAMBIO 0387.
--
--   md5 de partida, PEDIDO A PRODUCCIÓN en el SQL Editor (2026-09-07):
--     MD5_PENDIENTE
--
-- POR QUÉ ACÁ EL EMPATE PESA MÁS QUE EN LA 0386
--
--   `documentos_firmados.created_at` es `default now()`, y `now()` dentro de una
--   misma transacción vale LO MISMO para todas las filas. Y `fecha_firma` es una
--   DATE: dos documentos de ruta de la misma persona firmados el mismo día ya
--   empatan en el primer criterio. Sin un tercer criterio, cuál gana lo decide
--   el orden físico de la tabla.
--
--   La fila que gana decide `estado`, y ese estado distingue dos cosas que no se
--   parecen en nada:
--
--     'ok'       → firmó el pacto individual de movilidad.
--     'se_nego'  → se le ofreció y NO firmó.
--
--   Y esa diferencia no es de pantalla. Sin pacto individual firmado, el monto
--   de movilidad NO es no remunerativo; pagarlo igual es exactamente lo que la
--   RTF 05449-4-2007 sanciona — está escrito en el comentario de
--   `documentos_firmados.es_negativa` desde la 0157. Un tablero que contesta
--   'ok' donde el expediente dice que se negó apaga el único aviso que hay.
--
--   Medido con la prueba 307, contra el Postgres local, ANTES de esta migración:
--   dos personas con el mismo expediente —una ruta firmada y una negativa, las
--   dos del 02/03/2026— contestan al revés una de la otra según el orden en que
--   se guardaron los papeles. Una dice 'ok', la otra dice 'se_nego'.
--
-- POR QUÉ NO CAMBIA NADA EN PRODUCCIÓN
--
--   El criterio nuevo va DESPUÉS de `created_at desc`, así que solo puede
--   desempatar filas cuyo `created_at` sea idéntico al microsegundo. Eso hoy no
--   ocurre en producción: cada documento entra por su propia llamada a
--   `fn_documento_registrar` desde `apps/web/app/(admin)/admin/documentacion/`,
--   y cada RPC es su propia transacción — es la única función de todo el
--   esquema que inserta en esta tabla, y lo hace de a una fila.
--
--   Eso es lo que vuelve segura esta migración, y es deliberado: se agrega un
--   ancla determinista (`id desc`), NO un criterio de negocio. Decidir «entre
--   una firma y una negativa del mismo día manda la negativa» sería inventar
--   política laboral en un `order by`, y esa decisión no es de una migración.
--   El `id` es un uuid: no significa nada, y por eso no dice nada que no
--   corresponda — solo garantiza que la respuesta no cambie sola.
--
-- POR QUÉ EL CTE `bono` TAMBIÉN, SI ESE NUNCA EMPATÓ
--
--   `bono` tenía un `order by` todavía más corto —sin `created_at` siquiera— y
--   aun así nunca pudo empatar: el índice parcial único
--   `idx_documentos_bono_uno_por_anio` sobre (persona_id, anio) filtrado por
--   `tipo='bono' and anulado_at is null and not es_negativa` hace imposible que
--   haya dos candidatos, y el CTE filtra exactamente por esas condiciones más
--   `anio = hoy.anio`.
--
--   Se le pone igual, por dos razones. La primera es que su determinismo
--   dependía de un invariante que vive en OTRO objeto: el día que alguien
--   estreche ese índice, esta consulta se vuelve no determinista en silencio y
--   nadie relaciona las dos cosas. La segunda es que dos `distinct on` dentro
--   de la MISMA función no pueden tener disciplinas de orden distintas — una de
--   las dos está mal, y no es la que desempata.
--
--   Y como es inalcanzable, cuesta cero: no puede cambiar ninguna fila. Lo que
--   sostiene esa rama sigue siendo el índice, no el `order by`; la prueba 307 lo
--   deja fijado con un `throws_ok` para que ese índice no se pueda quitar sin
--   que algo se ponga rojo.
--
-- QUÉ NO TOCA, Y POR QUÉ
--
--   La misma forma —`order by … <columna now()> desc limit 1`, sin ancla— vive
--   todavía en cinco funciones más: `fn_contratos_listar`,
--   `fn_documentos_estado_politica`, `fn_documentos_listar`,
--   `fn_educacion_espejo_comprobante` y `fn_expediente_generar_falta`. Ninguna
--   se toca acá: meterlas mezclaría seis cambios en una migración que se pega a
--   mano, y ninguna de ellas decide hoy un estado que alimente el pago. Quedan
--   anotadas, no olvidadas.
--
-- CÓMO SE REVIERTE
--   Correr de nuevo el cuerpo de `fn_documentos_tablero` tal como quedó en
--   `supabase/migrations/0165_el_bono_de_onomastico_rige_desde_que_existe.sql`.
--   No hay datos que deshacer: esta migración no escribe ninguna fila.
-- ============================================================================

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
    -- ⇩⇩⇩ CAMBIO 0387 ⇩⇩⇩ `created_at` es `now()`, que dentro de una misma
    -- transacción vale lo mismo para todas las filas, y `fecha_firma` es una
    -- DATE: dos rutas firmadas el mismo día empatan en los dos criterios. Sin
    -- un tercero, quién ganaba lo decidía el orden físico de la tabla — y esa
    -- fila decide si `estado` dice 'ok' o 'se_nego', que es la diferencia entre
    -- «firmó el pacto de movilidad» y «se negó a firmarlo».
    -- `id desc` es un ANCLA, no un criterio de negocio: es un uuid, no
    -- significa nada. Decidir aquí quién manda entre una firma y una negativa
    -- del mismo día sería inventar política laboral en un `order by`.
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
  ),
  bono as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.anio, d.fecha_firma
    from documentos_firmados d, hoy
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = hoy.anio
    -- ⇩⇩⇩ CAMBIO 0387 ⇩⇩⇩ Este nunca empató, y no por su `order by`: el índice
    -- parcial único `idx_documentos_bono_uno_por_anio` (persona_id, anio) sobre
    -- las mismas condiciones que filtra este CTE hace imposible que haya dos
    -- candidatos. Se le pone el mismo desempate igual, porque depender de un
    -- invariante que vive en OTRO objeto significa que estrechar ese índice
    -- rompe esta consulta en silencio — y porque dos `distinct on` de la misma
    -- función no pueden tener disciplinas de orden distintas. Es inalcanzable,
    -- así que no puede cambiar ninguna fila. Lo que sostiene esta rama sigue
    -- siendo el índice; la prueba 307 lo deja fijado.
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
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

comment on function fn_documentos_tablero() is
  'Que documento de movilidad o bono de onomastico le falta a cada quien '
  '(0157/0161/0162/0165/0387). El documento de ruta que vale se elige con '
  'desempate explicito (0387): fecha_firma, created_at y por ultimo el id como '
  'ancla determinista. Sin ese ancla, dos rutas del mismo dia guardadas en la '
  'misma transaccion empataban y el ganador lo decidia el orden fisico de la '
  'tabla — y esa fila decide si el estado dice ok o se_nego, que no es lo mismo: '
  'sin pacto individual firmado el monto de movilidad no es no remunerativo.';

insert into migraciones_aplicadas (numero, nombre)
values (387, 'el_tablero_de_documentos_desempata_la_ruta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0387 · fn_documentos_tablero desempata el documento de ruta que vale, igual que la 0386 en fn_contratos_tablero. No cambia ninguna fila.';
end $mig$;
