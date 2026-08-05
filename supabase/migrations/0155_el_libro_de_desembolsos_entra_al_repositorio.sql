-- ============================================================================
-- 0155 — El libro de desembolsos entra al repositorio
-- ============================================================================
--
-- QUÉ PROMETE
--   `desembolsos_beneficios` queda descrita en el esquema, con la forma exacta
--   que ya tiene en producción, y protegida igual en todas las bases. Después de
--   esta migración, una base construida desde cero es idéntica a producción en
--   esta tabla.
--
-- QUÉ ASUME
--   · En producción la tabla YA existe: la 0153 la protegió el 2026-08-05. Acá
--     el `create table if not exists` no hace nada allá y sí en el laboratorio.
--   · Su forma se leyó de `information_schema` en producción ese mismo día. No
--     hay ni un tipo adivinado.
--
-- DE DÓNDE SALE ESTA TABLA
--   No de una migración: alguien la creó a mano en el SQL Editor. El comparador
--   la encontró el 2026-08-05 porque sus siete candados aparecieron como «sobran
--   en produccion». Cero coincidencias en el código, en las nueve ramas y en la
--   historia completa de commits.
--
--   Es el libro de a quién se le entregó qué beneficio: las cinco ventanas del
--   año peruano —las dos gratificaciones, los dos depósitos de CTS y las
--   vacaciones—, de qué año, cuánto, cuándo y por dónde salió la plata.
--
-- LO QUE ESTA MIGRACIÓN NO RESUELVE, Y HAY QUE DECIDIR
--   Ninguna función del sistema lee esta tabla. Comprobado: cero.
--
--   El sistema calcula lo que se DEBE (fn_cts_trunca, fn_grati_trunca,
--   fn_provisiones) y esta tabla registra lo que se PAGÓ, y no se hablan. La
--   0123 ya arregló que lo pagado dejara de acumularse en Provisiones, pero lo
--   hizo mirando los movimientos de la PLANILLA. Los valores de `origen`
--   —`plame`, `transferencia`, `otro`— sugieren que esta tabla anota justamente
--   lo que salió POR FUERA de la planilla, que es lo que la 0123 no puede ver.
--
--   Si eso es así, hoy hay dinero entregado que las provisiones no descuentan.
--   Es una decisión de negocio, no técnica, y no se toma en una migración.
--
-- POR QUÉ REPITE LA PROTECCIÓN DE LA 0153
--   Porque el orden manda. La 0153 corre ANTES y en el laboratorio no encuentra
--   la tabla, así que no hace nada; si esta solo la creara, el laboratorio
--   quedaría con la tabla abierta y producción con ella cerrada, y el comparador
--   marcaría esa diferencia para siempre. Con las dos, las dos bases convergen:
--   allá el `create` no hace nada y la protección es idempotente; acá se crea y
--   se protege en el mismo acto.
--
-- UNA DIVERGENCIA QUE SE CONSERVA A PROPÓSITO
--   `monto` es `numeric` SIN precisión, mientras el resto del sistema usa
--   `numeric(10,2)`. Se reproduce tal cual: el trabajo de esta migración es que
--   el repositorio describa la realidad, no corregirla de contrabando. Ajustar
--   el tipo cambia cómo se redondea plata ya registrada y merece su propia
--   migración, su propia prueba y su propia decisión.
--
-- CÓMO SE REVIERTE
--   En el laboratorio: drop table desembolsos_beneficios.
--   En producción NO se revierte: la tabla tiene datos y es anterior al repo.
-- ============================================================================

create table if not exists desembolsos_beneficios (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references personas(id),
  -- Las cinco ventanas del año laboral peruano. No es una lista arbitraria:
  -- son los momentos en que la ley obliga a entregar algo.
  ventana        text not null check (ventana = any (array['grati_s1','grati_s2','cts_may','cts_nov','vacaciones'])),
  anio           integer not null check (anio >= 2020 and anio <= 2100),
  monto          numeric not null check (monto > 0),
  fecha_pago     date not null,
  -- Por dónde salió: declarado en la PLAME, transferido al banco, u otro.
  origen         text not null check (origen = any (array['plame','transferencia','otro'])),
  nota           text,
  registrado_por uuid references personas(id),
  created_at     timestamptz not null default now()
);

-- Misma protección que la 0153 dejó en producción. Idempotente: allá no cambia
-- nada, acá deja el laboratorio igual que producción.
alter table desembolsos_beneficios enable row level security;
revoke all on desembolsos_beneficios from authenticated, anon;
drop policy if exists desembolsos_lectura_admin on desembolsos_beneficios;
create policy desembolsos_lectura_admin on desembolsos_beneficios
  for select using (fn_es_admin_o_lider());
grant select on desembolsos_beneficios to authenticated;

comment on table desembolsos_beneficios is
  'Libro de beneficios desembolsados: las cinco ventanas del año (dos gratificaciones, '
  'dos CTS, vacaciones), de qué año, cuánto, cuándo y por dónde salió. Creada a mano en '
  'producción antes de la 0153 y descrita en el repositorio recién en la 0155. Solo lectura '
  'para admin o líder de DO. NINGUNA función del sistema la lee todavía: lo que se debe y '
  'lo que se pagó se calculan por separado y no se descuentan entre sí.';

insert into migraciones_aplicadas (numero, nombre)
values (155, 'el_libro_de_desembolsos_entra_al_repositorio')
on conflict (numero) do nothing;
