# Plugin evals

`triggers/` checks that each skill fires when it should and that no skill fires
on unrelated requests (12 should-fire cases, 4 should-not). Graders are
`tool_used` checks, so they cost nothing beyond the runs themselves.

The suite lives here, not in `plugins/ai-maestro/` (the build output, rewritten
by `build-plugin.sh --clean`). To run it against a build:

```bash
./build-plugin.sh --clean
T=$(mktemp -d) && cp -R plugins/ai-maestro/. "$T" && rm -rf "$T/hooks" && cp -R evals/triggers "$T/evals"
(cd "$T" && claude plugin eval . --runs 3 --ablation none --model sonnet --trust-plugin --no-publish -j 4 --max-cost-usd 3)
```

Hooks are removed so the run measures the skills alone (the hook talks to a
local AI Maestro server).

## Results (2026-10-01, Sonnet, 3 runs per case)

| Plugin | Score | Cases passing all runs | Cost of the suite |
|---|---|---|---|
| 1.0.0 | 0.85 | 13 / 16 | $2.30 |
| 1.1.0 (descriptions say when to use each skill) | 0.92 | 14 / 16 | $2.35 |
| 1.2.0 (lean bodies, tuned docs-search) | 1.00 | 16 / 16 | $1.81 |
