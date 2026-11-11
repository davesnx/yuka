import { build, type Format, type Metafile, type Plugin } from "esbuild";
import { minify } from "@swc/core";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import { pathToFileURL } from "node:url";

export interface BundleOptions {
  entry: string;
  outdir: string;
  format: "iife" | "esm";
  splitting?: boolean;
  metafile?: string;
  cwd?: string;
}

const pure: Plugin = {
  name: "yuka-pure",
  setup(build) {
    build.onResolve({ filter: /\.js$/ }, async (args) => {
      if (args.pluginData === pure) return undefined;
      const resolved = await build.resolve(args.path, {
        kind: args.kind,
        importer: args.importer,
        resolveDir: args.resolveDir,
        pluginData: pure,
      });
      if (resolved.errors.length > 0) return { errors: resolved.errors };
      return /[\\/]node_modules[\\/]yuka(\.js)?[\\/]/.test(resolved.path) ? { ...resolved, sideEffects: false } : resolved;
    });
  },
};

export async function bundle(options: BundleOptions): Promise<Metafile> {
  const cwd = resolve(options.cwd ?? process.cwd());
  const format: Format = options.format;
  const result = await build({
    absWorkingDir: cwd,
    entryPoints: [options.entry],
    bundle: true,
    minify: true,
    define: { __YUKA_DEV__: "false" },
    format,
    splitting: options.splitting ?? false,
    outdir: options.outdir,
    write: false,
    metafile: true,
    logLevel: "warning",
    plugins: [pure],
  });
  const esm = format === "esm";
  for (const file of result.outputFiles) {
    mkdirSync(dirname(file.path), { recursive: true });
    if (!file.path.endsWith(".js")) {
      writeFileSync(file.path, file.contents);
      continue;
    }
    const { code } = await minify(file.text, {
      module: esm,
      compress: { passes: 3 },
      mangle: { toplevel: esm },
    });
    writeFileSync(file.path, code);
  }
  if (options.metafile !== undefined) writeFileSync(resolve(cwd, options.metafile), JSON.stringify(result.metafile));
  return result.metafile;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { values } = parseArgs({
    options: {
      entry: { type: "string" },
      outdir: { type: "string" },
      format: { type: "string", default: "iife" },
      splitting: { type: "boolean", default: false },
      metafile: { type: "string" },
    },
  });
  const { entry, outdir, format } = values;
  if (entry === undefined || outdir === undefined || (format !== "iife" && format !== "esm")) {
    console.error("usage: node scripts/bundle.ts --entry FILE --outdir DIR [--format iife|esm] [--splitting] [--metafile FILE]");
    process.exit(2);
  }
  await bundle({ entry, outdir, format, splitting: values.splitting, metafile: values.metafile });
}
