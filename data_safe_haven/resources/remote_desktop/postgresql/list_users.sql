SELECT
    guacamole_entity.name,
    guacamole_user.email_address
FROM
    guacamole_entity
    JOIN guacamole_user ON guacamole_entity.entity_id = guacamole_user.entity_id
WHERE
    guacamole_entity.type = 'USER';