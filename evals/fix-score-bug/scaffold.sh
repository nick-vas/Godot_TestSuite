#!/usr/bin/env bash
set -euo pipefail
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scaffold-gdscript.sh"
# The bug: the multiplier now rises every sixth hit instead of every fifth.
sed -i 's|combo / 5|combo / 6|' score.gd
git -c user.name=eval -c user.email=eval@example.com commit -qam "Tweak scoring"
