-- ¿A quién le falta entrar, y cuándo se le mandó el último correo?
--
-- Se pega en el SQL Editor de Supabase. La pantalla `/admin/cuentas` responde lo
-- mismo, pero esta consulta añade lo que la pantalla no puede mostrar: la HORA
-- del último correo que Auth despachó. Sirve para separar dos cosas que desde el
-- panel se ven igual — «el correo salió y la persona no lo abrió» de «el correo
-- nunca salió».
--
-- QUÉ SIGNIFICA CADA COLUMNA:
--
--   que_le_toca    · «invitación» si su correo no está confirmado (fue invitada
--                    y no aceptó); «recuperar acceso» si ya tenía clave puesta a
--                    mano. Son dos correos distintos porque Auth rechaza una
--                    segunda invitación a una cuenta confirmada (422 email_exists).
--   ultimo_correo  · lo más reciente entre la invitación y la recuperación.
--                    En blanco = Auth NUNCA le mandó nada.
--   entro          · siempre NUNCA en esta lista, por definición: aceptar la
--                    invitación ES iniciar sesión, así que quien entró ya no sale.
--
-- CÓMO SE LEE:
--   · ultimo_correo de hace minutos y entro NUNCA → el correo salió; falta que
--     ella lo abra. Revisar spam/promociones antes de reenviar otra vez.
--   · ultimo_correo en blanco → no salió nada. Ahí sí hay algo que arreglar.
--   · ultimo_correo viejo (de días) → el reenvío no llegó a esa persona; mirar
--     si el envío en tanda se cortó por el tope de correos por hora.

select p.nombres || ' ' || p.apellidos                       as persona,
       s.codigo                                              as sede,
       p.rol,
       u.email,
       case when u.email_confirmed_at is not null
            then 'recuperar acceso'
            else 'invitación'
       end                                                   as que_le_toca,
       to_char(greatest(u.invited_at, u.recovery_sent_at)
                 at time zone 'America/Lima',
               'DD-Mon HH24:MI')                             as ultimo_correo,
       coalesce(to_char(u.last_sign_in_at at time zone 'America/Lima',
                        'DD-Mon HH24:MI'),
                'NUNCA')                                     as entro
from personas p
join auth.users u on u.id = p.auth_user_id
left join sedes s on s.id = p.sede_base_id
where p.estado = 'activo'
  and u.last_sign_in_at is null
order by greatest(u.invited_at, u.recovery_sent_at) desc nulls first,
         p.apellidos;
