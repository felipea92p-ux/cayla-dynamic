---
name: backlog
description: Audita el repo real de Dynamic y propone qué falta construir, arreglar y mejorar, reconciliando docs/estado.md y docs/hallazgos-abiertos.md contra el código. Solo propone; Felipe aprueba antes de que se edite ningún archivo de estado.
---

> Adaptada de `backlog` de `cayla-retail` (2026-10-13). Cambia una cosa de fondo:
> en retail existe `BACKLOG.md` y la skill lo reescribe. **Aquí no hay backlog**:
> `docs/estado.md` es el único archivo de estado (se sobrescribe) y
> `docs/hallazgos-abiertos.md` el catálogo de lo mal. Varias sesiones los editan a la
> vez, así que esta skill **propone y no escribe** ahí.

1. Antes de nada: `./scripts/sesiones.sh`, `git fetch origin` y `git log --all --oneline -20`. Si otra rama ya construye lo que vas a listar, dilo.
2. Audita el repo de verdad: `supabase/migrations/*.sql` (`./scripts/siguiente-numero.sh` y `./scripts/que-falta-pegar.sh` para saber qué hay sin pegar), `apps/web/app`, `apps/web/lib`, `apps/web/components`, `packages/*`, `tests/`. No asumas nada de `estado.md` sin confirmarlo contra el código: ya describió como pendiente cosas fusionadas.
3. Compara contra lo commiteado (`git log`) y contra `docs/hallazgos-abiertos.md`. Marca cada hallazgo: **sigue abierto · ya cerrado en código (tachar) · no se reproduce hoy (tachar y anotar por qué)**.
4. Propón una lista de **máximo 3 ítems por cubo** (🔨 Construir, 🩹 Arreglar, ✨ Mejorar). Si hay un décimo ítem real, no lo agregues: es la señal de que no se está cerrando lo anterior.
5. Para cada ítem: qué desbloquea, de qué depende, si es reversible en menos de 30 minutos (decide si `/decide` pregunta o ejecuta), si **necesita SQL** (y por tanto Felipe a mano, con la migración pegada antes de fusionar), y por qué importa en términos de negocio — plata, falsos positivos, obligación legal — no solo técnicos.
6. Cierra con la ÚNICA cosa que harías hoy si solo pudieras hacer una, y por qué.

Entrega la propuesta en el chat con el formato de líneas listas para pegar en `hallazgos-abiertos.md`. No editas `estado.md`, `hallazgos-abiertos.md` ni `docs/historico.md`.
