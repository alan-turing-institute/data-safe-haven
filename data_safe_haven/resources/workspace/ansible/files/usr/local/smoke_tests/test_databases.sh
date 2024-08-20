#! /bin/bash
db_type=""
language=""
while getopts d:l: flag; do
    case "${flag}" in
    d) db_type=${OPTARG} ;;
    l) language=${OPTARG} ;;
    *)
        echo "Invalid option ${OPTARG}"
        exit 1
        ;;
    esac
done

# Read database password from file
db_credentials="/etc/database_credential"
username="databaseadmin"
password="$(cat $db_credentials 2> /dev/null)"
if [ -z "$password" ]; then
    echo "Database password could not be read from '$db_credentials'."
    exit 1
fi

sre_fqdn="$(grep trusted /etc/pip.conf | cut -d "." -f 2-99)"
sre_prefix="$(hostname | cut -d "-" -f 1-4)"
if [ "$db_type" == "mssql" ]; then
    db_name="master"
    port="1433"
    server_name="mssql.${sre_fqdn}"
    hostname="${sre_prefix}-db-server-mssql"
elif [ "$db_type" == "postgresql" ]; then
    db_name="postgres"
    port="5432"
    server_name="postgresql.${sre_fqdn}"
    hostname="${sre_prefix}-db-server-postgresql"
else
    echo "Did not recognise database type '$db_type'"
    exit 1
fi

if [ "$port" == "" ]; then
    echo "Database type '$db_type' is not part of this SRE"
    exit 1
else
    script_path=$(dirname "$(readlink -f "$0")")
    if [ "$language" == "python" ]; then
        python "${script_path}"/test_databases_python.py --db-type "$db_type" --db-name "$db_name" --port "$port" --server-name "$server_name" --hostname "$hostname" --username "$username" --password "$password" || exit 1
    elif [ "$language" == "R" ]; then
        Rscript "${script_path}"/test_databases_R.R "$db_type" "$db_name" "$port" "$server_name" "$hostname" "$username" "$password" || exit 1
    fi
fi
