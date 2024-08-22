---
name: Release checklist
about: Log completion of required actions for release testing
title: "Release: <version number>"
labels: "release candidate"
assignees: ""
---

## :white_check_mark: Checklist

<!--
Before reporting a problem please check the following. Replace the empty checkboxes [ ] below with checked ones [x] accordingly.
-->

Refer to the [Deployment](https://data-safe-haven.readthedocs.io/en/latest/deployment) section of our documentation when completing these steps.

- [ ] Consult the `data-safe-haven/VERSIONING.md` guide and determine the version number of the new release. Record it in the title of this issue.
- [ ] Create a release branch called e.g. `release-v0.0.1`
- [ ] Draft a changelog for the release similar to our previous releases, see https://github.com/alan-turing-institute/data-safe-haven/releases

### For patch releases only

- [ ] Confirm that the resource to which the patch applies can be successfully deployed

### For minor releases and above

- [ ] Deploy an SHM from this branch and save a transcript of the deployment logs
- Using the new image, deploy a tier 2 and a tier 3 SRE
    - [ ] Save the transcript of your tier 2 SRE deployment
    - [ ] Save the transcript of your tier 3 SRE deployment
- [ ] Complete the [Security evaluation checklist](https://data-safe-haven.readthedocs.io/en/latest/deployment/security_checklist.html) from the deployment documentation
- [ ] Add the new versions tag as an active build on [Read The Docs](https://readthedocs.org) (You can add as a hidden build, before release, to preview)

### For major releases only

- [ ] Confirm that a third party has carried out a full penetration test evaluating:
  1. external attack surface
  1. ability to exfiltrate data from the system
  1. ability to transfer data between SREs
  1. ability to escalate privileges on the SRD.

### Update documentation

- [ ] Update supported versions in `SECURITY.md`
- [ ] Update pen test results in `VERSIONING.md`

## :computer: Release information

- **Version number:** _
- **SHM ID:** _
- **T2 SRE ID:** _
- **T3 SRE ID:** _

## :deciduous_tree: Deployment problems

<!--
Keep a record in this issue of problems and fixes implemented during the release process. Be sure to update the changelog if any new commits are added to the release branch.
-->

