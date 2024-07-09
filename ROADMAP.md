# Roadmap

Last updated: 2024-07-08

## Background

This document sets out the plan for the evolution of the Data Safe Haven codebase.
It covers both short term-goals, which are organised in sprint milestones, and long-term goals, which are expected without a particular time frame.
It also collects desirable features which are unplanned or which we have decided not to pursue yet.

The [short-term plans](#short-term) aim to give a clear indication of current work and when it may be finished.
We hope that a focus on defining releases will encourage development to balance new features with other improvements and address the needs of users.

[Long-term goals](#long-term) give reassurance that we have committed to certain changes when we are unable to give an estimation of when they will be ready.

Finally, [desired features](#desired-features) is a way for us to express developments we would like to pursue but have decided not to do yet.
This is a good indication of where we would like the project to go and areas we would be interested in collaborating.

## Governance

This document is written by the code's [development lead](https://github.com/JimMadge) with input from the development team.

When deciding on what features to include in the roadmap, and where to include them we consider, in no particular order,

- The maintainability of the code (looking after the developers)
- Supporting users at The Alan Turing Institute (a significant user who we have a close relationship with)
- Supporting all users we are in contact with
- Integrating with, and building compatibility for, common infrastructure in the UK TRE landscape

These factors are balanced when making decisions.
There is no formal process for assigning scores for the above factors, or the weight each should be given.
In general, we currently consider the needs of our colleagues at The Alan Turing institute as our single most important user.
However, we also have opinions and expertise in trusted research and aim to inform the Turing rather than be directed by them.
Furthermore, we wouldn't necessarily let the priorities or opinions of the Turing overrule those of other users.

For example,

- User A wants new feature X next, the Turing wants new feature Y next.
    - We would be inclined to prioritise feature Y over X.
- The majority of the community feels the TRE should behave in manner X, a minority of the community, including the Turing, feels the TRE should behave in manner Y.
    - We would be inclined to design the TRE to behave in manner X.

At a time when the project has a large and active user base, we would like to better formalise how users feedback and ideas influence the roadmap.

## Short Term

Short-term goals are those which we have committed to and have planned an expected completion date.
These are organised into milestones.
Each milestone has,

- A description of its aims
- A target date
- A collection of issues which constitute the work to be done

Milestones will usually correspond to new releases of Data Safe Haven.
Currently we aim to align milestones with Data Study Groups at the Turing, so that new releases are made in time to be used at these events.

The milestones can be seen [on GitHub](https://github.com/alan-turing-institute/data-safe-haven/milestones)

## Long Term

Long-term goals are developments which we have committed to but have not planned an expected completion date.
This may be because they are lower priority than short-term goals or because the time required needs to be scoped.

## Desired Features

These are features we would like to highlight but which we have actively decided not to incorporate into the long- or short-term roadmap.
This may be because, for example, we have decided we have insufficient resource, are lacking the right expertise or it is low priority.

### User Defined Container Support

Enable users to bring containers they have developed outside of the TRE into the TRE to be used in research/analysis.
The HPC focused container project Apptainer could be a good fit, providing performance and protecting against privilege escalation.
This work would compliment [Develop Outside, Run Inside](#develop-outside-run-inside).

### Improve Resource Competition

Researchers currently tend to share resources in SRDs which can cause problems if they are not careful to coordinate their work.
This could be improved by,

- HPC style job submission queue
- Isolated resources per user (VMs, cgroups)

### User-Facing Web App for Project Management

There is currently little tooling for research teams working through processes or managing their environments.
A web app could be an accessible way to present features like,

- Switching on and off resources (improves cost management)
- Scaling resources
- Opening support tickets
- Opening data ingress or egress request tickets
- Working through IG processes

This work would be particularly powerful if the interfaces/processes can be abstracted so that the web app can be used by other TRE operators and integrated into their TRE implementations.

### Addon or Plugin System

For a TRE to be effective, it needs to enable research.
DSH has always tried to strike a good balance between security and features/convenience for researchers.
A downside of this is it can lead to a complicated environment with many components.
This is especially true when working across domains, as each domain has specific tools that they rely on.
This create a lot of maintenance burden and spreads developer time thin.

Another approach to this could be to break more TRE components out into option addon or plugin modules.
It would require building a system to integrate these into the TRE.
This would mean,

- It is easier for communities to add functionality they want
- Broken features can be easily disabled without affecting the core TRE
- If we have no interest in continuing to support a module, the community can adopt and maintain it
- There is an easier entry point to contributing
