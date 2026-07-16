# Parche propuesto 07 — fallas de carga silenciosas (Dashboard y 6 páginas más)

Hallazgo (reporte C): en 7 páginas, si una consulta falla (red, RLS,
timeout), el código no revisa `error` — `data` llega `null`, el `?? []` lo
convierte en lista vacía, y la pantalla se ve "limpia" en vez de avisar. El
patrón CORRECTO ya existe en el propio repo (`provisiones/page.tsx`,
`objetivos/page.tsx`, `areas/page.tsx`, `planilla/page.tsx`) — este parche
solo lo extiende a donde falta. Ejemplo completo con Dashboard (el más
delicado, es la pantalla que se mira para saber "quién está trabajando
ahora"); para las otras 6 el cambio es el mismo criterio.

**No aplicado** — es una edición de código para que revises y apliques.

## `apps/web/app/(admin)/admin/dashboard/page.tsx`

**Agregar estado de error** (junto a `cargando`, línea ~51):
```tsx
const [cargando, setCargando] = useState(true);
const [error, setError] = useState<string | null>(null);
```

**Antes** (líneas 64-75):
```tsx
const [{ data: personas }, { data: jornadas }, { data: extras }] = await Promise.all([
  supabase
    .from("personas")
    .select("id, nombres, apellidos, sedes:sede_base_id(codigo)")
    .eq("estado", "activo")
    .order("nombres"),
  supabase
    .from("jornadas")
    .select("persona_id, estado, entrada_ts, salida_final_ts, minutos_tarde, tiene_salida_no_retornada")
    .eq("fecha", hoy),
  supabase.rpc("fn_jornadas_extra", { p_desde: hoy, p_hasta: hoy }),
]);
```

**Después:**
```tsx
const [
  { data: personas, error: errPersonas },
  { data: jornadas, error: errJornadas },
  { data: extras }, // fn_jornadas_extra ya está diseñada para fallar en silencio (ver comentario original)
] = await Promise.all([
  supabase
    .from("personas")
    .select("id, nombres, apellidos, sedes:sede_base_id(codigo)")
    .eq("estado", "activo")
    .order("nombres"),
  supabase
    .from("jornadas")
    .select("persona_id, estado, entrada_ts, salida_final_ts, minutos_tarde, tiene_salida_no_retornada")
    .eq("fecha", hoy),
  supabase.rpc("fn_jornadas_extra", { p_desde: hoy, p_hasta: hoy }),
]);

if (errPersonas || errJornadas) {
  setError((errPersonas ?? errJornadas)!.message);
  setCargando(false);
  return; // no pisa `filas` con datos parciales/vacíos
}
setError(null);
```

**En el JSX**, justo después del `<h1>`/header (antes de la tabla), agregar
el mismo banner que ya usa Provisiones:
```tsx
{error && (
  <div className="mb-4 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
    No se pudo cargar la asistencia de hoy: {error}{" "}
    <button onClick={() => void cargar()} className="font-medium underline">
      Reintentar
    </button>
  </div>
)}
```

Con esto, si la consulta falla a mitad de uno de los refrescos automáticos
cada 30s, el Dashboard muestra el aviso rojo en vez de silenciosamente
poner a todo el equipo como "Sin marcar".

## Mismo cambio en las otras 6 páginas (mismo criterio, sin código repetido aquí)

- `apps/web/app/(admin)/admin/correcciones/page.tsx` — función `cargarDia`
  (líneas 79-87): hoy si falla muestra "No hay marcajes ese día" (mensaje de
  "todo bien"). Agregar el mismo patrón `error` + banner.
- `apps/web/app/(admin)/admin/horas/page.tsx` — resumen mensual (líneas
  52-56).
- `apps/web/app/(admin)/admin/incidencias/page.tsx` — líneas 52-59, el caso
  más irónico: si falla, literalmente dice "🎉 Sin incidencias en el
  periodo. Todo en orden." (líneas 123-126) — justo la página cuyo propósito
  es alertar.
- `apps/web/app/(admin)/admin/perfil/page.tsx` — función `cargar` (líneas
  84-96).
- `apps/web/app/(admin)/admin/horarios/page.tsx` — función `cargar` (líneas
  91-95).
- `apps/web/app/(admin)/admin/turnos/page.tsx` — función `cargar` (líneas
  111-118): este ya revisa el error de 2 de las 6 consultas (`fErr`/`arErr`)
  — solo falta agregar lo mismo para las 4 restantes (`personas`,
  `horarios_asignados`, `turnos`, `metas_cobertura`).
- `apps/web/app/(admin)/admin/equipo/page.tsx` — función `cargar` (líneas
  133-139): ya revisa 4 de 5 errores, falta `sedesError` del select de
  `sedes` (si falla, el selector de sede del formulario de alta queda vacío
  sin explicación).

El molde a copiar en cada una es el mismo: destructurar también `error` de
cada consulta del `Promise.all`, cortar temprano con un `setError(...)` si
alguno vino con error, y agregar el banner rojo + "Reintentar" (copiar tal
cual el bloque JSX que ya usa `provisiones/page.tsx`).
