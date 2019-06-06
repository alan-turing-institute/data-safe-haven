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

GITHUB_API_TOKEN = 'c27a967497ab98a55ac5aa4e8d66bc333bde70ff'
LIBRARIES_IO_API_KEY = '00cb33c5a2174dd7bbdcffb365d3a8de'

def get_soup(url):
    response = urllib.request.urlopen(url).read()
    soup = BeautifulSoup(response, 'html.parser')
    return soup

def check_repository(url):
    if 'github.com/' in url or 'gitlab.com' in url or 'bitbucket.org' in url:
        return 'yes'
    else:
        return 'no'

def has_version_control(name, link):
    if link:
        if 'github.com/' in link or 'gitlab.com' in link or 'bitbucket.org/' in link:
            return 'Yes'
        else:
            return 'No'
    return 'No'

def get_github_url(name, link):
    if 'github.com/' in link:
        return link
    elif 'readthedocs.org/' in link:
        return get_github(link)
    else:
        return None

def get_github(url):
    soup = get_soup(url)
    section = soup.find_all(class_ = 'fa fa-github')
    try:
        github_url = 'https://github.com/' + section[0].get('href').split('/')[3] + '/' + section[0].get('href').split('/')[4]
        return github_url
    except:
        return None
    
def get_initial_python_packages(python_packages_url):
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
    return 'https://pypi.org/project/{}'.format(name)

def get_libraries_io_project_info(name):
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
    project = get_libraries_io_project_info(name)
    if project:
        return project['name'], project['repository_url'], project['normalized_licenses']
    else:
        return None, None, None
    
def get_project_dependencies(name):
    """
    https://libraries.io/api/:platform/:name/dependents?api_key=00cb33c5a2174dd7bbdcffb365d3a8de
    """
    response = requests.get('https://libraries.io/api/Pypi/{name}/dependents?api_key={api_key}'.format(name=name, api_key=LIBRARIES_IO_API_KEY))
    return response.json()
    
def get_contributors_from_libraries_io(name):
    response = requests.get('https://libraries.io/api/pypi/{name}/contributors?api_key={api_key}'.format(name=name, api_key=LIBRARIES_IO_API_KEY))
    if response.status_code == 200:
        return response.json()
    else:
        return None

def get_contributor_email(name):
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
    url_parts = [x for x in url.split('/') if len(x) > 1]
    name = url_parts[2]+'/'+url_parts[3]
    return name

def get_num_commits(url):
    """
    Last year of commit activity.
    https://developer.github.com/v3/repos/statistics/#get-the-last-year-of-commit-activity-data
    """
    try:
        commits = requests.get('https://api.github.com/repos/{repo_name}/stats/commit_activity'.format(repo_name=get_repo_name(url)), auth=('darenasc', GITHUB_API_TOKEN)).json()
        num_commits = 0
        for commit in commits:
            num_commits+=commit['total']
        return num_commits
    except:
        return None

def get_total_contributors(url):
    repo_name = get_repo_name(url)
    contributors = requests.get('https://api.github.com/repos/{repo_name}/stats/contributors'.format(repo_name=repo_name), auth=('darenasc', GITHUB_API_TOKEN)).json()
    return len(contributors)

def get_commits(url, n_days=365):
    repo_name = get_repo_name(url)
    date_n_days_ago = date.today() - timedelta(days = n_days)
    commits = requests.get('https://api.github.com/repos/{}/commits?since={}'.format(repo_name, date_n_days_ago), auth=('darenasc', GITHUB_API_TOKEN)).json()
    return commits

def get_contributors(url, n_days=365):
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
    if num_contributors > n:
        return 'Yes'
    else:
        return 'No'
    
def is_in_pypi(name):
    pypi_url = get_pypi_url(name)
    response = requests.get(pypi_url)
    if response.status_code == 200:
        return 'Yes'
    elif response.status_code == 404:
        return 'No'
    else:
        return 'No'
    
def get_conda_packages(url):
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
    if package_name in python_list:
        return 'Yes'
    else:
        return 'No'

def get_dependencies(name):
    dep = get_project_dependencies(name)
    if 'error' in dep:
        return None, None
    else:
        dependencies = []
        for d in dep:
            dependencies.append((d['name'], d['repository_url'] or d['homepage']))
        return len(dep), dependencies

df = get_initial_python_packages('https://docs.anaconda.com/anaconda/packages/py3.7_linux-64/')

df['github_link'] = None
df['has_version_control'] = None
df['pypi_url'] = None

pbar = tqdm(range(len(df)))
for i in pbar:
    pbar.set_description('{}: {}'.format('Python 3.7', df.name.iloc[i]))
    df.at[i, 'github_link'] = get_github_url(df.name.iloc[i], df.link.iloc[i])
    df.at[i, 'has_version_control'] = has_version_control(df.name.iloc[i], df.github_link.iloc[i])
    df.at[i, 'pypi_url'] = get_pypi_url(df.name.iloc[i])

# Information from libraries.io
df['login'] = None
df['email'] = None
df['cont_rank'] = None
df['licenses'] = None

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

# Information from GitHub
df['num_commits'] = None
df['num_contributors_last_year'] = None
df['total_contributors'] = None
df['more_than_3_contributors'] = None
df['is_in_pypi'] = None
df['is_in_conda'] = None

python_anaconda_37 = get_conda_packages('https://docs.anaconda.com/anaconda/packages/py3.7_linux-64/')

pbar = tqdm(range(20, len(df)))
for i in pbar:
    pbar.set_description('{}'.format(df.name.iloc[i]))
    if df.github_link.iloc[i]:
        df.at[i, 'num_commits'] = get_num_commits(df.github_link.iloc[i])
        df.at[i, 'num_contributors_last_year'] = get_contributors(df.github_link.iloc[i], 365)
        df.at[i, 'total_contributors'] = get_total_contributors(df.github_link.iloc[i])
        df.at[i, 'more_than_3_contributors'] = has_more_than_n_contributors(df.num_contributors_last_year.iloc[i])
    df.at[i, 'is_in_pypi'] = is_in_pypi(df.name.iloc[i])
    df.at[i, 'is_in_conda'] = is_in_conda(python_anaconda_37, df.name.iloc[i])

df['evaluation_criteria'] = False

for i in range(len(df)):
    df.at[i, 'evaluation_criteria'] = (df.has_version_control.iloc[i]=='Yes'
          and (False if df.num_commits.iloc[i] == None else df.num_commits.iloc[i]>3)
          and df.more_than_3_contributors.iloc[i]=='Yes'
          and (df.is_in_pypi.iloc[i]=='Yes' or df.is_in_conda.iloc[i]=='Yes')
          and df.licenses.iloc[i] != None
          and df.email.iloc[i] != None)

# Adding dependencies of the packages
df['number_of_dependencies'] = None
df['dependencies'] = None

pbar = tqdm(range(len(df)))
for i in pbar:
    pbar.set_description('{}'.format(df.name.iloc[i]))
    num_deps, deps = get_dependencies(df.name.iloc[i])
    df.at[i, 'number_of_dependencies'] = num_deps
    df.at[i, 'dependencies'] = deps
    time.sleep(1)

df.to_excel('python_packages.xlsx')