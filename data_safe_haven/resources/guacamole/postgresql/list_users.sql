SELECT
    guacamole_entity.name,
    encode(guacamole_user.password_salt, 'hex') as password_salt_hex,
    encode(guacamole_user.password_hash, 'hex') as password_hash_hex,
    guacamole_user.password_date
FROM
    guacamole_entity
    join guacamole_user on guacamole_entity.entity_id = guacamole_user.entity_id
WHERE
    guacamole_entity.type = 'USER';