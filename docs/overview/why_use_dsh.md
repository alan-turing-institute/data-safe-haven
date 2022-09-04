# Why use the Data Safe Haven?

The Data Safe Haven is our implementation of a TRE following the principles we laid out in an [earlier paper](https://arxiv.org/abs/1908.08737).
We provide a set of instructions that will allow you to set up your own secure environment with some default security controls.
Our aim throughout has been to make the environments reproducible, usable, secure, cloud-native and open source.

```{caution}
Use of the Data Safe Haven is not sufficient to guarantee the security of your data! It must be paired with appropriate informative governance requirements and user agreements.
```

```{caution}
Each organisation deploying their own instance of the Data Safe Haven is responsible for verifying their Data Safe Haven instance is deployed as expected and that the deployed configuration effectively supports their own information governance policies and processes.
```

```{tip}
In terms of the [Five Safes framework](https://ukdataservice.ac.uk/help/secure-lab/what-is-the-five-safes-framework/) the Data Safe Haven is aiming to be a Safe Setting.
```

```{admonition} Reproducible
We use software tools to define our infrastructure.
This makes it easy to deploy an isolated secure environment for each project.
Our deployments are reproducible, since they rely on running scripts controlled by a single configuration file.
This gives configurability while minimising human error at deployment time.
```

```{admonition} Usable
We want to maximise the productivity of our users within the security constraints imposed by the sensitivity of the data with which they are working.
The primary user interface consists of one or more Secure Research Desktop (SRD) virtual machines.
These are Ubuntu desktop environments with many data science tools pre-installed.
They also have access to database and file storage and locally-hosted collaborative services such as GitLab.
```

```{admonition} Secure
Role-based access controls are used to determine which users can perform which actions.
Connectivity is kept to a minimum between different parts of the Data Safe Haven and outwards to the wider internet.
```

```{admonition} Cloud-native
The scalability and resilience of modern cloud-computing providers allows anyone to easily use our code to deploy their own Safe Haven.
Currently, we only support Microsoft Azure, but we are hoping to look at other providers in future.
```

```{admonition} Open source
The Data Safe Haven is released under the [MIT licence](https://opensource.org/licenses/MIT).
This means that that any person or organisation is welcome to extend the code base and adapt it to their particular context.
```

## Is the Data Safe Haven suitable for you?

The Data Safe Haven was initially developed for use at the Alan Turing Institute.
We hope it will be useful in other contexts but you may need to alter it to fit your requirements.
We also hope that you will contribute any improvements back to the main project.

```{warning}
The Data Safe Haven is not a managed service offered by the Alan Turing Institute. It is a set of instructions enabling you to set up your own secure environment
```