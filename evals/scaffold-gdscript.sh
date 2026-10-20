#!/usr/bin/env bash
# Copies the kit's GDScript example into the empty eval workspace as a git repository. Each case's scaffold.sh calls this
# and then breaks something on purpose. GUT is copied when the example has it locally, so runs need no download.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/../examples/gdscript"
for f in project.godot main.gd main.tscn score.gd test/test_score.gd test/flows/startup.flow.json .gitignore; do
  mkdir -p "$(dirname "$f")"
  cp "$src/$f" "$f"
done
if [ -d "$src/addons/gut" ]; then mkdir -p addons && cp -r "$src/addons/gut" addons/gut; fi
git init -q
git -c user.name=eval -c user.email=eval@example.com add -A
git -c user.name=eval -c user.email=eval@example.com commit -qm "Example game"
