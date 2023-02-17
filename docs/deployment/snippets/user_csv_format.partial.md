- Make a new copy of the user details template file from `C:\Installation\user_details_template.csv`

  ```{tip}
  We suggest naming this `YYYYDDMM-HHMM_user_details.csv` but this is up to you
  ```

- Remove the example user and add the required details for each user

    - `SamAccountName`: Log in username **without** the `@<SRE domain>` part.

      ```{tip}
      We recommend using `firstname.lastname` format.
      ```

      ```{warning}
      Ensure that `SamAccountName` has a maximum of **20 characters** from the 7-bit ASCII set (unaccented letters, numbers and some punctuation) or synchronisation will fail.
      ```

    - `GivenName`: User's first / given name

      ```{warning}
      Ensure that `GivenName` uses only characters from the 7-bit ASCII set (unaccented letters, numbers and some punctuation) or synchronisation will fail.
      ```

    - `Surname`: User's last name / surname

      ```{warning}
      Ensure that `Surname` uses only characters from the 7-bit ASCII set (unaccented letters, numbers and some punctuation) or synchronisation will fail.
      ```

    - `Mobile`: Phone number to use for initial password reset.

      ```{important}
      - This must include country code in the format `+<country-code> <local number>` (e.g. `+44 7123456789`).
      - Include a space between the country code and local number parts but no other spaces.
      - Remove the leading `0` from local number if present.
      - This can be a landline or or mobile but must be accessible to the user when resetting their password and setting up MFA.
      - Users can add the authenticator app and/or additional phone numbers during MFA self-registration.
      ```

    - `SecondaryEmail`: An existing organisational email address for the user.

      ```{note}
      This is **not** uploaded to their Data Safe Haven user account but is needed when sending account activation messages.
      ```

    - `GroupName`: [Optional] The name of the Active Directory security group(s) that the users should be added to (eg. `SG SANDBOX Research Users` ). You can also set this manually later on (see {ref}`adding_users_manually`).

      ```{tip}
      If the user needs to be added to multiple groups, separate them with a pipe-character ( `|` ).
      ```
