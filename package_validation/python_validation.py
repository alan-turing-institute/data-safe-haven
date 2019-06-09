import python_package_validation as pv
from tqdm import tqdm
import time

# Starts with an initial list from an anaconda url or packages
df = pv.get_initial_python_packages('https://docs.anaconda.com/anaconda/packages/py3.7_linux-64/')

# Creates new columns in the dataframe
df['github_link'] = None            # url of the github repository
df['has_version_control'] = None    # Yes/No if has a public repository in github, gitlab, or bitbucket
df['pypi_url'] = None               # generated pypi url, this url needs to be tested if exists or not.

# 
pbar = tqdm(range(len(df)))
for i in pbar:
    pbar.set_description('{}'.format(df.name.iloc[i]))
    df.at[i, 'github_link'] = pv.get_github_url(df.name.iloc[i], df.link.iloc[i])
    df.at[i, 'has_version_control'] = pv.has_version_control(df.name.iloc[i], df.github_link.iloc[i])
    df.at[i, 'pypi_url'] = pv.get_pypi_url(df.name.iloc[i])

# Information from libraries.io
df['login'] = None          # login of a main contributor
df['email'] = None          # email of a main contributor
df['cont_rank'] = None      # ranking of the contributor, starts searching from the lead contributor until finds an email and its rank
df['licenses'] = None       # license of the package

# This takes awhile because libraries.io has a rate limit of 60 calls per minute
pbar = tqdm(range(len(df)))
for i in pbar:
    pbar.set_description('{}'.format(df.name.iloc[i]))
    login, email, cont_rank = pv.get_contributor_email(df.name.iloc[i])
    _, repo_url, licenses = pv.get_project_info(df.name.iloc[i])
    df.at[i, 'login'] = login
    df.at[i, 'email'] = email
    df.at[i, 'cont_rank'] = cont_rank
    if repo_url and df.github_link.iloc[i] == None:
        df.at[i, 'github_link'] = repo_url
    if licenses:
        df.at[i, 'licenses'] = licenses
    time.sleep(1.5) # 1.5s because there is two calls to the API within the loop

# Creates new columns Information from GitHub
df['num_commits'] = None					# Number of commits in the last year
df['num_contributors_last_year'] = None		# Number of contributors in the last year
df['total_contributors'] = None				# Total number of contributores of the package
df['more_than_3_contributors'] = None		# Yes/No if the package has more than 3 contributors
df['is_in_pypi'] = None						# Yes/No if the package is in PYPI
df['is_in_conda'] = None					# Yes/No if the package is in Anaconda

# Gets all the packages in Python 3.7 in a list, to verify if the package is or not in the anaconda distribution.
python_anaconda_37 = pv.get_conda_packages('https://docs.anaconda.com/anaconda/packages/py3.7_linux-64/')

pbar = tqdm(range(len(df)))
for i in pbar:
    pbar.set_description('{}'.format(df.name.iloc[i]))
    if df.github_link.iloc[i]:
        df.at[i, 'num_commits'] = pv.get_num_commits(df.github_link.iloc[i])
        df.at[i, 'num_contributors_last_year'] = pv.get_contributors(df.github_link.iloc[i], 365)
        df.at[i, 'total_contributors'] = pv.get_total_contributors(df.github_link.iloc[i])
        df.at[i, 'more_than_3_contributors'] = pv.has_more_than_n_contributors(df.num_contributors_last_year.iloc[i])
    df.at[i, 'is_in_pypi'] = pv.is_in_pypi(df.name.iloc[i])
    df.at[i, 'is_in_conda'] = pv.is_in_conda(python_anaconda_37, df.name.iloc[i])

# Creating the evaluation criteria. Yes/No if passes all the criteria.
df['evaluation_criteria'] = False

for i in range(len(df)):
    df.at[i, 'evaluation_criteria'] = (df.has_version_control.iloc[i]=='Yes'
          and (False if df.num_commits.iloc[i] == None else df.num_commits.iloc[i]>3)
          and df.more_than_3_contributors.iloc[i]=='Yes'
          and (df.is_in_pypi.iloc[i]=='Yes' or df.is_in_conda.iloc[i]=='Yes')
          and df.licenses.iloc[i] != None
          and df.email.iloc[i] != None)

# Adding dependencies of the packages
df['number_of_dependencies'] = None		# Number of dependencies of the package
df['dependencies'] = None				# Dependencies and versions of the package

pbar = tqdm(range(len(df)))
for i in pbar:
    pbar.set_description('{}'.format(df.name.iloc[i]))
    num_deps, deps = pv.get_dependencies(df.name.iloc[i], df.version.iloc[i])
    df.at[i, 'number_of_dependencies'] = num_deps
    df.at[i, 'dependencies'] = deps
    time.sleep(1)

# Exporting the results to an Excel file
df.to_excel('python_packages_v1.xlsx')



# Or it can be evaluated one by one, uncommenting the following lines and calling pv.evaluate_package('some_package_name')
"""
example_package_name = 'pandas'
result = pv.evaluate_package(example_package_name)
print('{}'.format(result['evaluation_criteria']))
print(result)
"""