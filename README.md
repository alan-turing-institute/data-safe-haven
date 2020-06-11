# The Turing Data Safe Haven

This is the repository for the Alan Turing Institute's [Data Safe Havens in the Cloud](https://www.turing.ac.uk/research/research-projects/data-safe-havens-cloud) project, and contains the code and instructions to to deploy, administer and use your own instance of the Turing's Data Safe Haven on Microsoft's Azure cloud platform.


## Introduction

Many of the important questions we want to answer for society require the use of sensitive data. In order to effectively answer these questions, the right balance must be struck between ensuring the security of the data and enabling effective research using the data.

In consultation with the community, we have been developing recommended policies and controls for performing productive research on sensitive data, as well as a cloud-based reference implementation in order to address some of the above challenges.

We have developed:

- A shared model for classifying data sets and projects into common sensitivity tiers, with recommended security measures for each tier and a web-based tool to support this process.
- A cloud-based Safe Haven implementation using software defined infrastructure to support the reliable, efficient and safe deployment of project specific secure research environments tailored to the agreed sensitivity tier for the project.
- A productive environment for curiosity-driven research, including access to a wide range of data science software packages and community provided code.


## Overview

To get a good overview of the Safe Haven, see the resources below.

  - [One-page overview](https://doi.org/10.6084/m9.figshare.11815224): Poster with overview of our data classification approach, security measures, data management and technical architecture. This is the best one-page high-level overview of our systems and process.

  - [Overview presentation](https://doi.org/10.6084/m9.figshare.11923644): Slides from a presentation about the Safe Haven giving a more in-depth overview.

  - [Design choices](https://arxiv.org/abs/1908.08737): Our preprint "Design choices for productive, secure, data-intensive research at scale in the cloud", outlining our policies, processes and design decisions for the Safe Haven.


## Documentation

For detailed guidance on deploying, administering and using the Safe Haven, see our [documentation](/docs/README.md).


## Contributing

We worked together with the community to develop the policy, processes and design decisions for our Safe Haven, and we are keen to transition our implementation from being a Turing project to being a community owned platform which we work together with a range of other organisations to maintain and extend.

We welcome contributions from anyone who is interested in the project. There are lots of ways to contribute, not just writing code. See our [Code of Conduct](CODE_OF_CONDUCT.md) and our [Contributor Guide](CONTRIBUTING.md) to learn more about how you can contribute and how we work together as a community.


## Acknowledgements

We are grateful for the following support for this project:

  - The Alan Turing Institute's core EPSRC funding ([EP/N510129/1](https://gow.epsrc.ukri.org/NGBOViewGrant.aspx?GrantRef=EP/N510129/1)).
  - The UKRI Strategic Priorities Fund - AI for Science, Engineering, Health and Government programme ([EP/T001569/1](https://gow.epsrc.ukri.org/NGBOViewGrant.aspx?GrantRef=EP/T001569/1)), particularly the "Tools, Practices and Systems" theme within that grant.
  - Microsoft's generous [donation of Azure credits](https://www.microsoft.com/en-us/research/blog/microsoft-accelerates-data-science-at-the-alan-turing-institute-with-5m-in-cloud-computing-credits/) to the Alan Turing Institute.
