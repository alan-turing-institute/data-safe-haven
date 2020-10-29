# Taking data and software out of the Turing Safe Haven

Prior to publishing reports/papers, code or data that is currently being stored within the Turing Safe Haven a reclassification process must be followed. This is to ensure that any material that is to be made public is free of any confidential material. If commercially sensitive information is published this could lead to reputational or financial repercussions. If personal or personal sensitive information is leaked then it could lead to legal repercussions (See the [ICO Website](https://ico.org.uk/for-organisations/guide-to-data-protection/guide-to-the-general-data-protection-regulation-gdpr/key-definitions/what-is-personal-data/) for more information on this).

The process is divided into two stages: reclassification and then egress.

## Reclassification

It is a central premise of our model that any output data is classified as a new work package, separate from the work package that it is derived from.

This is the case whether the output data is for publication (in which case the output data should be Tier 1 or Tier 0) or will be analysed in a new Environment.

Much like the process for initial classification of the project, the same representatives (the investigator, dataset provider representative and the referee)  who classified the project at the beginning will need to again individually conduct the same assessment on the results. We recommend that, whenever data egress is conducted with the intent of establishing a new environment for further research, a Referee is consulted to ensure balance. Reclassification should take place within the Turing Safe Haven environment.

As a convenience, if derived data resulting from analysis is in a form which has been agreed with Dataset Provider Representatives at the initial classification stage – for example, a summary statistic which was the intended output for analysis of a sensitive dataset – then this re-classification may be pre-approved.

Following the flowchart for tier selection, the representatives should make note of any item that they would consider makes the results a tier 2 or above classification. If all three representatives mutually return a tier 0 or 1 classification then the results can be safely removed from the secure research environment. However, if there are differences, or if the agreed classification is 2 or above, a face to face discussion should be arranged. An email discussion is strongly not recommended here as the conversation may need to discuss sensitive information.

### Items for discussion in the case of mismatched classification

This discussion should focus on what features of the results prompted the different classification. The aim of this discussion is for the reviewers to come to an agreement on the appropriate classification. If no agreement can be reached, then the highest of the proposed classifications should be used.

### Items for discussion when the classification is tier 2 or higher

Each item that was deemed to be sensitive at tier 2 or higher will need to be reviewed with the purpose of how it will be represented in its public form. The representatives will need to decided and collectively agree to:

+ further pseudonymise the item
+ aggregate, restructure or reword the item so as it does not reveal the sensitive detail
+ remove the item all together

Care should be made to ensure that whichever option is chosen for each item, the results do not lose the overall meaning.

## Egress of code and data

In all cases, classification of a work package at the point of egress should be done with all parties fully aware of the analytical processes which created the derived data from the initial work package. These processes should be well documented and ideally fully reproducible (e.g. as code that can be run to regenerate the exact output data from the input data).

### Egress of generated datasets

The initial classification of a work package may be for the purpose of ingress into an initial high-tier environment to carry out anonymisation, pseudonymisation or synthetic data generation work, with the intention of making the data appropriate for treatment in a lower-tier Environment. In this case, the egress review should include validation that the anonymised, pseudonymised or synthetic data undergoes its own classification process for analysis that will be performed in the "downstream" work package.

The project member who triggers the declassification process should explain their reasons for believing that the script does indeed produce data of the appropriate tier; and describe the structure of the data in sufficient detail to allow the reviewers to understand the action of the script. The review should cover the anonymisation, pseudonymisation or synthetic data generation process, including all associated code.

### Egress of secure materials back to a data provider

It may be the case that Tier 2 or above items need to be removed from the secure compute environment and returned to a data provider. Due to the sensitivity of the data we will only ever release this data to the original data owner that sent it to us in the first place, or if it is to comply with law. In such cases, written notification should be given by the data provider. The data should be encrypted with a strong encryption and secure key or passphrase before being transferred.

## Management of reclassified materials pending publication

Within Turing, reclassified results at Tier 1 or below may be archived using normal business information processes in preparation for publication.

## Egress methods

The three methods of transferring data back to a provider are the following:

### Azure

The easiest way to retrieve your data is to use the Azure Storage Explorer, [here](<https://azure.microsoft.com/en-gb/features/storage-explorer/>). We will put the encrypted data on a new storage account that you will only be able to access using a secret link.
We will then send you in an encrypted email the secret link to access the data along with the key to decrypt the data after transit. For additional security these two items can be delivered separately.

### SFTP

We will send you a encrypted email with the address of the FTP server and a key to access the secure area. We will then notify you that the data is ready to download. We will then send the key via a separate secure channel to unlock the data.

### Physically bring in a disk

Alternatively, you can bring us a physical device. Please let us know when you will come to the Turing to deliver the data. We will then send the key via a separate secure channel to unlock the data.
