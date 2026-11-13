# Set up a coding assistant

[AGENTS.md](../AGENTS.md) holds the shared project instructions. [CLAUDE.md](../CLAUDE.md) imports it for Claude Code. To save a device choice for your checkout, copy [the local testing example](local-testing.example.md) to `.local/testing.md`. Git ignores that directory. Keep shared rules in `AGENTS.md` and personal preferences in the local file.

## Use the official skills

The checkout includes a small selection of skills from the repositories named in [Flutter's AI tools documentation](https://docs.flutter.dev/ai/tools#official-skills-repositories). Agents that discover `.agents/skills/` can use them without a separate install. If your agent uses a different discovery path, follow its [setup instructions](https://docs.flutter.dev/ai/get-started) or point it to the relevant `SKILL.md`.

| Upstream source | Included skills |
| --- | --- |
| [flutter/agent-plugins at e5a88d2](https://github.com/flutter/agent-plugins/tree/e5a88d2be19cbf7ba1ef974375e5846492aca2ac/skills) | `flutter-add-integration-test`, `flutter-add-widget-test`, `flutter-build-responsive-layout`, `flutter-setup-declarative-routing` |
| [dart-lang/skills at fa69167](https://github.com/dart-lang/skills/tree/fa691671fda391ea1d1f8c7ae61bddc03348ec85/skills) | `dart-add-unit-test`, `dart-run-static-analysis` |

Use the [project testing guide](testing.md) to choose how to run the checks. The skills do not install a plugin, enable MCP, or add app dependencies. If a skill assumes an MCP tool you have not configured, use the available Flutter or Dart commands.

To update the skills, review the selected directories at a newer upstream commit. Copy them into `.agents/skills/` unchanged, preserve the licenses, and update the pinned links above.
