# My Docker Configurations

This folder contains reusable Docker configurations for different development environments.

## Folders

### WordPress-Docker-Setup/

Complete WordPress development environment with:
- WordPress with PHP 8.5 and Apache
- MariaDB 11 database
- phpMyAdmin for database management
- Custom permission handling

**Quick start:**

```bash
cd WordPress-Docker-Setup
docker compose up -d --build
```

Access WordPress at: http://localhost:8080

See [WordPress-Docker-Setup/README.md](WordPress-Docker-Setup/README.md) for detailed instructions.

## General Docker Commands

See [../Commands%20And%20Settings/README.md](../Commands%20And%20Settings/README.md) for Docker Compose and Docker commands reference.
