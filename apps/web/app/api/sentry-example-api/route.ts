import * as Sentry from "@sentry/nextjs";

// Ruta rota a propósito: la usa /sentry-example-page para comprobar que los errores
// del servidor llegan a Sentry. Se puede borrar una vez verificado.

class SentryExampleAPIError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SentryExampleAPIError";
  }
}

export const dynamic = "force-dynamic";

export async function GET() {
  Sentry.logger.info("Sentry example API called");
  throw new SentryExampleAPIError(
    "This error is raised on the backend called by the example page.",
  );
}
