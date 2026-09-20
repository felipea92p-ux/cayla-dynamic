# Probar las boletas oficiales de punta a punta

**Para quién:** quien vaya a publicar las primeras boletas (DO, Felipe).
**Cuándo:** una vez, antes de usarlas con el equipo; y de nuevo si se toca la subida,
el visor o las políticas del bucket.

## Por qué hace falta

La 0482 está en producción y la Planilla ya enlaza a «Boletas», pero **nadie ha visto
estas pantallas funcionar de punta a punta**. Lo que sí está probado es la base
(pgTAP 380, 86 aserciones según `estado.md`, contra Supabase real en CI) y funciones
puras (≈ 70 casos en `tests/boletas*.test.ts` y `tests/mis-boletas.test.ts`). Lo que **no** cubre ninguna
prueba automática: la cámara del celular, Storage de verdad, el visor, el aspecto en
375 px, el giro de una foto, un HEIC en Chrome. Este recorrido es eso.

## Antes de empezar

1. **Usa tu propia boleta, de un periodo cuyo grupo ya esté pagado.** La boleta oficial
   solo existe cuando el pago de tu grupo está en `pagado` (0482): Septiembre aún no.
   Usa el último periodo pagado.
2. **Todo lo que se sube queda para siempre.** Archivos y versiones no se editan ni se
   borran, solo se anulan con motivo. Por eso: **tu boleta real**, no un papel cualquiera.
   Si funciona, es la primera boleta real; si algo falla, se anula y se sube de nuevo.
3. **No pruebes con las boletas del equipo.**
4. Ten a mano: el PDF de tu boleta (mejor de 2 o más hojas), dos fotos de la boleta
   impresa hechas con el celular (una de ellas girada de lado), un iPhone (Safari), un
   Android (Chrome) y una computadora con Chrome.
5. Tú eres DO y persona a la vez: sube desde `/admin/planilla/boletas` y mira lo que ve
   una persona en `/mio` → pestaña **Boletas**.

## El recorrido

Marca cada paso. «Esperado» es lo que debe pasar; si no pasa, anota qué viste (captura).

**A · DO sube un PDF.** `/admin/planilla` → «Boletas de este periodo →» (o
`/admin/planilla/boletas`), elige el periodo pagado, tu fila → **Subir boleta** → el PDF →
**Guardar versión 1**.
*Esperado:* queda en borrador. En `/mio` → Boletas **no** aparece todavía.

**B · Publicar.** **Publicar boletas**: el modal lista tu boleta con su miniatura y «Ver».
Publica.
*Esperado:* estado «Publicada», con «Sin abrir» y «Sin confirmar».

**C · La persona la abre.** Antes de abrir: aviso en la Bandeja y globito en el menú.
`/mio` → Boletas → **Ver**.
*Esperado:* el visor muestra las hojas en orden y se lee sin acercar demasiado, también
en el celular. Al abrirla el aviso desaparece y en DO la fila dice «Vista <fecha>».

**D · Guardar.** **Guardar** descarga cada hoja.
*Esperado:* el archivo baja con nombre legible y se abre.

**E · Confirmar.** Intenta **Confirmar que la recibí** ANTES de abrirla.
*Esperado:* no se puede (la base lo prohíbe). Ábrela, confirma; DO ve «Confirmada».

**F · Fotos, en otro periodo pagado** (una versión es de un solo tipo: todas fotos o todos
PDF). Sube las dos fotos; en la que salió de lado usa **Girar ↻**.
*Esperado:* las miniaturas quedan derechas. **Lee las cifras más pequeñas de la boleta**
en el visor: las fotos se reducen a 2 000 px de lado (≈ 170 puntos por pulgada en una
hoja A4) y no debe perderse ningún dígito. Si se pierde, hay que subir el tope.
Repite con un HEIC desde **Chrome en computadora**: debe decir «No pudimos leer esa
foto… guárdala como JPG», no fallar callado. En Safari del iPhone debe funcionar.

**G · Versión 2.** **Editar** la boleta del paso A.
- Solo reordena las hojas y **desmarca** «Avisar y pedir confirmar de nuevo» →
  *esperado:* la confirmación de la versión 1 se hereda.
- Quita o agrega una hoja → *esperado:* el aviso es obligatorio aunque lo desmarques; la
  persona vuelve a ver «Sin abrir». **Historial** conserva la constancia de la versión 1.

**H · Anular.** Anula la boleta del paso F, no la del A si quieres conservarla:
**Anular**, con un motivo de 5 letras o más.
*Esperado:* en `/mio` ya no aparece y, si tenías el visor abierto, al recargar deja de
abrir. El archivo sigue en Storage (por diseño: no se borra).

No pruebes «Marcar entregada en papel» con personas reales.

## Comprobar en la base (solo lectura, SQL Editor)

```sql
select b.estado, b.publicada_at, v.n, v.avisar, a.vista_at, a.recibida_at
  from boletas b
  join personas p on p.id = b.persona_id
  join boletas_versiones v on v.boleta_id = b.id
  left join boletas_acuses a on a.version_id = v.id
 where p.nombres ilike '%<tu nombre>%'
 order by b.periodo_id, v.n;

select count(*) as archivos_en_el_bucket
  from storage.objects where bucket_id = 'boletas';
```

Deben coincidir las versiones y las marcas de «vista» y «recibida» con lo que hiciste.

## Lo que esta prueba NO cubre

- **Que otra persona no vea tu boleta.** Lo garantiza pgTAP 380 contra una base real; aquí
  no se comprueba. Si quieres verlo con tus ojos, pide a UNA integrante de confianza con
  cuenta que abra `/mio` → Boletas: solo debe ver las suyas.
- **Storage caído.** No se puede simular; ver «LO QUE SE PUEDE PERDER» en la 0482.
- **Que el respaldo de los archivos exista.** Eso es
  [`scripts/respaldar-boletas.sh`](../scripts/respaldar-boletas.sh); léelo antes de la
  primera publicación real.

## Resultado

Anota aquí cada corrida (fecha, quién, dispositivo, qué falló). Si sale limpia, borra las
dudas de la entrada «Boletas oficiales» de `docs/estado.md`.

| Fecha | Quién | Dispositivo y navegador | Pasos A–H | Qué falló |
|---|---|---|---|---|
| | | | | |
