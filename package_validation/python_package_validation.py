from bs4 import BeautifulSoup
import urllib.request
import pandas as pd
from tqdm import tqdm
from github import Github
import json
from datetime import timedelta
from datetime import date
from datetime import datetime
import time
from math import isnan
import requests

# API tokens for github.com and for libraries.io
LIBRARIES_IO_API_KEY = ''
GITHUB_API_TOKEN = ''
GITHUB_USER = ''

"""
1) Have version control on public GitHub or Gitlab
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
"""

def get_api_keys(path='.', filename='secrets/api_keys.json'):
	"""
	Loads a JSON file with the following structure to get the API keys.
	{
		"libraries.io" : "<YOUR_API_KEY>",
		"github" : {
			"login" : "<YOUR_LOGIN>",
			"token" : "<YOUR_API_TOKEN>"
		}
	}
	"""
	global LIBRARIES_IO_API_KEY
	global GITHUB_API_TOKEN
	global GITHUB_USER
	with open(path + '/' + filename) as json_file:
		keys = json.load(json_file)
		LIBRARIES_IO_API_KEY = keys['libraries.io']
		GITHUB_API_TOKEN = keys['github']['token']
		GITHUB_USER = keys['github']['login']
		print('API keys imported OK...')
	return

# Call to load the API keys
get_api_keys()

def get_soup(url):
    """
    Returns a bs4 object with the HTML source code of the web page in the url.
    """
    response = urllib.request.urlopen(url).read()
    soup = BeautifulSoup(response, 'html.parser')
    return soup

def has_version_control(name, link):
    """
    1) Has version control on public GitHub or Gitlab (or Bitbucket)
    Measure: Yes/No
    """
    if link:
        if 'github.com/' in link or 'gitlab.com' in link or 'bitbucket.org/' in link:
            return 'Yes'
        else:
            return 'No'
    return 'No'

def get_github_url(name, link):
    """
    Given a url returns a github url if the input url is github or readthedocs. 
    """
    def get_github_from_readthedocs(url):
        soup = get_soup(url)
        section = soup.find_all(class_ = 'fa fa-github')
        try:
            github_url = 'https://github.com/' + section[0].get('href').split('/')[3] + '/' + section[0].get('href').split('/')[4]
            return github_url
        except:
            return None

    if 'github.com/' in link:
        return link
    elif 'readthedocs.org/' in link:
        return get_github_from_readthedocs(link)
    else:
        return None

def get_initial_python_packages(python_packages_url):
    """
    Given an anaconda url with a list of packages, it will find the names, version, url, and a boolean if the package comes in 
    the default installation. Gets all the information from the anaconda webpage.
    Returns a dataframe with this information.
    """
    soup = get_soup(python_packages_url)
    
    table = soup.find('table')
    rows = table.find_all('tr')
    packages = []
    
    for row in rows:
        cols = row.find_all('td')
        if len(cols) == 4:
            name = cols[0].get_text()
            version = cols[1].get_text()
            link = cols[0].find('a').get('href')
            if len(cols[3]) == 1:
                in_installation = True
            else: 
                in_installation = False

            packages.append((name, version, link, in_installation))

    columns = ['name', 'version', 'link', 'in_installation']
    df = pd.DataFrame(packages, columns=columns)
    return df

def get_pypi_url(name):
    """
    Returns a PYPI url. It might or not be valid.
    """
    return 'https://pypi.org/project/{}'.format(name)

def get_libraries_io_project_info(name):
    """
    Using the package name, it returns a JSON with information of the project/library from libraries.io 
    The libraries.io API has a limit of 60 calls per minute.
    """
    response = requests.get('https://libraries.io/api/Pypi/{name}?api_key={api_key}'.format(name=name, api_key=LIBRARIES_IO_API_KEY))
    if response.status_code == 200:
        return response.json()
    elif response.status_code == 404:
        return None
    elif response.status_code == 429:
        time.sleep(10)
    else:
        return None

def get_project_info(name):
    """
    Returns the name, url of the repository, and licenses of a package from libraries.io
    """
    project = get_libraries_io_project_info(name)
    if project:
        licenses = ','.join(project['normalized_licenses'])
        return project['name'], project['repository_url'], licenses #project['normalized_licenses']
    else:
        return None, None, None
    
def get_project_dependencies(name, version):
    """
    Returns a JSON with 
    https://libraries.io/api/:platform/:name/:version/dependencies?api_key=00cb33c5a2174dd7bbdcffb365d3a8de
    """
    response = requests.get('https://libraries.io/api/Pypi/{name}/{version}/dependencies?api_key={api_key}'.format(name=name, version=version, api_key=LIBRARIES_IO_API_KEY))
    return response.json()
    
def get_contributors_from_libraries_io(name):
	"""
	Returns a list of contributors of a package from libraries.io
	"""
	response = requests.get('https://libraries.io/api/pypi/{name}/contributors?api_key={api_key}'.format(name=name, api_key=LIBRARIES_IO_API_KEY))
	if response.status_code == 200:
		return response.json()
	else:
		return None

def get_contributor_email(name):
	"""
	Returns the login, email, and rank of the first contributor with email from the list of contributors. 
	The first contributor in the list is the main contributor.
	"""
	contributors = get_contributors_from_libraries_io(name)
	if contributors:
		i = 0
		for contributor in contributors:
			i+=1
			if contributor['email']:
				return contributor['login'], contributor['email'], i
	return None, None, None

def get_repo_name(url):
    """
    Given a github url returns the name of the repository
    """
    if 'github.com/' in url:
        url_parts = [x for x in url.split('/') if len(x) > 1]
        name = url_parts[2]+'/'+url_parts[3]
        return name
    else:
        return None

def get_num_commits(url):
    """
    Last year of commit activity.
    https://developer.github.com/v3/repos/statistics/#get-the-last-year-of-commit-activity-data
    """
    try:
        commits = requests.get('https://api.github.com/repos/{repo_name}/stats/commit_activity'.format(repo_name=get_repo_name(url)), auth=(GITHUB_USER, GITHUB_API_TOKEN)).json()
        num_commits = 0
        for commit in commits:
            num_commits+=commit['total']
        return num_commits
    except:
        return None

def get_total_contributors(url):
    """
    Returns the number of contributors of the package using the github API.
    """
    repo_name = get_repo_name(url)
    contributors = requests.get('https://api.github.com/repos/{repo_name}/stats/contributors'.format(repo_name=repo_name), auth=(GITHUB_USER, GITHUB_API_TOKEN)).json()
    return len(contributors)

def get_commits(url, n_days=365):
    """
    Returns the commits of the last n_days. By default is in the last 365 days.
    """
    repo_name = get_repo_name(url)
    date_n_days_ago = date.today() - timedelta(days = n_days)
    commits = requests.get('https://api.github.com/repos/{}/commits?since={}'.format(repo_name, date_n_days_ago), auth=(GITHUB_USER, GITHUB_API_TOKEN)).json()
    return commits

def get_contributors(url, n_days=365):
    """
    Returns the number of distinct contributors in the last n_days. By default is in the last 365 days.
    """
    commits = get_commits(url, n_days)
    committers = []
    for d in commits:
        try:
            if d['author']['login'] not in committers:
                committers.append(d['author']['login'])
            if d['committer']['login'] not in committers:
                committers.append(d['committer']['login'])
        except:
            pass
    return len(committers)

def has_more_than_n_contributors(num_contributors, n=3):
    """
    Criteria number 3. Yes/No if has or not more than 3 contributors. 
    3) Have commits by at least three different contributors
    Measure: Number of distinct committers in past month, 3 months, 6 months, 12 months, 24 months, 36 months
    """
    if num_contributors > n:
        return 'Yes'
    else:
        return 'No'
    
def is_in_pypi(name):
    """
    Yes/No if it has a PYPI page. 
    """
    pypi_url = get_pypi_url(name)
    response = requests.get(pypi_url)
    if response.status_code == 200:
        return 'Yes'
    elif response.status_code == 404:
        return 'No'
    else:
        return 'No'
    
def get_conda_packages(url):
    """
    Returns a list with all the package names in the given anaconda url.
    """
    soup = get_soup(url)
    table = soup.find('table')
    rows = table.find_all('tr')
    packages = []
    for row in rows:
        cols = row.find_all('td')
        if len(cols) == 4:
            if cols[0].get_text() not in packages:
                packages.append(cols[0].get_text())
    return packages

def is_in_conda(python_list, package_name):
    """
    Yes/No if the package name can be found in the list of package names.
    """
    if package_name in python_list:
        return 'Yes'
    else:
        return 'No'

def get_dependencies(name, version):
    """
    Returns the number and url of the repository of the dependencies.
    """
    dep = get_project_dependencies(name, version)
    if 'error' in dep:
        return None, None
    else:
        dependencies = []
        for d in dep['dependencies']:
            dependencies.append((d['name']+' '+d['requirements']))
        return len(dependencies), dependencies

def evaluate_packages_from_anaconda(python_version):
    anaconda_url = 'https://docs.anaconda.com/anaconda/packages/py{python_version}_linux-64/'.format(python_version=python_version)
    df = get_initial_python_packages(anaconda_url)

    # Creates new columns in the dataframe
    df['github_link'] = None            # url of the github repository
    df['has_version_control'] = None    # Yes/No if has a public repository in github, gitlab, or bitbucket
    df['pypi_url'] = None               # generated pypi url, this url needs to be tested if exists or not.

    # 
    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{}'.format(df.name.iloc[i]))
        df.at[i, 'github_link'] = get_github_url(df.name.iloc[i], df.link.iloc[i])
        df.at[i, 'has_version_control'] = has_version_control(df.name.iloc[i], df.github_link.iloc[i])
        df.at[i, 'pypi_url'] = get_pypi_url(df.name.iloc[i])

    # Information from libraries.io
    df['login'] = None          # login of a main contributor
    df['email'] = None          # email of a main contributor
    df['cont_rank'] = None      # ranking of the contributor, starts searching from the lead contributor until finds an email and its rank
    df['licenses'] = None       # license of the package

    # This takes awhile because libraries.io has a rate limit of 60 calls per minute
    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{}'.format(df.name.iloc[i]))
        login, email, cont_rank = get_contributor_email(df.name.iloc[i])
        _, repo_url, licenses = get_project_info(df.name.iloc[i])
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
    python_anaconda_37 = get_conda_packages(anaconda_url)

    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{}'.format(df.name.iloc[i]))
        if df.github_link.iloc[i]:
            df.at[i, 'num_commits'] = get_num_commits(df.github_link.iloc[i])
            df.at[i, 'num_contributors_last_year'] = get_contributors(df.github_link.iloc[i], 365)
            df.at[i, 'total_contributors'] = get_total_contributors(df.github_link.iloc[i])
            df.at[i, 'more_than_3_contributors'] = has_more_than_n_contributors(df.num_contributors_last_year.iloc[i])
        df.at[i, 'is_in_pypi'] = is_in_pypi(df.name.iloc[i])
        df.at[i, 'is_in_conda'] = is_in_conda(python_anaconda_37, df.name.iloc[i])

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
        num_deps, deps = get_dependencies(df.name.iloc[i], df.version.iloc[i])
        df.at[i, 'number_of_dependencies'] = num_deps
        df.at[i, 'dependencies'] = deps
        time.sleep(1)

    return df

def evaluate_package(name, python_version = '3.7'):
    """
    Returns a dataframe with 1 row evaluating the package.
    It filters the package from the anaconda list of packages, the rest is the same process as processing a list of packages.
    """
    anaconda_url = 'https://docs.anaconda.com/anaconda/packages/py{python_version}_linux-64/'.format(python_version=python_version)
    df_base = get_initial_python_packages(anaconda_url)
    df = df_base[df_base['name']==name].copy().reset_index()
    
    # Creates new columns in the dataframe
    df['github_link'] = None            # url of the github repository
    df['has_version_control'] = None    # Yes/No if has a public repository in github, gitlab, or bitbucket
    df['pypi_url'] = None               # generated pypi url, this url needs to be tested if exists or not.

    # 
    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{}'.format(df.name.iloc[i]))
        df.at[i, 'github_link'] = get_github_url(df.name.iloc[i], df.link.iloc[i])
        df.at[i, 'has_version_control'] = has_version_control(df.name.iloc[i], df.github_link.iloc[i])
        df.at[i, 'pypi_url'] = get_pypi_url(df.name.iloc[i])

    # Information from libraries.io
    df['login'] = None          # login of a main contributor
    df['email'] = None          # email of a main contributor
    df['cont_rank'] = None      # ranking of the contributor, starts searching from the lead contributor until finds an email and its rank
    df['licenses'] = None       # license of the package

    # This takes awhile because libraries.io has a rate limit of 60 calls per minute
    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{}'.format(df.name.iloc[i]))
        login, email, cont_rank = get_contributor_email(df.name.iloc[i])
        _, repo_url, licenses = get_project_info(df.name.iloc[i])
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
    python_anaconda_37 = get_conda_packages(anaconda_url)

    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{}'.format(df.name.iloc[i]))
        if df.github_link.iloc[i]:
            df.at[i, 'num_commits'] = get_num_commits(df.github_link.iloc[i])
            df.at[i, 'num_contributors_last_year'] = get_contributors(df.github_link.iloc[i], 365)
            df.at[i, 'total_contributors'] = get_total_contributors(df.github_link.iloc[i])
            df.at[i, 'more_than_3_contributors'] = has_more_than_n_contributors(df.num_contributors_last_year.iloc[i])
        df.at[i, 'is_in_pypi'] = is_in_pypi(df.name.iloc[i])
        df.at[i, 'is_in_conda'] = is_in_conda(python_anaconda_37, df.name.iloc[i])

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
        num_deps, deps = get_dependencies(df.name.iloc[i], df.version.iloc[i])
        df.at[i, 'number_of_dependencies'] = num_deps
        df.at[i, 'dependencies'] = deps
        time.sleep(1)
    return df