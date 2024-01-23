/* Ensure that all members of '{{sre.domain.securityGroups.systemAdministrators.name}}' have superuser permissions */
/* Triggering on all ddl_command_end will catch any: CREATE, ALTER, DROP, SECURITY LABEL, COMMENT, GRANT or REVOKE command */
/* We require that CURRENT_USER has SUPERUSER permissions inside the function, otherwise the ALTER USER calls will fail*/
CREATE OR REPLACE FUNCTION fn_sysadmin_permissions()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
DECLARE
obj record;
BEGIN
IF EXISTS (SELECT usename FROM pg_user WHERE ((usename = CURRENT_USER) AND (usesuper='t'))) THEN
    FOR obj in SELECT * FROM pg_user WHERE ((usesuper='t' or usecreatedb='t') AND (usename!='postgres') AND NOT pg_has_role(usesysid, '{{sre.domain.securityGroups.systemAdministrators.name}}', 'member')) LOOP
    EXECUTE format('ALTER USER "%s" WITH NOCREATEDB NOCREATEROLE NOSUPERUSER;', obj.usename);
    END LOOP;
    FOR obj in SELECT * FROM pg_user WHERE (pg_has_role(usesysid, '{{sre.domain.securityGroups.systemAdministrators.name}}', 'member')) LOOP
    EXECUTE format('ALTER USER "%s" WITH CREATEDB CREATEROLE SUPERUSER;', obj.usename);
    END LOOP;
END IF;
END;
$$;
CREATE EVENT TRIGGER trg_sysadmin_permissions ON ddl_command_end EXECUTE FUNCTION fn_sysadmin_permissions();
/* Restrict default privileges on public schema to '{{sre.domain.securityGroups.researchUsers.name}}' */
REVOKE ALL PRIVILEGES ON SCHEMA public FROM PUBLIC;
GRANT ALL PRIVILEGES ON SCHEMA public TO "{{sre.domain.securityGroups.researchUsers.name}}";
/* Add a trigger so that new tables under 'public' schema are readable by '{{sre.domain.securityGroups.researchUsers.name}}' */
CREATE OR REPLACE FUNCTION fn_public_schema_table_permissions()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
DECLARE
obj record;
BEGIN
FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() WHERE (command_tag='CREATE TABLE' AND schema_name='public') LOOP
    EXECUTE format('GRANT SELECT ON TABLE %s TO "{{sre.domain.securityGroups.researchUsers.name}}";', obj.object_identity);
END LOOP;
END;
$$;
CREATE EVENT TRIGGER trg_public_schema_table_permissions ON ddl_command_end WHEN tag IN ('CREATE TABLE') EXECUTE PROCEDURE fn_public_schema_table_permissions();
/* Create the data schema: allow '{{sre.domain.securityGroups.researchUsers.name}}' to read and '{{sre.domain.securityGroups.dataAdministrators.name}}' to do anything */
CREATE SCHEMA IF NOT EXISTS data AUTHORIZATION "{{sre.domain.securityGroups.dataAdministrators.name}}";
GRANT ALL PRIVILEGES ON SCHEMA data TO "{{sre.domain.securityGroups.dataAdministrators.name}}";
GRANT USAGE ON SCHEMA data TO "{{sre.domain.securityGroups.researchUsers.name}}";
/* Add a trigger so that new tables under 'data' schema are owned by '{{sre.domain.securityGroups.dataAdministrators.name}}' and readable by '{{sre.domain.securityGroups.researchUsers.name}}' */
CREATE OR REPLACE FUNCTION fn_data_schema_table_permissions()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
DECLARE
obj record;
BEGIN
FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() WHERE (command_tag='CREATE TABLE' AND schema_name='data') LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO "{{sre.domain.securityGroups.dataAdministrators.name}}"; GRANT SELECT ON TABLE %s TO "{{sre.domain.securityGroups.researchUsers.name}}";', obj.object_identity, obj.object_identity);
END LOOP;
END;
$$;
CREATE EVENT TRIGGER trg_data_schema_table_permissions ON ddl_command_end WHEN tag IN ('CREATE TABLE') EXECUTE PROCEDURE fn_data_schema_table_permissions();