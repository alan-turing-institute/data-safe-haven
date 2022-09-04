# The Turing Data Safe Haven

```{toctree}
:hidden: true
:maxdepth: 2

overview/index.md
design/index.md
processes/index.md
roles/index.md
```

```{image} static/scriberia_diagram.jpg
:alt: Project summary
:align: center
```

Many of the important questions we want to answer for society require the use of sensitive data.
In order to effectively answer these questions, we need productive, secure environments to analyse the data.

We have developed:

- A proposal for how to design productive and secure research environments.
- A shared model for classifying projects into common sensitivity tiers, with a web-based tool to support this process.
- A proposed default set of technical security measures for each tier.
- A set of infrastructure-as-code tools which will allow anyone to deploy their own isolated research environment.

If this sounds interesting to you, take a look at our GitHub releases: [![Data Safe Haven releases](https://img.shields.io/static/v1?label=Data%20Safe%20Haven&message=Releases&style=flat&logo=github)](https://github.com/alan-turing-institute/data-safe-haven/releases).

## Documentation structure

The documentation for this project covers several different topics.
You can read them through in order or simply jump to the section that you are most interested in.

- [**Overview**](overview/index.md)
  - if you want an overview of what the Data Safe Haven project is about.

- [**Design**](design/index.md)
  - if you want details about the technical design of the Data Safe Haven

- [**Processes**](processes/index.md)
  - processes necessary to use the Data Safe Haven

- [**Roles**](roles/index.md)
  - if you want to [**deploy your own**](role_system_deployer) Data Safe Haven
  - if you want to [**upload sensitive data**](role_data_provider_representative) to a Data Safe Haven
  - if you need to [**analyse data**](role_researcher) in a Data Safe Haven that someone else has deployed
