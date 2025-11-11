#!/usr/bin/env bash
set -euo pipefail

# ========== Defaults ==========
PROJECT_DIR="."                                  # Directorio del proyecto existente
PHP_VERSION="${PHP_VERSION:-8.3}"
NODE_VERSION="${NODE_VERSION:-20}"
SERVICES_DEFAULT="mysql,mariadb,pgsql,redis,memcached,meilisearch,minio,mailpit,selenium"
SERVICES="${SERVICES:-$SERVICES_DEFAULT}"

PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@example.com}"
PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-secret}"
PGADMIN_PORT="${PGADMIN_PORT:-5050}"

PHPMYADMIN="${PHPMYADMIN:-true}"
PHPMYADMIN_PORT="${PHPMYADMIN_PORT:-8081}"

usage() {
cat <<EOF
Uso: $(basename "$0") [opciones]

Instala/configura Sail en un proyecto Laravel existente y agrega servicios opcionales.

Opciones:
  --project-dir DIR       Directorio del proyecto (default: .)
  --php X.Y               Versión PHP (default: ${PHP_VERSION})
  --node N                Versión Node.js (default: ${NODE_VERSION})
  --services LISTA        Servicios Sail (default: ${SERVICES_DEFAULT})
  --pgadmin-email EMAIL   Email pgAdmin (default: ${PGADMIN_EMAIL})
  --pgadmin-pass PASS     Password pgAdmin (default: ****)
  --pgadmin-port PORT     Puerto pgAdmin (default: ${PGADMIN_PORT})
  --phpmyadmin true|false Incluir phpMyAdmin si hay mysql/mariadb (default: ${PHPMYADMIN})
  --phpmyadmin-port PORT  Puerto phpMyAdmin (default: ${PHPMYADMIN_PORT})
  -h, --help              Ayuda

Ejemplos:
  $(basename "$0") --project-dir /ruta/app --services "sqlite,mailpit"
  $(basename "$0") --services "pgsql,redis,mailpit" --pgadmin-email admin@demo --pgadmin-pass pass
EOF
}

# ========== Parseo de argumentos ==========
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --php) PHP_VERSION="$2"; shift 2;;
    --node) NODE_VERSION="$2"; shift 2;;
    --services) SERVICES="$2"; shift 2;;
    --pgadmin-email) PGADMIN_EMAIL="$2"; shift 2;;
    --pgadmin-pass) PGADMIN_PASSWORD="$2"; shift 2;;
    --pgadmin-port) PGADMIN_PORT="$2"; shift 2;;
    --phpmyadmin) PHPMYADMIN="$2"; shift 2;;
    --phpmyadmin-port) PHPMYADMIN_PORT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Opción desconocida: $1"; usage; exit 1;;
  esac
done

# ========== Validaciones ==========
cd "${PROJECT_DIR}"
if [[ ! -f composer.json ]]; then
  echo "❌ No se encontró composer.json en $(pwd). ¿Estás en un proyecto Laravel?"
  exit 1
fi
if ! command -v composer >/dev/null 2>&1; then
  echo "❌ composer no está instalado en el host."
  exit 1
fi

# ========== Instalar Sail y generar compose ==========
echo "📦 Instalando laravel/sail..."
composer require laravel/sail --dev --no-interaction --no-progress
composer dump-autoload --no-interaction >/dev/null 2>&1 || true

echo "⚙️ Ejecutando php artisan sail:install --with=\"$SERVICES\""
php artisan sail:install --with="$SERVICES" --no-interaction

# ========== Ajustar Dockerfile de la app (PHP/Node) ==========
DOCKERFILE=$(grep -RIl "laravelsail/php" docker dockerfiles . 2>/dev/null | head -n1 || true)
if [[ -n "${DOCKERFILE}" && -f "${DOCKERFILE}" ]]; then
  echo "🧩 Ajustando Dockerfile: ${DOCKERFILE}"
  PHP_TAG="$(echo "$PHP_VERSION" | tr -d '.')"
  sed -i.bak -E "s|(laravelsail/php)[0-9]+(-composer)?|\1${PHP_TAG}\2|g" "${DOCKERFILE}" || true
  if grep -qE 'ARG NODE_VERSION=' "${DOCKERFILE}"; then
    sed -i.bak -E "s|ARG NODE_VERSION=.*|ARG NODE_VERSION=${NODE_VERSION}|g" "${DOCKERFILE}"
  else
    awk -v nv="${NODE_VERSION}" '
      BEGIN{printed=0}
      /^FROM / && printed==0 { print; print "ARG NODE_VERSION=" nv; printed=1; next }
      { print }
    ' "${DOCKERFILE}" > "${DOCKERFILE}.tmp" && mv "${DOCKERFILE}.tmp" "${DOCKERFILE}"
  fi
else
  echo "⚠️ No pude localizar el Dockerfile de Sail para forzar PHP/Node. Ajustá manual si lo necesitás."
fi

# ========== pgAdmin si hay pgsql ==========
COMPOSE="docker-compose.yml"
if [[ -f "${COMPOSE}" ]] && echo "$SERVICES" | grep -q "pgsql"; then
  if ! grep -qE '^\s*pgadmin:' "${COMPOSE}"; then
    echo "➕ Agregando servicio pgadmin a ${COMPOSE}"
    cat >> "${COMPOSE}" <<YAML

  pgadmin:
    image: dpage/pgadmin4:latest
    ports:
      - '\${PGADMIN_PORT:-${PGADMIN_PORT}}:80'
    environment:
      PGADMIN_DEFAULT_EMAIL: \${PGADMIN_DEFAULT_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: \${PGADMIN_DEFAULT_PASSWORD}
    depends_on:
      - pgsql
    volumes:
      - 'sail-pgadmin:/var/lib/pgadmin'
    networks:
      - sail
YAML

    if ! grep -q '^volumes:' "${COMPOSE}"; then
      cat >> "${COMPOSE}" <<'YAML'

volumes:
  sail-pgadmin:
    driver: local
YAML
    else
      if ! grep -q 'sail-pgadmin:' "${COMPOSE}"; then
        cat >> "${COMPOSE}" <<'YAML'
  sail-pgadmin:
    driver: local
YAML
      fi
    fi
  fi

  if [[ -f .env ]]; then
    sed -i.bak -E 's/^DB_CONNECTION=.*/DB_CONNECTION=pgsql/' .env || true
    sed -i.bak -E 's/^DB_HOST=.*/DB_HOST=pgsql/' .env || true
    sed -i.bak -E 's/^DB_PORT=.*/DB_PORT=5432/' .env || true
    sed -i.bak -E 's/^DB_DATABASE=.*/DB_DATABASE=laravel/' .env || true
    sed -i.bak -E 's/^DB_USERNAME=.*/DB_USERNAME=sail/' .env || true
    sed -i.bak -E 's/^DB_PASSWORD=.*/DB_PASSWORD=password/' .env || true
    grep -q '^PGADMIN_DEFAULT_EMAIL=' .env || echo "PGADMIN_DEFAULT_EMAIL=${PGADMIN_EMAIL}" >> .env
    grep -q '^PGADMIN_DEFAULT_PASSWORD=' .env || echo "PGADMIN_DEFAULT_PASSWORD=${PGADMIN_PASSWORD}" >> .env
    grep -q '^PGADMIN_PORT=' .env || echo "PGADMIN_PORT=${PGADMIN_PORT}" >> .env
  fi
fi

# ========== phpMyAdmin si hay mysql/mariadb y está habilitado ==========
if [[ -f "${COMPOSE}" && "${PHPMYADMIN}" == "true" ]]; then
  if grep -qE '^\s*(mysql|mariadb):' "${COMPOSE}"; then
    if ! grep -qE '^\s*phpmyadmin:' "${COMPOSE}"; then
      echo "➕ Agregando servicio phpmyadmin a ${COMPOSE}"
      PMA_TARGET="mysql"
      grep -qE '^\s*mariadb:' "${COMPOSE}" && PMA_TARGET="mariadb"
      grep -qE '^\s*mysql:' "${COMPOSE}" && PMA_TARGET="mysql"

      cat >> "${COMPOSE}" <<YAML

  phpmyadmin:
    image: phpmyadmin:latest
    ports:
      - '\${PHPMYADMIN_PORT:-${PHPMYADMIN_PORT}}:80'
    environment:
      PMA_HOST: ${PMA_TARGET}
      PMA_PORT: 3306
    depends_on:
      - ${PMA_TARGET}
    networks:
      - sail
YAML
      if [[ -f .env ]]; then
        grep -q '^PHPMYADMIN_PORT=' .env || echo "PHPMYADMIN_PORT=${PHPMYADMIN_PORT}" >> .env
      fi
    fi
  fi
fi

# ========== Caso SQLite ligero ==========
if echo "$SERVICES" | grep -q "sqlite"; then
  echo "🗃️ Configurando SQLite"
  mkdir -p database
  touch database/database.sqlite
  if [[ -f .env ]]; then
    sed -i.bak -E 's/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/' .env || true
    if grep -q '^DB_DATABASE=' .env; then
      sed -i.bak -E 's|^DB_DATABASE=.*|DB_DATABASE=/var/www/html/database/database.sqlite|' .env
    else
      echo "DB_DATABASE=/var/www/html/database/database.sqlite" >> .env
    fi
    grep -q '^DB_FOREIGN_KEYS=' .env || echo "DB_FOREIGN_KEYS=true" >> .env
  fi
fi

echo "✅ Sail listo en $(pwd). Levantá con: ./vendor/bin/sail up -d"
