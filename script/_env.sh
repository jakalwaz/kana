# Shared setup for script/*. Source it, don't run it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Use full Xcode when it's usable; otherwise the Command Line Tools, which
# can build Kana but can't run swift-testing (no macro plugin).
if ! xcrun --find swift >/dev/null 2>&1 || xcrun swift --version 2>&1 | grep -q "license"; then
    if [ -d /Library/Developer/CommandLineTools ]; then
        export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    fi
fi

have_full_xcode() {
    [ "${DEVELOPER_DIR:-}" != "/Library/Developer/CommandLineTools" ] && xcrun --find xctest >/dev/null 2>&1
}
