---
name: web-search
description: Searches the live web through the search gateway set in the small-model-skills config, falling back to a local SearXNG. Use when a task needs current web results, documentation or news, and on local-model sessions where the built-in WebSearch tool returns nothing. Read-only.
x-wrappers: [web-search]
---

# Web search

Search the web with the `web-search` wrapper. It finds the gateway and its token from the config by
itself and never prints the token.

## Rules
- Use the `web-search` wrapper; never hand-build a `curl` to the gateway.
- Start with the free default search. Use `--brave`, `--news` or `--context` only when the default comes
  back thin or off-target. Those are paid per query: never loop them.
- One search per question. Refine the query rather than repeating it.

## Runbook
1. Run `web-search "<query>"`. Add `--fresh d` (or `w`, `m`, `y`) for recent results, `-n 5` for fewer.
2. Read the last line. `verdict: OK` or `verdict: WARN FALLBACK` means the results above it are usable.
   A `status: partial` row means some engines failed and the rest answered: still usable.
3. If the verdict is `WARN NO_RESULTS` or the results are off-target, run once more with a better query or
   with `--brave`. Use `--context` when you need page text rather than links.
4. If the verdict is `FAIL`, tell the user that search is unavailable and quote the verdict line.
5. To read a result, fetch only the one or two most promising pages (`WebFetch` or `curl`).
6. End the answer with a `Sources:` list of the markdown links you actually used.

## Tools
- `web-search [--brave|--news|--context] [--fresh d|w|m|y] [-n N] "<query>"` — read-only web search.
