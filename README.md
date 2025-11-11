# Proyecto Salificar

Scripts Bash para **crear** o **sailificar** proyectos **Laravel** con **Sail**, seleccionando servicios y versiones de **PHP**/**Node.js**, con extras opcionales de administración (**pgAdmin** para Postgres y **phpMyAdmin** para MySQL/MariaDB).

## Archivos

- `nl.sh` — Crea un **nuevo** proyecto Laravel con Sail (Nuevo Laravel).
- `en.sh` — Añade Sail y servicios a un **proyecto existente** (Existente Laravel).
- `sail_aliases.sh` — Instala funciones/aliases para usar `php`, `artisan`, `npm`, etc. **sin** anteponer `sail`.

## Requisitos

- **Composer** instalado en el host.
- **Docker** y **Docker Compose**.
- Acceso a internet para descargar imágenes y paquetes.

---

## Uso rápido

### 1) Nuevo proyecto (`nl.sh`)

```bash
chmod +x nl.sh
./nl.sh --name miapp \
  --php 8.3 \
  --node 20 \
  --services "sqlite,mailpit"
cd miapp
./vendor/bin/sail up -d
./vendor/bin/sail artisan migrate
```

**Con Postgres + pgAdmin**:
```bash
./nl.sh --name miapp --services "pgsql,redis,mailpit" \
  --pgadmin-email admin@demo.test --pgadmin-pass superseguro --pgadmin-port 5050
```

**Con MySQL + phpMyAdmin**:
```bash
./nl.sh --name miapp --services "mysql,redis,mailpit" \
  --phpmyadmin true --phpmyadmin-port 8081
```

### 2) Proyecto existente (`en.sh`)

```bash
chmod +x en.sh
# En la raíz del proyecto Laravel:
./en.sh --php 8.3 --node 20 --services "sqlite,mailpit"
./vendor/bin/sail up -d
./vendor/bin/sail artisan migrate
```

**Con Postgres + pgAdmin**:
```bash
./en.sh --services "pgsql,redis,mailpit" \
  --pgadmin-email admin@demo.test --pgadmin-pass superseguro
```

**Con MySQL + phpMyAdmin**:
```bash
./en.sh --services "mysql,redis,mailpit" \
  --phpmyadmin true --phpmyadmin-port 8081
```

---

## Servicios soportados (`--services`)

Podés combinar cualquiera:

- `mysql` — MySQL
- `mariadb` — MariaDB
- `pgsql` — PostgreSQL
- `sqlite` — **sin contenedor**, base de datos en archivo `database/database.sqlite`
- `redis` — Redis
- `memcached` — Memcached
- `meilisearch` — Meilisearch (búsqueda full-text)
- `minio` — S3 compatible
- `mailpit` — Captura/visualiza emails en desarrollo (UI en `http://localhost:8025`)
- `selenium` — Navegador para pruebas end‑to‑end

**Extras auto-inyectados:**
- `pgAdmin` → si elegís `pgsql` (UI en `http://localhost:5050` por defecto)
- `phpMyAdmin` → si elegís `mysql` o `mariadb` (UI en `http://localhost:8081` por defecto)

---

## Variables y archivos

- `.env` se ajusta automáticamente para el motor elegido:
  - **Postgres**: `DB_CONNECTION=pgsql`, host `pgsql`, puerto `5432`.
  - **MySQL/MariaDB**: `DB_CONNECTION=mysql` (o `mariadb`), host `mysql`/`mariadb`, puerto `3306`.
  - **SQLite**: `DB_CONNECTION=sqlite`, `DB_DATABASE=/var/www/html/database/database.sqlite`.
- Se crea `database/database.sqlite` si elegís `sqlite`.
- Se añaden variables `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`, `PGADMIN_PORT` y `PHPMYADMIN_PORT` si corresponde.

---

## Alias sin `sail`

```bash
chmod +x sail_aliases.sh
./sail_aliases.sh
# Abrí nueva terminal o:
source ~/.sail-aliases.sh

# Ejemplos
artisan migrate
npm run dev
php -v
```

> Los wrappers detectan `vendor/bin/sail`: si existe, ejecutan dentro del contenedor; si no, usan el binario local.

---

## Tips

- Si cambiás la versión de **PHP** o **Node.js**, el Dockerfile se edita; luego **reconstruí**:
  ```bash
  ./vendor/bin/sail build --no-cache
  ```
- **SQLite + Mailpit** es un stack súper liviano para desarrollo.
- Para ambientes con `pgsql`, `mysql` o `mariadb`, podés desactivar phpMyAdmin con `--phpmyadmin false`.

---

## Licencia

MIT — usalo libremente en tus proyectos.
