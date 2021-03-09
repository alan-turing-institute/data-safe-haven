# Tier 1

A light-weight, stand-alone environment for working with private data.

## 🤔 What is Tier 1

This environment is inspired by, and draws on, the [Data safe havens in the
cloud](https://www.turing.ac.uk/research/research-projects/data-safe-havens-cloud)
project. That project has developed policy and processes to deploy research
environments on the cloud that are secure enough to handle sensitive data yet
flexible enough to host productive data-science projects.

As part of this project a series of data security tiers numbered 0–4 were
established. Tiers 2 and above cover sensitive data, and tier 0 covers public,
non-sensitive data. That leaves tier 1 data which is not sensitive, but we may
still wish to keep private. For example, we might not be ready to share the data
or might want to keep it secret for a competitive advantage.

Tier 1 (and tier 0) data therefore do not require a safe haven and the
restrictions of a safe haven might become frustrating. However, there is still
value in having a reasonably secure, collaborative, flexible environment when
working with tier 1 data. The aim of this project is therefore to take the
features of the safe haven we like and include them in a light-weight,
stand-alone and more permissive environment more suitable for non-sensitive
data.

> ⚠️ Important
>
> This environment is not suitable for work involving sensitive or personal
> data. It is completely possible for someone to extract the private data from
> the environment, whether intentionally, accidentally or through coercion. In
> particular, users can copy/paste to and from the remote machine and make
> outbound internet connections.

## 🚀 Features

- 🚅 Quick and easy to deploy (leveraging [Terraform](https://www.terraform.io/)
  and [Ansible](https://www.ansible.com/))
- 🥑 Guacamole for remote desktop in a browser
- 🔐 Two factor authentication
- 🤖 Automated account creation and deletion
- 🖥️ Configurable Ubuntu VM pre-loaded with programming/data-science packages
- ⛰️ Read-only input data
- 🤝 Shared working directory backed (optionally) by SSD storage for
  collaborative work
- 🌐 Bring your own domain
- 🔑 Automatic HTTPS/SSL configuration using [Lets
  Encrypt](https://letsencrypt.org/) and [Traefik](https://traefik.io/)
