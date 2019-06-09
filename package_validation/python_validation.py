import python_package_validation as pv
import pandas as pd

# Starts with an initial list from an anaconda url or packages
df = pd.DataFrame()
df = pv.evaluate_packages_from_anaconda(python_version = '3.7')

# Exporting the results to an Excel file
df.to_excel('python_packages_v1.xlsx')


# Or it can be evaluated one by one, uncommenting the following lines and calling pv.evaluate_package('some_package_name')
"""
example_package_name = 'pandas'
result = pv.evaluate_package(example_package_name)
print('{}'.format(result['evaluation_criteria']))
print(result)
"""