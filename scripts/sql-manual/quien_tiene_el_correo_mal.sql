-- ============================================================================
-- ¿A QUIÉN LE TOCA ARREGLARLE EL CORREO? — solo LEE. Pégala en el SQL Editor.
-- ============================================================================
--
-- ⚠️ ESTE RESULTADO SÍ LLEVA DATOS PERSONALES: nombres y correos. Es para
--    mirarlo y actuar, NO para pegarlo en una conversación ni en un ticket.
--    La medición sin PII es `mediciones_antes_de_validar.sql`; esta es el
--    siguiente paso, cuando aquella devuelve algo distinto de cero.
--
-- QUÉ RESPONDE. Las tres cosas que no se pueden arreglar a ciegas:
--
--   · Correos guardados con alguna MAYÚSCULA. Para Supabase Auth «Ana@x.pe»
--     y «ana@x.pe» son la misma cuenta, pero el índice único de `personas` es
--     sensible a la caja, y la pantalla de la ficha compara en minúsculas
--     contra el valor crudo. Resultado: cada «Guardar ficha» de esa persona
--     terminaba en «La ficha se guardó, pero el correo no» —un error rojo,
--     permanente y falso—. La pantalla ya está corregida; lo que queda es bajar
--     el dato guardado. (Medido el 2026-08-10: 2 casos.)
--
--   · Correos SIN forma de correo. Esa persona figura como ficha completa,
--     sale así en el padrón que va al contador, y al intentar invitarla el
--     sistema responde «no tiene correo registrado», que es mentira: lo tiene,
--     está mal escrito. Son dos estados distintos y la pantalla los confunde.
--     (Medido el 2026-08-10: 1 caso.)
--
--   · DOS PERSONAS con el MISMO correo (comparando en minúsculas) — hallazgo
--     🔴 crítico #9 de la auditoría del 2026-09-03/04. Antes solo rompía la
--     invitación de la segunda. Hoy es mucho más caro: `fn_alertas_email_pendientes`
--     (0354/0356/0358/0359) despacha por correo el motivo de un auto-cierre,
--     el saldo de vacaciones o la fecha de fin de contrato — a la encargada,
--     a Desarrollo Organizacional y desde la 0359 a la propia persona. Si el
--     correo de Ana quedó guardado igual al de Bruno, el aviso de Ana LLEGA A
--     BRUNO, con su motivo, su fecha y su nombre completo. `mediciones_antes_de_
--     validar.sql` ya cuenta estas colisiones en agregado (sin nombres); esta
--     consulta es la que dice A QUIÉN corregir.
--
-- LA COLUMNA QUE DECIDE QUÉ HACER es `tiene_cuenta`:
--   · sin cuenta  → se corrige desde /admin/datos-personales, que llama a
--                   fn_set_email y la 0198 lo permite.
--   · con cuenta  → el correo ES su usuario de acceso. Cambiarlo en la ficha NO
--                   cambia su login, y la 0198 rechaza el intento a propósito
--                   para que no queden dos correos distintos. Se hace desde
--                   /admin/cuentas.
--
-- Para una colisión, arregla UNA de las dos personas — la que de verdad no es
-- dueña de ese correo — no las dos: si le vacías el correo a ambas, la que sí
-- lo tenía bien deja de poder entrar y de recibir sus propios avisos.
--
-- NO CAMBIA NADA. Si quieres la sentencia que baja a minúsculas, pídemela: va
-- en una migración con su encabezado, no en un update suelto pegado a mano.
-- ============================================================================

with colisiones as (
  select lower(btrim(email)) as correo_lower
  from personas
  where email is not null
  group by 1
  having count(*) > 1
)
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
    when lower(btrim(p.email)) in (select correo_lower from colisiones)
      then '🔴 mismo correo que otra persona — despacha alertas a quien no debe'
    when p.email <> lower(p.email)
      then '⚠ tiene mayúsculas'
    else 'ok'
  end                                                    as que_le_pasa,
  case
    when lower(btrim(p.email)) in (select correo_lower from colisiones)
      then 'lo comparte con: ' || (
        select string_agg(p2.nombres || ' ' || p2.apellidos || ' (' || p2.estado || ')', ' · ' order by p2.apellidos)
        from personas p2
        where p2.id <> p.id and lower(btrim(p2.email)) = lower(btrim(p.email))
      )
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
     or lower(btrim(p.email)) in (select correo_lower from colisiones)
      )
order by
  -- Primero el que ni siquiera es un correo (ensucia el padrón), luego la
  -- colisión (es la que de verdad entrega datos a otra persona), y al final
  -- la mayúscula (rompe el guardado, pero no manda nada a nadie).
  case
    when p.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then 0
    when lower(btrim(p.email)) in (select correo_lower from colisiones) then 1
    else 2
  end,
  p.apellidos;
