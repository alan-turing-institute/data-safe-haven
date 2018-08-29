# Contributing to the Turing Data Safe Haven project

**Welcome to the Turing Data Safe Haven project repository!**

Thank you for being here and contributing to the project.
It can truly only succeed with a interdisiplinary team working together.

The point of these contributing guidelines are to help you participate as easily as possible.
If you have any questions that aren't discussed below, please let us know by [opening an issue](#open-an-issue). `NOTE TO SELF: MAKE THIS HEADING!`

## Table of contents

Been here before?
Already know what you're looking for in this guide?
Jump to the following sections:

* [An Agile development philosophy](#an-agile-development-philosophy)
  * [Project workflow](#project-workflow)
  * [Project meetings](#project-meetings)
  * [Communications within the team and asking for help](#communications-within-the-team-and-asking-for-help)
* [Contributing through GitHub](#contributing-through-github)
  * [Writing in markdown](#writing-in-markdown)
  * [Project management through issues](#project-management-through-issues)
  * [Issues as conversations](#issues-as-conversations)
  * [Capturing knowledge in the GitHub wiki](#capturing-knowledge-in-the-github-wiki)
  * [Working in a private repository](#working-in-a-private-repository)
  * [Who's involved](#whos-involved)
* [Where to start: wiki, code and templates](#where-to-start-wiki-code-and-templates)
* [Where to start: issue labels](#where-to-start-issue-labels)
* [Make a change with a pull request](#making-a-change-with-a-pull-request)
  * [Example pull request](#example-pull-request)
* [Recognizing contributions](#recognizing-contributions)

## An Agile development philosophy

![](https://i.pinimg.com/originals/26/7c/41/267c41bbcd9ee183a663db3bc7d8772d.jpg)

For the Data Safe Haven project we've committed to following an Agile development philosophy.
You can read more details [on wikipedia](https://en.wikipedia.org/wiki/Agile_software_development) (and a [host of other websites](https://www.google.com/search?q=agile+development)!) but the values given in the [Agile Manifesto](http://agilemanifesto.org/) capture the overall goals well:

> We are uncovering better ways of developing software by doing it and helping others do it.
> Through this work we have come to value:
> 
> * **Individuals and interactions** over processes and tools
> * **Working software** over comprehensive documentation
> * **Customer collaboration** over contract negotiation
> * **Responding to change** over following a plan
> 
> That is, while there is value in the items on the right, we value the items on the left more.

Specifically, we're following a [Scrum framework](https://en.wikipedia.org/wiki/Scrum_(software_development)) (a specific *type* of agile development).

### Project workflow

You can read more details about a [Scrum workflow](https://en.wikipedia.org/wiki/Scrum_(software_development)#Workflow) online, but the following bullet points outline our agreed principles:

* No work that is not **documented in an issue** on GitHub
* All conversations and notes to be **recorded in the GitHub project wiki**
* All policy documents, guidelines, tutorials, code and its documentation to be **stored and maintained in this GitHub repository**
* Sprints last **two weeks** with regular **project meetings** in between

### Project meetings

The goal of the project meetings is to **reflect** on how the previous sprint went and to **plan** the next section of work.
These are two separate parts of the Scrum methodology: the [sprint retrospective](https://en.wikipedia.org/wiki/Scrum_(software_development)#Sprint_retrospective) and [sprint planning](https://en.wikipedia.org/wiki/Scrum_(software_development)#Sprint_planning) and shouldn't be confused (even though we'll do them in the same meeting!) 

During the project meetings we'll start by working through the [issues list][safehaven-issues] and discussing all the issues that have been tagged as work to be conducted in the finishing week's sprint.

For example, on 29 August 2018 we reviewed [Sprint 4 issues][labels-sprint4] and planned for [Sprint 5][labels-sprint5].

Note that the project meeting is very explicily **not** where the work gets done.
It is a review, reflection and an opportunity to set goals for the next two weeks.
Discussions around particular tasks should be conducted **during the sprint** not in the meeting.

### Communications within the team and asking for help

What we're missing that is integral to the Scrum methodology are the **daily standups**.
If we follow the process directly we should be having very short (15 minute) meetings **everyday** to make sure that the work is progressing during the sprints.

During a daily meeting everyone on the team would answer the following questions (from [wikipedia][scrum-dailyscrum]):

* What did I complete yesterday that contributed to the team meeting our sprint goal?
* What do I plan to complete today to contribute to the team meeting our sprint goal?
* Do I see any impediment that could prevent me or the team from meeting our sprint goal?

As we are distributed around the Turing and not working full time on this project, the best way to work around the absense of the daily meetings is to **commit to sharing updates as regularly as possible**.
Please see the section on [project management through issues](#project-management-through-issues) below on how to do this via GitHub.

> If each individual team member asks themselves the three questions (what did I did, what will I do, what is blocking me) and updates their assigned issues with the answers we will likely make good progress in the absense of these daily meetings.

<img align="right" width="50%" src="https://linuxcentro.com.br/wp-content/uploads/2017/04/github-520x350.jpg" alt="Two github cats working together"/>

## Contributing through GitHub

[git][git] is a really useful tool for version control. [GitHub][github] sits on top of git and supports collaborative and distributed working.

We know that it can be daunting to start using git and GitHub if you haven't worked with them in the past, but the Turing Research Engineering Team are happy to help you figure out any of the jargon or confusing instructions you encounter! :heart:

In order to contribute via GitHub you'll need to set up a free account and sign in. Here are some [instructions][github-newaccount] to help you get going.

### Writing in markdown

GitHub has a helpful page on [getting started with writing and formatting on GitHub][github-markdownhelp].

Most of the writing that you'll do will be in [Markdown][markdown]. You can think of Markdown as a few little symbols around your text that will allow GitHub to render the text with a little bit of formatting.
For example you could write words as bold (`**bold**`), or in italics (`*italics*`), or as a [link][rick-roll] (`[link](https://https://youtu.be/dQw4w9WgXcQ)`) to another webpage.

GitHub issues and the wiki pages both render markdown really nicely.
The goal is to allow you to focus on the content rather than worry too much about how things are laid out!

### Project management through issues

Please regularly check out the agreed upon tasks at the [issues list](https://github.com/alan-turing-institute/data-safe-haven/issues).

Issues for a specific sprint will be labelled as such (click on the buttons below to go to those sprints' issues).

[![Sprint1](https://img.shields.io/badge/-Sprint1-0052cc.svg)][labels-sprint1]
[![Sprint2](https://img.shields.io/badge/-Sprint2-7fea04.svg)][labels-sprint2]
[![Sprint3](https://img.shields.io/badge/-Sprint3-0052cc.svg)][labels-sprint3]
[![Sprint4](https://img.shields.io/badge/-Sprint4-23bca0.svg)][labels-sprint4]
[![Sprint5](https://img.shields.io/badge/-Sprint5-b5ecf4.svg)][labels-sprint5]

If you have an idea for a piece of work to complete, please **open an issue**.

If you have been assigned an issue, please be ready to explain in the [project meeting](#project-meetings) what your progress has been.
In a perfect world you'll have completed the task, documented everything you need to in the wiki and we'll be able to **close** the issue (to mark it as complete).

<img align="right" width="50%" src="https://ccistudentcenterblog.files.wordpress.com/2013/09/github-social-coding.jpg" alt="Two github cats working together"/>

### Issues as conversations

The name `issue` comes from a concept of catching errors (bugs :bug:) in software, but for this project they are simply our **tasks**.
They should be concrete enough to be done in one sprint.
If an issue is growing to encompass more than one task, consider breaking it into multiple issues.

You can think of the issues as **conversations** about a particular topic.
GitHub's tagline is **social coding** and the issues are inspired by social media conversations.

You can [mention a user][github-mentionuser] by putting `@` infront of their github id.
For example, `@KirstieJane` will send a notification to Kirstie Whitaker so she knows to visit the issue and (for example) reply to your question.

Alternatively (and this is encouraged) you can use the issue to keep track of where you're up to with the task and add information about next steps and barriers.

![](images/example-conversation-in-issue.png)

### Capturing knowledge in the GitHub wiki

Contributing on GitHub can be a little intimidating (see [making a change with a pull request](#making-a-change-with-a-pull-request) below.
What's great about the wiki is that you only need to be logged in to GitHub to edit it.

Here's a useful [introduction to GitHub wikis][intro-github-wiki].

To calm your nerves, the wiki is *itself* a git repository in the background and therefore it is versioned and (in that sense) backed up.
**You can't totally erase anyone's work in the wiki** so please don't feel nervous about refining and adding your work to an already existing document.


Your work does not need to be perfect and we encourage you to remember the premise behind the [Bus Factor][bus-factor]: a measurement of the risk resulting from information and capabilities not being shared among team members, from the phrase "in case they get hit by a bus".

> If you have thought about something, reviewed some work, worried about a potential problem, or come up with a potential solution it should be **written down in the wiki** to give the project resilience and to prevent us from reinventing the wheel.

### Working in a private repository

As one of the goals of this project is to build a secure infrastructure for data storage and analysis, our project will very likely include some code with security vulnerabilities! Therefore we're keeping the repository private until we're confident that our work is secure.

Please note that the plan is to make the contents of this repository openly available by the end of 2018. Please be considerate of the content you add and use professional and inclusive language at all times.

As we're working in a private repository you may not be able to see the repository if you aren't signed in. So if you see a 404 page and you're confident you have the correct url, go back to [github.com](https://github.com) to make sure that you're signed into your account.

### Who's involved

The private repositories in the Alan Turing Institute [GitHub organisation](https://github.com/alan-turing-institute) are set such that only named collaborators can see the work we do. (Another option for private repositories is to allow all members of the organisation but *not* public members to see all projects owned by the organisation.) Therefore it is sometimes nice to know **who** you're working with on the project (which is oddly difficult to do if you aren't an administrator on the project!)

(Additionally some users have GitHub IDs that make it a little difficult to know who they are in real life! Hopefully this table will help you put names to faces and IDs :sparkles:)

The following people have access to the project:

| Name               | GitHub ID | Email |
| ------------------ | --- | --- |
| Diego Arenas       | [@darenasc](https://github.com/darenasc)| <darenasc@gmail.com> |
| Jonathan Atkins     | [@jon-atkins](https://github.com/jon-atkins)| <jatkins@turing.ac.uk> |
| Ayman Boustati      | [@aboustati](https://github.com/aboustati)| <aboustati@turing.ac.uk> |
| Ian Carter          | [@getcarter21](https://github.com/getcarter21)| <icarter@turing.ac.uk> |
| Rob Clarke          | [@RobC-CTL](https://github.com/RobC-CTL)| <rob.clarke@coriniumtech.com> |
| Giovanni Colavizza  | [@Giovanni1085](https://github.com/Giovanni1085)| <gcolavizza@turing.ac.uk> |
| Christine Foster    | [@ChristineFoster](https://github.com/ChristineFoster)| <cfoster@turing.ac.uk> |
| Evelina Gabasova    | [@evelinag](https://github.com/evelinag)| <egabasova@turing.ac.uk> |
| James Geddes        | [@triangle-man](https://github.com/triangle-man)| <jgeddes@turing.ac.uk> |
| Andreas Grammenos   | [@andylamp](https://github.com/andylamp) | <axor@turing.ac.uk> |
| Nicolas Guernion    | | <nguernion@turing.ac.uk> |
| James Heatherington | [@jamespjh](https://github.com/jamespjh) | <jhetherington@turing.ac.uk> |
| Franz Kiraly       | [@fkiraly](https://github.com/fkiraly)| <fkiraly@turing.ac.uk> |
| Catherine Lawrence | [@cathiest](https://github.com/cathiest) | <clawrence@turing.ac.uk> |
| Martin O'Reilly    | [@martintoreilly](https://github.com/martintoreilly)| <moreilly@turing.ac.uk> |
| Kenji Takeda       | [@ktakeda1](https://github.com/ktakeda1)| <ktakeda@turing.ac.uk> |
| Sebastian Vollmer  | [@vollmersj](https://github.com/vollmersj)| <svollmer@turing.ac.uk> |
| Kirstie Whitaker   | [@KirstieJane](https://github.com/KirstieJane)| <kwhitaker@turing.ac.uk> |

## Making a change with a pull request

To contribute to the codebase you'll need to submit a **pull request**.

:point_right: Remember that if you're adding information to the wiki (as described [above](#github-wiki) you ***don't need to submit a pull request***. You can just log into GitHub, navigate to the [repository wiki][safehaven-wiki] and click the **edit** button.

If you're updating the code or other documents in the main repository, the following steps are a guide to help you contribute in a way that will be easy for everyone to review and accept with ease  :sunglasses:.

#### 1. Make sure there is an issue for this sprint that is clear about what work you're going to do

This allows other members of the Data Safe Haven project team to confirm that you aren't overlapping with work that's currently underway and that everyone is on the same page with the goal of the work you're going to carry out.

[This blog][dont-push-pull-request] is a nice explanation of why putting this work in up front is so useful to everyone involved.

#### 2. [Fork][github-fork] the [Data Safe Haven repository][safehaven-repo] to your profile

This is now your own unique copy of the Data Safe Haven repository. Changes here won't affect anyone else's work, so it's a safe space to explore edits to the code or documentation!

Make sure to [keep your fork up to date][github-syncfork] with the master repository, otherwise you can end up with lots of dreaded [merge conflicts][github-mergeconflicts].

#### 3. Make the changes you've discussed

Try to keep the changes focused. If you submit a large amount of work in all in one go it will be much more work for whomever is reviewing your pull request. [Help them help you][jerry-maguire] :wink:

If you feel tempted to "branch out" then please make a [new branch][github-branches] and a [new issue][safehaven-issues] to go with it.

#### 4. Submit a [pull request][github-pullrequest]

A member of the Safe Haven project team will review your changes to confirm that they can be merged into the main codebase.

A [review][github-review] will probably consist of a few questions to help clarify the work you've done. Keep an eye on your github notifications and be prepared to join in that conversation.

You can update your [fork][github-fork] of the data safe haven [repository][safehaven-repo] and the pull request will automatically update with those changes. **You don't need to submit a new pull request when you make a change in response to a review.**

GitHub has a [nice introduction][github-flow] to the pull request workflow, but please [get in touch](#get-in-touch) if you have any questions :balloon:.


## Thank you!

You're awesome. :wave::smiley:

<br>

*&mdash; Based on contributing guidelines from the [BIDS Starter Kit][bids-starterkit-repo] project.*

[bids-starterkit-repo]: https://github.com/INCF/bids-starter-kit
[bus-factor]: https://en.wikipedia.org/wiki/Bus_factor
[dont-push-pull-request]: https://www.igvita.com/2011/12/19/dont-push-your-pull-requests
[git]: https://git-scm.com
[github]: https://github.com
[github-newaccount]: https://help.github.com/articles/signing-up-for-a-new-github-account/
[github-branches]: https://help.github.com/articles/creating-and-deleting-branches-within-your-repository
[github-fork]: https://help.github.com/articles/fork-a-repo
[github-flow]: https://guides.github.com/introduction/flow
[github-markdownhelp]: https://help.github.com/articles/getting-started-with-writing-and-formatting-on-github
[github-mentionuser]: https://help.github.com/articles/basic-writing-and-formatting-syntax/#mentioning-people-and-teams
[github-mergeconflicts]: https://help.github.com/articles/about-merge-conflicts
[github-pullrequest]: https://help.github.com/articles/creating-a-pull-request
[github-review]: https://help.github.com/articles/about-pull-request-reviews
[github-syncfork]: https://help.github.com/articles/syncing-a-fork
[intro-github-wiki]: https://help.github.com/articles/about-github-wikis
[labels-sprint1]: https://github.com/alan-turing-institute/data-safe-haven/labels/Sprint1
[labels-sprint2]: https://github.com/alan-turing-institute/data-safe-haven/labels/Sprint2
[labels-sprint3]: https://github.com/alan-turing-institute/data-safe-haven/labels/Sprint3
[labels-sprint4]: https://github.com/alan-turing-institute/data-safe-haven/labels/Sprint4
[labels-sprint5]: https://github.com/alan-turing-institute/data-safe-haven/labels/Sprint5
[jerry-maguire]: https://media.giphy.com/media/uRb2p09vY8lEs/giphy.gif
[markdown]: https://daringfireball.net/projects/markdown
[neurostars-forum]: https://neurostars.org/tags/bids
[patrick-github]: https://github.com/Park-Patrick
[rick-roll]: https://www.youtube.com/watch?v=dQw4w9WgXcQ
[safehaven-issues]: https://github.com/alan-turing-institute/data-safe-haven/issues
[safehaven-labels]: https://github.com/alan-turing-institute/data-safe-haven/labels
[safehaven-repo]: https://github.com/alan-turing-institute/data-safe-haven
[safehaven-wiki]: https://github.com/alan-turing-institute/data-safe-haven/wiki
[scrum-dailyscrum]: https://en.wikipedia.org/wiki/Scrum_(software_development)#Daily_Scrum