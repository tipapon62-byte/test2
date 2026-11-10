#!/usr/bin/env bash
# Type-checks all Luau sources against the Roblox API.
# Needs rojo + luau-lsp on PATH (or ROJO / LUAU_LSP env vars) and the Roblox definitions file:
#   https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
set -e
cd "$(dirname "$0")"
ROJO=${ROJO:-rojo}
LSP=${LUAU_LSP:-luau-lsp}
DEFS=${ROBLOX_DEFS:-globalTypes.d.luau}
"$ROJO" sourcemap default.project.json -o sourcemap.json
"$LSP" analyze --definitions=@roblox="$DEFS" --sourcemap=sourcemap.json src
