#! /bin/bash
while getopts d:l:n:p:s: flag
do
    case "${flag}" in
        d) db_type=${OPTARG};;
        l) language=${OPTARG};;
    esac
done

if [ $db_type == "mssql" ]; then
    db_name="master"
    port="<mssql-port>"
    server_name="<mssql-server-name>"
elif [ $db_type == "postgres" ]; then
    db_name="postgres"
    port="<postgres-port>"
    server_name="<postgres-server-name>"
else
    echo "Did not recognise database type '$db_type'"
fi

if [ $port == "" ]; then
    echo "Database type '$db_type' is not part of this SRE"
    echo "All database tests passed"
else
    if [ $language == "python" ]; then
        python test_databases_python.py --db-type $db_type --db-name $db_name --port $port --server-name $server_name
    elif [ $language == "R" ]; then
        Rscript test_databases_R.R $db_type $db_name $port $server_name
    fi
fi
