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

### Section 2.3. Wi-Fi access

You need to be connected to the Turing’s internal Wi-fi network to access any of the challenges:

> Wi-Fi Name: Turing DSG 
> Password  : *<password start>REDACTED<password end>*

The password is the full string between <password start> and <password end>, including spaces.

### Section 2.4. Multi-factor authentication

Multi-factor authentication (MFA, also known as two-factor authentication, "2FA", even if there are more than two factors) is one of the most powerful ways of protecting your personal information online.
In this case, we use MFA to protect the challenge data.

Very briefly, MFA will ask you to confirm your identity via another mechanism whenever you connect to the Windows Azure environment.
You can think of your username and password as being the first authentication, and the second being a text message, phone call, personal access code or notification via the mobile app.
*This is why we ask that you bring a mobile device with you to the Data Study Group.*

The instructions below recommend using notifications via the Windows authenticator app, but all the options above will work too.

This process may cause some connectivity challenges on the first (and maybe second) days of the Data Study Group, especially if your phone provider’s network has low connectivity at the British Library.
The DSG team are here to help smooth these processes for you, but it is important to emphasise that we are always balancing ease of analysis with our responsibilities as data controllers for the DSG week.
Thank you for your patience as we and your facilitators work to get you connected securely.

## Section 3. User activation instructions

This section describes user activation and verification procedures which are a requirement for the tier 2 or higher Turing safe haven.
As a result, you will possess user credentials that allow you to use the safe haven.
Instructions should be followed only once, at the start of the data study week.
Please let your facilitator know if any of the below fails despite multiple tries.

These same user credentials can be used to access the Azure environments for the Tier 0/1 challenges, so if you don’t already have an Azure account, you can follow these user activation instructions and provide them to your facilitator.

### Section 3.1. Initial User Sign In, configuring MFA

If you provided your phone number via the form we circulated last week and requested participants to complete, your account will be ready to initialise.
If you did not provide your number, please let you facilitator know, so they can log this with the IT and DSG team and get you an account set up ready to activate.

Your user name will be in the format firstname.lastname – you will see this mentioned again later in this document, on its own, or together with the Turing safe haven domain, as firstname.lastname@turingsafehaven.ac.uk .

You will have to (1) set a password and (2) configure MFA before you are able to log in to the safe haven.

#### Set your password

For security reasons, you must (re-)set your password before you can log in:

1.	Open a private browser session (‘incognito mode’) on your laptop – this will avoid picking up any existing Azure / Microsoft accounts you have 
2.	Paste the following URL into the private browser address bar - https://aka.ms/ssprsetup
3.	At the login prompt enter your username username@turingsafehaven.ac.uk and confirm/proceed
4.	There will then be a password prompt.
  And as you haven’t set a password yet - click "Forgotten password" 
5.	Complete the requested information (captcha and the phone number you provided on registration) 
6.	Reset your password by following the instructions

#### Configure the MFA

Before any user can access the secure environment, you need to setup your multifactor authentication.
The authentication method can be either via a call or text to a mobile phone or the Microsoft Authenticator app (recommended).

**Step 1** (if using the Microsoft authenticator app): download the app on your mobile device.

The links to download the app for iOS, Android and Window mobile are:

* iOS: http://bit.ly/iosauthenticator 
* Android: http://bit.ly/androidauthenticator 
* Windows mobile: http://bit.ly/windowsauthenticator

**Step 2**: Configure the multifactor authentication

1. Open a private browser session on your laptop
2. Enter https://aka.ms/MFASetup into the address bar
3. Login using username@turingsafehaven.ac.uk and the new password you just created 
  a. Note that you might find another address is automatically inserted at this step (eg your work email account). This is why we suggest using a private (incognito) browser session. If that doesn’t work, log out of your personal account and try again with your data study group user name.
4. Make sure you add another alternative number or use the Azure Auth phone app, but best advice is to the same number (your mobile number) as the alternative number as the Azure App can be a little hit and miss
5. Click save when done
6. Click “Set it up now” when prompted
7. On the “Additional security verification” screen you have three options on how the system will contact you for verification.  Click the drop down next under “Step 1” and select the option you wish to use.

*Insert pic 1*
*Insert pic 2*
