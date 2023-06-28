SELECT
	entity_user.name,
    guacamole_user.email_address
FROM guacamole_user_group_member
	JOIN guacamole_user_group ON guacamole_user_group_member.user_group_id = guacamole_user_group.user_group_id
	JOIN guacamole_entity AS entity_group ON entity_group.entity_id = guacamole_user_group.entity_id
	JOIN guacamole_user ON guacamole_user.entity_id = guacamole_user_group_member.member_entity_id
	JOIN guacamole_entity AS entity_user ON entity_user.entity_id = guacamole_user.entity_id
WHERE
    entity_group.name = '{{group_name}}';