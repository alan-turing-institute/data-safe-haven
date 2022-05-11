-- Require that connection names are unique
ALTER TABLE guacamole_connection DROP CONSTRAINT IF EXISTS connection_name_constraint;
ALTER TABLE guacamole_connection ADD CONSTRAINT connection_name_constraint UNIQUE (connection_name);

-- Remove all connections (NB. this will cascade delete guacamole_connection_parameter entries)
TRUNCATE guacamole_connection CASCADE;

-- Add entries for RDP and ssh for each specified connection
{{#connections}}
INSERT INTO
    guacamole_connection (connection_name, protocol)
VALUES
    ('Desktop: {{connection_name}}', 'rdp'),
    ('SSH: {{connection_name}}', 'ssh')
ON CONFLICT DO NOTHING;
{{/connections}}

-- Add connection details
{{#connections}}
INSERT INTO
    guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
SELECT
    connection_id,
    parameter_name,
    parameter_value
FROM
    (
        VALUES
            ('hostname', '{{ip_address}}'),
            ('clipboard-encoding', 'UTF-8'),
            ('disable-copy', '{{disable_copy}}'),
            ('disable-paste', '{{disable_paste}}'),
            ('password', '${GUAC_PASSWORD}'),
            ('server-layout', 'en-gb-qwerty'),
            ('timezone', '{{timezone}}'),
            ('username', '${GUAC_USERNAME}')
    ) connection_settings (parameter_name, parameter_value)
    JOIN guacamole_connection ON guacamole_connection.connection_name LIKE '% {{connection_name}}'
ON CONFLICT DO NOTHING;
{{/connections}}
