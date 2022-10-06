#! /bin/bash
db_type=""
language=""
while getopts d:l: flag; do
    case "${flag}" in
        d) db_type=${OPTARG};;
        l) language=${OPTARG};;
        *) echo "Invalid option ${OPTARG}"; exit 1;;
    esac
done

if [ "$db_type" == "mssql" ]; then
    db_name="master"
    port="{{SmokeTests.MSSQLPort}}"
    server_name="{{SmokeTests.MSSQLVMName}}.{{shm.domain.fqdn}}"
elif [ "$db_type" == "postgres" ]; then
    db_name="postgres"
    port="{{SmokeTests.PostgreSQLPort}}"
    server_name="{{SmokeTests.PostgreSQLVMName}}.{{shm.domain.fqdn}}"
else
    echo "Did not recognise database type '$db_type'"
fi

if [ $port == "" ]; then
    echo "Database type '$db_type' is not part of this SRE"
    echo "All database tests passed"
else
    script_path=$(dirname "$(readlink -f "$0")")
    if [ "$language" == "python" ]; then
        python "${script_path}"/test_databases_python.py --db-type "$db_type" --db-name "$db_name" --port "$port" --server-name "$server_name"
    elif [ "$language" == "R" ]; then
        Rscript "${script_path}"/test_databases_R.R "$db_type" "$db_name" "$port" "$server_name"
    fi
fi
