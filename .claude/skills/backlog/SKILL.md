---
name: backlog
description: Audita el repo real de cayla-retail y reconstruye o actualiza /docs/BACKLOG.md con lo que falta construir, arreglar y mejorar.
---

1. Audita el repo de verdad: `supabase/migrations/*.sql`, `apps/web/app`, `apps/web/lib`,
   `apps/web/components`, `packages/*`. No asumas nada del backlog anterior sin
   confirmarlo contra el código.
2. Compara contra lo que ya está commiteado (`git log`) y lo que sigue pendiente según
   `CLAUDE.md` (principios, gap de Fase 2 financiera, etc.).
3. Reescribe `/docs/BACKLOG.md` respetando el máximo de 3 ítems por cubo (🔨 Construir,
   🩹 Arreglar, ✨ Mejorar). Si hay un décimo ítem real, no lo agregues — es señal de
   que no se está cerrando lo anterior.
4. Para cada ítem: qué desbloquea, de qué depende, si es reversible en menos de 30
   minutos (afecta si `/decide` pregunta o ejecuta directo), y por qué importa en
   términos de negocio, no solo técnicos.
5. Actualiza también "Conceptos pendientes de enseñar" si la auditoría revela algo que
   Felipe debería entender para poder auditar ese módulo.
6. Cierra con la ÚNICA cosa que harías hoy si solo pudieras hacer una, y por qué.
