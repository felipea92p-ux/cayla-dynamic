-- ============================================================================
-- 0279 — Una sede sabe en qué ciudad está
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el contrato de trabajo pueda decir «En la ciudad de Trujillo» en vez de
--   «En la ciudad de Tienda TRU». Hoy el generador usa `sedes.nombre` como si
--   fuera una ciudad, y `nombre` es el nombre del local — «Central», «Taller
--   LIM», «Tienda AQP» —, que no es lo mismo.
--
-- POR QUÉ UNA COLUMNA Y NO UN MAPA EN EL CÓDIGO
--   Porque es exactamente la clase de dato que este repositorio prohíbe escribir
--   a mano: un `CIUDAD_POR_SEDE = {...}` en TypeScript se vuelve falso el día que
--   se abra una sede nueva desde la pantalla de Sedes, y nadie se entera hasta
--   que un contrato sale con la ciudad equivocada. La sede se gestiona desde una
--   pantalla; su ciudad tiene que viajar con ella.
--
-- QUÉ ASUME
--   `sedes` (0001) con su columna `codigo`. El backfill de abajo va POR CÓDIGO y
--   no por nombre: los nombres se editan desde `/admin/sedes`, los códigos no.
--
-- ⚠️ CCO (Central) SE RELLENA CON TRUJILLO Y HAY QUE CONFIRMARLO
--   Trujillo es el domicilio legal de CAYLA S.A.C. que declaran los contratos
--   («Mza. Q, Lote 26, Urb. San Andrés V Etapa, distrito de Trujillo»), así que
--   es la mejor respuesta disponible — pero es una DEDUCCIÓN, no un dato que
--   alguien haya cargado. Las otras tres salen de su propio código.
--
--   Si Central opera desde otra ciudad, se corrige con una sentencia:
--       update sedes set ciudad = 'Arequipa' where codigo = 'CCO';
--   El `raise notice` del final imprime lo que quedó, para poder verlo al pegar.
--
-- POR QUÉ NULLABLE Y NO `not null`
--   Una sede nueva creada desde la pantalla no tendría cómo llenarla, y un
--   `not null` rompería esa pantalla en vez de avisar. El generador de contratos
--   trata el null como «falta el dato» y lo dice en el documento, en vez de
--   imprimir una ciudad inventada — misma regla que la tarifa de movilidad.
--
-- CÓMO SE REVIERTE
--   alter table sedes drop column if exists ciudad;
-- ============================================================================

alter table sedes add column if not exists ciudad text;

comment on column sedes.ciudad is
  'La ciudad donde opera la sede, para los documentos legales que la nombran '
  '(«En la ciudad de …»). No es lo mismo que `nombre`, que es el nombre del '
  'local. Nullable a proposito: una sede sin ciudad cargada hace que el '
  'documento lo diga, en vez de imprimir una ciudad inventada.';

-- Backfill por CÓDIGO, no por nombre: los nombres se editan desde la pantalla.
-- Idempotente: solo rellena lo que está vacío, así que repegar la migración no
-- pisa una corrección hecha a mano.
update sedes set ciudad = 'Trujillo' where codigo = 'TRU' and ciudad is null;
update sedes set ciudad = 'Lima'     where codigo = 'LIM' and ciudad is null;
update sedes set ciudad = 'Arequipa' where codigo = 'AQP' and ciudad is null;
update sedes set ciudad = 'Trujillo' where codigo = 'CCO' and ciudad is null;

insert into migraciones_aplicadas (numero, nombre)
values (279, 'una_sede_sabe_en_que_ciudad_esta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  r record;
  v_sin int;
begin
  raise notice '0279 · ciudad por sede, tal como quedo:';
  for r in select codigo, nombre, coalesce(ciudad, '(SIN CIUDAD)') as ciudad
             from sedes order by codigo loop
    raise notice '0279 ·   % (%) -> %', r.codigo, r.nombre, r.ciudad;
  end loop;

  select count(*) into v_sin from sedes where ciudad is null;
  if v_sin > 0 then
    raise notice '0279 · % sede(s) sin ciudad: sus contratos lo diran en el texto.', v_sin;
  end if;
  raise notice '0279 · CONFIRMA la fila CCO: se dedujo del domicilio legal, nadie la cargo.';
end $mig$;
