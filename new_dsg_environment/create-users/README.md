# Creating new users without the app

## Create new user file (Project Investigator or Research Co-ordinator)
- Make a new copy of `UserCreate.csv`, naming it `YYYYDDMM-HHMM_UserCreate.csv`
- Add the required details for each user
  - `SamAccountName`: Log in username **without** the @domain bit). Use "firstname.lastname" format
  - `GivenName`: User's first / given name
  - `Surname`: User's last name / surname
  - `Mobile`: Phone number to use for initial password reset. This can be a landline or or mobile but must be accessible to the user when resetting their password and setting up MFA. They can add the authenticator app and / or another phone number during MFA setup and at least one MFA method must work when at the Turing.
   - `SecondaryEmail`: An existing organisational email address for the user. Not uploaded to their Safe Haven user account but needs to be added here so we reliably send the account activation emails with the right usernames to the right email addresses.
 - Send the file to IT

## User creation (Domain Admin - IT)
- Log into the Active Directory Domain Controller (DC)
- Run Powershell
- Run ".\CreateUsers.ps1 -UserFilePath '<drive/folder>UserCreate.csv' -domain dsgroupdev.co.uk -UserOUPath "OU=Safe Haven Research Users,DC=dsgroupdev,DC=co,DC=uk"
- Note: OU path must be in quotes
- Allow ADSync to replicate changes to AAD, approx 15 mins users will be on Azure AD

### Troubleshooting
#### User exists with that name
First check if that user actually already exists!

If the new user should definitely be a different user, then the following fields need to be unique for all users in the Active Directory. If they are not you will may get a "Name already in use" error.
- `SamAccountName`: Specified explicitly in the CSV file, so update to `firstname.middle.initials.lastname`
- `DistinguishedName`: Formed of `CN=<DisplayName>,<OUPath>` by Active directory on user creation. `DisplayName` is `<GivenName> <Surname>` so change this to `<GivenName> <Middle> <Initials> <Surname>`.

## Azure Portal
- Login into Azure Portal and connect to the correct AAD subscription
- Open "Azure Active Directory"
- Location "Licenses" under "Manage" section
- Open "All Products" under "Manage"
- Click "Azure Active Directory Premium P2"
- Click "Assign"
- Click "Users and groups"
- Select the users you have recently created and click "Select"
- Click "Assign" to complete the process
- Return to "Azure Active Directory" pane
- Select "Users" from "Manage" section
- Select "Multi-Factor Authentication" button
- Check the users you want to apply MFA to
- Click to "Enable"
- Close MFA console
- Users are now ready to reset password and set up MFA

## User activation
- Research Co-ordinator to email users their user ID and instructions. We can securely email users thei ruser ID as they also need access to the phone number they provided us in order to reset their password and we don't provide this in the email.

### User activation instructions
These are a summary. The user should be sent a delegate pack / guide that has fuller instructions with screenshots. Kirstie's previous guide is being updated by Ian in issue #96.

#### Reset password
For security we do not store your initial password, so you must reset it before you can log in.
1. Open a private browser session on your laptop to avoid picking up any existing Azure / Microsoft accounts you have
2. Paste the following UR into the private browser address bar - https://aka.ms/ssprsetup
3. At the login prompt enter your username (provided in the welcome email)
4. At password prompt click "Forgotten password"
5. Complete the requested information (captcha and the phone number you provided on registration)
6. Reset your password
  
#### Set up MFA
Before you can access the secure environment, you need to setup your multifactor authentication.  The authentication method can be either via a call to a mobile phone or the Microsoft Authenticator app (recommended).

##### Step 1 (if using the Microsoft authenticator app): download the app on your mobile device
The links to download the app for iOS, Android and Window mobile are:
-	iOS: http://bit.ly/iosauthenticator 
-	Android: http://bit.ly/androidauthenticator 
-	Windows mobile: http://bit.ly/windowsauthenticator

##### Step 2: Configure the multifactor authentication
1.	Open a private browser session on your laptop to avoid picking up any existing Azure / Microsoft accounts you have
2.	Enter https://aka.ms/MFASetup into the private browser address bar
3.	Login with the username provided in your welcome email and the new password you chose when you reset your password.
4.	Click “Set it up now” when prompted
5.	On the “Additional security verification” screen you have three options on how the system will contact you for verification.  Click the drop down next under “Step 1” and select the option you wish to use.
