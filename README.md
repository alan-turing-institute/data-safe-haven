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
| data\_safe\_haven/commands/shm.py                                                 |       73 |       23 |     68% |69, 71, 73, 75-102, 117-122 |
| data\_safe\_haven/commands/sre.py                                                 |       58 |       10 |     83% |61-65, 112-120, 159-163, 175-178 |
| data\_safe\_haven/commands/users.py                                               |      118 |       32 |     73% |44-55, 83-93, 139-160, 190-198, 244-270 |
| data\_safe\_haven/config/\_\_init\_\_.py                                          |        7 |        0 |    100% |           |
| data\_safe\_haven/config/config\_sections.py                                      |       24 |        0 |    100% |           |
| data\_safe\_haven/config/context.py                                               |       56 |        1 |     98% |        88 |
| data\_safe\_haven/config/context\_manager.py                                      |       88 |        4 |     95% |102-105, 117-120 |
| data\_safe\_haven/config/dsh\_pulumi\_config.py                                   |       40 |        0 |    100% |           |
| data\_safe\_haven/config/dsh\_pulumi\_project.py                                  |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/config/shm\_config.py                                           |       18 |        3 |     83% |     29-33 |
| data\_safe\_haven/config/sre\_config.py                                           |       24 |        0 |    100% |           |
| data\_safe\_haven/console/\_\_init\_\_.py                                         |        4 |        0 |    100% |           |
| data\_safe\_haven/console/format.py                                               |       11 |        0 |    100% |           |
| data\_safe\_haven/console/pretty.py                                               |        5 |        0 |    100% |           |
| data\_safe\_haven/console/prompts.py                                              |        9 |        0 |    100% |           |
| data\_safe\_haven/directories.py                                                  |       15 |        1 |     93% |        20 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                      |       29 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        8 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_api.py                                      |      378 |      298 |     21% |91-102, 125, 155-159, 161-162, 182-210, 228-251, 267-290, 307-367, 382-404, 420-438, 451-480, 497-522, 539-557, 571-580, 613-625, 633-646, 666-683, 685-686, 702-730, 733-758, 770-795, 812-833, 846-877, 889-942, 950-986, 1003-1038, 1055-1074, 1088-1119, 1137-1151 |
| data\_safe\_haven/external/api/azure\_cli.py                                      |       64 |       38 |     41% |33-34, 42-65, 69-83, 87-105 |
| data\_safe\_haven/external/api/graph\_api.py                                      |      444 |      383 |     14% |30-37, 40-41, 88, 90, 105-129, 141-166, 180-263, 276-315, 323-349, 359-385, 393-436, 446-468, 481-535, 546-560, 563-570, 575-582, 585-594, 597-606, 629-637, 652-693, 708-757, 768-784, 795-811, 822-838, 849-866, 877-886, 899-909, 920-925, 939-946, 950-959, 972-1009, 1020-1029, 1041-1064, 1074-1127 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_authenticator.py                      |       47 |       23 |     51% |38-41, 45-50, 55-71 |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-90, 100-125 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      118 |       81 |     31% |46-56, 63-64, 68, 82-86, 92-96, 100-113, 119-126, 134-169, 173-234 |
| data\_safe\_haven/external/interface/pulumi\_account.py                           |       21 |        7 |     67% |26-27, 36-47 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/network.py                                            |       20 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       61 |       20 |     67% |22, 78-87, 102-104, 109, 119-127 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        3 |        0 |    100% |           |
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
| data\_safe\_haven/infrastructure/components/dynamic/entra\_application.py         |       77 |       55 |     29% |27-32, 37-38, 41-64, 68-116, 124-130, 140-141, 150-159, 175 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       71 |       48 |     32% |27-31, 37-40, 49-62, 70-79, 83-98, 106-121, 131-133, 146 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_upload.py               |       50 |       31 |     38% |29-38, 44-77, 85-95, 110-118, 122, 132-134, 147 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       90 |       66 |     27% |37-42, 47-61, 65-144, 152-170, 180-181, 194 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        6 |     65% |22-23, 39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       52 |       28 |     46% |    73-373 |
| data\_safe\_haven/infrastructure/programs/imperative\_shm.py                      |       64 |       50 |     22% |26-30, 38-144, 152-160 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       24 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       29 |       19 |     34% |34-44, 58-200 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |18-22, 38-173 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       83 |       68 |     18% |59-85, 103-786 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       26 |       18 |     31% |31-41, 55-107 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       36 |       23 |     36% |33-35, 49-317 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       27 |       18 |     33% |36-57, 73-303 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       45 |       34 |     24% |45-64, 78-332 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       42 |       29 |     31% |47-66, 80-310 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       32 |       23 |     28% |39-51, 67-253 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       28 |       17 |     39% |32-35, 49-214 |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |       88 |       78 |     11% |38-52, 66-1810 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       48 |       36 |     25% |56-95, 120-420 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       42 |       30 |     29% |40-55, 69-330 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       46 |       33 |     28% |47-75, 91-200 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       69 |       51 |     26% |54-88, 91-97, 111-214, 231-248 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      241 |      139 |     42% |68-82, 86, 139-141, 150, 154-164, 168-174, 180, 184, 188-197, 201-261, 265-268, 272-277, 281-289, 301-303, 307-320, 324-331, 345-350, 359-367, 371-381, 396-398 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                               |       38 |        0 |    100% |           |
| data\_safe\_haven/logging/plain\_file\_handler.py                                 |       16 |        0 |    100% |           |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       48 |       34 |     29% |29-57, 69-72, 76-77, 81-86, 90-126, 136-138 |
| data\_safe\_haven/resources/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       33 |        0 |    100% |           |
| data\_safe\_haven/serialisers/context\_base.py                                    |       15 |        2 |     87% |    15, 20 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       43 |        0 |    100% |           |
| data\_safe\_haven/singleton.py                                                    |        8 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       18 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |       85 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       23 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       64 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
|                                                                         **TOTAL** | **4333** | **2251** | **48%** |           |


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