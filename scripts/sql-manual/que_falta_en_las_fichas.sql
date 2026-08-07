-- ############################################################################
-- ####  QUÉ FALTA EN LAS FICHAS — SOLO LEE, NO ESCRIBE NADA               ####
-- ############################################################################
--
-- PARA QUÉ
--   Ver de una vez qué datos faltan en las fichas de todo el equipo, en vez de
--   descubrirlos de a uno el día que hacen falta. Nació de encontrar que a Janis
--   le faltaba la fecha de nacimiento (2026-08-07): sin ella el sistema no sabe
--   cuándo entregarle su bono de onomástico, y eso no se iba a notar hasta que
--   llegara su mes y no pasara nada.
--
-- NO MUESTRA NINGÚN DATO PERSONAL, A PROPÓSITO
--   Dice QUÉ falta, nunca QUÉ dice el campo que sí está. Un listado de DNI,
--   cuentas bancarias y direcciones no debería existir fuera de la ficha de cada
--   persona, y menos pegado en un chat o guardado en una descarga. Para leer un
--   dato concreto está su ficha en `/admin/personas`, que registra quién la vio.
--
-- POR QUÉ CADA CAMPO IMPORTA — sin esto la lista es un cuestionario
--   · nacimiento .......... decide el mes del bono de onomástico (0165)
--   · documento ........... sale impreso en la declaración de ruta y en el cargo
--                           del bono; sin él salen con una raya en blanco
--   · nombre_dni .......... el nombre legal para contratos y memos, que no
--                           siempre coincide con el de uso
--   · banco / cuenta ...... sin esto no se le puede depositar la planilla
--   · celular ............. el único canal para avisar de un turno o un cambio
--   · emergencia .......... a quién llamar si le pasa algo en el trabajo.
--                           Obligatorio tenerlo, no es un dato de cortesía
--
-- CÓMO SE USA
--   Pégalo entero en el SQL Editor. Se llena desde `/admin/personas`, en la
--   ficha de cada persona.
-- ############################################################################

select
  p.apellidos || ', ' || p.nombres                             as persona,
  coalesce(s.codigo, '?')                                      as sede,
  p.tipo_vinculo                                               as vinculo,

  -- Cada columna dice «falta» o va vacía. Se lee de un vistazo cuál columna
  -- tiene huecos, que es la pregunta real: no «qué le falta a Janis» sino «a
  -- cuántas les falta la fecha de nacimiento».
  case when d.fecha_nacimiento  is null then 'falta' end       as nacimiento,
  case when p.documento         is null then 'falta' end       as documento,
  case when nullif(trim(coalesce(d.nombre_dni,   '')), '') is null then 'falta' end as nombre_legal,
  case when nullif(trim(coalesce(d.entidad_bancaria, '')), '') is null then 'falta' end as banco,
  case when nullif(trim(coalesce(d.numero_cuenta, '')), '') is null then 'falta' end as cuenta,
  case when nullif(trim(coalesce(d.celular,      '')), '') is null then 'falta' end as celular,
  case when nullif(trim(coalesce(d.emergencia_nombre,   '')), '') is null
         or nullif(trim(coalesce(d.emergencia_telefono, '')), '') is null
       then 'falta' end                                        as emergencia,

  -- Cuántos huecos tiene en total, para ordenar por quién necesita más trabajo.
  (case when d.fecha_nacimiento is null then 1 else 0 end)
  + (case when p.documento is null then 1 else 0 end)
  + (case when nullif(trim(coalesce(d.nombre_dni, '')), '') is null then 1 else 0 end)
  + (case when nullif(trim(coalesce(d.entidad_bancaria, '')), '') is null then 1 else 0 end)
  + (case when nullif(trim(coalesce(d.numero_cuenta, '')), '') is null then 1 else 0 end)
  + (case when nullif(trim(coalesce(d.celular, '')), '') is null then 1 else 0 end)
  + (case when nullif(trim(coalesce(d.emergencia_nombre, '')), '') is null
            or nullif(trim(coalesce(d.emergencia_telefono, '')), '') is null
          then 1 else 0 end)                                   as huecos

from personas p
left join sedes s            on s.id = p.sede_base_id
-- LEFT JOIN y no JOIN: quien nunca abrió su ficha no tiene fila en
-- `datos_personales`, y es justamente a quien más le falta. Con un JOIN normal
-- desaparecería de la lista, que es el peor resultado posible para una consulta
-- que existe para encontrar huecos.
left join datos_personales d on d.persona_id = p.id
where p.estado = 'activo'
order by huecos desc, p.apellidos;
