from bs4 import BeautifulSoup
import urllib.request
import pandas as pd
#from tqdm import tqdm_notebook as tqdm
from tqdm import tqdm
from github import Github
import json
from datetime import timedelta
from datetime import date
from datetime import datetime
import time

"""
1. Have version control on public GitHub or Gitlab
Measure: Yes/No
2. Have commits within the last year
Measure: Number of commits per month for the past 36 months
3. Have commits by at least three different contributors
Measure: Number of distinct committers in past month, 3 months, 6 months, 12 months, 24 months, 36 months
4. Be on a recognised package repository (PyPI, Conda, CRAN, Bioconductor.)
Measure: Name of package repository plus release date and version number of all releases if available
5. Have LICENSE and README files (always true if on repository?)
Measure: Yes/No (plus name of licence if available/inferable, length of README in words and possibly content of LICENSE and README files - Note: Look for any files names LICENSE/LICENCE or README, regardless of suffix (or lack of)
6. The lead contributor should have an email address (always true if on repository?)
Measure: Yes/No plus capture of actual email address
"""

g = Github("<USER_NAME>", "<PASSWORD>")


R_PACKAGES = ['abind', 'ada', 'akima', 'ape', 'assertthat', 'AUC', 'backports', 'BBmisc', 'bedr', 'BiocManager', 'bitops', 'boot', 'brms', 'car', 'care', 'caret', 'checkmate', 'chron', 'class', 'cluster', 'coda', 'codetools', 'colorRamps', 'colorspace', 'COMBAT', 'compiler', 'corrgram', 'corrplot', 'cowplot', 'CoxBoost', 'crayon', 'CVST', 'cvTools', 'data.table', 'datasets', 'dbarts', 'DBI', 'deepnet', 'devtools', 'DiagrammeR', 'dichromat', 'digest', 'directlabels', 'dirichletprocess', 'dlm', 'doBy', 'doParallel', 'dplyr', 'DPpackage', 'DT', 'dtw', 'dummies', 'dygraphs', 'e1071', 'emulator', 'evaluate', 'factoextra', 'FactoMineR', 'fda', 'fields', 'fmsb', 'foreach', 'forecast', 'foreign', 'Formula', 'gamlss.dist', 'gamlss.mx', 'gamlss.nl', 'gamlss.spatial', 'gamlss', 'gbm', 'gdata', 'GGally', 'ggforce', 'ggmap', 'ggplot2', 'ggridges', 'ggvis', 'glmnet', 'googleVis', 'gplots', 'graphics', 'grDevices', 'grid', 'gridExtra', 'gtable', 'h2o', 'highr', 'Hmisc', 'htmltools', 'httpuv', 'httr', 'igraph', 'irace', 'IRdisplay', 'iterators', 'jsonlite', 'kernlab', 'KernSmooth', 'kknn', 'kml', 'kmlShape', 'knitr', 'labeling', 'lattice', 'lazyeval', 'LDAvis', 'leaflet', 'lme4', 'loo', 'lubridate', 'magrittr', 'maps', 'maptools', 'markdown', 'MASS', 'Matrix', 'matrixStats', 'mboost', 'mclust', 'MCMCpack', 'McSpatial', 'methods', 'mgcv', 'mime', 'mlbench', 'mlr', 'multcomp', 'munsell', 'ndtv', 'network', 'networkD3', 'neuralnet', 'nlme', 'nnet', 'parallel', 'parallelMap', 'ParamHelpers', 'party', 'pbdZMQ', 'pls', 'plyr', 'polycor', 'pomp', 'PReMiuM', 'pscl', 'psych', 'purrr', 'pvclust', 'quanteda', 'quantmod', 'R6', 'randomForest', 'RColorBrewer', 'RCurl', 'readr', 'readtext', 'readxl', 'repr', 'reshape', 'reshape2', 'revealjs', 'rgdal', 'rgeos', 'rgl', 'rJava', 'rmarkdown', 'RMySQL', 'ROCR', 'roxygen2', 'rpart', 'RPostgreSQL', 'rPython', 'RSQLite', 'rstan', 'runjags', 'RWeka', 'Scale', 'scales', 'shiny', 'slam', 'sna', 'SnowballC', 'sourcetools', 'sp', 'spacyr', 'spatial', 'splines', 'sqldf', 'stargazer', 'stats', 'stats4', 'stm', 'stringi', 'stringr', 'surveillance', 'survival', 'synthpop', 'tcltk2', 'testthat', 'text2vec', 'tgp', 'threejs', 'tibble', 'tidyr', 'tidyr', 'tidytext', 'tidyverse', 'tmap', 'tools', 'topicmodels', 'traj', 'tsne', 'urca', 'utils', 'uuid', 'varbvs', 'vars', 'vcd', 'vioplot', 'viridis', 'visNetwork', 'wordcloud', 'xgboost', 'XLConnect', 'xlsx', 'XML', 'xtable', 'xts', 'yaml', 'zoo', 'apeglm', 'ballgown', 'Biobase', 'ChemmineR', 'clusterProfiler', 'ComplexHeatmap', 'ConsensusClusterPlus', 'cummeRbund', 'dada2', 'DECIPHER', 'DESeq2', 'destiny', 'DirichletMultinomial', 'DMRcate', 'EBSeq', 'edgeR', 'fastseg', 'FlowSOM', 'flowUtils', 'ggtree', 'GOSemSim', 'GOstats', 'graph', 'graphite', 'GSEABase', 'Gviz', 'interactiveDisplayBase', 'KEGGgraph', 'limma', 'made4', 'maftools', 'metagenomeSeq', 'minet', 'MLInterfaces', 'monocle', 'pathview', 'pcaMethods', 'phyloseq', 'RankProd', 'RBGL', 'RDAVIDWebService', 'Rgraphviz', 'safe', 'SC3', 'scater', 'scde', 'scran', 'SNPRelate', 'SPIA', 'supraHex', 'sva', 'TCGAbiolinks', 'TimeSeriesExperiment', 'topGO', 'treeio']
PYTHON_PACKAGES = ['ipykernel', 'jupyter_client', 'jupyterlab', 'keras', 'notebook', 'pystan', 'pytorch', 'r-irkernel', 'tensorflow', 'torchvision']


"""
CRAN 			https://cran.r-project.org/web/packages/available_packages_by_name.html
Bioconductor 	https://www.bioconductor.org/checkResults/3.10/bioc-LATEST/
				https://www.bioconductor.org/checkResults/devel/bioc-LATEST/
PyPi			https://pypi.org
Anaconda		https://docs.anaconda.com/anaconda/packages/py2.7_linux-64/
				https://docs.anaconda.com/anaconda/packages/py3.6_linux-64/
				https://docs.anaconda.com/anaconda/packages/py3.7_linux-64/
"""

def get_soup(url):
    response = urllib.request.urlopen(url).read()
    soup = BeautifulSoup(response, 'html.parser')
    return soup

def check_repository(url):
    if 'github.com/' in url or 'gitlab.com' in url or 'bitbucket.org' in url:
        return 'yes'
    else:
        return 'no'
    
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

def get_repo_name(url):
    """
    Given a github url returns the name of the repository
    """
    url_parts = [x for x in url.split('/') if len(x) > 1]
    name = url_parts[2]+'/'+url_parts[3]
    return name

def get_repo(g, github_url):
    """
    Returns a repository object with information from GitHub
    """
    name = get_repo_name(github_url)
    try:
        repo = g.get_repo(name)
        return repo
    except:
        return None

def get_number_commits(repo, n_days=365):
    date_n_days_ago = date.today() - timedelta(days = n_days)
    commits = repo.get_commits(since=datetime(date_n_days_ago.year, date_n_days_ago.month, date_n_days_ago.day))
    return commits.totalCount

def get_number_contributors(repo, n_days=365):
    date_n_days_ago = date.today() - timedelta(days = n_days)
    commits = repo.get_commits(since=datetime(date_n_days_ago.year, date_n_days_ago.month, date_n_days_ago.day))
    
    committers = []
    for d in commits:
        if d.committer:
            try:
                if d.author.login not in committers:
                    committers.append(d.author.login)
                if d.committer.login not in committers:
                    committers.append(d.committer.login)
            except:
                pass
    
    return len(committers)

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

def has_more_than_n_contributors(num_contributors, n=3):
    if num_contributors > n:
        return 'Yes'
    else:
        return 'No'
    
def is_in_pypi(name):
    """
    Searches only by exact name.
    """
    url = 'https://pypi.org/search/?q={name}'.format(name=name)
    soup = get_soup(url)
    
    items = soup.find_all(class_ = 'package-snippet__title')
    for item in items:
        if name in item.find(class_ = 'package-snippet__name'):
            return 'Yes'
        else:
            return 'No'

def is_in_conda(python_list, package_name):
    if package_name in python_list:
        return 'Yes'
    else:
        return 'No'
    pass

def get_license(repo):
    try:
        license = repo.get_license()
        name = license.license.name
        url = license.html_url
        return name, url
    except:
        return None, None

def get_lead_contributor(repo):
    return repo.get_stats_contributors()[-1].author.login

def get_user_email(login):
    user = g.get_user(login)
    return user.email

def evaluate_python_packages(url):
    df = get_initial_python_packages(url)
    if 'py3.7' in url:
        python_version = 'Python 3.7'
    elif 'py3.6' in url:
        python_version = 'Python 3.6'
    elif 'py2.7' in url:
        python_version = 'Python 2.7'
    
    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{}: {}'.format(python_version, df.name.iloc[i]))
        df.at[i, 'github_link'] = get_github_url(df.name.iloc[i], df.link.iloc[i])
        df.at[i, 'has_version_control'] = has_version_control(df.name.iloc[i], df.github_link.iloc[i])

    df['num_commits'] = None
    df['num_contributors'] = None
    df['more_than_3_contributors'] = None
    df['license'] = None
    df['url_license'] = None
    df['has_license'] = None
    df['lead_contributor'] = None
    df['lead_contributor_email'] = None
    df['is_in_pypi'] = None
    df['is_in_conda'] = None
    df['has_lead_contributor_email'] = None
    
    python_conda = get_conda_packages(url)

    slow_responses = ['CanopyTax/asyncpgsa'
                  , 'PiDelport/backports.os'
                  , 'PiDelport/backports.weakref'
                  , 'bokeh/bkcharts'
                  , 'Blosc/c-blosc'
                  , 'biolab/bottlechest'
                  , 'conda-forge/ca-certificates-feedstock'
                  , 'pyviz/colorcet'
                  , 'conda-tools/conda-build-all'
                  , 'conda/conda-verify'
                  , 'twisted/constantly'
                  , 'dask/dask-glm'
                  , 'dask/dask-ml'
                  , 'dropbox/dropbox-sdk-python'
                  , 'Toblerity/Fiona'
                  , 'fribidi/fribidi'
                  , 'dask/hdfs3'
                  , 'cloudera/hs2client'
                  , 'python-hyper/hyperlink'
                 ]
    
    repos = []
    pbar = tqdm(range(len(df)))
    for i in pbar:
        pbar.set_description('{} {}'.format(python_version, df.name.iloc[i]))
        if df.github_link.iloc[i]:
            repo = get_repo(g, df.github_link.iloc[i])
            if repo:
                if df.num_commits.iloc[i] == None:
                    pbar.set_description('{} {} number of commits'.format(python_version, df.name.iloc[i]))
                    df.at[i, 'num_commits'] = get_number_commits(repo)
                if df.num_contributors.iloc[i] == None:
                    pbar.set_description('{} {} number of contributors'.format(python_version, df.name.iloc[i]))
                    df.at[i, 'num_contributors'] = get_number_contributors(repo)
                if df.more_than_3_contributors.iloc[i] == None:
                    pbar.set_description('{} {} more than 3 contributors?'.format(python_version, df.name.iloc[i]))
                    df.at[i, 'more_than_3_contributors'] = has_more_than_n_contributors(df.num_contributors.iloc[i], n=3)
                if df.license.iloc[i] == None:
                    pbar.set_description('{} {} license'.format(python_version, df.name.iloc[i]))
                    df.at[i, 'license'], df.at[i, 'url_license'] = get_license(repo)
                if df.at[i, 'license']:
                    df.at[i, 'has_license'] = 'Yes'
                else:
                    df.at[i, 'has_license'] = 'No'
                """if repo.full_name not in slow_responses and df.lead_contributor.iloc[i] == None:
                    df.at[i, 'lead_contributor'] = get_lead_contributor(repo)
                    df.at[i, 'lead_contributor_email'] = get_user_email(df.at[i, 'lead_contributor'])
                    if df.lead_contributor_email.iloc[i]:
                        df.at[i, 'has_lead_contributor_email'] = 'Yes'
                    else:
                        df.at[i, 'has_lead_contributor_email'] = 'No'"""
                repos.append(repo)
        df.at[i, 'is_in_pypi'] = is_in_pypi(df.name.iloc[i])
        df.at[i, 'is_in_conda'] = is_in_conda(python_conda, df.name.iloc[i])
    
    df.to_excel('python_libraries_v1.xlsx', sheet_name=python_version)
    df.to_csv(python_version+'.csv')
    return 

evaluate_python_packages('https://docs.anaconda.com/anaconda/packages/py3.7_linux-64/')
evaluate_python_packages('https://docs.anaconda.com/anaconda/packages/py3.6_linux-64/')
evaluate_python_packages('https://docs.anaconda.com/anaconda/packages/py2.7_linux-64/')
