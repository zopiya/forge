/**
 * Trigger Compact Extension
 *
 * Vendored from earendil-works/pi packages/coding-agent/examples/extensions
 * (same vendoring pattern as .pi/extensions/subagent/, see .pi/design.md).
 *
 * Deviations from upstream (see .pi/design.md §22):
 * - Threshold is a percentage of the model's actual context window
 *   (`usage.percent`), not an absolute token count. Upstream's 100k-token
 *   threshold doesn't scale with `contextWindow` — on a model with a
 *   ~1M-token window it fired at ~10% usage instead of near the end of the
 *   window. `ContextUsage.percent`/`.contextWindow` are already computed by
 *   pi-core and exposed on the same object upstream reads `.tokens` from;
 *   `.pi/extensions/custom-footer.ts` already consumes them, same pattern.
 * - "Crossed threshold" (low→high transition) trigger logic replaced with a
 *   `compactionPending` flag: still triggers if a session starts already
 *   above threshold (upstream never does, a known bug — see the same
 *   design.md section), and still won't double-trigger while a fire-and-
 *   forget `ctx.compact()` call from a previous turn is still in flight.
 * - Auto-triggered compactions now pass `customInstructions` biasing the
 *   summarizer to preserve in-progress task state, so the session can pick
 *   back up immediately after compaction instead of losing the thread.
 *   Manual `/recap` behavior is unchanged.
 * - Command renamed from `/trigger-compact` to `/recap` (.pi/design.md
 *   §25) — a bare `compact` would have collided with pi's own built-in
 *   `/compact`; "recap" reflects this version's continuity-preserving bias.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const COMPACT_THRESHOLD_PERCENT = 80;

const CONTINUITY_INSTRUCTIONS =
	"This compaction was auto-triggered mid-task, not at a natural stopping point. " +
	"Preserve the in-progress task with maximum fidelity: what is currently being worked on, " +
	"the exact next steps, and any TODO/checklist state, so work can resume immediately " +
	"after compaction without re-deriving context.";

export default function (pi: ExtensionAPI) {
	// Whether we've already triggered a compaction for the current
	// above-threshold episode. Set on trigger, cleared once usage drops
	// back below threshold (compaction succeeded) or the compaction errors
	// out (so the next turn can retry).
	let compactionPending = false;

	const triggerCompaction = (ctx: ExtensionContext, customInstructions?: string) => {
		if (ctx.hasUI) {
			ctx.ui.notify("Compaction started", "info");
		}
		compactionPending = true;
		ctx.compact({
			customInstructions,
			onComplete: () => {
				compactionPending = false;
				if (ctx.hasUI) {
					ctx.ui.notify("Compaction completed", "info");
				}
			},
			onError: (error) => {
				compactionPending = false;
				if (ctx.hasUI) {
					ctx.ui.notify(`Compaction failed: ${error.message}`, "error");
				}
			},
		});
	};

	pi.on("turn_end", (_event, ctx) => {
		const usage = ctx.getContextUsage();
		const currentPercent = usage?.percent ?? null;
		if (currentPercent === null) {
			return;
		}

		if (currentPercent < COMPACT_THRESHOLD_PERCENT) {
			compactionPending = false;
			return;
		}
		if (compactionPending) {
			return;
		}
		triggerCompaction(ctx, CONTINUITY_INSTRUCTIONS);
	});

	pi.registerCommand("recap", {
		description: "Trigger compaction immediately",
		handler: async (args, ctx) => {
			const instructions = args.trim() || undefined;
			triggerCompaction(ctx, instructions);
		},
	});
}
