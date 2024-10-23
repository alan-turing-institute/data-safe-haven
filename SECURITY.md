# Security and vulnerability disclosure policy

## Supported Versions

Only the latest version of the Data Safe Haven is actively supported with security updates.
All organisations using an earlier version in production should update to the latest version.

| Version                                                                                 | Supported          |
| --------------------------------------------------------------------------------------- | ------------------ |
| [5.0.1](https://github.com/alan-turing-institute/data-safe-haven/releases/tag/v5.0.1)   | :white_check_mark: |
| < 5.0.1                                                                                 | :x:                |

## Reporting a Vulnerability

This vulnerability disclosure policy applies to any vulnerabilities you are considering
reporting related to the Data Safe Haven. We recommend reading this vulnerability
disclosure policy fully before you report a vulnerability and always acting in
compliance with it.

We value those who take the time and effort to report security vulnerabilities
according to this policy. However, we do not offer monetary rewards for vulnerability
disclosures.

### Reporting

If you believe you have found a security vulnerability, please check the list of
published [security advisories](https://github.com/alan-turing-institute/data-safe-haven/security/advisories)
and, if the vulnerability you have identified is not covered by an existing advisory, use the "Report a vulnerability" button to submit a vulnerability report.

In your report please include the details requested in the report form, including:

- The area / component of the Data Safe Haven where the vulnerability can be observed.
- A brief description of the type of vulnerability, for example; “unexpected outbound data access” or "privilege escalation to admin user".
- Steps to reproduce. These should be a benign, non-destructive, proof of concept. This helps to ensure that the report can be triaged quickly and accurately. It also reduces the likelihood of duplicate reports, or malicious exploitation of some vulnerabilities.
- An indication of the severity of the issue.

### What to expect

After you have submitted your report, we will respond to your report within 5 working
days and aim to triage your report within 10 working days. We’ll also aim to keep you
informed of our progress.

Priority for remediation is assessed by looking at the impact, severity and exploit
complexity. Vulnerability reports might take some time to triage or address. You are
welcome to enquire on the status but should avoid doing so more than once every 14
days. This allows our teams to focus on the remediation.

We will notify you when the reported vulnerability is remediated, and you may be
invited to confirm that the solution covers the vulnerability adequately.

Once your vulnerability has been resolved, we welcome requests to disclose your
report. We’d like to unify guidance to affected users, so please do continue to
coordinate any public release with us.

We will generally look to publish a public security advisory on this repository's
[security advisories](https://github.com/alan-turing-institute/data-safe-haven/security/advisories)
page once a vulnerability has been resolved and we have given those organisations
we know of with active deployments reasonable time to patch or update their deployments.
We will credit you with reporting the vulnerability and with any other assistance
you have provided characterising and resolving it in the published security advisory.
If you would prefer not to be credited in the public security advisory, please let us know.

In some instances we may already be aware of the reported vulnerability but not yet
have published a public security advisory. We still welcome additional reports in these
cases as they often provide additional useful information. Where multiple people have reported
the same vulnerability we will credit each of them in the public advisory when it is published.

### Guidance

You must NOT:

- Break any applicable law or regulations.
- Access unnecessary, excessive or significant amounts of data.
- Modify data in any organisation's systems or services.
- Use high-intensity invasive or destructive scanning tools to find vulnerabilities.
- Attempt or report any form of denial of service, e.g. overwhelming a service with a high volume of requests.
- Disrupt any organisation's services or systems.
