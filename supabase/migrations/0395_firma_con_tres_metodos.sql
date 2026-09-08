-- QUÉ PROMETE: permite guardar la firma de un integrante por tres métodos —
-- imagen escaneada (el único que existía), trazo a mano en un canvas, o una
-- firma tipográfica generada a partir del nombre oficial del perfil— sin
-- cambiar el contrato que ya consumen el memo disciplinario, el contrato de
-- trabajo y la política salarial: los tres siguen pidiendo `fn_mi_firma()` /
-- `fn_firma_de_memo()` y reciben la misma imagen PNG/JPEG en base64 de
-- siempre. `firmas_escaneadas.imagen` sigue siendo SIEMPRE el PNG final ya
-- renderizado, sin importar el método con que se generó.
--
-- QUÉ ASUME: que el nombre que se imprime en una firma tipográfica nunca lo
-- escribe quien firma — sale de `datos_personales.nombre_dni` (con reserva a
-- `personas.nombres`+`apellidos`), igual que ya hace la ficha y los contratos
-- (ver `personas/[id]/page.tsx`: `ficha?.nombre_dni || nombre`). Por eso esta
-- migración NO agrega una columna de texto para el nombre: guardarlo aparte
-- abriría la puerta a que quedara desactualizado o a que alguien firmara con
-- un nombre distinto al de su DNI — el riesgo que este cambio busca cerrar.
--
-- POR QUÉ ASÍ: lo único que cambia en la base es que ahora se guarda TAMBIÉN
-- cómo se generó la firma (`tipo`) y, si fue tipográfica, con qué estilo
-- (`estilo`) — para que la pantalla pueda reabrir el editor mostrando lo
-- último elegido en vez de perderlo. El recorte y la transparencia del PNG
-- siguen resolviéndose en el cliente, como ya hacía "subir imagen".
--
-- `fn_set_mi_firma` pasa de 1 a 3 argumentos. Postgres no reemplaza una
-- función al cambiarle la cantidad de parámetros con `create or replace`
-- —crea una SEGUNDA función con ese nombre, y una llamada con los argumentos
-- que ambas aceptan queda ambigua ("function is not unique")—, que es
-- exactamente el accidente que dejó dos `fn_vacaciones_por_vencer`
-- conviviendo en silencio el 2026-08-25 (0297/0299). Por eso el
-- `drop function` explícito de abajo, antes de crear la versión nueva.
--
-- CÓMO SE REVIERTE:
--   drop function if exists fn_set_mi_firma(text, text, text);
--   drop function if exists fn_mi_firma_config();
--   -- recrear fn_set_mi_firma(p_dataurl text) con el cuerpo de la 0076;
--   alter table firmas_escaneadas
--     drop constraint if exists chk_firma_estilo_segun_tipo,
--     drop constraint if exists chk_firma_tipo,
--     drop column if exists estilo,
--     drop column if exists tipo;
--
-- md5 de partida (LOCAL) de fn_set_mi_firma, la que esta migración reemplaza:
-- 240e266ee4732ddfecc029c3182c1ed2 — confirmar contra producción con
-- donde-vive.sh antes de pegar; si no coincide, PARAR (ver protocolo en
-- CLAUDE.md).

-- ── Qué método generó la firma, y con qué estilo ─────────────────────────────
alter table firmas_escaneadas
  add column if not exists tipo text not null default 'imagen',
  add column if not exists estilo text;

alter table firmas_escaneadas drop constraint if exists chk_firma_tipo;
alter table firmas_escaneadas add constraint chk_firma_tipo
  check (tipo in ('imagen', 'dibujo', 'tipografica'));

-- Estado imposible: una firma tipográfica sin estilo no se podría re-renderizar
-- si el usuario vuelve a abrir el editor, y una firma de imagen/dibujo con un
-- estilo tipográfico "colgando" no significa nada. El constraint hace que ese
-- par sea inconsistente a nivel de esquema, no algo que el código deba
-- acordarse de revisar cada vez que se toque esta tabla.
alter table firmas_escaneadas drop constraint if exists chk_firma_estilo_segun_tipo;
alter table firmas_escaneadas add constraint chk_firma_estilo_segun_tipo
  check (
    (tipo = 'tipografica' and estilo in ('elegante', 'a_mano', 'clasica'))
    or (tipo <> 'tipografica' and estilo is null)
  );

-- ── Guardar MI firma ─────────────────────────────────────────────────────────
drop function if exists fn_set_mi_firma(text);

create function fn_set_mi_firma(p_dataurl text, p_tipo text default 'imagen', p_estilo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo uuid; v_estilo text;
begin
  if not coalesce(fn_es_admin_o_lider(), false) then
    raise exception 'Solo un administrador o líder puede guardar su firma.';
  end if;
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  if p_dataurl is null then
    delete from firmas_escaneadas where persona_id = v_yo;
    return;
  end if;
  if p_tipo not in ('imagen', 'dibujo', 'tipografica') then
    raise exception 'Método de firma inválido: %.', p_tipo;
  end if;
  v_estilo := case when p_tipo = 'tipografica' then p_estilo else null end;
  if p_tipo = 'tipografica' and (v_estilo is null or v_estilo not in ('elegante', 'a_mano', 'clasica')) then
    raise exception 'Elige un estilo de firma válido.';
  end if;
  if p_dataurl !~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$' then
    raise exception 'Formato inválido: la firma debe ser una imagen PNG o JPEG.';
  end if;
  if length(p_dataurl) > 400000 then
    raise exception 'La firma pesa demasiado (% KB, el máximo es 390 KB). Vuelve a escanearla más pequeña.',
      round(length(p_dataurl) / 1024.0);
  end if;

  insert into firmas_escaneadas (persona_id, imagen, tipo, estilo, actualizado_at)
  values (v_yo, p_dataurl, p_tipo, v_estilo, now())
  on conflict (persona_id) do update
    set imagen = excluded.imagen, tipo = excluded.tipo, estilo = excluded.estilo, actualizado_at = now();
end;
$$;
grant execute on function fn_set_mi_firma(text, text, text) to authenticated;
revoke execute on function fn_set_mi_firma(text, text, text) from public, anon;

-- ── Ver CÓMO quedó configurada MI firma ──────────────────────────────────────
-- fn_mi_firma() no cambia: memo, contrato y política salarial le siguen
-- pidiendo solo la imagen. Esta función es nueva y solo la usa el editor —
-- para saber con qué método y estilo reabrir la pantalla, en vez de arrancar
-- siempre en "subir imagen" y perder la elección anterior.
create or replace function fn_mi_firma_config()
returns table(imagen text, tipo text, estilo text)
language sql stable security definer set search_path = public as $$
  select imagen, tipo, estilo from firmas_escaneadas where persona_id = fn_persona_actual_id();
$$;
grant execute on function fn_mi_firma_config() to authenticated;
revoke execute on function fn_mi_firma_config() from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (395, 'firma_con_tres_metodos')
on conflict (numero) do nothing;
