DO $$
BEGIN
    -- Check if the user "k3s" exists, and create it with SUPERUSER privileges if it doesn't exist.
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'k3s') THEN
        CREATE ROLE k3s WITH SUPERUSER CREATEROLE CREATEDB LOGIN;
        ALTER USER k3s WITH PASSWORD :k3spass;
    END IF;
END
$$;

-- Check if the database "k3s" exists, and create it with "k3s" as the owner if it doesn't exist.
\c postgres
SELECT 'CREATE DATABASE k3s OWNER k3s' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'k3s')\gexec
GRANT ALL PRIVILEGES ON DATABASE k3s TO k3s\gexec

\c k3s
DO $$
BEGIN
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO k3s;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO k3s;
END
$$;
