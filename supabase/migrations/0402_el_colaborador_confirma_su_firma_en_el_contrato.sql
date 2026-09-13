-- QUÉ PROMETE: un colaborador puede confirmar, con un paso explícito y
-- separado de "guardar mi firma", que la firma que ve estampada en SU
-- contrato (`/mio/contrato`) es la que quiere dejar ahí. Esa confirmación
-- queda visible para admin/líder: en la lista de contratos (una marca) y al
-- abrir el contrato individual (la firma del colaborador, estampada en su
-- propio apartado — hoy esa vista solo llenaba el apartado de la empresa).
--
-- QUÉ ASUME: esto es una confirmación DIGITAL, distinta y sin relación con
-- `fecha_firma`/`storage_path` — el trámite LEGAL sigue siendo el escaneo
-- físico que un admin sube a mano, como ya declara el comentario de
-- `/mio/contrato/page.tsx` ("Firmar acá NO reemplaza el escaneado físico").
-- Mezclar las dos habría sido un error: `contrato_firma_coherente` (0272) ya
-- protege esa tripleta legal, y esta migración no la toca ni la lee.
--
-- POR QUÉ ASÍ: se guarda una COPIA de la imagen en el momento de confirmar
-- (`firma_persona`), no una referencia viva a `firmas_escaneadas`. Si el
-- colaborador cambia su firma general después, este contrato sigue
-- mostrando la que confirmó — igual que un papel firmado no cambia solo
-- porque cambies tu firma de ahora en más. La alternativa (leer siempre
-- `firmas_escaneadas.imagen` en vivo) haría que cambiar la firma general
-- modificara en silencio contratos que ya se habían dado por confirmados.
--
-- `fn_contratos_listar` pasa a devolver una columna más
-- (`firma_persona_confirmada_at`) para que la lista muestre la marca sin
-- pedirle a cada fila su firma completa (esa sí pesa, y la lista no la
-- necesita: solo el detalle, que ya lee la fila entera vía RLS). Postgres no
-- reemplaza una función al cambiarle las columnas de retorno con
-- `create or replace` — por eso el `drop function` explícito, mismo motivo
-- documentado en la 0391 para esta misma función.
--
-- CÓMO SE REVIERTE:
--   drop function if exists fn_confirmar_mi_firma_contrato(uuid);
--   drop function if exists fn_contratos_listar(uuid);
--   -- recrear fn_contratos_listar con el cuerpo de la 0391 (sin
--   -- firma_persona_confirmada_at);
--   alter table contratos_generados
--     drop constraint if exists chk_contrato_firma_persona,
--     drop column if exists firma_persona_confirmada_at,
--     drop column if exists firma_persona;
--
-- md5 de partida (LOCAL) de fn_contratos_listar, la que esta migración
-- reemplaza: 6253de3d0495f30043b5812e30e9400f — confirmar contra producción
-- con donde-vive.sh antes de pegar; si no coincide, PARAR.

-- ── La confirmación del colaborador, congelada al momento de darla ─────────
alter table contratos_generados
  add column if not exists firma_persona text,
  add column if not exists firma_persona_confirmada_at timestamptz;

alter table contratos_generados drop constraint if exists chk_contrato_firma_persona;
alter table contratos_generados add constraint chk_contrato_firma_persona check (
  (firma_persona is null and firma_persona_confirmada_at is null)
  or (firma_persona is not null and firma_persona_confirmada_at is not null
      and firma_persona ~ '^data:image/(png|jpeg);base64,')
);

-- ── Confirmar MI firma en MI contrato ───────────────────────────────────────
create or replace function fn_confirmar_mi_firma_contrato(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo     uuid;
  v_imagen text;
  v_dueno  uuid;
  v_anulado timestamptz;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select persona_id, anulado_at into v_dueno, v_anulado
    from contratos_generados where id = p_contrato_id;
  if v_dueno is null then raise exception 'No se encontró ese contrato.'; end if;
  if v_dueno <> v_yo then raise exception 'Ese contrato no es tuyo.'; end if;
  if v_anulado is not null then raise exception 'Ese contrato está anulado.'; end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a Mi perfil → Firma antes de confirmar.';
  end if;

  update contratos_generados
     set firma_persona = v_imagen, firma_persona_confirmada_at = now()
   where id = p_contrato_id;
end;
$$;
grant execute on function fn_confirmar_mi_firma_contrato(uuid) to authenticated;
revoke execute on function fn_confirmar_mi_firma_contrato(uuid) from public, anon;

-- ── fn_contratos_listar, con la marca de confirmación ───────────────────────
-- Mismo cuerpo que la 0391 (los tres desempates de generado_at/fecha_inicio/
-- fecha_fin/id ya resueltos ahí), con una columna más al final.
drop function if exists fn_contratos_listar(uuid);

create function fn_contratos_listar(p_persona_id uuid default null)
returns table (
  id                    uuid,
  persona_id            uuid,
  persona               text,
  tipo                  text,
  cargo                 text,
  sede                  text,
  remuneracion_mensual  numeric,
  fecha_inicio          date,
  fecha_fin             date,
  horas_semanales       numeric,
  generado_at           timestamptz,
  generado_por          text,
  storage_path          text,
  fecha_firma           date,
  copia_entregada_at    date,
  comunicado_mtpe_at    date,
  anulado_at            timestamptz,
  anulado_motivo        text,
  editado_at            timestamptz,
  editado_por           text,
  vigente               boolean,
  firma_persona_confirmada_at timestamptz   -- CAMBIO 0402
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id, c.persona_id, p.nombres || ' ' || p.apellidos,
    c.tipo, c.cargo, s.nombre,
    c.remuneracion_mensual, c.fecha_inicio, c.fecha_fin, c.horas_semanales,
    c.generado_at,
    gen.nombres || ' ' || gen.apellidos,
    c.storage_path, c.fecha_firma,
    c.copia_entregada_at, c.comunicado_mtpe_at,
    c.anulado_at, c.anulado_motivo,
    c.editado_at,
    edi.nombres || ' ' || edi.apellidos,
    (c.anulado_at is null and c.id = (
       select c2.id from contratos_generados c2
        where c2.persona_id = c.persona_id and c2.anulado_at is null
        order by c2.generado_at desc, c2.fecha_inicio desc,
                 c2.fecha_fin desc, c2.id desc limit 1)),
    c.firma_persona_confirmada_at   -- CAMBIO 0402
  from contratos_generados c
  join personas p on p.id = c.persona_id
  left join personas gen on gen.id = c.generado_por
  left join personas edi on edi.id = c.editado_por
  left join sedes s on s.id = c.sede_id
  where (fn_es_admin_o_lider() is true or c.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or c.persona_id = p_persona_id)
  order by c.generado_at desc;
$$;
grant execute on function fn_contratos_listar(uuid) to authenticated;
revoke execute on function fn_contratos_listar(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (402, 'el_colaborador_confirma_su_firma_en_el_contrato')
on conflict (numero) do nothing;
