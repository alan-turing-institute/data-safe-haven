/* Require that connection names are unique */
ALTER TABLE guacamole_connection DROP CONSTRAINT IF EXISTS connection_name_constraint;
ALTER TABLE guacamole_connection ADD CONSTRAINT connection_name_constraint UNIQUE (connection_name);

/* Load connections from text file */
CREATE TABLE connections (connection_name VARCHAR(128), ip_address VARCHAR(32));
COPY connections FROM '/var/lib/postgresql/data/connections.csv' (FORMAT CSV, DELIMITER(';'));

/* Add initial connections via RDP and ssh*/
INSERT INTO guacamole_connection (connection_name, protocol)
SELECT CONCAT(connection_name, ' ', connection_type), protocol
FROM
    (
        VALUES
        ('(Desktop)', 'rdp'),
        ('(SSH)', 'ssh')
    ) connection_settings (connection_type, protocol)
    CROSS JOIN connections
ON CONFLICT DO NOTHING;

/* Add connection details */
INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
    SELECT connection_id, parameter_name, COALESCE(parameter_value, ip_address)
    FROM
        (
            VALUES
                ('hostname', null),
                ('disable-paste', 'true'),
                ('disable-copy', 'true'),
                ('clipboard-encoding', 'UTF-8'),
                ('timezone', '{{timezone}}'),
                ('server-layout', 'en-gb-qwerty')
        ) connection_settings (parameter_name, parameter_value)
        CROSS JOIN guacamole_connection
        JOIN connections ON guacamole_connection.connection_name LIKE CONCAT(connections.connection_name, '%')
ON CONFLICT DO NOTHING;

/* Remove obsolete connections (NB. this will cascade delete guacamole_connection_parameter entries) */
DELETE FROM guacamole_connection
WHERE NOT EXISTS (
   SELECT FROM connections
   WHERE guacamole_connection.connection_name LIKE CONCAT(connections.connection_name, '%')
);

/* Drop the temporary connections table */
DROP TABLE connections;

/* Ensure that all LDAP users are Guacamole entities */
INSERT INTO guacamole_entity (name, type)
SELECT usename, 'USER'
FROM
    pg_user
    JOIN pg_auth_members ON (pg_user.usesysid = pg_auth_members.member)
    JOIN pg_roles ON (pg_roles.oid = pg_auth_members.roleid)
    WHERE rolname = 'ldap_users'
ON CONFLICT DO NOTHING;

/* Ensure that all LDAP users are Guacamole users */
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
SELECT entity_id, password_hash, password_salt, CURRENT_TIMESTAMP as password_date
FROM
    (
        SELECT
            usename,
            decode(md5(random() :: text), 'hex'),
            decode(md5(random() :: text), 'hex')
        FROM
        pg_user
        JOIN pg_auth_members ON (pg_user.usesysid = pg_auth_members.member)
        JOIN pg_roles ON (pg_roles.oid = pg_auth_members.roleid)
        WHERE rolname = 'ldap_users'
    ) user_details (username, password_hash, password_salt)
    JOIN guacamole_entity ON user_details.username = guacamole_entity.name
ON CONFLICT DO NOTHING;

/* Ensure that all user groups are Guacamole entities */
INSERT INTO guacamole_entity (name, type)
SELECT groname, 'USER_GROUP'
FROM
    pg_group
    WHERE (groname LIKE 'SG %')
ON CONFLICT DO NOTHING;

/* Ensure that all user groups are Guacamole user groups */
INSERT INTO guacamole_user_group (entity_id)
SELECT entity_id
FROM
    guacamole_entity WHERE type = 'USER_GROUP'
ON CONFLICT DO NOTHING;

/* Ensure that all users are added to the correct group */
INSERT INTO guacamole_user_group_member (user_group_id, member_entity_id)
SELECT guacamole_user_group.user_group_id, guac_user.entity_id
FROM
    pg_group
    JOIN pg_user ON pg_has_role(pg_user.usesysid, grosysid, 'member')
    JOIN guacamole_entity guac_group ON pg_group.groname = guac_group.name
    JOIN guacamole_entity guac_user ON pg_user.usename = guac_user.name
    JOIN guacamole_user_group ON guacamole_user_group.entity_id = guac_group.entity_id
    WHERE (groname LIKE 'SG %')
ON CONFLICT DO NOTHING;

/* Grant administration permissions to members of the SRE System Administrators group */
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT entity_id, permission :: guacamole_system_permission_type
FROM
    (
        VALUES
            ('{{ldap-group-system-administrators}}', 'CREATE_CONNECTION'),
            ('{{ldap-group-system-administrators}}', 'CREATE_CONNECTION_GROUP'),
            ('{{ldap-group-system-administrators}}', 'CREATE_SHARING_PROFILE'),
            ('{{ldap-group-system-administrators}}', 'CREATE_USER'),
            ('{{ldap-group-system-administrators}}', 'CREATE_USER_GROUP'),
            ('{{ldap-group-system-administrators}}', 'ADMINISTER')
    ) group_permissions (username, permission)
    JOIN guacamole_entity ON group_permissions.username = guacamole_entity.name AND guacamole_entity.type = 'USER_GROUP'
ON CONFLICT DO NOTHING;

/* Assign connection permissions to each group */
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
    SELECT entity_id, connection_id, permission::guacamole_object_permission_type
    FROM
        (
            VALUES
                ('{{ldap-group-system-administrators}}', 'READ'),
                ('{{ldap-group-system-administrators}}', 'UPDATE'),
                ('{{ldap-group-system-administrators}}', 'DELETE'),
                ('{{ldap-group-system-administrators}}', 'ADMINISTER'),
                ('{{ldap-group-researchers}}', 'READ')
        ) group_permissions (username, permission)
        CROSS JOIN guacamole_connection
        JOIN guacamole_entity ON group_permissions.username = guacamole_entity.name
ON CONFLICT DO NOTHING;
