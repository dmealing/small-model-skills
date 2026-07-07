---
name: file-search
description: Find files on this machine by name or by content. Use when asked to locate a file, find where something is configured, search for a string across files, or "find that thing I wrote about X." Read-only — it searches and reports paths; it never opens, edits, or deletes anything.
x-wrappers: [find-files]
---

# file-search

Use to locate files by **name** or by **content** on this machine — "where's my ssh config", "which file
mentions `API_KEY`", "find the notes about the router."

## Steps
1. Run `find-files <query> [path]`. The `<query>` is a **literal substring**, not a regex — dots,
   brackets, and other metacharacters match themselves. It searches file *names* (via fd/find) and file
   *contents* (via ripgrep/grep) under the path — defaulting to the configured `SEARCH_ROOT`, or the
   current directory — and prints matching paths plus a verdict. It searches gitignored and hidden files
   too (this is a whole-machine search), pruning only `.git`/`node_modules`. It is read-only.
2. Read the results:
   - Matches → report which files matched by name vs. by content.
   - `No matches` → the query may be too specific, or the search scope too narrow. Propose a broader path
     (e.g. the home directory) or a looser query, and re-run.
   - `CUT OFF by the time limit` → the search did **not** finish, so this is not a definitive "no matches."
     Propose a more specific path, or raising `SEARCH_NAME_TIMEOUT`/`SEARCH_CONTENT_TIMEOUT`, and re-run.
3. To show the exact lines inside a content match, propose `rg -n -i '<query>' <file>` (or
   `grep -ni '<query>' <file>`) — don't dump whole files into your reply.
4. Report the matching paths and the single most likely file. Never open, edit, or delete a file yourself.

Read-only: `find-files` only searches (name + content) and is time-bounded so a large tree can't hang it.
