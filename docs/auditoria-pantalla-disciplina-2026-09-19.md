> ℹ️ **Informe fechado, no estado vigente.** Resume el trabajo de una sesión sobre
> `/admin/disciplina` el 19 de setiembre de 2026. Lo vivo vive en otros sitios:
> el estado en [`estado.md`](estado.md), los pendientes en
> [`hallazgos-abiertos.md`](hallazgos-abiertos.md) (bloque «Auditoría de la
> pantalla Disciplina · 2026-09-19») y las preguntas al laboralista en
> [`disciplina-tardanzas-faltas/10-consulta-al-laboralista.md`](disciplina-tardanzas-faltas/10-consulta-al-laboralista.md)
> (consultas 3 a 8).

# Disciplina — auditoría, ajustes en pantalla y diseño del flujo del colaborador

## 1 · Qué se pidió y con qué alcance

1. **Auditar** la pantalla `/admin/disciplina` y proponer, sin tocar reglas, SQL ni
   textos legales. La regla de referencia (RIT 19.2) no se reabrió.
2. **Auditar el flujo amonestación → notificación → firma del colaborador** y
   decidir, con preguntas cerradas, cómo debería ser.
3. Implementar solo lo pequeño y reversible («carril 1»); lo estructural queda
   como propuesta con aprobación previa («carril 2/3»).
4. Un **prototipo** para ver el flujo antes de escribir código.

## 2 · Auditoría de la pantalla (resumen)

Verificado contra el código, las migraciones vigentes y el RIT v4.0. **No se midió
nada en producción** (sin acceso; Postgres local apagado).

| Sev. | Hallazgo | Estado |
|---|---|---|
| Alto | La política `disciplina_descargo_previo` nació en `false` (0267, decisión de Gerencia 17-ago): «Firmar» no exige comunicar cargos ni plazo. El modal decía lo contrario; el RIT 19.3 y 55.2 dicen que omitirlo invalida la medida. | Pantalla corregida. **Valor sin tocar** (decisión de Gerencia + laboralista). |
| Alto | `Esperada —` en la evidencia: una jornada medida antes de la 0446 no guarda el horario con que se midió. No es «tardanza contra nada» (`0445:116-118`). | Rótulo corregido. Falta reconstruir la hora esperada. |
| Alto | El memo de amonestación cita «artículo 7» y «8.3-b» (hoy otras materias). RIT 55.3 exige numeral y literal. | **Abierto** (texto legal; consulta 7). |
| Medio | El conteo suma tardanzas en días con permiso, licencia o vacaciones (RIT 17.3, 17.4 c); feriados: el texto del RIT y la práctica discrepan. | Abierto (consulta 5). |
| Medio | Sede como código («LIM») cuando existen el Taller y la Tienda de Lima. | Pantalla corregida. Queda el memo impreso. |
| Medio | «vigente hasta el 25-ago.» sin año; 365 días vs 12 meses de calendario. | Corregido. |
| Medio | Jerga a quien firma («Mig. 0189», «semáforo», «escalón», «la base») y una frase que confundía la segunda suspensión con la imputación. | Corregido. |
| Medio | Doble borrador simultáneo posible (sin candado ni índice único); firmar no revalida días de suspensión. | Abierto (SQL). |
| Medio | Errores de lectura mudos o que se leen como «no hay nadie». | Corregido en parte. |

Sobre el **escalón d)** del RIT 19.2 (segunda suspensión): el motor
(`fn_tardanza_escalon_al`, 0311) sí refleja los cuatro escalones; lo que faltaba
era la explicación que lee quien firma.

Existe además una auditoría previa de Disciplina (13-set) en la rama sin fusionar
`claude/cayla-disciplina-auditoria-9f1cf5`; su hallazgo del memo sigue vivo.

## 3 · Qué se implementó (PR #441, fusionado)

Ocho cambios solo de pantalla, sin SQL, con pruebas (972 en verde), typecheck y
eslint limpios:

- El antecedente dice su año y cuenta 12 meses de calendario.
- `/mio`: la constancia de «Tus memos» muestra el día de Lima, no el de UTC.
- «Esperada» dice «Sin foto del horario», «Descanso» o «Sin horario»; el panel avisa
  que hay que confirmar la hora antes de comunicar cargos.
- Lenguaje llano y los cuatro pasos de la escala (`explicarPasoTardanza`).
- La pantalla dice qué política de descargo rige hoy (sin cambiar su valor).
- Línea «Para hoy» y botón «Ir al borrador».
- Un fallo de lectura ya no se lee como «no hay nadie» (contadores «?»).
- La sede se lee «Taller · Lima» (`etiquetaDeSede`).

**No verificado en navegador** (el panel local no tiene `.env.local`).

## 4 · El flujo del colaborador: qué existe hoy

Ya existe una versión parcial (migración 0408, pegada en producción el 2026-09-10 según
`estado.md`):

- Tarjeta «Tus memos disciplinarios» en `/mio` → «Historial», con «Firmar» y
  «Prefiero no firmar digitalmente», solo para documentos `entregado` y de nivel
  verbal, amonestación o suspensión.
- Aviso «Tienes 1 documento por revisar y firmar» en Resumen y en la Bandeja.
- La constancia se ve dentro del memo del admin.

**Lo que hoy no hace:** la persona no puede leer el documento (solo nivel, fecha y
número); no hay aviso al iniciar sesión ni correo; no hay comentario ni motivo; DO no
recibe aviso ni ve una insignia en la tabla; la función pensada para avisar a DO
(`fn_memos_recientes_respuesta_sancionado`) no la usa ninguna pantalla. La base
permitiría reemplazar la respuesta, aunque la pantalla no lo ofrece.
**Ninguna prueba** (ni pgTAP ni de pantalla) cubre estas funciones.

## 5 · Decisiones tomadas para el flujo nuevo

| # | Decisión |
|---|---|
| 1 | Ruta propia `/mio/disciplina` + tarjeta destacada en la portada de `/mio`. |
| 2 | Aviso genérico al iniciar sesión, no bloqueante, hasta que abra el documento. |
| 3 | Leer → comentario opcional → firmar o negarse; queda sellado y solo se agregan constancias. Puede ver y descargar el documento firmado. |
| 4 | Insignia informativa por fila para el admin; aviso a su bandeja si no firma. |
| 5 | Entrega digital como medio formal (firma electrónica simple, contraseña, versión sellada), con habilitación y acuse por persona; el papel queda de respaldo; imputación y despido fuera. |
| 6 | Memo completo en solo lectura; descarga por la impresión del navegador. |
| 7 | Restringir `exp_select_propia` a `entregado` (SQL, a consultar). |
| 8 | Aviso inmediato si rechaza; recordatorio a 5 días hábiles sin respuesta (recordatorio interno, no plazo legal). |
| 9 | Habilitar el medio digital con acuse digital por persona (mecanismo de acuses existente). |
| 10 | Cuenta como entregado cuando la persona confirma la recepción con su contraseña. |
| 11 | La respuesta va en una **tabla aparte, solo inserciones**; el `estado` del documento no se toca (la escalera de tardanzas filtra `estado = 'entregado'`, `0311:260`). |
| 12 | Texto del memo congelado al firmar el emisor, como en contratos (`documento_html`). |
| 13 | El rechazo se llama «No conforme», con motivo y detalle; DO puede pasarlo a Gerencia como reconsideración (RIT 55.5). |
| 14 | El sha256 de ese texto se copia en cada respuesta. |

Modo de trabajo acordado: **por carriles**. Lo chico y reversible se implementa directo;
base, estados, permisos, reglas de sanción y textos legales van con OK previo; el SQL lo
pega Felipe **antes** de fusionar (fusionar a `main` publica producción).

## 6 · Diseño propuesto (sin implementar)

- **`expediente_respuestas`**: solo inserciones; vías `digital`, `fisica`, `rechazo`; hash,
  archivo, revisión de DO (`pendiente_validacion`, `validada`, `observada`), motivo y detalle.
- **`motivos_observacion_memo`**: catálogo en tabla (no lista en el código).
- **Recepción digital**: valor nuevo `sistema` en `medio_entrega`, más `recibido_at` y
  `recibido_sha256`.
- **Sello**: `contenido_html` congelado al firmar el emisor (hoy el memo se dibuja desde
  el código, así que corregir una cita cambiaría lo ya entregado).
- **Funciones** `SECURITY DEFINER` con guardas `is not true`; contraseña reciente
  comprobada con el `amr` del token (a verificar en este proyecto).
- **Storage**: bucket propio, con tipo y tamaño validados en la base.
- **Vista admin**: insignia «Respuesta», sección con historial, validar o pedir otro
  archivo, acta de negativa o pasar a Gerencia; avisos en la Bandeja.

## 7 · Demo

[`disciplina-colaborador-prototipo-2026-09-19.html`](disciplina-colaborador-prototipo-2026-09-19.html):
un solo HTML, datos ficticios, nada se guarda.

- **«Cómo es HOY»**: réplica del código actual (0408) y de lo que no hace.
- **«Propuesta»**: aviso, recepción con contraseña, firmar aquí / en papel / no estoy
  conforme, historial que no se pisa y avisos a DO. Probado con scripts de clics; se ve
  bien en claro, oscuro y 375 px.

Es una réplica, **no** el sistema real: no prueba que producción funcione.

## 8 · ¿Está funcional en el sistema?

No se pudo comprobar de punta a punta: Docker apagado, sin `apps/web/.env.local`, sin
sesión propia en producción. Lo que sí hay:

- La base (0408) pegada y verificada por md5 el 2026-09-10.
- El código de la tarjeta y del memo en `main`.
- Cero pruebas de comportamiento, y nadie lo ha usado con un caso real conocido.

**Consultas de solo lectura para producción:**

```sql
-- 1 · ¿La 0408 está pegada?
select numero, nombre from migraciones_aplicadas where numero = 408;
select proname from pg_proc
 where proname in ('fn_mis_memos','fn_firmar_memo_como_sancionado','fn_rechazar_firma_memo','fn_memos_recientes_respuesta_sancionado');

-- 2 · ¿Cuántas personas activas no podrían firmar por no tener su firma?
select count(*) filter (where f.persona_id is null) as sin_firma, count(*) as activas
  from personas p left join firmas_escaneadas f on f.persona_id = p.id
 where p.estado = 'activo' and p.en_planilla;

-- 3 · ¿Hay ya algún memo entregado que alguien pueda ver o haya respondido?
select nivel, estado, count(*) as total,
       count(*) filter (where firma_sancionado_confirmada_at is not null) as firmados,
       count(*) filter (where sancionado_rechazo_firma_at is not null) as rechazos
  from expediente_disciplinario group by 1, 2 order by 1, 2;
```

Por qué no se prueba con una amonestación de prueba en producción: no hay ningún botón
que cree un memo a demanda (los borradores nacen de los generadores, que exigen
umbral); al firmar se consume un número oficial; un expediente no se borra; y una
amonestación real cuenta como antecedente 12 meses.

## 9 · Pendiente

1. **Comprobar el flujo actual**: prueba pgTAP de la 0408, recorrido local con datos
   ficticios o mirada de solo lectura en producción (elegir).
2. **Laboralista**: consultas 3 a 8 (descargo previo y política, fecha de conocimiento,
   días que el RIT excluye, días sin foto del horario, numeral equivocado en memos
   entregados, quién estampa la firma).
3. **Decisión de Gerencia** sobre el valor de `disciplina_descargo_previo`. Dirección
   elegida: volver a exigirlo hasta que responda el laboralista. Sin aplicar.
4. **Memo impreso**: citas «artículo 7» y «8.3-b», y «Sede LIM» (texto legal).
5. **SQL del flujo nuevo** y la policy `exp_select_propia`: con el rito de la casa (número,
   md5 de producción dos veces, pegar antes de fusionar).
6. **Acuse digital de recepción de cargos** (comunicación de cargos): fuera de esta
   entrega, pendiente de decisión.
