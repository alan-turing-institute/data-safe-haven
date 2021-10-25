# Suppliers and Software Policy

What Software is available in the Data Safe Haven Virtual Machines? (DSVM)
The DSVM’s currently run the below operating system:

+ Ubuntu 20.04 LTS release

The DSVM will also come with the latest version of each of the below software packages (Note that the version is defined at build time, but any packages installed using apt are additionally updated to the latest version available at deploy time).
It is easiest to update DSVMs by removing an existing VM and redeploying. The data, shared and home directories will be left untouched by this process.
It is also possible to ingress updated software packages and update in place on a running DSVMs. This is only done in the case of essential security fixes where the project cannot afford the downtime involved in a redeploy.

Programming languages

+ Microsoft .NET framework
+ gcc compilers
+ Java
+ Julia (plus common data science libraries)
+ Python (plus common data science libraries)
+ R (plus common data science libraries)
+ scala
+ spark-shell

Editors/IDEs

+ atom
+ emacs
+ nano
+ PyCharm
+ RStudio
+ vim
+ Visual Studio code

Presentation tools

+ LaTeX
+ LibreOffice

Development/data science tools

+ Azure Data Studio
+ DBeaver
+ Firefox
+ git
+ psql
+ sqlcmd
+ weka

There is currently no unsupported software allowed on the DSVM, a supported operating system and all updated software are installed as part of the build process for the VM.

How do we handle suppliers having access to personal information? (think this probably needs rephrasing?)

Microsoft (Azure Cloud Infrastructure):

The only supplier who we use to support the storage of personal information is Microsoft Azure. However, although Microsoft supplies the infrastructure for the Data Safe Haven, their staff are not able to access customer data

The Data Safe Haven is designed so that we have control over who has access to our Data and guarantee that what Microsoft promises to us is true surrounding who has access to data with the below policies/certification

+ [Access to customer data by Microsoft operations and support personnel is denied by default](https://docs.microsoft.com/en-us/azure/security/fundamentals/protection-customer-data)
  + From link above: 'Access to customer data by Microsoft operations and support personnel is denied by default. When access to data related to a support case is granted, it is only granted using a just-in-time (JIT) model using policies that are audited and vetted against our compliance and privacy policies.'
+ Azure is [ISO/IEC 27701 certified](https://azure.microsoft.com/en-gb/blog/azure-is-now-certified-for-the-iso-iec-27701-privacy-standard/)
  + 'Schellman & Company LLC issued a certificate of registration for ISO/IEC 27701:2019 that covers the requirements, controls, and guidelines for implementing a privacy information security management system as an extension to ISO/IEC 27001:2013 for privacy management as a personally identifiable information (PII) processor relevant to the information security management system supporting Microsoft Azure, Dynamics, and other online services that are deployed in Azure Public, Government cloud, and Germany Cloud, including their development, operations, and infrastructures and their associated security, privacy, and compliance per the statement of applicability version 2019-02. A copy of the certification is available on the Service Trust Portal.'

DSPT Requirements breakdown:

+ 8.1.1: What Software do you use?

  + Ubuntu 20.04 LTS release
  The DSVM will also come with the latest version of each of the below software packages (Note that the version is defined at build time, but any packages installed using apt are additionally updated to the latest version available at deploy time).
  It is easiest to update DSVMs by removing an existing VM and redeploying. The data, shared and home directories will be left untouched by this process.
  It is also possible to ingress updated software packages and update in place on a running DSVMs. This is only done in the case of essential security fixes where the project cannot afford the downtime involved in a redeploy.

  Programming languages

  + Microsoft .NET framework
  + gcc compilers
  + Java
  + Julia (plus common data science libraries)
  + Python (plus common data science libraries)
  + R (plus common data science libraries)
  + scala
  + spark-shell

  Editors/IDEs

  + atom
  + emacs
  + nano
  + PyCharm
  + RStudio
  + vim
  + Visual Studio code

  Presentation tools

  + LaTeX
  + LibreOffice

  Development/data science tools

  + Azure Data Studio
  + DBeaver
  + Firefox
  + git
  + psql
  + sqlcmd
  + weka

+ 8.2.1: List any unsupported software prioritised to business risk

  There is currently no unsupported software allowed on the DSVM, a supported operating system and all updated software are installed as part of the build process for the VM.

+ 8.2.2: The person with overall responsibility for data security confirms that the risk of unsupported systems is being managed

  There is currently no unsupported software allowed on the DSVM, a supported operating system and all updated software are installed as part of the build process for the VM.

+ 8.3.1: How do your systems receive updates and how often?

  The DSVM will also come with the latest version of each of the below software packages (Note that the version is defined at build time, but any packages installed using apt are additionally updated to the latest version available at deploy time).
  It is easiest to update DSVMs by removing an existing VM and redeploying. The data, shared and home directories will be left untouched by this process.
  It is also possible to ingress updated software packages and update in place on a running DSVMs. This is only done in the case of essential security fixes where the project cannot afford the downtime involved in a redeploy.

+ 10.1.1: The organisation has a list of suppliers that handle personal information, products/services they deliver and contact details

  The only supplier who we use to support the storage of personal information is Microsoft Azure. However, although Microsoft supplies the infrastructure for the Data Safe Haven, their staff are not able to access customer data

+ 10.2.1 Your organisation ensures that any supplier of IT systems that could impact on the processing of personal identifiable data has the appropriate certification

  The Data Safe Haven is designed so that we have control over who has access to our Data and guarantee that what Microsoft promises to us is true surrounding who has access to data with the below policies/certification

  + [Access to customer data by Microsoft operations and support personnel is denied by default](https://docs.microsoft.com/en-us/azure/security/fundamentals/protection-customer-data)
    + From link above: 'Access to customer data by Microsoft operations and support personnel is denied by default. When access to data related to a support case is granted, it is only granted using a just-in-time (JIT) model using policies that are audited and vetted against our compliance and privacy policies.'
  + Azure is [ISO/IEC 27701 certified](https://azure.microsoft.com/en-gb/blog/azure-is-now-certified-for-the-iso-iec-27701-privacy-standard/)
    + 'Schellman & Company LLC issued a certificate of registration for ISO/IEC 27701:2019 that covers the requirements, controls, and guidelines for implementing a privacy information security management system as an extension to ISO/IEC 27001:2013 for privacy management as a personally identifiable information (PII) processor relevant to the information security management system supporting Microsoft Azure, Dynamics, and other online services that are deployed in Azure Public, Government cloud, and Germany Cloud, including their development, operations, and infrastructures and their associated security, privacy, and compliance per the statement of applicability version 2019-02. A copy of the certification is available on the Service Trust Portal.'

