## {{green_book}} Access databases

Your project might use a database for holding the input data.
You might also/instead be provided with a database for use in analysing the data.
The database server will use either `Microsoft SQL` or `PostgreSQL`.

If you have access to one or more databases, you can access them using the following details, replacing `<SRE ID>` with the {ref}`SRE ID <user_guide_sre_id>` for your project.

### Microsoft SQL

- Server name: `MSSQL-<SRE ID>` (e.g. `MSSQL-SANDBOX` )
- Database name: \<provided by your {ref}`role_system_manager`>
- Port: 1433

### PostgreSQL

- Server name: `PSTGRS-<SRE ID>` (e.g. `PSTGRS-SANDBOX` )
- Database name: \<provided by your {ref}`role_system_manager`>
- Port: 5432

Examples are given below for connecting using `Azure Data Studio`, `DBeaver`, `Python` and `R`.
The instructions for using other graphical interfaces or programming languages will be similar.

### {{art}} Connecting using Azure Data Studio

`Azure Data Studio` is currently only able to connect to `Microsoft SQL` databases.

````{note}
Our example user Ada Lovelace, working in the `sandbox` SRE on the `projects.turingsafehaven.ac.uk` Safe Haven, would connect using Azure Data Studio as follows:


```{image} user_guide/db_azure_data_studio.png
:alt: Azure Data Studio connection details
:align: center
```
````

```{important}
Be sure to select `Windows authentication` here so that your username and password will be passed through to the database.
```

### {{bear}} Connecting using DBeaver

Click on the `New database connection` button (which looks a bit like an electrical plug with a plus sign next to it)

#### Microsoft SQL

- Select `SQL Server` as the database type
- Enter the necessary information in the `Host` and `Port` boxes and set `Authentication` to `Kerberos`
- Tick `Show All Schemas` otherwise you will not be able to see the input data

````{note}
Our example user Ada Lovelace, working in the `sandbox` SRE on the `projects.turingsafehaven.ac.uk` Safe Haven, would connect using DBeaver as follows:

```{image} user_guide/db_dbeaver_mssql.png
:alt: DBeaver connection details for Microsoft SQL
:align: center
```
````

```{important}
Be sure to select `Kerberos authentication` so that your username and password will be passed through to the database
```

#### PostgreSQL

- Select `PostgreSQL` as the database type
- Enter the necessary information in the `Host` and `Port` boxes and set `Authentication` to `Database Native`

```{important}
You do not need to enter any information in the `Username` or `Password` fields
```

````{note}
Our example user Ada Lovelace, working in the `sandbox` SRE on the `projects.turingsafehaven.ac.uk` Safe Haven, would connect using DBeaver as follows:

```{image} user_guide/db_dbeaver_postgres_connection.png
:alt: DBeaver connection details for PostgreSQL
:align: center
```
````

````{tip}
If you are prompted for `Username` or `Password` when connecting, you can leave these blank and the correct username and password will be automatically passed through to the database
```{image} user_guide/db_dbeaver_postgres_ignore.png
:alt: DBeaver username/password prompt
:align: center
```
````

### {{snake}} Connecting using Python

Database connections can be made using `pyodbc` or `psycopg2` depending on which database flavour is being used.
The data can be read into a dataframe for local analysis.

```{note}
Our example user Ada Lovelace, working in the `sandbox` SRE on the `projects.turingsafehaven.ac.uk` Safe Haven, would connect using DBeaver as follows:
```

#### Microsoft SQL

```python
import pyodbc
import pandas as pd

server = "MSSQL-SANDBOX.projects.turingsafehaven.ac.uk"
port = "1433"
db_name = "master"

cnxn = pyodbc.connect("DRIVER={ODBC Driver 17 for SQL Server};SERVER=" + server + "," + port + ";DATABASE=" + db_name + ";Trusted_Connection=yes;")

df = pd.read_sql("SELECT * FROM information_schema.tables;", cnxn)
print(df.head(3))
```

#### PostgreSQL

```python
import psycopg2
import pandas as pd

server = "PSTGRS-SANDBOX.projects.turingsafehaven.ac.uk"
port = 5432
db_name = "postgres"

cnxn = psycopg2.connect(host=server, port=port, database=db_name)
df = pd.read_sql("SELECT * FROM information_schema.tables;", cnxn)
print(df.head(3))
```

### {{registered}} Connecting using R

Database connections can be made using `odbc` or `RPostgres` depending on which database flavour is being used.
The data can be read into a dataframe for local analysis.

```{note}
Our example user Ada Lovelace, working in the `sandbox` SRE on the `projects.turingsafehaven.ac.uk` Safe Haven, would connect using DBeaver as follows:
```

#### Microsoft SQL

```R
library(DBI)
library(odbc)

# Connect to the databases
cnxn <- DBI::dbConnect(
    odbc::odbc(),
    Driver = "ODBC Driver 17 for SQL Server",
    Server = "MSSQL-SANDBOX.projects.turingsafehaven.ac.uk,1433",
    Database = "master",
    Trusted_Connection = "yes"
)

# Run a query and save the output into a dataframe
df <- dbGetQuery(cnxn, "SELECT * FROM information_schema.tables;")
head(df, 3)
```

#### PostgreSQL

```R
library(DBI)
library(RPostgres)

# Connect to the databases
cnxn <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = "PSTGRS-SANDBOX.projects.turingsafehaven.ac.uk",
    port = 5432,
    dbname = "postgres"
)

# Run a query and save the output into a dataframe
df <- dbGetQuery(cnxn, "SELECT * FROM information_schema.tables;")
head(df, 3)
```
