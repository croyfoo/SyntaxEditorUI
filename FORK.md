# Fork maintenance

This is a fork of [`lynnswap/SyntaxEditorUI`](https://github.com/lynnswap/SyntaxEditorUI),
consumed by **Dired** as a local Swift package (`../../Developer/SyntaxEditorUI`).
Our changes live on the **`dired`** branch; **`main`** is kept as a pristine
mirror of upstream so we can pull updates cleanly.

## Remotes

| Remote     | URL                                    | Role                          |
|------------|----------------------------------------|-------------------------------|
| `upstream` | `lynnswap/SyntaxEditorUI`              | Read-only source of truth     |
| `origin`   | `croyfoo/SyntaxEditorUI`               | Our fork (push target/backup) |

## Branches

- **`main`** — untouched mirror of `upstream/main`. Never commit here.
- **`dired`** — our work (added languages, editor scrolling fixes). Checked out
  for development; Dired builds whatever is checked out.

## Pull upstream updates

```sh
cd ~/Developer/SyntaxEditorUI
git fetch upstream

# Fast-forward the mirror to the latest upstream.
git switch main
git merge --ff-only upstream/main

# Replay our commits on top of the new upstream.
git switch dired
git rebase main

# Rebuild Dired and smoke-test the editor, then update the fork:
git push --force-with-lease origin dired
```

Rebasing (rather than merging) keeps `dired` a clean, linear set of changes on
top of upstream, so conflicts are confined to files we actually touched.

After rebasing, in Xcode: **File → Packages → Reset Package Caches** (or delete
`DerivedData`) if the package doesn't pick up changes, then build Dired.

## Upstreaming our fixes

The **caret-follow / page-key scrolling** commit is a language-independent bug
fix in upstream's macOS editor and makes a clean PR:

```sh
git switch -c fix/editor-scrolling main
git cherry-pick <that-commit-sha>
git push origin fix/editor-scrolling
# open a PR against lynnswap:main
```

Once a fix is merged upstream, it drops out of the `dired` rebase automatically.
The language additions can stay on `dired` (or be proposed upstream separately).

## Related

See the "add a language to SyntaxEditorUI" recipe (capture scheme, scanner
manifest gotchas, static-only injection, exhaustive switches) in the Claude
project memory.
