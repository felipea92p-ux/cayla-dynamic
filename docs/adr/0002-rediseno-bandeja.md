# ADR 0002 — Rediseño de Bandeja (inbox operativo del panel)

> ⚠️ **Las decisiones 3 (zonas) y 7 (filtro de sede) fueron reemplazadas el
> 2026-09-15 por el [ADR 0003](0003-bandeja-por-urgencia.md).** Las demás siguen.

Fecha: 2026-09-13. Estado: **implementado** — migración
`supabase/migrations/0436_la_bandeja_recuerda_lo_que_ya_viste.sql`, prueba
`supabase/tests/345_la_bandeja_recuerda_lo_que_ya_viste.test.sql` (8/8 en
verde contra Postgres local, dentro de `BEGIN…ROLLBACK`), y
`apps/web/app/(admin)/admin/bandeja/page.tsx` reescrito con las 8 decisiones
de abajo. `tsc --noEmit` y `eslint` limpios en todo el monorepo.

⚠️ Pendiente de verificar visualmente en el navegador: el stack local completo
(`npx supabase start`) no levantó Kong/Auth/Storage en esta máquina durante
esta sesión — Postgres seguía sano y la migración se aplicó igual, directo
contra el contenedor, pero no se pudo confirmar la pantalla renderizada en
vivo. Revisar antes de dar esto por probado de punta a punta.

## Contexto

`apps/web/app/(admin)/admin/bandeja/page.tsx` junta en una sola pantalla lo
que hasta ahora solo se veía como un número suelto en el menú: 9 secciones,
cada una alimentada por su propia RPC (`fn_educacion_listar`,
`fn_vacaciones_por_vencer`, `fn_personas_sin_horario_vigente`,
`fn_revisiones_pedidas`, `fn_movilidad_revisiones_pedidas`,
`fn_contrato_revisiones_pedidas`, `fn_solicitudes_vacaciones`,
`fn_solicitudes_perfil_pendientes`, `fn_alertas_despacho_resumen`). No
inventa un criterio nuevo de "pendiente": reusa exactamente lo que ya cuentan
los badges de Educación, Ausencias e Incidencias.

Hoy la pantalla no guarda ningún estado propio — cada visita repregunta las 9
RPCs desde cero — y las 9 secciones se ven visualmente idénticas: mismo
tamaño de título, mismo orden fijo en el código, sin importar si tienen botón
de acción o son solo un aviso con un link de salida.

## Objeción al encuadre

Se pidió "hacerla más formidable, como los mejores ERPs del mundo". Tomado
literalmente, eso invita a copiar *features* de Workday/Oracle (delegación,
motor de workflow genérico, snooze). Este mismo repositorio ya hizo ese
ejercicio una vez — `docs/comparacion-workday-oracle-dynamic-2026-09-02.md`
— y concluyó que lo que vale la pena copiar de esos sistemas no son sus
pantallas, son sus **primitivos** (vigencia temporal, guardianes de campo
sensible), aplicados solo donde CAYLA ya sintió el dolor de no tenerlos. Con
30 personas y 4 sedes, construir hoy el motor de bandeja completo de un ERP
de miles de empleados sería pagar mantenimiento por flexibilidad que nadie
va a usar. Las decisiones de abajo aplican ese mismo criterio: se adopta el
primitivo que la Bandeja demostrablemente no puede vivir sin (leído/no
leído), y se descartan los que resuelven un problema que CAYLA no tiene
todavía (delegación, motor genérico, pantalla de salud aparte).

## Lo que no pidió

Ninguna de las 8 decisiones de abajo deja, una vez implementada, una forma
de medir si sirvió. Vamos a construir "se ve y se siente mejor" sin un
número de "cuánto bajó el tiempo que algo queda pendiente antes de
resolverse" — exactamente lo que el propio criterio de este proyecto pide
medir antes de opinar. La recomendación concreta va en "Próximos pasos".

## DECIDÍ

### 1. Alcance de esta sesión: diagnóstico + plan, no código

**DECIDÍ:** esta sesión entrega este ADR con las decisiones tomadas junto a
Felipe (8 preguntas, formato AskUserQuestion). Ninguna migración ni cambio
de pantalla se aplica todavía.

**DESCARTÉ:** implementar ya en `bandeja/page.tsx` — la decisión #2 de abajo
exige una tabla nueva, y el SQL a producción lo aplica Felipe a mano; dejar
código de front esperando una tabla que no existe en ningún ambiente
habría sido peor que no tocar nada.

**SE ROMPE SI:** alguien lee este documento como changelog en vez de como
plan. Si en dos semanas nadie escribió la migración de la decisión #2, este
ADR sigue en estado "propuesto", no "hecho" — hay que decirlo explícito acá
mismo cuando se retome, no dejar que el estado quede ambiguo.

### 2. Tabla mínima de "leído/no leído"

**DECIDÍ:** una tabla nueva y chica, solo para los 5 tipos de la zona "Por
aprobar" (decisión #3) — la zona informativa nunca se resuelve desde acá, así
que "leído" no cambia ninguna acción posible ahí.

```sql
create table bandeja_vistos (
  persona_id uuid not null references personas(id),
  tipo_item  text not null,  -- 'revision' | 'revision_movilidad' | 'revision_contrato'
                              -- | 'solicitud_vacacion' | 'solicitud_perfil'
  item_id    uuid not null,
  visto_at   timestamptz not null default now(),
  primary key (persona_id, tipo_item, item_id)
);
```

**DESCARTÉ — "sin estado nuevo":** significa que la Bandeja nunca puede
distinguir "esto lleva 3 días sin que nadie lo mire" de "lo vi ayer y decidí
dejarlo pendiente a propósito" — la ambigüedad que hoy hace que 14
pendientes se sientan todos igual de urgentes.

**DESCARTÉ — "motor de bandeja completo"** (tabla que normaliza los 9 tipos
con prioridad/snooze/delegado): es la respuesta de un ERP de miles de
personas. Con 30, construirla hoy es la complejidad que la objeción de
arriba ya advirtió.

**SE ROMPE SI:** aparece otro punto de entrada para resolver una solicitud
fuera de esta pantalla — hoy no existe, así que `item_id` nunca queda
huérfano. El día que exista, hay que revisar si `visto_at` sigue siendo
válido antes de confiar en él.

### 3. Separar en 2 zonas: "Por aprobar" y "Para saber"

**DECIDÍ:** "Por aprobar" arriba (revisiones, revisiones de movilidad,
revisiones de contrato, solicitudes de vacaciones, solicitudes de perfil) y
"Para saber" abajo (sin horario, vacaciones por vencer, educación), cada una
con su propio encabezado de zona.

**DESCARTÉ:** pestañas separadas — un clic extra para ver lo informativo
cuesta descubribilidad (alguien que entra a ver quién está sin horario
tendría que saber que existe una segunda pestaña), y hoy nadie pidió que la
zona "Por aprobar" quede más corta a costa de eso.

**SE ROMPE SI:** aparece una décima sección que informa Y a veces se
resuelve acá — la categoría binaria se queda corta, y hay que decidir de
nuevo en vez de forzarla en una de las dos.

### 4. El diseño soporta mobile, sin ser mobile-first

**DECIDÍ:** los formularios inline de "Por aprobar" (campo de texto + botones
Aprobar/Rechazar) se apilan en columna en pantallas angostas en vez de ir en
fila, con botones de alto mínimo táctil (44px).

**DESCARTÉ:** mobile-first puro — la respuesta fue "también celular A
VECES", no "principalmente celular"; invertir el diseño entero para el caso
menos frecuente sobre-optimiza el 20% de los usos a costa del 80% en
desktop.

**SE ROMPE SI:** en la práctica la mayoría de las aprobaciones terminan
pasando por celular — mismo criterio de números antes que opiniones: vale
la pena medir esto con datos reales una vez esté en producción, no con la
primera impresión.

### 5. Antigüedad visible, con alarma a los 7 días

**DECIDÍ:** mostrar "hace N días" junto a cada ítem accionable, en rojo desde
el día 8 — el mismo plazo que ya usa el reglamento de disciplina de este
sistema para exigir reiteración. **Corrección al implementar:** no hizo
falta ninguna migración. Al revisar el SQL real, las 5 RPC de "Por aprobar"
YA devuelven `pedida_at` (`fn_revisiones_pedidas`, 0257) o `creada_at`
(`fn_solicitudes_perfil_pendientes`, 0399) desde que se escribieron —
`fn_solicitudes_vacaciones` (0330) también trae `pedida_at`. El dato siempre
estuvo ahí; solo faltaba declararlo en las interfaces de TypeScript de la
pantalla y usarlo. Este párrafo original quedó como se escribió para no
reescribir la historia de la decisión.

**DESCARTÉ:** mostrar la antigüedad sin colorear nada — el objetivo
explícito era que la Bandeja *avise*, no solo informe.

**SE ROMPE SI:** el umbral de 7 días resulta parejo mal puesto — una
solicitud de vacaciones sin responder en 7 días es grave (retrasa el pago),
pero una revisión de marcaje puede tomar una semana en resolverse en persona
sin que sea un problema. Si en la práctica un tipo genera falsas alarmas y
otro deja pasar cosas reales, el umbral se separa por tipo, no se ajusta el
número global.

### 6. Sin posponer ni ocultar en "Para saber"

**DECIDÍ:** ningún botón de "posponer" u "ocultar" en las 3 secciones
informativas; siguen apareciendo hasta que la causa raíz se resuelve en su
pantalla real (Horarios, Ausencias, Educación).

**DESCARTÉ:** posponer con fecha de retorno — el propio comentario del
código de "Sin horario" ya advierte que un descanso médico que caiga en ese
hueco se paga en cero sin que nada falle. Dejar que alguien lo posponga y se
olvide es justo el escenario que esa sección existe para prevenir.

**SE ROMPE SI:** la lista de "Para saber" crece tanto por volumen (ej. las
12 asignaciones de educación de hoy) que deja de ser útil — ahí la
respuesta correcta es el filtro de sede (decisión #7) o revisar por qué
vencen tantas juntas, no dar un botón para dejar de verlas.

### 7. Filtro de sede, recordado entre visitas

**DECIDÍ:** un selector arriba de la pantalla ("Todas" por defecto, o
CCO/TRU/LIM/AQP) que filtra las 9 secciones a la vez y recuerda la última
elección (preferencia de UI en `localStorage`, no un dato de negocio en la
base).

**DESCARTÉ:** subtítulos por sede sin selector — no resuelve el problema
real (la longitud total de la pantalla cuando hay pendientes en las 4 sedes
a la vez), solo lo reorganiza.

**SE ROMPE SI:** alguien filtra por "TRU" y se olvida que el filtro sigue
puesto — dos días después entra buscando algo de AQP y la pantalla se ve
vacía sin razón aparente. Mitigación: el selector siempre visible arriba,
nunca escondido en un menú.

### 8. "Avisos por correo" se queda, con franja "Sistema" propia

**DECIDÍ:** la sección sigue en Bandeja pero con tratamiento visual
distinto — el token `pizarra` ya reservado en el sistema de diseño para
"informativo/en proceso", con etiqueta "Sistema" en vez del formato de las
demás secciones — para que se lea de entrada como salud del cron de correos,
no como una tarea de una persona.

**DESCARTÉ:** pantalla propia de "Salud del sistema" — crear pantalla y
entrada de menú nuevas para una sola tarjeta condicional (que solo aparece
cuando algo falla) es agregar una capa para un caso que hoy se resuelve con
una franja de color.

**SE ROMPE SI:** se suman más chequeos de salud del sistema y la franja
empieza a acumular 3 o 4 tarjetas de naturaleza distinta a las tareas
humanas — ahí sí se cruza el umbral donde una pantalla propia se justifica.

## Próximos pasos

1. **Pegar `0436_la_bandeja_recuerda_lo_que_ya_viste.sql` en producción** —
   Felipe, a mano, por `scripts/dame-el-sql.sh 435`. No toca ningún cálculo
   de planilla ni dato existente: solo agrega una tabla y una función nuevas.
2. Confirmar visualmente en el navegador que la pantalla rediseñada carga
   bien contra el stack local completo (bloqueado esta sesión, ver "Estado"
   arriba) — antes de considerar esto probado de punta a punta.
3. **Instrumentar antes de dar por bueno el rediseño:** guardar en algún lado
   consultable cuándo se resuelve cada tipo de pendiente (aprovechando
   `visto_at`/`pedida_at`/`creada_at` ya disponibles) para poder comparar, en
   unas semanas, el tiempo promedio de espera antes y después del rediseño.
   Sin ese número, "se ve más formidable" es una opinión, no una medición.
