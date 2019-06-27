#!/bin/bash
# $LDAP_USER must be present as an environment variable
# $DOMAIN_LOWER must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

read -r -d '' HACKMD_CONFIG <<- EOM
version: '2'
services:
    database:
        # Don't upgrade PostgreSQL by simply changing the version number
        # You need to migrate the Database to the new PostgreSQL version
        image: postgres:9.6-alpine
        #mem_limit: 256mb         # version 2 only
        #memswap_limit: 512mb     # version 2 only
        #read_only: true          # not supported in swarm mode please enable along with tmpfs
        #tmpfs:
        #  - /run/postgresql:size=512K
        #  - /tmp:size=256K
        environment:
            - POSTGRES_USER=hackmd
            - POSTGRES_PASSWORD=hackmdpass
            - POSTGRES_DB=hackmd
        volumes:
            - database:/var/lib/postgresql/data
        networks:
            backend:
        restart: always

    app:
        image: hackmdio/hackmd:1.2.0
        #mem_limit: 256mb         # version 2 only
        #memswap_limit: 512mb     # version 2 only
        #read_only: true          # not supported in swarm mode, enable along with tmpfs
        #tmpfs:
        #  - /tmp:size=512K
        #  - /hackmd/tmp:size=1M
        # Make sure you remove this when you use filesystem as upload type
        #  - /hackmd/public/uploads:size=10M
        volumes:
            - uploads:/hackmd/public/uploads
        environment:
        # DB_URL is formatted like: <databasetype>://<username>:<password>@<hostname>/<database>
        # Other examples are:
        # - mysql://hackmd:hackmdpass@database:3306/hackmd
        # - sqlite:///data/sqlite.db (NOT RECOMMENDED)
        # - For details see the official sequelize docs: http://docs.sequelizejs.com/en/v3/
            - HMD_DB_URL=postgres://hackmd:hackmdpass@database:5432/hackmd
            - HMD_ALLOW_ANONYMOUS=false
            - HMD_ALLOW_FREEURL=true
            - HMD_EMAIL=false
            - HMD_USECDN=false
            - HMD_LDAP_SEARCHFILTER=<hackmd-user-filter>
            - HMD_LDAP_SEARCHBASE=<hackmd-ldap-base>
            - HMD_LDAP_BINDCREDENTIALS=<hackmd-bind-creds>
            - HMD_LDAP_BINDDN=<hackmd-bind-dn>
            - HMD_LDAP_URL=<hackmd-ldap-url>
            - HMD_LDAP_PROVIDERNAME=<hackmd-ldap-netbios>
            - HMD_IMAGE_UPLOAD_TYPE=filesystem
        ports:
        # Ports that are published to the outside.
        # The latter port is the port inside the container. It should always stay on 3000
        # If you only specify a port it'll published on all interfaces. If you want to use a
        # local reverse proxy, you may want to listen on 127.0.0.1.
        # Example:
        # - "127.0.0.1:3000:3000"
            - "3000:3000"
        networks:
            backend:
        restart: always
        depends_on:
            - database

# Define networks to allow best isolation
networks:
    # Internal network for communication with PostgreSQL/MySQL
    backend:
    
# Define named volumes so data stays in place
volumes:
    # Volume for PostgreSQL/MySQL database
    database:
    uploads:
EOM

echo "Template HackMD config:"
echo "$HACKMD_CONFIG" 

TEMP_CONFIG="/tmp/docker-compose-hackmd.yml"
sudo echo "$HACKMD_CONFIG" > $TEMP_CONFIG

sed -i.bak "s%<hackmd-user-filter>%${HMD_LDAP_SEARCHFILTER}%g" $TEMP_CONFIG
sed -i.bak "s%<hackmd-ldap-base>%${HMD_LDAP_SEARCHBASE}%g" $TEMP_CONFIG
sed -i.bak "s%<hackmd-bind-creds>%${HMD_LDAP_BINDCREDENTIALS}%g" $TEMP_CONFIG
sed -i.bak "s%<hackmd-bind-dn>%${HMD_LDAP_BINDDN}%g" $TEMP_CONFIG
sed -i.bak "s%<hackmd-ldap-url>%${HMD_LDAP_URL}%g" $TEMP_CONFIG
sed -i.bak "s%<hackmd-ldap-netbios>%${HMD_LDAP_PROVIDERNAME}%g" $TEMP_CONFIG

echo "Patched HackMD config:"
sudo cat $TEMP_CONFIG

# copy config to placeholder used by cloud-init (to ensure consistency of this copy)
sudo cp $TEMP_CONFIG /docker-compose-hackmd.yml
# Copy config placeholder to location used by docker
sudo cp $TEMP_CONFIG /src/docker-hackmd/docker-compose.yml
echo "HackMD configuration updated"
sudo docker-compose -f /src/docker-hackmd/docker-compose.yml up -d
echo "HackMD restarted"
