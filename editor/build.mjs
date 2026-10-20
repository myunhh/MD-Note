import { build } from "esbuild";
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

await build({
  entryPoints: ["editor.js"], bundle: true, minify: true, format: "iife",
  globalName: "MDNoteRichEditor", target: "safari17",
  outfile: "../MDNote/Resources/WebAssets/vendor/editor.js"
});
const licenses = [];
for (const name of readdirSync("node_modules").sort()) {
  if (name.startsWith(".") || name.startsWith("@") || name === "esbuild") continue;
  const folder = join("node_modules", name);
  const license = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENSE-MIT"].find(file => existsSync(join(folder, file)));
  if (license) licenses.push(`${name}\n${readFileSync(join(folder, license), "utf8")}`);
}
writeFileSync("../MDNote/Resources/WebAssets/vendor/editor-LICENSES.txt", licenses.join("\n\n"));
