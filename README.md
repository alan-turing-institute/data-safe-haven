![Data Safe Haven cartoon by Scriberia for The Alan Turing Institute](docs/static/scriberia_diagram.jpg)

# :eyes: What is the Turing Data Safe Haven?

The **Turing Data Safe Haven** is an open-source framework for creating secure environments to analyse sensitive data.
It provides a set of scripts and templates that will allow you to deploy, administer and use your own secure environment.
It was developed as part of the Alan Turing Institute's [Data Safe Havens in the Cloud](https://www.turing.ac.uk/research/research-projects/data-safe-havens-cloud) project.

[![Docs](https://github.com/alan-turing-institute/data-safe-haven/actions/workflows/build_docs.yaml/badge.svg)](https://alan-turing-institute.github.io/data-safe-haven)
[![Build status](https://app.travis-ci.com/alan-turing-institute/data-safe-haven.svg?token=fmccRP1RHVJaEoiWy6QF&branch=develop)](https://app.travis-ci.com/alan-turing-institute/data-safe-haven)
[![Latest version](https://img.shields.io/github/v/release/alan-turing-institute/data-safe-haven?style=flat&label=Latest&color=%234B78E6)](https://github.com/alan-turing-institute/data-safe-haven/releases)
[![Slack](https://img.shields.io/badge/Join%20us!-yellow?style=flat&logo=slack&logoColor=white&labelColor=4A154B&label=Slack)](https://join.slack.com/t/turingdatasafehaven/signup)
![Licence](https://img.shields.io/github/license/alan-turing-institute/data-safe-haven)

## :family: Community & support

- Visit the [Data Safe Haven website](https://alan-turing-institute.github.io/data-safe-haven) for full documentation and useful links.
- Join our [Slack server](https://join.slack.com/t/turingdatasafehaven/shared_invite/zt-104oyd8wn-DyOufeaAQFiJDlG5dDGk~w) to ask questions, discuss features, and for general API chat.
- Open a [discussion on GitHub](https://github.com/alan-turing-institute/data-safe-haven/discussions) for general questions, feature suggestions, and help with our deployment scripts.
- Look through our [issues on GitHub](https://github.com/alan-turing-institute/data-safe-haven/issues) to see what we're working on and progress towards specific fixes.
- Subscribe to the [Data Safe Haven newsletter](https://tinyletter.com/turingdatasafehaven) for release announcements.

## :open_hands: Contributing

We are keen to transition our implementation from being a [Turing](https://www.turing.ac.uk/) project to being a community owned platform.
We have worked together with the community to develop the policy, processes and design decisions for the Data Safe Haven.

We welcome contributions from anyone who is interested in the project.
There are lots of ways to contribute, not just writing code!

See our [Code of Conduct](CODE_OF_CONDUCT.md) and our [Contributor Guide](CONTRIBUTING.md) to learn more about how we work together as a community and how you can contribute.

## :cake: Releases

If you're new to the project, why not check out our [latest release](https://github.com/alan-turing-institute/data-safe-haven/releases/latest)?

You can also browse [all our releases](https://github.com/alan-turing-institute/data-safe-haven/releases).
Follow the link from any release to view and clone this repository as at that release.

Read our [versioning scheme](VERSIONING.md) for how we number and label releases, as well as details of releases that have been used in production and releases that have undergone formal security evaluation.

## :mailbox_with_mail: Vulnerability disclosure

We value those who take the time and effort to report security vulnerabilities.
If you believe you have found a security vulnerability, please report it as outlined in our [Security and vulnerability disclosure policy](SECURITY.md).

## :book: Docs

The docs, including for older releases, are available [here](https://alan-turing-institute.github.io/data-safe-haven).

To build the docs locally, check out the repo, navigate to the `docs` folder and `make` them:

```{bash}
git clone https://github.com/alan-turing-institute/data-safe-haven.git
cd data-safe-haven/docs
make html
```

This will add the contents to a folder called `_output` inside `docs`.

## :bow: Acknowledgements

We are grateful for the following support for this project:

- The Alan Turing Institute's core EPSRC funding ([EP/N510129/1](https://gow.epsrc.ukri.org/NGBOViewGrant.aspx?GrantRef=EP/N510129/1)).
- The UKRI Strategic Priorities Fund - AI for Science, Engineering, Health and Government programme ([EP/T001569/1](https://gow.epsrc.ukri.org/NGBOViewGrant.aspx?GrantRef=EP/T001569/1)), particularly the "Tools, Practices and Systems" theme within that grant.
- Microsoft's generous [donation of Azure credits](https://www.microsoft.com/en-us/research/blog/microsoft-accelerates-data-science-at-the-alan-turing-institute-with-5m-in-cloud-computing-credits/) to the Alan Turing Institute.

## :warning: Disclaimer

The Alan Turing Institute and its group companies ("we", "us", the "Turing") make no representations, warranties, or guarantees, express or implied, regarding the information contained in this repository, including but not limited to information about the use or deployment of the Data Safe Haven and/or related materials.
We expressly exclude any implied warranties or representations whatsoever including without limitation regarding the use of the Data Safe Haven and related materials for any particular purpose.
The Data Safe Haven and related materials are provided on an 'as is' and 'as available' basis and you use them at your own cost and risk.
To the fullest extent permitted by law, the Turing excludes any liability arising from your use of or inability to use this repository, any of the information or materials contained on it, and/or the Data Safe Haven.

Deployments of the Data Safe Haven code and/or related materials depend on their specific implementation into different environments and we cannot account for all of these variations.
Safe use of any Data Safe Haven code or materials also relies upon individuals' and their organisations' good and responsible data handling processes and protocols and we make no representations and give no guarantees regarding the safety, security or suitability of any instance(s) of the deployment of the Data Safe Haven.
The Turing assumes no responsibility for updating any of the content in this repository; however, the underlying code and related materials may change from time to time with updates and it is the user's responsibility to keep abreast of these updates.
