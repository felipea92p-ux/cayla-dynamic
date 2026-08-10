-- ============================================================================
-- ¿A QUIÉN LE TOCA ARREGLARLE EL CORREO? — solo LEE. Pégala en el SQL Editor.
-- ============================================================================
--
-- ⚠️ ESTE RESULTADO SÍ LLEVA DATOS PERSONALES: nombres y correos. Es para
--    mirarlo y actuar, NO para pegarlo en una conversación ni en un ticket.
--    La medición sin PII es `mediciones_antes_de_validar.sql`; esta es el
--    siguiente paso, cuando aquella devuelve algo distinto de cero.
--
-- QUÉ RESPONDE. Las dos cosas que la medición del 2026-08-10 encontró en
-- producción y que no se pueden arreglar a ciegas:
--
--   · 2 correos guardados con alguna MAYÚSCULA. Para Supabase Auth «Ana@x.pe»
--     y «ana@x.pe» son la misma cuenta, pero el índice único de `personas` es
--     sensible a la caja, y la pantalla de la ficha compara en minúsculas
--     contra el valor crudo. Resultado: cada «Guardar ficha» de esa persona
--     terminaba en «La ficha se guardó, pero el correo no» —un error rojo,
--     permanente y falso—. La pantalla ya está corregida; lo que queda es bajar
--     el dato guardado.
--
--   · 1 correo SIN forma de correo. Esa persona figura como ficha completa,
--     sale así en el padrón que va al contador, y al intentar invitarla el
--     sistema responde «no tiene correo registrado», que es mentira: lo tiene,
--     está mal escrito. Son dos estados distintos y la pantalla los confunde.
--
-- LA COLUMNA QUE DECIDE QUÉ HACER es `tiene_cuenta`:
--   · sin cuenta  → se corrige desde /admin/datos-personales, que llama a
--                   fn_set_email y la 0198 lo permite.
--   · con cuenta  → el correo ES su usuario de acceso. Cambiarlo en la ficha NO
--                   cambia su login, y la 0198 rechaza el intento a propósito
--                   para que no queden dos correos distintos. Se hace desde
--                   /admin/cuentas.
--
-- NO CAMBIA NADA. Si quieres la sentencia que baja a minúsculas, pídemela: va
-- en una migración con su encabezado, no en un update suelto pegado a mano.
-- ============================================================================

select
  p.nombres || ' ' || p.apellidos                        as persona,
  s.codigo                                               as sede,
  p.estado,
  case
    when p.email is null then '(sin correo)'
    else p.email
  end                                                    as correo_guardado,
  case
    when p.email is not null
     and p.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
      then '⚠ NO tiene forma de correo'
    when p.email <> lower(p.email)
      then '⚠ tiene mayúsculas'
    else 'ok'
  end                                                    as que_le_pasa,
  case
    when p.email is not null and p.email <> lower(p.email)
      then lower(btrim(p.email))
    else null
  end                                                    as como_deberia_quedar,
  (p.auth_user_id is not null)                           as tiene_cuenta,
  case
    when p.auth_user_id is not null
      then 'Desde /admin/cuentas — su correo es su usuario de acceso'
    else 'Desde /admin/datos-personales — todavía no tiene acceso creado'
  end                                                    as donde_se_corrige
from personas p
left join sedes s on s.id = p.sede_base_id
where p.email is not null
  and (
        p.email <> lower(p.email)
     or p.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
      )
order by
  -- Primero el que ni siquiera es un correo: ese además ensucia el padrón.
  case when p.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then 0 else 1 end,
  p.apellidos;
