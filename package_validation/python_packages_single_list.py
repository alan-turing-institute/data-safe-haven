import pandas as pd
from math import isnan
import python_package_validation as pv
from os import listdir
from os.path import isfile, join
from collections import Iterable
from tqdm import tqdm
import importlib

path = '../new_dsg_environment/azure-vms/package_lists/'
onlyfiles = [f for f in listdir(path) if isfile(join(path, f)) and 'python' in f and '.list' in f and '-with-dependencies.list' not in f]

packages = []
for file in onlyfiles:
    with open(path+file) as f:
        data = f.read()
        for p in data.split('\n'):
            if len(p.strip()) > 0:
                packages.append(p)

diff_list = '../new_dsg_environment/azure-vms/package_lists/python-diff-names.list'

with open(diff_list) as f:
    data = f.read()

for package in data.split('\n'):
    name1, name2 = package.split(' -> ')
    packages.append(name1)
    packages.append(name2)

packages = list(set(packages))
packages.sort()

file_name = 'packages-plus-dependencies.list'
f = open(file_name, 'w')

# For each package in the file searches its dependencies.
pbar = tqdm(packages)
for package in pbar:
    pbar.set_description('{}'.format(package))
    f.write('{}\n'.format(package))
    deps = pv.get_names_of_all_dependencies(package)
    if deps is not None:
        for dep in list(set(pv.flatten(deps))):
            if dep != package:
                f.write('\t{}\n'.format(dep))
f.close()