type LogLevel = "debug" | "info" | "warn" | "error";

type LogContext = Record<string, unknown>;

function emit(level: LogLevel, message: string, context?: LogContext): void {
  const entry = {
    level,
    message,
    timestamp: new Date().toISOString(),
    ...sanitize(context),
  };

  if (level === "error") {
    console.error(entry);
    return;
  }
  if (level === "warn") {
    console.warn(entry);
    return;
  }
  if (process.env.NODE_ENV !== "production") {
    console.info(entry);
  }
}

function sanitize(context?: LogContext): LogContext {
  if (!context) {
    return {};
  }

  const blocked = new Set([
    "password",
    "token",
    "access_token",
    "refresh_token",
    "service_role",
    "authorization",
    "cookie",
    "secret",
  ]);

  return Object.fromEntries(
    Object.entries(context).filter(([key]) => !blocked.has(key.toLowerCase())),
  );
}

export const logger = {
  debug(message: string, context?: LogContext) {
    emit("debug", message, context);
  },
  info(message: string, context?: LogContext) {
    emit("info", message, context);
  },
  warn(message: string, context?: LogContext) {
    emit("warn", message, context);
  },
  error(message: string, context?: LogContext) {
    emit("error", message, context);
  },
};
