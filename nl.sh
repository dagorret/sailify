#!/usr/bin/env bash
set -euo pipefail

# ========== Defaults ==========
PROJECT_NAME=""                                # obligatorio: --name <carpeta>
PHP_VERSION="${PHP_VERSION:-8.3}"              # 8.3 / 8.2 / 8.1
NODE_VERSION="${NODE_VERSION:-20}"
SERVICES_DEFAULT="mysql,mariadb,pgsql,redis,memcached,meilisearch,minio,mailpit,selenium"
SERVICES="${SERVICES:-sqlite,mailpit}"         # por defecto liviano
PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@example.com}"
PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-secret}"
PGADMIN_PORT="${PGADMIN_PORT:-5050}"
PHPMYADMIN="${PHPMYADMIN:-true}"
PHPMYADMIN_PORT="${PHPMYADMIN_PORT:-8081}"

usage() {
cat <<EOF
Uso: $(basename "$0") --name NOMBRE [opciones]

Crea un proyecto Laravel nuevo con Sail completamente configurado, sin requerir Composer en el host.

Opciones:
  --name NOMBRE           Carpeta/Nombre del proyecto (obligatorio)
  --php X.Y               Versión PHP (default: ${PHP_VERSION})
  --node N                Versión Node.js (default: ${NODE_VERSION})
  --services LISTA        Servicios Sail (default: ${SERVICES})
  --pgadmin-email EMAIL   Email pgAdmin (default: ${PGADMIN_EMAIL})
  --pgadmin-pass PASS     Password pgAdmin (default: ${PGADMIN_PASSWORD})
  --pgadmin-port PORT     Puerto pgAdmin (default: ${PGADMIN_PORT})
  --phpmyadmin true|false Incluir phpMyAdmin si hay mysql/mariadb (default: ${PHPMYADMIN})
  --phpmyadmin-port PORT  Puerto phpMyAdmin (default: ${PHPMYADMIN_PORT})
  -h, --help              Ayuda

Ejemplos:
  $(basename "$0") --name myapp --services "sqlite,mailpit"
  $(basename "$0") --name myapp --php 8.2 --services "mariadb,redis,mailpit" --phpmyadmin true
EOF
}

# ========== Parse args ==========
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) PROJECT_NAME="$2"; shift 2;;
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

if [[ -z "${PROJECT_NAME}" ]]; then
  echo "❌ Falta --name NOMBRE"
  usage
  exit 1
fi

# ========== Helpers ==========
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Detectar runtime de contenedores (docker o podman)
RUNTIME=""
if has_cmd docker; then
  RUNTIME="docker"
elif has_cmd podman; then
  RUNTIME="podman"
fi

if [[ -z "${RUNTIME}" ]]; then
  echo "❌ Necesitás Docker o Podman instalado."
  exit 1
fi

# Wrapper para ejecutar composer/php dentro de contenedor con UID/GID del host
container_uid="$(id -u)"
container_gid="$(id -g)"
container_workdir="/app"
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

composer_c() { run_in_container composer:2 composer "$@"; }
php_c()      { run_in_container composer:2 php "$@"; }

# ========== Crear proyecto base ==========
if [[ -e "${PROJECT_NAME}" ]]; then
  echo "❌ La carpeta '${PROJECT_NAME}' ya existe."
  exit 1
fi

echo "📦 Creando proyecto Laravel: ${PROJECT_NAME}"
composer_c create-project --no-interaction laravel/laravel "${PROJECT_NAME}"

cd "${PROJECT_NAME}"

# .env inicial
cp .env.example .env

# ========== Instalar Sail ignorando platform-reqs (intl/gd) solo en este paso ==========
echo "➕ Agregando laravel/sail (bootstrap, ignorando requisitos de plataforma)..."
composer_c require laravel/sail --dev --no-interaction --no-progress --ignore-platform-reqs || {
  echo "❌ Falló composer require laravel/sail."
  exit 1
}
composer_c dump-autoload --no-interaction >/dev/null 2>&1 || true

# ========== Sail install con servicios ==========
echo "⚙️ Ejecutando php artisan sail:install --with='${SERVICES}'"
php_c artisan sail:install --with="${SERVICES}" --no-interaction

# ========== Forzar runtime PHP correcto y ajustar Dockerfile (intl + gd + Node) ==========
COMPOSE="docker-compose.yml"
RUNTIME_DIR="vendor/laravel/sail/runtimes/${PHP_VERSION}"
DOCKERFILE="${RUNTIME_DIR}/Dockerfile"

if [[ -f "${DOCKERFILE}" ]]; then
  echo "🧩 Ajustando Dockerfile: ${DOCKERFILE}"
  # Apuntar compose a la versión PHP seleccionada
  if [[ -f "${COMPOSE}" ]]; then
    sed -i.bak -E "s|runtimes/[0-9]+\.[0-9]+|runtimes/${PHP_VERSION}|g" "${COMPOSE}" || true
  fi

  # Asegurar ARG NODE_VERSION
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
  if [[ "${need_inject}" == "true" ]]; then
    echo "➕ Inyectando intl y gd en ${DOCKERFILE}"
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
  echo "⚠️ No encontré ${DOCKERFILE}. Sail usará su runtime por defecto."
fi

# ========== Extras: pgAdmin / phpMyAdmin en docker-compose ==========
if [[ -f "${COMPOSE}" ]]; then
  # pgAdmin si hay pgsql
  if echo "${SERVICES}" | grep -q "pgsql"; then
    if ! grep -qE '^\s*pgadmin:' "${COMPOSE}"; then
      echo "➕ Agregando pgAdmin a ${COMPOSE}"
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
      # asegurar volumen
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
      # .env defaults
      grep -q '^PGADMIN_DEFAULT_EMAIL=' .env || echo "PGADMIN_DEFAULT_EMAIL=${PGADMIN_EMAIL}" >> .env
      grep -q '^PGADMIN_DEFAULT_PASSWORD=' .env || echo "PGADMIN_DEFAULT_PASSWORD=${PGADMIN_PASSWORD}" >> .env
      grep -q '^PGADMIN_PORT=' .env || echo "PGADMIN_PORT=${PGADMIN_PORT}" >> .env
    fi
    # Ajustar .env para PG
    sed -i.bak -E 's/^DB_CONNECTION=.*/DB_CONNECTION=pgsql/' .env || true
    sed -i.bak -E 's/^DB_HOST=.*/DB_HOST=pgsql/' .env || true
    sed -i.bak -E 's/^DB_PORT=.*/DB_PORT=5432/' .env || true
    sed -i.bak -E 's/^DB_DATABASE=.*/DB_DATABASE=laravel/' .env || true
    sed -i.bak -E 's/^DB_USERNAME=.*/DB_USERNAME=sail/' .env || true
    sed -i.bak -E 's/^DB_PASSWORD=.*/DB_PASSWORD=password/' .env || true
  fi

  # phpMyAdmin si hay mysql/mariadb y está habilitado
  if [[ "${PHPMYADMIN}" == "true" ]] && echo "${SERVICES}" | grep -Eq "mysql|mariadb"; then
    if ! grep -qE '^\s*phpmyadmin:' "${COMPOSE}"; then
      echo "➕ Agregando phpMyAdmin a ${COMPOSE}"
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
      grep -q '^PHPMYADMIN_PORT=' .env || echo "PHPMYADMIN_PORT=${PHPMYADMIN_PORT}" >> .env
    fi
  fi
fi

# ========== SQLite ajuste ==========
if echo "${SERVICES}" | grep -q "sqlite"; then
  echo "🗃️ Configurando SQLite"
  mkdir -p database
  touch database/database.sqlite
  sed -i.bak -E 's/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/' .env || true
  if grep -q '^DB_DATABASE=' .env; then
    sed -i.bak -E 's|^DB_DATABASE=.*|DB_DATABASE=/var/www/html/database/database.sqlite|' .env
  else
    echo "DB_DATABASE=/var/www/html/database/database.sqlite" >> .env
  fi
  grep -q '^DB_FOREIGN_KEYS=' .env || echo "DB_FOREIGN_KEYS=true" >> .env
fi

# ========== UID/GID persistentes para evitar permisos ==========
echo "➕ Estableciendo WWWUSER/WWWGROUP en .env"
grep -q '^WWWUSER=' .env || echo "WWWUSER=${container_uid}" >> .env
grep -q '^WWWGROUP=' .env || echo "WWWGROUP=${container_gid}" >> .env

# ========== Permisos en host (storage, cache) ==========
echo "🔐 Ajustando permisos en storage y bootstrap/cache"
chmod -R u+rwX,g+rwX storage bootstrap/cache || true

# ========== Build + Up ==========
echo "🔨 Construyendo imágenes (aplicando intl/gd y Node ${NODE_VERSION})"
./vendor/bin/sail build --no-cache
echo "🚀 Levantando contenedores"
./vendor/bin/sail up -d

# ========== Generar APP_KEY, link storage y migrar si hay DB ==========
echo "🔑 Generando APP_KEY"
./vendor/bin/sail artisan key:generate --force || true
echo "🔗 Creando storage:link"
./vendor/bin/sail artisan storage:link || true

if echo "${SERVICES}" | grep -Eq "mysql|mariadb|pgsql"; then
  echo "🗄️ Ejecutando migraciones"
  ./vendor/bin/sail artisan migrate || true
fi

# ========== Info final ==========
echo
echo "✅ Proyecto listo en $(pwd)"
echo "➡️ URL app:          http://localhost"
if echo "${SERVICES}" | grep -q "mailpit"; then
  echo "➡️ Mailpit UI:       http://localhost:8025 (SMTP: mailpit:1025)"
fi
if echo "${SERVICES}" | grep -Eq "mysql|mariadb"; then
  echo "➡️ phpMyAdmin:       http://localhost:${PHPMYADMIN_PORT} (host: mariadb/mysql)"
fi
if echo "${SERVICES}" | grep -q "pgsql"; then
  echo "➡️ pgAdmin:          http://localhost:${PGADMIN_PORT}"
fi
echo
echo "Comandos útiles:"
echo "  ./vendor/bin/sail artisan migrate"
echo "  ./vendor/bin/sail npm install && ./vendor/bin/sail npm run dev"
