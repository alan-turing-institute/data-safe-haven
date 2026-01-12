# Repository Coverage

[Full report](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

| Name                                                                              |    Stmts |     Miss |   Cover |   Missing |
|---------------------------------------------------------------------------------- | -------: | -------: | ------: | --------: |
| data\_safe\_haven/\_\_init\_\_.py                                                 |        4 |        0 |    100% |           |
| data\_safe\_haven/administration/\_\_init\_\_.py                                  |        0 |        0 |    100% |           |
| data\_safe\_haven/administration/users/\_\_init\_\_.py                            |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/users/entra\_users.py                            |       69 |       50 |     28% |34-69, 78-102, 114-117, 126-135, 144-151, 160-166 |
| data\_safe\_haven/administration/users/guacamole\_users.py                        |       21 |       12 |     43% |20-48, 52-69 |
| data\_safe\_haven/administration/users/research\_user.py                          |       33 |       10 |     70% |28, 44, 50, 54-56, 59-66, 69 |
| data\_safe\_haven/administration/users/user\_handler.py                           |      100 |       73 |     27% |32-69, 75-81, 85, 91-97, 105-124, 135-137, 145-159, 167-206, 214-219 |
| data\_safe\_haven/allowlist/\_\_init\_\_.py                                       |        2 |        0 |    100% |           |
| data\_safe\_haven/allowlist/allowlist.py                                          |       39 |        3 |     92% |     50-52 |
| data\_safe\_haven/commands/\_\_init\_\_.py                                        |        2 |        0 |    100% |           |
| data\_safe\_haven/commands/allowlist.py                                           |       95 |       27 |     72% |32-33, 60-65, 77-79, 91-95, 98-99, 126-128, 160-161, 166-167, 173-175, 204, 211-213 |
| data\_safe\_haven/commands/cli.py                                                 |       30 |        3 |     90% |57, 60, 105 |
| data\_safe\_haven/commands/config.py                                              |      122 |        3 |     98% |   232-234 |
| data\_safe\_haven/commands/context.py                                             |       72 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                              |       19 |        0 |    100% |           |
| data\_safe\_haven/commands/shm.py                                                 |       85 |       27 |     68% |52, 67, 69, 71, 73-100, 119-124, 135, 156-157 |
| data\_safe\_haven/commands/sre.py                                                 |       86 |       15 |     83% |57-65, 69-73, 170-179, 227-231, 245-248 |
| data\_safe\_haven/commands/users.py                                               |      129 |       26 |     80% |40-51, 92-93, 167-172, 175-176, 203-211, 257-283 |
| data\_safe\_haven/config/\_\_init\_\_.py                                          |        7 |        0 |    100% |           |
| data\_safe\_haven/config/config\_sections.py                                      |       73 |        2 |     97% |   138-139 |
| data\_safe\_haven/config/context.py                                               |       78 |        1 |     99% |       123 |
| data\_safe\_haven/config/context\_manager.py                                      |       93 |        4 |     96% |97-100, 112-115 |
| data\_safe\_haven/config/dsh\_pulumi\_config.py                                   |       40 |        0 |    100% |           |
| data\_safe\_haven/config/dsh\_pulumi\_project.py                                  |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/config/shm\_config.py                                           |       23 |        7 |     70% |     33-41 |
| data\_safe\_haven/config/sre\_config.py                                           |       54 |        0 |    100% |           |
| data\_safe\_haven/console/\_\_init\_\_.py                                         |        4 |        0 |    100% |           |
| data\_safe\_haven/console/format.py                                               |       11 |        0 |    100% |           |
| data\_safe\_haven/console/pretty.py                                               |        5 |        0 |    100% |           |
| data\_safe\_haven/console/prompts.py                                              |        9 |        0 |    100% |           |
| data\_safe\_haven/directories.py                                                  |       15 |        1 |     93% |        20 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                      |       33 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        7 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_sdk.py                                      |      490 |      323 |     34% |118-124, 126-127, 153-154, 173-186, 188-189, 224-228, 230-231, 248-264, 284-312, 330-353, 369-392, 409-473, 488-509, 525-543, 556-585, 602-628, 645-665, 681-682, 692-693, 712-721, 754-767, 804, 806-807, 824-835, 851-881, 884-909, 923-929, 957-961, 975, 983-984, 987-989, 1001-1026, 1043-1058, 1071-1102, 1114-1167, 1175-1211, 1225-1257, 1273-1289, 1295-1299, 1304-1312, 1346-1361, 1379-1398 |
| data\_safe\_haven/external/api/credentials.py                                     |       98 |        7 |     93% |219-222, 231-235 |
| data\_safe\_haven/external/api/graph\_api.py                                      |      422 |      320 |     24% |112, 126-127, 129-131, 143-168, 182-265, 278-317, 327-353, 366-437, 448-462, 465-472, 477-484, 493-497, 500-509, 512-521, 544-552, 567-608, 623-672, 684, 697-711, 734, 767-771, 782-795, 806-822, 833-845, 858-868, 882-884, 898-905, 909-918, 931-968, 979-988, 1000-1023, 1033-1096 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-90, 100-125 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      112 |       83 |     26% |40-50, 57-58, 62, 76-80, 86-90, 94-107, 113-120, 128-165, 169-230 |
| data\_safe\_haven/external/interface/pulumi\_account.py                           |       21 |        7 |     67% |27-28, 33-45 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/network.py                                            |       15 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       61 |       11 |     82% |22, 78-87, 102-104, 109 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/dockerhub\_credentials.py                 |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                             |       28 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/transformations.py                        |       57 |       31 |     46% |13, 16-17, 24, 31-32, 39-40, 45-48, 55, 66-81, 88-89, 94-97, 102-105, 110-113 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py             |        8 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/entra\_application.py       |       27 |       13 |     52% |23-30, 53, 78, 102-151 |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py       |       16 |       10 |     38% |15-18, 30-70 |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py |       24 |       16 |     33% |22-28, 41-110 |
| data\_safe\_haven/infrastructure/components/composite/nfsv3\_blob\_container.py   |       21 |       14 |     33% |22-29, 39-76 |
| data\_safe\_haven/infrastructure/components/composite/nfsv3\_storage\_account.py  |       23 |       13 |     43% |22-27, 50-136 |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py     |       31 |       22 |     29% |26-34, 47-165 |
| data\_safe\_haven/infrastructure/components/composite/virtual\_machine.py         |       62 |       47 |     24% |37-58, 62, 66, 78-103, 116-289 |
| data\_safe\_haven/infrastructure/components/dynamic/\_\_init\_\_.py               |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py       |       43 |       27 |     37% |29-50, 56-68, 76-87, 97-98, 102, 114 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py    |       29 |       11 |     62% |41-54, 72-75, 139, 149, 168-170 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       70 |       48 |     31% |27-31, 37-40, 49-62, 71-86, 94-109, 119-121, 124-133, 146 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       95 |       66 |     31% |39-44, 50-137, 145-163, 173-179, 188-198, 212 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        4 |     76% |39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       75 |       46 |     39% |    68-522 |
| data\_safe\_haven/infrastructure/programs/imperative\_shm.py                      |       78 |       55 |     29% |27-31, 39-172, 188-195 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       24 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       29 |       19 |     34% |34-43, 57-202 |
| data\_safe\_haven/infrastructure/programs/sre/clamav\_mirror.py                   |       27 |       18 |     33% |33-41, 55-176 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       93 |       78 |     16% |70-94, 112-869 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       24 |       16 |     33% |28-34, 48-100 |
| data\_safe\_haven/infrastructure/programs/sre/desired\_state.py                   |       50 |       35 |     30% |68-91, 105-234, 238 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       47 |       33 |     30% |46-55, 69-308 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server\_vm.py                  |       42 |       27 |     36% |37-63, 77-115, 123-134 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_sidecar.py                     |       44 |       30 |     32% |69-82, 94-240 |
| data\_safe\_haven/infrastructure/programs/sre/entra.py                            |       26 |       16 |     38% |27-30, 42-121 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       49 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_mirror\_manager.py           |       50 |       36 |     28% |48-66, 78-388 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       52 |       40 |     23% |47-66, 80-417 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       45 |       32 |     29% |48-67, 81-347 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       32 |       23 |     28% |39-51, 67-251 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       25 |       15 |     40% |26-32, 46-132 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring\_elements.py             |       19 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |      144 |      130 |     10% |39-57, 71-1976, 1985, 2113, 2231, 2296-2565 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       46 |       34 |     26% |52-92, 117-413 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       55 |       41 |     25% |54-77, 102-443 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       60 |       44 |     27% |64-112, 128-240 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       52 |       29 |     44% |41-67, 70-76, 90-141 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      251 |      127 |     49% |69-83, 87, 140-142, 155-165, 169-182, 194-202, 224-231, 241-243, 247-256, 260-286, 309, 313-318, 328-330, 339-341, 345-358, 362-369, 383-388, 397-405, 409-419, 434-436 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                               |       38 |        0 |    100% |           |
| data\_safe\_haven/logging/non\_logging\_singleton.py                              |        7 |        1 |     86% |        14 |
| data\_safe\_haven/logging/plain\_file\_handler.py                                 |       21 |        1 |     95% |        36 |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       61 |       46 |     25% |27-71, 83-86, 90-95, 99-105, 109-134, 143-183, 195-200 |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       41 |        3 |     93% | 45-46, 81 |
| data\_safe\_haven/serialisers/context\_base.py                                    |       12 |        2 |     83% |    15, 20 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       48 |        0 |    100% |           |
| data\_safe\_haven/singleton.py                                                    |        8 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       21 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |      134 |        2 |     99% |   197-217 |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       24 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       70 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
| **TOTAL**                                                                         | **5227** | **2370** | **55%** |           |


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