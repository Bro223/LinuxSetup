# WordPress Docker Setup

A complete Docker setup for running WordPress locally with MariaDB database, Mailpit (email catching), and phpMyAdmin for database management.

## What's Included

- **WordPress** with PHP 8.5 and Apache
- **MariaDB 11** database server with custom config
- **Mailpit** — SMTP email catcher (dev/test emails, never sent)
- **phpMyAdmin** for database management
- **Custom entrypoint script** to handle file permissions between host and container

## Services

### WordPress
| Property | Value |
|----------|-------|
| Container | `wp-app` |
| URL | http://localhost:8085 |
| Port | 8085 (maps to Apache port 80) |
| Root Path | `/var/www/html` (mounted from `./www/`) |

### MariaDB
| Property | Value |
|----------|-------|
| Container | `wp-db` |
| Root Password | `root` |
| Database | `wordpress` |
| User | `wordpress` |
| Password | `wordpress` |
| Data Storage | `./db_data/` (persists between container restarts) |
| Custom Config | `./db_config/custom.cnf` (tuned for WordPress) |

### Mailpit (Email Catcher)
| Property | Value |
|----------|-------|
| Container | `wp-mailpit` |
| Web UI | http://localhost:8025 |
| SMTP Port | 1025 (internal, used by WordPress via msmtp) |
| Purpose | Catches all outgoing emails for local testing |

### phpMyAdmin
| Property | Value |
|----------|-------|
| Container | `wp-phpmyadmin` |
| URL | http://localhost:8084 |
| Access | User: `root`, Password: `root` |

## Prerequisites

- Docker installed and running
- Docker Compose installed
- At least 2GB of free disk space
- Ports 8085, 8084, and 8025 not in use

## Folder Structure

```
WordPress-Docker-Setup/
├── docker-compose.yml              # Service definitions
├── Dockerfile                      # WordPress image configuration
├── docker-entrypoint-custom.sh     # Permission handling script
├── db_config/
│   └── custom.cnf                  # MariaDB custom config
├── www/                            # WordPress files (auto-created)
└── db_data/                        # Database storage (auto-created)
```

## Quick Start

### 1. Start the WordPress server

```bash
cd /path/to/WordPress-Docker-Setup
docker compose up -d --build
```

This will:
- Build the WordPress image from the Dockerfile
- Start all four containers (MariaDB, WordPress, Mailpit, phpMyAdmin)
- Create `www/` and `db_data/` folders if they don't exist
- Run containers in the background (`-d` flag)

### 2. Wait for WordPress to initialize

The first start takes 30-60 seconds for MariaDB to initialize. Check status:

```bash
docker ps
```

You should see four containers running: `wp-db`, `wp-app`, `wp-mailpit`, and `wp-phpmyadmin`.

### 3. Access WordPress

```
http://localhost:8085
```

Complete the WordPress setup wizard.

### 4. Access Mailpit (for test emails)

```
http://localhost:8025
```

All emails WordPress sends (password resets, notifications, etc.) are caught here during development.

### 5. Access phpMyAdmin

```
http://localhost:8084
```

Login with root / root.

## Common Commands

| Command | What it does |
|---------|-------------|
| `docker compose up -d --build` | Build & start all containers |
| `docker compose down` | Stop & remove all containers (data preserved) |
| `docker compose restart` | Restart all containers |
| `docker compose logs -f wp-app` | Live WordPress logs |
| `docker compose logs wp-db` | Database logs |
| `docker exec -it wp-app bash` | Shell into WordPress container |
| `docker exec -it wp-db bash` | Shell into database container |

## Email Testing (Mailpit)

WordPress is pre-configured to route all outgoing emails through Mailpit via msmtp:

- No emails are actually sent — they're caught by Mailpit
- View them at http://localhost:8025
- Useful for testing password resets, notifications, contact forms, etc.

To switch to real email sending, change `/etc/msmtprc` in the Dockerfile or override the `mail.ini` PHP config.

## File Permissions

The `docker-entrypoint-custom.sh` script automatically handles permissions:
- Files in `./www/` are writable by both the host user and `www-data` inside the container
- WordPress plugins and themes can be installed from the admin dashboard or from your host machine

## Notes

- Containers restart automatically if they crash (`restart: always`)
- All data is preserved in `db_data/` and `www/` folders
- To reset completely, delete `db_data/` and `www/` folders and start fresh
- For production use, change all default passwords and credentials
- This setup is designed for **local development only**
