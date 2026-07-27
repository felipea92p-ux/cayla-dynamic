# `scripts/sql-manual/` — el SQL listo para pegar

Esta es la carpeta de la que se copia y se pega en el **SQL Editor de Supabase**.
Es la más peligrosa del repo: lo que sale de acá entra directo a producción sin
que nadie lo revise en el camino.

## La regla

**Un archivo vive acá solo mientras esté pendiente de aplicarse.**
En cuanto se aplica en producción y queda registrado en `migraciones_aplicadas`,
se borra. Su contenido ya vive en `supabase/migrations/`, que es la fuente.

## Por qué

El 27-07-2026 se encontraron **cinco archivos que ya no coincidían con su
migración**. El peor, `aplicar_0017.sql`, calculaba la tardanza con `round`
donde el sistema real usa `floor`:

| Alguien llega 9:00:35 | Sistema actual | Ese script |
|---|---|---|
| tardanza registrada | **0 minutos** | **1 minuto** |

Pegarlo habría hecho que todo el equipo acumulara tardanzas por segundos, y las
tardanzas alimentan el semáforo disciplinario: se habrían disparado avisos de
"patrón de tardanzas" contra gente que llegó a tiempo. Es exactamente el error
que este sistema define como el peor —acusar a quien no debía— y estaba a un
copiar-pegar de distancia.

Nadie los dejó ahí por descuido: sirvieron cuando se aplicaron, en 2026. El
problema es que después las migraciones siguieron corrigiéndose y su copia no.
Una copia que envejece en silencio es peor que no tener copia.

Se borraron las cinco (`0014_0015`, `0017`, `0017_0018`, `0019`, `0020`). Están
en el historial de git si alguna vez hicieran falta.

## Cómo comprobar que no volvió a pasar

```bash
for a in scripts/sql-manual/aplicar_*.sql; do
  n=$(basename "$a" | grep -oE "00[0-9]{2}" | head -1)
  m=$(ls supabase/migrations/${n}_*.sql 2>/dev/null | head -1)
  [ -n "$m" ] && d=$(diff <(grep -vE "^\s*--|^\s*$" "$m") <(grep -vE "^\s*--|^\s*$" "$a") | wc -l) \
    && [ "$d" -gt 0 ] && echo "⚠  $(basename $a) diverge de su migración"
done
```

Un archivo que agrupa varias migraciones (como `aplicar_0076_a_0080.sql`) va a
salir siempre como divergente: se compara contra una sola. Eso es esperado.

## Lo que no se borra

- **Scripts con datos personales** (`aplicar_0031`, `aplicar_0033`): están fuera
  de git a propósito, en `.gitignore`. No tienen migración fuente y por eso son
  la única copia que existe.
- **Consultas de diagnóstico** (`consulta_*`, `registrar_*`, `quitar_*`): no
  aplican migraciones, se corren cuando hacen falta.
