#!/bin/bash
# Runs the offline tests. Needs `lua` on PATH and nothing else - no sibling
# repo, no client. What lands on the bar is the part that can be wrong without
# anybody being able to reproduce it, so that is the part kept testable.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
for test in tests/test_*.lua; do
	echo "=== $test"
	lua "$test" || status=1
done

exit "$status"
