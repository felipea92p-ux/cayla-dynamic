-- ============================================================================
-- 0231 — Marcar después del contrato deja de pasar en silencio
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que el sistema diga, el mismo día, quién sigue marcando después de la fecha
-- en que su contrato a plazo venció.
--
-- El artículo 8.8 a) del Reglamento recoge el artículo 77 de la LPCL sin
-- matices: el contrato sujeto a modalidad se considera de duración
-- indeterminada «si la colaboradora continúa laborando después de la fecha de
-- vencimiento del plazo estipulado».
--
-- No hace falta que nadie firme nada ni que nadie reclame. Basta con que venga
-- a trabajar un día más. Y ese día queda registrado en `marcajes`, que es
-- append-only: la prueba de la desnaturalización la produce el propio sistema,
-- todos los días, y hasta hoy no la miraba nadie.
--
-- ── POR QUÉ NO BASTA CON LO QUE YA HABÍA ────────────────────────────────────
--
-- `fn_contratos_por_vencer` (0144) existe y el Dashboard la usa a 90 días. Pero
-- responde a otra pregunta: «¿a quién le vence pronto?». Esta responde «¿a
-- quién se le venció Y SIGUE VINIENDO?», que no es un aviso anticipado sino un
-- hecho consumado con consecuencia legal.
--
-- La diferencia importa porque las dos se leen distinto. Un contrato por vencer
-- se resuelve renovando o no renovando. Uno desnaturalizado ya no se resuelve:
-- se reconoce. Mezclarlas en la misma lista invita a tratar la segunda como si
-- todavía se pudiera evitar.
--
-- ── QUÉ SE CUENTA Y QUÉ NO ──────────────────────────────────────────────────
--
--   · Se cuenta el marcaje POSTERIOR a `fecha_fin_contrato`, no el de ese
--     mismo día. La pantalla de Equipo dice de ese campo «el último día que
--     trabaja por contrato — el último día que viene, no el siguiente», así que
--     marcar ESE día es cumplir el contrato, no excederlo.
--   · No se cuentan los marcajes anulados. Una marca anulada es una que no
--     ocurrió, y fundar una desnaturalización en ella sería fundarla en algo
--     que el propio sistema ya declaró inexistente.
--   · Se mira `marcajes` y no `jornadas` a propósito: `jornadas` es un resumen
--     derivado que mantiene un trigger, y aquí lo que hace falta es el hecho
--     bruto de que vino.
--
-- ── QUÉ ASUME, Y ES LO ÚNICO DISCUTIBLE ─────────────────────────────────────
--
-- Que una renovación se registra moviendo `fecha_fin_contrato` hacia adelante,
-- como manda el numeral 8.6 y hace `fn_set_fin_contrato` (0144). Si alguien
-- renueva en papel y no toca el sistema, esta función la señalará igual — y esa
-- es la respuesta correcta: desde fuera, un contrato renovado que no consta
-- registrado no se distingue de uno vencido, y el numeral 8.6 obliga a
-- registrarlo.
--
-- Lo contrario —callar por si acaso hubo un papel— dejaría el aviso valiendo
-- exactamente cero.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- `drop function fn_contratos_desnaturalizados()`. No toca datos ni cambia
-- ninguna función existente.
-- ============================================================================

create or replace function fn_contratos_desnaturalizados()
returns table(
  persona_id              uuid,
  nombre                  text,
  sede                    text,
  fecha_fin_contrato      date,
  primer_dia_despues      date,
  ultimo_dia_marcado      date,
  dias_marcados_despues   int
)
language sql stable security definer set search_path = public as $$
  with despues as (
    select m.persona_id,
           -- La fecha se saca en hora de Lima, no en UTC: una marca de las
           -- 7 p.m. del último día de contrato es de ESE día, y leída en UTC
           -- caería en el siguiente y fabricaría una desnaturalización que no
           -- ocurrió.
           (m.timestamp_marca at time zone 'America/Lima')::date as dia
      from marcajes m
      join personas p on p.id = m.persona_id
     where m.anulada_at is null
       and p.fecha_fin_contrato is not null
       and (m.timestamp_marca at time zone 'America/Lima')::date > p.fecha_fin_contrato
     group by m.persona_id, (m.timestamp_marca at time zone 'America/Lima')::date
  )
  select p.id,
         (p.nombres || ' ' || p.apellidos)::text,
         coalesce(s.codigo, '—')::text,
         p.fecha_fin_contrato,
         min(d.dia),
         max(d.dia),
         count(*)::int
    from despues d
    join personas p on p.id = d.persona_id
    left join sedes s on s.id = p.sede_base_id
   where p.estado = 'activo'
     -- Solo lo ve quien puede hacer algo con ello. No es una lista de faltas,
     -- pero sí dice quién tiene el contrato en el aire.
     and fn_es_admin_o_lider() is true
   group by p.id, p.nombres, p.apellidos, s.codigo, p.fecha_fin_contrato
   order by min(d.dia);
$$;

comment on function fn_contratos_desnaturalizados() is
  'Art. 8.8 a) del RIT y art. 77 de la LPCL: quien sigue marcando despues de que su contrato a plazo vencio. Cuenta dias marcados, no marcajes.';

grant execute on function fn_contratos_desnaturalizados() to authenticated, service_role;
revoke execute on function fn_contratos_desnaturalizados() from public;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (231, 'marcar_despues_del_contrato_deja_de_pasar_en_silencio')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- `desnaturalizados` es el número que importa, y ojalá salga 0. Si sale más,
-- cada una de esas personas tiene hoy un contrato indeterminado por el artículo
-- 77, haya firmado alguien lo que haya firmado.
--
-- `con_fecha_de_fin` y `vencen_en_90_dias` van al lado para dar contexto: con
-- unos veinte contratos venciendo el 31-12, conviene ver los tres números
-- juntos y no solo el que asusta.
select
  (select count(*) from personas
    where estado = 'activo' and fecha_fin_contrato is not null)              as con_fecha_de_fin,
  (select count(*) from personas
    where estado = 'activo' and fecha_fin_contrato is not null
      and fecha_fin_contrato between fn_hoy_lima() and fn_hoy_lima() + 90)   as vencen_en_90_dias,
  (select count(*) from personas p
    where p.estado = 'activo' and p.fecha_fin_contrato is not null
      and exists (select 1 from marcajes m
                   where m.persona_id = p.id and m.anulada_at is null
                     and (m.timestamp_marca at time zone 'America/Lima')::date
                         > p.fecha_fin_contrato))                            as desnaturalizados;
