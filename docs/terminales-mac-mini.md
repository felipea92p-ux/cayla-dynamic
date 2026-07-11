# Configurar el terminal de marcaje en la Mac mini de cada sede

Guía para dejar la Mac mini de TRU, LIM o AQP funcionando como terminal de
marcaje. Se hace **una sola vez por sede** y toma ~5 minutos.

> Reemplaza `URL_DE_LA_APP` por la dirección real (ej. `https://cayla-dynamic.vercel.app`)
> en todos los pasos. Esa dirección se define al desplegar en Vercel.

## 1. Vincular el dispositivo (una sola vez)

1. Abre **Safari** (o Chrome) en la Mac mini.
2. Entra a `URL_DE_LA_APP/terminal`.
3. Aparecerá "Vincular este dispositivo". Ingresa las credenciales del
   terminal de **esa sede** (las tiene Felipe; una por sede: TRU, LIM, AQP).
4. Al vincular, verás la pantalla de marcaje con los nombres del equipo de la
   sede. La vinculación queda guardada — no se vuelve a pedir salvo que se
   borren los datos del navegador.

⚠️ **No borrar historial/datos de navegación** de este navegador: eso
desvincula el terminal (se re-vincula con las mismas credenciales, pero
mejor evitarlo).

## 2. Pantalla completa

- En Safari/Chrome: menú **Visualización → Usar pantalla completa**
  (o `⌃⌘F`). Así solo se ve la app de marcaje.

## 3. Que arranque solo al encender la Mac mini

1. **Ajustes del Sistema → General → Ítems de inicio de sesión**.
2. Agrega Safari (o Chrome) con **+**.
3. En Safari: **Safari → Ajustes → General → "Safari se abre con: Todas las
   ventanas de la última sesión"** — así al reiniciar vuelve directo al
   terminal de marcaje.

Recomendado además:
- **Ajustes → Pantalla de bloqueo**: poner "Iniciar protector de pantalla" y
  "Apagar pantalla" en **Nunca** (o un tiempo largo) durante el horario de
  tienda, para que la pantalla esté siempre lista para marcar.
- **Ajustes → General → Inicio de sesión automático** para el usuario de la
  tienda, de modo que un corte de luz no deje la Mac esperando contraseña.

## 4. Uso diario (para el equipo)

1. Toca tu **nombre** en la pantalla.
2. Ingresa tu **PIN de 4 dígitos** (es personal — no lo compartas).
3. La app decide sola si corresponde Entrada, Salida o Regreso. Si estás
   saliendo, elige el motivo (salida final, almuerzo, asunto personal,
   trámite, salud u otro).
4. Confirma (o espera 3 segundos y se confirma solo). Listo.

**¿Te equivocaste?** Presiona **Cancelar** dentro de los 3 segundos. Si ya se
confirmó, avisa a tu supervisora para que lo corrija desde el panel.

**¿Se fue el internet?** Marca igual — el terminal guarda el marcaje y lo
envía solo cuando vuelva la conexión. No marques dos veces.

## 5. Si algo falla

| Problema | Solución |
|---|---|
| "Vincular este dispositivo" aparece de nuevo | Se borraron los datos del navegador. Re-vincular con las credenciales de la sede. |
| No aparece un nombre en la lista | La persona no está registrada como activa en esa sede — avisar a Felipe/Carlos. |
| "PIN incorrecto" 5 veces | Espera unos segundos y reintenta. Si se olvidó el PIN, Felipe/Carlos genera uno nuevo. |
| La pantalla quedó en otra página | Volver a `URL_DE_LA_APP/terminal`. |
