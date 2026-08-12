/**
 * Doom Loop Guard Extension
 *
 * Blocks a tool call once it repeats the immediately preceding call(s)
 * identically (same tool name + same input) past a small threshold — a
 * circuit breaker for the agent getting stuck re-running the exact same
 * failing action and expecting a different result.
 *
 * Written for Forge, not vendored — inspired by the general idea behind
 * third-party "doom loop" detector packages seen on pi.dev/packages (see
 * docs/design.md §9.12), but no external source was read or copied; this is
 * a from-scratch minimal implementation, deliberately matching the same
 * `tool_call`-blocking shape already used by
 * `.pi/extensions/plan-mode/index.ts` and `.pi/extensions/protected-paths.ts`
 * rather than inventing a new mechanism.
 *
 * Known simplification, stated up front rather than discovered later: calls
 * are compared by shape only (tool name + JSON-serialized input), not by
 * result — a call that legitimately needs to repeat (e.g. polling for a
 * background job to finish) would still count toward the streak. Forge has
 * no background-polling extension installed, so this trade-off favors
 * catching real loops over accommodating a case that doesn't exist in this
 * setup today; revisit if that changes.
 *
 * Hardened in the same pass as docs/design.md §9.13's robustness audit:
 * JSON.stringify on tool input can throw (circular structures etc.) — a
 * broken guard shouldn't be the reason a real tool call fails, so an
 * unserializable input is now treated as unclassifiable (streak reset, call
 * allowed) instead of throwing out of the tool_call hook.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const REPEAT_BLOCK_THRESHOLD = 3; // allow 2 identical attempts, block the 3rd

function callSignature(toolName: string, input: unknown): string | null {
	try {
		return `${toolName}:${JSON.stringify(input)}`;
	} catch {
		// Circular structure or other non-serializable input — extremely unlikely
		// for tool call arguments, but a broken guard shouldn't be the reason a
		// real tool call fails. Treat as unclassifiable rather than throwing.
		return null;
	}
}

export default function (pi: ExtensionAPI) {
	let lastSignature: string | null = null;
	let streak = 0;

	pi.on("tool_call", async (event, ctx) => {
		const signature = callSignature(event.toolName, event.input);

		if (signature === null) {
			lastSignature = null;
			streak = 0;
			return undefined;
		}

		if (signature === lastSignature) {
			streak++;
		} else {
			lastSignature = signature;
			streak = 1;
		}

		if (streak < REPEAT_BLOCK_THRESHOLD) {
			return undefined;
		}

		if (ctx.hasUI) {
			ctx.ui.notify(`Blocked: "${event.toolName}" repeated identically ${streak}x in a row`, "warning");
		}
		return {
			block: true,
			reason: `Doom loop guard: this exact "${event.toolName}" call (same arguments) has now repeated ${streak} times in a row with nothing else happening in between. Stop and either try a materially different approach, or ask the user one specific question instead of repeating this call again.`,
		};
	});

	// Fresh session (new or resumed) starts with a clean slate — no history
	// is persisted for this, and resuming shouldn't inherit a stale streak.
	pi.on("session_start", () => {
		lastSignature = null;
		streak = 0;
	});
}
