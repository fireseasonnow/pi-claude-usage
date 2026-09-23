/**
 * /claude-usage — show Claude subscription usage limits (5-hour session, weekly).
 * Named claude-usage rather than usage: many Pi packages register /usage, and
 * duplicate command names make Pi rename both (/usage:1, /usage:2).
 * Runs the bundled claude-usage skill script directly, so no model tokens are spent.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT = path.resolve(
	path.dirname(fileURLToPath(import.meta.url)),
	"../skills/claude-usage/scripts/usage.sh",
);

export default function (pi: ExtensionAPI) {
	pi.registerCommand("claude-usage", {
		description: "Show Claude plan usage limits (5-hour session, weekly)",
		getArgumentCompletions: (prefix) =>
			"--json".startsWith(prefix) ? [{ value: "--json", label: "--json" }] : null,
		handler: async (args, ctx) => {
			const flag = args.trim() === "--json" ? "--json" : "--color";
			const res = await pi.exec("bash", [SCRIPT, flag], { timeout: 20_000 }).catch((e) => ({
				stdout: "",
				stderr: String(e),
				code: 1,
				killed: false,
			}));
			if (res.code !== 0) {
				// Pi prefixes error notices with "Error: " itself
				const message = res.stderr.trim().replace(/^error:\s*/, "");
				ctx.ui.notify(message || `usage.sh exited with code ${res.code}`, "error");
				return;
			}
			// stderr carries non-fatal notes (e.g. "showing data from 7m ago"); color it
			// explicitly, since it follows the output's last color reset
			const note = res.stderr.trim();
			const dimNote = note ? `\n\x1b[38;5;244m  ${note}\x1b[39m` : "";
			ctx.ui.notify(res.stdout.trimEnd() + dimNote, "info");
		},
	});
}
