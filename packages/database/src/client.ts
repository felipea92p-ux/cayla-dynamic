import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./types";

let browserClient: SupabaseClient<Database> | undefined;

/**
 * Cliente para Client Components (terminal y admin) — respeta RLS del usuario/terminal
 * autenticado. Todas las pantallas de este MVP son "use client" con sesión
 * persistida en localStorage (comportamiento por defecto), así que no se necesita
 * el manejo de cookies SSR de @supabase/ssr.
 */
export function createBrowserSupabaseClient(): SupabaseClient<Database> {
  if (!browserClient) {
    browserClient = createClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    );
  }
  return browserClient;
}

/**
 * Cliente con service role — SOLO para Edge Functions/servidor de confianza
 * (auto-cierre cron, sheets-sync). Nunca importar este módulo desde código
 * que se ejecuta en el navegador.
 */
export function createServiceRoleClient(): SupabaseClient<Database> {
  return createClient<Database>(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  );
}
