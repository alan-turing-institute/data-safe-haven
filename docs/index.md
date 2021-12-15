# The Turing Data Safe Haven

```{toctree}
:hidden: true
:maxdepth: 2

introduction/index.md
roles/index.md
policies/index.md
design/index.md
```

```{image} static/scriberia_diagram.jpg
:alt: Project summary
:align: center
```

Many of the important questions we want to answer for society require the use of sensitive data.
In order to effectively answer these questions, the right balance must be struck between ensuring the security of the data and enabling effective research using the data.

In consultation with the community, we have been developing recommended policies and controls for performing productive research on sensitive data, as well as a cloud-based reference implementation in order to address some of the above challenges.

We have developed:

- A shared model for classifying data sets and projects into common sensitivity tiers, with recommended security measures for each tier and a web-based tool to support this process.
- A cloud-based Data Safe Haven implementation using software defined infrastructure to support the reliable, efficient and safe deployment of project specific secure research environments tailored to the agreed sensitivity tier for the project.
- A productive environment for curiosity-driven research, including access to a wide range of data science software packages and community provided code.

## Documentation structure

The documentation for this project covers into several different topics.
You can read them through in order or simply jump to the section that you are most interested in.

- [**Introduction**](introduction/index.md)
  - if you want an overview of what the **Data Safe Haven** project is about.

- [**Roles**](roles/index.md)
  - if you want to deploy your own **Data Safe Haven**
  - if you need to work with one that someone else has deployed
  - if you want to evaluate how **Data Safe Haven** works in practice

- [**Policies**](policies/index.md)
  - if you want details about our data governance and user management recommendations

- [**Design**](design/index.md)
  - if you want details about the technical design of the **Data Safe Haven**
  - if you are interested in contributing to the **Data Safe Haven** codebase
