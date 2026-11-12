import { buildSync } from "esbuild";
import { readFileSync } from "node:fs";

const [hrefEntry, findEntry, helperEntry] = process.argv.slice(2);
if (!hrefEntry || !findEntry || !helperEntry) {
  console.error("usage: node check.ts HREF_ENTRY FIND_ENTRY HELPER_ENTRY");
  process.exit(2);
}

const bundle = (entry: string): string => {
  const result = buildSync({
    entryPoints: [entry],
    bundle: true,
    minify: true,
    format: "esm",
    write: false,
    logLevel: "silent",
  });
  const file = result.outputFiles[0];
  if (!file) throw new Error(`no output for ${entry}`);
  return file.text;
};

const matcherMarkers = ["legacy-blog", "old-docs"];
const hrefMarker = "/docs";
const calledHelperMarker = "draft:";
const otherHelperMarkers = ["slug:", "seen:", "parts:"];

const entryMarkers: [string, string[]][] = [
  [hrefEntry, matcherMarkers],
  [findEntry, matcherMarkers],
  [helperEntry, [...matcherMarkers, calledHelperMarker, ...otherHelperMarkers]],
];
for (const [entry, markers] of entryMarkers) {
  const source = readFileSync(entry, "utf8");
  for (const marker of markers) {
    if (source.includes(marker)) {
      console.error(`FAIL entry ${entry} holds the marker ${marker}, so the check would prove nothing`);
      process.exit(1);
    }
  }
}

const href = bundle(hrefEntry);
const find = bundle(findEntry);
const helper = bundle(helperEntry);
const failures: string[] = [];

if (!href.includes(hrefMarker)) failures.push(`href bundle lacks ${hrefMarker}`);
for (const marker of matcherMarkers) {
  if (href.includes(marker)) failures.push(`href bundle holds matcher string ${marker}`);
  if (!find.includes(marker)) failures.push(`find bundle lacks ${marker}`);
  if (helper.includes(marker)) failures.push(`helper bundle holds matcher string ${marker}`);
}
if (!helper.includes(calledHelperMarker)) failures.push(`helper bundle lacks ${calledHelperMarker}`);
for (const marker of otherHelperMarkers) {
  if (helper.includes(marker)) failures.push(`helper bundle holds ${marker} of a helper it does not call`);
}

console.log(
  `href-only bundle: ${href.length} bytes; find bundle: ${find.length} bytes; helper bundle: ${helper.length} bytes`,
);
if (failures.length > 0) {
  for (const f of failures) console.error(`FAIL ${f}`);
  process.exit(1);
}
