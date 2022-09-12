# Data egress process

Data Safe Havens are used for doing secure data research on individual "work packages" of data.
Once the project is finished, it is important to extract all outputs from the environment before shutting it down.
Each time you egress data from the environment, it needs to be classified using the {ref}`process_data_classification`.

```{note}
You might want to define multiple data collections for egress, which would each have their own sensitivity classification. For example, you might separate a low-sensitivity written report from a high-sensitivity derived dataset.
```

## Bringing data out of the environment

As for [data ingress](data_ingress.md), there are three methods of transferring data out of the Data Safe Haven (in order of preference):

- Microsoft Azure Storage Explorer
- SFTP
- Physical

Ensure that the {ref}`role_data_provider_representative` and the {ref}`role_system_manager` discuss the most appropriate method to bring data out of the environment.

```{danger}
Under no circumstance should sensitive data be sent via email, even if encrypted.
```

## Case study - one-off project

For the [Turing Data Study Groups](https://www.turing.ac.uk/collaborate-turing/data-study-groups) we egress the following two collections at the end of a project.

### Data egress 1 - Reports and outputs for report finalisation

When you're finishing a project, you'll need to complete reports and any other outputs that might be pertinent to the presentation of the research you've done.
In this work package, you'll be egressing the documents, graphs, pictures and any other data you might need to make it easier to finish the report.

```{tip}
We recommend redacting or removing any sensitive items from this dataset so that it will be classified at a low tier, allowing report writing to be done outside a secure environment.
```

**Contents:** Report inputs including text, images and code snippets.

### Data egress 2 - Data Provider Handover

This dataset includes the full set of outputs, such as derived data and any code used to produce or process them.
If these end up classified at a higher tier than the inputs, you should discuss potentially removing problematic outputs before starting egress.

**Contents:** All outputs, including text, images, code and any derived datasets.
