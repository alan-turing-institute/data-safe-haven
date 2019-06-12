import python_package_validation as pv
from os import listdir
from os.path import isfile, join
from tqdm import tqdm

"""
	It uses two functions from `pv` to generate a list file with the packages and dependencies.
	- pv.get_names_of_all_dependencies(package) returns a list of lists of dependencies.
	- pv.flatten(deps) flattens the nested lists from the dependencies.
"""

# Gets the file names of the Python list in the `path` directory
path = '../new_dsg_environment/azure-vms/package_lists/'
onlyfiles = [f for f in listdir(path) if isfile(join(path, f)) and 'python' in f and '.list' in f and '-with-dependencies.list' not in f]

# For each .list file, a new one is created adding '-with-dependencies' to the name.
for file in onlyfiles:
    with open(path+file) as f:
        package_list = f.read()
        
    file_name = file.replace('.list', '-with-dependencies.list')
    f = open(path+file_name, 'w')

	# For each package in the file searches its dependencies.
    pbar = tqdm(package_list.split('\n'))
    for package in pbar:
        pbar.set_description('{} {}'.format(file_name, package))
        if len(package) > 0:
            f.write('{}\n'.format(package))
            deps = pv.get_names_of_all_dependencies(package)
            if deps is not None:
                for dep in list(set(pv.flatten(deps))):
                    if dep != package:
                        f.write('\t{}\n'.format(dep))
    f.close() 