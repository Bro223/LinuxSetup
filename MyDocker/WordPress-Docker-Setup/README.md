# WordPress Docker Setup Guide

A complete Docker setup for running WordPress locally with MariaDB database and phpMyAdmin for database management.

## What's Included

- **WordPress** with PHP 8.5 and Apache
- **MariaDB 11** database server
- **phpMyAdmin** for database management
- **Custom entrypoint script** to handle file permissions between host and container

## Services

### WordPress
- **Container:** `wp-app`
- **URL:** http://localhost:8080
- **Port:** 8080 (maps to Apache port 80)
- **Database:** WordPress database on MariaDB
- **Root Path:** `/var/www/html` (mounted from `./www/`)

### MariaDB
- **Container:** `wp-db`
- **Root Password:** `root`
- **Database:** `wordpress`
- **User:** `wordpress`
- **Password:** `wordpress`
- **Port:** 3306 (internal, not exposed to host)
- **Data Storage:** `./db_data/` (persists between container restarts)

### phpMyAdmin
- **Container:** `wp-phpmyadmin`
- **URL:** http://localhost:8081
- **Port:** 8081 (maps to phpMyAdmin port 80)
- **Access:** Use root credentials (user: `root`, password: `root`)

## Prerequisites

- Docker installed and running
- Docker Compose installed
- At least 2GB of free disk space
- Ports 8080 and 8081 not in use

## Folder Structure

```
dockerwpsetup/
├── docker-compose.yml          # Service definitions
├── Dockerfile                  # WordPress image configuration
├── docker-entrypoint-custom.sh # Permission handling script
├── www/                        # WordPress files (auto-created)
└── db_data/                    # Database storage (auto-created)
```

## Quick Start

### 1. Start the WordPress server

Navigate to the `dockerwpsetup` folder and run:

```bash
cd /path/to/dockerwpsetup
docker compose up -d --build
```

What it does:
- Builds the WordPress image from the Dockerfile
- Starts all three containers (MariaDB, WordPress, phpMyAdmin)
- Creates `www/` and `db_data/` folders if they don't exist
- Runs containers in the background (`-d` flag)

### 2. Wait for WordPress to initialize

The first time you start, WordPress needs to initialize. Give it 30-60 seconds, then check:

```bash
docker ps
```

You should see three containers running: `wp-db`, `wp-app`, and `wp-phpmyadmin`

### 3. Access WordPress

Open your browser and go to:

```
http://localhost:8080
```

Complete the WordPress setup wizard:
- Site title
- Admin username and password
- Admin email

### 4. Access phpMyAdmin (optional)

To manage the database directly:

```
http://localhost:8081
```

Login with:
- **User:** root
- **Password:** root

## Common Commands

### View container status

```bash
docker ps
```

Shows all running containers with their IDs, ports, and status.

### View container logs

```bash
docker logs wp-app
```

Shows WordPress container logs (helpful for debugging).

```bash
docker logs wp-db
```

Shows database container logs.

### Stop all containers

```bash
docker compose down
```

Stops and removes all containers but keeps data in `db_data/` and `www/`.

### Restart containers

```bash
docker compose restart
```

Restarts all running containers without stopping them first.

### Rebuild and restart (after code changes)

```bash
docker compose down
docker compose up -d --build
```

Useful after modifying the Dockerfile or PHP code.

### Access WordPress container shell

```bash
docker exec -it wp-app bash
```

Opens a bash shell inside the WordPress container. Useful for:
- Running WP-CLI commands
- Debugging PHP errors
- Exploring the container filesystem

Example - check WordPress files:

```bash
docker exec -it wp-app ls -la /var/www/html/wp-content/
```

### Access database container shell

```bash
docker exec -it wp-db bash
```

For running MySQL commands directly or debugging database issues.

## File Permissions

The `docker-entrypoint-custom.sh` script automatically handles permissions so that:
- Files in `./www/` remain writable by both the host user and the `www-data` user inside the container
- WordPress plugins and themes can be installed and edited from both inside and outside the container
- Backups and migrations work smoothly

## Volume Mounts

### WordPress files (`./www/`)

- **Host location:** `./www/` (relative to where you run docker compose)
- **Container location:** `/var/www/html`
- **Purpose:** WordPress installation, themes, plugins, uploads
- **Persistence:** Changes persist when containers restart
- **Editing:** You can edit files from your host machine directly

### Database files (`./db_data/`)

- **Host location:** `./db_data/` (relative to where you run docker compose)
- **Container location:** `/var/lib/mysql`
- **Purpose:** MariaDB data storage
- **Persistence:** Database data persists when containers restart
- **Backup:** Backup the entire `db_data/` folder to backup your database

## Environment Variables

The docker-compose file sets:

- `UID` and `GID`: Your user ID and group ID (used for file permissions)
- `WORDPRESS_DB_HOST`: Database connection (db:3306)
- `WORDPRESS_DB_USER`: WordPress database user
- `WORDPRESS_DB_PASSWORD`: WordPress database password
- `WORDPRESS_DB_NAME`: WordPress database name

To change credentials, edit `docker-compose.yml` and rebuild:

```bash
docker compose down
docker compose up -d --build
```

⚠️ **Warning:** Changing credentials after first run requires deleting `db_data/` first.

## Backup and Restore

### Backup WordPress files and database

```bash
# Backup WordPress files
cp -r ./www ~/backup/wordpress-www-$(date +%Y%m%d)

# Backup database
cp -r ./db_data ~/backup/wordpress-db-$(date +%Y%m%d)
```

### Restore from backup

```bash
# Stop containers
docker compose down

# Restore files and database
cp -r ~/backup/wordpress-www-20240101/* ./www/
cp -r ~/backup/wordpress-db-20240101/* ./db_data/

# Start containers
docker compose up -d
```

## Troubleshooting

### WordPress shows "Error establishing database connection"

This usually means:
- Database container hasn't fully started yet - wait 30 seconds
- Database credentials are wrong - check `docker-compose.yml`
- The database container crashed - run `docker logs wp-db`

**Fix:**

```bash
docker compose restart wp-db
docker compose restart wp-app
```

### Permission denied when editing WordPress files

The file permissions may have gotten out of sync. Restart the containers:

```bash
docker compose down
docker compose up -d
```

The custom entrypoint script will fix permissions automatically.

### Port 8080 or 8081 already in use

Change the ports in `docker-compose.yml`:

```yml
  wordpress:
    ports:
      - "8090:80"  # Changed from 8080:80

  phpmyadmin:
    ports:
      - "8091:80"  # Changed from 8081:80
```

Then restart:

```bash
docker compose down
docker compose up -d
```

### View container logs for debugging

```bash
docker compose logs -f wp-app
```

Shows live logs from the WordPress container. Press `Ctrl+C` to exit.

```bash
docker compose logs wp-db
```

Shows logs from the database container.

## Next Steps

- [WordPress Admin Guide](https://wordpress.org/support/article/administration-screens/)
- [WordPress Plugin Development](https://developer.wordpress.org/plugins/)
- [WordPress Theme Development](https://developer.wordpress.org/themes/)

## Notes

- Containers restart automatically if they crash (`restart: always`)
- All data is preserved in `db_data/` and `www/` folders
- To reset everything, delete `db_data/` and `www/` folders and start fresh
- For production use, change all default passwords and credentials
- This setup is designed for local development only
