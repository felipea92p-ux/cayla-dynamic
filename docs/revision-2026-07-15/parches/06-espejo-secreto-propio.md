# Parche propuesto 06 — dejar de usar la llave `service_role` como secreto del espejo a Sheets

Hallazgo (reportes D y E): `api/espejo/route.ts` compara el token entrante
contra la llave real `SUPABASE_SERVICE_ROLE_KEY` (acceso total a la base,
bypass de RLS, `supabase.auth.admin.*`), y esa misma llave vive guardada en
Google Apps Script (`scripts/espejo-sheets.gs`), llamando además directo a
PostgREST en vez de pasar por esta ruta. Si esa llave se filtra por
cualquier vía relacionada a Sheets/Apps Script, quien la obtenga tiene
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

## 3. Actualizar `scripts/espejo-sheets.gs`

Hoy ese script llama DIRECTO a PostgREST con la llave `service_role` (no
pasa por `/api/espejo` en absoluto — vale la pena que confirmes cuál de los
dos está corriendo de verdad en la hoja de producción antes de tocar nada).
El cambio real es dejar de mandar la llave real y, en su lugar:
- Guardar el nuevo `ESPEJO_TOKEN` (el mismo valor del paso 2) en
  "Propiedades del script" de Apps Script, reemplazando donde hoy vive la
  llave `service_role`.
- Apuntar la llamada a `https://cayla-dynamic.vercel.app/api/espejo` (esta
  ruta) en vez de a PostgREST directo, con
  `Authorization: Bearer <ESPEJO_TOKEN>`.

No incluyo el `.gs` reescrito completo porque no lo leí en esta revisión
(quedó fuera de lo que los agentes tocaron a fondo) — pero el cambio es
literalmente reemplazar el valor guardado y, si el script llama a PostgREST
directo, cambiar la URL de destino a la ruta de arriba.

## 4. Rotar la llave `service_role` real

Dado que ya circuló por Apps Script (Google), conviene rotarla en el
dashboard de Supabase (Settings → API → regenerar `service_role`) una vez
que los pasos de arriba estén funcionando — así el valor viejo, que ya
estuvo expuesto, deja de servir para nada. Ojo: rotar esa llave rompe
temporalmente `api/admin/cuentas` y `api/reabrir-dia` hasta que actualices
la variable de entorno `SUPABASE_SERVICE_ROLE_KEY` en Vercel con el valor
nuevo — hacerlo en el mismo despliegue, no por separado.
