-- ============================================================================
-- 0623 — El organigrama vive en el sistema
-- ============================================================================
--
-- QUÉ PROMETE
--   Un organigrama que se arma desde las fichas: el nombre y la foto salen de
--   `personas`, y quien pasa a inactivo desaparece solo del dibujo. Desarrollo
--   Organizacional (DO) decide dónde va cada quien, con qué función se muestra y
--   con quién se une. Mientras no esté publicado lo ve solo DO; publicado, lo ve
--   todo el equipo con sesión.
--
-- QUÉ ASUME
--   `personas` (0001), `fn_persona_actual_id()` y `fn_es_admin_o_lider()` (0078).
--   No lee ni escribe cargo, rol, sede, sueldo ni ningún cálculo de pago.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- La «función» del organigrama es un dato aparte del cargo de la ficha. Se
-- decidió el 2026-11-25: varios cargos cambian y antes de tocarlos hay que
-- revisar contratos (bajar de categoría puede reclamarse como hostilidad,
-- art. 30 del D.S. 003-97-TR). Dibujar no puede cambiar una ficha.
--
-- La misma tarde se decidió que quien asesora o es externo aparece SIN MANDO:
-- varios cobran por honorarios, y un papel de la propia empresa que les dibuja
-- gente a cargo es un indicio de relación laboral. Esa decisión no queda como
-- costumbre: ninguna línea de «equipo» (llena) puede tocar a alguien con
-- etiqueta «asesoría» o «externo»; solo la de «asesoría» (punteada).
--
-- El color de una tarjeta (verde, azul o naranja, que usa el token «ambar») es
-- solo un resalte que DO elige: no dice quién manda a quién. Eso lo dicen la
-- función escrita, la etiqueta y las líneas.
--
-- La forma del dibujo es dato y no código: bloques en filas, y dentro de cada
-- bloque niveles y, si hace falta alinear, columnas. Así una persona nueva se
-- ubica desde la pantalla, sin desplegar nada y sin nombres escritos en git.
--
-- ── SE ROMPE SI ─────────────────────────────────────────────────────────────
--   La función del organigrama y el cargo de la ficha dicen cosas distintas y
--   alguien toma el dibujo como el cargo oficial. Por eso nace sin publicar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   drop function if exists fn_organigrama();
--   drop function if exists fn_organigrama_guardar(uuid, text, int, text, text, text, boolean, int, int);
--   drop function if exists fn_organigrama_quitar(uuid);
--   drop function if exists fn_organigrama_linea(uuid, uuid, text);
--   drop function if exists fn_organigrama_publicar(boolean);
--   drop table if exists organigrama_lineas, organigrama_personas,
--                        organigrama_bloques, organigrama_publicacion;
--   drop function if exists fn_organigrama_cuida_mando();
--   delete from migraciones_aplicadas where numero = 623;
-- ============================================================================

-- ── Los bloques: los equipos que se dibujan, y dónde ────────────────────────
create table if not exists organigrama_bloques (
  clave       text primary key check (clave ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 60),
  fila        smallint not null check (fila between 1 and 12),
  orden       smallint not null check (orden between 1 and 12),
  -- Cuánto ancho toma frente a sus vecinos de fila.
  ancho       numeric(3,2) not null default 1 check (ancho between 0.5 and 4),
  -- null = cada nivel reparte sus tarjetas solo; con número, es una cuadrícula
  -- y cada persona dice en qué columna va.
  columnas    smallint check (columnas between 1 and 4),
  -- Se dibuja en segundo plano (título tenue).
  discreto    boolean not null default false,
  -- En el celular los bloques se apilan en este orden.
  orden_movil smallint not null default 100 check (orden_movil between 1 and 999),
  constraint organigrama_bloque_un_sitio unique (fila, orden)
);
comment on table organigrama_bloques is
  'Los equipos del organigrama y su posición en el dibujo (0623). Solo se lee por fn_organigrama.';

insert into organigrama_bloques (clave, nombre, fila, orden, ancho, columnas, discreto, orden_movil) values
  ('sistemas',  'Sistemas',                  1, 1, 1,    null, false, 20),
  ('direccion', 'Dirección',                 1, 2, 2,    2,    false, 10),
  ('lima',      'Lima · taller y tienda',    2, 1, 1,    null, false, 40),
  ('arequipa',  'Arequipa · tienda',         2, 2, 1.35, 2,    false, 30),
  ('do',        'Desarrollo organizacional', 2, 3, 1,    2,    true,  60),
  ('trujillo',  'Trujillo · tienda',         3, 1, 1,    null, false, 50)
on conflict (clave) do nothing;

-- ── Quién va dónde ──────────────────────────────────────────────────────────
create table if not exists organigrama_personas (
  persona_id      uuid primary key references personas(id),
  bloque          text not null references organigrama_bloques(clave),
  nivel           smallint not null check (nivel between 1 and 9),
  columna         smallint check (columna between 1 and 4),
  orden           smallint not null default 1 check (orden between 1 and 30),
  funcion         text not null check (char_length(btrim(funcion)) between 2 and 120),
  etiqueta        text check (etiqueta in ('apoyo_lider', 'asesoria', 'externo')),
  color           text check (color in ('verde', 'azul', 'ambar')),
  discreto        boolean not null default false,
  actualizado_at  timestamptz not null default now(),
  actualizado_por uuid references personas(id)
);
comment on table organigrama_personas is
  'Dónde aparece cada integrante en el organigrama y con qué función (0623). La función NO es el cargo de la ficha. Escritura solo por fn_organigrama_*.';

-- Dos personas en la misma casilla de una cuadrícula es un dibujo imposible.
create unique index if not exists idx_organigrama_una_casilla
  on organigrama_personas (bloque, nivel, columna) where columna is not null;

-- ── Las líneas ──────────────────────────────────────────────────────────────
create table if not exists organigrama_lineas (
  desde uuid not null references organigrama_personas(persona_id) on delete cascade,
  hasta uuid not null references organigrama_personas(persona_id) on delete cascade,
  tipo  text not null check (tipo in ('equipo', 'asesoria')),
  primary key (desde, hasta),
  constraint organigrama_linea_entre_dos check (desde <> hasta)
);
comment on table organigrama_lineas is
  'Quién se une con quién (0623): «equipo» es línea llena; «asesoria», punteada y sin mando.';

-- Una sola línea por par, la mire quien la mire.
create unique index if not exists idx_organigrama_linea_por_par
  on organigrama_lineas (least(desde, hasta), greatest(desde, hasta));

-- ── Publicado o no ──────────────────────────────────────────────────────────
create table if not exists organigrama_publicacion (
  unica           boolean primary key default true check (unica),
  publicado       boolean not null default false,
  actualizado_at  timestamptz not null default now(),
  actualizado_por uuid references personas(id)
);
comment on table organigrama_publicacion is
  'Una sola fila: si el organigrama ya lo ve todo el equipo (0623).';
insert into organigrama_publicacion (unica, publicado) values (true, false)
on conflict (unica) do nothing;

-- Todo se lee y se escribe por funciones: RLS encendida y sin políticas.
alter table organigrama_bloques     enable row level security;
alter table organigrama_personas    enable row level security;
alter table organigrama_lineas      enable row level security;
alter table organigrama_publicacion enable row level security;

-- ── El candado de «asesoría sin mando» entre dos tablas ─────────────────────
create or replace function fn_organigrama_cuida_mando()
returns trigger
language plpgsql set search_path = public
as $$
begin
  if exists (
    select 1
      from organigrama_lineas l
      join organigrama_personas o on o.persona_id in (l.desde, l.hasta)
     where l.tipo = 'equipo'
       and o.etiqueta in ('asesoria', 'externo')
  ) then
    raise exception 'Quien asesora o es externo no lleva línea de equipo: únelo con línea de asesoría.'
      using errcode = '23514';
  end if;
  return null;
end;
$$;

drop trigger if exists organigrama_mando_en_lineas on organigrama_lineas;
create trigger organigrama_mando_en_lineas
  after insert or update on organigrama_lineas
  for each statement execute function fn_organigrama_cuida_mando();

drop trigger if exists organigrama_mando_en_personas on organigrama_personas;
create trigger organigrama_mando_en_personas
  after insert or update on organigrama_personas
  for each statement execute function fn_organigrama_cuida_mando();

-- ── Leer ────────────────────────────────────────────────────────────────────
-- Devuelve solo nombre, foto y lo que DO escribió para el dibujo: nada de
-- documento, sueldo, rol ni contacto.
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
               'color', o.color, 'discreto', o.discreto)
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

-- ── Ubicar o cambiar a alguien ──────────────────────────────────────────────
create or replace function fn_organigrama_guardar(
  p_persona_id uuid,
  p_bloque     text,
  p_nivel      int,
  p_funcion    text,
  p_etiqueta   text    default null,
  p_color      text    default null,
  p_discreto   boolean default false,
  p_columna    int     default null,
  p_orden      int     default 1
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_columnas smallint;
  v_etiqueta text := nullif(btrim(coalesce(p_etiqueta, '')), '');
  v_color    text := nullif(btrim(coalesce(p_color, '')), '');
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
    (persona_id, bloque, nivel, columna, orden, funcion, etiqueta, color, discreto, actualizado_at, actualizado_por)
  values
    (p_persona_id, p_bloque, p_nivel, p_columna, coalesce(p_orden, 1), btrim(p_funcion), v_etiqueta,
     v_color, coalesce(p_discreto, false), now(), fn_persona_actual_id())
  on conflict (persona_id) do update set
    bloque = excluded.bloque, nivel = excluded.nivel, columna = excluded.columna, orden = excluded.orden,
    funcion = excluded.funcion, etiqueta = excluded.etiqueta, color = excluded.color,
    discreto = excluded.discreto, actualizado_at = now(), actualizado_por = excluded.actualizado_por;
end;
$$;

-- ── Quitar del dibujo (la ficha no se toca) ─────────────────────────────────
create or replace function fn_organigrama_quitar(p_persona_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede cambiar el organigrama.';
  end if;
  delete from organigrama_personas where persona_id = p_persona_id;
end;
$$;

-- ── Unir o separar a dos personas (`p_tipo` nulo = quitar la línea) ─────────
create or replace function fn_organigrama_linea(p_desde uuid, p_hasta uuid, p_tipo text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede cambiar el organigrama.';
  end if;
  if p_desde is null or p_hasta is null or p_desde = p_hasta then
    raise exception 'Una línea une a dos personas distintas.';
  end if;
  if p_tipo is not null and p_tipo not in ('equipo', 'asesoria') then
    raise exception 'Tipo de línea desconocido.';
  end if;
  if p_tipo is not null and (
       select count(*) from organigrama_personas where persona_id in (p_desde, p_hasta)) <> 2 then
    raise exception 'Las dos personas tienen que estar ubicadas en el organigrama.';
  end if;

  delete from organigrama_lineas
   where least(desde, hasta) = least(p_desde, p_hasta)
     and greatest(desde, hasta) = greatest(p_desde, p_hasta);

  if p_tipo is not null then
    insert into organigrama_lineas (desde, hasta, tipo) values (p_desde, p_hasta, p_tipo);
  end if;
end;
$$;

-- ── Publicar o volver a borrador ────────────────────────────────────────────
create or replace function fn_organigrama_publicar(p_publicar boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede publicar el organigrama.';
  end if;
  if p_publicar is null then
    raise exception 'Indica si se publica o vuelve a borrador.';
  end if;
  insert into organigrama_publicacion (unica, publicado, actualizado_at, actualizado_por)
  values (true, p_publicar, now(), fn_persona_actual_id())
  on conflict (unica) do update set
    publicado = excluded.publicado, actualizado_at = now(), actualizado_por = excluded.actualizado_por;
end;
$$;

grant  execute on function fn_organigrama() to authenticated;
grant  execute on function fn_organigrama_guardar(uuid, text, int, text, text, text, boolean, int, int) to authenticated;
grant  execute on function fn_organigrama_quitar(uuid) to authenticated;
grant  execute on function fn_organigrama_linea(uuid, uuid, text) to authenticated;
grant  execute on function fn_organigrama_publicar(boolean) to authenticated;
revoke execute on function fn_organigrama() from public, anon;
revoke execute on function fn_organigrama_guardar(uuid, text, int, text, text, text, boolean, int, int) from public, anon;
revoke execute on function fn_organigrama_quitar(uuid) from public, anon;
revoke execute on function fn_organigrama_linea(uuid, uuid, text) from public, anon;
revoke execute on function fn_organigrama_publicar(boolean) from public, anon;
revoke execute on function fn_organigrama_cuida_mando() from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (623, 'el_organigrama_vive_en_el_sistema')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
