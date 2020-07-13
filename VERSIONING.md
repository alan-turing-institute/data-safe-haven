# Versioning for the Turing Data Safe Haven project

We use [semantic versioning](https://semver.org/), with the `MAJOR.MINOR.PATCH-pre-release` version numbering model.
We use versioning to indicate two things:

- the recency of the release in question, indicated by the number
- the level of confidence we have in the release, indicated by the presence or absence of a pre-release label.

## Numbering
Versions are numbered as `MAJOR.MINOR.PATCH`.

An increment to each of these corresponds to:
- `MAJOR`: Using this release together with an existing environment will require redeployment or patching of some or all existing components. An SRE will not be compatible with an SHM (or another SRE) deployed from a different `MAJOR` version.
- `MINOR`: Adds new functionality, but new SREs can be deployed into existing environments deployed from any version sharing the same `MAJOR` number without these existing SHM and SRE elements needing to be redeployed or patched.
- `PATCH`: Fixes bugs only and new SREs can be deployed into existing environments deployed from any version sharing the same `MAJOR` number without these existing SHM and SRE elements needing to be redeployed or patched.

## Releases vs pre-releases

### Releases
- When we have comprehensively evaluated a complete freshly deployed system against our stated security and functionality standard, we issue it as a full release, with no pre-release label in the version.

### Pre-releases
We also issue pre-releases, where functionality has been tested to some extent, but not fully evaluated against our stated security and functionality standard. We use the pre-release label to indicate the level of quality assurance that has taken place using the following values, representing increasing order of assurance.

- `beta`: We have done a full, from-scratch deployment of an SHM and SRE and run a test suite to confirm key functionality and security is as expected, but have not fully validated the deployment against our stated security and functionality standard.


## Which version to choose
If you are beginning a deployment from scratch, take the highest numbered version that corresponds to the quality level you require.
- If you want the highest confidence that the deployment will work with no issues, take the latest full release.
- To take advantage of more recent developments, where you are comfortable working with us to resolve the odd teething issue, take the latest `beta` pre-release.

If you are deploying SREs against an existing SHM you should either:
- use the same release as was used for deploying the SHM
- use a compatible `MINOR` version of the same `MAJOR` version

## Patching
Under some circumstances, it may be possible to patch an existing SHM to bring it into alignment with a newer version.
This is not guaranteed although we're happy to provide assistance to anyone trying to do this.


## Versions that have been used in production
The following versions have been deployed for events held at the Turing or in conjunction with partners.

| Date | Event name | Release used |
| --- | --- | --- |
| December 2018 | DSG 2018-12 | v0.1.0-beta |
| April 2019 | DSG 2019-04 | v0.2.0-beta |
| June-August 2019 | DSSG 2019 | v0.3.0-beta |
| August 2019 | DSGN Bristol 2020 | v1.0.0-beta |
| September 2019 | DSG 2019-09 | v1.0.1-beta |
| December 2019 | DSG 2019-12 | v1.1.0-beta |
| April 2020 | DSG 2020-04 (event cancelled) | v2.0.0-beta |
| June 2020 | DSSG 2020 | v3.0.0-beta |

## Versions that have undergone formal security evaluation
The following versions have been evaluated by third party security consultants.

| Version | Evaluation date | Evaluation performed | Outcome |
| --- | --- | --- | --- |
| v3.1.0 | 13 July 2020 | Penetration test evaluating (1) external attack surface, (2) ability to exfiltrate data from the system, (3) abilility to transfer data between SREs, (4) ability to escalate priviliges on the Data Science VM | No major security issues identified |

## Questions
If you have any questions or comments that are not dealt with here, please let us know by [opening an issue](#project-management-through-issues).
