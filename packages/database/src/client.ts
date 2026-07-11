import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./types";

/**
 * Sesiones SEPARADAS por superficie: el terminal de marcaje y el panel admin
 * guardan su sesión bajo claves distintas de localStorage. Así, si una
 * supervisora entra al panel desde la Mac mini de su sede, NO desconecta la
 * sesión del terminal de marcaje (y viceversa).
 *
 * Todas las pantallas de este MVP son "use client" con sesión en localStorage,
 * así que no se necesita el manejo de cookies SSR de @supabase/ssr.
 */

const clientes: Partial<Record<string, SupabaseClient<Database>>> = {};

function crearClienteConAlmacen(storageKey: string): SupabaseClient<Database> {
  if (!clientes[storageKey]) {
    clientes[storageKey] = createClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { auth: { storageKey } },
    );
  }
  return clientes[storageKey]!;
}

/** Cliente del TERMINAL de marcaje (sesión persistente del dispositivo fijo de la sede). */
export function createTerminalSupabaseClient(): SupabaseClient<Database> {
  return crearClienteConAlmacen("cayla-auth-terminal");
}

/** Cliente del PANEL DE ADMINISTRACIÓN (sesión personal de admin/supervisor). */
export function createAdminSupabaseClient(): SupabaseClient<Database> {
  return crearClienteConAlmacen("cayla-auth-admin");
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
