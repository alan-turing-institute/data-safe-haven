# Data Safe Haven
Django web application for the data safe haven


## Setup

### Install system requirements

* Python 3.6+
* Postgres 10+ (with dev headers)

### Install requirements into virtualenv

```bash
pip install -r requirements/base.txt
```

or, for local dev setup:

```bash
pip install -r requirements/dev.txt
```

### Set up PostgreSQL

The --createdb flag should be set for the database user if running tests (so test databases can be set up and torn down). This should not be done on a production system.

```bash
createuser haven --createdb
createdb -O haven haven
```

### Set up environment variables

Create a file named `haven/.env` with the following entries (these can also be set as environment variables
when the webserver is run):

```python
# A randomly generated string
SECRET_KEY='my-secret-key'

# Database connection string: depends on local postgres setup
DATABASE_URL='postgres://haven:haven@localhost/haven'
```

### Apply migrations

```bash
haven/manage.py migrate
```

### Create initial admin user account

```bash
haven/manage.py createsuperuser
```

### Run server

```bash
python haven/manage.py runserver
```

### Run unit tests

```
cd haven
pytest
```

## Contributing

Python dependencies are managed via [`pip-tools`](https://pypi.org/project/pip-tools/). To add a new python package to the requirements:

* Add the package name and version to the relevant `.in` file in `requirements/` (usually `requirements/base.in`)
* Run `make -C requirements/` to rebuild the requirements txt files
