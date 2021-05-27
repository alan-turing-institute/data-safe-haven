---
layout: page
title: Secure Research Environment Build Instructions
---

These instructions will walk you through deploying a Secure Research Environment (SRE) that uses an existing Safe Haven Management (SHM) environment.

We currently support three different end-user interfaces:

+ :pear: `Apache Guacamole` :sparkles: **recommended for development and testing or for Tier 0/1 production SREs requiring full remote desktop** :sparkles:
  + [Tiers 0/1 only](how-to-deploy-sre-apache-guacamole.md)
+ :beginner: `CoCalc` :sparkles: **recommended for Tier 0/1 SREs requiring collaborative notebook editing** :sparkles:
  + [Tiers 0/1 only](how-to-deploy-sre-cocalc.md)
+ :bento: `Microsoft Remote Desktop` :sparkles: **recommended for Tier 2 or above production SREs** :sparkles:
  + [Tiers 2/3/4](how-to-deploy-sre-microsoft-rds.md)

Deployment of an SRE using Apache Guacamole is more fully automated and cheaper than using Microsoft Remote Desktop.
However, we have not yet run a penetration test for a Guacamole based SRE so would not yet recommend it's use in production environments at Tier 2 or above.
