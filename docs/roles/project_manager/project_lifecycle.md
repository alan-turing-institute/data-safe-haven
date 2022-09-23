# Project lifecycle

Each project will contain one or more work packages.
A work package is a set of input data together with the data analysis that will be performed on it.
As **project manager** it is your responsibility to keep track of all the work packages belonging to a project.
You should also ensure that all participants have been appropriately trained and are aware of the policies and procedures for the Data Safe Haven.

## Stakeholder identification

The first stage of any project involves identifying the different stakeholders.
The {ref}`role_data_provider_representative` represents the organisation providing the data.
Ensure that you have identified the **data owner** - the organisation who owns the dataset(s) being used in this work package.

```{hint}
Usually the **data provider** is also the **data owner**, but not in cases where they have purchased or loaned the data.
```

Ensure that the **data owner** has given this project permission to use the data.
You can do this by checking with the **data controller** - an individual or group at the **data owner**.

```{hint}
There may be additional **data owner stakeholders** working at the **data owner** who can provide input to discussions around data sharing and data classification.
```

Next you should identify the {ref}`role_investigator` - the lead researcher with overall responsibility for the project.
Finally, you should identify a {ref}`role_referee`, who will be able to provide an independent evaluation of the work package if needed.

## Review data governance arrangements

There may be existing agreements or arrangements between your institution and the **data owner**.
These should be reviewed to check the scope of data usage allowed before deciding whether a new agreement is needed.
Ensure that data sharing agreements are signed off before allowing the project to proceed any further.

## Consent and privacy of individuals in the dataset

If there is data relating to individual people in the data set, they must consent to their data being shared.
It is therefore necessary to check whether they have already consented or whether they need to be individually contacted to obtain this permission.
An assessment should also be made of any potential exclusions of informed consent for the purpose of research.

## Classification and data ingress

You should ensure that the {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable) go through the {ref}`process_data_classification`.
At the end of this process they should have classified the work package into one of the Data Safe Haven security tiers.
Follow the guide to [data ingress](data_ingress.md) to bring all necessary code and data into the secure research environment.

## Environment setup

You should now contact your {ref}`role_system_manager` and get them to schedule the deployment of a new environment for this work package.
You will need to provide the {ref}`role_system_manager` with contact details (email address and phone number) for each of the participants in this work package.
Work with the {ref}`role_investigator` and the {ref}`role_system_manager` to ensure that all participants are able to access the environment.
If new participants are added or removed, ensure that the {ref}`role_system_manager` is made aware and updates access to the environment as appropriate.

## Environment shutdown

At the end of the project, make sure that the project team identify all data or code that they want to egress from the environment.

- ensure that the {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable) go through the {ref}`process_data_classification`.
- follow the guide to [data egress](data_egress.md) to bring all necessary code and data out of the secure research environment.
- once this is done, let the {ref}`role_system_manager` know so that they can shut it down and securely delete all the contents of the secure research environment.
