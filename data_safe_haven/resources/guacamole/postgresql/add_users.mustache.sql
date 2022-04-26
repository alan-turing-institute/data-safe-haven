-- Create users in guacamole_entity table
{{#users}}
INSERT INTO
    guacamole_entity (name, type)
VALUES
    ('{{username}}', 'USER')
ON CONFLICT DO NOTHING;
{{/users}}

-- Create password entries in guacamole_user table
{{#users}}
INSERT INTO
    guacamole_user (
        entity_id,
        password_hash,
        password_salt,
        password_date
    )
SELECT
    entity_id,
    decode(
        '{{password_hash}}',
        'hex'
    ),
    decode(
        '{{password_salt}}',
        'hex'
    ),
    '{{password_date}}'
FROM
    guacamole_entity
WHERE
    name = '{{username}}'
    AND guacamole_entity.type = 'USER'
ON CONFLICT DO NOTHING;
{{/users}}
