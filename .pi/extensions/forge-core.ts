/**
 * Forge Core Extension
 *
 * Forge's own operating instructions — Identity, routing, dispatch
 * mechanics, Race mode, extensions available, working style, etc. — live
 * in .pi/FORGE.md, not the project-level AGENTS.md. AGENTS.md at the repo
 * root is left entirely to whatever project gets built here (see
 * .pi/design.md §20): the user can rewrite, trim, or delete it freely and
 * Forge's own mechanics keep working, because this extension injects
 * .pi/FORGE.md's content into the system prompt directly, on every turn,
 * independent of AGENTS.md's content or even its existence.
 *
 * Written for Forge from scratch (same pattern as doom-loop-guard.ts) — no
 * upstream example does exactly this; closest precedent is pi's own
 * examples/extensions/claude-rules.ts (reads a rules folder at
 * session_start, appends a *list of paths* to the system prompt at
 * before_agent_start for the model to `read` on demand). This adapts that
 * shape to inject one file's full content directly, every turn, rather
 * than a pointer the model may or may not decide to follow.
 *
 * Reads .pi/FORGE.md once per session (session_start), not on every turn —
 * a session already running won't pick up an edit to .pi/FORGE.md without
 * a restart. That matches how pi loads AGENTS.md itself (also read once at
 * startup), so this isn't a new inconsistency.
 *
 * Prepends rather than appends: FORGE.md's content goes *before*
 * event.systemPrompt, not after, so it frames everything else pi
 * assembled (base prompt, AGENTS.md, skills) instead of trailing behind
 * it. This is deliberate, not cosmetic — pi does not guarantee load order
 * among multiple extensions in the same .pi/extensions/ directory (no sort
 * on the directory scan, confirmed by reading dist/core/extensions/loader.js),
 * so "run before other extensions" can't be relied on; putting our content
 * first *in the string* is what actually guarantees it reads first,
 * regardless of hook registration order. See .pi/design.md §20.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function forgeCoreExtension(pi: ExtensionAPI) {
	let forgeContent = "";

	pi.on("session_start", async (_event, ctx) => {
		const forgePath = path.join(ctx.cwd, ".pi", "FORGE.md");
		try {
			forgeContent = fs.readFileSync(forgePath, "utf-8").trim();
		} catch {
			forgeContent = "";
		}
	});

	pi.on("before_agent_start", async (event) => {
		if (!forgeContent) {
			return;
		}
		return {
			systemPrompt: `${forgeContent}\n\n---\n\n${event.systemPrompt}`,
		};
	});
}
