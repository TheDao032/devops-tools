DO $$
BEGIN
    -- Check if the user "repmgr" exists, and create it with SUPERUSER privileges if it doesn't exist.
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'repmgr') THEN
        CREATE ROLE repmgr WITH SUPERUSER CREATEROLE CREATEDB LOGIN;
    END IF;
END
$$;

-- Check if the database "repmgr" exists, and create it with "repmgr" as the owner if it doesn't exist.
\c postgres
SELECT 'CREATE DATABASE repmgr OWNER repmgr' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'repmgr')\gexec
