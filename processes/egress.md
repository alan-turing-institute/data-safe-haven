# Intro
Prior to publishing reports/papers, code or data that is currently being stored within the Turing Safe Haven a declassification process must be followed. This is to ensure that any material that is to be made public is free of any confidential material. If commercially sensitive information is published this could lead to reputational or financial repercussions. If personal or personal sensitive information is leaked then it could lead to legal repercussions (See the [ICO Website](https://ico.org.uk/for-organisations/guide-to-data-protection/guide-to-the-general-data-protection-regulation-gdpr/key-definitions/what-is-personal-data/) for more information on this). 

The process is divided into two stages: declassification and then egress.

# Declassification
Much like the process for initial classification of the project, the same three representatives (The investigator, dataset provider representative and the referee)  who classified the project at the beginning will need to again individually conduct the same assessment on the results. Declassification should take place within the Turing Safe Haven environment.  `do we want to mention where? Data Set provider might need to be able to do this from their organisation if unable to come to Turing or other "safe access point" `

Following the flowchart for tier selection, the representatives should make note of any item that they would consider makes the results a tier 2 or above classification. If all three representatives mutually return a tier 0 or 1 classification then the results can be safely egressed. However, if there are differences, or if the agreed classification is 2 or above, a face to face discussion should be arranged. An email discussion is strongly not recommended here as the conversation may need to discuss sensitive information.

## Items for discussion in the case of mismatched classification
This discussion should focus on what features of the results prompted the different classification. Agreement must be made. In the case of two competing arguments, the reason for the higher classification should take precedent to err on the side of caution.

## Items for discussion when the classification is tier 2 or higher
Each item that was deemed to be sensitive at tier 2 or higher will need to be reviewed with the purpose of how it will be represented in its public form. The representatives will need to decided and collectively agree to:
* anonymise or obfuscate the item
* aggregate, restructure or reword the item so as it does not reveal the sensitive detail
* remove the item all together

Care should be made to ensure that whichever option is chosen for each item, the results do not lose the overall meaning.

## Data Study Group specific processes
The same procedure will be followed as above, but only for the report. Code and derived data will be securely transferred to the Data Set Provider. They will have X weeks to review the code and inform Turing if there is anything sensitive within it that needs to be removed. Derived data will not be published at all, unless tier 1 or 0 and agreed with the Data Set Provider at the beginning of the project

With agreement on how all the sensitive items will be safely represented in the results, declassification will have been achieved. 

# Egress
With the results declassified, they will be transferred to the Data Set Provider and any other party involved in the project. Please refer to the three methods of transferring data back to a provider [here](https://github.com/alan-turing-institute/data-safe-haven/blob/master/processes/secure-egress.md)

Within Turing, results will be archived within a locally hosted secure storage server in preparation for publication.
