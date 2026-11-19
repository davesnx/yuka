globalThis.__errors = [];
console.error = function (message, error) {
  globalThis.__errors.push({ message: String(message), stack: error instanceof Error && typeof error.stack === "string" });
};
