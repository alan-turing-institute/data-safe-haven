import requests
import json
from tqdm.autonotebook import tqdm
import random
from datetime import datetime, timedelta
import time
import logging

logging.basicConfig(filename='package-validator.log', filemode='w', level=logging.INFO, format='%(asctime)s - %(message)s')
logging.info('Admin logged in')

def read_list(file_path):
    """
    Reads a file expecting a package name per line.
    Returns a list with all package names in the file.
    """
    with open(file_path) as f:
        data = f.read()
    package_names = [x.strip() for x in data.split('\n')]
    return package_names

def get_libraries_io_project_info(platform, name):
    """
    Using the package name, it returns a JSON with information of the project/library from libraries.io
    The libraries.io API has a limit of 60 calls per minute.
    """
    api_key = get_libraries_io_api_key()
    response = requests.get('https://libraries.io/api/{platform}/{name}?api_key={api_key}'.format(platform=platform,name=name, api_key=api_key))
    if response.status_code == 200:
        return response.json()
    elif response.status_code == 404:
        return None
    elif response.status_code == 429:
        time.sleep(10)
        get_libraries_io_project_info(platform, name)
    else:
        return None

def get_project_dependencies(platform, name, version):
    """
    Returns a json with the dependencies of a package given its name, version and platform (CRAN, PyPI, etc.)
    """
    api_key = get_libraries_io_api_key()
    url = 'https://libraries.io/api/{platform}/{name}/{version}/dependencies?api_key={api_key}'.format(platform=platform, name=name, version=version, api_key=api_key)
    response = requests.get(url)
    if response.status_code == 200:
        return response.json()
    elif response.status_code == 404:
        return None
    elif response.status_code == 429:
        time.sleep(10)
        get_project_dependencies(platform, name, version)
    else:
        return None

def load_api_keys(path='.', filename='secrets/libraries_io_api_keys.json'):
    """
    Loads a JSON file with the following structure to get the API keys.
    {
        "api_keys" : [
            {
                "key" : "<YOUR_API_KEY_1>",
                "last_time_used" : null,
                "limit" : 60,
                "api_calls" : 0,
                "reset_time" : null
            },
            ...
            {
                "key" : "<YOUR_API_KEY_N>",
                "last_time_used" : null,
                "limit" : 60,
                "api_calls" : 0,
                "reset_time" : null
            }
        ],
        "available_keys" : null
    }
    """
    with open(path + '/' + filename) as json_file:
        keys = json.load(json_file)

    if len(keys['keys'][0]['key']) == 0:
        print('Please store the key(s) for libraries.io in the secrets/libraries_io_api_keys.json file.')
        return None
    else:
        available_keys = []
        for i, key in enumerate(keys['keys']):
            key['reset_time'] = get_reset_time()
            available_keys.append(i)

        keys['available_keys'] = available_keys
        return keys

def get_reset_time():
    """
    Returns the time when an API key will reset. One minute in the future.
    This time is compared against now to decide if the key can still be used or should it wait until its reset.
    """
    return datetime.now() + timedelta(minutes=1)

def check_available_keys():
    """
    It updates a global variable with the available keys to query the API. It can handle many API keys at the same time.
    """
    global api_keys
    for i, k in enumerate(api_keys['keys']):
        if datetime.now() > k['reset_time']:
            api_keys['keys'][i]['reset_time'] = get_reset_time()
            api_keys['keys'][i]['api_calls'] = 0
            if i not in api_keys['available_keys']:
                api_keys['available_keys'].append(i)
        elif api_keys['keys'][i]['api_calls'] >= api_keys['keys'][i]['limit'] and i in api_keys['available_keys']:
            api_keys['available_keys'].remove(i)

def get_libraries_io_api_key():
    """
    Returns a valid API key for libraries.io
    It will wait until a key is reset if there are no more calls available.
    The use of more than one API key is advisable.
    An API key can be obtained by creating an account in libraries.io and going to https://libraries.io/account to the `API Key` section.
    The API key is a string of  32 characters.
    All the API keys must be added to the `secrets/libraries_io_api_keys.json`
    """
    global api_keys
    check_available_keys()
    if len(api_keys['available_keys']) > 0:
        index = random.sample(api_keys['available_keys'], 1)[0]
        api_keys['keys'][index]['api_calls'] += 1
        return api_keys['keys'][index]['key']
    else:
        # wait
        seconds = []
        for k in api_keys['keys']:
            seconds.append((k['reset_time'] - datetime.now()).seconds)
        pbar3 = tqdm(range(min(seconds) + 2), leave = False)
        pbar3.set_description('Waiting to reset API key...')
        for _ in pbar3:
            time.sleep(1)
        return get_libraries_io_api_key()

def get_package_dependencies(platform, package_name, verbose = False):
    global dependencies_included
    project_info = get_libraries_io_project_info(platform, package_name)
    package_dependencies = []
    if project_info:
        package_versions = [x['number'] for x in project_info['versions']]
        if verbose:
            logging.info('{} {} versions {}'.format(package_name, len(package_versions), package_versions))
        pbar2 = tqdm(package_versions, leave = False)

        for version in pbar2:
            pbar2.set_description('{} {}'.format(package_name, version))
            dependencies = get_project_dependencies(platform, package_name, version)
            if verbose:
                if dependencies:
                    logging.info('{} {} {} dependencies {}'.format(package_name, version, len(dependencies['dependencies']), [x['name'] for x in dependencies['dependencies']]))
                else:
                    logging.info('{} {} no dependencies'.format(package_name, version))
            if dependencies:
                for x in dependencies['dependencies']:
                    if x['name'] not in dependencies_included:
                        package_dependencies.append(x['name'])
                        dependencies_included.append(x['name'])
        if verbose:
            logging.info('{} new dependencies to check {} {}'.format(package_name, len(package_dependencies), package_dependencies))

    return package_dependencies

def get_recursive_dependencies(platform, package_names, verbose = False):
    """
    For each package gets all the versions.
        For each version of each package gets all the dependencies.
            For each dependency repeats the previous process until it include all the dependencies.

    `dependencies_included` will contain the extended list of packages including any package or dependency that is not in the input list of package names.
    """
    global dependencies_included

    pbar1 = tqdm(package_names)
    for i, package_name in enumerate(pbar1):
        pbar1.set_description(package_name)
        if package_name not in dependencies_included:
            dependencies_included.append(package_name)
        if verbose:
            logging.info('{} package starting validation {}/{}'.format(package_name, i, len(package_names)))
        package_dependencies = get_package_dependencies(platform, package_name, verbose = verbose)
        if verbose:
            logging.info('{} dependencies {}'.format(package_name, package_dependencies))
        while(len(package_dependencies) > 0):
            for p in package_dependencies:
                package_dependencies.remove(p)
                if verbose:
                    logging.info('{} {} dependency included'.format(package_name, p))
                    package_dependencies += get_package_dependencies(platform, p, verbose = verbose)

        logging.info('{} finished validation {}/{} '.format(package_name, i, len(package_names)))

# Reading the API keys to query libraries.io
api_keys = load_api_keys()

# Definning constants for Python and R platforms
PYTHON_PLATFORM = 'Pypi'
R_PLATFORM = 'CRAN'


# FOR PYTHON PACKAGES
# Reading the list of Python package names
python_packages = read_list('tier3_pypi_whitelist.list')
# Making a copy that will be extended with all the dependencies iteratively
dependencies_included = python_packages.copy()
# Process the dependencies for a list of packages. The results are included to the `dependencies_included` list structure.
# The `verbose = True` is optional to create a log called `package-validator.log` recording all the calls and results found in the process of going per dependency. It is useful for validation.
get_recursive_dependencies(PYTHON_PLATFORM, python_packages, verbose = True)
# Sorting the results
dependencies_included.sort()
# Exporting the results
with open('dependencies_included_PyPI.list', 'w') as f:
    for package_name in dependencies_included:
        f.write(package_name + '\n')


# FOR R PACKAGES
# Reading the list of R package names
r_packages = read_list('cran.list')
# Making a copy that will be extended with all the dependencies iteratively
dependencies_included = r_packages.copy()
# Process the dependencies for a list of packages. The results are included to the `dependencies_included` list structure.
# The `verbose = True` is optional to create a log called `package-validator.log` recording all the calls and results found in the process of going per dependency. It is useful for validation.
get_recursive_dependencies(R_PLATFORM, r_packages, verbose = True)
# Exporting the results
dependencies_included.sort()
with open('dependencies_included_CRAN.list', 'w') as f:
    for package_name in dependencies_included:
        f.write(package_name + '\n')