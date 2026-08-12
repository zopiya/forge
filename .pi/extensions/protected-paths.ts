/**
 * Protected Paths Extension
 *
 * Blocks write and edit operations to protected paths.
 * Useful for preventing accidental modifications to sensitive files.
 *
 * Vendored from earendil-works/pi packages/coding-agent/examples/extensions
 * (same vendoring pattern as .pi/extensions/subagent/, see docs/design.md).
 *
 * Deviations from upstream (see docs/design.md §9.12):
 * - Reads `event.input.file_path` as a fallback when `path` is absent. The
 *   built-in write/edit tools accept both field names (dist/core/tools/write.js:
 *   `args?.file_path ?? args?.path`) — upstream only read `path`, which throws
 *   on `undefined.includes()` the moment a model emits `file_path` instead
 *   (the same "assumed field name" class of bug already fixed once this
 *   session for the scout/planner/reviewer/builder tool lists).
 * - Matches by path *segment* instead of substring. Upstream's
 *   `path.includes(".env")` also blocks unrelated files like
 *   `some.envfile.txt`; `.git/`/`node_modules/` substring checks had the same
 *   false-positive risk for oddly-named paths. Now checks the exact basename
 *   (`.env` or `.env.*`) and exact directory segments (`.git`,
 *   `node_modules`) after normalizing `\` to `/`, so it behaves the same on
 *   Windows-style paths too.
 *
 * Deliberately no confirmation prompt — this is a silent hard block, not the
 * "confirm before destructive action" guardrail APPEND_SYSTEM.md/§3.4
 * already decided against. The container boundary doesn't undo a secret
 * that already made it into a commit/push; that's the specific gap this
 * closes.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PROTECTED_DIR_SEGMENTS = new Set([".git", "node_modules"]);

function isProtectedPath(rawPath: string): boolean {
	const segments = rawPath.replace(/\\/g, "/").split("/").filter(Boolean);
	if (segments.length === 0) return false;

	const basename = segments[segments.length - 1];
	if (basename === ".env" || basename.startsWith(".env.")) return true;

	return segments.some((segment) => PROTECTED_DIR_SEGMENTS.has(segment));
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") {
			return undefined;
		}

		// event.input's declared type only has `path` (write/edit schemas never
		// declared `file_path`), but the built-in tools accept both at runtime —
		// narrow through `unknown` rather than assuming the schema is exhaustive.
		const input = event.input as unknown as { path?: string; file_path?: string };
		const path = input.path ?? input.file_path;
		if (!path || !isProtectedPath(path)) {
			return undefined;
		}

		if (ctx.hasUI) {
			ctx.ui.notify(`Blocked write to protected path: ${path}`, "warning");
		}
		return { block: true, reason: `Path "${path}" is protected` };
	});
}
