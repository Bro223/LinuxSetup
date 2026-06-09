FROM wordpress:php8.5-apache

# Install required packages for Duplicator and other plugins
RUN apt-get update && \
    apt-get install -y \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

# Copy custom entrypoint script
COPY docker-entrypoint-custom.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint-custom.sh

# Use custom entrypoint
ENTRYPOINT ["docker-entrypoint-custom.sh"]
CMD ["apache2-foreground"]
