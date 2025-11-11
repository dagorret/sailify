#!/usr/bin/env bash
set -euo pipefail

# Archivo de salida en el HOME del usuario
TARGET="${HOME}/.sail-aliases.sh"

# Genera funciones/wrappers para usar comandos sin prefijo "sail"
cat > "${TARGET}" <<'EOS'
# ===== Sail transparent command wrappers =====
_sail_present() { [ -f "./vendor/bin/sail" ]; }

php() {
  if _sail_present; then ./vendor/bin/sail php "$@"; else command php "$@"; fi
}
composer() {
  if _sail_present; then ./vendor/bin/sail composer "$@"; else command composer "$@"; fi
}
artisan() {
  if _sail_present; then ./vendor/bin/sail artisan "$@"; else command php artisan "$@"; fi
}
npm() {
  if _sail_present; then ./vendor/bin/sail npm "$@"; else command npm "$@"; fi
}
pnpm() {
  if _sail_present; then ./vendor/bin/sail pnpm "$@"; else command pnpm "$@"; fi
}
yarn() {
  if _sail_present; then ./vendor/bin/sail yarn "$@"; else command yarn "$@"; fi
}
node() {
  if _sail_present; then ./vendor/bin/sail node "$@"; else command node "$@"; fi
}
phpunit() {
  if _sail_present; then ./vendor/bin/sail phpunit "$@"; else command ./vendor/bin/phpunit "$@"; fi
}
tinker() {
  if _sail_present; then ./vendor/bin/sail tinker "$@"; else command php artisan tinker "$@"; fi
}
# atajos útiles
queue()  { artisan queue:"$@"; }
migrate(){ artisan migrate "$@"; }
seed()   { artisan db:seed "$@"; }
EOS

# Auto-carga en shells comunes
for RC in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
  if [[ -f "$RC" ]] && ! grep -qF ".sail-aliases.sh" "$RC"; then
    echo -e "\n# Sail aliases" >> "$RC"
    echo "[ -f ${TARGET} ] && . ${TARGET}" >> "$RC"
  fi
done

echo "✅ Aliases instalados en ${TARGET}"
echo "🔁 Abrí una nueva terminal o ejecutá: source ${TARGET}"
