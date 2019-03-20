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

![](MFA_Step1.png)

**Option 1**: Authentication by phone

This option will call your mobile phone.
The service is automated, and you’ll be requested to press the # key to confirm the request 
Note: some people get a call that says, "press the pound key" and others receive "press the hash key" – both mean hit the "#"

1.	Select your country from the drop down
2.	Enter your mobile number
3.	Click "Next"
4.	Answer your phone and follow the instructions
5.	Click "Done" to finish the process

After completing the process you can close your browser.

**Option 2**: Mobile app

If you have installed the Microsoft Authenticator app then this is the option to select.

1.	Select the "Receive notifications for verification" radio button
2.	Click on "Set up"
3.	Open your Microsoft Authenticator app on your phone and select "Add an account"
4.	Select "Work or School" account
5.	Scan the QR code on the screen
6.	Click "Next" to start verification
7.	Click "Next" again to test the app, you will get a verification on your app.
8.	Enter your mobile phone number to enable password recovery
9.	Click "Done" to finish

After completing the process you can close your browser

#### Top tips regarding MFA

***If at first you don’t succeed: do the exact same thing a few more times!***

Sometimes the MFA steps can be buggy.
We’ve collected a few top tips here, but really, the answer is to be patient and just try again with the exact steps you just completed!

* :sparkles: TOP TIP :sparkles:: Verifying your account in the Authenticator app can be weirdly buggy. Sometimes it doesn’t work the first time, but for the facilitators we all connected after somewhere between 1 and 10 attempts. 
* :sparkles: TOP TIP :sparkles:: Make sure you allow notifications on your authenticator app, and check you don’t have Do not Disturb mode on
* :sparkles: TOP TIP :sparkles:: You have to be SUPER FAST at acknowledging the notification on your app! I think within the 30 seconds that each of the access codes update. If at first you don’t succeed…

## Section 4. Using the safe haven

### Section 4.1. Access credentials

From the user registration process as in Section 3, you should have the following ready:
* A user name – firstname.lastname, we refer to this as [UID] below
* A user password – you choose this in the registration/MFA set-up process, [pw] below
* A safe haven internal VM (IP – 10.250.sth.sth. or similar), your facilitator will pass on, [IP] below. 
Those can be accessed by clicking on the custom VM icon.

### Section 4.2. Logging into the Windows Azure environment

In order to access the Azure safe haven environment, follow the below steps:

1. Open a private web browser session and enter the following URL in an incognito tab / private mode)
https://rds.dsgroupX.co.uk/RDWeb/webclient/ 

Where you replace “X” by one of the following numbers, depending on challenge
Challenge A: X = 1	Challenge B: X = 2	Challenge C: X = 3	NATS: X = 4

NOTE: due to the security tier, there is no internet access from inside any of the above VMs. There is no copy/paste functionality from outside to inside the environment.

* :sparkles: TOP TIP :sparkles:: Don’t forget the https:// - it won’t work without that prefix. 

2. Enter the user name you’ve been provided, ensure that you use the following format:
[UID]@turingsafehaven.ac.uk
* :sparkles: TOP TIP :sparkles:: that's an AC.UK address not .co.uk!!

3. Enter your [pw] and confirm.

You will now receive a call/text/push notification for the MFA to confirm. 
For the call, you may have to move to a place with good reception and/or press the hash (#) key multiple times in-call.
After success, you’ll see the following screen:

![](RDS_app_selection_options.png)

4. Follow the steps in [Section 4.3](#section-43-First-time-set-up) if this is the first time you are logging in.
Following first time use, you can select whatever app that you wish to work with – each is explained in the following sections. 

5. Remember that once you go into one of these apps, you’re now going to a local server / UK Remote Desktop / VM. 
That means some of your key mappings may not be the same as you’re used to.

* :sparkles: TOP TIP :sparkles:: Open up a text editor to check what keys the remote desktop thinks you’re typing – especially if you have special characters you are using.

* :sparkles: TOP TIP :sparkles:: Right click on Desktop and Applications->Settings->Keyboard to change the layout

### Section 4.3. First-time set-up

In order to set up your user account on the VM, you need to follow the below steps **once**.

1  Run the “Shared VM (SSH)” app and log in with [UID], [pw], at [IP] (enter into fields). 
(Note, the cursor will not move while you are typing your password)
Confirm the below security alert with “yes” (this only happens on the first log in). 
Once you have confirmed log in, you can close this window.

![](1st_logon_putty.png)

2. run the “Shared VM (Desktop)” app. 
Log in with [UID]@turingsafehaven.ac.uk and [pw]. 
Check the box in the security alert below and confirm by clicking the “yes” button. 

![](1st_logon_sharedVMdesktop.png)

Insert your credentials as per the example below:

![](logon_VMdesktop.png)

## Section 4.4. Using the data analytics VM

The analytics environment can be accessed through the Shared VM (desktop) app. 
Please log in with user name [UID] and password [pw].

Applications can be accessed through Terminal or right click on desktop (top left) and:
* Applications->Development->RStudio
* Applications->Development->Atom
* Open Terminal here -> “jupyter notebook &” for python through jupyter
* Open Terminal here -> “spyder &” for Spyder a Python IDE that behaves like RStudio jupyter

Note that all the custom R packages requested have been installed in the system R. However, just typing R at the commandline will run conda's R. You can run the system R by typing /user/bin/R. We had already pointed RStudio to use system R, so those using RStudio should see the custom packages with no issues.

This VM can also be used to directly access GitLab and HackMD
1.	E.g. point firefox to url provided by the resource dashboard for GitLab/HackMD
2.	Read and write access – the repository URL can be copied using via icon and then replacing the first bit by the IP address – in the case below 10.250.10.151

![](repository_url_copy_icon.png)

![](gitlab_screenshot.png)

## Section 4.5. Accessing GitLab and storing code

GitLab is an open source version of GitHub. 

It allows you to version control all the code that you write for any of the Data Study Group challenges. 
There is a local GitLab installation within the Work Resources. 

If you have not used GitLab before – do feel free to ask your group colleagues for help, ask in the Slack channel for help.

Everything that is not stored in a GitLab repository on Friday lunchtime will be DESTROYED FOR EVER.
Make sure that every piece of code or processed dataset you think might be at all useful is stored in a GitLab repository within the secure environment.

You can access the same GitLab repositories from the Work Resources page. **(or via the sahared VM desktop?)

Login with user name [UID] and password [pw].

![](gitlab_screenshot_login.png)

Please make all your repositories public so they are easy to share within your group. 
(Note that they are not really public as the server is only available inside your team’s virtual environment.)

## Section 4.6. Accessing HackMD and writing the report

HackMD is a locally installed tool that allows you to collaboratively write the data study group challenge report. 
It uses markdown which is a simple way to format your text so that it renders nicely in full html. 

You can find a really great markdown cheat sheet at
[https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet) 

You can access a local installation of HackMD from the Work Resources page. 
Login with your user name [UID]@turingsafehaven.ac.uk and password [pw], as below.
![](hackmd_logon.png)

We have provided some example report templates for you which outline a structure we recommend.

Please make all your documents public so they are easy to share within your group. 
(Note that they are not really public as the server is only available inside your team’s virtual environment.)
We recommend that one person start the document, then let everyone know the URL text after the “/”

* :sparkles: TOP TIP :sparkles:: The URL for sharing a report is rather long... 
You can either write it in a textfile in the R drive (which everyone has access to) or publish the link and share that one (the published link will be much shorter. 
Anyone who has it can now click the little blue pen to go back to the editable version.

* :sparkles: TOP TIP :sparkles:: a lower case “L” and an upper case “I” will look the same! [ I /= l ]Try the one you didn’t try first time round if you don’t get to the right place.

![](hackmd_screenshot.png)

If you are working on a challenge that is below Tier 2, the environment is open so you do not have to use HackMD and can use other tools such as Overleaf, if you prefer. 
You can use our HackMD templates to help you structure the report.

## Section 4.7. Accessing the data and exporting figures

The data can be found in the R drive on the Windows Azure environment.
Everyone in your group will be able to access it, so please make a copy of it to your own desktop or working directory. You can use Windows File Explorer to move data within the Windows environment.

You can transfer the data to the Linux environment using the WinSCP app. (See Appendix A)
To access the data science VM’s file system, enter user name [UID] and password [pw] into the login mask, as shown below, and confirm with “login”.
![](WinSCP_logon.png)

* :sparkles: TOP TIP :sparkles:: Although the default says not to save the password – you’re in a super secure environment so your life will be easier if you do save it.

You can now drag and drop any files between the data science VM and the Windows Azure environment, as in the screenshot below.
![](WinSCP_screenshot.png)

## Section 4.8. Creating and presenting the report-out slides for Friday

If you are in one of the Tier 2 level challenges:
To create the presentation slides, go to the “Presentation server” on the Work Resources list and then open the Open Office icon on the Windows desktop.
An example template is provided for you in the windows Azure environment (shared drive).

You won't be able to access the compute virtual machines from the windows desktop. 
That means all figures etc needed for the presentation must be moved off the compute VM(s) onto the network fileshares.
As a nice side effect of this move to the network file shares, you'll also be moving the outputs you want to save to persistent storage! Once the compute virtual machines are gone - on Friday afternoon - they will be gone forever. 
Please do this early and often through the week (not just for the presentation.)

The presentations on Friday will be given from *inside* the secure environment. 
This means you don't have to be too careful about protecting any sensitive analyses or results you have created. It also means you can show live demos if needed.

It’s important to note that the presentation will probably be slightly laggy (there will be a lot of people using the wifi in the Enigma room during your presentation). 
It probably won't be a problem for your slides, but if you show movies or demo code there's a risk - as always - that they won't play as well as you'd hoped. 
Be prepared for this outcome and be able to talk about what the audience would see. 
You do not have time to try to fix the demo during your presentation. 
And that’s ok! 
You can always show the demo to the challenge owners in a quiet space after lunchtime.

If you are in one of the Tier 0/1 level challenges:
You do not need to use the above instructions as it is an open environment.  
Your facilitator has an example presentation template which your team can use. 

## Section 4.9. Outputs from the week

We will close down the compute virtual machines on the Friday afternoon.

That means that anything that is a valuable output of the week should be stored in the persistent storage area - shared drive - rather than your local user storage, OR in the GitLab repository.

Make sure that every piece of code or processed dataset you think might be at all useful is stored in a GitLab repository within the secure environment.
**Should we be encourgaing people to put data in GitLab...?**

Everything that is not stored in a GitLab repository on Friday lunchtime will be DESTROYED FOR EVER.

Please do this early and often through the week (not just for the presentation.)

The folders will be:
* Presentation
* Transformed data/derived data
* Report
* ???? **UPDATE**

## Acknowledgments

Based on an initial document by Kirstie Whitaker.
Updated by Catherine Lawrence, Franz Király, Martin O’Reilly, and Sebastian Vollmer.
 

## Appendix A. Migrating to a new data science VM post package update 

Important: please listen to your facilitators who will explicitly update you on VM updates and potential additional instructions specific to the migration. 

Do not attempt to migrate to a new data science VM before it has been officially authorized or recommended by your facilitator, as it might result in loss of work or data.

For each iteration of package updates, a new data science VM will be deployed into the Azure environment.

User access credentials [UID] and [pw] remain the same; the IP address [IP] changes in a systematic way. 
Each package update increments the last IP block “160” by one. That is, the first VM’s address is 10.250.sth.160, the address of the first update is 10.250.sth.161, of the second update 10.250.sth.162, and so on.
Apart from the change in IP address, the VM itself will behave the same. 

Local availability of a data copy file volume, usage of Gitlab, HackMD, etc will be unaffected by the VM update.

To access an updated VM, use the “custom VM (desktop) app” instead of the “shared VM (desktop) app”. 
This is exactly as in Section 4.4, with the onnly difference that in each log-in, you have to provide the updated VM’s [IP].
Prior to initial use, you will also have to follow the first-time set-up instructions by SSH-ing in via the “custom VM (SSH) app” instead of the “shared VM (SH) app”, following instructions as in Section 4.3, with the onnly difference that in each log-in, you have to provide the updated VM’s [IP].

Any local files that you have created in older VMs – e.g., analysis scripts, notes, derived data – will have to be manually transferred and are not automatically available in a newer VM. 

Three options to transfer files:
* Use WinSCP for drag-and-drop file transfer, as in Section 4.7. First transfer from the old [IP] to the Windows environment, then transfer from Windows environment to new [IP].
* Use command line SCP for direct transfer from old [IP] to new [IP]. The data science VMs are able to see each other in the network.
* Push your partial work to Gitlab from a local git repository on the old VM, and the pull your work into a local git repository on the new VM. This is *not* recommended for figures or files above a size of 1MB as it will clutter Gitlab, please use only for code and other text files, or small figures/data.
