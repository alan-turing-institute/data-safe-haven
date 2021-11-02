# Physical resilience and availability

One of the [NHS Cloud Security Principles](https://digital.nhs.uk/data-and-information/looking-after-information/data-security-and-information-governance/nhs-and-social-care-data-off-shoring-and-the-use-of-public-cloud-services), covers physical resilence.

> Services have varying levels of resilience, which will affect their ability to operate normally in the event of failures, incidents or attacks.
> A service without guarantees of availability may become unavailable, potentially for prolonged periods, regardless of the impact on your business.

## Design for failure. Solutions should be resilient regardless of the underlying cloud infrastructure

In the future we will look into creating alternative cloud implementations, for example the use of Amazon Web Services (AWS).
This might also allow for cross-cloud redundancy.
At present, however our implementation uses Microsoft Azure and we are therefore reliant on the availability of a single cloud infrastructure provider.
Azure data centres have [99.9% availability](<https://azure.microsoft.com/en-gb/support/legal/sla/summary/>) which should be sufficient for most Data Safe Haven users.

## Use multiple availability zones / data centres

We recommend using an Azure region with multiple availability zones.
For example, the UK South region has three availability zones.

## Have resilient network links to each zone / data centre

The Data Safe Haven is completely cloud-based and connections within a single deployed Safe Haven use Azure networking infrastructure.
Connections between users and the Data Safe Haven are out of our control.

## Use different cloud vendors or multiple regions from the same vendor

At the moment we only have an Azure implementation of our Safe Havens.
We are however exploring options for alternative implementations, for example by using Amazon Web Services (AWS).

Due to the current limitations of Azure, certain resources can only communicate with one another if they are deployed in the same region.
This means that each Data Safe Haven is fully contained in a specific region.

## Ensure their system has DDoS protection. This may be provided by the Cloud vendor or a third party

We only allow known IP addresses to connect to our Safe Havens.
This means we are not vulnerable to external DDoS attacks.
We cannot rule out attacks from our own users, but these can be mitigated using policy controls such as an agreed code of conduct.
