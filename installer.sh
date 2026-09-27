#!/usr/bin/env bash
# Version Mac : installe Rokit, Rojo et le plugin Rojo, puis lance `rojo serve`.
# Utilisation : ./installer.sh
set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/.rokit/bin:$PATH"

echo "=== Etape 1/3 : Rokit ==="
if ! command -v rokit >/dev/null 2>&1; then
	curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
fi

echo "=== Etape 2/3 : Rojo, Selene, StyLua ==="
rokit install --no-trust-check

echo "=== Etape 3/3 : plugin Rojo pour Roblox Studio ==="
rojo plugin install

echo
echo "Tout est installe ! Dans Roblox Studio : Plugins > Rojo > Connect."
echo "Laisse ce terminal ouvert. Ctrl+C pour arreter."
rojo serve
