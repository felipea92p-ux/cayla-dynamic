# Guía de pegado

**No hay pasos que seguir acá. Pregúntale al repositorio.**

```bash
./scripts/que-falta-pegar.sh     # genera la consulta: qué falta en producción
./scripts/dame-el-sql.sh 178     # te entrega esa migración, si está a salvo
```

`que-falta-pegar.sh` escribe una consulta que se pega en el SQL Editor y responde
migración por migración cuál falta, y además **en qué versión está viva
`fn_planilla_calcular`** — que es lo único que el registro por sí solo no puede
decirte.

`dame-el-sql.sh` se niega a darte un archivo que no esté en git, que tenga cambios
sin commitear o que no esté en GitHub byte por byte. Y avisa si lo que pides
**revierte** una función que una migración posterior ya arregló.

---

## Por qué esto ya no es una lista de pasos

Este archivo tenía 362 líneas y siete pasos numerados, del `aplicar_0162` al
`aplicar_0168`. Todos aplicados en producción hace tiempo.

El 2026-08-08 se descubrió que seguirlo **habría revertido la planilla**. El paso
5 mandaba pegar `aplicar_0166.sql`, y ese archivo llevaba dentro el cuerpo entero
de `fn_planilla_calcular` en su versión de julio. Pegarlo para arreglar la
movilidad —que es lo que la guía prometía— habría deshecho en silencio todo lo
que se corrigió después: el plus por objetivos, el feriado del sueldo fijo, y las
vacaciones pagadas como días trabajados.

Eso fue exactamente lo que pasó, aunque no se pudo saber con qué archivo. Se
detectó porque la 0177 figuraba como aplicada mientras la función corría el cuerpo
de la 0173.

**Una guía con pasos numerados caduca el día que se pega el primero, y no avisa
de que caducó.** Es la misma lección que el nombre de este archivo ya llevaba
escrito arriba —la primera versión se llamaba `GUIA_pegado_0162_a_0167.md` y
quedó desfasada en dos horas—, solo que la lección estaba en el título y el
contenido seguía siendo una lista.

Lo que no caduca es preguntarle a producción qué le falta.

---

## Las dos cosas que sí conviene recordar

**El registro puede mentir.** Una migración anotada como aplicada NO prueba que su
contenido siga vivo: un pegado posterior pudo pisarlo sin dar error. Y no queda
rastro, porque el apunte se hace con `on conflict (numero) do nothing` — al
repegar, la fila no se actualiza y la hora sigue siendo la del primer pegado. Por
eso la consulta de `que-falta-pegar.sh` compara además el `md5` del cuerpo real.

**Antes de copiar el cuerpo de cualquier función, pregunta cuál es la vigente:**

```bash
./scripts/donde-vive.sh fn_planilla_calcular
```

Tiene 27 versiones repartidas por el repo. Copiar de cualquiera que no sea la
última revierte en silencio todo lo que se arregló entre medias.
