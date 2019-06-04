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
from math import isnan

R_PACKAGES = ['abind', 'ada', 'akima', 'ape', 'assertthat', 'AUC', 'backports', 'BBmisc', 'bedr', 'BiocManager', 'bitops', 'boot', 'brms', 'car', 'care', 'caret', 'checkmate', 'chron', 'class', 'cluster', 'coda', 'codetools', 'colorRamps', 'colorspace', 'COMBAT', 'compiler', 'corrgram', 'corrplot', 'cowplot', 'CoxBoost', 'crayon', 'CVST', 'cvTools', 'data.table', 'datasets', 'dbarts', 'DBI', 'deepnet', 'devtools', 'DiagrammeR', 'dichromat', 'digest', 'directlabels', 'dirichletprocess', 'dlm', 'doBy', 'doParallel', 'dplyr', 'DPpackage', 'DT', 'dtw', 'dummies', 'dygraphs', 'e1071', 'emulator', 'evaluate', 'factoextra', 'FactoMineR', 'fda', 'fields', 'fmsb', 'foreach', 'forecast', 'foreign', 'Formula', 'gamlss.dist', 'gamlss.mx', 'gamlss.nl', 'gamlss.spatial', 'gamlss', 'gbm', 'gdata', 'GGally', 'ggforce', 'ggmap', 'ggplot2', 'ggridges', 'ggvis', 'glmnet', 'googleVis', 'gplots', 'graphics', 'grDevices', 'grid', 'gridExtra', 'gtable', 'h2o', 'highr', 'Hmisc', 'htmltools', 'httpuv', 'httr', 'igraph', 'irace', 'IRdisplay', 'iterators', 'jsonlite', 'kernlab', 'KernSmooth', 'kknn', 'kml', 'kmlShape', 'knitr', 'labeling', 'lattice', 'lazyeval', 'LDAvis', 'leaflet', 'lme4', 'loo', 'lubridate', 'magrittr', 'maps', 'maptools', 'markdown', 'MASS', 'Matrix', 'matrixStats', 'mboost', 'mclust', 'MCMCpack', 'McSpatial', 'methods', 'mgcv', 'mime', 'mlbench', 'mlr', 'multcomp', 'munsell', 'ndtv', 'network', 'networkD3', 'neuralnet', 'nlme', 'nnet', 'parallel', 'parallelMap', 'ParamHelpers', 'party', 'pbdZMQ', 'pls', 'plyr', 'polycor', 'pomp', 'PReMiuM', 'pscl', 'psych', 'purrr', 'pvclust', 'quanteda', 'quantmod', 'R6', 'randomForest', 'RColorBrewer', 'RCurl', 'readr', 'readtext', 'readxl', 'repr', 'reshape', 'reshape2', 'revealjs', 'rgdal', 'rgeos', 'rgl', 'rJava', 'rmarkdown', 'RMySQL', 'ROCR', 'roxygen2', 'rpart', 'RPostgreSQL', 'rPython', 'RSQLite', 'rstan', 'runjags', 'RWeka', 'Scale', 'scales', 'shiny', 'slam', 'sna', 'SnowballC', 'sourcetools', 'sp', 'spacyr', 'spatial', 'splines', 'sqldf', 'stargazer', 'stats', 'stats4', 'stm', 'stringi', 'stringr', 'surveillance', 'survival', 'synthpop', 'tcltk2', 'testthat', 'text2vec', 'tgp', 'threejs', 'tibble', 'tidyr', 'tidyr', 'tidytext', 'tidyverse', 'tmap', 'tools', 'topicmodels', 'traj', 'tsne', 'urca', 'utils', 'uuid', 'varbvs', 'vars', 'vcd', 'vioplot', 'viridis', 'visNetwork', 'wordcloud', 'xgboost', 'XLConnect', 'xlsx', 'XML', 'xtable', 'xts', 'yaml', 'zoo', 'apeglm', 'ballgown', 'Biobase', 'ChemmineR', 'clusterProfiler', 'ComplexHeatmap', 'ConsensusClusterPlus', 'cummeRbund', 'dada2', 'DECIPHER', 'DESeq2', 'destiny', 'DirichletMultinomial', 'DMRcate', 'EBSeq', 'edgeR', 'fastseg', 'FlowSOM', 'flowUtils', 'ggtree', 'GOSemSim', 'GOstats', 'graph', 'graphite', 'GSEABase', 'Gviz', 'interactiveDisplayBase', 'KEGGgraph', 'limma', 'made4', 'maftools', 'metagenomeSeq', 'minet', 'MLInterfaces', 'monocle', 'pathview', 'pcaMethods', 'phyloseq', 'RankProd', 'RBGL', 'RDAVIDWebService', 'Rgraphviz', 'safe', 'SC3', 'scater', 'scde', 'scran', 'SNPRelate', 'SPIA', 'supraHex', 'sva', 'TCGAbiolinks', 'TimeSeriesExperiment', 'topGO', 'treeio']

cran_url = 'https://cran.r-project.org/web/packages/available_packages_by_name.html'
base_cran_url = 'https://cran.r-project.org'
bioconductor_url = 'https://www.bioconductor.org/checkResults/3.10/bioc-LATEST/'

def get_soup(url):
    """
    Gets the html code from a url
    """
    response = urllib.request.urlopen(url).read()
    soup = BeautifulSoup(response, 'html.parser')
    return soup

def get_initial_r_package_list(cran_url):
    """
    Returns a list of package names, urls and descriptions from a CRAN url
    """
    soup = get_soup(cran_url)

    table = soup.find('table')
    rows = table.find_all('tr')

    packages = []
    for row in rows:
        cols = row.find_all('td')
        if len(cols) == 2:
            name = cols[0].get_text()
            url_package = base_cran_url + cols[0].find('a').get('href').replace('../..','')
            description = cols[1].get_text()
            if name in R_PACKAGES:
                packages.append((name, url_package, description))
    return packages

def get_cran_package_deatails(url):
    """
    Retuns information about a package scrapped from its webpage.
    version
    depends
    imports
    published
    maintainer
    license
    """
    soup = get_soup(url)
    table = soup.find('table')
    rows = table.find_all('tr')
    
    version = None
    depends = None
    imports = None
    published = None
    maintainer = None
    license = None

    for row in rows:
        cols = row.find_all('td')
        key, value = cols[0].get_text(), cols[1].get_text()
        if 'version' in key.lower():
            version = value
        if 'depends' in key.lower():
            depends = value
        if 'imports' in key.lower():
            imports = value
        if 'published' in key.lower():
            published = value
        elif 'maintainer' in key.lower():
            maintainer = value
        elif 'license' in key.lower():
            license = value
    return (version, depends, imports, published, maintainer, license)

def get_cran_packages(url):
    packages = get_initial_r_package_list(cran_url)
    cran_packages = []
    for package in packages:
        cran_packages.append(package[0])
    return cran_packages

def is_in_bioconductor(package_name, bioconductor_packages):
    if package_name in bioconductor_packages:
        return 'Yes'
    else:
        return 'No'

def is_in_cran(package_name, cran_packages):
    if package_name in cran_packages:
        return 'Yes'
    else:
        return 'No'

def get_bioconductor_packages(url):
    bioconductor_packages = get_initial_bioconductor_packages(url)
    package_list = []
    for package in bioconductor_packages:
        package_list.append(package[0])
    return package_list

def get_initial_bioconductor_packages(url):
    """
    Finds all the links and filters them
    """
    soup = get_soup(url)
    table = soup.find('table', {'class':'mainrep'})
    urls = table.find_all('a')
    
    bioconductor_base_url = 'https://www.bioconductor.org'
    bioconductor_packages = []
    for url in urls:
        if '/packages' in str(url.get('href')):
            bioconductor_packages.append((url.get_text(), bioconductor_base_url+url.get('href')))
    return bioconductor_packages

def get_bioconductor_package_details(url):
    soup = get_soup(url)
    table = soup.find('table', class_ = 'details')

    rows = table.find_all('tr')

    version = None
    depends = None
    imports = None
    published = None
    maintainer = None
    license = None

    for row in rows:
        cols = row.find_all('td')
        key, value = cols[0].get_text(), cols[1].get_text()
        if 'version' in key.lower():
            version = value
        elif 'depends' in key.lower():
            depends = value
        elif 'imports' in key.lower():
            imports = value
        elif 'in bioconductor since' in key.lower():
            published = value
        elif 'license' in key.lower():
            license = value

    paragraphs = soup.find_all('p')
    maintainer = [p.get_text().replace('Maintainer:', '').strip() for p in paragraphs if 'Maintainer:' in p.get_text()][0]

    return version, depends, imports, published, maintainer, license

# Gets a list of package names from CRAN and Bioconductor to be compared with a package name to check if the package is or not in a big package repository.
cran_package_list = get_cran_packages(cran_url)
bioconductor_package_list = get_bioconductor_packages(bioconductor_url)

# Packages from CRAN
packages = get_initial_r_package_list(cran_url)
columns = ['name', 'url', 'description']
r_packages = pd.DataFrame(packages, columns=columns)

r_packages['version'] = None
r_packages['depends'] = None
r_packages['imports'] = None
r_packages['published'] = None
r_packages['maintainer'] = None
r_packages['license'] = None
r_packages['is_in_cran'] = None
r_packages['is_in_bioconductor'] = None

pbar = tqdm(range(len(r_packages)))
for i in pbar:
    pbar.set_description('R {}'.format(r_packages.name.iloc[i]))
    if r_packages.version.iloc[i] == None:
        version, depends, imports, published, maintainer, license = get_cran_package_deatails(r_packages.url.iloc[i])
        r_packages.at[i, 'version'] = version
        r_packages.at[i, 'depends'] = depends
        r_packages.at[i, 'imports'] = imports
        r_packages.at[i, 'published'] = published
        r_packages.at[i, 'maintainer'] = maintainer
        r_packages.at[i, 'license'] = license
        r_packages.at[i, 'is_in_cran'] = is_in_cran(r_packages.name.iloc[i], cran_package_list)
        r_packages.at[i, 'is_in_bioconductor'] = is_in_bioconductor(r_packages.name.iloc[i], bioconductor_package_list)


# Packages from Bioconductor
bioconductor_packages = get_initial_bioconductor_packages(bioconductor_url)
columns = ['name', 'url']
df_bioconductor = pd.DataFrame(bioconductor_packages, columns=columns)

df_bioconductor['version'] = None
df_bioconductor['depends'] = None
df_bioconductor['imports'] = None
df_bioconductor['published'] = None
df_bioconductor['maintainer'] = None
df_bioconductor['license'] = None
df_bioconductor['is_in_cran'] = None
df_bioconductor['is_in_bioconductor'] = None

pbar = tqdm(range(len(df_bioconductor)))
for i in pbar:
    pbar.set_description('Bioconductor {}'.format(df_bioconductor.name.iloc[i]))
    version, depends, imports, published, maintainer, license = get_bioconductor_package_details(df_bioconductor.url.iloc[i])
    df_bioconductor.at[i, 'version'] = version
    df_bioconductor.at[i, 'depends'] = depends
    df_bioconductor.at[i, 'imports'] = imports
    df_bioconductor.at[i, 'published'] = published
    df_bioconductor.at[i, 'maintainer'] = maintainer
    df_bioconductor.at[i, 'license'] = license
    df_bioconductor.at[i, 'is_in_cran'] = is_in_cran(df_bioconductor.name.iloc[i], cran_package_list)
    df_bioconductor.at[i, 'is_in_bioconductor'] = is_in_bioconductor(df_bioconductor.name.iloc[i], bioconductor_package_list)

# Exporting the results to an Excel file
writer = pd.ExcelWriter('R_packages.xlsx', engine='xlsxwriter')

r_packages.to_excel(writer, sheet_name='CRAN')
df_bioconductor.to_excel(writer, sheet_name='Bioconductor')

writer.save()