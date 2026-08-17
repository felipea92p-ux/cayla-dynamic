-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 203_el_contador_de_constancias_cuenta_a_la_misma_gente.test.sql
-- ============================================================================
-- «N de M han dejado constancia» contaba dos poblaciones distintas: el numerador
-- toda fila de `documentos_acuses`, el denominador solo a quien está activa y en
-- planilla. La desviación no venía de un error de nadie: venía del PASO DEL
-- TIEMPO. Quien deja su constancia y después cesa se queda en el numerador —y
-- debe quedarse, esa fila es su prueba— pero sale del denominador.
--
-- El resultado era «24 de 24» sin el «faltan», o el imposible «24 de 23», en el
-- mismo texto que ES el botón que abre la lista que lo desmiente. Y un contador
-- que dice que ya está completo es justo el que hace que nadie mire la lista.
--
-- La 0265 lo corrige. Lo que esta prueba fija:
--
--   · que un cese haga bajar el numerador Y el denominador a la vez;
--   · que la fila del acuse NO se borre — la prueba de la entrega sobrevive al
--     cese, y es lo único que sostiene el expediente de un periodo pasado;
--   · que un locador no cuente en ninguno de los dos lados (no está comprendido
--     por el Reglamento);
--   · y que la etiqueta de versión del documento viaje hasta la pantalla, que es
--     lo que permite cruzar el cargo firmado con la base.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000009c1', 'ZZNO', 'Sede de laboratorio normas', true);

set session_replication_role = replica;

-- Dos obligadas, y una locadora que no lo está.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo)
values
  ('00000000-0000-0000-0000-0000000009a1', 'Ana',  'Obligada', '00000000-0000-0000-0000-0000000009c1', 'integrante', 'x', 'planilla'),
  ('00000000-0000-0000-0000-0000000009a2', 'Bea',  'Obligada', '00000000-0000-0000-0000-0000000009c1', 'integrante', 'x', 'planilla'),
  ('00000000-0000-0000-0000-0000000009a3', 'Cris', 'Locadora', '00000000-0000-0000-0000-0000000009c1', 'integrante', 'x', 'rxh');

insert into documentos_tipos (codigo, nombre, orden, requiere_acuse)
values ('zz_prueba_normas', 'Documento de laboratorio', 900, true)
on conflict (codigo) do nothing;

insert into documentos_institucionales (id, tipo, version, titulo, documento, vigente_desde, etiqueta_version)
values ('00000000-0000-0000-0000-0000000009d1', 'zz_prueba_normas', 1,
        'Documento de laboratorio', 'texto congelado', current_date, '4.0');

-- ── 1 · La locadora no entra en el denominador ──────────────────────────────
select is(
  (select poblacion from fn_documentos_vigentes() where documento_id = '00000000-0000-0000-0000-0000000009d1'),
  2,
  'la poblacion obligada son las dos en planilla, no la locadora'
);

select is(
  (select count(*)::int from fn_poblacion_obligada()),
  2,
  'fn_poblacion_obligada devuelve solo a quien tiene contrato de trabajo'
);

-- ── 2 · Las dos obligadas dejan constancia, y la locadora tambien ───────────
-- La locadora puede acusar si quiere; lo que no puede es alterar el contador.
insert into documentos_acuses (documento_id, persona_id, via, nombre_declarado)
values
  ('00000000-0000-0000-0000-0000000009d1', '00000000-0000-0000-0000-0000000009a1', 'sistema', 'Ana Obligada'),
  ('00000000-0000-0000-0000-0000000009d1', '00000000-0000-0000-0000-0000000009a2', 'sistema', 'Bea Obligada'),
  ('00000000-0000-0000-0000-0000000009d1', '00000000-0000-0000-0000-0000000009a3', 'sistema', 'Cris Locadora');

select is(
  (select total_acuses from fn_documentos_vigentes() where documento_id = '00000000-0000-0000-0000-0000000009d1'),
  2,
  'el numerador ignora a la locadora, igual que el denominador'
);

select ok(
  (select total_acuses = poblacion from fn_documentos_vigentes()
    where documento_id = '00000000-0000-0000-0000-0000000009d1'),
  'con las dos obligadas acusando, el contador cuadra'
);

-- ── 3 · Bea cesa ────────────────────────────────────────────────────────────
update personas set estado = 'inactivo', fecha_cese = current_date
 where id = '00000000-0000-0000-0000-0000000009a2';

select is(
  (select poblacion || ' de ' || total_acuses from fn_documentos_vigentes()
    where documento_id = '00000000-0000-0000-0000-0000000009d1'),
  '1 de 1',
  'el cese baja el numerador Y el denominador: nunca «2 de 1»'
);

select ok(
  (select total_acuses <= poblacion from fn_documentos_vigentes()
    where documento_id = '00000000-0000-0000-0000-0000000009d1'),
  'el numerador no puede pasarse del denominador, que era el numero imposible'
);

-- ── 4 · Y la prueba de la entrega sobrevive al cese ─────────────────────────
-- Esto es lo que NO se puede perder: el expediente de un periodo pasado se
-- sostiene en esa fila. Bajarla del contador es una cosa; borrarla, otra.
select is(
  (select count(*)::int from documentos_acuses
    where persona_id = '00000000-0000-0000-0000-0000000009a2'),
  1,
  'la constancia de quien ceso sigue guardada: es la prueba de que la recibio'
);

-- ── 5 · La etiqueta del documento llega a la pantalla ──────────────────────
select is(
  (select etiqueta_version from fn_documentos_vigentes()
    where documento_id = '00000000-0000-0000-0000-0000000009d1'),
  '4.0',
  'la version que declara el documento viaja hasta la lista, para poder cruzarla con el cargo firmado'
);

select * from finish();
rollback;
