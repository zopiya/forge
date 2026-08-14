/**
 * Custom Footer Extension - demonstrates ctx.ui.setFooter()
 *
 * Vendored from earendil-works/pi packages/coding-agent/examples/extensions
 * (same vendoring pattern as .pi/extensions/subagent/, see .pi/design.md).
 *
 * Deviations from upstream (see .pi/design.md §9.4, §9.6–§9.10):
 * This went through several rounds (block bar → two-line, pipe-heavy → one
 * line, screenshot-matched → duration/clock added) before landing here on a
 * "car dashboard" brief: only the two things you'd actually glance at, not
 * a stats page. Everything else that accumulated along the way — cost,
 * model id, thinking level, cache hit rate, raw token counts, session
 * duration, a clock — got cut. See §9.10 for the full reasoning; the short
 * version is that a dashboard has a speedometer and a fuel gauge, not a
 * trip computer with twelve numbers on it.
 *
 * What's left:
 * - Left (identity — "where"): cwd, branch (bold + accent), session name.
 *   Space-separated, no pipe. Branch/session name only appear when set.
 * - Right (context window — "fuel gauge"): tokens/window (percent%),
 *   colored success under 70%, warning past 70%, error past 90% — same
 *   source and thresholds pi's own built-in footer uses
 *   (src/modes/interactive/components/footer.ts), not reinvented. This is
 *   the one number that's actually actionable: it predicts when
 *   compaction fires. Everything upstream's footer also shows (tokens,
 *   cost, model) was cut as noise relative to that one signal.
 * - Left/right pad to terminal width, matching upstream's original layout.
 *
 * footerData exposes data not otherwise accessible:
 * - getGitBranch(): current git branch
 * - getExtensionStatuses(): texts from ctx.ui.setStatus()
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const CONTEXT_WARN_PERCENT = 70; // same threshold pi's built-in footer uses
const CONTEXT_ERROR_PERCENT = 90; // same threshold pi's built-in footer uses

function fmtTokens(n: number): string {
	return n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`;
}

function formatCwd(cwd: string): string {
	const home = process.env.HOME || process.env.USERPROFILE;
	if (!home) return cwd;
	if (cwd === home) return "~";
	if (cwd.startsWith(`${home}/`)) return `~${cwd.slice(home.length)}`;
	return cwd;
}

export default function (pi: ExtensionAPI) {
	let enabled = false;

	function setFooterEnabled(ctx: ExtensionContext, next: boolean, opts: { silent?: boolean } = {}) {
		enabled = next;

		if (enabled) {
			ctx.ui.setFooter((tui, theme, footerData) => {
				const unsub = footerData.onBranchChange(() => tui.requestRender());

				return {
					dispose: unsub,
					invalidate() {},
					render(width: number): string[] {
						// ---- Left: identity — cwd, branch (bold+accent), session name ----
						const branch = footerData.getGitBranch();
						const sessionName = pi.getSessionName();

						const leftParts: string[] = [theme.fg("dim", formatCwd(ctx.cwd))];
						if (branch) leftParts.push(theme.fg("muted", "on ") + theme.bold(theme.fg("accent", branch)));
						if (sessionName) leftParts.push(theme.fg("accent", sessionName));
						const left = leftParts.join(" ");

						// ---- Right: context window usage, the one gauge that matters ----
						const usage = ctx.getContextUsage();
						const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
						const contextTokens = usage?.tokens ?? null;
						const percent = usage?.percent ?? null;
						const contextColor =
							percent !== null && percent > CONTEXT_ERROR_PERCENT
								? "error"
								: percent !== null && percent > CONTEXT_WARN_PERCENT
									? "warning"
									: "success";
						const tokensLabel = contextTokens === null ? "?" : fmtTokens(contextTokens);
						const percentLabel = percent === null ? "?" : `${Math.round(percent)}%`;
						const right = theme.fg(contextColor, `${tokensLabel}/${fmtTokens(contextWindow)} (${percentLabel})`);

						const pad = " ".repeat(Math.max(1, width - visibleWidth(left) - visibleWidth(right)));
						return [truncateToWidth(left + pad + right, width)];
					},
				};
			});
			if (!opts.silent) ctx.ui.notify("Custom footer enabled", "info");
		} else {
			ctx.ui.setFooter(undefined);
			if (!opts.silent) ctx.ui.notify("Default footer restored", "info");
		}
	}

	pi.registerCommand("footer", {
		description: "Toggle custom footer (path/branch + context usage)",
		handler: async (_args, ctx) => setFooterEnabled(ctx, !enabled),
	});

	// Default on: Forge's Race/multi-worktree workflow wants branch
	// visibility without remembering to type /footer every session.
	pi.on("session_start", async (_event, ctx) => {
		if (ctx.hasUI) setFooterEnabled(ctx, true, { silent: true });
	});
}
