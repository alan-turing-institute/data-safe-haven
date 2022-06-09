-- Drop password entries from guacamole_user table
{{#users}}
DELETE FROM
    guacamole_user
USING
    guacamole_entity
WHERE
    guacamole_user.entity_id = guacamole_entity.entity_id
AND
    guacamole_entity.name = '{{username}}'
    AND guacamole_entity.type = 'USER';
{{/users}}
