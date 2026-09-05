-- ============================================================================
-- ¿QUÉ HAY GUARDADO HOY? — solo LEE, no cambia nada. Pégala en el SQL Editor.
-- ============================================================================
--
-- PARA QUÉ. Antes de ponerle un CHECK a una columna hay que saber qué tiene
-- dentro. Un `alter table … add constraint` que choca contra una fila real
-- ABORTA la migración entera, y peor: si se pega a medias deja la tabla en un
-- estado que nadie planeó. La regla del CLAUDE.md es medir contra la base antes
-- de proponer, y esto es esa medición.
--
-- ES UNA SOLA CONSULTA, Y ESO IMPORTA. El SQL Editor de Supabase muestra
-- únicamente el resultado del ÚLTIMO `select`. Varios seguidos se ejecutan y no
-- los ve nadie — una herramienta de diagnóstico que esconde dos tercios de su
-- diagnóstico es peor que no tenerla, porque uno cree que ya miró. (Misma
-- lección que `que_falta_pegar.sql`.)
--
-- NO DEVUELVE NI UN DATO PERSONAL. Cuentas, longitudes y categorías; nunca un
-- correo, un DNI, un número de cuenta ni un nombre. El resultado se puede pegar
-- entero en una conversación sin sacar PII del sistema.
--
-- CÓMO SE LEE. Cada fila dice qué se preguntó y qué se encontró. Las que
-- empiezan por «⚠» son las que impedirían aplicar el candado correspondiente;
-- las demás son para dimensionar la regla, no para alarmarse.
-- ============================================================================

with
-- ── 0 · ¿La 0201 va a entrar limpia? ────────────────────────────────────────
-- La migración lleva esta misma comprobación dentro y aborta sola si falla,
-- pero saberlo ANTES evita pegar algo que se va a revertir.
foto as (
  select
    count(*) as total,
    count(*) filter (
      where total <> pago_base + monto_feriados + monto_plus + asignacion_familiar
                     + monto_movilidad + monto_educacion - descuento_pension
                     + bonos - descuentos
    ) as no_cuadran
  from planilla_pagada_detalle
),

-- ── 1 · Correo ──────────────────────────────────────────────────────────────
correo as (
  select
    count(*) filter (where email is not null)                        as con_correo,
    count(*) filter (where email <> lower(email))                    as con_mayusculas,
    count(*) filter (
      where email is not null
        and email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    )                                                                 as no_pasan_patron
  from personas
),
correo_colision as (
  select coalesce(sum(n - 1), 0) as sobrantes
  from (
    select lower(email) as e, count(*) as n
    from personas where email is not null
    group by 1 having count(*) > 1
  ) x
),

-- ── 2 · Documento ───────────────────────────────────────────────────────────
-- La regla vigente de fn_set_documento (0125) es ^[0-9A-Za-z]{8,12}$. No exige
-- un solo dígito, así que «Rodriguez» pasa — y el comentario de esa función
-- promete literalmente lo contrario.
documento as (
  select
    count(*) filter (where estado = 'activo')                              as personas_activas,
    count(*) filter (where estado = 'activo' and documento is null)        as activas_sin_documento,
    count(*) filter (where documento is not null and documento !~ '[0-9]') as sin_ningun_digito,
    count(*) filter (
      where documento is not null and documento !~ '^[0-9A-Za-z]{8,12}$'
    )                                                                       as fuera_del_patron_vigente,
    count(*) filter (where documento ~ '^0')                                as con_cero_adelante
  from personas
),

-- ── 3 · Cuenta bancaria ─────────────────────────────────────────────────────
-- No se busca un patrón por banco: BCP tiene 14 dígitos, Interbank 13, BBVA 18
-- o 20 y el CCI 20. Una lista por banco es una máquina de falsos positivos. Lo
-- que se mide es si hay letras dentro, que es la basura gruesa.
cuenta as (
  select
    count(*) filter (where numero_cuenta is not null)                   as con_cuenta,
    count(*) filter (where numero_cuenta ~ '[^0-9]')                    as con_algo_que_no_es_digito,
    coalesce(min(length(regexp_replace(numero_cuenta, '[^0-9]', '', 'g')))
             filter (where numero_cuenta is not null), 0)               as digitos_min,
    coalesce(max(length(regexp_replace(numero_cuenta, '[^0-9]', '', 'g')))
             filter (where numero_cuenta is not null), 0)               as digitos_max
  from datos_personales
),

-- ── 4 · CUSPP ───────────────────────────────────────────────────────────────
-- El encabezado de la 0198 decidió que la base guarda el dato sin opinar, y los
-- «12 caracteres» no están sustentados en ningún documento del repositorio. Se
-- mide para saber si esa cifra es cierta antes de escribir cualquier regla.
cuspp as (
  select
    count(*) filter (where cuspp is not null)          as con_cuspp,
    count(*) filter (where cuspp ~ '[^0-9A-Za-z]')     as con_simbolos,
    coalesce(min(length(cuspp)) filter (where cuspp is not null), 0) as largo_min,
    coalesce(max(length(cuspp)) filter (where cuspp is not null), 0) as largo_max
  from datos_personales
),

-- ── 5 · Catálogos ───────────────────────────────────────────────────────────
-- Se devuelven los valores tal cual, sin compararlos con ninguna lista escrita
-- acá: la lista vive en packages/shared/src/enums.ts y copiarla aquí sería la
-- tercera copia. Son categorías, no datos personales.
catalogos as (
  select
    (select coalesce(string_agg(distinct estado_civil, ' · '), '(ninguno)')
       from datos_personales where estado_civil is not null)      as estados_civiles,
    (select coalesce(string_agg(distinct grado_instruccion, ' · '), '(ninguno)')
       from datos_personales where grado_instruccion is not null) as grados
),

-- ── 6 · sede_codigo sin llave foránea ───────────────────────────────────────
sede_huerfana as (
  select count(*) as n
  from parametros_laborales p
  where p.sede_codigo is not null
    and not exists (select 1 from sedes s where s.codigo = p.sede_codigo)
)

select * from (
  select 0 as orden, '0 · LA 0201' as bloque,
         '¿Cuántas fotos del pago hay guardadas?' as pregunta,
         total::text as respuesta from foto
  union all
  select 1, '0 · LA 0201',
         case when no_cuadran = 0 then '¿Alguna NO cuadraría con el candado nuevo?'
              else '⚠ ¿Alguna NO cuadraría con el candado nuevo?' end,
         case when no_cuadran = 0 then 'ninguna — la 0201 entra limpia'
              else no_cuadran::text || ' fila(s): la 0201 abortará sola y sin tocar nada' end
  from foto

  union all
  select 10, '1 · CORREO', 'Personas con correo guardado', con_correo::text from correo
  union all
  select 11, '1 · CORREO',
         case when con_mayusculas = 0 then 'Correos con alguna mayúscula'
              else '⚠ Correos con alguna mayúscula (hay que bajarlos a minúsculas)' end,
         con_mayusculas::text from correo
  union all
  select 12, '1 · CORREO',
         case when sobrantes = 0 then 'Correos que colisionarían al bajar a minúsculas'
              else '⚠ Correos que colisionarían (bloquean el índice lower(email))' end,
         sobrantes::text from correo_colision
  union all
  select 13, '1 · CORREO',
         case when no_pasan_patron = 0 then 'Correos que no pasan el patrón laxo (algo@algo.algo)'
              else '⚠ Correos SIN forma de correo — hoy se guardan igual' end,
         no_pasan_patron::text from correo

  union all
  select 20, '2 · DOCUMENTO', 'Personas activas', personas_activas::text from documento
  union all
  select 21, '2 · DOCUMENTO',
         case when activas_sin_documento = 0 then 'Activas sin documento'
              else 'Activas sin documento (no bloquea: el alta no lo pide)' end,
         activas_sin_documento::text from documento
  union all
  select 22, '2 · DOCUMENTO',
         case when sin_ningun_digito = 0 then 'Documentos sin ni un dígito («Rodriguez» pasa hoy)'
              else '⚠ Documentos sin ni un dígito — son un nombre, no un documento' end,
         sin_ningun_digito::text from documento
  union all
  select 23, '2 · DOCUMENTO',
         case when fuera_del_patron_vigente = 0 then 'Documentos fuera del patrón que ya exige la 0125'
              else '⚠ Documentos que el propio patrón vigente rechazaría' end,
         fuera_del_patron_vigente::text from documento
  union all
  select 24, '2 · DOCUMENTO', 'De ellos, cuántos empiezan en cero (DNI antiguo)',
         con_cero_adelante::text from documento

  union all
  select 30, '3 · CUENTA', 'Fichas con número de cuenta', con_cuenta::text from cuenta
  union all
  select 31, '3 · CUENTA',
         case when con_algo_que_no_es_digito = 0 then 'Cuentas con letras, puntos o guiones dentro'
              else '⚠ Cuentas con algo que no es un dígito — hay que limpiarlas antes del CHECK' end,
         con_algo_que_no_es_digito::text from cuenta
  union all
  select 32, '3 · CUENTA', 'Longitud en dígitos: la más corta y la más larga',
         digitos_min::text || ' … ' || digitos_max::text from cuenta

  union all
  select 40, '4 · CUSPP', 'Fichas con CUSPP', con_cuspp::text from cuspp
  union all
  select 41, '4 · CUSPP', 'Largo del CUSPP: el más corto y el más largo',
         largo_min::text || ' … ' || largo_max::text from cuspp
  union all
  select 42, '4 · CUSPP',
         case when con_simbolos = 0 then 'CUSPP con símbolos raros'
              else '⚠ CUSPP con símbolos raros' end,
         con_simbolos::text from cuspp

  union all
  select 50, '5 · CATÁLOGOS', 'Valores de estado_civil que hay guardados', estados_civiles from catalogos
  union all
  select 51, '5 · CATÁLOGOS', 'Valores de grado_instruccion que hay guardados', grados from catalogos

  union all
  select 60, '6 · SEDES',
         case when n = 0 then 'Filas de parametros_laborales con una sede que no existe'
              else '⚠ Filas con una sede que NO existe (bloquean la llave foránea)' end,
         n::text from sede_huerfana
) x
order by orden;
