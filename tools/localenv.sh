# Sourced by the shell tools: read the ignored local.env (KEY=value lines).
# Settings already in the environment win, as in tools/localenv.py, so
# `TOLKARA_MODE=local-signing tools/run.sh sim` works with any local.env.
tolkara_load_env() {
    local given
    # Re-export: 'declare -x', as bash lists it, would be local to this function.
    # POSIX mode lists 'export NAME=' instead; accept both.
    if [ -f local.env ]; then
        eval "$(python3 -c '
from pathlib import Path
for line in Path("local.env").read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line: continue
    k, v = line.split("=", 1)
    k = k.strip().removeprefix("export ").strip()
    v = v.strip()
    if (v.startswith("\"") and v.endswith("\"")) or (v.startswith("\x27") and v.endswith("\x27")):
        v = v[1:-1]
    v_escaped = v.replace("\x27", "\x27\\x27\x27")
    print(f"export {k}=\x27{v_escaped}\x27")
')"
    fi
    eval "$given"
}
