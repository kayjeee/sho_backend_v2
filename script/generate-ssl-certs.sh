#!/bin/bash
# Generate self-signed SSL certificates for localhost

# Exit immediately if a command exits with a non-zero status
set -e

# Create a directory for the SSL certificates
mkdir -p config/ssl

# Generate the private key and certificate signing request
openssl req -new -newkey rsa:2048 -nodes -keyout config/ssl/localhost.key -out config/ssl/localhost.csr -subj "/C=US/ST=CA/L=SF/O=Localhost/CN=localhost"

# Generate the self-signed certificate
openssl x509 -req -days 365 -in config/ssl/localhost.csr -signkey config/ssl/localhost.key -out config/ssl/localhost.crt

# Remove the certificate signing request
rm config/ssl/localhost.csr

echo "SSL certificates generated successfully in config/ssl"
