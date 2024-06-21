# Repository Coverage

[Full report](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

| Name                                                                              |    Stmts |     Miss |   Cover |   Missing |
|---------------------------------------------------------------------------------- | -------: | -------: | ------: | --------: |
| data\_safe\_haven/\_\_init\_\_.py                                                 |        4 |        0 |    100% |           |
| data\_safe\_haven/administration/\_\_init\_\_.py                                  |        0 |        0 |    100% |           |
| data\_safe\_haven/administration/users/\_\_init\_\_.py                            |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/users/entra\_users.py                            |       68 |       53 |     22% |27-29, 38-70, 79-103, 112-118, 127-136, 145-152, 161-167 |
| data\_safe\_haven/administration/users/guacamole\_users.py                        |       24 |       13 |     46% |23-51, 55-72 |
| data\_safe\_haven/administration/users/research\_user.py                          |       30 |       19 |     37% |16-23, 27, 31-33, 37-39, 42-49, 52 |
| data\_safe\_haven/administration/users/user\_handler.py                           |      104 |       81 |     22% |24-28, 36-72, 76-82, 86, 92-103, 111-130, 138-143, 151-165, 173-212, 220-225 |
| data\_safe\_haven/commands/\_\_init\_\_.py                                        |        2 |        0 |    100% |           |
| data\_safe\_haven/commands/cli.py                                                 |       29 |        3 |     90% |57, 60, 100 |
| data\_safe\_haven/commands/config.py                                              |       75 |        0 |    100% |           |
| data\_safe\_haven/commands/context.py                                             |      105 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                              |       31 |        4 |     87% |     58-71 |
| data\_safe\_haven/commands/shm.py                                                 |       46 |       27 |     41% |44-73, 83-84, 93-117 |
| data\_safe\_haven/commands/sre.py                                                 |       53 |       40 |     25% |30-110, 118-152 |
| data\_safe\_haven/commands/users.py                                               |      121 |       51 |     58% |39-55, 79-91, 133-159, 185-198, 236-267 |
| data\_safe\_haven/config/\_\_init\_\_.py                                          |        5 |        0 |    100% |           |
| data\_safe\_haven/config/config\_sections.py                                      |       67 |        2 |     97% |   48, 154 |
| data\_safe\_haven/config/dsh\_pulumi\_config.py                                   |       40 |        0 |    100% |           |
| data\_safe\_haven/config/dsh\_pulumi\_project.py                                  |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/config/shm\_config.py                                           |       12 |        0 |    100% |           |
| data\_safe\_haven/config/sre\_config.py                                           |       26 |        0 |    100% |           |
| data\_safe\_haven/context/\_\_init\_\_.py                                         |        3 |        0 |    100% |           |
| data\_safe\_haven/context/context.py                                              |       60 |        1 |     98% |        92 |
| data\_safe\_haven/context/context\_settings.py                                    |       85 |        6 |     93% |102-105, 107-108, 113-116 |
| data\_safe\_haven/context\_infrastructure/\_\_init\_\_.py                         |        2 |        0 |    100% |           |
| data\_safe\_haven/context\_infrastructure/infrastructure.py                       |       43 |       19 |     56% |40-78, 83-84, 99-100 |
| data\_safe\_haven/directories.py                                                  |       15 |        1 |     93% |        20 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                      |       36 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        8 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_api.py                                      |      349 |      276 |     21% |82-97, 132-147, 164-189, 206-266, 281-303, 319-337, 357-376, 378-379, 396-421, 438-456, 470-479, 512-524, 532-545, 558-585, 601-629, 632-657, 669-694, 711-732, 745-776, 788-833, 847-872, 876-877, 894-929, 946-965, 979-1010, 1028-1042 |
| data\_safe\_haven/external/api/azure\_cli.py                                      |       49 |       24 |     51% |33-34, 42-65, 69-83 |
| data\_safe\_haven/external/api/graph\_api.py                                      |      438 |      384 |     12% |32-39, 42-43, 83-96, 107-131, 143-168, 182-265, 278-313, 321-347, 357-383, 391-434, 444-466, 479-531, 542-556, 559-566, 571-578, 581-590, 593-602, 625-633, 648-689, 704-753, 764-781, 792-809, 820-837, 848-866, 877-886, 899-909, 920-925, 939-946, 950-959, 972-1009, 1020-1029, 1041-1066, 1076-1129 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_authenticator.py                      |       47 |       23 |     51% |38-41, 45-50, 55-71 |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-92, 102-127 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       37 |        4 |     89% |23-24, 48-49 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      118 |       81 |     31% |46-58, 65-66, 70, 84-88, 94-98, 102-115, 121-128, 136-171, 175-236 |
| data\_safe\_haven/external/interface/pulumi\_account.py                           |       21 |        7 |     67% |26-27, 36-47 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        2 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       61 |       20 |     67% |22, 78-87, 102-104, 109, 119-127 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        2 |        0 |    100% |           |
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
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py       |       41 |       26 |     37% |29-50, 56-68, 76-87, 97-98, 110 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py    |       35 |       20 |     43% |28-41, 50, 57-58, 63-65, 70-72, 81-83, 87-88, 97-99 |
| data\_safe\_haven/infrastructure/components/dynamic/entra\_application.py         |       77 |       55 |     29% |28-34, 40-63, 67-115, 123-129, 139-141, 150-160, 175 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       72 |       48 |     33% |27-31, 37-40, 49-62, 71-80, 84-99, 107-122, 132-134, 147 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_upload.py               |       48 |       30 |     38% |29-38, 44-77, 85-95, 110-118, 128-130, 143 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       91 |       66 |     27% |37-42, 48-62, 66-145, 153-171, 181-182, 195 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        6 |     65% |22-23, 39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_shm.py                     |       16 |        3 |     81% |     24-41 |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       54 |       36 |     33% |66-73, 77-379 |
| data\_safe\_haven/infrastructure/programs/shm/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/shm/networking.py                       |       23 |       15 |     35% |21-27, 41-98 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       24 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       29 |       19 |     34% |34-44, 58-200 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |18-22, 38-173 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       83 |       68 |     18% |59-85, 103-786 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       26 |       18 |     31% |31-41, 55-107 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       36 |       23 |     36% |33-35, 49-317 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       27 |       18 |     33% |35-56, 72-265 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       45 |       34 |     24% |45-64, 78-332 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       42 |       29 |     31% |47-66, 80-310 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       32 |       23 |     28% |39-51, 67-253 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       28 |       17 |     39% |32-35, 49-214 |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |       88 |       78 |     11% |38-52, 66-1810 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       48 |       36 |     25% |56-95, 120-420 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       42 |       30 |     29% |40-55, 69-330 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       46 |       33 |     28% |47-75, 91-200 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       69 |       51 |     26% |54-88, 91-97, 111-214, 231-248 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      231 |      130 |     44% |74-79, 83, 133-135, 140, 144, 148-158, 162-168, 174, 178, 182-191, 195-258, 262-265, 269-274, 278-288, 292-294, 298-314, 318-324, 337-341, 350-356, 360-372, 394-396, 434-435 |
| data\_safe\_haven/logging/\_\_init\_\_.py                                         |        2 |        0 |    100% |           |
| data\_safe\_haven/logging/logger.py                                               |       32 |        0 |    100% |           |
| data\_safe\_haven/logging/plain\_file\_handler.py                                 |       14 |        0 |    100% |           |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       48 |       34 |     29% |29-57, 69-72, 76-77, 81-86, 90-126, 136-138 |
| data\_safe\_haven/resources/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       28 |        0 |    100% |           |
| data\_safe\_haven/serialisers/context\_base.py                                    |       14 |        2 |     86% |    14, 19 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       43 |        0 |    100% |           |
| data\_safe\_haven/singleton.py                                                    |        8 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       17 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |       80 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        3 |        0 |    100% |           |
| data\_safe\_haven/utility/console.py                                              |       11 |        8 |     27% |     17-25 |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/utility/prompts.py                                              |        9 |        0 |    100% |           |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       20 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       59 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
|                                                                         **TOTAL** | **4340** | **2281** | **47%** |           |


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