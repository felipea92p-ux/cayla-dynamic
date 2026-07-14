# Dynamic — para retomar el 2026-07-14

Revisión de cierre del 2026-07-13. Nada roto: producción sigue en el deploy de
hace 6h (sin las columnas nuevas), el equipo puede marcar y usar el panel con
normalidad. Todo lo de abajo está construido, con typecheck en verde, y
**esperando un solo bloqueador** para salir a producción.

## 🔴 Bloqueador #1 (antes que nada mañana)

**El caché de PostgREST (API de Supabase) no reconoce 2 columnas nuevas**
(`jornadas.minutos_salida_temprana`, `personas.funcion`), aunque:
- ✅ Existen en la base (`information_schema.columns` → 2 filas)
- ✅ Los permisos están bien (`has_column_privilege` → true/true)
- ❌ NOTIFY ×3, restart (plan gratis y ya en Pro), cambio de "Max rows", y el
  propio upgrade a Pro — ninguno lo destrabó.

Ya se mandó un ticket a soporte de Supabase (ahora con prioridad Pro).

**Checklist al retomar:**
- [ ] Revisar si llegó respuesta de soporte de Supabase (email).
- [ ] Correr esta prueba (server o SQL) — si da 2/2, ya se puede desplegar:
  ```
  cd ~/Proyectos/cayla-dynamic && set -a && . ./apps/web/.env.local && set +a
  node -e "import('@supabase/supabase-js').then(async ({createClient})=>{const s=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,{auth:{persistSession:false}});let n=0;for(const [t,c] of [['jornadas','minutos_salida_temprana'],['personas','funcion']]){const{error}=await s.from(t).select(c).limit(1);if(!/does not exist|schema cache/i.test(error?.message??''))n++;}console.log(n+'/2');});"
  ```
- [ ] Si sigue en 0/2 tras la respuesta de soporte: probar UN restart más
  (ahora en Pro, infra dedicada — no debería toparse con el incidente viejo).
- [ ] En cuanto dé 2/2 → `cd ~/Proyectos/cayla-dynamic && npx vercel --prod --yes`.

*(Nota: `scripts/esperar-columnas.mjs` quedó corriendo en segundo plano
vigilando esto — si sigue viva la sesión, avisa solo cuando destrabe.)*

## ✅ Construido y probado, solo esperando el deploy de arriba

1. **Salida anticipada** 🟠 y **Tiempo adicional** 🟢 — contra el horario de
   cada día, con tolerancia de 15 min (dentro de eso no se marca). La
   tardanza de entrada sigue sin tolerancia, pero ahora es **por minuto**
   (segundos dentro del minuto no cuentan) — **esta parte YA está viva**
   (no depende de columnas nuevas, se aplicó con el resto de la 0017).
   No se miden en jornadas auto-cerradas (salida sintética).
   Se ven en: Dashboard (hoy), Incidencias (para revisar), Horas y Perfil
   (periodo), CSV.
2. **Función de persona** (Atención al cliente / Ejecutivo / Procesos) —
   editable en Equipo. La cobertura de Turnos cuenta **solo** Atención al
   cliente (Carlos como ejecutivo, por ejemplo, no debe sumar).
3. Revisión adversarial: 2 rondas sobre esto, hallazgos reales arreglados
   (tope de implausibilidad en tiempo adicional, y exclusión de auto-cierre).

**Verificar al desplegar** (5 min con el equipo real):
- [ ] Perfil de Estefany (o alguien con horario variado) — confirmar que
  "Tardanza" ya no cuenta los segundos dentro del minuto.
- [ ] Marcar una salida claramente antes de hora → ver "Sal. antic." en
  Dashboard/Horas/Perfil.
- [ ] Poner a Carlos como "Ejecutivo" en Equipo → confirmar que la fila
  "Programados / meta" de Turnos deja de contarlo.

## 📋 Pendiente sin bloqueo técnico (se puede seguir cuando quieras)

- **Cuenta de Estefany**: sigue sin correo en `datos-privados/correos.json`.
  Pedirle el correo a Felipe, o crearle la cuenta manualmente desde
  `/admin/cuentas` cuando la tenga.
- **Cobertura en vivo en el dashboard** — cuántos presentes AHORA vs meta.
- **Metas de cobertura por sede/día** — Felipe debe pasar datos de ventas.
- **Proyección de planilla** — Felipe debe pasar tarifas por persona.
- **Espejo a Google Sheets más legible** — encabezados fijos, 1 fila/persona.
- **Franjas horarias** (mañana/tarde) para cobertura más fina — fase 2.

## Commits pendientes

Todo lo de hoy está sin commitear (`git status` muestra los cambios). Cuando
el deploy quede confirmado funcionando, conviene commitear en 2-3 tandas
lógicas (turnos+cobertura / horario por día / salida anticipada+función) en
vez de un commit gigante.
