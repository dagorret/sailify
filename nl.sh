#!/usr/bin/env bash
set -euo pipefail

# ========== Config por defecto (sobrescribible por flags o variables de entorno) ==========
APP_NAME=""
PHP_VERSION="${PHP_VERSION:-8.3}"     # Versión de PHP para la imagen de Sail (laravelsail/phpXY)
NODE_VERSION="${NODE_VERSION:-20}"    # Node.js para el contenedor de app
SERVICES_DEFAULT="mysql,mariadb,pgsql,redis,memcached,meilisearch,minio,mailpit,selenium"
SERVICES="${SERVICES:-$SERVICES_DEFAULT}"

# Extras opcionales de administración web
PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@example.com}"     # Usuario inicial de pgAdmin
PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-secret}"          # Password inicial de pgAdmin
PGADMIN_PORT="${PGADMIN_PORT:-5050}"                    # Puerto host para pgAdmin
PHPMYADMIN="${PHPMYADMIN:-true}"                        # Incluir phpMyAdmin si hay mysql o mariadb
PHPMYADMIN_PORT="${PHPMYADMIN_PORT:-8081}"              # Puerto host para phpMyAdmin

# ========== Ayuda ==========
usage() {
cat <<EOF
Uso: $(basename "$0") --name NOMBRE [opciones]

Crea un proyecto Laravel nuevo y lo configura con Sail y servicios seleccionados.

Opciones:
  --name NOMBRE           Nombre de la carpeta/proyecto (obligatorio)
  --php X.Y               Versión PHP p/ Sail (default: ${PHP_VERSION})
  --node N                Versión Node.js (default: ${NODE_VERSION})
  --services LISTA        Servicios Sail (default: ${SERVICES_DEFAULT})
  --pgadmin-email EMAIL   Email pgAdmin (default: ${PGADMIN_EMAIL})
  --pgadmin-pass PASS     Password pgAdmin (default: ****)
  --pgadmin-port PORT     Puerto pgAdmin (default: ${PGADMIN_PORT})
  --phpmyadmin true|false Incluir phpMyAdmin si hay mysql/mariadb (default: ${PHPMYADMIN})
  --phpmyadmin-port PORT  Puerto phpMyAdmin (default: ${PHPMYADMIN_PORT})
  -h, --help              Ayuda
EOF
}

# ========== Parseo de argumentos ==========
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) APP_NAME="$2"; shift 2;;
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

# ========== Validaciones básicas ==========
if [[ -z "${APP_NAME}" ]]; then
  echo "❌ Debes indicar --name NOMBRE"
  usage; exit 1
fi
if ! command -v composer >/dev/null 2>&1; then
  echo "❌ composer no está instalado en el host."
  exit 1
fi

# ========== Crear proyecto ==========
echo "🆕 Creando proyecto Laravel: ${APP_NAME}"
composer create-project laravel/laravel "${APP_NAME}"

# ========== Entrar al proyecto y delegar en lógica común (ver función) ==========
cd "${APP_NAME}"

apply_sail_and_services() {
  local php_v="$1" node_v="$2" services="$3" \
        pgadmin_email="$4" pgadmin_pass="$5" pgadmin_port="$6" \
        phpmyadmin="$7" phpmyadmin_port="$8"

  # ----- Instalar Sail -----
  echo "📦 Instalando laravel/sail..."
  composer require laravel/sail --dev --no-interaction --no-progress
  composer dump-autoload --no-interaction >/dev/null 2>&1 || true

  # ----- Generar docker-compose con servicios -----
  echo "⚙️ Ejecutando php artisan sail:install --with=\"$services\""
  php artisan sail:install --with="$services" --no-interaction

  # ----- Detectar Dockerfile de la app de Sail -----
  local DOCKERFILE=""
  DOCKERFILE=$(grep -RIl "laravelsail/php" docker dockerfiles . 2>/dev/null | head -n1 || true)
  if [[ -n "${DOCKERFILE}" && -f "${DOCKERFILE}" ]]; then
    echo "🧩 Ajustando Dockerfile: ${DOCKERFILE}"

    # Ajustar tag base de PHP (8.3 → php83).
    local PHP_TAG
    PHP_TAG="$(echo "$php_v" | tr -d '.')"
    sed -i.bak -E "s|(laravelsail/php)[0-9]+(-composer)?|\1${PHP_TAG}\2|g" "${DOCKERFILE}" || true

    # Inyectar/ajustar ARG NODE_VERSION
    if grep -qE 'ARG NODE_VERSION=' "${DOCKERFILE}"; then
      sed -i.bak -E "s|ARG NODE_VERSION=.*|ARG NODE_VERSION=${node_v}|g" "${DOCKERFILE}"
    else
      awk -v nv="${node_v}" '
        BEGIN{printed=0}
        /^FROM / && printed==0 { print; print "ARG NODE_VERSION=" nv; printed=1; next }
        { print }
      ' "${DOCKERFILE}" > "${DOCKERFILE}.tmp" && mv "${DOCKERFILE}.tmp" "${DOCKERFILE}"
    fi
  else
    echo "⚠️ No pude localizar el Dockerfile de Sail para forzar PHP/Node. Ajustá manual si lo necesitás."
  fi

  # ----- Insertar pgAdmin si está pgsql en la composición -----
  local COMPOSE="docker-compose.yml"
  if [[ -f "${COMPOSE}" ]] && echo "$services" | grep -q "pgsql"; then
    if ! grep -qE '^\s*pgadmin:' "${COMPOSE}"; then
      echo "➕ Agregando servicio pgadmin a ${COMPOSE}"
      cat >> "${COMPOSE}" <<YAML

  pgadmin:
    image: dpage/pgadmin4:latest
    ports:
      - '\${PGADMIN_PORT:-${pgadmin_port}}:80'
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
      # Asegurar volumen
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
    # Ajustes .env
    if [[ -f .env ]]; then
      sed -i.bak -E 's/^DB_CONNECTION=.*/DB_CONNECTION=pgsql/' .env || true
      sed -i.bak -E 's/^DB_HOST=.*/DB_HOST=pgsql/' .env || true
      sed -i.bak -E 's/^DB_PORT=.*/DB_PORT=5432/' .env || true
      sed -i.bak -E 's/^DB_DATABASE=.*/DB_DATABASE=laravel/' .env || true
      sed -i.bak -E 's/^DB_USERNAME=.*/DB_USERNAME=sail/' .env || true
      sed -i.bak -E 's/^DB_PASSWORD=.*/DB_PASSWORD=password/' .env || true
      grep -q '^PGADMIN_DEFAULT_EMAIL=' .env || echo "PGADMIN_DEFAULT_EMAIL=${pgadmin_email}" >> .env
      grep -q '^PGADMIN_DEFAULT_PASSWORD=' .env || echo "PGADMIN_DEFAULT_PASSWORD=${pgadmin_pass}" >> .env
      grep -q '^PGADMIN_PORT=' .env || echo "PGADMIN_PORT=${pgadmin_port}" >> .env
    fi
  fi

  # ----- Insertar phpMyAdmin si hay mysql/mariadb y está habilitado -----
  if [[ -f "${COMPOSE}" && "${phpmyadmin}" == "true" ]]; then
    if grep -qE '^\s*(mysql|mariadb):' "${COMPOSE}"; then
      if ! grep -qE '^\s*phpmyadmin:' "${COMPOSE}"; then
        echo "➕ Agregando servicio phpmyadmin a ${COMPOSE}"
        local PMA_TARGET="mysql"
        grep -qE '^\s*mariadb:' "${COMPOSE}" && PMA_TARGET="mariadb"
        grep -qE '^\s*mysql:' "${COMPOSE}" && PMA_TARGET="mysql"

        cat >> "${COMPOSE}" <<YAML

  phpmyadmin:
    image: phpmyadmin:latest
    ports:
      - '\${PHPMYADMIN_PORT:-${phpmyadmin_port}}:80'
    environment:
      PMA_HOST: ${PMA_TARGET}
      PMA_PORT: 3306
    depends_on:
      - ${PMA_TARGET}
    networks:
      - sail
YAML
        if [[ -f .env ]]; then
          grep -q '^PHPMYADMIN_PORT=' .env || echo "PHPMYADMIN_PORT=${phpmyadmin_port}" >> .env
        fi
      fi
    fi
  fi

  # ----- Caso SQLite -----
  if echo "$services" | grep -q "sqlite"; then
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

  echo "✅ Sail listo. Levantá con: ./vendor/bin/sail up -d"
  echo "   PHP: ${php_v} · Node: ${node_v}"
}

apply_sail_and_services "${PHP_VERSION}" "${NODE_VERSION}" "${SERVICES}" \
                        "${PGADMIN_EMAIL}" "${PGADMIN_PASSWORD}" "${PGADMIN_PORT}" \
                        "${PHPMYADMIN}" "${PHPMYADMIN_PORT}"

echo "🎉 Proyecto creado en $(pwd)"
echo "👉 Sugerido: ./vendor/bin/sail up -d && ./vendor/bin/sail artisan migrate"
