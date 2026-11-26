-- ============================================================================
-- 0624 — El organigrama marca una especialidad en común
-- ============================================================================
--
-- QUÉ PROMETE
--   Un distintivo corto y opcional en la tarjeta de cada quien («Negocios
--   internacionales»), para mostrar que varias personas de equipos distintos
--   comparten una especialidad sin cruzar el dibujo con más líneas.
--
--   Y acomoda los equipos para que las líneas no se crucen: Dirección pasa a la
--   izquierda de Sistemas (quien reparte hacia las tiendas queda en la orilla de
--   su lado) y Desarrollo Organizacional toma más ancho.
--
-- QUÉ ASUME
--   La 0623. Parte de sus dos funciones, y se niega a correr si en la base no
--   son esas (md5 sin retornos de carro: fn_organigrama
--   fbbe5dc1e392089ff67869f71aa2b55b · fn_organigrama_guardar
--   498153cd0f7ee684b8f905d4f40d4cf1).
--
-- POR QUÉ ASÍ
--   Es un dato aparte de la etiqueta (apoyo, asesoría, externo): una persona
--   puede asesorar y además tener especialidad. En `fn_organigrama_guardar`, no
--   mandar el distintivo lo CONSERVA y mandarlo vacío lo borra: así la web que
--   aún no conoce el campo no lo borra al guardar. La función cambia de firma,
--   así que la vieja se retira en la misma pasada (dos firmas con el mismo
--   nombre dejan la llamada ambigua).
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_organigrama_guardar(uuid, text, int, text, text, text, boolean, int, int, text);
--   pegar de nuevo la 0623 (recrea las dos funciones anteriores);
--   alter table organigrama_personas drop column if exists distintivo;
--   delete from migraciones_aplicadas where numero = 624;
-- ============================================================================

do $guard$
declare
  v_mal text;
begin
  -- Solo la primera vez: repegar encima de la 0624 ya aplicada no debe frenar.
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'organigrama_personas' and column_name = 'distintivo') then
    return;
  end if;
  select string_agg(e.nombre, ', ') into v_mal
    from (values ('fn_organigrama', 'fbbe5dc1e392089ff67869f71aa2b55b'),
                 ('fn_organigrama_guardar', '498153cd0f7ee684b8f905d4f40d4cf1')) as e(nombre, huella)
   where not exists (select 1 from pg_proc p
                      where p.proname = e.nombre and p.pronamespace = 'public'::regnamespace
                        and md5(replace(p.prosrc, chr(13), '')) = e.huella);
  if v_mal is not null then
    raise exception 'La 0624 no se aplicó: % no es la versión de la 0623.', v_mal;
  end if;
end
$guard$;

-- El puesto 12 es un lugar de paso: dos equipos no pueden compartir (fila, orden).
update organigrama_bloques set orden = 12 where clave = 'sistemas';
update organigrama_bloques set orden = 1 where clave = 'direccion';
update organigrama_bloques set orden = 2 where clave = 'sistemas';
update organigrama_bloques set ancho = 1.35 where clave = 'do';

alter table organigrama_personas add column if not exists distintivo text
  constraint organigrama_distintivo_corto check (distintivo is null or char_length(btrim(distintivo)) between 2 and 40);

create or replace function fn_organigrama()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_edita     boolean := fn_es_admin_o_lider() is true;
  v_publicado boolean;
begin
  if fn_persona_actual_id() is null then
    raise exception 'Inicia sesión para ver el organigrama.';
  end if;

  select coalesce((select publicado from organigrama_publicacion), false) into v_publicado;

  if not v_publicado and not v_edita then
    return jsonb_build_object('publicado', false, 'puede_editar', false,
      'bloques', '[]'::jsonb, 'personas', '[]'::jsonb, 'lineas', '[]'::jsonb, 'sin_ubicar', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'publicado', v_publicado,
    'puede_editar', v_edita,
    'bloques', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'clave', b.clave, 'nombre', b.nombre, 'fila', b.fila, 'orden', b.orden,
               'ancho', b.ancho, 'columnas', b.columnas, 'discreto', b.discreto,
               'orden_movil', b.orden_movil)
             order by b.fila, b.orden), '[]'::jsonb)
        from organigrama_bloques b),
    'personas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'persona_id', o.persona_id, 'nombres', p.nombres, 'apellidos', p.apellidos,
               'foto_url', p.foto_url, 'bloque', o.bloque, 'nivel', o.nivel, 'columna', o.columna,
               'orden', o.orden, 'funcion', o.funcion, 'etiqueta', o.etiqueta,
               'color', o.color, 'discreto', o.discreto,
               'distintivo', o.distintivo)
             order by o.bloque, o.nivel, o.columna, o.orden, p.apellidos, p.nombres, o.persona_id), '[]'::jsonb)
        from organigrama_personas o
        join personas p on p.id = o.persona_id
       where p.estado = 'activo' and not p.cuenta_de_servicio),
    'lineas', (
      select coalesce(jsonb_agg(jsonb_build_object('desde', l.desde, 'hasta', l.hasta, 'tipo', l.tipo)
             order by l.desde, l.hasta), '[]'::jsonb)
        from organigrama_lineas l
        join personas a on a.id = l.desde and a.estado = 'activo' and not a.cuenta_de_servicio
        join personas z on z.id = l.hasta and z.estado = 'activo' and not z.cuenta_de_servicio),
    -- A quién le falta sitio: solo le sirve a quien ordena.
    'sin_ubicar', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'persona_id', p.id, 'nombres', p.nombres, 'apellidos', p.apellidos,
               'cargo', p.cargo, 'sede', s.nombre)
             order by s.nombre, p.apellidos, p.nombres, p.id), '[]'::jsonb)
        from personas p
        left join sedes s on s.id = p.sede_base_id
       where v_edita
         and p.estado = 'activo' and not p.cuenta_de_servicio
         and not exists (select 1 from organigrama_personas o where o.persona_id = p.id))
  );
end;
$$;

drop function if exists fn_organigrama_guardar(uuid, text, int, text, text, text, boolean, int, int);

create or replace function fn_organigrama_guardar(
  p_persona_id uuid,
  p_bloque     text,
  p_nivel      int,
  p_funcion    text,
  p_etiqueta   text    default null,
  p_color      text    default null,
  p_discreto   boolean default false,
  p_columna    int     default null,
  p_orden      int     default 1,
  p_distintivo text    default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_columnas smallint;
  v_etiqueta text := nullif(btrim(coalesce(p_etiqueta, '')), '');
  v_color    text := nullif(btrim(coalesce(p_color, '')), '');
  v_distintivo text := nullif(btrim(coalesce(p_distintivo, '')), '');
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede cambiar el organigrama.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo' and not cuenta_de_servicio) then
    raise exception 'Solo se ubica a integrantes activos.';
  end if;
  if not exists (select 1 from organigrama_bloques where clave = p_bloque) then
    raise exception 'Ese equipo no existe en el organigrama.';
  end if;
  if p_funcion is null or char_length(btrim(p_funcion)) not between 2 and 120 then
    raise exception 'Escribe la función que se muestra (entre 2 y 120 letras).';
  end if;
  if p_nivel is null or p_nivel not between 1 and 9 then
    raise exception 'El nivel va del 1 al 9.';
  end if;
  if coalesce(p_orden, 1) not between 1 and 30 then
    raise exception 'El orden va del 1 al 30.';
  end if;
  if v_etiqueta is not null and v_etiqueta not in ('apoyo_lider', 'asesoria', 'externo') then
    raise exception 'Etiqueta desconocida.';
  end if;
  if v_color is not null and v_color not in ('verde', 'azul', 'ambar') then
    raise exception 'Color desconocido.';
  end if;
  if v_distintivo is not null and char_length(v_distintivo) not between 2 and 40 then
    raise exception 'El distintivo va de 2 a 40 letras.';
  end if;
  select columnas into v_columnas from organigrama_bloques where clave = p_bloque;
  if p_columna is not null and (v_columnas is null or p_columna not between 1 and v_columnas) then
    raise exception 'Ese equipo no tiene la columna %.', p_columna;
  end if;
  if p_columna is not null and exists (
       select 1 from organigrama_personas o
         join personas p on p.id = o.persona_id
        where o.bloque = p_bloque and o.nivel = p_nivel and o.columna = p_columna
          and o.persona_id <> p_persona_id and p.estado = 'activo') then
    raise exception 'Esa casilla ya está ocupada: elige otro nivel o columna.';
  end if;
  -- Quien ya salió no se dibuja, pero su fila seguiría reservando la casilla.
  delete from organigrama_personas o
   using personas p
   where p.id = o.persona_id and p.estado <> 'activo'
     and o.bloque = p_bloque and o.nivel = p_nivel and o.columna = p_columna;

  insert into organigrama_personas as o
    (persona_id, bloque, nivel, columna, orden, funcion, etiqueta, color, discreto, distintivo, actualizado_at, actualizado_por)
  values
    (p_persona_id, p_bloque, p_nivel, p_columna, coalesce(p_orden, 1), btrim(p_funcion), v_etiqueta,
     v_color, coalesce(p_discreto, false), v_distintivo, now(), fn_persona_actual_id())
  on conflict (persona_id) do update set
    bloque = excluded.bloque, nivel = excluded.nivel, columna = excluded.columna, orden = excluded.orden,
    funcion = excluded.funcion, etiqueta = excluded.etiqueta, color = excluded.color,
    discreto = excluded.discreto,
    -- CAMBIO 0624: sin mandar el dato se conserva; con texto vacío se borra.
    distintivo = case when p_distintivo is null then o.distintivo else excluded.distintivo end,
    actualizado_at = now(), actualizado_por = excluded.actualizado_por;
end;
$$;

grant  execute on function fn_organigrama() to authenticated;
grant  execute on function fn_organigrama_guardar(uuid, text, int, text, text, text, boolean, int, int, text) to authenticated;
revoke execute on function fn_organigrama() from public, anon;
revoke execute on function fn_organigrama_guardar(uuid, text, int, text, text, text, boolean, int, int, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (624, 'el_organigrama_marca_una_especialidad_en_comun')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
