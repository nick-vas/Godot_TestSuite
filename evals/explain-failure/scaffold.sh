#!/usr/bin/env bash
set -euo pipefail
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scaffold-gdscript.sh"
# A wrong expectation: the test, not the game, is broken.
sed -i 's|assert_eq(score.hit(10), 20)|assert_eq(score.hit(10), 25)|' test/test_score.gd
git -c user.name=eval -c user.email=eval@example.com commit -qam "Update expectation"
