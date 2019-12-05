# Code from: http://enhancedatascience.com/2017/04/23/tutorial-logistic-regression-python/

import pandas as pd
from sklearn.linear_model import LogisticRegression

def main():
    """Logistic regression"""
    data = pd.read_csv('logistic.csv')
    input_data = data.iloc[:, :-1]
    output_data = data.iloc[:, -1]

    logit1 = LogisticRegression(solver="liblinear")
    logit1.fit(input_data, output_data)
    logit1.score(output_data, output_data)

    print("Logistic model ran OK")

if __name__ == "__main__":
    main()
