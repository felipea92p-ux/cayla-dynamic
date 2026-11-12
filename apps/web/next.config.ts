import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs/config";

const nextConfig: NextConfig = {
  // La versión de este despliegue, horneada en el navegador al construir. La
  // compara `components/aviso-version-nueva.tsx` con la que contesta
  // `/api/version`. Vacía fuera de Vercel: ver lib/version-despliegue.ts.
  env: {
    NEXT_PUBLIC_VERSION_DESPLIEGUE: process.env.VERCEL_DEPLOYMENT_ID ?? "",
  },

  // Solo en Vercel, `next build` no vuelve a revisar los tipos (2026-11-12). Vercel cobra la compilación por minuto y
  // por núcleo —US$ 84 de una factura de 102— y esa revisión ya la hace el CI ANTES de fusionar: `pnpm typecheck` en el
  // job `ui-tests`, obligatorio para entrar a `main`. Ese typecheck corre `next typegen` antes de `tsc`, así que revisa
  // también el validador de rutas que genera Next (`.next/types/validator.ts`), que era lo único que `next build`
  // revisaba y `tsc` solo no. Fuera de Vercel —el CI, la máquina de cada uno— `next build` los sigue revisando.
  // Cuánto ahorra, medido: ~4 s por compilación en Vercel cuando trae la caché incremental de la anterior, ~30 s
  // cuando no (local en frío: 32.6 de 49 s de `next build`).
  typescript: { ignoreBuildErrors: process.env.VERCEL === "1" },
};

export default withSentryConfig(nextConfig, {
  // For all available options, see:
  // https://www.npmjs.com/package/@sentry/webpack-plugin#options

  org: "cayla",
  project: "cayla-dynamic",

  // Only print logs for uploading source maps in CI
  silent: !process.env.CI,

  // For all available options, see:
  // https://docs.sentry.io/platforms/javascript/guides/nextjs/manual-setup/

  // Upload a larger set of source maps for prettier stack traces (increases build time)
  widenClientFileUpload: true,

  // Route browser requests to Sentry through a Next.js rewrite to circumvent ad-blockers.
  // This can increase your server load as well as your hosting bill.
  // Note: Check that the configured route will not match with your Next.js middleware, otherwise reporting of client-
  // side errors will fail.
  tunnelRoute: "/monitoring",

  webpack: {
    // Enables automatic instrumentation of Vercel Cron Monitors. (Does not yet work with App Router route handlers.)
    // See the following for more information:
    // https://docs.sentry.io/product/crons/
    // https://vercel.com/docs/cron-jobs
    automaticVercelMonitors: true,

    // Tree-shaking options for reducing bundle size
    treeshake: {
      // Automatically tree-shake Sentry logger statements to reduce bundle size
      removeDebugLogging: true,
    },
  },
});
