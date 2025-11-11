# 🚀 Instalación rápida de Laravel Sail en un proyecto existente

Este entorno automatiza la instalación y configuración de **Laravel Sail** con servicios comunes como **MariaDB**, **Mailpit**, **phpMyAdmin**, y herramientas adicionales.  
Funciona incluso si **Composer no está instalado** en tu máquina, usando Docker o Podman como fallback.

---

## 🧩 Requisitos previos

Antes de ejecutar el script:

- Tener instalado **Docker** o **Podman** (uno de los dos es suficiente).
- Un proyecto Laravel existente con `composer.json`.
- Acceso a Internet para descargar imágenes base.
- Permisos de ejecución sobre el script (`chmod +x en.sh`).

---

## ⚙️ Ejecución del script

Ejecutá el script desde el directorio raíz del proyecto Laravel:

```bash
./en.sh --services "mariadb,mailpit" --phpmyadmin true --php 8.2
```

O si no tenés permisos de ejecución:

```bash
bash en.sh --services "mariadb,mailpit" --phpmyadmin true --php 8.2
```

### 🔧 Parámetros disponibles

| Opción | Descripción | Valor por defecto |
|--------|--------------|-------------------|
| `--project-dir DIR` | Directorio del proyecto | `.` |
| `--php X.Y` | Versión de PHP para Sail | `8.3` |
| `--node N` | Versión de Node.js | `20` |
| `--services LISTA` | Lista de servicios Sail | `mysql,mariadb,pgsql,redis,memcached,meilisearch,minio,mailpit,selenium` |
| `--phpmyadmin true|false` | Agrega phpMyAdmin si hay MySQL/MariaDB | `true` |
| `--phpmyadmin-port PORT` | Puerto phpMyAdmin | `8081` |
| `--pgadmin-email EMAIL` | Email de pgAdmin (si usás pgsql) | `admin@example.com` |
| `--pgadmin-pass PASS` | Contraseña pgAdmin | `secret` |
| `--pgadmin-port PORT` | Puerto pgAdmin | `5050` |

---

## 🧱 Qué hace el script

1. **Instala Laravel Sail** (`laravel/sail`) ignorando temporalmente extensiones faltantes (`intl`, `gd`).
2. Detecta si Composer está instalado localmente; si no, usa `composer:2` dentro de Docker/Podman.
3. Ejecuta `php artisan sail:install` con los servicios especificados.
4. Detecta el Dockerfile real de Sail en  
   `vendor/laravel/sail/runtimes/<PHP_VERSION>/Dockerfile`
   y lo modifica para:
   - Inyectar las extensiones **intl** y **gd**.
   - Actualizar la versión de **Node.js**.
5. Actualiza automáticamente tu `docker-compose.yml` para apuntar al runtime correcto.
6. Si usás MySQL o MariaDB, agrega **phpMyAdmin** automáticamente.
7. Si usás PostgreSQL, agrega **pgAdmin**.
8. Configura SQLite si fue seleccionado.

---

## 🧰 Comandos posteriores a la instalación

### 🔨 1. Construir la imagen (aplica intl/gd y Node)

```bash
./vendor/bin/sail build --no-cache
```

### 🚀 2. Levantar los contenedores

```bash
./vendor/bin/sail up -d
```

### 🧩 3. Verificar extensiones instaladas

```bash
./vendor/bin/sail php -m | grep -Ei 'intl|gd' || echo 'extensiones NO cargadas'
```

### 📦 4. Instalar dependencias

```bash
./vendor/bin/sail composer install
```

### 🗃️ 5. Migrar la base de datos

```bash
./vendor/bin/sail artisan migrate
```

---

## 🧾 Configuración de la base de datos

Si usás **MariaDB**, asegurate que tu `.env` tenga algo como:

```env
DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=sail
DB_PASSWORD=password
```

---

## 🌐 Servicios incluidos

| Servicio | URL / Puerto | Descripción |
|-----------|---------------|--------------|
| Laravel App | http://localhost | Aplicación principal |
| phpMyAdmin | http://localhost:8081 | UI para MariaDB/MySQL |
| Mailpit (Web) | http://localhost:8025 | Visualizar correos enviados |
| Mailpit (SMTP) | `mailpit:1025` | Servidor SMTP local |
| MariaDB | `mariadb:3306` | Base de datos principal |

---

## 🧰 Tips útiles

- Para reiniciar los contenedores:

  ```bash
  ./vendor/bin/sail restart
  ```

- Para entrar a la consola PHP dentro del contenedor:

  ```bash
  ./vendor/bin/sail shell
  ```

- Para ejecutar migraciones y seeders en una sola línea:

  ```bash
  ./vendor/bin/sail artisan migrate:fresh --seed
  ```

- Para destruir todo y empezar limpio:

  ```bash
  ./vendor/bin/sail down -v
  ```

---

## ⚠️ Problemas comunes

| Error | Causa / Solución |
|-------|------------------|
| `composer: command not found` | El script usa `composer:2` dentro de Docker automáticamente. No hace falta tenerlo instalado. |
| `TTY mode requires /dev/tty` | Advertencia inofensiva. Ignorala. |
| `intl` o `gd` faltan | Reejecutá `./vendor/bin/sail build --no-cache`. |
| `Permission denied` | Corré `chmod +x en.sh` o `bash en.sh ...` |
| `No pude localizar Dockerfile` | Asegurate de haber ejecutado el script dentro del proyecto Laravel con Sail instalado. |

---

## 💡 Recomendaciones finales

- Si vas a trabajar con distintos proyectos Laravel, mantené este script en tu `$HOME/bin` y ejecutalo desde cualquier repo.
- Si usás **Arch Linux**, asegurate de tener `docker`, `podman`, `bash` y `dos2unix` instalados.
- Para cambiar de PHP más adelante, podés volver a ejecutar:
  ```bash
  ./en.sh --php 8.3
  ./vendor/bin/sail build --no-cache
  ```
- Si tu equipo usa Git, agregá `vendor/` y `docker-compose.override.yml` al `.gitignore`.

---

## Recuerde

## REmember
```
echo "WWWUSER=$(id -u)" >> .env
echo "WWWGROUP=$(id -g)" >> .env
```

and
```
./vendor/bin/sail build --no-cache
./vendor/bin/sail up -d
./vendor/bin/sail composer install
```

## ✅ Conclusión

Con este setup:

- No necesitás tener PHP ni Composer en tu host.
- Todo corre dentro de contenedores Docker Sail.
- Las extensiones `intl` y `gd` ya están habilitadas.
- MariaDB, phpMyAdmin y Mailpit funcionan automáticamente.

Tu entorno Laravel queda listo para desarrollo local con un solo comando. 🚀
