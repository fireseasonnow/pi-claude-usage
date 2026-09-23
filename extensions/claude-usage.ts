/**
 * /usage — show Claude subscription usage limits (5-hour session, weekly).
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
	pi.registerCommand("usage", {
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
				ctx.ui.notify(res.stderr.trim() || `usage.sh exited with code ${res.code}`, "error");
				return;
			}
			// stderr carries non-fatal notes (e.g. "showing cached data")
			const note = res.stderr.trim();
			ctx.ui.notify(res.stdout.trimEnd() + (note ? `\n${note}` : ""), "info");
		},
	});
}
