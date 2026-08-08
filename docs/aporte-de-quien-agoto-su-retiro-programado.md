# Consulta a Dante — quién aporta cuando el retiro programado se agotó

**Qué es esto.** El texto listo para enviar. Una sola pregunta, porque de su
respuesta depende si a una persona se le descuenta o no el aporte previsional
todos los meses — y la respuesta correcta no se puede deducir del sistema.

**Por qué existe como documento.** Porque la decisión que provoca es permanente
y afecta el líquido de una persona mes a mes. Si se resuelve mal, el error se
repite hasta que alguien lo note, y para entonces son meses de descuentos
indebidos o de aportes que nunca se hicieron. Una conversación así merece quedar
escrita, no vivir en un chat.

**Sin datos personales.** No lleva nombres ni montos individuales: es un
documento del repositorio. Los datos de la persona van por el canal que Felipe
decida.

**De dónde sale.** El 2026-08-08 se preparó la migración
[`0190`](../supabase/migrations/0190_quien_ya_se_jubilo_deja_de_aportar.sql),
que crea el régimen `jubilada` con tasa 0 %. Su fundamento es el **art. 87 del
TUO del D.L. 25897**: los afiliados que **perciban** pensión de jubilación no
están obligados a aportar al SPP.

Antes de aplicarla a nadie apareció el dato que la deja en duda: la persona se
jubiló por **retiro programado** y **su fondo ya se agotó**. Sigue trabajando.
El verbo del artículo está en presente, y ahí está el problema: hoy no percibe.

**Estado: la migración está pegada pero NO se le asignó el régimen a nadie.**
Todo sigue exactamente como estaba hasta que llegue la respuesta.

---

## El texto para enviar

Dante, una consulta puntual sobre aportes previsionales.

Tenemos a una colaboradora en planilla que ya se jubiló por el SPP en la
modalidad de **retiro programado**, y **su fondo se agotó**: hoy no está
percibiendo pensión. Sigue trabajando con nosotros con normalidad.

Yo tenía entendido que el art. 87 del TUO del D.L. 25897 exime de aportar a
quien percibe pensión de jubilación, y con eso iba a dejar de descontarle. Pero
el artículo dice «perciban», en presente, y ella hoy no percibe. Antes de tocar
nada prefiero preguntarte:

1. **¿Sigue alcanzada por la exención del art. 87, o al agotarse el retiro
   programado vuelve a estar obligada a aportar?**

2. Si vuelve a aportar: ¿desde cuándo corresponde — desde que se agotó el fondo,
   o desde el mes en que lo regularicemos? Y si es desde antes, ¿cómo se
   regulariza lo que no se retuvo?

3. Y algo que no es de planilla pero me importa: al habérsele agotado el retiro
   programado, **¿le corresponde alguna pensión mínima o complemento del SPP?**
   Si califica, es un ingreso al que tiene derecho y que hoy no está recibiendo.
   Dime qué requisitos hay que verificar y por dónde se tramita.

Mientras tanto no cambiamos nada: se le sigue descontando como hasta hoy.

Gracias.

---

## Qué se hace con cada respuesta

| Si Dante dice | Qué hacemos |
|---|---|
| **Sigue exenta** | Cambiar su régimen a «Jubilada» desde `/admin/datos-personales` — desde ahí, no por SQL, para que la auditoría registre quién lo decidió |
| **Vuelve a aportar** | No se toca nada. La 0190 queda como herramienta para el caso que sí aplique: alguien con renta vitalicia, que no se agota |
| **Vuelve a aportar desde antes** | Hay que regularizar lo no retenido. Eso no se resuelve cambiando un campo: pídeme el cálculo periodo por periodo |

Y la pregunta 3 se persigue **en cualquiera de los tres casos**: no depende de
cómo quede el aporte.
