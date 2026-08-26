// ============================================================================
// rpc-estricto.prueba-de-tipos.ts — el freno que vigila al freno
// ============================================================================
//
// QUÉ ES
//   No es una prueba de vitest: es una prueba que corre el COMPILADOR. Cada
//   `@ts-expect-error` de abajo dice «esta línea tiene que fallar». Si un día
//   deja de fallar —porque alguien deshizo `ClienteCayla`, porque una
//   actualización de supabase-js cambió la firma de `rpc`, o porque el cliente
//   volvió a ser el de la librería— TypeScript no se calla: emite
//   TS2578 «Unused '@ts-expect-error' directive» y el typecheck se cae.
//
//   Esa es la propiedad que hacía falta. Un guardián que se apaga en silencio
//   es peor que no tenerlo: aquí ya pasó con ESLint, instalado y configurado
//   desde julio, que nadie ejecutaba y que llegó a 131 errores sin que se
//   notara. Este no se puede apagar sin que el push se caiga, porque
//   `scripts/hooks/pre-push` corre `npx pnpm typecheck` y `packages/database`
//   incluye `src` entero.
//
//   Por eso también hay casos que DEBEN pasar: un freno probado solo con lo que
//   debe bloquear puede estar bloqueándolo todo y parecer sano.
//
//   El archivo es puramente de tipos —`declare const` no genera código— y no se
//   exporta desde `index.ts`, así que no entra en ningún paquete.
// ============================================================================

import type { ClienteCayla } from "./rpc-estricto";

declare const supabase: ClienteCayla;

// ── Lo que DEBE bloquear ────────────────────────────────────────────────────

export async function argumentoInventado() {
  await supabase.rpc("fn_expediente_generar_falta", {
    p_persona_id: "…",
    // @ts-expect-error — `p_inventado_xyz` no existe: PostgREST devolvería PGRST202.
    p_inventado_xyz: 1,
  });
}

export async function parametroOpcionalMalEscrito() {
  // El caso que más caro sale: nada falta, solo sobra una letra. Antes de
  // `ClienteCayla` esto compilaba y el botón moría en producción.
  await supabase.rpc("fn_aceptar_incidencia", {
    p_persona_id: "…",
    p_fecha: "2026-08-26",
    p_tipo: "tardanza",
    // @ts-expect-error — se llama `p_nota`, en singular.
    p_notas: "llegó tarde",
  });
}

export async function nombreDeFuncionInventado() {
  // @ts-expect-error — esa función no existe en el esquema.
  await supabase.rpc("fn_no_existe_en_ninguna_parte", { p_persona_id: "…" });
}

export async function parametroObligatorioAusente() {
  // @ts-expect-error — falta `p_persona_id`.
  await supabase.rpc("fn_expediente_generar_falta", {});
}

export async function tipoEquivocado() {
  await supabase.rpc("fn_expediente_generar_falta", {
    // @ts-expect-error — `p_persona_id` es un uuid, no un número.
    p_persona_id: 12345,
  });
}

export async function argumentosAUnaFuncionQueNoLosTiene() {
  // @ts-expect-error — `fn_actas_descanso` no recibe parámetros.
  await supabase.rpc("fn_actas_descanso", { p_lo_que_sea: 1 });
}

// ── Lo que DEBE pasar ───────────────────────────────────────────────────────

export async function llamadaCorrecta() {
  await supabase.rpc("fn_expediente_generar_falta", { p_persona_id: "…" });
}

export async function llamadaSinArgumentos() {
  await supabase.rpc("fn_actas_descanso");
}

export async function opcionalOmitido() {
  await supabase.rpc("fn_aceptar_incidencia", {
    p_persona_id: "…",
    p_fecha: "2026-08-26",
    p_tipo: "tardanza",
  });
}

export async function opcionalPresente() {
  await supabase.rpc("fn_aceptar_incidencia", {
    p_persona_id: "…",
    p_fecha: "2026-08-26",
    p_tipo: "tardanza",
    p_nota: "conversado con la encargada",
  });
}

export async function nullDondeElEsquemaLoAdmite() {
  // `tipos-args-nullables.mjs` existe justo para que esto compile.
  await supabase.rpc("fn_expediente_generar_falta", { p_persona_id: null });
}

// El tipo de retorno tiene que seguir siendo el de siempre, no `any`: si se
// perdiera, el freno habría cambiado un agujero por otro.
export async function elRetornoSigueTipado() {
  const { data } = await supabase.rpc("fn_actas_descanso");
  const filas: { referencia: string; registros: number }[] | null = data;
  return filas;
}

export async function elRetornoEscalarSigueTipado() {
  const { data } = await supabase.rpc("fn_expediente_generar_falta", { p_persona_id: "…" });
  const id: string | null = data;
  return id;
}
