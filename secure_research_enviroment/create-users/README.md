# Creating new users (Project Investigator or Programme Manager)

## Creating new users using the web app

- Follow the [instructions in the webapp repository](https://github.com/alan-turing-institute/data-safe-haven-webapp/blob/master/runbooks/create-users/create-users.md) to create users.
  - Users can be created in bulk by selecting `Create User > Import user list` and uploading a spreadsheet of user details  
  - Users can also be created individually by selecting `Create User > Create Single User`
- After creating users, export the `UserCreate.csv` file
  - To export all users, select `Users > Export UserCreate.csv`
  - To export only users for a particular project, select `Projects > (Project Name) > Export UserCreate.csv`
- Send the file to IT

## Creating new users without the web app

- Make a new copy of the user details file `UserCreate.csv`, naming it `YYYYDDMM-HHMM_UserCreate.csv`
- Add the required details for each user
  - `SamAccountName`: Log in username **without** the @domain bit). Use `firstname.lastname` format
  - `GivenName`: User's first / given name
  - `Surname`: User's last name / surname
  - `Mobile`: Phone number to use for initial password reset. This must include country code in the format `+<country-code> <local number>`. Include a space between the country code and local number parts and include the leading `0` in the country code if present. This can be a landline or or mobile but must be accessible to the user when resetting their password and setting up MFA. They can add the authenticator app and / or another phone number during MFA setup and at least one MFA method must work when at the Turing.
   - `SecondaryEmail`: An existing organisational email address for the user. Not uploaded to their Safe Haven user account but needs to be added here so we reliably send the account activation emails with the right usernames to the right email addresses.
 - Send the file to IT

## User creation (Domain Admin - IT)
- Log into the Active Directory Domain Controller (DC)
- Run Powershell
- Run `.\CreateUsers.ps1 -UserFilePath "<path_to_user_details_file>" -shmId <shm-id>`, where `<shm-id>` is "test" for the test SHM and "prod" for the production SHM
- The `CreateUsers.ps1` script will trigger a sync with Azure Active Directory, but it will still take around 5 minutes for the changes to propagate.

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
- Click "Azure Active Directory Premium P1"
- Click "Assign"
- Click "Users and groups"
- Select the users you have recently created and click "Select"
- Click "Assign" to complete the process
- Return to "Azure Active Directory" pane
- Click "Users" from "Manage" section
- Click "Multi-Factor Authentication" button
- Check the box for the users you want to apply MFA to
- Click the "Enable" link in the "Quick steps" block on the right and confirm in the pop-up
- Close MFA console
- Users are now ready to reset password and set up MFA

## User activation
- Research Co-ordinator to email users their user ID and instructions. We can securely email users their user ID as they also need access to the phone number they provided us in order to reset their password and we don't provide this in the email.

### User activation instructions
These are a summary. The user should be sent a delegate pack / guide that has fuller instructions with screenshots. Kirstie's previous guide is being updated by Ian in issue #96.

#### Reset password
For security we do not store your initial password, so you must reset it before you can log in.
1. Open a private/incognito browser session on your laptop to avoid picking up any existing Azure / Microsoft accounts you have
2. Paste the following UR into the private/incognito browser address bar - https://aka.ms/ssprsetup
3. At the login prompt enter your username (provided in the welcome email)
4. At password prompt click "Forgotten password"
5. Complete the requested information (captcha and the phone number you provided on registration).
6. Generate a new password using the [Secure Password
Generator we set up](https://passwordsgenerator.net/?length=20&symbols=0&numbers=1&lowercase=1&uppercase=1&similar=1&ambiguous=0&client=1&autoselect=1).
7. Reset your password

**Note**: Do **not** use special characters or symbols in your password if you
prefer to pass on using the Secure Password Generator. If you include symbols,
you may be unable to type them in the virtual keyboard to access the secure
environment. Choose an alphanumeric password with minimum length of 12
characters, with at least one of each:

- uppercase character
- lowercase character
- number

**Note**: During this process, you will need to provide a phone number for
account recovery. This is **not** MFA. You still need to set up MFA in the next
section, otherwise you will be unable to launch any apps.

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
