# Repository Coverage

[Full report](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

| Name                                                                              |    Stmts |     Miss |   Cover |   Missing |
|---------------------------------------------------------------------------------- | -------: | -------: | ------: | --------: |
| data\_safe\_haven/\_\_init\_\_.py                                                 |        4 |        0 |    100% |           |
| data\_safe\_haven/administration/\_\_init\_\_.py                                  |        0 |        0 |    100% |           |
| data\_safe\_haven/administration/users/\_\_init\_\_.py                            |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/users/entra\_users.py                            |       69 |       55 |     20% |24-25, 34-69, 78-102, 111-117, 126-135, 144-151, 160-166 |
| data\_safe\_haven/administration/users/guacamole\_users.py                        |       20 |       11 |     45% |20-45, 49-66 |
| data\_safe\_haven/administration/users/research\_user.py                          |       31 |       20 |     35% |17-25, 29, 33-35, 39-41, 44-51, 54 |
| data\_safe\_haven/administration/users/user\_handler.py                           |      100 |       78 |     22% |22-24, 32-69, 75-81, 85, 91-97, 105-124, 132-137, 145-159, 167-206, 214-219 |
| data\_safe\_haven/commands/\_\_init\_\_.py                                        |        2 |        0 |    100% |           |
| data\_safe\_haven/commands/cli.py                                                 |       28 |        3 |     89% |56, 59, 99 |
| data\_safe\_haven/commands/config.py                                              |       49 |        0 |    100% |           |
| data\_safe\_haven/commands/context.py                                             |       71 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                              |       22 |        0 |    100% |           |
| data\_safe\_haven/commands/shm.py                                                 |       73 |       20 |     73% |69, 71, 73, 75-85, 92-102, 117-122 |
| data\_safe\_haven/commands/sre.py                                                 |       58 |       10 |     83% |61-65, 113-121, 160-164, 179-182 |
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
| data\_safe\_haven/external/api/azure\_sdk.py                                      |      433 |      306 |     29% |124-135, 195-199, 201-202, 222-250, 268-291, 307-330, 347-407, 422-443, 459-477, 490-519, 536-561, 578-598, 612-621, 654-667, 675-688, 708-725, 727-728, 757-785, 788-813, 841-845, 859, 867-868, 871-873, 885-910, 927-948, 961-992, 1004-1057, 1065-1101, 1118-1153, 1170-1189, 1203-1235, 1253-1267 |
| data\_safe\_haven/external/api/credentials.py                                     |       81 |        0 |    100% |           |
| data\_safe\_haven/external/api/graph\_api.py                                      |      428 |      325 |     24% |111, 125-126, 128-130, 142-167, 181-264, 277-316, 324-350, 360-386, 399-470, 481-495, 498-505, 510-517, 520-529, 532-541, 564-572, 587-628, 643-692, 704, 717-731, 754, 787-791, 802-815, 826-842, 853-862, 875-885, 899-901, 915-922, 926-935, 948-985, 996-1005, 1017-1040, 1050-1103 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-90, 100-125 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      118 |       81 |     31% |46-56, 63-64, 68, 82-86, 92-96, 100-113, 119-126, 134-169, 173-234 |
| data\_safe\_haven/external/interface/pulumi\_account.py                           |       20 |        7 |     65% |26-27, 32-43 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/network.py                                            |       20 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       63 |       11 |     83% |22, 83-92, 107-109, 114 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/dockerhub\_credentials.py                 |        6 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                             |       24 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/transformations.py                        |       57 |       34 |     40% |12-17, 24, 31-32, 39-40, 45-48, 55, 66-81, 88-89, 94-97, 102-105, 110-113 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py             |        5 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py       |       15 |        9 |     40% |15-18, 30-66 |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py |       24 |       16 |     33% |22-28, 41-110 |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py     |       25 |       17 |     32% |22-28, 41-132 |
| data\_safe\_haven/infrastructure/components/composite/virtual\_machine.py         |       63 |       44 |     30% |37-58, 62, 66, 78-103, 116-282 |
| data\_safe\_haven/infrastructure/components/dynamic/\_\_init\_\_.py               |        5 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py       |       43 |       27 |     37% |29-50, 56-68, 76-87, 97-98, 102, 114 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py    |       29 |       11 |     62% |41-54, 72-75, 133, 143, 162-164 |
| data\_safe\_haven/infrastructure/components/dynamic/entra\_application.py         |       77 |       55 |     29% |27-32, 37-38, 42-90, 98-104, 114-121, 124-147, 156-165, 181 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       71 |       48 |     32% |27-31, 37-40, 49-62, 71-86, 94-109, 119-121, 124-133, 146 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       90 |       66 |     27% |37-42, 48-127, 135-153, 163-164, 167-181, 194 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        6 |     65% |22-23, 39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       54 |       30 |     44% |    73-393 |
| data\_safe\_haven/infrastructure/programs/imperative\_shm.py                      |       64 |       50 |     22% |26-30, 38-144, 152-160 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       25 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       26 |       16 |     38% |32-40, 54-187 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |19-24, 40-166 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       94 |       78 |     17% |63-93, 111-939 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       24 |       16 |     33% |28-34, 48-99 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       36 |       23 |     36% |36-40, 54-323 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       27 |       18 |     33% |36-57, 73-305 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       43 |       32 |     26% |44-61, 75-338 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       41 |       28 |     32% |46-64, 78-317 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       30 |       21 |     30% |39-50, 66-251 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       28 |       17 |     39% |32-36, 50-213 |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |       90 |       80 |     11% |38-52, 66-1912 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       47 |       35 |     26% |57-97, 122-419 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       40 |       28 |     30% |39-52, 66-337 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       44 |       31 |     30% |49-76, 92-184 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       60 |       37 |     38% |52-88, 91-97, 111-170 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      249 |      130 |     48% |69-83, 87, 140-142, 151-161, 165-178, 190-198, 220-227, 237-239, 243-252, 256-281, 285-288, 292-297, 307-309, 321-323, 327-340, 344-351, 365-370, 379-388, 392-402, 417-419 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                               |       41 |        0 |    100% |           |
| data\_safe\_haven/logging/non\_logging\_singleton.py                              |        7 |        1 |     86% |        14 |
| data\_safe\_haven/logging/plain\_file\_handler.py                                 |       16 |        0 |    100% |           |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       48 |       34 |     29% |29-57, 69-72, 76-77, 81-86, 90-126, 136-138 |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       33 |        0 |    100% |           |
| data\_safe\_haven/serialisers/context\_base.py                                    |       15 |        2 |     87% |    15, 20 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       43 |        0 |    100% |           |
| data\_safe\_haven/singleton.py                                                    |        8 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       18 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |       91 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       23 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       64 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
|                                                                         **TOTAL** | **4313** | **2073** | **52%** |           |


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