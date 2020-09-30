# Adding software to the default environment

If multiple researchers want to install the same tool, it makes sense to add it to the list of tools installed by default in the safe haven analysis environment (see [Analysis Environment Design](AnalysisEnvironmentDesign)).

As a general rule, user-written own code should not be added to the default list. Ingress should instead follow the [Software ingress policy](SoftwareIngressPolicy).

Adding other software tools to the default list will go through an application process. The requester should submit a form containing the following information:

+ Software name
+ Link to installation instructions
+ Justification for requiring this tool
+ Who is going to use this tool.

The request is then approved by a member of the Research engineering team.

The two evaluation criteria are:

+ Has this tool been reviewed by a community of developers? Is there a process through which harmful code could have been recognised and removed?
  + Note that this does not mean a review of the code by a member of the Research Engineering team. Default tools should have a community review and development process. Bespoke code written by an individual developer is not likely to meet this criterion.
+ Will this tool be useful to additional researchers? As a rule, any default software should be used by more than 1 person.

If the software is considered worth adding to the default environment, then ..... *what happens if you **do** want to update the environment?*
