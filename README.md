# Repository Coverage

[Full report](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

| Name                                                                              |    Stmts |     Miss |   Cover |   Missing |
|---------------------------------------------------------------------------------- | -------: | -------: | ------: | --------: |
| data\_safe\_haven/\_\_init\_\_.py                                                 |        4 |        0 |    100% |           |
| data\_safe\_haven/administration/\_\_init\_\_.py                                  |        0 |        0 |    100% |           |
| data\_safe\_haven/administration/users/\_\_init\_\_.py                            |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/users/entra\_users.py                            |       69 |       50 |     28% |34-69, 78-102, 114-117, 126-135, 144-151, 160-166 |
| data\_safe\_haven/administration/users/guacamole\_users.py                        |       21 |       12 |     43% |20-48, 52-69 |
| data\_safe\_haven/administration/users/research\_user.py                          |       31 |        9 |     71% |29, 35, 39-41, 44-51, 54 |
| data\_safe\_haven/administration/users/user\_handler.py                           |      100 |       73 |     27% |32-69, 75-81, 85, 91-97, 105-124, 135-137, 145-159, 167-206, 214-219 |
| data\_safe\_haven/allowlist/\_\_init\_\_.py                                       |        2 |        0 |    100% |           |
| data\_safe\_haven/allowlist/allowlist.py                                          |       39 |        3 |     92% |     50-52 |
| data\_safe\_haven/commands/\_\_init\_\_.py                                        |        2 |        0 |    100% |           |
| data\_safe\_haven/commands/allowlist.py                                           |       77 |       23 |     70% |39-44, 52-54, 66-70, 73-74, 101-103, 135-136, 143-145, 174, 181-183 |
| data\_safe\_haven/commands/cli.py                                                 |       30 |        3 |     90% |57, 60, 105 |
| data\_safe\_haven/commands/config.py                                              |      122 |        3 |     98% |   232-234 |
| data\_safe\_haven/commands/context.py                                             |       72 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                              |       19 |        0 |    100% |           |
| data\_safe\_haven/commands/shm.py                                                 |       85 |       27 |     68% |52, 67, 69, 71, 73-100, 119-124, 135, 156-157 |
| data\_safe\_haven/commands/sre.py                                                 |       86 |       15 |     83% |57-65, 69-73, 170-179, 227-231, 245-248 |
| data\_safe\_haven/commands/users.py                                               |      129 |       26 |     80% |40-51, 92-93, 167-172, 175-176, 203-211, 257-283 |
| data\_safe\_haven/config/\_\_init\_\_.py                                          |        7 |        0 |    100% |           |
| data\_safe\_haven/config/config\_sections.py                                      |       49 |        0 |    100% |           |
| data\_safe\_haven/config/context.py                                               |       78 |        1 |     99% |       123 |
| data\_safe\_haven/config/context\_manager.py                                      |       93 |        4 |     96% |97-100, 112-115 |
| data\_safe\_haven/config/dsh\_pulumi\_config.py                                   |       40 |        0 |    100% |           |
| data\_safe\_haven/config/dsh\_pulumi\_project.py                                  |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/config/shm\_config.py                                           |       23 |        7 |     70% |     33-41 |
| data\_safe\_haven/config/sre\_config.py                                           |       53 |        0 |    100% |           |
| data\_safe\_haven/console/\_\_init\_\_.py                                         |        4 |        0 |    100% |           |
| data\_safe\_haven/console/format.py                                               |       11 |        0 |    100% |           |
| data\_safe\_haven/console/pretty.py                                               |        5 |        0 |    100% |           |
| data\_safe\_haven/console/prompts.py                                              |        9 |        0 |    100% |           |
| data\_safe\_haven/directories.py                                                  |       15 |        1 |     93% |        20 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                      |       33 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        7 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_sdk.py                                      |      526 |      352 |     33% |123-129, 131-132, 158-159, 188-192, 197-205, 222-238, 254-255, 265-266, 285-298, 300-301, 336-340, 342-343, 363-391, 409-432, 448-471, 488-552, 567-588, 604-622, 635-664, 681-707, 724-744, 758-767, 800-813, 821-834, 871, 873-874, 891-902, 918-948, 951-976, 991-997, 1025-1029, 1043, 1051-1052, 1055-1057, 1069-1094, 1111-1126, 1139-1170, 1182-1235, 1243-1279, 1296-1331, 1348-1367, 1381-1413, 1429-1445, 1479-1494, 1512-1531 |
| data\_safe\_haven/external/api/credentials.py                                     |       98 |        7 |     93% |219-222, 231-235 |
| data\_safe\_haven/external/api/graph\_api.py                                      |      422 |      320 |     24% |112, 126-127, 129-131, 143-168, 182-265, 278-317, 327-353, 366-437, 448-462, 465-472, 477-484, 493-497, 500-509, 512-521, 544-552, 567-608, 623-672, 684, 697-711, 734, 767-771, 782-795, 806-822, 833-845, 858-868, 882-884, 898-905, 909-918, 931-968, 979-988, 1000-1023, 1033-1096 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-90, 100-125 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      120 |       83 |     31% |40-50, 57-58, 62, 76-80, 86-90, 94-107, 113-120, 128-165, 169-230 |
| data\_safe\_haven/external/interface/pulumi\_account.py                           |       21 |        7 |     67% |27-28, 33-45 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/network.py                                            |       15 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       61 |       11 |     82% |22, 78-87, 102-104, 109 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/dockerhub\_credentials.py                 |        6 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                             |       25 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/transformations.py                        |       57 |       31 |     46% |13, 16-17, 24, 31-32, 39-40, 45-48, 55, 66-81, 88-89, 94-97, 102-105, 110-113 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py             |        8 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/entra\_application.py       |       27 |       13 |     52% |23-30, 53, 78, 102-151 |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py       |       15 |        9 |     40% |15-18, 30-66 |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py |       24 |       16 |     33% |22-28, 41-110 |
| data\_safe\_haven/infrastructure/components/composite/nfsv3\_blob\_container.py   |       21 |       14 |     33% |22-29, 39-76 |
| data\_safe\_haven/infrastructure/components/composite/nfsv3\_storage\_account.py  |       23 |       13 |     43% |22-27, 50-136 |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py     |       27 |       19 |     30% |24-31, 44-143 |
| data\_safe\_haven/infrastructure/components/composite/virtual\_machine.py         |       63 |       44 |     30% |37-58, 62, 66, 78-103, 116-285 |
| data\_safe\_haven/infrastructure/components/dynamic/\_\_init\_\_.py               |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py       |       43 |       27 |     37% |29-50, 56-68, 76-87, 97-98, 102, 114 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py    |       29 |       11 |     62% |41-54, 72-75, 139, 149, 168-170 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       71 |       48 |     32% |27-31, 37-40, 49-62, 71-86, 94-109, 119-121, 124-133, 146 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       97 |       66 |     32% |39-44, 50-137, 145-163, 173-179, 188-198, 212 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        4 |     76% |39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       68 |       40 |     41% |    51-443 |
| data\_safe\_haven/infrastructure/programs/imperative\_shm.py                      |       78 |       55 |     29% |27-31, 39-172, 188-195 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       25 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       27 |       17 |     37% |34-43, 57-196 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |19-24, 40-166 |
| data\_safe\_haven/infrastructure/programs/sre/clamav\_mirror.py                   |       25 |       16 |     36% |33-41, 55-170 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       87 |       72 |     17% |68-92, 110-815 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       24 |       16 |     33% |28-34, 48-100 |
| data\_safe\_haven/infrastructure/programs/sre/desired\_state.py                   |       49 |       34 |     31% |66-88, 102-230, 234 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       42 |       29 |     31% |38-43, 57-335 |
| data\_safe\_haven/infrastructure/programs/sre/entra.py                            |       26 |       16 |     38% |27-30, 42-121 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       38 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       45 |       34 |     24% |46-64, 78-362 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       43 |       30 |     30% |48-67, 81-341 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       30 |       21 |     30% |39-51, 67-244 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       28 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |      101 |       91 |     10% |37-53, 67-2065 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       46 |       34 |     26% |52-92, 117-410 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       41 |       29 |     29% |41-55, 69-350 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       45 |       31 |     31% |51-79, 95-174 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       52 |       29 |     44% |41-67, 70-76, 90-141 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      251 |      127 |     49% |69-83, 87, 140-142, 155-165, 169-182, 194-202, 224-231, 241-243, 247-256, 260-286, 309, 313-318, 328-330, 339-341, 345-358, 362-369, 383-388, 397-405, 409-419, 434-436 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                               |       38 |        0 |    100% |           |
| data\_safe\_haven/logging/non\_logging\_singleton.py                              |        7 |        1 |     86% |        14 |
| data\_safe\_haven/logging/plain\_file\_handler.py                                 |       21 |        1 |     95% |        36 |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       43 |       30 |     30% |27-54, 66-69, 73-78, 82-122, 132-133 |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       41 |        3 |     93% | 45-46, 81 |
| data\_safe\_haven/serialisers/context\_base.py                                    |       15 |        2 |     87% |    15, 20 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       48 |        0 |    100% |           |
| data\_safe\_haven/singleton.py                                                    |        8 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       21 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |      114 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       24 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       70 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
|                                                                         **TOTAL** | **4940** | **2175** | **56%** |           |


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