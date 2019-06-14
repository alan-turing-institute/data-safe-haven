import python_package_validation as pv
from os import listdir
from os.path import isfile, join
from tqdm import tqdm

"""
	It uses two functions from `pv` to generate a list file with the packages and dependencies.
	- pv.process_dependencies(packages, master_list) returns a list of new dependencies found among the dependencies of the `packages` list.
	- get_repository_dependencies(name, delay = 0.5) returns the dependencies of a given package.
"""

# Getting the files to make the initial list of packages
path = '../new_dsg_environment/azure-vms/package_lists/'
onlyfiles = [f for f in listdir(path) if isfile(join(path, f)) and 'python' in f and '.list' in f and '-with-dependencies.list' not in f and 'diff' not in f]

packages = []
for file in onlyfiles:
    with open(path+file) as f:
        data = f.read()
        for p in data.split('\n'):
            if len(p.strip()) > 0:
                packages.append(p)

# Adding the packages that may have different names in pip
diff_list = '../new_dsg_environment/azure-vms/package_lists/python-diff-names.list'

with open(diff_list) as f:
    data = f.read()

for package in data.split('\n'):
    name1, name2 = package.split(' -> ')
    packages.append(name1)
    packages.append(name2)

packages = list(set(packages))
packages.sort()

# `packages` is the initial list of packages.

# The search is iterative, it looks for dependencies of packages in a list. 
# Then stores the new packages to search for their dependencies in the next iteration and so on.
master_list = packages
new_packages = None
iterations = 10

for i in range(iterations):
    if new_packages == None:
        new_packages = pv.process_dependencies(master_list, master_list)
        master_list.extend(new_packages)
    else:
        new_packages = pv.process_dependencies(new_packages, master_list)
        master_list.extend(new_packages)    

# Saving the list to a file
final_list = master_list
final_list = list(set(final_list))

file_name = 'new_dsg_environment/azure-vms/package_lists/python-final.list'
f = open(file_name, 'w')
final_list.sort()
for p in final_list:
    f.write(p+'\n')
    
f.close()
