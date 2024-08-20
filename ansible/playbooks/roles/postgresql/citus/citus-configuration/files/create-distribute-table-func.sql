\c postgres
SELECT 'CREATE DATABASE citusdb OWNER postgres' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'citusdb');\gexec

\c citusdb
SELECT 'CREATE EXTENSION citus' WHERE NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'citus');\gexec

-- CREATE OR REPLACE FUNCTION auto_distribute_table()
-- RETURNS event_trigger AS $$
-- DECLARE
--     obj record;
--     table_name text;
-- BEGIN
--     FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() WHERE command_tag = 'CREATE TABLE'
--     LOOP
--         -- Extract the schema and table name
--         table_name := obj.object_identity;
--
--         -- Attempt to distribute the table on the 'id' column
--         -- This assumes that 'id' is a common column name across your tables
--         EXECUTE format('SELECT create_distributed_table(%L, %L)', table_name, 'id');
--
--         RAISE NOTICE 'Distributed table: %', table_name;
--     END LOOP;
-- EXCEPTION
--     WHEN others THEN
--         RAISE NOTICE 'Could not distribute table: %', table_name;
-- END;
-- $$ LANGUAGE plpgsql;
