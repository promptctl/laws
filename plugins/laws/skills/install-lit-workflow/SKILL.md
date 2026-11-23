---
name: install-lit-workflow
description: Install this plugin's lit workflows into lit's global workflow layer, so lit asks for the plan review as a ticket leaves plan and for the law review as a ticket enters review, in every project it tracks. Run it once per machine, and again after the plugin updates.
disable-model-invocation: true
---

Run `${CLAUDE_SKILL_DIR}/install.sh` and show its output.

It copies the definitions in `${CLAUDE_SKILL_DIR}/definitions/` into `workflows/laws/` under lit's config directory (`~/.config/links-issue-tracker`, or `$XDG_CONFIG_HOME/links-issue-tracker` when that is set), and removes any definition there that the plugin no longer ships.

If it exits non-zero, give the user the message it printed and stop. Do not work around it.

When it succeeds, tell the user which files it wrote, and that `lit workflows` lists them. Do not run lit yourself to check.
