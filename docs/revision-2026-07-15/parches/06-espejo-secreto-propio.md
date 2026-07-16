# Parche propuesto 06 — dejar de usar la llave `service_role` como secreto del espejo a Sheets

Hallazgo (reportes D y E): `api/espejo/route.ts` compara el token entrante
contra la llave real `SUPABASE_SERVICE_ROLE_KEY` (acceso total a la base,
bypass de RLS, `supabase.auth.admin.*`).

**Confirmado en vivo el 2026-07-16** (revisando el Apps Script real con
Felipe): el script que de verdad corre en producción (`Código.gs` del
proyecto "Dynamic — Espejo") **sí llama al puente `/api/espejo`** — no
llama directo a PostgREST como decía `scripts/espejo-sheets.gs` en el repo
(ese archivo está desactualizado, no refleja lo que corre hoy; considerar
actualizarlo o borrarlo para que no confunda a futuro). Pero la propiedad
de script `SUPABASE_KEY` que manda como `Authorization: Bearer` tiene que
contener la llave real — es lo único que la ruta acepta hoy. El riesgo de
fondo es el mismo: esa llave maestra vive guardada en "Propiedades del
script" de Apps Script, fuera del control de Vercel/Supabase. Si se filtra
por cualquier vía relacionada a Sheets/Apps Script, quien la obtenga tiene
control total de la base — no solo del espejo de asistencia.

**No aplicado** — requiere 3 pasos, uno de código y dos de configuración
externa (Vercel + Google) que solo tú puedes hacer:

## 1. Código: `apps/web/app/api/espejo/route.ts`

**Antes** (líneas 8-15):
```ts
const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const TZ = "America/Lima";

export async function GET(req: Request) {
  if (!URL || !SERVICE) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token || token !== SERVICE) return NextResponse.json({ error: "no autorizado" }, { status: 401 });
```

**Después** — un secreto propio, de bajo privilegio, solo para este puente:
```ts
const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ESPEJO_TOKEN = process.env.ESPEJO_TOKEN;
const TZ = "America/Lima";

export async function GET(req: Request) {
  if (!URL || !SERVICE || !ESPEJO_TOKEN) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token || token !== ESPEJO_TOKEN) return NextResponse.json({ error: "no autorizado" }, { status: 401 });
```
(El resto de la función sigue usando `SERVICE` internamente para el cliente
de Supabase — eso está bien, es server-side. Lo único que cambia es CON QUÉ
se compara el token que llega de afuera.)

De paso, ya que se está tocando el archivo: agregar
`export const dynamic = "force-dynamic";` y devolver
`{ "Cache-Control": "no-store" }` en los headers de la respuesta (hallazgo
menor de E — que ningún proxy/CDN cachee por error una respuesta con datos
de asistencia de toda la empresa).

## 2. Generar el secreto nuevo y agregarlo a Vercel

En tu Mac, generar un valor aleatorio largo (cualquiera de estas formas
sirve):
```
openssl rand -base64 32
```
Copiar el resultado. En Vercel → tu proyecto → Settings → Environment
Variables: agregar `ESPEJO_TOKEN` con ese valor, para Production (y Preview
si usas ese endpoint ahí también).

## 3. Actualizar la propiedad del script en Apps Script (más simple de lo
   que parecía — el script en sí NO hay que tocarlo, solo el valor guardado)

En el editor de Apps Script (`script.google.com`, proyecto "Dynamic —
Espejo"): ícono de engranaje ⚙️ ("Configuración del proyecto") en la barra
izquierda → sección "Propiedades del script". Ahí vas a ver `SUPABASE_KEY`
con el valor actual (la llave real) — edítala y reemplaza el valor por el
`ESPEJO_TOKEN` nuevo del paso 2. El código (`Código.gs`) no necesita
ningún cambio — ya llama a la URL correcta, solo estaba mandando el secreto
equivocado.

(Aparte, sin apuro: el archivo `scripts/espejo-sheets.gs` del repo describe
un script viejo que ya no es el que corre — vale la pena borrarlo o
actualizarlo para que no confunda a alguien que lo lea después.)

## 4. Rotar la llave `service_role` real

Dado que ya circuló por Apps Script (Google), conviene rotarla en el
dashboard de Supabase (Settings → API → regenerar `service_role`) una vez
que los pasos de arriba estén funcionando — así el valor viejo, que ya
estuvo expuesto, deja de servir para nada. Ojo: rotar esa llave rompe
temporalmente `api/admin/cuentas` y `api/reabrir-dia` hasta que actualices
la variable de entorno `SUPABASE_SERVICE_ROLE_KEY` en Vercel con el valor
nuevo — hacerlo en el mismo despliegue, no por separado.
