-- ############################################################################
-- ####  A QUIÉN LE FALTA FIRMAR — SOLO LEE, NO ESCRIBE NADA               ####
-- ############################################################################
--
-- PARA QUÉ
--   La misma lista que muestra `/admin/documentacion`, pero en el SQL Editor:
--   quién no tiene su declaración de ruta y a quién le falta el cargo del
--   onomástico. Sirve para saber cuántas hojas van a salir antes de darle a
--   «Imprimir las que faltan», y para cruzar contra lo que se ve en pantalla.
--
-- POR QUÉ SALE DE `fn_documentos_tablero()` Y NO DE UN SELECT PROPIO
--   Porque es la función que ya responde esa pregunta para la pantalla. Escribir
--   aquí otra consulta que decida por su cuenta quién está pendiente daría dos
--   verdades que se pueden contradecir —y el día que se contradigan, nadie
--   sabría cuál creer—. Si esta lista y la pantalla difieren, es un fallo real,
--   no una diferencia de criterio.
--
--   Eso también significa que hereda TODAS sus reglas, que es lo que se quiere:
--   no lista a los RxH (no cobran movilidad, 0117), ni a quien firma por CAYLA
--   (0162), ni a quien termina contrato este mes, ni reclama el bono a quien
--   cumplió años antes de que la política existiera (0165).
--
-- CÓMO SE USA
--   Pégalo entero en el SQL Editor. No pide parámetros ni modifica nada.
-- ############################################################################

-- `fn_documentos_tablero` exige sesión de admin —solo Desarrollo Organizacional
-- ve quién debe papeles— y el SQL Editor no la trae. Se le presta una, igual que
-- hace `comparar_movilidad_0166.sql`.
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and auth_user_id is not null limit 1), false) as _sesion_prestada;

with meses(n, nombre) as (values
  (1,'enero'),(2,'febrero'),(3,'marzo'),(4,'abril'),(5,'mayo'),(6,'junio'),
  (7,'julio'),(8,'agosto'),(9,'septiembre'),(10,'octubre'),(11,'noviembre'),(12,'diciembre'))
select
  t.persona,
  t.sede,

  case t.estado
    when 'sin_ruta' then '⚠ falta firmar'
    when 'se_nego'  then '⚠ se negó — no cobra movilidad'
    else 'firmada el ' || to_char(t.ruta_firmada_el, 'DD/MM/YYYY')
       || case when t.ruta_desfasada
               then ' ⚠ declara S/ ' || t.ruta_monto || ' y hoy se paga otra tarifa'
               else '' end
  end                                                        as declaracion_de_ruta,

  case t.bono_estado
    when 'ok'        then 'firmado el ' || to_char(t.bono_firmada_el, 'DD/MM/YYYY')
    when 'este_mes'  then '⚠ cumple este mes — entregar y firmar'
    when 'vencido'   then '⚠ cumplió en ' || m.nombre || ' y no hay cargo'
    when 'proximo'   then 'cumple en ' || m.nombre
    when 'sin_fecha' then 'falta su fecha de nacimiento en la ficha'
    when 'no_aplica' then 'este año no le corresponde'
    else t.bono_estado
  end                                                        as cargo_de_cumpleanos,

  -- Cuántas hojas saldrían por esta persona si imprimes los dos lotes ahora.
  (case when t.estado = 'sin_ruta' then 1 else 0 end)
  + (case when t.bono_estado in ('este_mes','vencido') then 1 else 0 end) as hojas_pendientes

from fn_documentos_tablero() t
left join meses m on m.n = t.bono_mes
-- Primero quien debe algo: esta lista se lee para actuar, no para archivar.
order by
  (case when t.estado = 'sin_ruta' then 0 else 1 end),
  (case when t.bono_estado in ('este_mes','vencido') then 0 else 1 end),
  t.persona;
