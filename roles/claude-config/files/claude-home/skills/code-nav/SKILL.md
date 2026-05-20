---
name: code-nav
description: Navigate large codebases efficiently — find symbols, definitions, references, and call sites without reading whole files. Use this skill whenever you need to understand "where is X defined", "where is X used", "what does this function call", or to grep/scan code in any repo larger than a handful of files. Saves dozens of K tokens vs reading files. Tools available: ripgrep (rg), fd, bat, ast-grep (if installed), git grep.
---

# Code Navigation

This VPS has fast local search tools. **Prefer them over `Read` for any file > 200 lines or any unknown codebase.**

## Decision tree

| Goal | Use this | Why |
|------|---------|-----|
| Find file by name | `fd <name>` | Faster than `find`, respects `.gitignore` |
| Find symbol/keyword across repo | `rg -n '<pattern>'` | ripgrep, fast |
| See definition + N lines context | `rg -n -A 20 'def my_func'` | Get just the chunk you need |
| Search restricted to file type | `rg -t py 'pattern'` / `rg -t go 'pattern'` | Skip noise |
| Function call sites | `rg -n '\bmy_func\(' --type py` | Word boundary + paren |
| Imports of a module | `rg -n '(import\|from)\s+foo' --type py` | Both syntaxes |
| Browse one large file | `bat -p file.py | rg -A 5 -B 5 'class Foo'` | Just the relevant span |
| AST-precise queries (if `ast-grep` present) | `ast-grep run -p 'function $F() { $$$ }' file.js` | Pattern by syntax, not regex |
| Recently changed files | `git log --since='2 days' --name-only --pretty=` | Focus diff |

## Anti-patterns

- ❌ `Read /huge/file.py` (10K lines) when you only need one function → use `rg -n -A 30 'def func_name'` instead
- ❌ `cat **/*.py` to "see what's there" → use `rg --files -t py | head -50` for inventory
- ❌ Asking the user to paste a file → ssh / use the tools, that's why they exist

## Common recipes

```bash
# Where is class FooService defined?
rg -n 'class FooService' --type py

# All call sites of FooService.do_thing()
rg -n '\.do_thing\(' --type py

# What does this function depend on (its imports)?
rg -n '^(import|from)' src/service.py

# How big is this codebase?
rg --files | wc -l                       # file count
rg --files -t py | xargs wc -l | tail -1 # python LoC

# Find all TODOs added in last week
git log --since='1 week' -p | rg '^\+.*TODO'

# Find recursive structure quickly
fd -t d -d 2  # directories, depth 2

# Search across multiple file types with context
rg -A 3 -B 1 'connect_db' -t py -t js -t go

# Show file structure (symbols) — needs `ctags` (apt: universal-ctags)
ctags -R -f - --sort=no | head -50

# JSON / config: extract specific keys without reading whole file
jq '.scripts | keys' package.json
yq '.services | keys' docker-compose.yml
```

## When you DO need to Read whole file

If after `rg`/`fd`/`bat` you genuinely need the full file:
1. Confirm size first: `wc -l <file>` — if > 1000 lines, you almost certainly want a slice not the whole
2. Read with offset+limit: `Read <file> --offset N --limit 200`
3. Or extract a region with `sed -n 'A,Bp'` or `bat -r A:B`

## Tools detection

This snippet checks what's available:
```bash
for t in rg fd bat ast-grep ctags eza jq yq; do
  command -v $t >/dev/null && echo "✓ $t" || echo "✗ $t (not installed)"
done
```
On Codens VPS: `rg`, `fd`, `bat`, `eza`, `jq`, `ctags` are guaranteed. `ast-grep` and `yq` may not be — install via mise/cargo if needed.
