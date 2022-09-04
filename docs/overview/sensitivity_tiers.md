(policy_classification_sensitivity_tiers)=

# Sensitivity tiers

Since increasing security inevitably decreases usability, we classify projects into one of five security tiers.
As the sensitivity of the data increases, the security controls applied at that tier tighten.
When you set up your Data Safe Haven, you should think carefully about the security controls needed around:

- data classification
- data and software ingress (data or code entering a secure environment from an external source)
- data and software egress (data or code leaving a secure environment to an external recipient)
- user access
- user device management
- analysis environments

The Data Safe Haven suports five sensitivity tiers out-of-the-box.
These are discussed further in our [design choices](https://arxiv.org/abs/1908.08737) preprint.
A summary of the technical controls imposed by the Data Safe Haven codebase follows below.

(policy_tier_0)=

## Tier 0

**Tier 0** environments are the most permissive environments supported by the Data Safe Haven.
The following security controls are imposed out-of-the-box:

- connections are only permitted via an in-browser remote desktop
- users must authenticate with password and multi-factor authentication

(policy_tier_1)=

## Tier 1

**Tier 1** environments use the same technical controls as {ref}`policy_tier_0`.
Non-technical restrictions related to information governance procedures may also be applied according to your organisation's needs.

(policy_tier_2)=

## Tier 2

**Tier 2** environments impose the following technical controls on top of what is required at {ref}`policy_tier_1`.

- connections to the in-browser remote desktop can only be made from an agreed set of IP addresses
- outbound connections to the internet from inside the environment are not possible
- copy-and-paste between the environment and the user's device is not possible
- access to all packages on PyPI and CRAN is made available through a proxy or mirror server

Non-technical restrictions related to information governance procedures may also be applied according to your organisation's needs.

At the Turing connections to Tier 2 environments are only permitted from networks managed by the Turing or one of it's organisational partners.

(policy_tier_3)=

## Tier 3

**Tier 3** environments impose the following technical controls on top of what is required at {ref}`policy_tier_2`.

- a partial replica of agreed PyPI and CRAN packages is made available through a proxy or mirror server

Non-technical restrictions related to information governance procedures may also be applied according to your organisation's needs.

At the Turing connections to Tier 3 environments are only permitted from medium security spaces.
Such spaces control the possibility of unauthorised viewing by requiring card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) and screen adaptations or desk partitions are used in open-plan spaces if there is a high risk of "visual eavesdropping".

At the Turing connections to Tier 3 environments are also only permitted from managed devices (i.e. where the user is not an administrator) that have antivirus software installed and regular software updates applied.

(policy_tier_4)=

## Tier 4

**Tier 4** environments do not impose additional technical controls on top of what is required at {ref}`policy_tier_3`.

Non-technical restrictions related to information governance procedures may also be applied according to your organisation's needs.

The Turing does not currently operate any Tier 4 environments so has not thought through what additional controls it would impose at this Tier.
However, it is likely that any such additional controls would include stronger restrictions on the physical spaces from which Tier 4 environments could be accessed.
