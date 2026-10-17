-- ============================================================================
-- 0530 · «Mi seguro»: cada colaborador ve en qué seguro está y abre sus propias pólizas
-- ============================================================================
-- QUÉ PROMETE
--
--   Que cada colaborador vea, en «Lo mío», SU seguro: en cuál está hoy y, si ese seguro
--   lleva póliza, la póliza —número, aseguradora, hasta cuándo es vigente— y el PDF de su
--   póliza y de su convenio de pago, para abrir o descargar. Sin que por eso pueda ver
--   NADA de las demás personas: ni su seguro, ni su póliza, ni sus PDF.
--
--   Tres piezas, y las tres tienen que decir lo mismo:
--     · `fn_mi_seguro()`      en qué seguro PRINCIPAL está hoy (FOLA, EsSalud, el que DO le
--                             haya asignado…) y, si lleva póliza, si alguna lo cubre hoy.
--     · `fn_mis_polizas()`    sus pólizas, de cualquier seguro, con sus PDF.
--     · `polizas_seguro_select_propia`   una política de lectura en Storage: el PDF solo
--                             se abre si es de una póliza suya. Con su función de apoyo,
--                             `fn_seguro_archivo_es_mio`.
--   La prueba 423 las compara archivo por archivo: lo que `fn_mis_polizas` le muestra a
--   alguien es EXACTAMENTE lo que Storage le deja abrir.
--
--   Es la ETAPA 2 de los seguros. La etapa 1 (0528: los tipos, las asignaciones, las
--   pólizas y los cambios) es de DO y no se toca: sus cuatro políticas de Storage y
--   `fn_seguro_archivo_libre` quedan como están; aquí se AGREGA una.
--
-- QUÉ ASUME
--
--   · La 0528 está pegada: las seis tablas de seguros, `fn_seguro_tipo_principal` y el
--     bucket `polizas-seguro` con sus cuatro políticas. Si no lo está, esta migración se
--     detiene antes de tocar nada (primer bloque) en vez de dejar funciones que
--     fallarían recién cuando alguien abra la sección.
--   · `fn_persona_actual_id()` resuelve la ficha de quien inició sesión
--     (`personas.auth_user_id`) y `fn_hoy_lima()` da el día de Lima.
--   · Que DO sube a cada póliza SOLO el PDF de esa persona. La base no puede
--     comprobarlo: un PDF que juntara las pólizas de varias se lo mostraría completo a
--     cada una. La pantalla de DO lo dice al subir.
--
-- QUÉ VE LA PERSONA, Y QUÉ NO (decidido con Felipe, 2026-10-17)
--
--   VE:    el nombre de su seguro principal y si lleva póliza; de cada póliza suya —del
--          seguro que sea, vigente o no— el nombre del seguro, el número, la aseguradora,
--          la vigencia, si cubre hoy, el plan y los beneficios máximos (vacíos mientras el
--          corredor no los confirme), y sus archivos de tipo `poliza` y `convenio_pago`
--          que no estén retirados.
--   NO VE: la descripción del seguro ni los textos de alta y baja (DO los edita desde la
--          pantalla y pueden llevar notas internas); quién le asignó el seguro y por qué;
--          sus cambios de seguro; la prima, cuándo vence ni si está pagada; si está firmada
--          o si llegó la factura; la nota de DO; quién la registró; el historial; si
--          renueva sola; el nombre con que DO subió cada archivo; las facturas ni los
--          archivos «otro»; las pólizas anuladas.
--
--   El nombre del archivo no sale a propósito: lo escribe DO al subirlo y puede llevar
--   nombres de personas. La pantalla rotula cada archivo por su tipo, no por lo que
--   alguien escribió.
--
-- LO QUE DECIDÍ, Y LO QUE DESCARTÉ
--
--   DECIDÍ:    LA PUERTA ES «ES MI PÓLIZA», no «hoy estoy en ese seguro». Quien pasa de
--              FOLA a EsSalud conserva su póliza FOLA y su PDF: la póliza sigue vigente
--              hasta que la aseguradora procese la baja, y puede necesitarla para un
--              reembolso de lo que pasó cuando sí cubría. La primera versión de esta
--              migración pedía ser practicante HOY; se quitó cuando Felipe hizo el módulo
--              general (2026-10-17).
--   DECIDÍ:    LA REGLA DE EN QUÉ SEGURO ESTÁ ALGUIEN NO SE ESCRIBE OTRA VEZ.
--              `fn_mi_seguro` llama a `fn_seguro_tipo_principal` (0528), la misma que
--              usa `fn_seguros_equipo` para DO. «Cubre hoy» sí se repite —la misma cuenta,
--              con el último día EXCLUSIVO—, y la prueba 423 compara las dos respuestas
--              persona por persona.
--   DECIDÍ:    LA PERSONA NO VE LA MORA, Y POR ESO SU PANTALLA NO DICE «CUBIERTO».
--              `cubre_hoy` es solo de fechas, igual que en `fn_seguros_equipo`. La cobertura
--              puede suspenderse sola si la prima lleva más de 30 días sin pagarse (convenio
--              de pago, cláusula quinta): la pantalla de DO lo calcula con `estadoPrima` y
--              lo llama «suspendida». Aquí no sale la prima ni su estado, así que la pantalla
--              habla de la PÓLIZA («vigente», «va hasta») y nunca de que la persona «esté
--              cubierta», y cierra con «si la aseguradora te dice otra cosa, avisa a
--              Desarrollo Organizacional». Decirle «tu seguro está suspendido» por una marca
--              que DO todavía no hizo sería una falsa alarma sobre su salud; decirle
--              «estás cubierta» cuando no lo está, mandarla a una clínica a que se lo
--              nieguen. Si Felipe prefiere avisarle, hace falta una columna más en
--              `fn_mi_seguro` y repetir en SQL la regla de los 30 días de `estadoPrima`.
--   DECIDÍ:    UN SEGURO SIN PÓLIZA NO DICE MÁS QUE LO QUE LA BASE SABE. Para EsSalud la
--              función devuelve el nombre y `con_poliza = false`, y nada de texto: lo que
--              se le explica a la persona lo decide Felipe, no esta migración.
--   DECIDÍ:    `plan` y los beneficios máximos se devuelven tal cual y la pantalla los
--              calla mientras sean null. «Sin confirmar» no es un dato que mostrar: el
--              convenio de FOLA ya promete 14 y 30 subvenciones, y una cifra equivocada es
--              peor que ninguna.
--   DECIDÍ:    UNA función de apoyo para Storage (`fn_seguro_archivo_es_mio`). Las tablas
--              de pólizas solo las lee DO, así que una consulta metida dentro de la
--              política vería cero filas para quien no es DO. Es el molde de
--              `fn_boleta_puede_ver` (0482).
--   DESCARTÉ:  Devolver `seguros_tipos.descripcion`. DO la edita desde la pantalla y la de
--              EsSalud dice «Dynamic solo lo muestra»: es un texto para DO.
--   DESCARTÉ:  Una sola función con las pólizas anidadas en un json: se pierde el tipado
--              de lo que se devuelve y la prueba no puede fijar la lista de columnas.
--   DESCARTÉ:  Dejar ver todos los archivos de una póliza. La factura es papel de DO y del
--              contador; «otro» es un cajón de DO.
--
-- QUÉ NO HACE
--
--   · No deja escribir nada. Nadie sube, retira ni marca desde aquí: la política es solo
--     de lectura y las funciones solo leen.
--   · No avisa a nadie de nada ni toca la Bandeja.
--   · No lee ni escribe planilla, ni `aporte_essalud`, ni ninguna columna de pago.
--   · Ninguna función existente se reescribe → no hay md5 de partida.
--
-- SE ROMPE SI
--
--   · Se agrega un tipo de archivo nuevo a `polizas_seguro_archivos.tipo` esperando que la
--     persona lo vea: no lo verá, porque la lista de los dos tipos vive en `fn_mis_polizas`
--     Y en `fn_seguro_archivo_es_mio`. La prueba 423 y `tests/mi-seguro.test.ts` la
--     comparan; fallarían en `db-tests` si una cambia sin la otra.
--   · Cambia la lista de columnas de `fn_mi_seguro` o de `fn_mis_polizas`: `create or
--     replace` no deja cambiar lo que una función devuelve (hay que `drop function`
--     primero) y hay que volver a generar los tipos. La prueba 423 fija las dos listas, a
--     propósito: una columna nueva es una decisión de qué ve una persona, no un descuido.
--   · La 0528 cambia cómo se decide el seguro principal: `fn_mi_seguro` la sigue sola
--     (llama a la misma función); lo que no sigue solo es «cubre hoy».
--
-- ANTES DE PEGAR — UNA CONSULTA DE SOLO LECTURA A PRODUCCIÓN (SQL Editor)
--   Esperado: la 0528 presente (6 tablas, las dos funciones de apoyo, las 4 políticas
--   de DO) y NADA de esta migración todavía.
--
--   select
--     (select count(*) from information_schema.tables
--       where table_schema = 'public'
--         and table_name in ('seguros_tipos','seguros_asignaciones','seguros_cambios',
--                            'polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos'))
--                                                                    as tablas_0528_de_6,
--     (select count(*) from pg_proc
--       where proname in ('fn_seguro_tipo_principal','fn_seguro_archivo_libre'))   as apoyo_0528_de_2,
--     (select count(*) from pg_policies where schemaname = 'storage'
--         and policyname in ('polizas_seguro_insert','polizas_seguro_select',
--                            'polizas_seguro_update','polizas_seguro_delete')) as politicas_0528_de_4,
--     (select count(*) from pg_proc
--       where proname in ('fn_mi_seguro','fn_mis_polizas','fn_seguro_archivo_es_mio'))
--                                                                    as funciones_que_ya_existen,
--     (select count(*) from pg_policies where schemaname = 'storage'
--         and policyname = 'polizas_seguro_select_propia')           as politica_que_ya_existe,
--     (select string_agg(numero || ' · ' || nombre, ' | ' order by numero) from migraciones_aplicadas
--       where numero between 526 and 532)                            as registro_526_a_532;
--
-- CÓMO SE REVIERTE (esta primero y luego la 0528, nunca al revés: la política y las
-- funciones de aquí leen las tablas de allá)
--   begin;
--   drop policy if exists polizas_seguro_select_propia on storage.objects;
--   drop function if exists fn_mi_seguro();
--   drop function if exists fn_mis_polizas();
--   drop function if exists fn_seguro_archivo_es_mio(text);
--   delete from migraciones_aplicadas where numero = 530;
--   commit;
--   Nada de planilla, asistencia ni pago lee esto: revertir solo esconde la sección
--   «Mi seguro» (la pantalla muestra «no pudimos leer tu seguro»). No se pierde ningún dato.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final, que va la última porque el SQL Editor solo muestra el
--   resultado de la última. Y la prueba 423 en `db-tests`.
-- ============================================================================


-- ── 0 · Esta migración cuelga de la 0528 ─────────────────────────────────────
-- Las funciones de PL/pgSQL no comprueban sus tablas al crearse: sin este bloque,
-- pegar la 0530 sin la 0528 "funcionaría" y fallaría recién cuando alguien abra la
-- sección. Se detiene antes de tocar nada.
do $guarda$
begin
  if to_regclass('public.seguros_tipos') is null
     or to_regclass('public.polizas_seguro') is null
     or to_regclass('public.polizas_seguro_archivos') is null
     or to_regprocedure('public.fn_seguro_tipo_principal(uuid, date)') is null
     or to_regprocedure('public.fn_seguro_archivo_libre(text)') is null then
    raise exception 'La 0530 necesita la 0528 (los seguros del equipo) y no está pegada. Pega primero la 0528.';
  end if;
end
$guarda$;


-- ── 1 · Quién puede abrir qué archivo (Storage) ──────────────────────────────
-- Un archivo es «mío» si está en una póliza MÍA que no se anuló, es de un tipo que la
-- persona ve (póliza o convenio de pago) y no está retirado. SECURITY DEFINER porque las
-- tablas son de DO. Nunca devuelve null: `exists (…)` es true o false, y sin sesión o sin
-- ficha `fn_persona_actual_id()` es null, así que la comparación no encuentra nada.
--
-- No mira qué es la persona hoy (practicante, planilla…): una póliza es de quien es, aunque
-- haya cambiado de seguro. Los dos tipos están escritos AQUÍ y en `fn_mis_polizas`; si uno
-- cambia, el otro también: la prueba 423 compara las dos lecturas archivo por archivo.
create or replace function fn_seguro_archivo_es_mio(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $fn$
  select fn_persona_actual_id() is not null
     and exists (
       select 1
         from polizas_seguro_archivos a
         join polizas_seguro z on z.id = a.poliza_id
        where a.storage_path = p_path
          and a.tipo in ('poliza', 'convenio_pago')
          and a.retirado_at is null
          and z.anulada_at is null
          and z.persona_id = fn_persona_actual_id()
     );
$fn$;

-- Las políticas se evalúan con el privilegio de quien lee, así que `authenticated`
-- tiene que poder llamarla. Nadie más.
grant execute on function fn_seguro_archivo_es_mio(text) to authenticated;
revoke execute on function fn_seguro_archivo_es_mio(text) from public, anon;

-- UNA política, de lectura. Se suma a `polizas_seguro_select` (la de DO): las políticas
-- permisivas del mismo tipo se suman con OR, así que DO sigue viendo todo y cada persona
-- ve solo lo suyo. No hay política de insert, update ni delete para ella: no sube ni toca
-- nada.
drop policy if exists polizas_seguro_select_propia on storage.objects;
create policy polizas_seguro_select_propia on storage.objects
  for select to authenticated
  using (bucket_id = 'polizas-seguro' and fn_seguro_archivo_es_mio(name));


-- ── 2 · En qué seguro está ───────────────────────────────────────────────────
-- UNA fila: su seguro PRINCIPAL de hoy. Si no le corresponde ninguno (honorarios, sin
-- vínculo laboral), la fila viene con todo en null y `con_poliza` en false. Si la persona no
-- tiene ficha, o es la cuenta de servicio de un terminal, no devuelve nada: no es un error
-- (la pantalla ya dice qué hacer cuando no hay nada).
--
--   tipo         la clave del seguro (`seguros_tipos.clave`), o null.
--   tipo_nombre  cómo se llama («FOLA», «EsSalud»).
--   con_poliza   false = «por planilla» (EsSalud): no hay póliza que ver. Tampoco hay
--                póliza si no le corresponde ningún seguro.
--   cubre_hoy    solo si su seguro lleva póliza: si alguna de ese tipo está vigente hoy
--                (solo fechas, el último día NO cuenta). null si no lleva. Es el MISMO
--                cálculo de `fn_seguros_equipo` (0528), que tampoco sabe de mora.
create or replace function fn_mi_seguro()
returns table (
  tipo        text,
  tipo_nombre text,
  con_poliza  boolean,
  cubre_hoy   boolean
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
  -- `is not false` y no `not`: si la ficha no aparece el subselect no devuelve nada (null)
  -- y eso no puede pasar como «es una persona».
  if (select p.cuenta_de_servicio from personas p where p.id = v_yo) is not false then
    return;
  end if;

  return query
  select ef.clave,
         t.nombre,
         coalesce(t.con_poliza, false),
         case when t.con_poliza then cob.cubre end
    from (select fn_seguro_tipo_principal(v_yo, v_hoy) as clave) ef
    left join seguros_tipos t on t.clave = ef.clave
    left join lateral (
      select exists (select 1 from polizas_seguro z
                      where z.persona_id = v_yo and z.producto = ef.clave and z.anulada_at is null
                        and v_hoy >= z.vigente_desde and v_hoy < z.vigente_hasta) as cubre
    ) cob on true;
end;
$fn$;

grant execute on function fn_mi_seguro() to authenticated;
revoke execute on function fn_mi_seguro() from public, anon;


-- ── 3 · Sus pólizas ──────────────────────────────────────────────────────────
-- Una fila por póliza viva (no anulada) de quien llama, de CUALQUIER seguro —el principal,
-- uno complementario o el que tenía antes de cambiar—, la más reciente primero. Si no tiene
-- ficha, no devuelve nada.
--
-- `archivos` es un arreglo json, siempre un arreglo (vacío si no hay), con
-- {id, tipo, storage_path, mime, bytes}, la póliza antes que el convenio de pago y dentro
-- de cada tipo el más nuevo primero. Sin el nombre con que se subió.
create or replace function fn_mis_polizas()
returns table (
  poliza_id            uuid,
  producto             text,
  producto_nombre      text,
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

  return query
  select z.id, z.producto, t.nombre, z.aseguradora, z.numero_poliza, z.vigente_desde, z.vigente_hasta,
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
    join seguros_tipos t on t.clave = z.producto
   where z.persona_id = v_yo
     and z.anulada_at is null
   -- `z.id desc` como ancla: dos pólizas con la misma fecha de inicio no empatan al azar
   -- (lección de la 0312/0389).
   order by z.vigente_desde desc, z.id desc;
end;
$fn$;

grant execute on function fn_mis_polizas() to authenticated;
revoke execute on function fn_mis_polizas() from public, anon;


-- ── Registro ─────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (530, 'mi_seguro_cada_colaborador_ve_su_seguro_y_abre_sus_pdf')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc
    where proname in ('fn_mi_seguro', 'fn_mis_polizas', 'fn_seguro_archivo_es_mio'))            as funciones_de_3,
  (select count(*) from pg_policies where schemaname = 'storage'
      and policyname = 'polizas_seguro_select_propia' and cmd = 'SELECT')                       as politica_de_lectura_de_1,
  (select count(*) from pg_policies where schemaname = 'storage'
      and policyname like 'polizas\_seguro\_%')                                                  as politicas_storage_de_5,
  has_function_privilege('authenticated', 'fn_mi_seguro()', 'execute')                          as authenticated_lo_llama,
  has_function_privilege('anon', 'fn_mi_seguro()', 'execute')                                   as anon_no_deberia,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 530)              as registro;
