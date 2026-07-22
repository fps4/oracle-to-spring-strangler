# assessment/agents/ — provenance (FS-0002, ADR-0004)

Every artifact in `assessment/` was drafted by an AI agent from the paired
prompt in this directory, then reviewed by the architect — corrections and
overrules are recorded in each artifact's `## Architect review` footer.
Agents draft; the architect decides.

| Artifact | Generator | Pipeline stage |
|---|---|---|
| `business-rule-catalog.md` | `business-rule-catalog.prompt.md` | 1 (reads `legacy/` only) |
| `dependency-map.md` | `dependency-map.prompt.md` | 1 (reads `legacy/` only) |
| `classification.md` | `classification.prompt.md` | 1 (reads `legacy/` + ADRs) |
| `wave-plan.md` | `wave-plan.prompt.md` | 2 (reads stage-1 outputs) |
| `effort-estimate.md` | `effort-estimate.prompt.md` | 2 (reads stage-1 outputs + wave plan) |

## How these were actually run

Claude Code, from the repo root. Stage 1 prompts ran as three parallel
subagents; stage 2 ran after stage 1 outputs were committed-quality. Each
agent received the prompt file content verbatim plus repo read access.

## Re-running

Any agentic assistant with repo read/write works. With Claude Code:

```bash
claude -p "$(cat assessment/agents/business-rule-catalog.prompt.md)"
# ... then stage 2, after stage 1 outputs exist:
claude -p "$(cat assessment/agents/wave-plan.prompt.md)"
claude -p "$(cat assessment/agents/effort-estimate.prompt.md)"
```

Expect wording differences between runs (LLM nondeterminism); substance —
rules found, edges mapped, verdicts — should reproduce. If a re-run finds a
rule the committed catalog missed, that is a catalog bug: open a PR.

The architect-review footers are human-authored and are NOT reproduced by
re-running the generators.
