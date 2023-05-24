(design_security_objectives)=

# Security objectives

The diagram below shows an overview of the security objectives outlined in our [design choices](https://arxiv.org/abs/1908.08737) preprint.

```{image} sample_security_controls.png
:alt: Sample security controls
:align: center
```

```{caution}
The Alan Turing Institute does not yet operate any {ref}`policy_tier_4` environments and so our suggested default controls for {ref}`policy_tier_4` environments are still under development.
Organisations are responsible for making their own decisions about the suitability of any of our default controls, but should be especially careful about doing so if considering using the Data Safe Haven for projects at the {ref}`policy_tier_4` sensitivity level.
```

## Security considerations

In order to configure your Data Safe Haven deployment according to your needs you may want to consider the following:

- Multifactor authentication and password strength requirements
- Allowed networks for inbound and outbound connections
- Level of control over user devices
- Physical security
- Whether to allow copy-and-paste from user devices
- How to manage data ingress and egress
- How to manage software ingress and egress
- Whether to allow access to some or all packages from external repositories
- Which external URLs to allow through the firewall

These are a mixture of technical, policy and physical controls.

The built-in technical controls applied in the Data Safe Haven are detailed [here](technical_controls.md).
The configuration used at the Alan Turing Institute is included [here](reference_configuration.md) for reference.
