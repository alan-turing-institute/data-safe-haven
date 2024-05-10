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
| data\_safe\_haven/commands/cli.py                                                 |       34 |       14 |     59% |55-62, 93-98 |
| data\_safe\_haven/commands/config.py                                              |       29 |        0 |    100% |           |
| data\_safe\_haven/commands/context.py                                             |       64 |        0 |    100% |           |
| data\_safe\_haven/commands/shm.py                                                 |       46 |       27 |     41% |44-73, 83-84, 93-117 |
| data\_safe\_haven/commands/sre.py                                                 |       65 |       50 |     23% |32-146, 154-188 |
| data\_safe\_haven/commands/users.py                                               |      100 |       79 |     21% |29-51, 57-75, 96-134, 149-168, 189-231 |
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
| data\_safe\_haven/external/\_\_init\_\_.py                                        |        8 |        0 |    100% |           |
| data\_safe\_haven/external/api/\_\_init\_\_.py                                    |        0 |        0 |    100% |           |
| data\_safe\_haven/external/api/azure\_api.py                                      |      443 |      377 |     15% |92-107, 124-192, 209-220, 237-262, 279-339, 354-376, 390-411, 427-460, 476-494, 507-536, 553-578, 595-613, 627-636, 648-657, 669-681, 689-702, 715-742, 746-764, 780-808, 811-836, 848-873, 890-911, 924-955, 967-1012, 1020-1051, 1054-1074, 1091-1126, 1143-1162, 1176-1207, 1220-1235, 1253-1267, 1276-1285 |
| data\_safe\_haven/external/api/azure\_cli.py                                      |       47 |       24 |     49% |31-32, 40-63, 67-81 |
| data\_safe\_haven/external/api/graph\_api.py                                      |      445 |      392 |     12% |30-37, 40-41, 82-95, 106-130, 142-167, 181-264, 277-312, 320-346, 356-382, 390-433, 443-465, 478-530, 541-555, 558-565, 570-577, 580-586, 589-598, 601-610, 633-641, 656-697, 712-761, 772-789, 800-817, 828-845, 856-874, 885-894, 907-917, 928-933, 947-954, 958-967, 980-1017, 1028-1037, 1049-1074, 1084-1137 |
| data\_safe\_haven/external/interface/\_\_init\_\_.py                              |        0 |        0 |    100% |           |
| data\_safe\_haven/external/interface/azure\_authenticator.py                      |       47 |       28 |     40% |27-31, 35-40, 44-49, 54-70 |
| data\_safe\_haven/external/interface/azure\_container\_instance.py                |       56 |       39 |     30% |26-29, 33-34, 38-47, 52-92, 102-127 |
| data\_safe\_haven/external/interface/azure\_fileshare.py                          |       64 |       47 |     27% |23-28, 32-36, 40-52, 56-68, 72-85, 89-92, 99-109 |
| data\_safe\_haven/external/interface/azure\_ipv4\_range.py                        |       34 |       23 |     32% |16-26, 30-31, 35, 39, 43-55 |
| data\_safe\_haven/external/interface/azure\_postgresql\_database.py               |      117 |       81 |     31% |45-57, 64-65, 69, 83-87, 93-97, 101-114, 120-127, 135-170, 174-235 |
| data\_safe\_haven/functions/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/functions/miscellaneous.py                                      |       16 |       11 |     31% |7-37, 45-58, 63-70 |
| data\_safe\_haven/functions/strings.py                                            |       44 |       23 |     48% |21, 26, 31, 39-48, 53, 68-70, 75, 85-93 |
| data\_safe\_haven/infrastructure/\_\_init\_\_.py                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/\_\_init\_\_.py                           |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/enums.py                                  |       51 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/common/ip\_ranges.py                             |       20 |       14 |     30% | 13-25, 33 |
| data\_safe\_haven/infrastructure/common/transformations.py                        |       50 |       36 |     28% |12-14, 19-22, 27-30, 35-38, 45, 56-71, 76-79, 84-87, 92-95, 100-103 |
| data\_safe\_haven/infrastructure/components/\_\_init\_\_.py                       |        4 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/\_\_init\_\_.py             |        6 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/composite/automation\_dsc\_node.py    |       28 |       17 |     39% |35-47, 62-108 |
| data\_safe\_haven/infrastructure/components/composite/local\_dns\_record.py       |       16 |       10 |     38% |16-20, 32-68 |
| data\_safe\_haven/infrastructure/components/composite/microsoft\_sql\_database.py |       24 |       16 |     33% |22-28, 41-109 |
| data\_safe\_haven/infrastructure/components/composite/postgresql\_database.py     |       24 |       16 |     33% |22-28, 41-122 |
| data\_safe\_haven/infrastructure/components/composite/virtual\_machine.py         |       77 |       55 |     29% |40-77, 81, 85, 96-116, 128-148, 161-288 |
| data\_safe\_haven/infrastructure/components/dynamic/\_\_init\_\_.py               |        8 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/dynamic/blob\_container\_acl.py       |       41 |       26 |     37% |29-50, 56-68, 76-87, 97-98, 110 |
| data\_safe\_haven/infrastructure/components/dynamic/compiled\_dsc.py              |       36 |       16 |     56% |27-33, 39-52, 60, 70-71, 88 |
| data\_safe\_haven/infrastructure/components/dynamic/dsh\_resource\_provider.py    |       35 |       20 |     43% |28-41, 50, 57-58, 63-65, 70-72, 81-83, 87-88, 97-99 |
| data\_safe\_haven/infrastructure/components/dynamic/entra\_application.py         |       77 |       55 |     29% |28-34, 40-65, 69-117, 125-131, 141-143, 152-162, 177 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_share\_file.py          |       72 |       48 |     33% |27-31, 37-40, 49-62, 71-80, 84-99, 107-122, 132-134, 147 |
| data\_safe\_haven/infrastructure/components/dynamic/file\_upload.py               |       48 |       30 |     38% |29-38, 44-77, 85-95, 110-118, 128-130, 143 |
| data\_safe\_haven/infrastructure/components/dynamic/remote\_script.py             |       32 |       17 |     47% |26-32, 38-47, 55, 65-73, 86 |
| data\_safe\_haven/infrastructure/components/dynamic/ssl\_certificate.py           |       91 |       66 |     27% |37-42, 48-62, 66-145, 153-171, 181-182, 195 |
| data\_safe\_haven/infrastructure/components/wrapped/\_\_init\_\_.py               |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/components/wrapped/automation\_account.py        |       20 |        7 |     65% |22-23, 39, 54, 63-71, 80 |
| data\_safe\_haven/infrastructure/components/wrapped/log\_analytics\_workspace.py  |       17 |        6 |     65% |22-23, 39, 46, 53-59 |
| data\_safe\_haven/infrastructure/programs/\_\_init\_\_.py                         |        3 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/declarative\_shm.py                     |       22 |        7 |     68% |     26-74 |
| data\_safe\_haven/infrastructure/programs/declarative\_sre.py                     |       50 |       32 |     36% |63-70, 74-383 |
| data\_safe\_haven/infrastructure/programs/shm/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/shm/firewall.py                         |       34 |       25 |     26% |28-32, 48-350 |
| data\_safe\_haven/infrastructure/programs/shm/monitoring.py                       |       45 |       35 |     22% |38-44, 58-450 |
| data\_safe\_haven/infrastructure/programs/shm/networking.py                       |       41 |       32 |     22% |23-32, 46-217 |
| data\_safe\_haven/infrastructure/programs/sre/\_\_init\_\_.py                     |        0 |        0 |    100% |           |
| data\_safe\_haven/infrastructure/programs/sre/application\_gateway.py             |       24 |       14 |     42% |31-44, 60-93 |
| data\_safe\_haven/infrastructure/programs/sre/apt\_proxy\_server.py               |       29 |       19 |     34% |34-44, 58-201 |
| data\_safe\_haven/infrastructure/programs/sre/backup.py                           |       18 |       11 |     39% |18-22, 38-173 |
| data\_safe\_haven/infrastructure/programs/sre/data.py                             |       84 |       69 |     18% |59-87, 90, 108-797 |
| data\_safe\_haven/infrastructure/programs/sre/database\_servers.py                |       26 |       18 |     31% |31-41, 55-107 |
| data\_safe\_haven/infrastructure/programs/sre/dns\_server.py                      |       38 |       26 |     32% |35-41, 55-305 |
| data\_safe\_haven/infrastructure/programs/sre/gitea\_server.py                    |       46 |       35 |     24% |46-66, 80-334 |
| data\_safe\_haven/infrastructure/programs/sre/hedgedoc\_server.py                 |       42 |       30 |     29% |48-68, 82-312 |
| data\_safe\_haven/infrastructure/programs/sre/identity.py                         |       32 |       23 |     28% |39-51, 67-253 |
| data\_safe\_haven/infrastructure/programs/sre/monitoring.py                       |       18 |       10 |     44% |23-28, 42-47 |
| data\_safe\_haven/infrastructure/programs/sre/networking.py                       |      113 |      104 |      8% |39-91, 105-1783 |
| data\_safe\_haven/infrastructure/programs/sre/remote\_desktop.py                  |       48 |       36 |     25% |56-95, 120-420 |
| data\_safe\_haven/infrastructure/programs/sre/software\_repositories.py           |       42 |       30 |     29% |41-56, 70-331 |
| data\_safe\_haven/infrastructure/programs/sre/user\_services.py                   |       47 |       34 |     28% |48-77, 93-204 |
| data\_safe\_haven/infrastructure/programs/sre/workspaces.py                       |       68 |       50 |     26% |53-86, 89-95, 109-207, 224-241 |
| data\_safe\_haven/infrastructure/project\_manager.py                              |      241 |      135 |     44% |37-38, 47-58, 101-106, 110, 160-162, 167, 171, 175-185, 189-195, 201, 205, 209-218, 222-281, 285-288, 292-297, 301-311, 315-317, 321-337, 341-347, 351-355, 364-370, 374-386, 408-410, 449-450 |
| data\_safe\_haven/provisioning/\_\_init\_\_.py                                    |        2 |        0 |    100% |           |
| data\_safe\_haven/provisioning/sre\_provisioning\_manager.py                      |       48 |       34 |     29% |29-57, 69-72, 76-77, 81-86, 90-126, 136-138 |
| data\_safe\_haven/resources/\_\_init\_\_.py                                       |        3 |        0 |    100% |           |
| data\_safe\_haven/serialisers/\_\_init\_\_.py                                     |        4 |        0 |    100% |           |
| data\_safe\_haven/serialisers/azure\_serialisable\_model.py                       |       22 |        0 |    100% |           |
| data\_safe\_haven/serialisers/context\_base.py                                    |       14 |        2 |     86% |    14, 19 |
| data\_safe\_haven/serialisers/yaml\_serialisable\_model.py                        |       40 |        0 |    100% |           |
| data\_safe\_haven/types/\_\_init\_\_.py                                           |        4 |        0 |    100% |           |
| data\_safe\_haven/types/annotated\_types.py                                       |       16 |        0 |    100% |           |
| data\_safe\_haven/types/enums.py                                                  |       10 |        0 |    100% |           |
| data\_safe\_haven/types/types.py                                                  |        2 |        0 |    100% |           |
| data\_safe\_haven/utility/\_\_init\_\_.py                                         |        5 |        0 |    100% |           |
| data\_safe\_haven/utility/directories.py                                          |        8 |        0 |    100% |           |
| data\_safe\_haven/utility/file\_reader.py                                         |       20 |        9 |     55% |16-17, 21, 25-30, 33 |
| data\_safe\_haven/utility/logger.py                                               |      108 |       60 |     44% |28-30, 35-37, 41-42, 87-88, 92-93, 117-120, 129-132, 136-137, 141-159, 167-180, 184-190, 194, 200-201, 215-223, 232-234 |
| data\_safe\_haven/utility/singleton.py                                            |        8 |        0 |    100% |           |
| data\_safe\_haven/validators/\_\_init\_\_.py                                      |        3 |        0 |    100% |           |
| data\_safe\_haven/validators/typer.py                                             |       19 |        0 |    100% |           |
| data\_safe\_haven/validators/validators.py                                        |       49 |        0 |    100% |           |
| data\_safe\_haven/version.py                                                      |        2 |        0 |    100% |           |
| tests/commands/conftest.py                                                        |       38 |        0 |    100% |           |
| tests/commands/test\_cli.py                                                       |       23 |        0 |    100% |           |
| tests/commands/test\_config.py                                                    |       44 |        0 |    100% |           |
| tests/commands/test\_context.py                                                   |      100 |        0 |    100% |           |
| tests/commands/test\_shm.py                                                       |       13 |        1 |     92% |        15 |
| tests/config/test\_config.py                                                      |      105 |        1 |     99% |       158 |
| tests/config/test\_pulumi.py                                                      |      116 |        0 |    100% |           |
| tests/conftest.py                                                                 |       86 |        2 |     98% |     54-55 |
| tests/context/test\_context\_settings.py                                          |      184 |        0 |    100% |           |
| tests/functions/test\_strings.py                                                  |        5 |        0 |    100% |           |
| tests/infrastructure/test\_project\_manager.py                                    |       85 |        0 |    100% |           |
| tests/serialisers/test\_azure\_serialisable\_model.py                             |       56 |        0 |    100% |           |
| tests/serialisers/test\_yaml\_serialisable\_model.py                              |       63 |        0 |    100% |           |
| tests/validators/test\_typer\_validators.py                                       |       13 |        0 |    100% |           |
| tests/validators/test\_validators.py                                              |       34 |        0 |    100% |           |
|                                                                         **TOTAL** | **5519** | **2766** | **50%** |           |


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