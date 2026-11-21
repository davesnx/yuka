#!/bin/sh
set -eu

base=https://raw.githubusercontent.com/davesnx/yuka/main

cat <<'EOF'
# Yuka

> Yuka is a web framework for OCaml. The server renders pages to HTML and streams slow parts when they are ready. Islands are components that Melange compiles to JavaScript and that hydrate in the browser. Components are written in mlx (JSX for OCaml) and use signals.

Yuka is experimental and its API changes. Read the page for the task before you write Yuka code.

## Docs

EOF

for page in "$@"; do
  title=$(sed -n 's/^# //p' "$page" | head -n 1)
  printf -- '- [%s](%s/docs/%s)\n' "$title" "$base" "$(basename "$page")"
done

cat <<EOF

## Optional

- [Agent skill](${base}/skills/yuka/SKILL.md): rules and a guide to the docs for a coding agent. The \`yuka\` opam package installs it in \`share/yuka/skills/yuka\`.
EOF
