# env.sh — resolve deployment mode and export library path
# This is the ONLY file that knows about deployment modes and the src/ layout.
# All other scripts source this and use ${LIB_DIR}/common.sh etc.

if [[ -n "${CLAUDE_PLUGIN_ROOT}" ]]; then
    # Plugin mode: Claude Code sets CLAUDE_PLUGIN_ROOT to plugin install dir.
    # lib/ lives at the plugin root (plugin branch) or via symlink (main branch).
    export HOOK_ROOT="${CLAUDE_PLUGIN_ROOT}"
    export LIB_DIR="${HOOK_ROOT}/lib"
elif [[ -d "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../src/lib" ]]; then
    # Dev mode: env.sh is at src/env.sh, ../src/lib exists.
    export HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export LIB_DIR="${HOOK_ROOT}/src/lib"
else
    # install.sh mode: env.sh is alongside hook scripts, lib/ is in the same dir.
    export HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export LIB_DIR="${HOOK_ROOT}/lib"
fi
