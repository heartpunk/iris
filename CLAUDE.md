[[ include AGENTS.md ]]

## jj (Jujutsu) VCS Rules

- **Use `jj` for all VCS operations**, not raw git commands (repo is colocated).
- **Commits must be minimally logical** — one concern per commit. Never bundle unrelated changes.
- **`jj split` with filesets, not `--interactive`** — always pass explicit file paths to `jj split` (e.g. `jj split -r <rev> -m "msg" path/to/file`). Never use `-i`/`--interactive` or `--tool` flags, as they require an interactive diff editor.
- **`jj describe`** to set commit messages, **`jj new`** to start new work.
- **`jj squash`** to fold working copy into parent. **`jj squash -r`** to fold a commit into its parent.
