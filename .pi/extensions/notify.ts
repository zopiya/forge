/**
 * Pi Notify Extension
 *
 * Vendored from earendil-works/pi packages/coding-agent/examples/extensions
 * (same vendoring pattern as .pi/extensions/subagent/, see .pi/design.md).
 *
 * Deviations from upstream (see .pi/design.md §9.4–§9.5):
 * - Added an ntfy.sh push channel (notifyNtfy) alongside the original terminal
 *   protocols. Terminal notifications (OSC 777/99/Windows Toast) only reach you
 *   if a terminal is open and attached — no good when pi is running unattended
 *   on a remote box (Codespaces left open overnight, a detached tmux, etc.).
 *   ntfy pushes to a phone/desktop regardless of whether anything is attached.
 *   Opt-in only: no-ops unless PI_NTFY_TOPIC is set, so default behavior for
 *   anyone who hasn't configured it is unchanged.
 * - Notification body is now a preview of the agent's last message instead of
 *   the static "Ready for input" — more useful on a lock screen, and the title
 *   includes the working directory so multiple concurrent pi runs are
 *   distinguishable.
 * - Added tmux-aware notification (see .pi/design.md §9.5). This is the
 *   "server" scenario: pi running inside a detached/attached tmux on a
 *   remote box, you're bouncing between tmux windows over SSH. Two problems
 *   the plain OSC codes above don't solve there:
 *     1. Without `allow-passthrough on` in tmux.conf (tmux ≥3.3, opt-in, off
 *        by default), tmux either swallows OSC 777/99 silently or — on older
 *        tmux — leaks the raw escape bytes into the pane as visible garbage.
 *        We check the actual `allow-passthrough` setting via `tmux
 *        show-options` before trusting OSC to reach the outer terminal.
 *     2. Even if it's swallowed cleanly, nothing tells you *which* tmux
 *        window to look at. tmux's own bell/activity monitoring (BEL char,
 *        `monitor-bell` — on by default) flags the right window in the
 *        status line, and `tmux display-message` pops a transient message —
 *        both work with zero client-side terminal support required, unlike
 *        OSC. Used only as a fallback when passthrough is off, so it doesn't
 *        double up with a real desktop notification when passthrough *is*
 *        configured.
 * - Gated the whole `notify()` call on `ctx.hasUI` (robustness audit,
 *   .pi/design.md §9.13). Upstream fires unconditionally on `agent_end`,
 *   which includes every non-interactive `pi --mode json -p` run — exactly
 *   what `subagent` dispatch uses for scout/planner/reviewer/builder. Two
 *   concrete problems, not hypothetical: (1) notifyTerminal()/
 *   notifyTmuxNative() write raw OSC/BEL bytes to process.stdout, which in
 *   `--mode json` is the same line-delimited JSON stream the dispatching
 *   subagent tool parses — confirmed to actually splice garbage into a
 *   dispatched run's output and silently corrupt whichever JSON line it
 *   landed on; (2) even the ntfy channel firing per dispatched subprocess
 *   would spam a push per parallel task (up to 8) for a "waiting for input"
 *   state that a non-interactive one-shot process never has.
 *
 * Sends a notification when Pi agent is done and waiting for input.
 * Terminal protocols:
 * - OSC 777: Ghostty, iTerm2, WezTerm, rxvt-unicode
 * - OSC 99: Kitty
 * - Windows toast: Windows Terminal (WSL)
 * tmux (when $TMUX is set):
 * - `allow-passthrough on` → trust OSC above to reach the outer terminal
 * - otherwise → tmux bell (status-line flag) + `tmux display-message`
 * Push (opt-in):
 * - ntfy.sh (or a self-hosted ntfy server) via PI_NTFY_TOPIC / PI_NTFY_SERVER
 */

import * as path from "node:path";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { AssistantMessage, TextContent } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BODY_PREVIEW_LIMIT = 160;
const TMUX_MESSAGE_LIMIT = 60; // tmux status line is narrow, keep display-message short

function windowsToastScript(title: string, body: string): string {
	const type = "Windows.UI.Notifications";
	const mgr = `[${type}.ToastNotificationManager, ${type}, ContentType = WindowsRuntime]`;
	const template = `[${type}.ToastTemplateType]::ToastText01`;
	const toast = `[${type}.ToastNotification]::new($xml)`;
	return [
		`${mgr} > $null`,
		`$xml = [${type}.ToastNotificationManager]::GetTemplateContent(${template})`,
		`$xml.GetElementsByTagName('text')[0].AppendChild($xml.CreateTextNode('${body}')) > $null`,
		`[${type}.ToastNotificationManager]::CreateToastNotifier('${title}').Show(${toast})`,
	].join("; ");
}

function notifyOSC777(title: string, body: string): void {
	process.stdout.write(`\x1b]777;notify;${title};${body}\x07`);
}

function notifyOSC99(title: string, body: string): void {
	// Kitty OSC 99: i=notification id, d=0 means not done yet, p=body for second part
	process.stdout.write(`\x1b]99;i=1:d=0;${title}\x1b\\`);
	process.stdout.write(`\x1b]99;i=1:p=body;${body}\x1b\\`);
}

function notifyWindows(title: string, body: string): void {
	const { execFile } = require("child_process");
	execFile("powershell.exe", ["-NoProfile", "-Command", windowsToastScript(title, body)]);
}

function notifyTerminal(title: string, body: string): void {
	if (process.env.WT_SESSION) {
		notifyWindows(title, body);
	} else if (process.env.KITTY_WINDOW_ID) {
		notifyOSC99(title, body);
	} else {
		notifyOSC777(title, body);
	}
}

function tmuxOptionEnabled(option: string): boolean {
	try {
		const { execFileSync } = require("child_process");
		// -g reads the global value; -v prints just the value ("on"/"off").
		const out = execFileSync("tmux", ["show-options", "-gv", option], { encoding: "utf8" }).trim();
		return out === "on";
	} catch {
		// tmux binary missing, or the option doesn't exist on this tmux version —
		// treat as off, which is the safer assumption (falls back to bell/display-message).
		return false;
	}
}

/**
 * tmux-native notification. Returns true when it's safe for the caller to
 * also try the OSC-based notifyTerminal() (i.e. allow-passthrough is on, so
 * OSC 777/99 will actually reach the outer terminal instead of being
 * swallowed or leaked as garbage) — see the header comment for the full
 * reasoning. Returns true unconditionally when not running inside tmux, since
 * this function then has nothing to do with the decision.
 */
function notifyTmuxNative(title: string, body: string): boolean {
	if (!process.env.TMUX) return true;
	if (tmuxOptionEnabled("allow-passthrough")) return true;

	// No passthrough: use tmux's own channels instead of raw OSC.
	process.stdout.write("\x07"); // BEL — flags this pane's window in the status line (monitor-bell, on by default)
	try {
		const { execFileSync } = require("child_process");
		const message = `${title}: ${body}`;
		const truncated = message.length > TMUX_MESSAGE_LIMIT ? `${message.slice(0, TMUX_MESSAGE_LIMIT - 1)}…` : message;
		execFileSync("tmux", ["display-message", truncated], { stdio: "ignore" });
	} catch {
		// best-effort — a missing tmux binary or a display-message failure
		// shouldn't break the agent turn; the bell above already fired.
	}
	return false;
}

/**
 * Push via ntfy.sh (or a self-hosted server). No-op unless PI_NTFY_TOPIC is set.
 * Setup: export PI_NTFY_TOPIC="something-private-and-hard-to-guess" (topic names
 * on the public server are unauthenticated — anyone who knows the topic can read
 * it), subscribe to that topic in the ntfy app. Point PI_NTFY_SERVER at a
 * self-hosted instance instead of the default https://ntfy.sh if you have one.
 * Requires a runtime with global fetch (Node 18+ / Bun — both of which pi itself
 * requires, so this doesn't add a new baseline requirement).
 */
function notifyNtfy(title: string, body: string): void {
	const topic = process.env.PI_NTFY_TOPIC;
	if (!topic) return;

	const server = (process.env.PI_NTFY_SERVER || "https://ntfy.sh").replace(/\/+$/, "");
	const url = topic.startsWith("http") ? topic : `${server}/${encodeURIComponent(topic)}`;

	fetch(url, {
		method: "POST",
		body,
		headers: { Title: title, Tags: "robot_face", Priority: "default" },
	}).catch(() => {
		// Best-effort — a flaky network shouldn't break the agent turn or throw
		// inside an unawaited event handler.
	});
}

function notify(title: string, body: string): void {
	const oscSafe = notifyTmuxNative(title, body);
	if (oscSafe) notifyTerminal(title, body);
	notifyNtfy(title, body);
}

function isAssistantMessage(m: AgentMessage): m is AssistantMessage {
	return m.role === "assistant" && Array.isArray(m.content);
}

function getTextContent(message: AssistantMessage): string {
	return message.content
		.filter((block): block is TextContent => block.type === "text")
		.map((block) => block.text)
		.join("\n");
}

function previewOf(text: string): string {
	const flat = text.trim().replace(/\s+/g, " ");
	if (!flat) return "Ready for input";
	return flat.length > BODY_PREVIEW_LIMIT ? `${flat.slice(0, BODY_PREVIEW_LIMIT - 1)}…` : flat;
}

export default function (pi: ExtensionAPI) {
	pi.on("agent_end", async (event, ctx) => {
		// Non-interactive runs (subagent dispatch uses `pi --mode json -p` for
		// every scout/planner/reviewer/builder call) have no one "waiting for
		// input" to notify — and worse, notifyTerminal()/notifyTmuxNative() write
		// raw OSC/bell bytes straight to process.stdout, which in --mode json IS
		// the line-delimited JSON transport the dispatching subagent tool parses.
		// Confirmed empirically: those bytes showed up spliced into a dispatched
		// run's JSON output, corrupting whichever line they landed on (silently
		// dropped by the caller's `catch { return }`, i.e. a lost event with no
		// error surfaced). Gating on ctx.hasUI matches the pattern every other
		// extension here already uses for this exact distinction (custom-footer's
		// session_start, plan-mode's agent_end, trigger-compact's notify calls).
		if (!ctx.hasUI) return;

		const lastAssistant = [...event.messages].reverse().find(isAssistantMessage);
		const body = previewOf(lastAssistant ? getTextContent(lastAssistant) : "");
		const title = `Pi · ${path.basename(process.cwd())}`;
		notify(title, body);
	});
}
