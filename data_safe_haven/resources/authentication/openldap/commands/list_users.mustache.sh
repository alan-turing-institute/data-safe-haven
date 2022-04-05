#! /bin/bash
ldapsearch -x -H ldap://localhost:1389 -D "uid={{ldap_search_user_id}},{{ldap_user_base_dn}}" -w "{{ldap_search_user_password}}" -b "cn=researchers,{{ldap_group_base_dn}}" "memberUid" | grep "memberUid:" | awk '{print $2}'
