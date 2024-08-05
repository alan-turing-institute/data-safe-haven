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
| data\_safe\_haven/commands/config.py                                              |       78 |        3 |     96% |   146-148 |
| data\_safe\_haven/commands/context.py                                             |       72 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                              |       22 |        0 |    100% |           |
| data\_safe\_haven/commands/shm.py                                                 |       73 |       25 |     66% |52, 66, 68, 70, 72-99, 114-119, 130 |
| data\_safe\_haven/commands/sre.py                                                 |       58 |       10 |     83% |56-60, 108-116, 155-159, 174-177 |
| data\_safe\_haven/commands/users.py                                               |      118 |       32 |     73% |39-50, 78-88, 134-155, 185-193, 239-265 |
| data\_safe\_haven/config/\_\_init\_\_.py                                          |        7 |        0 |    100% |           |
| data\_safe\_haven/config/config\_sections.py                                      |       27 |        0 |    100% |           |
| data\_safe\_haven/config/context.py                                               |       57 |        1 |     98% |        87 |
| data\_safe\_haven/config/context\_manager.py                                      |       93 |        4 |     96% |97-100, 112-115 |
| data\_safe\_haven/config/dsh\_pulumi\_config.py                                   |       40 |        0 |    100% |           |
| data\_safe\_haven/config/dsh\_pulumi\_project.py                                  |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/config/shm\_config.py                                           |       18 |        3 |     83% |     29-33 |
| data\_safe\_haven/config/sre\_config.py                                           |       25 |        0 |    100% |           |
| data\_safe\_haven/console/\_\_init\_\_.py                                         |        4 |        0 |    100% |           |
| data\_safe\_haven/console/format.py                                               |       11 |        0 |    100% |           |
| data\_safe\_haven/console/pretty.py                                               |        5 |        0 |    100% |           |
| data\_safe\_haven/console/prompts.py                                              |        9 |        0 |    100% |           |
| data\_safe\_haven/directories.py                                                  |       15 |        1 |     93% |        20 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                      |       31 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        7 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_sdk.py                                      |      441 |      294 |     33% |123-134, 160-161, 200-204, 206-207, 227-255, 273-296, 312-335, 352-412, 427-448, 464-482, 495-524, 541-566, 583-603, 617-626, 659-672, 680-693, 730, 732-733, 762-790, 793-818, 846-850, 864, 872-873, 876-878, 890-915, 932-953, 966-997, 1009-1062, 1070-1106, 1123-1158, 1175-1194, 1208-1240, 1274-1288 |
| data\_safe\_haven/external/api/credentials.py                                     |       86 |        0 |    100% |           |
| data\_safe\_haven/external/api/graph\_api.py                                      |      428 |      325 |     24% |110, 124-125, 127-129, 141-166, 180-263, 276-315, 323-349, 359-385, 398-469, 480-494, 497-504, 509-516, 519-528, 531-540, 563-571, 586-627, 642-691, 703, 716-730, 753, 786-790, 801-814, 825-841, 852-861, 874-884, 898-900, 914-921, 925-934, 947-984, 995-1004, 1016-1039, 1049-1102 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-90, 100-125 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      118 |       81 |     31% |40-50, 57-58, 62, 76-80, 86-90, 94-107, 113-120, 128-163, 167-228 |
| data\_safe\_haven/external/interface/pulumi\_account.py                           |       20 |        7 |     65% |26-27, 32-43 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/network.py                                            |       15 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       63 |       11 |     83% |22, 83-92, 107-109, 114 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/dockerhub\_credentials.py                 |        6 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                             |       25 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/transformations.py                        |       57 |       34 |     40% |12-17, 24, 31-32, 39-40, 45-48, 55, 66-81, 88-89, 94-97, 102-105, 110-113 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py             |        5 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py       |       15 |        9 |     40% |15-18, 30-66 |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py |       24 |       16 |     33% |22-28, 41-110 |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py     |       27 |       19 |     30% |24-31, 44-143 |
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
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       57 |       31 |     46% |    50-389 |
| data\_safe\_haven/infrastructure/programs/imperative\_shm.py                      |       64 |       50 |     22% |26-30, 38-144, 152-160 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       25 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       26 |       16 |     38% |32-40, 54-187 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |19-24, 40-166 |
| data\_safe\_haven/infrastructure/programs/sre/clamav\_mirror.py                   |       24 |       15 |     38% |31-38, 52-161 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       94 |       78 |     17% |63-93, 111-939 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       24 |       16 |     33% |28-34, 48-100 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       36 |       23 |     36% |36-40, 54-323 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       28 |       19 |     32% |37-61, 77-334 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       43 |       32 |     26% |44-61, 75-339 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       41 |       28 |     32% |46-64, 78-318 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       30 |       21 |     30% |39-50, 66-251 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       28 |       17 |     39% |25-29, 43-206 |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |       93 |       83 |     11% |35-49, 63-2039 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       47 |       35 |     26% |53-93, 118-416 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       40 |       28 |     30% |39-52, 66-337 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       43 |       30 |     30% |49-76, 92-168 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       61 |       38 |     38% |50-87, 90-96, 110-170 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      249 |      130 |     48% |69-83, 87, 140-142, 151-161, 165-178, 190-198, 220-227, 237-239, 243-252, 256-281, 285-288, 292-297, 307-309, 321-323, 327-340, 344-351, 365-370, 379-388, 392-402, 417-419 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                               |       41 |        0 |    100% |           |
| data\_safe\_haven/logging/non\_logging\_singleton.py                              |        7 |        1 |     86% |        14 |
| data\_safe\_haven/logging/plain\_file\_handler.py                                 |       16 |        0 |    100% |           |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       48 |       34 |     29% |29-57, 69-72, 76-77, 81-86, 90-126, 136-138 |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       38 |        3 |     92% | 45-46, 78 |
| data\_safe\_haven/serialisers/context\_base.py                                    |       15 |        2 |     87% |    15, 20 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       43 |        0 |    100% |           |
| data\_safe\_haven/singleton.py                                                    |        8 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       18 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |       93 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       23 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       65 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
|                                                                         **TOTAL** | **4401** | **2094** | **52%** |           |


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