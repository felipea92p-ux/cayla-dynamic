-- ============================================================================
-- 0548 — Los avisos por correo que fallaron para siempre tienen salida
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE
--   Que un aviso de `alertas` que el despacho ya no va a enviar solo deje de
--   ser un callejón sin salida. Hay DOS formas de quedar así, y la tarjeta
--   «Sistema» de la Bandeja cuenta las dos:
--     · DEFINITIVA: agotó sus tres intentos. La fila queda 'fallido' (o
--       'procesando' si la ejecución murió con ella en vuelo) PARA SIEMPRE:
--       `fn_alertas_despacho_resumen` (0362) la cuenta en
--       `fallidas_definitivas` —sin ventana de fecha, así que no se va nunca—,
--       `fn_alerta_despachable` no la deja salir y no existe función ni
--       pantalla para reponerla ni para darla por cerrada.
--     · CADUCADA: no salió y le pasaron los 7 días de ventana con intentos
--       que le quedaban (`caducadas` del mismo resumen). Tampoco se va nunca.
--   Al 2026-10-25 la tarjeta cuenta 61 definitivas, por un 403 de Resend
--   (dominio sin verificar) y por «sin líder de equipo con correo». Y el
--   propio arreglo de la ruta (cortar el lote cuando el canal está caído)
--   deja filas 'pendiente' esperando días: sin esta migración esas filas
--   terminan caducadas, que es otro callejón. La tarjeta no puede volver a
--   decir «nada pendiente» mientras esas filas sigan contando.
--
--   Esta migración agrega cinco cosas:
--
--   a) El estado 'descartada' en `alertas_estado_check`: «una persona (o esta
--      función) miró este aviso y decidió que ya no hay nada que enviar».
--   b) `fn_alerta_sigue_vigente(tipo, persona_id, payload)`: ayudante interno
--      que contesta UNA pregunta —¿el hecho que motivó este aviso sigue
--      siendo cierto hoy?— por tipo de aviso.
--   c) `fn_alerta_sin_salida(estado, intentos, procesando_desde, enviado_at,
--      created_at)`: ayudante interno que dice cuáles filas son
--      «definitivas o caducadas» y no están en vuelo. Existe para que la
--      condición se escriba UNA vez: la usan el bloqueo y la resolución.
--   d) `fn_alertas_resolver_fallidas(p_ejecutar boolean default false)`: para
--      cada fila sin salida, la REENCOLA si el aviso todavía es útil y la
--      DESCARTA si no. Con `p_ejecutar = false` no escribe nada y dice lo que
--      haría.
--   e) `fn_alertas_devolver_intento(p_id uuid)`: interna, solo la ruta con la
--      llave de servicio. Devuelve el intento gastado de una fila 'fallido'
--      cuando el fallo fue del canal y no de la fila (ver «Por qué» abajo).
--
-- POR QUÉ NO BASTABA UN UPDATE
--   · Reencolarlas todas tal cual manda hechos viejos: una jornada que ya se
--     corrigió («salida cerrada automáticamente» de una persona cuyo marcaje
--     DO ya revisó), un «vence en N días» que dejó de ser verdad. Un correo
--     que dice algo falso a una líder de equipo es peor que ningún correo —
--     la regla de esta casa sobre falsos positivos.
--   · Marcarlas 'enviado' mentiría a la auditoría: `enviado_at` y el estado
--     'enviado' son la prueba de que alguien recibió un correo. Un 'enviado'
--     que no salió es un registro falso, y no hay vuelta atrás de eso.
--   · Descartar todo lo viejo tampoco: un aviso de contrato por vencer o de
--     vacaciones se genera UNA vez por hecho (el `not exists` de la 0371
--     ignora el estado) y el hecho sigue siendo cierto mientras el contrato
--     no se renueve. Medido en una base de prueba: un contrato que vence en 3
--     días, con su aviso de hace 10 días descartado, no se vuelve a avisar
--     nunca —justo cuando es más urgente—. Esos dos tipos se reencolan con
--     ventana renovada (ver abajo).
--
-- QUÉ ASUME
--   · Que `alertas_estado_check` es el único freno de valores de `estado`
--     (0001 lo creó inline; la 0362 lo recreó con el nombre explícito). Las
--     filas existentes son 'pendiente'|'procesando'|'enviado'|'fallido', así
--     que cumplen el check ampliado: no hace falta NOT VALID.
--   · Que la ventana de despacho vive en UN solo sitio: `fn_alerta_despachable`
--     (0362). La resolución NO escribe «7 días» para decidir si un aviso
--     todavía puede salir: le pregunta a esa definición. (La definición de
--     «caducada» sí repite los 7 días y el límite por fecha de la 0354: está
--     COPIADA tal cual de `fn_alertas_despacho_resumen`, porque el botón tiene
--     que resolver exactamente lo que la tarjeta cuenta, ni una fila más ni
--     una menos. Si la ventana cambia, cambian las dos —y esta, con ellas.)
--   · Que el despacho corre UNA vez al día (cron 07:00 Lima). Por eso la
--     ventana se mide como la verá el despacho de MAÑANA y no como está hoy:
--     una fila de 6 días y 20 horas «cabe» hoy, pero cuando llegue el
--     despacho ya no (medido: pasaba a caducada 10 horas después de
--     reencolarla, un fantasma que la tarjeta cuenta y nadie puede resolver).
--   · Que `fn_vacaciones_saldo_interno` (0357) y los payloads que arman
--     `fn_auto_cierre` (0327) y `fn_generar_alertas_vencimiento` (0371) siguen
--     teniendo las claves de hoy: `ts_cierre`; `persona_id`, `fecha_fin_contrato`
--     y `evento`; `persona_id` y `vence_el`.
--   · Que el permiso es el de `fn_alertas_despacho_resumen` —
--     `fn_es_admin_o_lider()`, o sea admin y lider_do—, que es lo mismo que
--     `puedeVerSaludDeAlertas` en `packages/shared/src/permisos.ts` (DO). Quien
--     ve la tarjeta es quien puede resolver lo que la tarjeta cuenta: la base
--     y la pantalla dicen lo mismo, y la líder de equipo no ve ninguna de las
--     dos.
--   · Que la ruta `/api/alertas-encargadas` calcula los días de un aviso de
--     vencimiento AL ENVIAR (`plazo-al-enviar.ts`), contra la fecha del
--     payload y no contra `created_at`: por eso renovar la ventana de un
--     aviso viejo no hace que el correo diga un plazo viejo.
--   · Que las filas a resolver son pocas (decenas): bloquearlas no estorba.
--
-- QUÉ HACE `fn_alertas_resolver_fallidas`
--   Considera las filas «sin salida» (`fn_alerta_sin_salida`):
--     · las DEFINITIVAS: `estado in ('fallido','procesando') and intentos >= 3`
--       —la misma condición del resumen—, y
--     · las CADUCADAS: `estado <> 'enviado' and enviado_at is null and
--       intentos < 3 and created_at <= now() - 7 días and created_at >= desde
--       que existe la cola (0354)` —la misma condición del resumen, límite
--       inferior incluido—,
--   salvo una fila 'procesando' con `procesando_desde` de menos de una hora:
--   está en vuelo en el despacho de ahora mismo y no se toca. Para cada una:
--     1. VIGENTE y dentro de la ventana de mañana → REENCOLAR: estado
--        'pendiente', intentos 0, procesando_desde nulo. `created_at` queda
--        intacto.
--     2. VIGENTE, FUERA de la ventana y de tipo contrato_por_vencer o
--        vacaciones_por_vencer → REENCOLAR CON VENTANA RENOVADA: igual que
--        arriba y además `created_at = now()` (otra semana para salir). La
--        fecha de creación original no se pierde: queda en
--        `payload.creada_originalmente` (y se conserva la primera si se
--        renueva dos veces). Estos avisos no se pueden volver a generar y el
--        hecho sigue siendo cierto, así que descartarlos le quitaría a DO el
--        aviso de un vencimiento que se acerca.
--     3. VIGENTE, FUERA de la ventana y de otro tipo (auto_cierre, un tipo sin
--        regla propia) → DESCARTAR, motivo `fuera_de_ventana`. El hecho sigue
--        a la vista en su pantalla (la cola de revisión de marcajes, por
--        ejemplo): solo se deja de mandar el correo.
--     4. NO vigente → DESCARTAR, motivo `ya_no_vigente`.
--   DESCARTAR = estado 'descartada', `intentos = greatest(intentos, 3)` (con
--   menos de 3 una caducada descartada se volvería a contar como caducada) y
--   la nota «descartada: <motivo> · por <nombre y apellido de quien resolvió>
--   el <fecha de Lima> · <nota anterior>». REENCOLAR también deja rastro:
--   «reencolada por … el … · <nota anterior>». Quién y cuándo importan: sin
--   eso, semanas después nadie sabe quién cerró 21 avisos.
--   Devuelve, con esta forma EXACTA (la pantalla la consume):
--     {"ejecutado": bool,
--      "reencolar": {"total": n, "por_tipo": {"auto_cierre": n, ...},
--                    "ventana_renovada": n},
--      "descartar": {"total": n, "por_motivo": {"fuera_de_ventana": n,
--                                                "ya_no_vigente": n}}}
--   `ventana_renovada` cuenta, DENTRO del total reencolado, los de la regla 2.
--   `por_tipo` trae solo los tipos que tienen algo que reencolar (vacío si no
--   hay nada); `por_motivo` trae siempre sus dos claves. Con `p_ejecutar =
--   false` (el valor por defecto) NO escribe nada ni bloquea nada. Con `true`:
--     1. bloquea las candidatas (`select … for update`, ordenadas por id para
--        que dos resolver no se crucen), y SOLO DESPUÉS
--     2. clasifica y escribe en UNA sentencia —una transacción—: o se
--        resuelven todas o ninguna.
--   Si otra sesión resolvió antes, la espera termina, el bloqueo re-evalúa la
--   condición y esas filas ya no entran: la segunda ejecución devuelve 0 y 0
--   (medido con dos sesiones psql). Los conteos salen de lo que de verdad se
--   escribió. Idempotente: tras ejecutar, nada de lo resuelto vuelve a ser
--   candidato.
--
-- VIGENCIA POR TIPO (`fn_alerta_sigue_vigente`)
--   · auto_cierre: el marcaje `auto_cierre` con ese `ts_cierre` (la salida
--     inventada) sigue en 'pendiente_revision', sin anular, y la persona no
--     está liquidada. Es la misma cola que la 0422 le muestra a quien corrige
--     marcajes: si DO ya lo revisó, lo anuló, o la persona ya cobró su
--     liquidación, avisar «se cerró tu salida solo» es avisar de algo resuelto.
--     Un auto_cierre sin `ts_cierre` en el payload no se puede comprobar y
--     cuenta como no vigente (solo los de antes de la 0327 carecen de él).
--   · contrato_por_vencer: la persona DEL PAYLOAD sigue activa, su
--     `fecha_fin_contrato` actual es la misma que el aviso decía (si se
--     renovó, el aviso miente) y todavía no pasó (`>= fn_hoy_lima()`: el
--     generador tampoco avisa de lo ya vencido).
--   · vacaciones_por_vencer: la persona DEL PAYLOAD sigue activa y
--     `fn_vacaciones_saldo_interno` —el mismo cálculo con el que el
--     generador creó el aviso— sigue diciendo que aplica, que hay récords sin
--     gozar y que o vencen en ≤ 60 días o hay alguno vencido; y `vence_el`
--     es el del aviso (si cambió, es otro hecho y el generador ya creó/creará
--     su propio aviso). Esta última igualdad es un agregado de esta
--     migración sobre la decisión de partida: sin ella, un aviso de un
--     vencimiento que ya pasó a otro récord saldría diciendo la fecha vieja.
--   · tipo desconocido (olvido_salida, tardanza, digest_diario, uno futuro): no
--     hay con qué comprobar el hecho, así que SIGUE vigente solo por ventana.
--   Ojo con una trampa real que esto evita: en los avisos de vencimiento
--   `alertas.persona_id` es el DESTINATARIO (la persona de DO), y la persona
--   del contrato o de las vacaciones va en `payload->>'persona_id'` (0356).
--   Pasar la columna equivocada compararía la fecha de contrato de un
--   integrante de DO —que casi nunca vence— y descartaría EN SILENCIO todos
--   los avisos buenos. Por eso la prueba 440 siembra ese caso a propósito.
--
-- QUÉ HACE `fn_alertas_devolver_intento`
--   `fn_alertas_reservar` (0362) suma el intento ANTES de enviar y
--   `fn_marcar_alerta_resultado` no lo devuelve. Con el lote cortado por una
--   avería del canal (remitente sin verificar, clave inválida, configuración
--   faltante), la fila «canario» —la primera de la lista, la más vieja— gasta
--   un intento cada día aunque nunca tuvo culpa: tras tres días de avería
--   queda definitiva (simulado con 61 filas). Esta función le devuelve el
--   intento: solo toca filas 'fallido', nunca baja de 0, y no la puede llamar
--   ni un navegador ni anon: solo la ruta con la llave de servicio. La ruta
--   la usa SOLO cuando la causa es determinista del canal; en una causa que
--   puede ser de la fila (rechazo del destinatario, 5xx) devolver el intento
--   dejaría que una fila envenenada bloquee el lote para siempre.
--   La ruta la llama sin romperse si esta migración todavía no está pegada.
--
-- POR QUÉ ASÍ
--   DECIDÍ: cuatro piezas separadas —el estado, la pregunta de vigencia, la
--     definición de «sin salida» y la resolución—, con cada regla en su
--     propia función.
--   DESCARTÉ: meter la vigencia y la condición como `case`/`where` dentro de
--     la función de resolución, porque entonces la regla «¿sigue siendo cierto
--     este aviso?» solo se podría usar desde ahí; y la reutilizará el despacho
--     el día que quiera dejar de mandar avisos que ya no valen. Y porque
--     bloquear y resolver tienen que mirar EXACTAMENTE las mismas filas: dos
--     copias de la condición se desincronizan.
--   SE ROMPE SI: alguien agrega un tipo de aviso con un payload nuevo y no
--     le escribe su rama en `fn_alerta_sigue_vigente`: caería en «solo por
--     ventana» y se reencolaría un aviso que quizá ya no vale.
--
--   DECIDÍ: el botón resuelve también las CADUCADAS, no solo las definitivas.
--   DESCARTÉ: resolver solo las definitivas (lo que hacía la primera versión):
--     la tarjeta y la insignia del menú cuentan las caducadas y el botón se
--     dibuja con ellas, pero una caducada no tenía salida —la vista previa
--     decía 0/0 y la tarjeta seguía encendida para siempre—. Medido: además
--     REENCOLAR creaba caducadas (una definitiva a una hora de salir de la
--     ventana volvía a la cola y moría ahí).
--   SE ROMPE SI: se cambia lo que cuenta `caducadas` en el resumen y no esta
--     condición: el botón resolvería algo distinto de lo que la tarjeta cuenta.
--
--   DECIDÍ: la ventana se mide con `created_at - 1 día`, o sea como la verá el
--     despacho de mañana.
--   DESCARTÉ: medirla «ahora» (lo que hacía la primera versión): reencolar un
--     aviso de 6 días y 20 horas lo dejaba caducar antes del próximo despacho,
--     y el aviso de la pantalla prometía «saldrá en el próximo despacho».
--   SE ROMPE SI: el cron deja de ser diario. Si corriera cada hora, medir un
--     día de más descartaría avisos que todavía alcanzaban a salir (los de
--     contrato y vacaciones no, porque se renuevan).
--
--   DECIDÍ: contrato_por_vencer y vacaciones_por_vencer vigentes y fuera de
--     ventana se reencolan con la ventana renovada.
--   DESCARTÉ: descartarlos «por pasar de 7 días» (la primera versión): para
--     un hecho que sigue cierto, la edad del aviso no es motivo; la tarjeta lo
--     llamaba «ya no sirve» siendo falso. También descarté dejar la decisión
--     a DO caso por caso: son los avisos que DO necesita ver y no hay otra
--     fuente que los vuelva a generar.
--   SE ROMPE SI: el canal sigue caído al reencolar —vuelven a gastar tres
--     intentos (tres días) y vuelven a ser definitivas—, o si alguien agrega
--     un tercer tipo «de estado» (un hecho que sigue cierto y no se regenera)
--     y no lo suma a la lista de la regla 2.
--
--   DECIDÍ: 'descartada' como estado propio, con el motivo, quién y cuándo en
--     `nota_fallo`.
--   DESCARTÉ: borrar la fila (la auditoría pierde que hubo un aviso y que
--     falló) y marcarla 'enviado' (miente: nadie recibió nada).
--   SE ROMPE SI: alguien lee `estado = 'fallido'` esperando ver TODO lo que no
--     salió: las descartadas ya no están ahí (ver «qué lee `alertas`» abajo).
--
--   DECIDÍ: descartar sube `intentos` a 3 como mínimo.
--   DESCARTÉ: dejarlos como estaban, o ponerlos en 0 (parece «limpio»):
--     `caducadas` del resumen contaría la fila como un aviso viejo que no
--     salió (estado <> 'enviado', intentos < 3) y la tarjeta volvería a
--     encenderse con las mismas filas que acabamos de cerrar.
--   SE ROMPE SI: alguien «normaliza» los intentos de las descartadas a 0.
--
--   DECIDÍ: bloquear primero y clasificar después, y contar lo que se escribió.
--   DESCARTÉ: una sola sentencia con `for update` dentro del mismo CTE que
--     clasifica (la primera versión): dos DO a la vez —uno espera al otro— la
--     segunda sentencia clasificaba con la foto vieja, y el conteo que le
--     mostraba a la segunda persona no era lo que se había escrito. Y el
--     `for update` en la vista previa bloqueaba a quien escribe solo por
--     mirar (medido).
--   SE ROMPE SI: la función se llama dentro de una transacción REPEATABLE
--     READ: el bloqueo fallaría con error de serialización en vez de esperar
--     (seguro, pero ruidoso). PostgREST usa READ COMMITTED.
--
--   DECIDÍ: devolver el intento solo en las causas deterministas del canal.
--   DESCARTÉ: devolverlo siempre: una fila cuyo destinatario Resend rechaza
--     (422) volvería a reservar un intento cada día sin gastar nunca el
--     lote, y bloquearía el despacho de las demás para siempre.
--   SE ROMPE SI: la ruta clasifica mal una causa de la fila como «del canal»
--     (el cuerpo de error de Resend cambia): se devolvería un intento de más.
--
-- QUÉ LEE O ESCRIBE `alertas` Y POR QUÉ 'descartada' NO ROMPE NADA
--   Revisado el 2026-10-25 (grep en supabase/, packages/ y apps/):
--   · `estado` solo se compara en `fn_alerta_despachable`,
--     `fn_alertas_email_pendientes`, `fn_alertas_reservar`,
--     `fn_marcar_alerta_resultado` y `fn_alertas_despacho_resumen` (0354-0362),
--     y todas piden 'pendiente', 'fallido' o 'procesando' por nombre (o
--     `<> 'enviado'`, con `intentos < 3`, que una descartada no cumple por lo
--     de arriba): una 'descartada' no es despachable, no se reserva, y no es
--     ni definitiva ni atascada ni caducada en el resumen. El resto de las
--     migraciones (0007, 0036, 0082, 0089, 0095, 0203, 0327) solo INSERTAN
--     filas nuevas.
--   · La ruta `/api/alertas-encargadas` solo llama a las funciones de arriba.
--     La Bandeja lee el resumen (`bandeja-fuentes.ts`), no la tabla.
--   · Ninguna pantalla ni tipo de TypeScript enumera los valores de `estado`
--     (en `types.ts` es `string`).
--
-- CONSECUENCIA CONOCIDA
--   Los avisos de vencimiento se generan con un `not exists` por
--   persona|fecha|destinatario|canal (0371). Una fila 'descartada' cuenta como
--   «ya avisado» igual que hoy cuenta una 'fallido': ese mismo evento NO se
--   vuelve a generar. Es deliberado para lo que ya no está vigente. Con la
--   regla 2, un contrato o unas vacaciones que SIGUEN vigentes ya no se
--   descartan, así que esto solo alcanza a los avisos de otros tipos (un
--   auto_cierre fuera de ventana), cuyo hecho sigue visible en su pantalla.
--   Se encuentran con `nota_fallo like '%sigue vigente%'`; quien decide si
--   hay que avisar a mano es DO.
--
-- HUECO PREEXISTENTE QUE NO ES DE ESTA MIGRACIÓN (no se arregla acá)
--   La política `alertas_marcar_leida_propia` (0003) deja al dueño de una fila
--   (`persona_id = fn_persona_actual_id()`) hacer UPDATE de CUALQUIER
--   columna, `estado` e `intentos` incluidos, por PostgREST. En los avisos de
--   vencimiento el dueño es el DO destinatario; en un auto_cierre, el propio
--   integrante. Debería poder tocar solo `leido_at`. Medido: como
--   `authenticated`, `update alertas set estado = 'descartada', intentos = 0
--   where persona_id = <la suya>` devuelve UPDATE 1 —y con esta migración
--   'descartada' ahora es un valor aceptado—. No es una escalada nueva (ya
--   podía ponerse 'enviado' a sí mismo), pero es el molde de «campo sensible
--   → función guardián + trigger BEFORE UPDATE» del CLAUDE.md, y falta
--   aplicarlo a `alertas` (como `fn_set_rol` y `fn_set_sede_base`). Queda
--   anotado para Felipe.
--
-- COMO NO REESCRIBE NINGUNA FUNCIÓN EXISTENTE no hay «md5 de partida»: las
-- cuatro funciones son nuevas (comprobado con ./scripts/donde-vive.sh y con
-- git grep sobre todas las ramas el 2026-10-25: ninguna migración ni rama las
-- define). Lo único que toca de lo existente es `alertas_estado_check`. Y no
-- depende de ninguna otra migración en vuelo (0526, 0545-0547, 0549): usa
-- solo objetos de la 0003, 0078, 0354, 0357, 0362 y 0371.
--
-- CÓMO SE USA
--   Desde la pantalla de Sistema (la que llama a esta función con la sesión de
--   DO): muestra PRIMERO la vista previa —lo que se reencolaría y lo que se
--   cerraría— y solo ejecuta cuando DO confirma.
--
--   Desde el SQL Editor —que corre como postgres y SIN sesión, así que la
--   guarda de permiso lo rechaza— hay que simular a una persona de DO dentro de
--   una transacción, y siempre primero la vista previa. El uuid se saca de:
--     select auth_user_id from personas
--      where rol in ('admin','lider_do') and estado = 'activo' and auth_user_id is not null;
--   y entonces:
--     begin;
--     select set_config('request.jwt.claim.sub', '<auth_user_id de alguien de DO>', true);
--     select fn_alertas_resolver_fallidas();        -- vista previa: no escribe
--     -- select fn_alertas_resolver_fallidas(true); -- lo hace
--     commit;       -- siempre cerrar con commit o rollback
--   Y ANTES de ejecutar, con el 403 de Resend vigente, conviene verificar el
--   dominio: reencolar con el correo todavía caído devuelve los avisos a la
--   misma fila de 'fallido' tras tres intentos más. Y las que fallaron por
--   «sin líder de equipo con correo» fallarán igual hasta que esa sede tenga
--   una líder con correo (se arregla en Equipo, no en Resend).
--
-- ANTES DE PEGAR — consulta de SOLO LECTURA (no usa nada de esta migración)
--   Pegarla en el SQL Editor y mandar las filas. Cuenta las filas sin salida
--   de HOY por origen (definitiva o caducada), por el destino que esta
--   migración les daría y por causa. No escribe nada. Con esta migración ya
--   pegada, la vista previa de `fn_alertas_resolver_fallidas()` da los mismos
--   números (comprobado fila por fila sobre el mismo estado). Si algo no
--   cuadra con lo que dice la tarjeta Sistema, PARAR.
--   Y dos de lectura más: el check tiene que listar solo pendiente,
--   procesando, enviado y fallido, y ningún otro estado puede existir:
--     select pg_get_constraintdef(oid) from pg_constraint where conname = 'alertas_estado_check';
--     select estado, count(*) from alertas group by 1;
--     select numero, nombre from migraciones_aplicadas where numero >= 548;  -- vacío
--
-- >>> CONSULTA
-- with cand as (
--   select a.id, a.tipo, a.persona_id, a.payload, a.estado, a.created_at,
--          a.procesando_desde, a.nota_fallo,
--          (a.estado in ('fallido', 'procesando') and a.intentos >= 3) as definitiva
--     from alertas a
--    where (a.estado in ('fallido', 'procesando') and a.intentos >= 3)
--       or (a.estado <> 'enviado' and a.enviado_at is null and a.intentos < 3
--           and a.created_at <= now() - interval '7 days'
--           and a.created_at >= coalesce((select ma.aplicada_at from migraciones_aplicadas ma where ma.numero = 354),
--                                        timestamptz '2026-09-03 00:00:00-05'))
-- ),
-- c as (
--   select d.*,
--          (d.estado = 'procesando'
--           and coalesce(d.procesando_desde, '-infinity'::timestamptz) >= now() - interval '1 hour') as en_vuelo,
--          fn_alerta_despachable('pendiente', 0, null, d.created_at - interval '1 day') as en_ventana,
--          case d.tipo
--            when 'auto_cierre' then
--              d.persona_id is not null
--              and d.payload ->> 'ts_cierre' ~ '^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T\d{2}:\d{2}:\d{2}'
--              and exists (select 1 from marcajes m
--                           where m.persona_id = d.persona_id
--                             and m.origen = 'auto_cierre' and m.tipo = 'salida_final'
--                             and m.timestamp_marca = (d.payload ->> 'ts_cierre')::timestamptz
--                             and m.estado_revision = 'pendiente_revision'
--                             and m.anulada_at is null)
--              and fn_persona_liquidada(d.persona_id) is not true
--            when 'contrato_por_vencer' then
--              d.payload ->> 'persona_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
--              and d.payload ->> 'fecha_fin_contrato' ~ '^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$'
--              and exists (select 1 from personas p
--                           where p.id = (d.payload ->> 'persona_id')::uuid
--                             and p.estado = 'activo'
--                             and p.fecha_fin_contrato = (d.payload ->> 'fecha_fin_contrato')::date
--                             and p.fecha_fin_contrato >= fn_hoy_lima())
--            when 'vacaciones_por_vencer' then
--              v.s is not null
--              and coalesce((v.s ->> 'aplica')::boolean, false)
--              and coalesce((v.s ->> 'records_sin_gozar')::int, 0) > 0
--              and (coalesce((v.s ->> 'dias_para_vencer')::int, 1000) <= 60
--                   or coalesce((v.s ->> 'records_vencidos')::int, 0) > 0)
--              and ((d.payload ->> 'vence_el') is null
--                   or (v.s ->> 'vence_el') = (d.payload ->> 'vence_el'))
--            else true            -- tipos sin regla propia: vigentes por ventana
--          end as vigente
--     from cand d
--     left join lateral (
--       select fn_vacaciones_saldo_interno(p.id, fn_hoy_lima()) as s
--         from personas p
--        where d.tipo = 'vacaciones_por_vencer'
--          and d.payload ->> 'persona_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
--          and p.id = (d.payload ->> 'persona_id')::uuid
--          and p.estado = 'activo'
--     ) v on true
-- )
-- select c.tipo,
--        case when c.definitiva then 'definitiva' else 'caducada' end as origen,
--        case when c.en_vuelo then '0 · EN VUELO (no se toca)'
--             when coalesce(c.vigente, false) and c.en_ventana then '1 · REENCOLAR'
--             when coalesce(c.vigente, false) and c.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer')
--               then '2 · REENCOLAR CON VENTANA RENOVADA (sigue vigente, ya pasó la ventana)'
--             when coalesce(c.vigente, false) then '3 · DESCARTAR: fuera de ventana (sigue vigente, otro tipo)'
--             else '4 · DESCARTAR: ya no vigente' end as destino,
--        case when c.nota_fallo ~* 'not verified|verify a domain' then 'remitente Resend sin verificar'
--             when c.nota_fallo ~* 'sin (líder de equipo|encargada|ningún destinatario)' then 'sin destinatario con correo'
--             when c.nota_fallo is null then '(sin nota)'
--             else left(c.nota_fallo, 60) end as causa,
--        count(*) as n,
--        min(c.created_at)::date as creada_desde,
--        max(c.created_at)::date as creada_hasta
--   from c
--  group by 1, 2, 3, 4
--  order by 3, 1, 2, 5 desc;
-- <<< CONSULTA
--
-- CÓMO SE REVIERTE
--   -- 1. Las descartadas vuelven a ser definitivas (el motivo, quién y cuándo
--   --    quedan en la nota; las que antes eran caducadas vuelven con intentos 3):
--   update alertas set estado = 'fallido' where estado = 'descartada';
--   -- 2. Las funciones:
--   drop function if exists fn_alertas_resolver_fallidas(boolean);
--   drop function if exists fn_alertas_devolver_intento(uuid);
--   drop function if exists fn_alerta_sin_salida(text, int, timestamptz, timestamptz, timestamptz);
--   drop function if exists fn_alerta_sigue_vigente(text, uuid, jsonb);
--   -- 3. El check y su comentario, como los dejó la 0362:
--   alter table alertas drop constraint if exists alertas_estado_check;
--   alter table alertas add constraint alertas_estado_check
--     check (estado in ('pendiente', 'procesando', 'enviado', 'fallido'));
--   comment on column alertas.estado is null;
--   -- 4. El registro (pegar la migración otra vez sigue siendo seguro):
--   delete from migraciones_aplicadas where numero = 548;
--   OJO: revertir NO restaura lo que la resolución ya hizo. Lo reencolado no se
--   puede «des-reencolar» (ya salió o falló de nuevo, y eso es historia real),
--   y a las reencoladas con ventana renovada su `created_at` original solo
--   sobrevive en `payload.creada_originalmente`. Las descartadas vuelven a
--   'fallido' (paso 1), pero sus intentos subidos a 3 no se bajan.
--   `nota_fallo` guarda en todos los casos qué pasó, quién y cuándo.
-- ============================================================================

-- ── 1 · La tabla aprende el estado 'descartada' ─────────────────────────────

alter table alertas drop constraint if exists alertas_estado_check;
alter table alertas add constraint alertas_estado_check
  check (estado in ('pendiente', 'procesando', 'enviado', 'fallido', 'descartada'));

comment on column alertas.estado is
  'pendiente → procesando → enviado | fallido. ''descartada'' (0548): alguien resolvió que ya no hay nada que enviar (el hecho dejó de ser cierto o salió de la ventana de despacho); deja intentos >= 3 y el motivo, quién y cuándo al frente de nota_fallo.';

-- ── 2 · ¿El hecho de este aviso sigue siendo cierto hoy? ────────────────────
-- Helper interno: nadie de afuera lo llama. SECURITY DEFINER para leer
-- marcajes, personas y liquidaciones sin depender de quién la invoque (la
-- llama otra SECURITY DEFINER, pero así también sirve para una prueba o una
-- sesión de servicio); STABLE porque solo lee y depende de la fecha de hoy.
--
-- Un dato ilegible en el payload (un uuid o una fecha mal escritos) no
-- puede reventar la resolución de las otras 60 filas: se contesta false —«no
-- puedo comprobar que sigue vigente»— y esa fila se descarta con su motivo.

create or replace function fn_alerta_sigue_vigente(p_tipo text, p_persona_id uuid, p_payload jsonb)
returns boolean
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_persona uuid;
  v_ts      timestamptz;
  v_fin     date;
  v_vence   date;
  v_hoy     date := fn_hoy_lima();
  v_saldo   jsonb;
begin
  if p_tipo = 'auto_cierre' then
    -- La persona del aviso ES alertas.persona_id (el integrante cuya salida se
    -- cerró sola). La salida inventada se identifica por su instante exacto.
    if p_persona_id is null or p_payload ->> 'ts_cierre' is null then
      return false;
    end if;
    v_ts := (p_payload ->> 'ts_cierre')::timestamptz;

    return exists (
             select 1
               from marcajes m
              where m.persona_id = p_persona_id
                and m.origen = 'auto_cierre'
                and m.tipo = 'salida_final'
                and m.timestamp_marca = v_ts
                and m.estado_revision = 'pendiente_revision'
                and m.anulada_at is null
           )
       and fn_persona_liquidada(p_persona_id) is not true;

  elsif p_tipo = 'contrato_por_vencer' then
    -- OJO: alertas.persona_id es el DO destinatario. La persona del contrato
    -- va en el payload.
    if p_payload ->> 'persona_id' is null or p_payload ->> 'fecha_fin_contrato' is null then
      return false;
    end if;
    v_persona := (p_payload ->> 'persona_id')::uuid;
    v_fin     := (p_payload ->> 'fecha_fin_contrato')::date;

    return exists (
             select 1
               from personas p
              where p.id = v_persona
                and p.estado = 'activo'
                and p.fecha_fin_contrato = v_fin
                and p.fecha_fin_contrato >= v_hoy
           );

  elsif p_tipo = 'vacaciones_por_vencer' then
    -- Igual que arriba: la persona de las vacaciones va en el payload.
    if p_payload ->> 'persona_id' is null then
      return false;
    end if;
    v_persona := (p_payload ->> 'persona_id')::uuid;
    v_vence   := (p_payload ->> 'vence_el')::date;   -- null si el payload no lo trae

    -- Primero que exista y siga activa: fn_vacaciones_saldo_interno revienta
    -- ('La persona no existe.') si no la encuentra.
    if not exists (select 1 from personas p where p.id = v_persona and p.estado = 'activo') then
      return false;
    end if;

    -- El MISMO cálculo y las MISMAS condiciones con las que
    -- fn_generar_alertas_vencimiento (0371) creó el aviso.
    v_saldo := fn_vacaciones_saldo_interno(v_persona, v_hoy);

    return coalesce((v_saldo ->> 'aplica')::boolean, false)
       and coalesce((v_saldo ->> 'records_sin_gozar')::int, 0) > 0
       and (   coalesce((v_saldo ->> 'dias_para_vencer')::int, 1000) <= 60
            or coalesce((v_saldo ->> 'records_vencidos')::int, 0) > 0)
       and (v_vence is null or (v_saldo ->> 'vence_el')::date = v_vence);
  end if;

  -- Un tipo sin regla propia (o uno futuro) no se puede comprobar contra el
  -- mundo: sigue vigente solo por la ventana, que decide quien llama.
  return true;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    return false;
end;
$fn$;

revoke all on function fn_alerta_sigue_vigente(text, uuid, jsonb) from public, anon, authenticated;

comment on function fn_alerta_sigue_vigente(text, uuid, jsonb) is
  'Interno (0548). ¿El hecho que motivó este aviso sigue siendo cierto hoy? Por tipo: auto_cierre, contrato_por_vencer, vacaciones_por_vencer; cualquier otro tipo sigue vigente solo por ventana. En los avisos de vencimiento la persona del hecho va en payload->>persona_id, NO en alertas.persona_id (que es el DO destinatario).';

-- ── 3 · ¿Esta fila ya no tiene salida por el despacho? ──────────────────────
-- UNA definición de «definitiva o caducada, y no en vuelo». Recibe columnas y
-- no una fila, igual que fn_alerta_despachable (0362), para que se use en un
-- `where` —también en el del bloqueo, donde Postgres la vuelve a evaluar sobre
-- la versión nueva de la fila si otra sesión la tocó mientras esperábamos—.
-- Las dos condiciones están COPIADAS de fn_alertas_despacho_resumen (0362):
-- `fallidas_definitivas` y `caducadas`, esta última con el límite inferior por
-- la fecha en que se pegó la 0354 en ESTA base. El botón resuelve exactamente
-- lo que la tarjeta cuenta.

create or replace function fn_alerta_sin_salida(
  p_estado text,
  p_intentos int,
  p_procesando_desde timestamptz,
  p_enviado_at timestamptz,
  p_created_at timestamptz
)
returns boolean
language sql stable
as $fn$
  select
    -- En vuelo ahora mismo en el despacho: no se toca, ni cuenta como candidata.
    not (p_estado = 'procesando'
         and coalesce(p_procesando_desde, '-infinity'::timestamptz) >= now() - interval '1 hour')
    and (
         -- DEFINITIVA: tres intentos, sea que el tercero terminó en 'fallido'
         -- o que la ejecución murió con él en vuelo.
         (p_estado in ('fallido', 'procesando') and p_intentos >= 3)
         -- CADUCADA: sin salir, fuera de la ventana, con intentos que le
         -- quedaban, creada desde que existe el despacho (backlog de antes de
         -- la 0354 no cuenta: nunca fue candidata).
      or (p_estado <> 'enviado'
          and p_enviado_at is null
          and p_intentos < 3
          and p_created_at <= now() - interval '7 days'
          and p_created_at >= coalesce(
                (select ma.aplicada_at from migraciones_aplicadas ma where ma.numero = 354),
                timestamptz '2026-09-03 00:00:00-05'))
    );
$fn$;

revoke all on function fn_alerta_sin_salida(text, int, timestamptz, timestamptz, timestamptz) from public, anon, authenticated;

comment on function fn_alerta_sin_salida(text, int, timestamptz, timestamptz, timestamptz) is
  'Interno (0548). ¿Esta fila es una definitiva (intentos >= 3 en fallido/procesando) o una caducada (sin salir, intentos < 3, más de 7 días, creada desde la 0354) y no está en vuelo? Copia de lo que cuenta fn_alertas_despacho_resumen.';

-- ── 4 · Resolver: reencolar lo vigente, descartar el resto ──────────────────

create or replace function fn_alertas_resolver_fallidas(p_ejecutar boolean default false)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_ejecutar  boolean := p_ejecutar is true;   -- null cuenta como «solo mirar»
  v_hoy       text    := fn_hoy_lima()::text;
  v_quien     text;
  v_resultado jsonb;
begin
  -- Mismo permiso que la tarjeta Sistema: fn_alertas_despacho_resumen (0362).
  -- `is not true`, no `not`: un null no puede pasar como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.';
  end if;

  if v_ejecutar then
    -- Quién resuelve queda en la nota de cada fila.
    v_quien := coalesce(
      (select p.nombres || ' ' || p.apellidos from personas p where p.id = fn_persona_actual_id()),
      'Desarrollo Organizacional');

    -- PASO 1 — bloquear, y nada más. Ordenado por id para que dos resolver
    -- simultáneos tomen los bloqueos en el mismo orden y no se crucen. Si otra
    -- sesión ya está resolviendo, esto ESPERA su commit; al despertar,
    -- Postgres re-evalúa la condición sobre la fila ya cambiada y las que esa
    -- sesión resolvió dejan de entrar. La vista previa NO pasa por acá: mirar
    -- no bloquea a nadie.
    perform 1
       from alertas a
      where fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
      order by a.id
        for update of a;
  end if;

  -- PASO 2 — clasificar y escribir en UNA sentencia (una transacción). En
  -- READ COMMITTED esta sentencia toma su propia foto DESPUÉS de los
  -- bloqueos, así que ve lo que la otra sesión dejó.
  with candidatas as materialized (
    select a.id, a.tipo, a.persona_id, a.payload, a.nota_fallo, a.created_at
      from alertas a
     where fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
  ),
  clasificadas as materialized (
    select c.id, c.tipo, c.nota_fallo,
           -- La ventana se lee de fn_alerta_despachable, no se copia, y se mide
           -- como la verá el despacho de MAÑANA (corre una vez al día): una
           -- fila 'pendiente' sin intentos creada hace `created_at + 1 día`
           -- ¿saldría?
           fn_alerta_despachable('pendiente', 0, null, c.created_at - interval '1 day') as en_ventana,
           fn_alerta_sigue_vigente(c.tipo, c.persona_id, c.payload)                     as vigente
      from candidatas c
  ),
  destinos as materialized (
    select k.id, k.tipo, k.nota_fallo, k.en_ventana,
           case
             -- Vigente y le alcanza la ventana: vuelve a la cola tal cual.
             when k.vigente and k.en_ventana then 'reencolar'
             -- Vigente, ya pasó la ventana, pero es un HECHO DE ESTADO que no
             -- se vuelve a generar (el not exists de la 0371 ignora el
             -- estado) y sigue siendo cierto: vuelve con otra semana.
             when k.vigente and k.tipo in ('contrato_por_vencer', 'vacaciones_por_vencer') then 'reencolar'
             -- Vigente, ya pasó la ventana, y el hecho sigue a la vista en su
             -- pantalla: solo se deja de mandar el correo.
             when k.vigente then 'fuera_de_ventana'
             -- No vigente (o un null: no se pudo comprobar): ya no hay nada
             -- que avisar.
             else 'ya_no_vigente'
           end as destino
      from clasificadas k
  ),
  reencoladas as (
    update alertas a
       set estado = 'pendiente',
           intentos = 0,
           procesando_desde = null,
           -- Ventana renovada: otra semana para salir, y la fecha original
           -- se guarda (la primera, si se renueva más de una vez).
           created_at = case when d.en_ventana then a.created_at else now() end,
           payload = case when d.en_ventana then a.payload
                          else a.payload || jsonb_build_object(
                                 'creada_originalmente',
                                 coalesce(a.payload -> 'creada_originalmente', to_jsonb(a.created_at)))
                     end,
           nota_fallo = 'reencolada'
             || case when d.en_ventana then '' else ' con ventana renovada' end
             || ' por ' || v_quien || ' el ' || v_hoy
             || coalesce(' · ' || a.nota_fallo, '')
      from destinos d
     where v_ejecutar
       and d.destino = 'reencolar'
       and a.id = d.id
       -- Revalida bajo el candado del propio update.
       and fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
    returning a.id
  ),
  descartadas as (
    update alertas a
       set estado = 'descartada',
           -- Al menos 3: con menos, una caducada descartada se volvería a
           -- contar como caducada (estado <> 'enviado', intentos < 3).
           intentos = greatest(a.intentos, 3),
           procesando_desde = null,
           nota_fallo = 'descartada: '
             || case d.destino
                  when 'fuera_de_ventana' then 'fuera de la ventana de despacho, pero el hecho sigue vigente'
                  else 'el hecho ya no está vigente'
                end
             || ' · por ' || v_quien || ' el ' || v_hoy
             || coalesce(' · ' || a.nota_fallo, '')
      from destinos d
     where v_ejecutar
       and d.destino <> 'reencolar'
       and a.id = d.id
       and fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)
    returning a.id
  ),
  -- Lo que de verdad se escribió. En la vista previa no hay updates y se
  -- cuenta toda la clasificación: mostrar y ejecutar salen del mismo cálculo.
  hechos as (
    select d.*
      from destinos d
     where not v_ejecutar
        or d.id in (select r.id from reencoladas r union all select x.id from descartadas x)
  )
  select jsonb_build_object(
           'ejecutado', v_ejecutar,
           'reencolar', jsonb_build_object(
             'total', count(*) filter (where h.destino = 'reencolar'),
             'por_tipo', coalesce(
               (select jsonb_object_agg(t.tipo, t.n)
                  from (select x.tipo, count(*) as n
                          from hechos x
                         where x.destino = 'reencolar'
                         group by x.tipo) t),
               '{}'::jsonb),
             'ventana_renovada', count(*) filter (where h.destino = 'reencolar' and not h.en_ventana)
           ),
           'descartar', jsonb_build_object(
             'total', count(*) filter (where h.destino <> 'reencolar'),
             'por_motivo', jsonb_build_object(
               'fuera_de_ventana', count(*) filter (where h.destino = 'fuera_de_ventana'),
               'ya_no_vigente',    count(*) filter (where h.destino = 'ya_no_vigente')
             )
           )
         )
    into v_resultado
    from hechos h;

  return v_resultado;
end;
$fn$;

grant execute on function fn_alertas_resolver_fallidas(boolean) to authenticated;
revoke execute on function fn_alertas_resolver_fallidas(boolean) from public, anon;

comment on function fn_alertas_resolver_fallidas(boolean) is
  'Solo DO (0548). Con las filas sin salida de alertas (definitivas: fallido/procesando con intentos >= 3; y caducadas; menos las en vuelo): reencola las vigentes que le alcanzan la ventana de mañana, reencola con ventana renovada los contratos y vacaciones vigentes ya vencidos de ventana, y descarta el resto. p_ejecutar = false (por defecto) no escribe ni bloquea nada. Idempotente.';

-- ── 5 · Devolver el intento que el canal averiado se llevó ──────────────────

create or replace function fn_alertas_devolver_intento(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $fn$
begin
  -- Solo una fila 'fallido' (la reserva ya se soltó al marcar el resultado) y
  -- nunca por debajo de 0. Una fila enviada, descartada o en vuelo no se toca.
  update alertas
     set intentos = greatest(intentos - 1, 0)
   where id = p_id
     and estado = 'fallido';
end;
$fn$;

revoke all on function fn_alertas_devolver_intento(uuid) from public, anon, authenticated;

comment on function fn_alertas_devolver_intento(uuid) is
  'Interno (0548), solo la ruta con la llave de servicio. Devuelve el intento que fn_alertas_reservar gastó en una fila ''fallido'' cuando el fallo fue del canal (remitente sin verificar, clave inválida, configuración) y no de la fila. Nunca baja de 0.';

insert into migraciones_aplicadas (numero, nombre)
values (548, 'los_avisos_que_fallaron_para_siempre_tienen_salida')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- check_acepta_descartada = true     → el estado nuevo entra
-- check_conserva_los_cuatro = true   → los cuatro de siempre siguen
-- fn_resolver / fn_vigente / fn_sin_salida / fn_devolver = 1
--                                    → UNA definición de cada una (dos serían
--                                      el accidente 0297/0299)
-- internas_sin_permiso = true        → los tres ayudantes NO son llamables por authenticated
-- resolver_con_permiso = true        → la pantalla sí puede llamar a la resolución
-- sin_salida_hoy                     → cuántas filas resolvería hoy (definitivas + caducadas)
select
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'alertas_estado_check') like '%descartada%' as check_acepta_descartada,
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'alertas_estado_check') like '%procesando%'
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'alertas_estado_check') like '%fallido%' as check_conserva_los_cuatro,
  (select count(*) from pg_proc where proname = 'fn_alertas_resolver_fallidas') as fn_resolver,
  (select count(*) from pg_proc where proname = 'fn_alerta_sigue_vigente') as fn_vigente,
  (select count(*) from pg_proc where proname = 'fn_alerta_sin_salida') as fn_sin_salida,
  (select count(*) from pg_proc where proname = 'fn_alertas_devolver_intento') as fn_devolver,
  not has_function_privilege('authenticated', 'fn_alerta_sigue_vigente(text, uuid, jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'fn_alerta_sin_salida(text, int, timestamptz, timestamptz, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'fn_alertas_devolver_intento(uuid)', 'execute') as internas_sin_permiso,
  has_function_privilege('authenticated', 'fn_alertas_resolver_fallidas(boolean)', 'execute') as resolver_con_permiso,
  (select count(*) from alertas a
    where fn_alerta_sin_salida(a.estado, a.intentos, a.procesando_desde, a.enviado_at, a.created_at)) as sin_salida_hoy;
