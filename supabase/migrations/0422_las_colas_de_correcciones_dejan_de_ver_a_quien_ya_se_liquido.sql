-- ============================================================================
-- 0422 · Las colas de Correcciones dejan de ver a quien ya se liquidó
-- ============================================================================
-- QUÉ PROMETE
--
--   `fn_dias_por_revisar` y `fn_marcas_apartadas` —las dos colas automáticas
--   que alimenta la pantalla Correcciones— dejan de listar para siempre el
--   marcaje sin resolver de alguien que ya cobró su liquidación. Antes no
--   filtraban por la persona en absoluto: un marcaje `pendiente_revision` o
--   una marca apartada de alguien liquidado hace un año seguía apareciendo.
--
-- EL DEFECTO
--
--   Correcciones respondía la misma pregunta —"¿a quién le puedo corregir un
--   marcaje?"— de dos formas distintas dentro de la MISMA pantalla. El
--   selector manual (`admin/correcciones/page.tsx`) excluía hasta hoy a TODO
--   cesado sin excepción, mientras estas dos colas nunca excluían a nadie. El
--   mismo commit que trae esta migración cambia también ese selector
--   (`personasCorregibles`, en el propio `page.tsx` — no necesita SQL propio:
--   ya le alcanza con `fn_personas_funciones`) para que responda la MISMA
--   regla que esta migración les pone a las colas: activo, o cesado pero
--   todavía sin liquidar. Ninguna de las dos mitades puede seguir
--   contestando distinto — es el mismo criterio que ya cerró la 0237 entre
--   tardanzas y faltas.
--
-- QUÉ ASUME
--
--   `fn_persona_liquidada` (0421) ya existe. Ninguna otra condición de las
--   dos funciones cambia: mismas columnas de retorno, mismo permiso de quién
--   puede llamarlas.
--
-- CÓMO SE REVIERTE
--
--   Quitar la línea `and not fn_persona_liquidada(...)` de cada una y volver
--   a pegar el resto tal como quedó en la 0384 (`fn_dias_por_revisar`) y en la
--   0304 (`fn_marcas_apartadas`).
-- ============================================================================

create or replace function fn_dias_por_revisar(p_limite integer default 50)
returns table (persona_id uuid, nombre text, sede text, fecha date, marcas integer,
               periodo_pagado boolean, motivo text)
language sql stable security definer set search_path = public
as $fn$
  with dias as (
    select m.persona_id,
           (p.nombres || ' ' || p.apellidos) as nombre,
           s.codigo as sede,
           (m.timestamp_marca at time zone 'America/Lima')::date as fecha,
           count(*)::int as marcas,
           bool_or(m.origen = 'auto_cierre') as hay_auto_cierre
    from marcajes m
    join personas p on p.id = m.persona_id
    join sedes s on s.id = p.sede_base_id
    where m.estado_revision = 'pendiente_revision'
      and m.anulada_at is null
      -- ⇩ CAMBIO 0422: quien ya cobró su liquidación deja de aparecer para
      -- siempre en esta cola. Mientras no se le liquide, sigue viéndose —
      -- puede tener un marcaje real por corregir antes de calcularla.
      and not fn_persona_liquidada(p.id)
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona()))
    group by m.persona_id, p.nombres, p.apellidos, s.codigo,
             (m.timestamp_marca at time zone 'America/Lima')::date
    order by (m.timestamp_marca at time zone 'America/Lima')::date desc,
             (p.nombres || ' ' || p.apellidos)
    limit greatest(p_limite, 1)
  )
  select d.persona_id, d.nombre, d.sede, d.fecha, d.marcas,
         exists (
           select 1 from periodos_planilla pp
           where pp.estado = 'pagado' and d.fecha between pp.fecha_ini and pp.fecha_fin
         ) as periodo_pagado,
         case
           when fn_dia_incoherente(d.persona_id, d.fecha) then 'secuencia_imposible'
           when d.hay_auto_cierre                         then 'auto_cierre_sin_confirmar'
           else 'sello_sin_levantar'
         end as motivo
  from dias d
  order by d.fecha desc, d.nombre;
$fn$;

grant execute on function fn_dias_por_revisar(int) to authenticated;
revoke execute on function fn_dias_por_revisar(int) from public, anon;

create or replace function fn_marcas_apartadas()
returns table (
  id                uuid,
  client_uuid       uuid,
  persona_id        uuid,
  persona           text,
  sede              text,
  tipo              text,
  timestamp_cliente timestamptz,
  fecha             date,
  ultimo_error      text,
  reportada_at      timestamptz
)
language sql stable security definer set search_path = public
as $fn$
  select m.id, m.client_uuid, m.persona_id,
         p.nombres || ' ' || p.apellidos,
         coalesce(s.codigo, '?'),
         m.tipo::text,
         m.timestamp_cliente,
         (m.timestamp_cliente at time zone 'America/Lima')::date,
         m.ultimo_error,
         m.reportada_at
    from marcas_apartadas m
    join personas p on p.id = m.persona_id
    left join sedes s on s.id = p.sede_base_id
   where m.resuelta_at is null
     -- ⇩ CAMBIO 0422: mismo criterio que fn_dias_por_revisar, arriba.
     and not fn_persona_liquidada(p.id)
     and ( fn_es_admin_o_lider() is true
        or ( fn_rol_actual() = 'supervisor_sede'::rol_usuario
             and p.sede_base_id = fn_sede_actual_persona() ) )
   order by m.timestamp_cliente;
$fn$;

grant execute on function fn_marcas_apartadas() to authenticated;
revoke execute on function fn_marcas_apartadas() from public, anon;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (422, 'las_colas_de_correcciones_dejan_de_ver_a_quien_ya_se_liquido')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

do $$
begin
  raise notice '0422 · fn_dias_por_revisar y fn_marcas_apartadas ya excluyen a quien se liquidó.';
end $$;
