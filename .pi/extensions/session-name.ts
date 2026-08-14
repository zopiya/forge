/**
 * Session naming example.
 *
 * Vendored from earendil-works/pi packages/coding-agent/examples/extensions
 * (same vendoring pattern as .pi/extensions/subagent/, see .pi/design.md).
 * Pairs naturally with the .pi/work/<feature-slug> naming convention when
 * several sessions run in parallel across worktrees.
 *
 * Deviation from upstream (see .pi/design.md §25): command renamed from
 * `/session-name` to `/label` — a bare `name`/`session` would have
 * collided with pi's own documented `/name`/`/session` commands.
 *
 * Shows setSessionName/getSessionName to give sessions friendly names
 * that appear in the session selector instead of the first message.
 *
 * Usage: /label [name] - set or show session name
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.registerCommand("label", {
		description: "Set or show session name (usage: /label [new name])",
		handler: async (args, ctx) => {
			const name = args.trim();

			if (name) {
				pi.setSessionName(name);
				ctx.ui.notify(`Session named: ${name}`, "info");
			} else {
				const current = pi.getSessionName();
				ctx.ui.notify(current ? `Session: ${current}` : "No session name set", "info");
			}
		},
	});
}
