SELECT
    guacamole_connection.connection_name,
    guacamole_entity.name
FROM
    guacamole_connection_permission
    JOIN guacamole_connection ON guacamole_connection_permission.connection_id = guacamole_connection.connection_id
    JOIN guacamole_user_group ON guacamole_user_group.entity_id = guacamole_connection_permission.entity_id
    JOIN guacamole_user_group_member ON guacamole_user_group_member.user_group_id = guacamole_user_group.user_group_id
    JOIN guacamole_entity ON guacamole_entity.entity_id = guacamole_user_group_member.member_entity_id
WHERE
    connection_name LIKE 'Desktop:%'
    AND permission = 'READ';