## {{beginner}} Introduction

{{tada}} Welcome to the Turing Data Safe Haven! {{tada}}

Secure research environments (SREs) for analysis of sensitive datasets are essential to give data providers confidence that their datasets will be kept secure over the course of a project.
The Data Safe Haven is a prescription for how to set up one or more SREs and give users access to them.
The Data Safe Haven SRE design is aimed at allowing groups of researchers to work together on projects that involve sensitive or confidential datasets at scale.
Our goal is to ensure that you are able to implement the most cutting edge data science techniques while maintaining all ethical and legal responsibilities of information governance and access.

The data you are working on will have been classified into one of five sensitivity tiers, ranging from open data at Tier 0, to highly sensitive and high risk data at Tier 4.
The tiers are defined by the most sensitive data in your project, and may be increased if the combination of data is deemed to be require additional levels of security.
You can read more about this process in our policy paper: _Arenas et al, 2019_, [`arXiv:1908.08737`](https://arxiv.org/abs/1908.08737).

The level of sensitivity of your data determines whether you have access to the internet within the SRE and whether you are allowed to copy and paste between the secure research environment and other windows on your computer.
This means you may be limited in which data science tools you are allowed to install.
You will find that many software packages are already available, and the administrator of the SRE will ingress - bring into the environment - as many additional resources as possible.

```{important}
Please read this user guide carefully and remember to refer back to it when you have questions.
In many cases the answer is already here, but if you think this resource could be clearer, please let us know so we can improve the documentation for future users.
```

### Definitions

The following definitions might be useful during the rest of this guide

Secure Research Environment (SRE)
: the environment that you will be using to access the sensitive data.

Data Safe Haven
: the overall project that details how to create and manage one or more SREs.

(user_guide_username_domain)=
Username domain
: the domain (for example `projects.turingsafehaven.ac.uk`) which your user account will belong to. Multiple SREs can share the same domain for managing users in common.

(user_guide_sre_id)=
SRE ID
: each SRE has a unique short ID, for example `sandbox` which your {ref}`System Manager <role_system_manager>` will use to distinguish different SREs in the same Data Safe Haven.

(user_guide_sre_url)=
SRE URL
: each SRE has a unique URL (for example `sandbox.projects.turingsafehaven.ac.uk`) which is used to access the data.
