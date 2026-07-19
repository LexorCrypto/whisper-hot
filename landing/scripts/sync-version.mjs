// Syncs landing/lib/version.ts with the repo-root VERSION file, so the
// landing page always ships with the same version string as the app build.
// Runs via `prebuild`/`predev`; never fails the build if VERSION is missing.
import { readFile, writeFile } from "node:fs/promises";

const versionFileUrl = new URL("../../VERSION", import.meta.url);
const targetFileUrl = new URL("../lib/version.ts", import.meta.url);

try {
  const raw = await readFile(versionFileUrl, "utf8");
  const version = raw.split("\n")[0].trim();

  if (!version) {
    throw new Error("VERSION file is empty");
  }

  await writeFile(targetFileUrl, `export const BUILD_VERSION = "${version}";\n`, "utf8");
} catch (err) {
  console.warn(`[sync-version] skipped: ${err instanceof Error ? err.message : err}`);
}
