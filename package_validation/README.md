# Python package validation

## Criteria

According to [issue 312](https://github.com/alan-turing-institute/data-safe-haven/issues/312) the criteria to validate a package are:

1) Have version control on public GitHub or Gitlab. 
Measure: Yes/No
2) Have commits within the last year
Measure: Number of commits per month for the past 36 months
3) Have commits by at least three different contributors
Measure: Number of distinct committers in past month, 3 months, 6 months, 12 months, 24 months, 36 months
4) Be on a recognised package repository (PyPI, Conda, CRAN, Bioconductor.)
Measure: Name of package repository plus release date and version number of all releases if available
5) Have LICENSE and README files (always true if on repository?)
Measure: Yes/No (plus name of licence if available/inferable, length of README in words and possibly content of LICENSE and README files - Note: Look for any files names LICENSE/LICENCE or README, regardless of suffix (or lack of)
6) The lead contributor should have an email address (always true if on repository?)
Measure: Yes/No plus capture of actual email address

## The process

The code starts with a list of packages taken from the Anaconda website. It can use a list for Python 2.7, 3.6, or 3.7. It gets the package name, version, a url of the package specified in Anaconda, and a boolean variable to say if the package comes or not with the installation.

The output of the code is a DataFrame with the following columns.

| Column | Description | Example |
| --- | --- | --- |
| name | Name of the Python package.| `pandas` |
| version | Version of the package in the installation | `0.24.2` |
| link | An url taken from the Anaconda list | http://pandas.pydata.org |
| in_installation | If the package comes in the defualt installation of Anaconda | TRUE |
| github_link | Gets a github url if the `link` column has a github url or a readthedocs.org link. If doesn't find it in `link`, it queries the libraries.io API in search of repository url. | https://github.com/pandas-dev/pandas |
| has_version_control | Yes if the `github_link` is a github.com, gitlab.com or bitbucket.org url.| `No` |
| pypi_url | Generated url for the PYPI repository. If exists, it is used to get the libraries.io of the package to collect data about | https://pypi.org/project/pandas |
| login | Login of the first main contributor with email. | | 
| email | Email of the first main contributor with email. | |
| cont_rank | Ranking of the first main contributor that has email data.| `5` |
| licenses | Licenses of the project. | `BSD-3-Clause` |
| num_commits | Number of commits in the last year. | `2225` |
| num_contributors_last_year | Number of contributors in the last year. | `17` |
| total_contributors | Total number of contributros to the project. If the number is `100` then the project has more than 100 contributors. | 100 |
| more_than_3_contributors | If the project has more than three contributors in the last year. It is calculated based on `num_contributors_last_year` columns. | `Yes` |
| is_in_pypi | If the package can be found in PYPI. It evaluates if the `pypi_url` exists. If the response status is 200 of a get request. | `Yes` |
| is_in_conda | If the package can be found in the Anaconda link. | `Yes` |
| evaluation_criteria | Logic evaluation of six conditions, all six must be TRUE. | TRUE |
| number_of_dependencies | Number of packages that this package depends on. | `2` |
| dependencies | List of tuples indicating `package` and `version` separated by space. | `['pyparsing >=2.0.2', 'six *']` |

The `evaluation_criteria` column is calculated as follows:
```python
(has_version_control == 'Yes'
and (False if num_commits == None else num_commits > 3)
and more_than_3_contributors=='Yes'
and (is_in_pypi == 'Yes' or is_in_conda == 'Yes')
and licenses != None
and email != None)
```

### Limitations
* `has_version_control` searches in a column that specifically stores a github url. Gitlab and bitbucket data collection has not been implemented.
* Verification of a README file is not implemented. It only checks for licenses at the moment.
* For criteria 2) the code only verifies the last year.
* For criteria 3) the code is no verifying all the intervals. It only verifies the last year. 
* The libraries.io API accepts 60 calls per minute.
* The GitHub.com API accepts 5000 calls per hour to a registered user. And 60 calls per hour to a non registered user.

The process starts with the list of packages in the Anaconda list of packages.

The validation uses three websites

* https://libraries.io/api
* github.com
* pypi.org

The script evaluates in order package by package all the criterias. 

It creates a dataframe with name, version, url and a boolean variable if the package comes or not with the anaconda installation.

## To do
- [ ] Implement dependency search of the evaluation criteria. At the moment it evaluates package by package and doesn't consider dependencies. This should be a simple seach algorithm in a graph that collects the evaluation criteria of the dependencies and updates the current one if they are different. 
- [ ] Extend the data collection from Gitlab, Bitbucket and other public repositories where packages can be hosted.

## How to use the code

The code is in two files. [python_package_validation.py](python_package_validation.py) and [python_validation.py](python_validation.py). All the functions are in `python_package_validation.py`, which are imported from `python_validation.py`. 

Having both files in the same folder, they can be used from the terminal as follows.

```
python python_validation.py
```

By default, it will get a base list of packages from Anaconda installation for Linux of Python version 3.7.

The `python_validation.py` can be modified with a different Python version and also changing the path or name of the excel file that is exported at the end of the processing.

```python
import python_package_validation as pv
import pandas as pd

# Starts with an initial list from an anaconda url or packages
df = pd.DataFrame()
df = pv.evaluate_packages_from_anaconda(python_version = '3.7')

# Exporting the results to an Excel file
df.to_excel('python_packages_v1.xlsx')
```

The `python_validation.py` can also be used to run single package validations. It will return a dataframe with only one row.

```python
import python_package_validation as pv
import pandas as pd

result = pd.DataFrame()

example_package_name = 'pandas'
result = pv.evaluate_package(example_package_name)
print('{}'.format(result['evaluation_criteria']))
print(result)
```