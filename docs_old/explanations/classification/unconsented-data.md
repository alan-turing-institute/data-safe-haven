# Unconsented data

This document summarises some considerations that must be taken into account when dealing with **unconsented patient data**, but similar ideas may apply to the use of non-health related unconsented individual-level data. Unconsented patient data typically consists of routine electronic health records (EHR) that are collected by health providers (e.g. NHS). EHRs include but are not restricted to: blood test results, fMRI scans and free text notes recorded by medical practitioners. These are a powerful, low cost source of data that is expected to play a central role in the development of precision medicine strategies. However, working with unconsented patient data introduces a variety of challenges, covering data ingress, processing and egress.

## Data ingress

From May 2018, GDPR has introduced strict regulations regarding the use of personal data. In particular, [Art 9](https://gdpr-info.eu/art-9-gdpr/) states that:

> Processing of personal data revealing racial or ethnic origin, political opinions, religious or philosophical beliefs, or trade union membership, and the processing of genetic data, biometric data for the purpose of uniquely identifying a natural person, data concerning health or data concerning a natural person’s sex life or sexual orientation shall be prohibited.

Despite this, lawful processing of such information is allowed when *explicit consent* has been given by the individual. When using EHRs, however, explicit consent is typically not practical - particularly when dealing with large patient cohorts. As such, prior to data ingress, it is important to establish that the study satisfies one of the conditions required for lawful processing of personal information [see Art 9.2](https://gdpr-info.eu/art-9-gdpr/). In the case of medical data, the Health Research Authority has issued [guidelines](https://www.hra.nhs.uk/hra-guidance-general-data-protection-regulation/) for the lawful use of unconsented data. In particular, it states that *the legal basis is determined by the type of organisation that is the data controller for the processing*:

+ *For universities, NHS organisations, Research Council institutes or [other public authority](http://www.legislation.gov.uk/ukpga/2000/36/schedule/1) the processing of personal data for research should be a ‘task in the public interest’*.
+ *For commercial companies and charitable research organisations the processing of personal data for research should be undertaken within ‘legitimate interests’*.

As such, prior to data ingress, it is important that researchers (or commercial partners) provide valid evidence regarding these conditions being satisfied. The source of this information **must** be external to the research group, and depends on who is the data provider.

+ For data provided by a single NHS Trust/Board: approval from local Caldicott Guardian

+ For data provided by multiple NHS Trusts/Boards (Scotland): approval from the Public Benefit and Privacy Panel fro Health and Social Care (PBPP)

+ For data provided by multiple NHS Trusts/Boards (England): approval from NHS Digital

In addition to this, the data provider must provide evidence to certify that the data does not include personal information for patients who have explicitly requested to [opt-out](https://digital.nhs.uk/about-nhs-digital/our-work/keeping-patient-data-safe/how-we-look-after-your-health-and-care-information/your-information-choices/opting-out-of-sharing-your-confidential-patient-information) from their data being used for purposes that are not directly related to their own care.

Finally, whenever possible, the amount of identifiable personal information must be minimised prior to data ingress. This includes, but it is not restricted to: name, postcode, NHS number (England) and CHI number (Scotland). Moreover, a formal data transfer agreement between the data provider and the Institute must be in place.

## Data access

**NOTE: This is partially inspired by the requirements set for the University of Edinburgh's DSH.**

The following conditions are requirements to access unconsented patient data:

+ Completion and approval of at least one of the following accredited courses:
  + MRC Research Data and Confidentiality: https://byglearning.com/mrcrsc-lms/course/index.php?categoryid=1
  + ADRC SURE Training: http://adrc-scotland-sure-training.weebly.com

An electronic certificate will be retained by the Institute as a proof of training. The certificate must be dated no longer than **3 months** prior to the start of the data access. If the data access period exceeds *one year*, the researcher will need to provide a new certificate (one per each year of data access).

**Note: the MRC training listed above is currently unavailable, but a replacement course is under preparation. Additionally, we might consider alternative accredited courses that can be added in this list.**

+ The researcher must be named as an approved data user by the data controller (Caldicott Guardian, PBPP or NHS digital depending on the data source; see data ingress conditions). The data controller can remove a researcher from the list of approved data users at any time throughout the project.

+ The researcher must be an employee of the Turing. Alternatively, the researcher must hold a valid Turing visiting researcher contract, in which the project and the data access conditions are stated. Contact details for the researcher's line manager (or supervisor, in the case of PhD students) must be provided in this contract.

## Data processing

During the data access period, the following conditions must be satisfied:

+ At all times, researchers must abide to the [Data Protection Act 2018](http://www.legislation.gov.uk/ukpga/2018/12/contents/enacted).

+ The data can **only** be used for purposes that are approved by the data controller (Caldicott Guardian, PBPP or NHS digital depending on the data source; see data ingress conditions), as specified in the data access agreement.

+ Researchers must never attempt to uncover the identify of any subject present in the data (including himself/herself).

+ Researcher must never allow data access (even visual inspection in a computer screen) to people that have not been approved by the data controller.
