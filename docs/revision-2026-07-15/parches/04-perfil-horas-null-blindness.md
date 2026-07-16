# Parche propuesto 04 — "0 tardanzas" falso en Perfil y Horas

Hallazgo (reporte C): mismo bug ya encontrado y corregido HOY en
`fn_calcular_bono_puntualidad` (`minutos_tarde` es `NULL` cuando no hay
horario con qué comparar, no `0` — tratarlo como `0` con `?? 0` confunde
"sin medir" con "confirmado a tiempo"), vivo en 3 lugares del frontend.
**No aplicado** — son ediciones de código, para que las revises y las
apliques tú mismo (con `Edit`/copiar-pegar) cuando quieras.

## 1. `apps/web/app/(admin)/admin/perfil/page.tsx`

**Antes** (líneas 110-114):
```tsx
const totalHoras = jornadas.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
const diasTrabajados = jornadas.filter((j) => (j.horas_trabajadas ?? 0) > 0).length;
const tardanzas = jornadas.filter((j) => (j.minutos_tarde ?? 0) > 0).length;
const salidasTempranas = jornadas.filter((j) => (j.minutos_salida_temprana ?? 0) > 0).length;
const horasExtra = jornadas.reduce((s, j) => s + (j.horas_extra_detectadas ?? 0), 0);
```

**Después:**
```tsx
const totalHoras = jornadas.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
const diasTrabajados = jornadas.filter((j) => (j.horas_trabajadas ?? 0) > 0).length;
const diasTardeMedidos = jornadas.filter((j) => j.minutos_tarde !== null).length;
const tardanzas = jornadas.filter((j) => (j.minutos_tarde ?? 0) > 0).length;
const diasSalidaMedidos = jornadas.filter((j) => j.minutos_salida_temprana !== null).length;
const salidasTempranas = jornadas.filter((j) => (j.minutos_salida_temprana ?? 0) > 0).length;
const horasExtra = jornadas.reduce((s, j) => s + (j.horas_extra_detectadas ?? 0), 0);
```

**Antes** (líneas 161-164, las tarjetas de estadística):
```tsx
{ label: "Días trabajados", valor: String(diasTrabajados) },
{ label: "Promedio por día", valor: diasTrabajados ? fmtHoras(totalHoras / diasTrabajados) : "—" },
{ label: "Días con tardanza", valor: String(tardanzas) },
{ label: "Salidas anticipadas", valor: String(salidasTempranas) },
```

**Después** — el número sigue siendo el mismo (`tardanzas`/`salidasTempranas`),
solo se agrega el contexto de cuántos días realmente se pudieron medir:
```tsx
{ label: "Días trabajados", valor: String(diasTrabajados) },
{ label: "Promedio por día", valor: diasTrabajados ? fmtHoras(totalHoras / diasTrabajados) : "—" },
{ label: "Días con tardanza", valor: `${tardanzas} de ${diasTardeMedidos} medidos` },
{ label: "Salidas anticipadas", valor: `${salidasTempranas} de ${diasSalidaMedidos} medidos` },
```
Si `diasTardeMedidos` es 0 (nadie pudo medirse — el caso Felipe/Estefany sin
horario), el texto queda "0 de 0 medidos", que ya no se lee como "perfecto".

## 2. `apps/web/app/(admin)/admin/horas/page.tsx`

**Antes** (línea 62, la forma inicial del acumulador por persona):
```tsx
diasTrabajados: 0, horasTotales: 0, tardanzas: 0, minutosTarde: 0, salidasTempranas: 0, horasExtra: 0, incompletas: 0, pendientesRevision: 0,
```
**Después** — agrega `diasTardeMedidos`:
```tsx
diasTrabajados: 0, horasTotales: 0, tardanzas: 0, diasTardeMedidos: 0, minutosTarde: 0, salidasTempranas: 0, horasExtra: 0, incompletas: 0, pendientesRevision: 0,
```
(y agregar el campo `diasTardeMedidos: number;` al tipo `ResumenPersona` donde
esté declarado — buscar `interface ResumenPersona` en el mismo archivo.)

**Antes** (línea 70):
```tsx
if ((j.minutos_tarde ?? 0) > 0) { r.tardanzas++; r.minutosTarde += j.minutos_tarde!; }
```
**Después:**
```tsx
if (j.minutos_tarde !== null) r.diasTardeMedidos++;
if ((j.minutos_tarde ?? 0) > 0) { r.tardanzas++; r.minutosTarde += j.minutos_tarde!; }
```

Y en la tabla, donde se muestra la columna de tardanzas (buscar dónde se
renderiza `r.tardanzas` en el JSX de la tabla — no incluido aquí porque no
llegué a leer esa parte del archivo, pero el cambio es el mismo criterio de
arriba: mostrar `${r.tardanzas} / ${r.diasTardeMedidos}` en vez de solo
`r.tardanzas`).

## Nota

No toqué `perfil/page.tsx:110` (`diasTrabajados`, basado en
`horas_trabajadas ?? 0 > 0`) ni `horas_extra_detectadas ?? 0` — el reporte C
los marcó como 🟡 de menor severidad (sumar `null` como `0` en un total
agregado es razonable, no "confirma" nada falso). Si querés, el mismo
criterio de "contar por `entrada_ts is not null`" está descrito en el
reporte C si en algún momento quieres afinar también ese número.
