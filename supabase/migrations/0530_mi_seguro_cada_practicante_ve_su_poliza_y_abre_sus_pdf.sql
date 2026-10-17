-- ============================================================================
-- 0530 · «Mi seguro»: cada practicante ve SU póliza y abre sus PDF (etapa 2)
-- ============================================================================
-- QUÉ PROMETE
--
--   Que una practicante vea, en «Lo mío», su propia póliza FOLA —número,
--   aseguradora, hasta cuándo la cubre, y el PDF de su póliza y de su convenio de
--   pago— sin que por eso pueda ver NADA de las otras: ni la póliza de otra
--   practicante, ni el papeleo de DO, ni las facturas.
--
--   Dos cosas lo sostienen, y las dos tienen que decir lo mismo:
--     · `fn_mi_seguro()`: devuelve SOLO las pólizas de quien llama, y de cada una
--       lo que una practicante necesita saber, nada más.
--     · una política de lectura en Storage (`polizas_seguro_select_propia`): el
--       PDF solo se abre si es de la póliza de quien lo pide.
--   La prueba 423 las compara archivo por archivo: lo que la función le muestra a
--   una practicante es EXACTAMENTE lo que Storage le deja abrir.
--
--   Es la ETAPA 2. La etapa 1 (0528) es de DO y no se toca: sus cuatro políticas
--   de Storage y `fn_seguro_archivo_libre` quedan como están; aquí se AGREGA una.
--
-- QUÉ ASUME
--
--   · La 0528 está pegada: las tres tablas de pólizas, el bucket `polizas-seguro` y
--     sus cuatro políticas. Si no lo está, esta migración se detiene antes de
--     tocar nada (ver el primer bloque) en vez de dejar funciones que fallarían
--     recién al abrir la pantalla.
--   · `fn_persona_actual_id()` resuelve la ficha de quien inició sesión
--     (`personas.auth_user_id`), `fn_hoy_lima()` da el día de Lima, y una practicante
--     es `personas.tipo_vinculo = 'practicante'`.
--   · Que DO sube a cada póliza SOLO el PDF de esa persona. La base no puede
--     comprobarlo: un PDF que juntara las pólizas de las cuatro se lo mostraría
--     completo a cada una. Está dicho en docs/estado.md y en la pantalla de DO.
--
-- QUÉ VE LA PRACTICANTE, Y QUÉ NO (decidido con Felipe, 2026-10-17)
--
--   VE:    el número, la aseguradora, la vigencia, si cubre hoy, el plan y los
--          beneficios máximos (vacíos mientras el corredor no los confirme), y
--          los archivos de tipo `poliza` y `convenio_pago` que no estén retirados.
--   NO VE: la prima, cuándo vence su pago ni si está pagada; si está firmada o si
--          llegó la factura; la nota de DO; quién la registró y cuándo; el
--          historial; si renueva sola; el nombre con que DO subió cada archivo;
--          las facturas ni los archivos «otro»; las pólizas anuladas.
--
--   El nombre del archivo no sale a propósito: lo escribe DO al subirlo y puede
--   llevar nombres de personas. La pantalla rotula cada archivo por su tipo
--   («Tu póliza», «Convenio de pago»), no por lo que alguien escribió.
--
-- LO QUE DECIDÍ, Y LO QUE DESCARTÉ
--
--   DECIDÍ:    «SOLO PRACTICANTES» TAMBIÉN AQUÍ, no solo en la pantalla. FOLA es
--              exclusiva de ellos (Felipe, 2026-10-17) y quien deja de serlo ya no
--              ve la sección. Las dos puertas —la función y la política— piden
--              `tipo_vinculo = 'practicante'` AHORA, no cuando se registró la
--              póliza. Lo que cuesta: una practicante que pasa a planilla pierde
--              el acceso a su PDF (DO se lo puede dar). Lo que evita: dos reglas
--              de quién ve la sección, una en la pantalla y otra aquí.
--   DECIDÍ:    «CUBRE HOY» LO DICE LA BASE, con el mismo cálculo del tablero de DO
--              (`vigente_hasta` EXCLUSIVO, día de Lima). Lo que la practicante lee
--              y lo que lee DO sale de la misma cuenta; recalcularlo en el
--              navegador daría dos respuestas a «¿tengo seguro hoy?».
--   DECIDÍ:    «AL DÍA» ES QUE LA PÓLIZA ESTÁ VIGENTE, no que la prima esté pagada.
--              La cobertura puede suspenderse por mora (convenio de pago, cláusula
--              quinta), pero decirle a una practicante «tu seguro está suspendido»
--              por una marca que DO todavía no hizo es una falsa alarma sobre su
--              salud, y la mora ya sale en rojo en la Bandeja de DO. Si Felipe
--              prefiere que la practicante lo vea, se agrega una columna.
--   DECIDÍ:    `plan` y los beneficios máximos se devuelven tal cual y la pantalla
--              los calla mientras sean null. «Sin confirmar» no es un dato que
--              mostrar: el convenio ya promete 14 y 30 subvenciones, y una cifra
--              equivocada es peor que ninguna.
--   DECIDÍ:    UNA función de ayuda para Storage (`fn_seguro_archivo_es_mio`). Las
--              tablas de pólizas solo las lee DO, así que una consulta metida
--              dentro de la política vería cero filas para una practicante. Es el
--              molde de `fn_boleta_puede_ver` (0482).
--   DESCARTÉ:  Una segunda función para los archivos. La lista viaja dentro de cada
--              fila (`archivos`, jsonb) y la pantalla hace una sola llamada.
--   DESCARTÉ:  Dejar que la practicante vea todos los archivos de su póliza. La
--              factura es papel de DO y el contador; «otro» es un cajón de DO.
--
-- QUÉ NO HACE
--
--   · No deja escribir nada. La practicante no sube, retira ni marca: la política es
--     solo de lectura y `fn_mi_seguro` solo lee.
--   · No avisa a la practicante de nada ni toca la Bandeja.
--   · No toca el seguro del resto del equipo ni lee planilla.
--   · Ninguna función existente se reescribe → no hay md5 de partida.
--
-- SE ROMPE SI
--
--   · Se agrega un tipo de archivo nuevo a `polizas_seguro_archivos.tipo` esperando
--     que la practicante lo vea: no lo verá, porque la lista de los dos tipos vive
--     en `fn_mi_seguro` Y en `fn_seguro_archivo_es_mio`. La prueba 423 compara las
--     dos y fallaría en `db-tests` si una cambia sin la otra.
--   · Alguien quita el «solo practicantes» para dar seguro a todo el equipo. Hay
--     que revisar las dos puertas, no una.
--   · Cambia la lista de columnas de `fn_mi_seguro`: `create or replace` no deja
--     cambiar lo que devuelve (hay que `drop function` primero) y hay que volver a
--     generar los tipos. La prueba 423 fija la lista exacta, a propósito: una
--     columna nueva es una decisión de qué ve una persona, no un descuido.
--
-- ANTES DE PEGAR — UNA CONSULTA DE SOLO LECTURA A PRODUCCIÓN (SQL Editor)
--   Esperado: la 0528 presente (3 tablas, `fn_seguro_archivo_libre`, las 4
--   políticas de DO), y NADA de esta migración todavía.
--
--   select
--     (select count(*) from information_schema.tables
--       where table_schema = 'public'
--         and table_name in ('polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos'))
--                                                                    as tablas_0528_de_3,
--     (select count(*) from pg_proc where proname = 'fn_seguro_archivo_libre') as apoyo_0528_de_1,
--     (select count(*) from pg_policies where schemaname = 'storage'
--         and policyname in ('polizas_seguro_insert','polizas_seguro_select',
--                            'polizas_seguro_update','polizas_seguro_delete')) as politicas_0528_de_4,
--     (select count(*) from pg_proc
--       where proname in ('fn_mi_seguro','fn_seguro_archivo_es_mio'))   as funciones_que_ya_existen,
--     (select count(*) from pg_policies where schemaname = 'storage'
--         and policyname = 'polizas_seguro_select_propia')              as politica_que_ya_existe,
--     (select string_agg(numero || ' · ' || nombre, ' | ' order by numero) from migraciones_aplicadas
--       where numero between 528 and 531)                               as registro_528_a_531;
--
-- CÓMO SE REVIERTE (esta primero y luego la 0528, nunca al revés: la política y las
-- funciones de aquí leen las tablas de allá)
--   begin;
--   drop policy if exists polizas_seguro_select_propia on storage.objects;
--   drop function if exists fn_mi_seguro();
--   drop function if exists fn_seguro_archivo_es_mio(text);
--   delete from migraciones_aplicadas where numero = 530;
--   commit;
--   Nada de planilla, asistencia ni pago lee esto: revertir solo esconde la sección
--   «Mi seguro» (la pantalla muestra «no se pudo cargar»). No se pierde ningún dato.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final, que va la última porque el SQL Editor solo muestra el
--   resultado de la última. Y la prueba 423 en `db-tests`.
-- ============================================================================


-- ── 0 · Esta migración cuelga de la 0528 ─────────────────────────────────────
-- Las funciones de PL/pgSQL no comprueban sus tablas al crearse: sin este bloque,
-- pegar la 0530 sin la 0528 "funcionaría" y fallaría recién cuando una practicante
-- abra la sección. Se detiene antes de tocar nada.
do $guarda$
begin
  if to_regclass('public.polizas_seguro') is null
     or to_regclass('public.polizas_seguro_archivos') is null
     or to_regprocedure('public.fn_seguro_archivo_libre(text)') is null then
    raise exception 'La 0530 necesita la 0528 (las pólizas de seguro de los practicantes) y no está pegada. Pega primero la 0528.';
  end if;
end
$guarda$;


-- ── 1 · Quién puede abrir qué archivo (Storage) ──────────────────────────────
-- Un archivo es «mío» si: está en una póliza MÍA que no se anuló, es de un tipo que
-- la practicante ve (póliza o convenio de pago), no está retirado, y yo soy hoy una
-- practicante. SECURITY DEFINER porque las tablas son de DO. Nunca devuelve null:
-- `exists (…)` es true o false, y sin sesión o sin ficha `fn_persona_actual_id()` es
-- null, así que la comparación no encuentra nada.
--
-- Los dos tipos están escritos AQUÍ y en `fn_mi_seguro`. Si uno cambia, el otro
-- también: la prueba 423 compara las dos lecturas archivo por archivo.
create or replace function fn_seguro_archivo_es_mio(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select fn_persona_actual_id() is not null
     and exists (
       select 1
         from polizas_seguro_archivos a
         join polizas_seguro z on z.id = a.poliza_id
         join personas p on p.id = z.persona_id
        where a.storage_path = p_path
          and a.tipo in ('poliza', 'convenio_pago')
          and a.retirado_at is null
          and z.anulada_at is null
          and z.persona_id = fn_persona_actual_id()
          and p.tipo_vinculo = 'practicante'
     );
$fn$;

-- Las políticas se evalúan con el privilegio de quien lee, así que `authenticated`
-- tiene que poder llamarla. Nadie más.
grant execute on function fn_seguro_archivo_es_mio(text) to authenticated;
revoke execute on function fn_seguro_archivo_es_mio(text) from public, anon;

-- UNA política, de lectura. Se suma a `polizas_seguro_select` (la de DO): las
-- políticas permisivas del mismo tipo se suman con OR, así que DO sigue viendo todo
-- y una practicante ve solo lo suyo. No hay política de insert, update ni delete
-- para ella: no sube ni toca nada.
drop policy if exists polizas_seguro_select_propia on storage.objects;
create policy polizas_seguro_select_propia on storage.objects
  for select to authenticated
  using (bucket_id = 'polizas-seguro' and fn_seguro_archivo_es_mio(name));


-- ── 2 · Lo que ve «Mi seguro» ────────────────────────────────────────────────
-- Una fila por póliza viva (no anulada) de quien llama, la más reciente primero. Si
-- quien llama no es una practicante, o no tiene ficha, devuelve vacío: no es un error
-- (la pantalla ya dice qué hacer cuando no hay nada).
--
-- `archivos` es un arreglo json, siempre un arreglo (vacío si no hay), con
-- {id, tipo, storage_path, mime, bytes}, la póliza antes que el convenio de pago y
-- dentro de cada tipo el más nuevo primero. Sin el nombre con que se subió.
create or replace function fn_mi_seguro()
returns table (
  poliza_id            uuid,
  aseguradora          text,
  numero_poliza        text,
  vigente_desde        date,
  vigente_hasta        date,
  cubre_hoy            boolean,
  plan                 text,
  beneficio_enfermedad numeric,
  beneficio_accidente  numeric,
  archivos             jsonb
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_yo  uuid := fn_persona_actual_id();
  v_hoy date := fn_hoy_lima();
begin
  if v_yo is null then
    return;
  end if;
  -- `is not true` y no `not`: sin ficha el subselect no devuelve nada (null) y eso
  -- no puede pasar como «es practicante».
  if (select p.tipo_vinculo = 'practicante' from personas p where p.id = v_yo) is not true then
    return;
  end if;

  return query
  select z.id, z.aseguradora, z.numero_poliza, z.vigente_desde, z.vigente_hasta,
         -- El mismo cálculo que `fn_seguros_tablero` (0528): el día final NO cubre.
         (v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta),
         z.plan, z.beneficio_enfermedad, z.beneficio_accidente,
         coalesce((
           select jsonb_agg(
                    jsonb_build_object('id', a.id, 'tipo', a.tipo, 'storage_path', a.storage_path,
                                       'mime', a.mime, 'bytes', a.bytes)
                    order by case a.tipo when 'poliza' then 0 else 1 end, a.subido_at desc, a.id desc)
             from polizas_seguro_archivos a
            where a.poliza_id = z.id
              and a.tipo in ('poliza', 'convenio_pago')
              and a.retirado_at is null
         ), '[]'::jsonb)
    from polizas_seguro z
   where z.persona_id = v_yo
     and z.anulada_at is null
   -- `z.id desc` como ancla: dos pólizas con la misma fecha de inicio no empatan al
   -- azar (lección de la 0312/0389).
   order by z.vigente_desde desc, z.id desc;
end;
$fn$;

grant execute on function fn_mi_seguro() to authenticated;
revoke execute on function fn_mi_seguro() from public, anon;


-- ── Registro ─────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (530, 'mi_seguro_cada_practicante_ve_su_poliza_y_abre_sus_pdf')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname in ('fn_mi_seguro', 'fn_seguro_archivo_es_mio')) as funciones_de_2,
  (select count(*) from pg_policies where schemaname = 'storage'
      and policyname = 'polizas_seguro_select_propia' and cmd = 'SELECT')                       as politica_de_lectura_de_1,
  (select count(*) from pg_policies where schemaname = 'storage'
      and policyname like 'polizas\_seguro\_%')                                                  as politicas_storage_de_5,
  has_function_privilege('authenticated', 'fn_mi_seguro()', 'execute')                          as authenticated_la_llama,
  has_function_privilege('anon', 'fn_mi_seguro()', 'execute')                                   as anon_no_deberia,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 530)              as registro;
