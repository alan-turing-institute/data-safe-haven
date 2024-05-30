# Repository Coverage

[Full report](https://htmlpreview.github.io/?https://github.com/alan-turing-institute/data-safe-haven/blob/python-coverage-comment-action-data/htmlcov/index.html)

| Name                                                                              |    Stmts |     Miss |   Cover |   Missing |
|---------------------------------------------------------------------------------- | -------: | -------: | ------: | --------: |
| data\_safe\_haven/\_\_init\_\_.py                                                 |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/\_\_init\_\_.py                                  |        0 |        0 |    100% |           |
| data\_safe\_haven/administration/users/\_\_init\_\_.py                            |        2 |        0 |    100% |           |
| data\_safe\_haven/administration/users/entra\_users.py                            |       68 |       53 |     22% |27-29, 38-70, 79-103, 112-118, 127-136, 145-152, 161-167 |
| data\_safe\_haven/administration/users/guacamole\_users.py                        |       24 |       13 |     46% |23-51, 55-72 |
| data\_safe\_haven/administration/users/research\_user.py                          |       30 |       19 |     37% |16-23, 27, 31-33, 37-39, 42-49, 52 |
| data\_safe\_haven/administration/users/user\_handler.py                           |      105 |       83 |     21% |24-29, 37-73, 77-84, 88, 94-104, 112-133, 141-146, 154-168, 176-215, 223-228 |
| data\_safe\_haven/commands/\_\_init\_\_.py                                        |        2 |        0 |    100% |           |
| data\_safe\_haven/commands/cli.py                                                 |       36 |       14 |     61% |56-63, 99-104 |
| data\_safe\_haven/commands/config.py                                              |       39 |        0 |    100% |           |
| data\_safe\_haven/commands/context.py                                             |       64 |        0 |    100% |           |
| data\_safe\_haven/commands/pulumi.py                                              |       30 |        4 |     87% |     56-68 |
| data\_safe\_haven/commands/shm.py                                                 |       46 |       27 |     41% |44-73, 83-84, 93-117 |
| data\_safe\_haven/commands/sre.py                                                 |       62 |       47 |     24% |32-131, 139-173 |
| data\_safe\_haven/commands/users.py                                               |      120 |       51 |     58% |40-56, 73-85, 123-149, 175-188, 225-256 |
| data\_safe\_haven/config/\_\_init\_\_.py                                          |        4 |        0 |    100% |           |
| data\_safe\_haven/config/config.py                                                |      104 |        7 |     93% |71, 77, 89, 166, 216, 228-229 |
| data\_safe\_haven/config/pulumi.py                                                |       40 |        0 |    100% |           |
| data\_safe\_haven/config/pulumi\_project.py                                       |       11 |        2 |     82% |    15, 19 |
| data\_safe\_haven/context/\_\_init\_\_.py                                         |        3 |        0 |    100% |           |
| data\_safe\_haven/context/context.py                                              |       60 |        1 |     98% |        92 |
| data\_safe\_haven/context/context\_settings.py                                    |       83 |        6 |     93% |100-103, 105-106, 111-114 |
| data\_safe\_haven/context\_infrastructure/\_\_init\_\_.py                         |        2 |        0 |    100% |           |
| data\_safe\_haven/context\_infrastructure/infrastructure.py                       |       40 |       28 |     30% |21-25, 33-83, 91-95 |
| data\_safe\_haven/exceptions/\_\_init\_\_.py                                      |       28 |        0 |    100% |           |
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        7 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_api.py                                      |      344 |      277 |     19% |83-98, 133-144, 161-186, 203-263, 278-300, 316-334, 347-376, 393-418, 435-453, 467-476, 509-521, 529-542, 555-582, 598-626, 629-654, 666-691, 708-729, 742-773, 785-830, 838-869, 886-921, 938-957, 971-1002, 1020-1034 |
| data\_safe\_haven/external/api/azure\_cli.py                                      |       47 |       24 |     49% |31-32, 40-63, 67-81 |
| data\_safe\_haven/external/api/graph\_api.py                                      |      437 |      385 |     12% |30-37, 40-41, 82-95, 106-130, 142-167, 181-264, 277-312, 320-346, 356-382, 390-433, 443-465, 478-530, 541-555, 558-565, 570-577, 580-589, 592-601, 624-632, 647-688, 703-752, 763-780, 791-808, 819-836, 847-865, 876-885, 898-908, 919-924, 938-945, 949-958, 971-1008, 1019-1028, 1040-1065, 1075-1128 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_authenticator.py                      |       47 |       25 |     47% |35-40, 44-49, 54-70 |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-92, 102-127 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       34 |        4 |     88% |23-24, 44-45 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      117 |       81 |     31% |45-57, 64-65, 69, 83-87, 93-97, 101-114, 120-127, 135-170, 174-235 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        2 |        0 |    100% |           |
| data\_safe\_haven/functions/strings.py                                            |       61 |       20 |     67% |26, 77-86, 101-103, 108, 118-126 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                             |       26 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/transformations.py                        |       57 |       34 |     40% |12-17, 24, 31-32, 39-40, 45-48, 55, 66-81, 88-89, 94-97, 102-105, 110-113 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py             |        5 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py       |       16 |       10 |     38% |16-20, 32-68 |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py |       24 |       16 |     33% |22-28, 41-109 |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py     |       24 |       16 |     33% |22-28, 41-122 |
| data\_safe\_haven/infrastructure/components/composite/virtual\_machine.py         |       79 |       57 |     28% |41-79, 83, 87, 98-118, 130-155, 168-310 |
| data\_safe\_haven/infrastructure/components/dynamic/\_\_init\_\_.py               |        6 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py       |       41 |       26 |     37% |29-50, 56-68, 76-87, 97-98, 110 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py    |       35 |       20 |     43% |28-41, 50, 57-58, 63-65, 70-72, 81-83, 87-88, 97-99 |
| data\_safe\_haven/infrastructure/components/dynamic/entra\_application.py         |       77 |       55 |     29% |28-34, 40-65, 69-117, 125-131, 141-143, 152-162, 177 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       72 |       48 |     33% |27-31, 37-40, 49-62, 71-80, 84-99, 107-122, 132-134, 147 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_upload.py               |       48 |       30 |     38% |29-38, 44-77, 85-95, 110-118, 128-130, 143 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       91 |       66 |     27% |37-42, 48-62, 66-145, 153-171, 181-182, 195 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        6 |     65% |22-23, 39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_shm.py                     |       19 |        5 |     74% |     25-58 |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       51 |       33 |     35% |66-73, 77-394 |
| data\_safe\_haven/infrastructure/programs/shm/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/shm/monitoring.py                       |       32 |       21 |     34% |35-41, 55-184 |
| data\_safe\_haven/infrastructure/programs/shm/networking.py                       |       38 |       29 |     24% |23-30, 44-202 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       24 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       29 |       19 |     34% |34-44, 58-200 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |18-22, 38-173 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       85 |       69 |     19% |59-87, 90, 108-797 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       26 |       18 |     31% |31-41, 55-107 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       39 |       26 |     33% |35-41, 55-308 |
| data\_safe\_haven/infrastructure/programs/sre/firewall.py                         |       27 |       18 |     33% |35-56, 72-265 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       46 |       35 |     24% |46-66, 80-334 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       43 |       30 |     30% |48-68, 82-312 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       32 |       23 |     28% |39-51, 67-253 |
| data\_safe\_haven/infrastructure/programs/sre/maintenance.py                      |       15 |        7 |     53% |20-22, 36-70 |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |      122 |      112 |      8% |41-96, 110-1816 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       48 |       36 |     25% |56-95, 120-420 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       42 |       30 |     29% |40-55, 69-330 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       47 |       34 |     28% |48-77, 93-204 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       69 |       51 |     26% |54-88, 91-97, 111-214, 231-248 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      248 |      135 |     46% |37-38, 47-58, 101-106, 110, 160-162, 167, 171, 175-185, 189-195, 201, 205, 209-218, 222-281, 285-288, 292-297, 301-311, 315-317, 321-337, 341-347, 360-364, 373-379, 383-395, 417-419, 458-459 |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       48 |       34 |     29% |29-57, 69-72, 76-77, 81-86, 90-126, 136-138 |
| data\_safe\_haven/resources/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       28 |        0 |    100% |           |
| data\_safe\_haven/serialisers/context\_base.py                                    |       14 |        2 |     86% |    14, 19 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       43 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       16 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |       78 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        5 |        0 |    100% |           |
| data\_safe\_haven/utility/directories.py                                          |        8 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/utility/logger.py                                               |      108 |       54 |     50% |28-30, 35-37, 41-42, 87-88, 92-93, 117-120, 129-132, 159, 167-180, 184-190, 194, 200-201, 215-223, 232-234 |
| data\_safe\_haven/utility/singleton.py                                            |        8 |        0 |    100% |           |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       20 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       54 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
|                                                                         **TOTAL** | **4359** | **2435** | **44%** |           |


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