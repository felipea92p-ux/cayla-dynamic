-- ============================================================================
-- 0514 — Las faltas se eligen por su nombre corto, y el memo de conducta llega
--        entero a la Info de la persona
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1. `faltas_rotulos`: un nombre corto para cada falta del catálogo
--      («Trato descortés», «Caja o inventario»), con el que la líder la elige
--      en el formulario. El papel NUNCA lo usa: cita el texto del RIT.
--   2. `fn_mi_memo` le entrega a la persona, junto con su documento de
--      conducta, la falta citada (numeral, literal, texto y gravedad) y la
--      fecha en que la empresa supo del hecho. Sin eso, el memo que lee en su
--      Info decía que cometió una falta sin poder decir cuál.
--
-- ── DE QUIÉN ES LA DECISIÓN ─────────────────────────────────────────────────
--
-- De la usuaria, el 2026-10-06, mirando el prototipo
-- (`docs/conducta-prototipo-2026-10-06.html`, decisión 2): elegir la falta
-- por nombres cortos y no por el texto completo. Se le mostró el costo: es
-- una segunda redacción que alguien mantiene, y se elige por un nombre que no
-- es lo que dice el papel. Por eso la pantalla muestra, al elegir, el texto
-- exacto que va a citar el memo.
--
-- ── POR QUÉ UNA TABLA APARTE Y NO UNA COLUMNA EN EL CATÁLOGO ────────────────
--
-- `faltas_catalogo` (0510) es inmutable a propósito: es el texto legal que
-- citan documentos ya entregados, y un trigger rechaza todo UPDATE. El nombre
-- corto es otra cosa —cómo se elige, no qué se cita— y SÍ tiene que poder
-- cambiarse si una líder no lo entiende. Ponerlo como columna obligaba a
-- elegir entre abrir el candado del texto legal o no poder corregir un
-- nombre. Dos tablas separan las dos cosas: el catálogo sigue cerrado, y los
-- nombres se corrigen con un `update` (o repegando esta migración, que usa
-- `do update`).
--
-- Un nombre corto por falta y versión, y dos faltas de la misma versión nunca
-- con el mismo nombre: al elegir no se podrían distinguir.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- Que la 0510 está pegada (el catálogo y sus columnas en el expediente) —
-- verificado en producción el 2026-10-06—.
--
-- md5 de partida de `fn_mi_memo` (0486): df34ddb98d0a221a6499594c239c0b01
-- (2149 caracteres) según el repositorio. PENDIENTE de confirmar contra
-- producción antes de entregar esta migración.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   · Restaurar `fn_mi_memo` de la 0486 (la pantalla de Lo mío vuelve a
--     mostrar el memo de conducta sin la falta, sin romperse).
--   · drop table faltas_rotulos;  (la pantalla elige entonces por número)
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · Los nombres cortos
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists faltas_rotulos (
  rit_version numeric(4,1) not null,
  numeral     text not null,
  literal     text not null,
  rotulo      text not null check (length(btrim(rotulo)) between 3 and 40),
  primary key (rit_version, numeral, literal),
  constraint fk_rotulo_falta foreign key (rit_version, numeral, literal)
    references faltas_catalogo (rit_version, numeral, literal),
  constraint uq_rotulo_por_version unique (rit_version, rotulo)
);

comment on table faltas_rotulos is
  'Nombre corto de cada falta del catálogo, para elegirla en pantalla. Nunca se imprime: el papel cita faltas_catalogo.texto.';

alter table faltas_rotulos enable row level security;
drop policy if exists faltas_rotulos_select on faltas_rotulos;
create policy faltas_rotulos_select on faltas_rotulos
  for select to authenticated using (true);
grant select on faltas_rotulos to authenticated;

-- `do update`: repegar corrige un nombre. Los de los literales a), b) y c) del
-- 53.2 no se eligen a mano, pero se nombran igual para cuando aparecen en el
-- panel de un caso.
insert into faltas_rotulos (rit_version, numeral, literal, rotulo) values
  (4.0, '53.1', 'a', 'Olvidó marcar'),
  (4.0, '53.1', 'b', 'Puesto desordenado'),
  (4.0, '53.1', 'c', 'Presentación personal'),
  (4.0, '53.1', 'd', 'Teléfono atendiendo'),
  (4.0, '53.1', 'e', 'Datos sin actualizar'),
  (4.0, '53.1', 'f', 'Se ausentó del puesto'),
  (4.0, '53.1', 'g', 'Salió antes sin permiso'),
  (4.0, '53.2', 'a', 'Tres leves en un año'),
  (4.0, '53.2', 'b', 'Tardanzas reiteradas'),
  (4.0, '53.2', 'c', 'Inasistencia injustificada'),
  (4.0, '53.2', 'd', 'No marca, reiterado'),
  (4.0, '53.2', 'e', 'No siguió una instrucción'),
  (4.0, '53.2', 'f', 'Seguridad y salud'),
  (4.0, '53.2', 'g', 'Caja o inventario'),
  (4.0, '53.2', 'h', 'Trato descortés'),
  (4.0, '53.2', 'i', 'Divulgó información'),
  (4.0, '53.2', 'j', 'Uso de bienes de la empresa'),
  (4.0, '53.2', 'k', 'Faltó a capacitación'),
  (4.0, '53.2', 'l', 'Conflicto de intereses'),
  (4.0, '53.2', 'm', 'No reportó un accidente')
on conflict (rit_version, numeral, literal) do update set rotulo = excluded.rotulo;


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · El memo de conducta llega entero a la Info de la persona
-- ════════════════════════════════════════════════════════════════════════════
-- Copiada de la 0486 (la vigente). Lo único nuevo son los dos campos del
-- final, marcados CAMBIO 0514.
create or replace function fn_mi_memo(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_yo uuid;
  d expediente_disciplinario%rowtype;
  p personas%rowtype;
  f personas%rowtype;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then return null; end if;

  select * into d from expediente_disciplinario where id = p_id and persona_id = v_yo;
  if not found then return null; end if;
  if d.nivel not in ('verbal', 'amonestacion', 'suspension') then return null; end if;
  if not ((d.estado = 'firmado' and d.enviado_a_info_at is not null) or d.estado = 'entregado') then
    return null;
  end if;

  select * into p from personas where id = d.persona_id;
  select * into f from personas where id = d.firmante_id;

  return jsonb_build_object(
    'id', d.id,
    'correlativo', d.correlativo,
    'tipo_causal', d.tipo_causal,
    'nivel', d.nivel,
    'estado', d.estado,
    'periodo_desde', d.periodo_desde,
    'periodo_hasta', d.periodo_hasta,
    'hechos', d.hechos,
    'suspension_dias', d.suspension_dias,
    'suspension_desde', d.suspension_desde,
    'suspension_hasta', d.suspension_hasta,
    'suspension_fechas', d.suspension_fechas,
    'firmado_at', d.firmado_at,
    'creado_at', d.creado_at,
    'entregado_at', d.entregado_at,
    'medio_entrega', d.medio_entrega,
    'enviado_a_info_at', d.enviado_a_info_at,
    'firma_sancionado', d.firma_sancionado,
    'firma_sancionado_confirmada_at', d.firma_sancionado_confirmada_at,
    'sancionado_rechazo_firma_at', d.sancionado_rechazo_firma_at,
    'persona', jsonb_build_object(
      'nombres', p.nombres,
      'apellidos', p.apellidos,
      'documento', p.documento,
      'funcion', p.funcion,
      'sede_codigo', (select s.codigo from sedes s where s.id = p.sede_base_id)
    ),
    'firmante', case when f.id is null then null else jsonb_build_object(
      'nombre', f.nombres || ' ' || f.apellidos,
      'cargo', fn_cargo_de_rol(f.rol)
    ) end,
    -- La regla de quién ve la firma de quien emite vive en fn_firma_de_memo
    -- (0148). Se llama a ella y no se copia: dos versiones de esa regla es
    -- exactamente lo que este repositorio ya pagó con el firmante de los memos.
    'firma_emisor', fn_firma_de_memo(d.id),
    -- CAMBIO 0514 · Conducta: la falta que el documento cita, con su texto en
    -- la versión del RIT que cita, y cuándo supo la empresa del hecho (52.6).
    -- Sin esto su memo decía «en los términos que constan en su expediente»:
    -- la persona leía que había cometido una falta sin poder leer cuál.
    'conocido_el', d.conocido_el,
    'falta', (select jsonb_build_object('numeral', c.numeral, 'literal', c.literal,
                                        'texto', c.texto, 'gravedad', c.gravedad)
                from faltas_catalogo c
               where c.rit_version = d.falta_rit_version
                 and c.numeral = d.falta_numeral and c.literal = d.falta_literal)
  );
end;
$$;

grant execute on function fn_mi_memo(uuid) to authenticated;
revoke execute on function fn_mi_memo(uuid) from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (514, 'las_faltas_se_eligen_por_nombre_corto')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
