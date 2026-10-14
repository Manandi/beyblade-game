#!/bin/sh
# Runs BeyConfig outside Roblox: load-time validation, display odds, simulated box rolls vs stated odds,
# and a check that a box whose odds do not total 100% refuses to load. Needs `luau` on PATH.
set -e
cd "$(dirname "$0")/.."
build() { # $1 = path to BeyConfig.lua
  cat tools/stubs.luau
  echo "local BeyConfig = (function()"
  cat "$1"
  echo "end)()"
  echo "local BeyMeshData = (function()"
  cat src/shared/BeyMeshData.lua
  echo "end)()"
  echo "local BeyDesigns = (function()"
  cat src/shared/BeyDesigns.lua
  echo "end)()"
  cat tools/test_body.luau
}
tmp=$(mktemp -d)
build src/shared/BeyConfig.lua > "$tmp/good.luau"
luau "$tmp/good.luau"

sed 's/Epic = 550/Epic = 551/' src/shared/BeyConfig.lua > "$tmp/bad_config.lua"
build "$tmp/bad_config.lua" > "$tmp/bad.luau"
if luau "$tmp/bad.luau" 2>&1 | grep -q "must be 10000"; then
  echo "bad odds rejected: OK"
else
  echo "FAIL: bad odds were accepted"; rm -rf "$tmp"; exit 1
fi
rm -rf "$tmp"
