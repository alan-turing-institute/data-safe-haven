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

When we have comprehensively evaluated a complete freshly deployed system against our stated security and functionality standard, we issue it as a full release, with no pre-release label in the version.

### Pre-releases

We also issue pre-releases, where functionality has been tested to some extent, but not fully evaluated against our stated security and functionality standard. We use the pre-release label to indicate the level of quality assurance that has taken place using the following values, representing increasing order of assurance.

- `beta`: We have done a full, from-scratch deployment of an SHM and SRE and run a test suite to confirm key functionality and security is as expected, but have not fully validated the deployment against our stated security and functionality standard.

## Which version to choose

If you are beginning a deployment from scratch, take the highest numbered [release](https://github.com/alan-turing-institute/data-safe-haven/releases/) that corresponds to the quality level you require.

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
The Turing runs multiple week-long Data Study Groups (DSGs) each year and a 3-month Data Science for Social Good (DSSG) programme over the summer.
We usually deploy the latest available version of the Data Safe Haven for each of these to take advantage of new functionality.

| Event date       | Event name                    | Release used                                                                                     |
| ---------------- | ----------------------------- | ------------------------------------------------------------------------------------------------ |
| December 2018    | DSG 2018-12                   | [v0.1.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v0.1.0-beta) |
| April 2019       | DSG 2019-04                   | [v0.2.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v0.2.0-beta) |
| June-August 2019 | DSSG 2019                     | [v0.3.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v0.3.0-beta) |
| August 2019      | DSGN Bristol 2020             | [v1.0.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v1.0.0-beta) |
| September 2019   | DSG 2019-09                   | [v1.0.1-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v1.0.1-beta) |
| December 2019    | DSG 2019-12                   | [v1.1.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v1.1.0-beta) |
| April 2020       | DSG 2020-04 (event cancelled) | [v2.0.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v2.0.0-beta) |
| June 2020        | DSSG 2020                     | [v3.0.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v3.0.0-beta) |
| December 2021    | DSG 2021-12                   | [v3.3.1](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v3.3.1)           |
| December 2022    | DSG 2022-12                   | [v4.0.2](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.0.2)           |
| February 2023    | DSG 2023-02                   | [v4.0.3](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.0.3)           |
| May 2023         | DSG 2023-05                   | [v4.0.3](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.0.3)           |
| September 2023   | DDRC DSG Exeter 2023          | [v4.1.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.1.0)           |
| December 2023    | DSG 2023-12                   | [v4.1.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.1.0)           |
| May 2024         | DSG 2024-05                   | [v4.2.1](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.2.1)           |

Additionally, a production instance of DSH is maintained for use by research projects at the Turing.

| Year      | Release used                                                                                     |
|-----------|--------------------------------------------------------------------------------------------------|
| 2020      | [v2.0.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v2.0.0-beta) |
| 2020      | [v3.0.0-beta](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v3.0.0-beta) |
| 2021–2022 | [v3.3.1](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v3.3.1)           |
| 2022      | [v4.0.2](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.0.2)           |
| 2023      | [v4.0.3](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.0.3)           |
| 2023–2024 | [v4.1.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.1.0)           |
| 2024      | [v4.2.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.2.0)           |

## Versions that have undergone formal security evaluation

The following versions have been evaluated by third party security consultants prior to release.

| Version                                                                                         | Evaluation date   | Evaluation performed                                                                                                                                                                               | Outcome                              |
| --------------------------------------------------------------------------------------          | ----------------  | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| [v3.1.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v3.1.0)          | 13 July 2020      | Penetration test evaluating (1) external attack surface, (2) ability to exfiltrate data from the system, (3) ability to transfer data between SREs, (4) ability to escalate privileges on the SRD. | No major security issues identified. |
| [v3.3.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v3.3.0)          | 15 July 2021      | Penetration test evaluating (1) external attack surface, (2) ability to exfiltrate data from the system, (3) ability to transfer data between SREs, (4) ability to escalate privileges on the SRD. | No major security issues identified. |
| [v3.4.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v3.4.0)          | 22 April 2022     | Penetration test evaluating (1) external attack surface, (2) ability to exfiltrate data from the system, (3) ability to transfer data between SREs, (4) ability to escalate privileges on the SRD. | No major security issues identified. |
| [v4.0.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.0.0)          | 2 September 2022  | Penetration test evaluating ability to infiltrate/exfiltrate data from the system.                                                                                                                 | No major security issues identified. |
| [v5.0.0-rc1](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v5.0.0-rc.1) | 18 September 2023 | Penetration test evaluating ability to infiltrate/exfiltrate data from the system. Testing next codebase, using Python and Pulumi.                                                                 | No major security issues identified. |
| [v4.2.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v4.2.0)          | 22 March 2024     | Penetration test evaluating ability to infiltrate/exfiltrate data from the system. Repeat tests for v4.0.0 vulnerabilities.                                                                        | No major security issues identified. |
| [v5.0.0](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v5.0.0)          | 9 August 2024     | Penetration test evaluating ability to infiltrate/exfiltrate data from the system.                                                                                                                 | No major security issues identified. |

## Questions

If you have any questions or comments that are not dealt with here, please let us know by [starting a discussion](https://github.com/alan-turing-institute/data-safe-haven/discussions).
