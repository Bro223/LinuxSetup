#!/bin/bash
set -e

# Fix permissions on /var/www/html (mounted volume)
# This ensures both www-data and host user can write to the WordPress directory
if [ -d /var/www/html ]; then
    echo "Setting correct permissions on /var/www/html..."
    
    # Set ownership to www-data but make files group-writable
    # This works when the host folder is owned by the host user
    # and www-data writes to it from inside the container
    
    # Only change ownership of files that www-data doesn't own yet
    # This preserves host user ownership while allowing www-data to write
    find /var/www/html -type d -exec chmod 775 {} \; 2>/dev/null || true
    find /var/www/html -type f -exec chmod 664 {} \; 2>/dev/null || true
    
    # Ensure www-data can write by adding it to group permissions
    chgrp -R www-data /var/www/html 2>/dev/null || true
    
    echo "Permissions set successfully!"
fi

# Call the original WordPress entrypoint
exec docker-entrypoint.sh "$@"
