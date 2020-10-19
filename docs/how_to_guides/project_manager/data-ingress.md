# Data Ingress Process

This document details the ways of importing data to the Turing Safe Haven. By data we refer to any digital document, file, dataset in any format known and to be known.

## Definitions

The **staging area** is the file storage location at the Turing Institute that is visible to the data owner.
The data owner will transfer the data to this location.
A restricted number of Turing staff will have access to the staging area and data will be deleted from the staging area as soon as it has been transferred to the Data Safe Haven.

The **secure data area** is the workspace within the Azure infrastructure that contains the data and analysis environment.
It is in the secure data area that approved researchers will have access to the data.
Access will be managed via the user roles.
Note that most researchers will only have read access to this data to avoid accidental deletion.

The **secure document store** is the single volume within the Azure infrastructure that contains the definitive copy of the signed data transfer agreements. (Do we ever use this?)

The **golden copy** is the exact copy of the data received from the data owner and stored in secure data area.

## Step 1: Categorise the data into one of the defined tiers

Remember that Tier-0 is the least sensitive data tier (public data) and Tier-4 the most sensitive (SECRET). If there are mixed data sensitivities in the complete data set then the whole data set must be assigned to the **most sensitive** data tier.

## Step 2: Complete data sharing paperwork

The appropriate legal paperwork needs to be completed to ensure that a data sharing agreement is in place.
This step should also cover ethical considerations of sharing the data.
The project may need to be approved by the Turing Ethics Advisory Group (EAG; more information can be found at the [Turing Institute intranet site](https://turingcomplete.topdesk.net/tas/public/ssp/content/detail/service?unid=cb5e35246f474d1f90abae8ea262338c)) and permission to use the data (including [unconsented patient data](../../explanations/classification/unconsented-data.md)) should be obtained.

The data sharing paperwork must make very clear the tier to which the dataset has been assigned.

## Step 3: Store the signed documents in a secure location

All documents detailed in step 2 should be available in the secure document store.
They certify that the users are allowed to have access to the specified data, and to process it in agreed ways.

A likely workflow is that a Business Development Manager or Programme Manager will place the authorised copy of the data sharing agreement in that location.

The version of the documents stored in the secure document store are the definitive ones.
There will be a COPY (labelled as such) stored in the same location as the data for user reference.
There should be a hash to confirm that the documents are indeed the same.

## Step 4: Transfer from data owner to Turing

Different processes should be followed depending on the tier to which the data has been assigned (as described in the [data classification process](../..//explanations/classification/classification-overview.md).

It is the responsibility of the Turing staff member conducting this step to ensure that they are following the appropriate process for the assigned data classification tier.

### Tier 3: Sensitive

The [preferred secure transfer process](#preferred-secure-transfer-process) should be followed by default.
If it is not possible to use [secure copy protocol (SCP) transfer](https://en.wikipedia.org/wiki/Secure_copy) then the [alternate secure transfer process](#alternate-secure-transfer-process) should be followed.

If the data are too large to transfer over the internet then the [encrypted transfer for large data process](#encrypted-transfer-for-large-data-process) should be followed.

Note that tier 3 data in physical form will not be accepted by the Turing Institute.
It is the responsibility of the data owner to digitise the files.

#### Preferred secure transfer process

The data should be transferred to the staging area via [SCP transfer](https://en.wikipedia.org/wiki/Secure_copy) (not [SFTP](https://en.wikipedia.org/wiki/SSH_File_Transfer_Protocol)) from the data owner to the Turing Institute.

In order to set up the transfer, a secure email (via [Egress](https://www.egress.com/what-we-offer/email-and-file-protection) which is [certified](https://www.ncsc.gov.uk/scheme/commercial-product-assurance-cpa) by the UK National Cyber Security Centre (NCSC)) should be sent to the Data Owner by Turing to provide the access details and instructions for how they can load their data to the staging area in order for Turing to receive it.
The following Turing staff members are authorised to send this email: Head of IT and Security, IT team member, Programme Manager, REG team member.

On receipt of this email the data owner will need to provide Turing with a public IP address for a member of the Turing to whitelist in order for the files to be transferred.
The whitelisting should be for a restricted period; the length of the period will be decided on a case-by-case basis depending on - for example - how responsive the Data Owner is.
**The length of the period will not exceed one week.**
If the data is not transferred during this period, the whitelisting will need to be re-set up.
The following Turing staff members are authorised to whitelist the IP address: Head of IT and Security, IT team member, Programme Manager, REG team member.

#### Alternate secure transfer process

If the SCP transfer process described above is not possible, for example if the data owner has restrictions about what tools they are able to use or download on their devices, the following process may be used.

The data owner must first encrypt the data, using a strong encryption method to be agreed by REG team - for example using [VeraCrypt](https://www.veracrypt.fr/en/Home.html) - with a strong password.
The data owner will then send the encrypted data over normal email or via a website upload. The encryption key must be communicated from the data owner to a Turing staff member verbally over the phone or in person.
**The key must not be communicated over the same channel through which the encrypted data was sent**.
The following Turing staff members are authorised to receive the encryption key: Head of IT and Security, IT team member, Programme Manager, REG team member.

A member of the Turing Institute will then upload the data to the staging area.
If the data was encrypted when it was received it should **remain encrypted until after transfer to the secure data area**.

#### Encrypted transfer for large data process

If the data is so large that it cannot be sent over the internet, the following process may be used.

The data owner must first encrypt the data, using a strong encryption method to be agreed by REG team - for example using [VeraCrypt](https://www.veracrypt.fr/en/Home.html) - with a strong password. Turing will accept delivery of the data via an encrypted hard drive.
The encryption key must be communicated from the data owner to a Turing staff member verbally over the phone or in person.
**The key must not be delivered in the same physical package as the encrypted hard drive**.
The following Turing staff members are authorised to receive the encrypted hard drive: Head of IT and Security, IT team member, Programme Manager, REG team member.

A member of the Turing Institute will then upload the data to the staging area.
If the data was encrypted when it was received it should **remain encrypted in the staging area until after transfer to the secure data area**.

### Tier 2: Official

For this type of OFFICIAL data; the processes are be the same as for [Tier 3](#tier-3-sensitive) above, except IP whitelisting for SCP is not required.

Note that tier 2 data in physical form will not be accepted by the Turing Institute.
It is the responsibility of the data owner to digitise the files.

### Tier 1: Publishable

The same transfer process as [Tier 2](#tier-3-official) is available to the data owners.

Alternatively they may share the data via a the file sharing site of their choice (for example Dropbox, Box, Google Drive, SharePoint).
They are recommended - but not required - to password protect these files.
If a password is used it should be shared with Turing via a different channel that the one sharing the URL to the data.

One supported example for the file transfer is for Turing to set up an Office365 Group and add the data owners as members of the group ("external guests").
The data can then be uploaded to the SharePoint site associated with the group.

A member of the Turing Institute will then upload the data to the staging area.

Data **should not be sent over email** to avoid the risk of individuals at Turing unintentionally retaining the data for longer than intended.
This also reduces risk of accidental pre-publication forwarding of data sets.

#### Physical data format

If data at tier 1 or lower comes in physical form - for example as sheets of paper - they should be delivered to the Turing by a trusted party of the data owner.
Each item in the physical dataset will be scanned to create a digital copy and transferred directly to a SharePoint folder from the scanner.
The scanned files will then be transferred to the staging area.
The following Turing staff members are authorised to scan the physical data and transfer it to the staging area: Head of IT and Security, IT team member, Programme Manager, REG team member.

### Tier 0: Public

This is publicly available, open data, and as such is likely to be hosted on a public website and can therefore simply be downloaded directly to the staging area.

## Step 5: Transfer from staging area to secure data area

Once the data is received at Turing a Turing staff member should transfer the data to the secure analysis environment in Azure.
There are two ways of uploading data to the system: through a web interface where files can be selected and tranferred to the secure data area and copying them using secure copy protocol (SCP).
The following Turing staff members are authorised to transfer the data: Head of IT and Security, IT team member, Programme Manager, REG team member.

At this point a copy of the signed data transfer documents - saved in the secure document store - should be made in the secure data area.
These copies should be marked as COPIES.
There should be a hash to confirm that the documents are indeed the same.

It is the responsibility of the Turing staff member conducting this step to ensure that they are following the appropriate process for the assigned data classification tier.

This transferred version of the data is the **golden copy** and can not be edited once placed in the secure data area.

### Web Interface

Available using OSX/Windows/GNU/Linux.

The Turing staff member who is transferring the data can log in and move datasets and files from the staging area to the secure data area.

### Command line via secure copy protocol

Using the [SCP](https://en.wikipedia.org/wiki/Secure_copy) protocol the data can be uploaded by using the IP of the secure data area.
The Turing staff member who is transferring the data can connect to the server using a secure shell (`ssh` protocol).

## Step 6: Confirm that the data in the secure data area is the same as that transferred from the Data Owner

A Turing staff member must sent an [integrity verification](https://en.wikipedia.org/wiki/File_verification) proof for each file uploaded to the data owner.
This will include decrypting the data where necessary.
This step is to verify that the files in the secure data area are the same as the original data that is stored with the Data Owner.

> TO DO: Write up instructions on how to create the verification for both Turing and data owners.

## Step 7: Clear the staging area

All copies of the data in the staging area must be deleted after the integrity verification has been completed.

## Step 8: Test the integrity of the data

A member of the Turing Research Engineering team will run all the necessary tests to ensure the integrity of the dataset.
After the revision a report is generated informing the content and metadata of the data provided by the user in the staging area.
Any changes in the data should be versioned.
All the transformation and exploration process should be versioned.
At the beginning and the end of each session a hash with the code and data should be generated to verify authenticity of the work on the data.
Once all tests have been complied the resultant data will be ready to go to the secure data area.
Data in this area can be deleted except for the latest version of the data, that in the case of no longer be needed should be archived along with the code, reports, and policy checks.

