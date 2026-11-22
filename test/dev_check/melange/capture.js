globalThis.__errors = [];
console.error = function (message, error) {
  globalThis.__errors.push({ message: String(message), stack: error instanceof Error && typeof error.stack === "string" });
};
globalThis.__logs = [];
const log = console.log;
console.log = function (message) {
  if (typeof message === "string" && message.startsWith("[yuka] ")) globalThis.__logs.push(message);
  else log.apply(console, arguments);
};
