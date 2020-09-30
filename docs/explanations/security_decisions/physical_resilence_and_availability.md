# Design decisions based on physical resilience and availability

## Issues

As per the NHS Cloud Security Principals (Principal 2, section 6), this document describes our approach and decision decisions towards the following points:

**Services have varying levels of resilience, which will affect their ability to operate normally in the event of failures, incidents or attacks. A service without guarantees of availability may become unavailable, potentially for prolonged periods, regardless of the impact on your business.**

This is split out across the following points:

### 1. Design for failure. Solutions should be architected for cloud such that they are resilient regardless of the underlying cloud infrastructure

The Safe Haven is designed to be a full cloud solution. Our current implementation uses Microsoft Azure which means that if Azure goes down so will our Safe Havens.

Microsoft claims to have Data Centres with at least [99.9% availability](<https://azure.microsoft.com/en-gb/support/legal/sla/summary/>).

In the future we will look into creating alternative cloud implementations, for example the use of Amazon Web Services (AWS). For a given Safe Haven however, it is likely that they will be fully implemented within a specific cloud infrastructure. Thus we are still dependant on the cloud infrastructure being up.

### 2. Use at least one availability zone / Data Centre

Most of our Safe Havens use one of the Microsoft UK regions (UK South or UK West).

UK South has three availability zones.

### 3. Have resilient network links to the zone / Data Centre

Safe Havens are full cloud based solutions, and we connect to a resilient system (Azure) using their standard approach.

### 4. Use multiple availability zones / Data Centres

Each Safe Haven is fully implemented in a specific region. This is due to the current Azure infrastructure where certain entities can only connect if they are in the same region.

Some of our Safe Havens use UK South, which have three availability zones.

### 5. Have resilient network links to each zone / Data Centres

Safe Havens are full cloud based solutions, and we connect to a resilient system (Azure) using their standard approach.

### 6. Use different cloud vendors or multiple regions from the same vendor

At the moment we only have a Microsoft Azure implementation of our Safe Havens. We are however exploring options for alternative implementations, for example by using Amazon Web Services (AWS).

Different Safe Havens use different regions. Most of our Safe Havens use either UK South or West. Some of our development environments will use US Data centres.

Microsoft infrastructure means that at the moment it is unlikely we could have operate in two regions at once. This is because a number of entities can only connect if they are in the same region. This is unlikely to change.

### 7. Have resilient network links to each region / vendor

Safe Havens are full cloud based solutions, and we connect to a resilient system (Azure) using their standard approach.

### 8. Ensure their system has DDoS protection. This may be provided by the Cloud vendor or a third party

We only allow known IP addresses to connect to our Safe Havens. This means we are not vulnerable to external DDoS attacks.
Our system may however be vulnerable to our own users.
