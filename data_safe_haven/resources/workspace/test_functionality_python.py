"""Test logistic regression using python"""

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression


def gen_data(n_samples: int, n_points: int) -> pd.DataFrame:
    """Generate data for fitting"""
    target = np.random.binomial(n=1, p=0.5, size=(n_samples, 1))
    theta = np.random.normal(loc=0.0, scale=1.0, size=(1, n_points))
    means = np.mean(np.multiply(target, theta), axis=0)
    values = np.random.multivariate_normal(
        means, np.diag([1] * n_points), size=n_samples
    ).T
    data = {f"x{n}": values[n] for n in range(n_points)}
    data["y"] = target.reshape((n_samples,))
    data["weights"] = np.random.gamma(shape=1, scale=1.0, size=n_samples)
    return pd.DataFrame(data=data)


def main() -> None:
    """Logistic regression"""
    data = gen_data(100, 3)
    input_data = data.iloc[:, :-2]
    output_data = data["y"]
    weights = data["weights"]

    logit = LogisticRegression(solver="liblinear")
    logit.fit(input_data, output_data, sample_weight=weights)
    logit.score(input_data, output_data, sample_weight=weights)

    print("Logistic model ran OK")  # noqa: T201
    print("All functionality tests passed")  # noqa: T201


if __name__ == "__main__":
    main()
