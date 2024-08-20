#!/usr/bin/env Rscript
library(DBI, lib.loc='~/.local/bats-r-environment')
library(odbc, lib.loc='~/.local/bats-r-environment')
library(RPostgres, lib.loc='~/.local/bats-r-environment')

# Parse command line arguments
args = commandArgs(trailingOnly=TRUE)
if (length(args)!=7) {
    stop("Exactly seven arguments are required: db_type, db_name, port, server_name, hostname, username and password")
}
db_type = args[1]
db_name = args[2]
port = args[3]
server_name = args[4]
hostname = args[5]
username = args[6]
password = args[7]

# Connect to the database
print(paste("Attempting to connect to '", db_name, "' on '", server_name, "' via port '", port, sep=""))
if (db_type == "mssql") {
    cnxn <- DBI::dbConnect(
        odbc::odbc(),
        Driver = "ODBC Driver 17 for SQL Server",
        Server = paste(server_name, port, sep=","),
        Database = db_name,
        # Trusted_Connection = "yes",
        UID = paste(username, "@", hostname, sep=""),
        PWD = password
    )
} else if (db_type == "postgresql") {
    cnxn <- DBI::dbConnect(
        RPostgres::Postgres(),
        host = server_name,
        port = port,
        dbname = db_name,
        user = username,
        password = password
    )
} else {
    stop(paste("Database type '", db_type, "' was not recognised", sep=""))
}

# Run a query and save the output into a dataframe
df <- dbGetQuery(cnxn, "SELECT * FROM information_schema.tables;")
if (dim(df)[1] > 0) {
    print(head(df, 5))
    print("All database tests passed")
} else {
    stop(paste("Reading from database '", db_name, "' failed", sep=""))
}
