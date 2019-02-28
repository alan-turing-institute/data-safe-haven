# Safe Haven User Documentation

## Section 1. Support for bugs and reports

The Turing IT and Research Engineering Group and the data study group team attempt to solve IT infrastructure issues arising as soon as possible.

The process for requesting help with the issue is as follows:

1. make sure you have read the below document and checked if it answers your query.
  Please do not log an issue before you have read the below document.
2. re-start the environment (safe haven or data science suite) at least once, re-attempt the process leading to the bug/error at least twice.
3. Let your challenge facilitator know of the issue. They have been given access to an internal Github issue tracker and will relay issues to Turing IT and REG.
Please help your facilitator with a summary, and an appropriate tag for the issue: [feature request], [package request], [bug report], etc.
If you are reporting a bug, include:
•	Your client machine’s operating system and operating system version
•	Precise condition under which the bug occurs. How to reproduce it.
•	Precise description of the bug. What happens? What would you expect to happen instead if there were no bug?
•	Any workarounds/fixes you have found

## Section 2. Overview of the Turing DSG IT set-up

To maintain security of the data and challenge insights we are legally required to work on some of the challenges within in the data safe haven hosted by the Turing Institute. 
Each challenge data set has a data governance and security tier which may impose restrictions on the analysis environment.

### Section 2.1 Data governance and challenge overview

The challenges in this DSG fall into *two distinct security tiers*:

* **Tier 2** – medium security: dstl, MedImmune, NATS, PlayerLens
* **Tier 0/1** – low security: Imperial/LANL/HiMAR, NSCS

Access procedures depend on the security tier for the chosen challenge:

**Tier 2**: the DSG team will come to each room and take a participant register for each challenge.
While you are having an initial problem discussion and brainstorming session, access will be granted to the Turing safe haven and to the relevant challenge data.
When this is ready, your facilitator will guide you through user registration and a safe haven usage tutorial.
Please also familiarise yourself with user registration and safe haven usage documentation as outlined in sections 3 and 4 of this document.

**Tier 0/1**: the challenge facilitator and/or challenge owner representative can give you direct access to the data and/or the analysis environment.
Challenge specifics are as below.

* NCSC – if you join this challenge, please send your facilitator Giovanni Colavizza, *email address redacted*, your Azure and GitHub account names – create accounts if necessary.
  Giovanni will then invite you to code and data repositories.
  This is an open data challenge so the analysis environment is also open.
* Imperial College/LANL/HiMaR –  this is also an open data challenge so the analysis environment is open.
  Ask your facilitator Helen Hu *email address redacted* and Challenge Owner Niall Adams to give you access to the Spark cluster and the Azure data science virtual machines.

### Section 2.2. Turing safe haven set-up

The following applies only to tier 2 or tier 3 challenges (see [section 2.1](#section-21-data-governance-and-challenge-overview)).

The original data is hosted on a server at the Alan Turing Institute.
You will not have access to that data server.

A copy of the data is available in a read-only file volume inside a [Windows Azure environment](https://azure.microsoft.com/en-gb/overview/what-is-azure/).

The Azure environment also contains a Unix data science VM, which can only be accessed from the dashboard. 

:arrow_right: Your laptop
  :arrow_right: Turing DSG Wi-Fi
    :arrow_right: Windows remote desktop (multi-factor authentication required)
      :arrow_right: Unix Azure environment

The data science VM has a standard suite of data science software, including Python 2/3 via Conda, Spyder, Jupyter and RStudio, with a large selection of pre-installed packages.

You also have access to HackMD for collaborative writing and GitLab to version control and share your code.

Note that tier 2 and higher safe havens do not allow you to install new software packages – if you require a specific package, please communicate this to your facilitator.

