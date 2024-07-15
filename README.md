# Repository Coverage

[Full report](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

| Name                                                                              |    Stmts |     Miss |   Cover |   Missing |
|---------------------------------------------------------------------------------- | -------: | -------: | ------: | --------: |
| data\_safe\_haven/\_\_init\_\_.py                                                 |        4 |        0 |    100% |           |
| data\_safe\_haven/administration/\_\_init\_\_.py                                  |        0 |        0 |    100% |           |
| data\_safe\_haven/administration/users/\_\_init\_\_.py                            |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/users/entra\_users.py                            |       66 |       52 |     21% |24-25, 34-66, 75-99, 108-114, 123-132, 141-148, 157-163 |
| data\_safe\_haven/administration/users/guacamole\_users.py                        |       20 |       11 |     45% |20-45, 49-66 |
| data\_safe\_haven/administration/users/research\_user.py                          |       30 |       19 |     37% |16-23, 27, 31-33, 37-39, 42-49, 52 |
| data\_safe\_haven/administration/users/user\_handler.py                           |      100 |       78 |     22% |22-24, 32-68, 74-80, 84, 90-96, 104-123, 131-136, 144-158, 166-205, 213-218 |
| data\_safe\_haven/commands/\_\_init\_\_.py                                        |        2 |        0 |    100% |           |
| data\_safe\_haven/commands/cli.py                                                 |       28 |        3 |     89% |56, 59, 99 |
| data\_safe\_haven/commands/config.py                                              |       49 |        0 |    100% |           |
| data\_safe\_haven/commands/context.py                                             |       71 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                              |       22 |        0 |    100% |           |
| data\_safe\_haven/commands/shm.py                                                 |       73 |       20 |     73% |69, 71, 73, 75-85, 92-102, 117-122 |
| data\_safe\_haven/commands/sre.py                                                 |       58 |       10 |     83% |61-65, 113-121, 160-164, 176-179 |
| data\_safe\_haven/commands/users.py                                               |      118 |       32 |     73% |44-55, 83-93, 139-160, 190-198, 244-270 |
| data\_safe\_haven/config/\_\_init\_\_.py                                          |        7 |        0 |    100% |           |
| data\_safe\_haven/config/config\_sections.py                                      |       27 |        0 |    100% |           |
| data\_safe\_haven/config/context.py                                               |       56 |        1 |     98% |        88 |
| data\_safe\_haven/config/context\_manager.py                                      |       88 |        4 |     95% |102-105, 117-120 |
| data\_safe\_haven/config/dsh\_pulumi\_config.py                                   |       40 |        0 |    100% |           |
| data\_safe\_haven/config/dsh\_pulumi\_project.py                                  |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/config/shm\_config.py                                           |       18 |        3 |     83% |     29-33 |
| data\_safe\_haven/config/sre\_config.py                                           |       25 |        0 |    100% |           |
| data\_safe\_haven/console/\_\_init\_\_.py                                         |        4 |        0 |    100% |           |
| data\_safe\_haven/console/format.py                                               |       11 |        0 |    100% |           |
| data\_safe\_haven/console/pretty.py                                               |        5 |        0 |    100% |           |
| data\_safe\_haven/console/prompts.py                                              |        9 |        0 |    100% |           |
| data\_safe\_haven/directories.py                                                  |       15 |        1 |     93% |        20 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                      |       29 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        7 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_sdk.py                                      |      411 |      297 |     28% |122-133, 193-197, 199-200, 220-248, 266-289, 305-328, 345-405, 420-441, 457-475, 488-517, 534-559, 576-596, 610-619, 652-665, 673-686, 706-723, 725-726, 755-783, 786-811, 823-848, 865-886, 899-930, 942-995, 1003-1039, 1056-1091, 1108-1127, 1141-1173, 1191-1205 |
| data\_safe\_haven/external/api/credentials.py                                     |       81 |        0 |    100% |           |
| data\_safe\_haven/external/api/graph\_api.py                                      |      415 |      318 |     23% |99, 113-114, 116-118, 130-155, 169-252, 265-304, 312-338, 348-374, 387-441, 452-466, 469-476, 481-488, 491-500, 503-512, 535-543, 558-599, 614-663, 674-690, 716-717, 748-749, 760-776, 787-804, 815-824, 837-847, 861-863, 877-884, 888-897, 910-947, 958-967, 979-1002, 1012-1065 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-90, 100-125 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      118 |       81 |     31% |46-56, 63-64, 68, 82-86, 92-96, 100-113, 119-126, 134-169, 173-234 |
| data\_safe\_haven/external/interface/pulumi\_account.py                           |       20 |        7 |     65% |26-27, 32-43 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/network.py                                            |       20 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       61 |       20 |     67% |22, 78-87, 102-104, 109, 119-127 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/dockerhub\_credentials.py                 |        6 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                             |       23 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/transformations.py                        |       57 |       34 |     40% |12-17, 24, 31-32, 39-40, 45-48, 55, 66-81, 88-89, 94-97, 102-105, 110-113 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py             |        5 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py       |       16 |       10 |     38% |16-20, 32-68 |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py |       24 |       16 |     33% |22-28, 41-109 |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py     |       24 |       16 |     33% |22-28, 41-122 |
| data\_safe\_haven/infrastructure/components/composite/virtual\_machine.py         |       70 |       49 |     30% |37-58, 62, 66, 77-97, 109-134, 147-311 |
| data\_safe\_haven/infrastructure/components/dynamic/\_\_init\_\_.py               |        6 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py       |       43 |       27 |     37% |29-50, 56-68, 76-87, 97-98, 102, 114 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py    |       29 |       11 |     62% |41-54, 72-75, 133, 143, 162-164 |
| data\_safe\_haven/infrastructure/components/dynamic/entra\_application.py         |       77 |       55 |     29% |27-32, 37-38, 42-90, 98-104, 114-115, 118-141, 150-159, 175 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       71 |       48 |     32% |27-31, 37-40, 49-62, 71-86, 94-109, 119-121, 124-133, 146 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_upload.py               |       50 |       31 |     38% |29-38, 44-77, 85-95, 110-118, 122, 132-134, 147 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       90 |       66 |     27% |37-42, 48-127, 135-153, 163-164, 167-181, 194 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        6 |     65% |22-23, 39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       52 |       29 |     44% |    72-383 |
| data\_safe\_haven/infrastructure/programs/imperative\_shm.py                      |       64 |       50 |     22% |26-30, 38-144, 152-160 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       24 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       29 |       19 |     34% |34-44, 58-200 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |18-22, 38-173 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       83 |       68 |     18% |59-85, 103-786 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       26 |       18 |     31% |31-41, 55-107 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       37 |       24 |     35% |35-38, 52-328 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       27 |       18 |     33% |36-57, 73-303 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       46 |       35 |     24% |47-67, 81-343 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       43 |       30 |     30% |49-69, 83-321 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       33 |       24 |     27% |41-54, 70-264 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       28 |       17 |     39% |32-35, 49-214 |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |       88 |       78 |     11% |38-52, 66-1810 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       49 |       37 |     24% |58-98, 123-431 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       43 |       31 |     28% |42-58, 72-343 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       47 |       34 |     28% |51-80, 96-208 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       69 |       51 |     26% |54-88, 91-97, 111-214, 231-248 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      238 |      135 |     43% |68-82, 86, 140-142, 151-161, 165-178, 184-193, 197-257, 261-264, 268-273, 283-285, 297-299, 303-316, 320-327, 341-346, 355-363, 367-377, 392-394 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                               |       38 |        0 |    100% |           |
| data\_safe\_haven/logging/plain\_file\_handler.py                                 |       16 |        0 |    100% |           |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       48 |       34 |     29% |29-57, 69-72, 76-77, 81-86, 90-126, 136-138 |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       33 |        0 |    100% |           |
| data\_safe\_haven/serialisers/context\_base.py                                    |       15 |        2 |     87% |    15, 20 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       43 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       18 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |       90 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       23 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       64 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
|                                                                         **TOTAL** | **4314** | **2125** | **51%** |           |


## Setup coverage badge

Below are examples of the badges you can use in your main branch `README` file.

### Direct image

[![Coverage badge](https://raw.githubusercontent.com/alan-turing-institute/data-safe-haven/python-coverage-comment-action-data/badge.svg)](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

This is the one to use if your repository is private or if you don't want to customize anything.

### [Shields.io](https://shields.io) Json Endpoint

[![Coverage badge](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/alan-turing-institute/data-safe-haven/python-coverage-comment-action-data/endpoint.json)](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

Using this one will allow you to [customize](https://shields.io/endpoint) the look of your badge.
It won't work with private repositories. It won't be refreshed more than once per five minutes.

### [Shields.io](https://shields.io) Dynamic Badge

[![Coverage badge](https://img.shields.io/badge/dynamic/json?color=brightgreen&label=coverage&query=%24.message&url=https%3A%2F%2Fraw.githubusercontent.com%2Falan-turing-institute%2Fdata-safe-haven%2Fpython-coverage-comment-action-data%2Fendpoint.json)](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

This one will always be the same color. It won't work for private repos. I'm not even sure why we included it.

## What is that?

This branch is part of the
[python-coverage-comment-action](https://github.com/marketplace/actions/python-coverage-comment)
GitHub Action. All the files in this branch are automatically generated and may be
overwritten at any moment.