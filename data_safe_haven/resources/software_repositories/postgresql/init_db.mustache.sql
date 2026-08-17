-- Initialization Script. Based on https://help.sonatype.com/en/install-nexus-repository-with-postgresql.html

-- Create a schema
CREATE SCHEMA IF NOT EXISTS nexus;

-- Create new user
DO
$$
BEGIN
  IF NOT EXISTS (SELECT * FROM pg_user WHERE usename = 'nexus') THEN
    CREATE USER nexus WITH PASSWORD '{{nexus_password}}';
  ELSE
    ALTER USER nexus WITH PASSWORD '{{nexus_password}}';
  END IF;
END
$$
;

-- Grant permissions for new user on the new database
GRANT ALL PRIVILEGES ON DATABASE nexus TO nexus;
GRANT ALL PRIVILEGES ON DATABASE nexus TO nexus;

-- Create extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA nexus;
