# Laravel Sailify Project

**Sailify** provides Bash scripts to **create** or **enable Laravel Sail** on new or existing Laravel projects.  
It lets you choose **PHP/Node.js versions**, configure **database services**, and optionally include **pgAdmin** (for PostgreSQL) or **phpMyAdmin** (for MySQL/MariaDB).

---

## 📂 Files

- `nl.sh` — Creates a **new Laravel project** with Sail ready to use.  
- `en.sh` — Adds Sail to an **existing Laravel project**.  
- `sail_aliases.sh` — Installs command aliases so you can run `php`, `artisan`, `npm`, etc., **without typing `sail`**.

---

## ⚙️ Requirements

- **Composer** installed on your system  
- **Docker** and **Docker Compose**  
- Internet access to download required images and dependencies

---

## 🚀 Quick Usage

### 1️⃣ Create a New Project (`nl.sh`)

```bash
chmod +x nl.sh
./nl.sh --name myapp   --php 8.3   --node 20   --services "sqlite,mailpit"

cd myapp
./vendor/bin/sail up -d
./vendor/bin/sail artisan migrate
```

**With PostgreSQL + pgAdmin:**
```bash
./nl.sh --name myapp --services "pgsql,redis,mailpit"   --pgadmin-email admin@demo.test --pgadmin-pass supersecure --pgadmin-port 5050
```

**With MySQL + phpMyAdmin:**
```bash
./nl.sh --name myapp --services "mysql,redis,mailpit"   --phpmyadmin true --phpmyadmin-port 8081
```

---

### 2️⃣ Use an Existing Laravel Project (`en.sh`)

```bash
chmod +x en.sh
# Inside your existing Laravel project:
./en.sh --php 8.3 --node 20 --services "sqlite,mailpit"
./vendor/bin/sail up -d
./vendor/bin/sail artisan migrate
```

**With PostgreSQL + pgAdmin:**
```bash
./en.sh --services "pgsql,redis,mailpit"   --pgadmin-email admin@demo.test --pgadmin-pass supersecure
```

**With MySQL + phpMyAdmin:**
```bash
./en.sh --services "mysql,redis,mailpit"   --phpmyadmin true --phpmyadmin-port 8081
```

---

## 🧩 Supported Services (`--services`)

You can combine any of the following Sail services:

| Service | Description |
|----------|--------------|
| `mysql` | MySQL |
| `mariadb` | MariaDB |
| `pgsql` | PostgreSQL |
| `sqlite` | Local file database (no container required) |
| `redis` | In-memory data store |
| `memcached` | Cache service |
| `meilisearch` | Full-text search engine |
| `minio` | S3-compatible object storage |
| `mailpit` | Mail testing service (UI at `http://localhost:8025`) |
| `selenium` | Browser testing service (E2E testing) |

**Automatically added extras:**
- `pgAdmin` → if you include `pgsql` (UI: `http://localhost:5050`)
- `phpMyAdmin` → if you include `mysql` or `mariadb` (UI: `http://localhost:8081`)

---

## ⚙️ Environment Variables (`.env`)

The scripts automatically configure your `.env` file depending on the database engine.

### PostgreSQL
```env
DB_CONNECTION=pgsql
DB_HOST=pgsql
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=sail
DB_PASSWORD=password
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=secret
PGADMIN_PORT=5050
```

### MySQL / MariaDB
```env
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=sail
DB_PASSWORD=password
PHPMYADMIN_PORT=8081
```

### SQLite
```env
DB_CONNECTION=sqlite
DB_DATABASE=/var/www/html/database/database.sqlite
DB_FOREIGN_KEYS=true
```

---

## 🧠 Using Aliases (No `sail` Prefix Needed)

```bash
chmod +x sail_aliases.sh
./sail_aliases.sh
# Then restart your terminal or:
source ~/.sail-aliases.sh

# Examples
artisan migrate
npm run dev
php -v
```

If `vendor/bin/sail` exists, commands automatically run inside Docker containers;  
otherwise, they fallback to your local environment.

---

## 🛠️ Useful Commands

```bash
# Start Sail containers
./vendor/bin/sail up -d

# Rebuild containers (after changing PHP/Node versions)
./vendor/bin/sail build --no-cache

# Run migrations or seeders
./vendor/bin/sail artisan migrate
./vendor/bin/sail artisan db:seed

# Frontend tools
./vendor/bin/sail npm install
./vendor/bin/sail npm run dev
```

---

## 💡 Tips

- When you change **PHP** or **Node.js** versions, rebuild using:
  ```bash
  ./vendor/bin/sail build --no-cache
  ```
- The combination `sqlite,mailpit` gives you a lightweight setup ideal for local development.
- Disable `phpMyAdmin` using `--phpmyadmin false` if you don't need it.

---

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


## 📜 License

MIT License — free to use in personal or commercial projects.
