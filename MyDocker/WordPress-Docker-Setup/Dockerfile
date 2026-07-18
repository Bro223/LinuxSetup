FROM wordpress:php8.5-apache

# Install required packages for Duplicator, other plugins, and email support
RUN apt-get update && \
    apt-get install -y \
        unzip \
        zip \
        msmtp \
        msmtp-mta \
    && rm -rf /var/lib/apt/lists/*

# Configure msmtp to deliver to a local Mailpit (add a mailpit service to docker-compose)
# For now, configure with a catch-all that won't fail
RUN printf 'account default\nhost mailpit\nport 1025\nauto_from on\nmaildomain localhost\ntls off\ntls_starttls off\n' > /etc/msmtprc

# Set PHP to use msmtp as sendmail
RUN echo 'sendmail_path = "/usr/bin/msmtp -t"' > /usr/local/etc/php/conf.d/mail.ini

# Copy custom entrypoint script
COPY docker-entrypoint-custom.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint-custom.sh

# Use custom entrypoint
ENTRYPOINT ["docker-entrypoint-custom.sh"]
CMD ["apache2-foreground"]
