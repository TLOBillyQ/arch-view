#!/usr/bin/env bash
# Syntax-check every Lua file under lib/ and the viewer's script.js.
# Run from anywhere: tests/check_syntax.sh
# Exit code 0 when every file parses, non-zero otherwise.
set -u

cd "$(dirname "$0")/.." || exit 1

LUAC="$(command -v luac || command -v luac5.5 || command -v luac5.4 || true)"
LUA="$(command -v lua || true)"
NODE="$(command -v node || true)"

failures=0
checked=0

check_lua() {
  local file="$1"
  local message
  if [ -n "$LUAC" ]; then
    if message="$("$LUAC" -p "$file" 2>&1)"; then
      echo "OK   $file"
    else
      echo "FAIL $file"
      echo "$message" | sed 's/^/     /'
      failures=$((failures + 1))
    fi
  elif [ -n "$LUA" ]; then
    if message="$("$LUA" -e 'local f, e = loadfile(arg[1]); if f == nil then io.stderr:write(e, "\n"); os.exit(1) end' "$file" 2>&1)"; then
      echo "OK   $file"
    else
      echo "FAIL $file"
      echo "$message" | sed 's/^/     /'
      failures=$((failures + 1))
    fi
  else
    echo "error: neither luac nor lua found on PATH" >&2
    exit 1
  fi
  checked=$((checked + 1))
}

while IFS= read -r file; do
  check_lua "$file"
done < <(find lib -type f -name '*.lua' | sort)

if [ -n "$NODE" ]; then
  if message="$(node --check viewer/script.js 2>&1)"; then
    echo "OK   viewer/script.js"
  else
    echo "FAIL viewer/script.js"
    echo "$message" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
  checked=$((checked + 1))
else
  echo "SKIP viewer/script.js (node not found on PATH)"
fi

if [ "$failures" -gt 0 ]; then
  echo "check_syntax: $failures of $checked files failed"
  exit 1
fi
echo "check_syntax: all $checked files passed"
