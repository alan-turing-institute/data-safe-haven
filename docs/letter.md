One-pager for comms pack for external reviewers

The Alan Turing Institute, in collaboration with the Universities of Cambridge, 
Edinburgh, Manchester and St Andrew’s, and VWV, are creating a framework to allow researchers 
to simply and securely conduct analysis on sensitive datasets in high-compute and productive environments. 
We are calling this project “Data Safe Havens”. We are sharing with you our policies document describing
our framework of recommendations in the hope that you will support us to develop it further and move towards
widespread implementation.

Currently, research institutions implement varying degrees of security controls for environments in which
researchers can handle sensitive data. If these are too loose, there are obvious consequences for potential breach
– however, they are more often overly strict and imprecisely applied. This makes research slow and unproductive,
and often has the unintended consequence of inspiring researchers to come up with creative workarounds, thus 
ctually reducing security. Even the best systems, if operated in isolation, make it difficult to compare risk
profiles and conduct joint research with other organisations.

We are therefore constructing a framework for conducting research on sensitive datasets which we hope to be
widely adopted, thus aligning research methods across institutions, and increasing trust and interoperability
by ensuring that institutions meet the same baseline standards for security classification. The key elements
of our proposal are as follows:

Clearly defined security tiers: We identify five tiers of security classification, from Tier 0 (open,
publicly available information) to Tier 4 (personal data where disclosure would lead to a risk to safety,
health or security). We provide recommendations for security controls which should be implemented at each tier,
and guidance for classifying data to the appropriate tier by taking into account its sensitivity and the
sensitivity of datasets it will be in combination with.

An easy-to-implement system for management, tracking and review: We make recommendations for certain
roles which should be specified within a project team, and the part that each of them plays in data
classification and data management. By sharing responsibility between multiple roles, we ensure that
no one role in the system becomes a point of failure.

Automated creation of multiple, independent secure environments, for conducting bespoke pieces of work:
One of the reasons for heavy-handed security restrictions at some institutions is that they maintain
blanket policies for all projects as they are conducted in similar environments. We recommend
instantiating separate environments for each analysis piece, based on software-defined infrastructure
executed against web services. This allows for appropriate and minimal controls to be applied for
individual work packages, thus decreasing the likelihood of workaround breach.

We are taking a cloud-based approach to instantiating environments, ensuring that every aspect of
the system can be defined by fully scripted configuration manifests which can be interrogated by
any data provider acting as auditor. This also provides scalable high-performance computing.

We are constructing an implementation on Microsoft Azure and intend to publish the reference
implementation in due course. This will allow researchers to instantiate environments with the
same processes, to the same classifications, with minimal effort. Our processes are adaptable to
any programmable, software-defined infrastructure. We are hopeful that others will adapt them to
other at-scale cloud platforms, and we will be happy to write the reference implementation to allow
these solutions to become easily repeatable.

We are seeking to develop this framework in collaboration with the expert community. We are
ideologically committed to creating and delivering in an agile manner, continually updating our
guidance in response to expert opinion and the lessons from practical use. This will be a living
framework, growing with the community as it moves from the realm of theory to implementation, and
we intend to allow it to develop in a direction that is flexible and responsive to the needs of
researchers and data providers.

This is why we are requesting your involvement. We hope that this framework can meet the needs of
researchers across institutions, sectors, and geographical boundaries, to provide a truly interoperable
and trusted solution to the difficulties of secure research. Our goals are to break down the boundaries
which prevent collaborative research between organisations, and to provide researchers with the
confidence to conduct bold and innovative analysis of datasets at all levels of sensitivity.

However, we will not get there without your support. We need the expertise of the community to
develop our approach and make it applicable across organisations. We hope that you will be involved
with taking this project forward, and we look forward to working with you more closely.

Yours,
