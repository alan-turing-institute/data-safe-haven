# Creating new users without the app

## Create new user file (Project Investigator or Research Co-ordinator)
- Make a new copy of `UserCreate.csv`, naming it `YYYYDDMM-HHMM_UserCreate.csv`
- Add the required details for each user
  - Safe haven user ID (**without** the @domain bit)
  - First name
  - Last name
  - Safe haven user ID (test = xxx@dsgroupdev.co.uk / prod = xxx@turingsafehaven.ac.uk)
  - Phone number (office or mobile - used for initial password reset + MFA setup). Can add app during MFA setup but at least one method must work at Turing
- Powershell to create users (can be run by IT / Rob - IT have the script)

## User creation (Domain Admin)
- Log into the Active Directory Domain Controller (DC)
- Run Powershell
- Run `CreateUser.ps1 -Environment <Testing | Production> -UserFilePath <PathToUserFile>
- In 15 mins users will be on Azure AD
- Add "Active directory premium P2" licence to users (could likely be scripted but will be manual bulk operation in portal) Q: Can we selectively apply licence to new batches of users if we don't add everyone at once?
- Enable MFA on all user (could likely be scripted but will be manual bulk operation in portal)
- Users are now ready to reset password and set up MFA

## User activation
- Give users their user ID and instructions  - Q: Do we email in advance or do on the day with paper? A: We can email as they need access to the phone number they provided us.
  - Open a private browser session to avoid picking up any existing Azure / Microsoft accounts you have
  - Paste the following UR into the private browser address bar - https://aka.ms/ssprsetup
  - At the login prompt enter my user name
  - At password prompt click "Forgotten password"
  - Complete the requested information (captcha/my phone number)
  - Reset my password
  - Click "Login"
  - Enter user name and my new password
  - Now the MFA configuration process starts (these steps are in Kirstie's doc - add the preceding steps to this).