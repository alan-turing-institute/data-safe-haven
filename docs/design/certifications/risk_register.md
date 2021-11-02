(design_risk_register)=
# Risk Register

This risk rating was undertaken on the 2/02/2021.
All risks identified have been rated as **low risk**, with the exception of an Azure platform compromise being rated **medium**.

Risk register rating has been calculated using [this guide](http://intaver.com/risk-scores/) to create a simple reference to measure the risks.

| Risk                           | Description                                                                                                                                                                   | Likelihood  | Severity  | Score  |
| ----                           | ------------                                                                                                                                                                  | ----------- | --------- | ------ |
| Azure platform compromise      | A malicious actor gained access to an administrative account on the  Azure platform, compromising the data and infrastructure                                                 | 1           | 5         | 5      |
| Compromising Nexus server      | A malicious actor manages to compromise the Nexus machine or app (only accessible via port 80) and gains (limited) access to the internet                                     | 1           | 4         | 4      |
| Configuration error            | A DSH is configured incorrectly, leaving access to the internet on a higher=level tier                                                                                        | 3           | 1         | 3      |
| Authorised malicious user      | An authorised malicious user decided to try and remove from data from the data safe haven                                                                                     | 1           | 3         | 3      |
| Compromising of a user account | A malicious actor compromised a user account, by compromising both their log-in and 2FA, and gaining access to account with intent to steal personal information              | 1           | 3         | 3      |
| Egress check failure           | An accidental removal of sensitive data from the DSH due to user error, with sensitive data being incorrectly released, or data being given to the incorrect person or people | 1           | 2         | 2      |
