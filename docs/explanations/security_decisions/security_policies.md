# Additional Security Policies for Data Safe Haven

Overview:

Before data is imported into a DSH will initially go through an assessment process to classify it into one of 5 sensitivity tiers (from least sensitive at Tier 0, to most sensitive at Tier 4). This classification is conducted by the dataset provider’s representative, The research project lead (Investigator) and an independent adviser (Referee). Currently, the data safe haven only covers data categorised as tier 2 or 3. A full overview of the classification process can be found [here](https://github.com/alan-turing-institute/data-safe-haven/blob/master/docs/explanations/classification/classification-overview.md).

Technical Controls in the DSH to prevent secure information being removed:

Any dataset that is rated as Tier 2 or above (which would include personal data that is not publicly available or commercially/politically/legally sensitive data) have technical controls in place to ensure data can’t be incorrectly removed from the DSH.

These cover three main areas:

+ There are technical controls that ensures you can’t copy and paste between the environment and outside
+ You can’t connect to the internet from inside the environment
+ You can’t connect to Azure services (e.g Azure file storage) apart from the one which are secured inside the environment.

Business Continuity Plan for DSH in case of data security incident, failure or compromise

Data security incident process:

The DSH follows the Turing Institute’s data security incident process which can be found [here](https://turingcomplete.topdesk.net/tas/public/ssp/content/detail/knowledgeitem?origin=sspTile&unid=6c4590be2c74466497f5239915717621&from=7c877b26-e14b-400c-9097-ae99267258fe).

As an additional measure, when a potential data security incident was identified, the affected DSH would be shut down to ensure the security of the data. An investigation would be conducted simultaneously with the Data Security Team to identify any other potentially breached DSH’s and also shut these down.

Data back-up policy:

As the Data Safe Haven is not the canonical source of data a decision has been made to not back-up the data stored in the DSH.

The data safe haven is a secure environment to store the data in, and the risk of needing to reimport the data is minimal. As any backup copy of the data would decrease the security of the data, a security decision has been taken that it is preferable to have to reimport the data from the original source in the event that it would need to be restored.

Requirements:

+ 1.6.2: There are technical controls that prevent information from being inappropriately copied or downloaded

    Any dataset that is rated as Tier 2 or above (which would include personal data that is not publicly available or commercially/politically/legally sensitive data) have technical controls in place to ensure data can’t be incorrectly removed from the DSH.
    These cover three main areas:
        + There are technical controls that ensures you can’t copy and paste between the environment and outside
        + You can’t connect to the internet from inside the environment
        + You can’t connect to Azure services (e.g Azure file storage) apart from the one which are secured inside the environment.

+ 7.1.2: Do you have a business continuity plan in place to ensure continuity of services in event of data security incident, failure or compromise?

    Data security incident process:

    The DSH follows the Turing Institute’s data security incident process which can be found [here](https://turingcomplete.topdesk.net/tas/public/ssp/content/detail/knowledgeitem?origin=sspTile&unid=6c4590be2c74466497f5239915717621&from=7c877b26-e14b-400c-9097-ae99267258fe)..

    As an additional measure, when a potential data security incident was identified, the affected DSH would be shut down to ensure the security of the data. An investigation would be conducted simultaneously with the Data Security Team to identify any other potentially breached DSH’s and also shut these down.

+ 7.2.1: Explain how your data security incident response and management plan has been tested to ensure all parties understand roles and responsibilities as part of the plan

    The DSH follows the Turing Institute’s data security incident process which can be found [here](https://turingcomplete.topdesk.net/tas/public/ssp/content/detail/knowledgeitem?origin=sspTile&unid=6c4590be2c74466497f5239915717621&from=7c877b26-e14b-400c-9097-ae99267258fe)..

+ 7.3.4: Suitable backups are made, tested, documented and reviewed

    Data back-up policy:

    As the Data Safe Haven is not the canonical source of data a decision has been made to not back-up the data stored in the DSH.

    The data safe haven is a secure environment to store the data in, and the risk of needing to reimport the data is minimal. As any backup copy of the data would decrease the security of the data, a security decision has been taken that it is preferable to have to reimport the data from the original source in the event that it would need to be restored.

+ 7.3.5: When did you last successfully restore from backup?

    Data back-up policy:

    As the Data Safe Haven is not the canonical source of data a decision has been made to not back-up the data stored in the DSH.

    The data safe haven is a secure environment to store the data in, and the risk of needing to reimport the data is minimal. As any backup copy of the data would decrease the security of the data, a security decision has been taken that it is preferable to have to reimport the data from the original source in the event that it would need to be restored.
