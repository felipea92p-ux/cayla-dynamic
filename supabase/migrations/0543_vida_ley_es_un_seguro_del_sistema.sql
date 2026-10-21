-- ============================================================================
-- 0543 · Vida Ley entra al catálogo como seguro del sistema
-- ============================================================================
-- QUÉ PROMETE
--
--   Que «Vida Ley» exista en la lista de tipos de seguro desde el primer día, con
--   su clave fija (`vida_ley`), y no dependa de que alguien de Desarrollo
--   Organizacional se acuerde de agregarla con «+ Agregar un seguro».
--
--   Es una sola fila en `seguros_tipos`: complementario (va además del seguro
--   principal), con póliza, sin vínculos automáticos, y marcada «del sistema».
--   Con ella ya se puede, desde las pantallas que existen desde la 0528: registrar
--   la póliza colectiva a todas las personas de una vez, leer el PDF de la póliza,
--   y bajar la lista de asegurados para el contador y La Positiva. No cambia ninguna
--   función, ninguna pantalla ni ninguna tabla.
--
-- QUÉ ASUME
--
--   · La 0528 está pegada: existe `seguros_tipos` con FOLA y EsSalud. (Lo dice la
--     consulta de «ANTES DE PEGAR».)
--   · Que Vida Ley es COMPLEMENTARIO y no principal. Si fuera principal, asignárselo
--     a una persona la sacaría de EsSalud: la 0528 lo dejó escrito justo con este
--     ejemplo. El check `seguro_tipo_complementario_con_poliza` ya lo obliga a llevar
--     póliza y a no tener vínculos automáticos.
--   · El texto legal es el que el repositorio ya trae, sin agregar nada: el reglamento
--     interno (`docs/reglamento-interno-de-trabajo.md`, derecho a Seguro de Vida Ley) y
--     `docs/reglamento-pendientes-de-construir.md` (punto 26) dicen D. Leg. 688,
--     modificado por el D.U. 044-2019 y la Ley 31408; 16 remuneraciones por muerte
--     natural y 32 por accidente o invalidez total; registro en el MTPE dentro de los
--     30 días. Si el contador corrige alguna cifra, se edita desde la pantalla
--     (la descripción de un tipo del sistema sí se puede editar).
--
-- POR QUÉ DEL SISTEMA, SI LA 0528 DICE QUE DO AGREGA LOS DEMÁS
--
--   FOLA y EsSalud son «del sistema» porque el código DEPENDE de ellos (practicante →
--   FOLA, planilla → EsSalud). Vida Ley no se calcula por vínculo, pero es la única
--   obligación de la lista cuyo incumplimiento se paga con patrimonio propio
--   (`docs/reglamento-pendientes-de-construir.md`, punto 26): no es un seguro más que
--   alguien «quizá» tenga. Tres razones concretas:
--     1. La CLAVE. El día que el sistema avise «persona en planilla sin Vida Ley»
--        —hoy espera al contador—, esa regla tiene que apuntar a un tipo que existe
--        con un nombre que no cambió. Si DO lo hubiera agregado a mano como «Seguro de
--        vida» su clave sería `seguro_de_vida`, y habría que adivinar cuál es la buena.
--        `vida_ley` es además la clave que ya usan las pruebas y el código de lectura.
--     2. Que no se archive sin querer. Un tipo del sistema no tiene botón «Archivar»
--        ni cambia de nombre; archivarlo apaga el registro de pólizas de ese seguro.
--     3. Que nadie lo escriba dos veces con dos nombres. Quien registra una póliza
--        elige de una lista: si la lista dice «Vida Ley» y «Seguro de vida», la mitad
--        del equipo queda en uno y la mitad en otro, y «quién está asegurado» deja de
--        tener una sola respuesta.
--
-- QUÉ NO HACE
--
--   · NO avisa quién está en planilla y no está en la póliza. Eso lo decidió Felipe
--     (2026-10-19, `docs/estado.md`): «la alerta de Vida Ley / SCTR espera la respuesta
--     del contador». Para un seguro complementario, «estar en él» es tener su póliza
--     vigente, y `aplica_a_vinculos` solo manda en los principales (0528, «QUÉ NO
--     HACE»). Lo más cerca que hay son el atajo «Las de planilla» al registrar la
--     póliza colectiva y la lista de asegurados.
--   · NO registra ninguna póliza ni dice cuántas personas van: eso lo hace DO con
--     el papel de La Positiva en la mano, y solo cuando se firme.
--   · NO toca planilla, pago ni `aporte_essalud`: la prima se paga a la aseguradora.
--
-- DECIDÍ:    Una fila del sistema, escrita por migración, con `on conflict (clave)`
--            que PROMUEVE a «del sistema» la que DO haya agregado a mano con esa misma
--            clave —sin pisarle su descripción— solo si tiene la forma correcta
--            (complementario, con póliza, activa). Repegar es seguro.
-- DESCARTÉ:  Que DO la agregue desde la pantalla. Cuesta un minuto y no pide SQL, pero
--            la clave depende del nombre que se teclee, y es la que la futura alerta
--            necesita encontrar. También descarté sembrar además una póliza: el papel
--            no está firmado, y una póliza inventada es peor que ninguna.
-- DESCARTÉ:  Hacerlo ya un hueco («planilla sin Vida Ley»). Está decidido que espera
--            al contador, y construirlo ahora exigiría reescribir `fn_seguros_equipo`
--            (la función de lectura que alimenta la pantalla de Seguros; hay que pedir su
--            md5 a producción antes) sin saber aún para qué vínculos es obligatorio
--            (¿entra quien está de prueba?).
-- SE ROMPE SI: DO ya había agregado «Vida Ley» y la dejó como seguro PRINCIPAL por
--            equivocación: la migración no la toca (no tiene la forma), la
--            comprobación del final lo muestra, y hay que corregirlo a mano porque
--            cambiar si es principal cambia lo que significa cada fila que ya la usa.
--            También si DO agregó «Seguro de vida» con otra clave: quedan DOS en la
--            lista; se archiva el suyo si no tiene pólizas (la pantalla no deja
--            archivar uno que las tenga: habría que pasarlas a «Vida Ley» con una
--            consulta).
--
-- ANTES DE PEGAR — UNA CONSULTA DE SOLO LECTURA A PRODUCCIÓN (SQL Editor)
--   Esperado: la tabla existe, los tipos de hoy son exactamente FOLA y EsSalud, no hay
--   pólizas de `vida_ley` y la 543 no figura aún en el registro. Si sale otra cosa, no
--   se para nada, pero se lee con esto en la mano: cualquier `vida_ley` que ya exista se
--   conserva (la migración solo la marca «del sistema»).
--
--   select
--     (select count(*) from pg_class where relname = 'seguros_tipos') as tabla_de_1,
--     (select string_agg(clave || ' · ' || nombre
--                        || case when de_sistema then ' (sistema)' else '' end
--                        || case when activo then '' else ' (archivado)' end,
--                        ' | ' order by clave) from seguros_tipos) as tipos_de_hoy,
--     (select count(*) from polizas_seguro where producto = 'vida_ley') as polizas_de_vida_ley,
--     (select string_agg(numero || ' · ' || nombre, ' | ' order by numero)
--        from migraciones_aplicadas where numero between 540 and 543) as registro_540_a_543;
--
-- CÓMO SE REVIERTE
--   Si todavía no hay ninguna póliza, asignación ni cambio que use `vida_ley`:
--     begin;
--     delete from seguros_tipos t
--      where t.clave = 'vida_ley' and t.de_sistema
--        and not exists (select 1 from polizas_seguro z where z.producto = 'vida_ley')
--        and not exists (select 1 from seguros_asignaciones a where a.tipo = 'vida_ley')
--        and not exists (select 1 from seguros_cambios c where 'vida_ley' in (c.de_tipo, c.a_tipo));
--     delete from migraciones_aplicadas where numero = 543;
--     commit;
--   Si ya hay pólizas, NO se borra (las pólizas apuntan a la clave): solo se le quita la
--   marca y DO vuelve a poder archivarla y renombrarla:
--     update seguros_tipos set de_sistema = false where clave = 'vida_ley';
--   Nada de planilla, asistencia ni pago lee esta fila: revertir solo cambia la lista.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final, que va la última porque el SQL Editor solo muestra el
--   resultado de la última. Esperado: una fila, `Vida Ley`, principal = false,
--   con_poliza = true, de_sistema = true, activo = true, y el registro «543 · …».
--   Y la prueba 422 en `db-tests` (afirma esa forma y que la clave se reserva).
-- ============================================================================

insert into seguros_tipos
  (clave, nombre, descripcion, principal, con_poliza, aplica_a_vinculos, texto_alta, texto_baja, de_sistema)
values
  ('vida_ley', 'Vida Ley',
   'Seguro de vida que la empresa debe contratar por cada persona de planilla desde el primer día '
   || '(D. Leg. 688, modificado por el D.U. 044-2019 y la Ley 31408). Capital: 16 remuneraciones por muerte natural '
   || 'y 32 por accidente o invalidez total. Es una póliza colectiva con un solo número: se registra a todas de una vez, '
   || 'y quien está en planilla y fuera de la póliza queda sin cobertura. Se registra en el MTPE dentro de los 30 días de firmada.',
   false, true, array[]::text[], null, null, true)
on conflict (clave) do update
   set de_sistema  = true,
       descripcion = coalesce(seguros_tipos.descripcion, excluded.descripcion)
 where not seguros_tipos.principal and seguros_tipos.con_poliza and seguros_tipos.activo;

insert into migraciones_aplicadas (numero, nombre)
values (543, 'vida_ley_es_un_seguro_del_sistema')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ─────────────────────────────────────────────────────────
select t.clave, t.nombre, t.principal, t.con_poliza, t.de_sistema, t.activo,
       (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 543) as registro
  from seguros_tipos t
 where t.clave = 'vida_ley';
