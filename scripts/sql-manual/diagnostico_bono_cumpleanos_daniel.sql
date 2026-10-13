-- Diagnóstico (SOLO LEE): ¿por qué Daniel Ruiz no ve su bono de cumpleaños?
-- Se pega en el SQL Editor de producción. No escribe nada.
--
-- Cada columna es una de las puertas por las que `fn_mi_bono_cumpleanos`
-- (0478/0479) puede contestar «no_aplica» o callarse. La que salga en rojo
-- (false / null / fuera de rango) es la causa.

select
  p.nombres || ' ' || p.apellidos                          as persona,
  p.estado,                                                -- tiene que ser 'activo'
  p.tipo_vinculo,                                          -- HASTA la 0518: 'practicante' ⇒ no_aplica. DESDE la 0518: solo 'rxh', 'prueba' y 'no_trabajador' quedan fuera
  p.en_planilla,                                           -- HASTA la 0518: false ⇒ fn_mi_bono_cumpleanos dice 'no_aplica'
  p.fecha_fin_contrato - p.fecha_ingreso + 1               as dias_de_contrato, -- DESDE la 0518: menos de 7 ⇒ no_aplica (null = indefinido, sí le toca)
  p.cuenta_de_servicio,                                    -- true ⇒ el tablero no lo lista
  p.auth_user_id is not null                               as tiene_login,     -- sin login no ve nada de /mio
  extract(month from d.fecha_nacimiento)::int              as mes_nacimiento,  -- null ⇒ 'sin_fecha' (Info no muestra nada)
  p.fecha_ingreso,                                         -- si ingresó DESPUÉS de octubre ⇒ 'no_aplica'
  p.fecha_fin_contrato,                                    -- si vence en octubre ⇒ el tablero no lo lista ⇒ 'no_aplica'
  fn_persona_le_corresponde_movilidad(p.id)                as en_el_tablero_de_documentos,
  exists (select 1 from firmas_escaneadas f where f.persona_id = p.id and f.imagen is not null)
                                                           as tiene_firma,     -- sin firma no puede firmar la constancia
  (select string_agg(anio || ' · ' || coalesce(fecha_firma::text, '—'), ', ')
     from documentos_firmados b
    where b.persona_id = p.id and b.tipo = 'bono' and b.anulado_at is null)
                                                           as constancias_de_bono
from personas p
left join datos_personales d on d.persona_id = p.id
where p.apellidos ilike '%ruiz%' and p.nombres ilike '%daniel%';

-- ¿Están las tres migraciones del bono en producción? (pedir numero Y nombre)
select numero, nombre, aplicada_at
  from migraciones_aplicadas
 where numero in (477, 478, 479)
 order by numero;
