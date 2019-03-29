# Code from

# http://enhancedatascience.com/2017/04/23/tutorial-logistic-regression-python/

import pandas as pd
import numpy as np

data = pd.read_csv('logistic.csv')

inputData = data.iloc[:,:-1]
outputData = data.iloc[:,-1]

from sklearn.linear_model import LogisticRegression
logit1=LogisticRegression()
logit1.fit(inputData,outputData)

logit1.score(inputData,outputData)

print("Logistic model ran OK")
