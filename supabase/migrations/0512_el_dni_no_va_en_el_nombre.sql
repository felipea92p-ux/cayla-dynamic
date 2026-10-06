-- ============================================================================
-- 0512 · El DNI no va en el nombre
-- ============================================================================
--
-- ── QUÉ PASÓ ────────────────────────────────────────────────────────────────
--
-- El 2026-10-06 apareció en Correcciones, en Equipo y en el terminal de su sede
-- una integrante con su DNI pegado al apellido corto: «Nombre Apellido 7xxxxxxx».
-- Ningún código lo pegó. Se tecleó a mano en el «Apellido corto» al darla de
-- alta: el alta no tiene un campo para el DNI, y desde la 0506 un nombre
-- parecido a otro pide confirmación — escribir el número en el nombre es la
-- forma natural de «diferenciarla» cuando el formulario no ofrece otra.
--
-- Lo que eso cuesta: el nombre corto se ve en TODAS las listas del panel y en
-- el terminal, que marca sin PIN a la vista de toda la sede. Un DNI ahí es un
-- dato personal publicado. Y el número tampoco cumple la función que se le
-- quería dar: el índice único de documento (0125) mira `personas.documento`,
-- no el apellido, así que no frena ningún duplicado.
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
--   1. Limpia los nombres que ya lo tienen: quita del nombre y del apellido
--      corto toda secuencia de 6 o más dígitos (y los espacios que la rodean).
--      Dice por NOTICE a quién tocó y si esa persona tiene o no su DNI cargado
--      en `personas.documento` — si no, hay que cargarlo en Datos personales.
--   2. `personas_nombre_sin_documento`: un CHECK que hace imposible volver a
--      guardarlo, entre por la puerta que entre (alta, edición, SQL).
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- Que ningún nombre real ni ninguna estación de retail lleva 6 dígitos
-- seguidos. Por eso 6 y no «ningún dígito»: cualquier documento tiene más
-- (DNI 8, carné de extranjería 9, RUC 11, un celular 9), y una estación que
-- algún día se llame «Caja 2» no rompe nada. La pantalla usa la MISMA regla
-- (`PATRON_DOCUMENTO_EN_NOMBRE`, packages/shared/src/nombres.ts): si se cambia
-- aquí, se cambia allá.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- Un CHECK y no solo la validación de la pantalla: la pantalla se puede saltar
-- (otra pestaña vieja, otra pantalla futura, un SQL a mano) y la base no.
--
-- La limpieza va DENTRO de la migración y no como un paso aparte porque el
-- CHECK no se puede validar mientras exista una fila que lo rompa: con un paso
-- aparte, pegar esto antes de corregir el nombre fallaría. Así es una sola
-- pegada, y repegarla no hace nada (ya no hay filas que limpiar).
--
-- La limpieza NO mueve el número a `personas.documento`: ese campo tiene su
-- puerta con reglas y rastro (0125), y un número tecleado dentro de un apellido
-- no es un dato verificado. Se avisa, y se carga a mano desde Datos personales.
--
-- Sin rastro en `correcciones_auditoria`: `corregido_por` es NOT NULL y en el
-- SQL Editor no hay persona que firme (mismo criterio que la 0490). El rastro
-- es esta migración y su NOTICE.
--
-- Si limpiar dejara un nombre o un apellido VACÍO (alguien escribió solo el
-- número), la migración se detiene sin tocar nada y nombra a la persona: ese
-- nombre lo tiene que escribir alguien que la conozca.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   alter table personas drop constraint if exists personas_nombre_sin_documento;
--
-- La limpieza no se revierte: volver a escribir el DNI en el nombre es justo lo
-- que se está corrigiendo.
-- ============================================================================

-- ── 1 · Limpiar lo que ya está ──────────────────────────────────────────────
do $$
declare
  v_fila record;
  v_vacios text;
  v_tocadas int := 0;
begin
  -- Primero se mira, después se escribe: si alguna quedaría vacía, no se toca
  -- ninguna.
  select string_agg(id::text, ', ') into v_vacios
    from personas
   where (nombres ~ '[0-9]{6,}' or apellidos ~ '[0-9]{6,}')
     and (btrim(regexp_replace(nombres,   '[[:space:]]*[0-9]{6,}[[:space:]]*', ' ', 'g')) = ''
       or btrim(regexp_replace(apellidos, '[[:space:]]*[0-9]{6,}[[:space:]]*', ' ', 'g')) = '');
  if v_vacios is not null then
    raise exception '0512: a estas personas les quedaría el nombre o el apellido vacío al quitar el número: %. Corrígelas a mano en Equipo → Editar y vuelve a pegar esta migración.', v_vacios;
  end if;

  for v_fila in
    update personas
       set nombres   = btrim(regexp_replace(nombres,   '[[:space:]]*[0-9]{6,}[[:space:]]*', ' ', 'g')),
           apellidos = btrim(regexp_replace(apellidos, '[[:space:]]*[0-9]{6,}[[:space:]]*', ' ', 'g'))
     where nombres ~ '[0-9]{6,}' or apellidos ~ '[0-9]{6,}'
    returning id, nombres, apellidos, documento
  loop
    v_tocadas := v_tocadas + 1;
    raise notice '0512: queda «% %» (id %). %', v_fila.nombres, v_fila.apellidos, v_fila.id,
      case when v_fila.documento is null
        then 'NO tiene DNI cargado: cárgalo en Datos personales.'
        else 'Su DNI ya está cargado aparte.'
      end;
  end loop;

  raise notice '0512: % persona(s) con un número en el nombre corregida(s).', v_tocadas;
end $$;

-- ── 2 · Que no vuelva a pasar ───────────────────────────────────────────────
-- `not valid` + `validate` por separado: si quedara una fila que lo rompe,
-- falla el validate con el nombre del constraint, y como el SQL Editor corre
-- todo en una transacción, no queda nada a medias.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'personas_nombre_sin_documento'
       and conrelid = 'public.personas'::regclass
  ) then
    alter table personas add constraint personas_nombre_sin_documento check (
      nombres !~ '[0-9]{6,}' and apellidos !~ '[0-9]{6,}'
    ) not valid;
  end if;
  alter table personas validate constraint personas_nombre_sin_documento;
end $$;

comment on constraint personas_nombre_sin_documento on personas is
  'El nombre y el apellido corto no llevan 6+ dígitos seguidos (un DNI, CE, RUC o celular). '
  'Se ven en el terminal y en todas las listas; el DNI va en personas.documento. 0512. '
  'La pantalla usa la misma regla: PATRON_DOCUMENTO_EN_NOMBRE en packages/shared/src/nombres.ts.';

insert into migraciones_aplicadas (numero, nombre) values (512, 'el_dni_no_va_en_el_nombre')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── COMPROBACION ────────────────────────────────────────────────────────────
-- Todas deben dar `true`, y `registro` debe decir 512 · el_dni_no_va_en_el_nombre.
select
  (select count(*) = 0 from personas where nombres ~ '[0-9]{6,}' or apellidos ~ '[0-9]{6,}')
    as ningun_nombre_con_numero,
  (select convalidated from pg_constraint
    where conname = 'personas_nombre_sin_documento' and conrelid = 'public.personas'::regclass)
    as candado_validado,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 512)
    as registro;
