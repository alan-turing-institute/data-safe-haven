#! /bin/bash

# Get all members of the researchers group
GROUP_MEMBERS=$(ldapsearch -x -H ldap://localhost:1389 -D "uid={{ldap_search_user_id}},{{ldap_user_base_dn}}" -w "{{ldap_search_user_password}}" -b "cn=researchers,{{ldap_group_base_dn}}" "memberUid" | grep "memberUid:")

# Get IDs for all users
USER_IDS=$(ldapsearch -x -H ldap://localhost:1389 -D "uid={{ldap_search_user_id}},{{ldap_user_base_dn}}" -w "{{ldap_search_user_password}}" -b "{{ldap_user_base_dn}}" "uid" | grep -E "^uid:" | sed "s/uid: //g")

# Combine all information
for USER_ID in $USER_IDS; do
    for GROUP_MEMBER in $GROUP_MEMBERS; do
        IN_GROUP=0
        if [ "$GROUP_MEMBER" != "memberUid:" ] && [ "$USER_ID" == "$GROUP_MEMBER" ]; then
            IN_GROUP=1
            break
        fi
    done
    USER_DETAILS=$(ldapsearch -x -H ldap://localhost:1389 -D "uid={{ldap_search_user_id}},{{ldap_user_base_dn}}" -w "{{ldap_search_user_password}}" -b "uid=$USER_ID,{{ldap_user_base_dn}}" "employeeType" "givenName" "mail" "mobile" "uid" "uidNumber" "sn"  | grep -E "^employeeType|^givenName|^mail|^mobile|^uid|^uidNumber|^sn" | xargs)
    echo "isResearcher:${IN_GROUP};$USER_DETAILS" | sed -e "s/: /:/g" -e "s/ /;/g"
done