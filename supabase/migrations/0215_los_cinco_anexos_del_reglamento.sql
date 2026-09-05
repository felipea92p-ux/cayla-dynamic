-- ============================================================================
-- 0215 — Los cinco anexos del Reglamento, y quién puede añadir el sexto
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que los cinco documentos que derivan del Reglamento Interno de Trabajo se
-- puedan publicar en `/admin/normas` junto a él, cada uno con su constancia o
-- sin ella según lo que la ley pida de cada uno. Y que el día que haya un
-- sexto, se pueda añadir desde la pantalla en vez de con otra migración.
--
-- ── LOS CINCO, Y POR QUÉ CADA UNO LLEVA O NO CONSTANCIA ─────────────────────
--
-- El criterio no lo elige esta migración: lo fijan el numeral 4.5 y el 47.2 del
-- propio Reglamento. El 4.5 dice que las políticas, guías y manuales «solo son
-- exigibles desde que se entregan a la colaboradora con constancia de
-- recepción». El 47.2 dice que los instrumentos de hostigamiento sexual tienen
-- «finalidad informativa, de difusión y de gestión» y que en caso de
-- discrepancia prevalece el Reglamento.
--
-- De ahí sale, documento por documento:
--
--   · POLÍTICA DE PREVENCIÓN DEL HOSTIGAMIENTO SEXUAL → CON constancia.
--     Es el documento de difusión que la Ley 27942 y su Reglamento obligan a
--     poner en conocimiento de todo el personal. Sin constancia, la difusión no
--     se prueba, y probarla es la mitad de la obligación.
--
--   · RESOLUCIÓN DE DESIGNACIÓN DEL ÓRGANO → CON constancia.
--     El numeral 48.6 obliga a comunicar por escrito a cada persona quién es la
--     Delegada y cómo se la contacta. Un canal de queja que la persona no sabe
--     dónde está no es un canal.
--
--   · MANUAL DEL PROCEDIMIENTO DISCIPLINARIO → SIN constancia.
--     No impone ni una sola obligación a la colaboradora: le dice a quien
--     sanciona cómo hacerlo. Pedirle constancia a las 21 personas de un manual
--     que gobierna a tres llenaría el registro de acuses que no significan
--     nada — y un registro de constancias vale exactamente lo que valga que
--     cada línea signifique algo.
--
--   · FORMATO DE QUEJA → SIN constancia. Es un formulario en blanco.
--
--   · CARGO DE RECEPCIÓN DEL REGLAMENTO → SIN constancia, y este es el caso
--     que más claro lo deja: es el papel CON EL QUE se acusa el Reglamento.
--     Pedir constancia de él sería pedir el acuse del acuse.
--
-- Ninguno lleva `orden` por debajo del Reglamento: el 10 es suyo y se queda
-- suyo. La pantalla trata como anexo todo lo que no sea `rit`, así que el orden
-- solo decide en qué fila aparece cada anexo dentro de su bloque.
--
-- ── POR QUÉ ADEMÁS SE ABREN LAS POLÍTICAS DE ESCRITURA ──────────────────────
--
-- La 0208 dejó escrito que esta lista «se administra desde la pantalla» y que
-- «el código NUNCA escribe esta lista». Lo segundo se cumplió; lo primero no
-- llegó a existir: `documentos_tipos` solo tenía política de LECTURA, así que
-- nadie podía añadir un tipo desde ningún sitio, y el único camino real era
-- una migración como esta.
--
-- Eso convierte cada documento nuevo en trabajo de programación, que es justo
-- lo que la 0208 quiso evitar. Se abren `insert` y `update` a administración y
-- a Desarrollo Organizacional, y la pantalla estrena el formulario.
--
-- No se abre `delete` a propósito. Un tipo borrado se lleva por delante la
-- clave foránea de todas sus versiones publicadas y de sus acuses; para
-- retirar un documento de circulación está `activo`, que lo esconde sin tocar
-- las constancias que ya firmó el equipo.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- Que sembrar filas de catálogo desde una migración es aceptable pese a la
-- frase de la 0208. Lo es porque la 0208 hace exactamente eso con `rit` en su
-- línea 110: la prohibición es que el código de la aplicación mantenga una
-- lista paralela —la regla 3 del CLAUDE.md—, no que el esquema traiga sus
-- filas de arranque.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- `delete from documentos_tipos where codigo in (…)` mientras no tengan
-- versiones publicadas, y `drop policy` sobre las dos nuevas. Si ya se publicó
-- algún documento, no se borra el tipo: se pone `activo = false`.
-- ============================================================================

-- ── 1 · Los cinco anexos ────────────────────────────────────────────────────
insert into documentos_tipos (codigo, nombre, orden, requiere_acuse) values
  ('politica_hostigamiento',  'Política de Prevención del Hostigamiento Sexual Laboral', 20, true),
  ('resolucion_hostigamiento','Resolución de designación del órgano de hostigamiento sexual', 30, true),
  ('manual_disciplinario',    'Manual del Procedimiento Disciplinario',                  40, false),
  ('formato_queja',           'Formato de Queja o Denuncia por Hostigamiento Sexual',    50, false),
  ('cargo_recepcion',         'Cargo de recepción del Reglamento',                       60, false)
on conflict (codigo) do nothing;

-- ── 2 · Que la pantalla pueda administrarlos ────────────────────────────────
-- Guard en la forma obligatoria del CLAUDE.md: `is not true`, nunca `not (…)`.
-- Un null no puede pasar por autorizado.
drop policy if exists documentos_tipos_alta on documentos_tipos;
create policy documentos_tipos_alta on documentos_tipos
  for insert to authenticated
  with check (fn_es_admin_o_lider() is true);

drop policy if exists documentos_tipos_edicion on documentos_tipos;
create policy documentos_tipos_edicion on documentos_tipos
  for update to authenticated
  using (fn_es_admin_o_lider() is true)
  with check (fn_es_admin_o_lider() is true);

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (215, 'los_cinco_anexos_del_reglamento')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las cuatro deben decir true.
select
  (select count(*) from documentos_tipos where activo) = 6                    as hay_seis_documentos,
  (select count(*) from documentos_tipos where requiere_acuse and activo) = 3 as tres_piden_constancia,
  (select count(*) from pg_policy where polrelid = 'documentos_tipos'::regclass) = 3
                                                                              as tres_politicas,
  (select requiere_acuse from documentos_tipos where codigo = 'cargo_recepcion') is false
                                                                              as el_cargo_no_se_acusa_a_si_mismo;
