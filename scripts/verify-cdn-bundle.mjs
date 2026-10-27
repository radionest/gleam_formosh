// `lustre_dev_tools` swallows esbuild bundling failures into exit code 0
// (issue #87), so `npm run build` can report success while `dist/cdn.min.mjs`
// is stale or missing. Run after the bundling step and fail loudly instead.
import { existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";

// fileURLToPath, not .pathname: on Windows a file URL's pathname starts with
// "/C:/", which existsSync rejects.
const bundle = fileURLToPath(new URL("../dist/cdn.min.mjs", import.meta.url));

if (!existsSync(bundle)) {
  console.error(`formosh build: ${bundle} was not produced — the bundling step likely failed silently (issue #87).`);
  process.exit(1);
}

const size = statSync(bundle).size;
if (size < 10_000) {
  console.error(`formosh build: ${bundle} is only ${size} bytes — suspiciously small for the minified bundle.`);
  process.exit(1);
}

console.log(`formosh build: ${bundle} looks fine (${size} bytes).`);
