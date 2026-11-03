-- ============================================================================
-- 0591 · «Prefiero trabajar» en la disponibilidad
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una colaboradora pueda decir, además de «no puedo» y «prefiero no»,
--   «prefiero trabajar» en ciertos días u horas, y que eso llegue a la
--   sugerencia de Turnos como una preferencia a favor (un empujón suave), nunca
--   como una obligación.
--
--   Dos cambios, y solo dos:
--     1. `disponibilidad_bloques.estado` acepta un tercer valor:
--        'prefiere_trabajar'. Es un día de la semana o una fecha, todo el día
--        (sin horas) o de una hora a otra, igual que los otros dos.
--     2. `disponibilidades.motivo` acepta 'preferencia'. Hace falta porque el
--        motivo es obligatorio en una disponibilidad parcial (CHECK
--        disponibilidad_parcial_con_motivo y la función guardián) y los cinco
--        motivos que había —estudios, hijos, salud, otro trabajo, otro— explican
--        por qué NO se puede. Quien solo marca lo que prefiere trabajar no tiene
--        nada que justificar, y obligarla a elegir «Salud» sería falso. La
--        pantalla pone 'preferencia' sola cuando no hay ninguna restricción; no
--        se ofrece como botón.
--
-- QUÉ ASUME
--   · Ninguna función cambia. `fn_disponibilidad_guardar_interno` inserta
--     `v_b->>'estado'` tal cual y la única puerta que valida el valor es el
--     CHECK de la columna; `fn_disponibilidad_vigente` devuelve `b.estado` tal
--     cual. Por eso esta migración NO reescribe ninguna función (no hay md5 de
--     partida que pedir a producción) y no puede revertir a otra sesión.
--   · El EXCLUDE `bloque_sin_cruces` no mira el estado: dos bloques del mismo
--     día que se cruzan se rechazan sean del estado que sean. «No puedo» y
--     «prefiero trabajar» en la misma hora seguiría siendo un cruce.
--   · Quien no aparece en un día puede a cualquier hora (sin cambio): «prefiero
--     trabajar» no es un permiso, es un deseo. Un turno NUNCA se mueve a
--     «no puedo» por él.
--
-- CONTRATO DE LECTURA (lo que cambia para la sugerencia de Turnos)
--   fn_disponibilidad_vigente devuelve además estado = 'prefiere_trabajar'
--     → la sugerencia lo cuenta a favor de ese turno (un bonus pequeño, mucho
--       menor que cubrir un hueco de la venta o que respetar un «prefiero no»).
--       Si la sugerencia de una versión vieja del panel no lo conoce, lo ignora
--       (solo lee 'no_puede', 'prefiere_no' y 'horario_fijo').
--
-- POR QUÉ ASÍ
--   · No una columna nueva ni una tabla aparte: es el mismo concepto (un bloque
--     de tiempo con un estado) y el modelo ya sabe cruzarlo, validarlo y
--     leerlo. Agregar un valor al CHECK es lo mínimo que lo hace posible.
--   · El CHECK se busca por lo que dice y no por su nombre: el automático
--     (`…_estado_check`) depende de cómo se creó la tabla en cada base. Se suelta
--     lo que haya y se deja uno con nombre propio, así repegar es seguro.
--
-- ESTADOS QUE NUNCA DEBEN EXISTIR (y quién lo impide)
--   · Un bloque con un estado inventado → CHECK disponibilidad_bloque_estado_valido.
--   · Una disponibilidad con un motivo inventado → CHECK disponibilidad_motivo_valido.
--   · Una parcial sin motivo → sigue igual (CHECK de la 0584 y la función).
--
-- SE ROMPE SI
--   · Alguien lee `disponibilidad_bloques.estado` y supone que solo hay dos
--     valores: la web (lib/disponibilidad.ts, sugerencia-turnos.ts y
--     sugerencia-entrada.ts) ya conoce los tres.
--
-- CÓMO SE PEGA — EN TRES PARTES, UNA POR UNA (aprendido el 2026-11-03)
--   El SQL Editor corre todo lo pegado en UNA transacción. Pegada entera, esta
--   migración tomaba un bloqueo exclusivo sobre `disponibilidad_bloques` y,
--   sin soltarlo, pedía otro sobre `disponibilidades`; una pantalla que lee las
--   dos tablas en el orden contrario (primero `disponibilidades`, después sus
--   bloques) cierra el ciclo y Postgres aborta con «40P01 deadlock detected». Eso
--   pasó en producción al primer intento: no se aplicó nada (la transacción se
--   revirtió entera) y se reprodujo después en un Postgres local con dos sesiones.
--   La salida es que cada transacción toque UNA sola tabla:
--     PARTE 1 · el estado de los bloques        (solo `disponibilidad_bloques`)
--     PARTE 2 · el motivo de la disponibilidad  (solo `disponibilidades`)
--     PARTE 3 · comentarios y registro          (ninguna tabla en uso)
--   Cada parte se pega y se corre sola, en ese orden, y empieza con
--   `set local lock_timeout = '3s'`: si no consigue el bloqueo en 3 segundos
--   falla con 55P03 en vez de quedarse en cola —y una ALTER en cola frena a todos
--   los que vienen detrás—; se repega y listo. Las partes 2 y 3 se niegan a
--   correr si falta la anterior, para que el registro nunca diga «aplicada» sin
--   estarlo. Todas son idempotentes. Entera, en un solo bloque, sigue siendo
--   válida en una base sin tráfico (`supabase db reset`, las pruebas).
--
-- CÓMO SE REVIERTE
--   Con datos nuevos ya guardados NO se revierte soltando el CHECK sin más: las
--   filas con 'prefiere_trabajar' / 'preferencia' dejarían de cumplirlo y
--   Postgres se negaría. Primero se archivan o se corrigen esas filas a mano, y
--   después se vuelve a poner el CHECK de dos valores (0584, línea del estado):
--     alter table disponibilidad_bloques drop constraint disponibilidad_bloque_estado_valido;
--     alter table disponibilidad_bloques add constraint disponibilidad_bloques_estado_check
--       check (estado in ('no_puede', 'prefiere_no'));
--   Las personas nunca se borran ni se pierden: esto solo toca bloques y motivos.
-- ============================================================================

-- ═══ PARTE 1 · El estado de un bloque (solo disponibilidad_bloques) ═════════

set local lock_timeout = '3s';

do $$
declare
  v_con text;
begin
  -- Lo que haya (el automático de la 0584 o uno anterior de esta misma): se suelta.
  for v_con in
    select conname
      from pg_constraint
     where conrelid = 'public.disponibilidad_bloques'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) like '%prefiere_no%'
       and conname <> 'disponibilidad_bloque_estado_valido'
  loop
    execute format('alter table public.disponibilidad_bloques drop constraint %I', v_con);
  end loop;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.disponibilidad_bloques'::regclass
                    and conname = 'disponibilidad_bloque_estado_valido') then
    alter table public.disponibilidad_bloques
      add constraint disponibilidad_bloque_estado_valido
      check (estado in ('no_puede', 'prefiere_no', 'prefiere_trabajar'));
  end if;
end;
$$;

comment on column public.disponibilidad_bloques.estado is
  'no_puede (nunca ahí) · prefiere_no (se respeta si alcanza la gente) · prefiere_trabajar (cuenta a favor '
  'de poner a la persona ahí; nunca obliga). 0584, 0591.';

-- ═══ PARTE 2 · El motivo de una disponibilidad (solo disponibilidades) ══════
-- Se pega DESPUÉS de la parte 1 y sola.

set local lock_timeout = '3s';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.disponibilidad_bloques'::regclass
                    and conname = 'disponibilidad_bloque_estado_valido') then
    raise exception 'Falta la PARTE 1 (el estado de los bloques): pégala primero y sola, y después esta.';
  end if;
end;
$$;

do $$
declare
  v_con text;
begin
  for v_con in
    select conname
      from pg_constraint
     where conrelid = 'public.disponibilidades'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) like '%otro_trabajo%'
       and pg_get_constraintdef(oid) not like '%registro_motivo%'
       and conname <> 'disponibilidad_motivo_valido'
  loop
    execute format('alter table public.disponibilidades drop constraint %I', v_con);
  end loop;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.disponibilidades'::regclass
                    and conname = 'disponibilidad_motivo_valido') then
    alter table public.disponibilidades
      add constraint disponibilidad_motivo_valido
      check (motivo in ('estudios', 'hijos', 'salud', 'otro_trabajo', 'otro', 'preferencia'));
  end if;
end;
$$;

comment on column public.disponibilidades.motivo is
  'estudios, hijos, salud, otro_trabajo, otro: por qué no puede. preferencia: solo marcó lo que prefiere '
  'trabajar (no hay nada que justificar); la pone la pantalla, no se elige. 0584, 0591.';

-- ═══ PARTE 3 · El contrato de lectura y el registro (ninguna tabla en uso) ═══
-- Se pega DESPUÉS de las partes 1 y 2 y sola.

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.disponibilidad_bloques'::regclass
                  and conname = 'disponibilidad_bloque_estado_valido')
     or not exists (select 1 from pg_constraint where conrelid = 'public.disponibilidades'::regclass
                     and conname = 'disponibilidad_motivo_valido') then
    raise exception 'Faltan la PARTE 1 o la PARTE 2: pégalas primero, cada una sola, y después esta.';
  end if;
end;
$$;

do $$
declare
  v_actual text := obj_description('public.fn_disponibilidad_vigente(date, date, uuid, timestamptz)'::regprocedure, 'pg_proc');
begin
  if v_actual is not null and v_actual not like '%prefiere_trabajar%' then
    execute format(
      'comment on function public.fn_disponibilidad_vigente(date, date, uuid, timestamptz) is %L',
      v_actual || ' 0591: además devuelve estado = prefiere_trabajar (cuenta a favor de ese turno; nunca obliga).');
  end if;
end;
$$;

-- Registro
insert into migraciones_aplicadas (numero, nombre) values (591, 'prefiero_trabajar_en_la_disponibilidad')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
