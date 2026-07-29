# Repository Coverage

[Full report](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

| Name                                                                                      |    Stmts |     Miss |   Cover |   Missing |
|------------------------------------------------------------------------------------------ | -------: | -------: | ------: | --------: |
| data\_safe\_haven/\_\_init\_\_.py                                                         |        4 |        0 |    100% |           |
| data\_safe\_haven/administration/\_\_init\_\_.py                                          |        0 |        0 |    100% |           |
| data\_safe\_haven/administration/users/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/users/entra\_users.py                                    |       69 |       50 |     28% |34-69, 78-102, 114-117, 126-135, 144-151, 160-166 |
| data\_safe\_haven/administration/users/guacamole\_users.py                                |       21 |       12 |     43% |20-48, 52-69 |
| data\_safe\_haven/administration/users/research\_user.py                                  |       33 |       10 |     70% |28, 44, 50, 54-56, 59-66, 69 |
| data\_safe\_haven/administration/users/user\_handler.py                                   |      100 |       73 |     27% |32-69, 75-81, 85, 91-97, 105-124, 135-137, 145-159, 167-206, 214-219 |
| data\_safe\_haven/allowlist/\_\_init\_\_.py                                               |        2 |        0 |    100% |           |
| data\_safe\_haven/allowlist/allowlist.py                                                  |       39 |        3 |     92% |     50-52 |
| data\_safe\_haven/commands/\_\_init\_\_.py                                                |        2 |        0 |    100% |           |
| data\_safe\_haven/commands/allowlist.py                                                   |      101 |       27 |     73% |35-36, 63-68, 80-82, 99-103, 106-107, 133-135, 167-168, 173-174, 180-182, 216, 223-225 |
| data\_safe\_haven/commands/cli.py                                                         |       30 |        3 |     90% |57, 60, 105 |
| data\_safe\_haven/commands/config.py                                                      |      122 |        3 |     98% |   232-234 |
| data\_safe\_haven/commands/context.py                                                     |       72 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                                      |       19 |        0 |    100% |           |
| data\_safe\_haven/commands/shm.py                                                         |       85 |       27 |     68% |52, 67, 69, 71, 73-100, 119-124, 135, 156-157 |
| data\_safe\_haven/commands/sre.py                                                         |       86 |       15 |     83% |73-81, 85-89, 188-197, 245-249, 263-266 |
| data\_safe\_haven/commands/users.py                                                       |      129 |       26 |     80% |40-51, 92-93, 167-172, 175-176, 203-211, 257-283 |
| data\_safe\_haven/config/\_\_init\_\_.py                                                  |        8 |        0 |    100% |           |
| data\_safe\_haven/config/account\_confirm\_config.py                                      |       23 |        0 |    100% |           |
| data\_safe\_haven/config/config\_sections.py                                              |       75 |        2 |     97% |   141-142 |
| data\_safe\_haven/config/context.py                                                       |       78 |        1 |     99% |       123 |
| data\_safe\_haven/config/context\_manager.py                                              |       98 |        4 |     96% |104-107, 119-122 |
| data\_safe\_haven/config/dsh\_pulumi\_config.py                                           |       40 |        0 |    100% |           |
| data\_safe\_haven/config/dsh\_pulumi\_project.py                                          |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/config/local\_config\_manager.py                                        |       41 |        0 |    100% |           |
| data\_safe\_haven/config/shm\_config.py                                                   |       23 |        7 |     70% |     33-41 |
| data\_safe\_haven/config/sre\_config.py                                                   |       54 |        0 |    100% |           |
| data\_safe\_haven/console/\_\_init\_\_.py                                                 |        4 |        0 |    100% |           |
| data\_safe\_haven/console/format.py                                                       |       11 |        0 |    100% |           |
| data\_safe\_haven/console/pretty.py                                                       |        5 |        0 |    100% |           |
| data\_safe\_haven/console/prompts.py                                                      |        9 |        0 |    100% |           |
| data\_safe\_haven/directories.py                                                          |       15 |        1 |     93% |        20 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                              |       33 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                                |        7 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                            |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_sdk.py                                              |      530 |      333 |     37% |121-127, 129-130, 156-157, 176-189, 191-192, 227-231, 233-234, 251-267, 287-315, 333-356, 372-395, 412-476, 491-512, 528-546, 552-569, 629, 664-693, 710-736, 753-773, 789-790, 800-801, 820-829, 862-875, 903, 912, 914-915, 932-943, 959-989, 992-1017, 1031-1037, 1065-1069, 1083, 1091-1092, 1095-1097, 1109-1134, 1151-1166, 1179-1210, 1222-1275, 1283-1319, 1333-1365, 1381-1397, 1403-1407, 1412-1420, 1454-1469, 1487-1506 |
| data\_safe\_haven/external/api/credentials.py                                             |      105 |        7 |     93% |232-235, 244-248 |
| data\_safe\_haven/external/api/graph\_api.py                                              |      422 |      320 |     24% |112, 126-127, 129-131, 143-168, 182-265, 278-317, 327-353, 366-437, 448-462, 465-472, 477-484, 493-497, 500-509, 512-521, 544-552, 567-608, 623-672, 684, 697-711, 734, 767-771, 782-795, 806-822, 833-845, 858-868, 882-884, 898-905, 909-918, 931-968, 979-988, 1000-1023, 1033-1096 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                                      |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                        |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-90, 100-125 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                                |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py                       |      112 |       83 |     26% |40-50, 57-58, 62, 76-80, 86-90, 94-107, 113-120, 128-165, 169-230 |
| data\_safe\_haven/external/interface/pulumi\_account.py                                   |       21 |        7 |     67% |27-28, 33-45 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                               |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/network.py                                                    |       15 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                                    |       61 |       10 |     84% |78-87, 102-104, 109 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                          |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                                   |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/dockerhub\_credentials.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                                     |       28 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/transformations.py                                |       57 |       24 |     58% |13, 16-17, 24, 31-32, 39-40, 47-48, 66-81, 88-89, 96-97, 104-105, 110-113 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                               |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py                     |        9 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/entra\_application.py               |       27 |       13 |     52% |23-30, 53, 78, 102-151 |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py               |       16 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py         |       24 |       16 |     33% |22-28, 41-110 |
| data\_safe\_haven/infrastructure/components/composite/nfsv3\_blob\_container.py           |       21 |       14 |     33% |22-29, 39-76 |
| data\_safe\_haven/infrastructure/components/composite/nfsv3\_storage\_account.py          |       22 |       13 |     41% |19-24, 47-133 |
| data\_safe\_haven/infrastructure/components/composite/operational\_insights\_workspace.py |       22 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py             |       32 |        1 |     97% |       107 |
| data\_safe\_haven/infrastructure/components/composite/virtual\_machine.py                 |       67 |        3 |     96% |135-147, 176 |
| data\_safe\_haven/infrastructure/components/dynamic/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py               |       43 |       27 |     37% |29-50, 56-68, 76-87, 97-98, 102, 114 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py            |       29 |       11 |     62% |41-54, 72-75, 139, 149, 168-170 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py                  |       70 |       42 |     40% |37-40, 49-62, 71-86, 94-109, 119-121, 124-133 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py                   |       95 |       66 |     31% |39-44, 50-137, 145-163, 173-179, 188-198, 212 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                                 |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                             |       75 |       46 |     39% |    68-528 |
| data\_safe\_haven/infrastructure/programs/imperative\_shm.py                              |       78 |       55 |     29% |27-31, 39-172, 188-195 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                             |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py                     |       24 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py                       |       29 |       19 |     34% |34-43, 57-203 |
| data\_safe\_haven/infrastructure/programs/sre/clamav\_mirror.py                           |       27 |       18 |     33% |33-41, 55-177 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                                     |       87 |       72 |     17% |70-94, 112-821 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                        |       24 |        2 |     92% |     54-69 |
| data\_safe\_haven/infrastructure/programs/sre/desired\_state.py                           |       50 |       35 |     30% |68-91, 105-234, 238 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                              |       47 |        2 |     96% |     96-97 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server\_vm.py                          |       42 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/dns\_sidecar.py                             |       44 |       30 |     32% |73-86, 98-287 |
| data\_safe\_haven/infrastructure/programs/sre/entra.py                                    |       26 |       16 |     38% |27-30, 42-121 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                                 |       48 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_mirror\_manager.py                   |       49 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                            |       51 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                         |       44 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                                 |       32 |       23 |     28% |39-51, 67-252 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                               |       25 |       15 |     40% |26-32, 46-138 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring\_elements.py                     |       19 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                               |      147 |        2 |     99% |     79-80 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                          |       46 |       34 |     26% |52-92, 117-415 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py                   |       59 |       11 |     81% |189-422, 439-444 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                           |       60 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                               |       52 |       29 |     44% |43-69, 72-78, 92-148 |
| data\_safe\_haven/infrastructure/project\_manager.py                                      |      271 |      117 |     57% |77-79, 93, 146-148, 161-171, 175-188, 200-208, 230-237, 247-249, 259-269, 273-299, 322, 326-331, 341-343, 358-371, 384-387, 401-406, 415-423, 432-435, 450-460, 475-477 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                                 |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                                       |       38 |        0 |    100% |           |
| data\_safe\_haven/logging/non\_logging\_singleton.py                                      |        7 |        1 |     86% |        14 |
| data\_safe\_haven/logging/plain\_file\_handler.py                                         |       21 |        1 |     95% |        36 |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                            |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                              |       62 |       47 |     24% |27-71, 83-86, 90-95, 99-105, 109-132, 141-182, 194-199 |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                             |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                               |       41 |        3 |     93% | 45-46, 81 |
| data\_safe\_haven/serialisers/context\_base.py                                            |       12 |        2 |     83% |    15, 20 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                                |       51 |        0 |    100% |           |
| data\_safe\_haven/singleton.py                                                            |        8 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                                   |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                               |       22 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                          |      134 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                          |        2 |        0 |    100% |           |
| data\_safe\_haven/upgrade/\_\_init\_\_.py                                                 |        2 |        0 |    100% |           |
| data\_safe\_haven/upgrade/upgrade.py                                                      |       90 |        8 |     91% |136-139, 148-151 |
| data\_safe\_haven/utility/\_\_init\_\_.py                                                 |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                                 |       20 |        1 |     95% |        33 |
| data\_safe\_haven/validators/\_\_init\_\_.py                                              |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                                     |       24 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                                |       70 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                              |        2 |        0 |    100% |           |
| **TOTAL**                                                                                 | **5474** | **1888** | **66%** |           |


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