#!/usr/bin/env bash
set -euo pipefail

# ========== Defaults ==========
PROJECT_DIR="."                                  # Directorio del proyecto existente
PHP_VERSION="${PHP_VERSION:-8.3}"               # e.g. 8.3, 8.2
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
Si no hay Composer en el host, usa docker/podman con la imagen composer:2.

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

# ========== Helpers ==========
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Detectar runtime de contenedores (docker o podman)
RUNTIME=""
if has_cmd docker; then
  RUNTIME="docker"
elif has_cmd podman; then
  RUNTIME="podman"
fi

# Wrapper para ejecutar Composer y PHP (dentro o fuera de contenedor)
USE_CONTAINER_COMPOSER="false"
if ! has_cmd composer; then
  if [[ -z "${RUNTIME}" ]]; then
    echo "❌ composer no está instalado y tampoco encontré docker/podman."
    echo "   Instalá Composer o Docker/Podman para continuar."
    exit 1
  fi
  USE_CONTAINER_COMPOSER="true"
fi

# Construir comandos según disponibilidad
container_uid="$(id -u)"
container_gid="$(id -g)"
container_workdir="/app"

if [[ "${USE_CONTAINER_COMPOSER}" == "true" ]]; then
  COMPOSER_CACHE_DIR="${HOME}/.cache/composer"
  mkdir -p "${COMPOSER_CACHE_DIR}"

  run_in_container() {
    ${RUNTIME} run --rm \
      -u "${container_uid}:${container_gid}" \
      -v "${PWD}:${container_workdir}" \
      -v "${COMPOSER_CACHE_DIR}:/tmp/composer-cache" \
      -e COMPOSER_CACHE_DIR=/tmp/composer-cache \
      -w "${container_workdir}" \
      "$@"
  }

  COMPOSER_CMD=(run_in_container composer:2 composer)
  PHP_CMD=(run_in_container composer:2 php)
else
  COMPOSER_CMD=(composer)
  PHP_CMD=(php)
fi

composer_exec() { "${COMPOSER_CMD[@]}" "$@"; }
php_exec() { "${PHP_CMD[@]}" "$@"; }

# ========== Validaciones ==========
cd "${PROJECT_DIR}"
if [[ ! -f composer.json ]]; then
  echo "❌ No se encontró composer.json en $(pwd). ¿Estás en un proyecto Laravel?"
  exit 1
fi

# ========== Instalar Sail y generar compose ==========
echo "📦 Instalando laravel/sail (ignorando requisitos de plataforma SOLO en este paso)..."
# Ignora TODOS los platform-reqs del proyecto (intl, gd, etc.) SOLO para agregar Sail
COMPOSER_SAIL_FLAGS=(--dev --no-interaction --no-progress --ignore-platform-reqs)
composer_exec require laravel/sail "${COMPOSER_SAIL_FLAGS[@]}" || {
  echo "❌ Falló composer require laravel/sail (incluso ignorando platform-reqs)."
  exit 1
}
composer_exec dump-autoload --no-interaction >/dev/null 2>&1 || true

echo "⚙️ Ejecutando php artisan sail:install --with=\"$SERVICES\""
php_exec artisan sail:install --with="$SERVICES" --no-interaction

# ========== Localizar Dockerfile real de Sail y ajustar PHP/Node + intl+gd ==========
COMPOSE="docker-compose.yml"
DOCKERFILE=""
RUNTIME_DIR=""

# 1) Preferimos el runtime segun PHP_VERSION: vendor/laravel/sail/runtimes/<PHP_VERSION>/Dockerfile
CANDIDATE="vendor/laravel/sail/runtimes/${PHP_VERSION}/Dockerfile"
if [[ -f "${CANDIDATE}" ]]; then
  RUNTIME_DIR="vendor/laravel/sail/runtimes/${PHP_VERSION}"
  DOCKERFILE="${CANDIDATE}"
  # Actualizar docker-compose.yml para que apunte a ese runtime (si existe compose)
  if [[ -f "${COMPOSE}" ]]; then
    sed -i.bak -E "s|runtimes/[0-9]+\.[0-9]+|runtimes/${PHP_VERSION}|g" "${COMPOSE}" || true
  fi
fi

# 2) Si no existe el runtime exacto, tomamos el primero disponible bajo vendor/laravel/sail/runtimes/*
if [[ -z "${DOCKERFILE}" ]]; then
  DOCKERFILE=$(find vendor/laravel/sail/runtimes -maxdepth 2 -type f -name "Dockerfile" 2>/dev/null | head -n1 || true)
  [[ -n "${DOCKERFILE}" ]] && RUNTIME_DIR="$(dirname "${DOCKERFILE}")"
fi

# 3) Si tampoco aparece, intentamos leer el contexto de build del compose (laravel.test)
if [[ -z "${DOCKERFILE}" && -f "${COMPOSE}" ]]; then
  # Extraer context y dockerfile del servicio laravel.test con awk básico (sin yq)
  CONTEXT_PATH=$(awk '
    BEGIN{in_service=0}
    /^[[:space:]]*services:/{in_services=1}
    in_services && /^[[:space:]]*laravel\.test:/{in_service=1; next}
    in_service && /^[[:space:]]*[a-zA-Z0-9_.-]+:/{exit}  # fin del bloque del servicio
    in_service && $1 ~ /context:/ {print $2; exit}
  ' "${COMPOSE}" 2>/dev/null || true)

  DOCKERFILE_NAME=$(awk '
    BEGIN{in_service=0}
    /^[[:space:]]*services:/{in_services=1}
    in_services && /^[[:space:]]*laravel\.test:/{in_service=1; next}
    in_service && /^[[:space:]]*[a-zA-Z0-9_.-]+:/{exit}
    in_service && $1 ~ /dockerfile:/ {print $2; exit}
  ' "${COMPOSE}" 2>/dev/null || true)

  [[ -z "${DOCKERFILE_NAME:-}" ]] && DOCKERFILE_NAME="Dockerfile"
  if [[ -n "${CONTEXT_PATH:-}" && -f "${CONTEXT_PATH}/${DOCKERFILE_NAME}" ]]; then
    RUNTIME_DIR="${CONTEXT_PATH}"
    DOCKERFILE="${CONTEXT_PATH}/${DOCKERFILE_NAME}"
  fi
fi

if [[ -n "${DOCKERFILE}" && -f "${DOCKERFILE}" ]]; then
  echo "🧩 Ajustando Dockerfile: ${DOCKERFILE}"

  # Asegurar ARG NODE_VERSION (lo insertamos si no existe)
  if grep -qE '^ARG[[:space:]]+NODE_VERSION=' "${DOCKERFILE}"; then
    sed -i.bak -E "s|^ARG[[:space:]]+NODE_VERSION=.*|ARG NODE_VERSION=${NODE_VERSION}|g" "${DOCKERFILE}"
  else
    awk -v nv="${NODE_VERSION}" '
      BEGIN{printed=0}
      /^FROM[[:space:]]/ && printed==0 { print; print "ARG NODE_VERSION=" nv; printed=1; next }
      { print }
    ' "${DOCKERFILE}" > "${DOCKERFILE}.tmp" && mv "${DOCKERFILE}.tmp" "${DOCKERFILE}"
  fi

  # Inyectar intl + gd si no están
  need_inject="false"
  grep -qiE 'docker-php-ext-install[[:space:]].*intl' "${DOCKERFILE}" || need_inject="true"
  grep -qiE 'docker-php-ext-install[[:space:]].*gd'   "${DOCKERFILE}" || need_inject="true"

  if [[ "$need_inject" == "true" ]]; then
    echo "➕ Inyectando instalación de intl y gd en ${DOCKERFILE}"
    # Insertar tras la PRIMERA línea FROM para máxima compatibilidad
    awk '
      BEGIN{inserted=0}
      /^FROM[[:space:]]/ && inserted==0 {
        print
        print "RUN apt-get update \\"
        print "    && apt-get install -y --no-install-recommends \\"
        print "       libicu-dev libjpeg62-turbo-dev libpng-dev libfreetype6-dev libwebp-dev \\"
        print "    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \\"
        print "    && docker-php-ext-install gd \\"
        print "    && docker-php-ext-configure intl \\"
        print "    && docker-php-ext-install intl \\"
        print "    && rm -rf /var/lib/apt/lists/*"
        inserted=1
        next
      }
      { print }
    ' "${DOCKERFILE}" > "${DOCKERFILE}.tmp" && mv "${DOCKERFILE}.tmp" "${DOCKERFILE}"
  fi
else
  echo "⚠️ No pude localizar el Dockerfile de Sail."
  echo "   Busqué en vendor/laravel/sail/runtimes y en docker-compose.yml (laravel.test)."
  echo "   Decime dónde está tu Dockerfile y lo adapto al toque."
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

echo "✅ Sail listo en $(pwd)."
echo "➡️ Construí la imagen para aplicar intl/gd y Node:"
echo "   ./vendor/bin/sail build --no-cache"
echo "   ./vendor/bin/sail up -d"
echo "🔎 Verificá intl y gd:"
echo "   ./vendor/bin/sail php -m | grep -Ei 'intl|gd' || echo 'extensiones NO cargadas'"
echo "📦 Luego instalá dependencias normalmente (sin ignorar requisitos):"
echo "   ./vendor/bin/sail composer install"
