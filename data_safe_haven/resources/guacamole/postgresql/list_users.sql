SELECT
    guacamole_entity.name,
    encode(guacamole_user.password_salt, 'hex') AS password_salt_hex,
    encode(guacamole_user.password_hash, 'hex') AS password_hash_hex,
    guacamole_user.password_date
FROM
    guacamole_entity
    JOIN guacamole_user ON guacamole_entity.entity_id = guacamole_user.entity_id
WHERE
    guacamole_entity.type = 'USER';