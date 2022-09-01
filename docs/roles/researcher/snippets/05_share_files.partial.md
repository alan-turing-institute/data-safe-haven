## {{link}} Share files with collaborators

### {{open_file_folder}} Shared directories within the SRE

There are several shared areas on the SRD that all collaborators within a research project team can see and access:

- [input data](#input-data-data): `/data/`
- [shared space](#shared-space-shared): `/shared/`
- [scratch space](#scratch-space-scratch): `/scratch/`
- [backup space](#shared-space-backup): `/backup/`
- [output resources](#output-resources-output): `/output/`

#### Input data: `/data/`

Data that has been "ingressed" - approved and brought into the secure research environment - can be found in the `/data/` folder.

Everyone in your group will be able to access it, but it is **read-only**.

```{important}
You will not be able to change any of the files in `/data/` .
If you want to make derived datasets, for example cleaned and reformatted data, please add those to the `/shared/` or `/output/` directories.
```

The contents of `/data/` will be **identical** on all SRDs in your SRE.
For example, if your group requests a GPU-enabled machine, this will contain an identical `/data/` folder.

```{tip}
If you are participating in a Turing Data Study Group you will find example slides and document templates in the `/data/` drive.
```

#### Shared space: `/shared/`

The `/shared/` folder should be used for any work that you want to share with your group.
Everyone in your group will be able to access it, and will have **read-and-write access**.

The contents of `/shared/` will be **identical** on all SRDs in your SRE.

#### Scratch space: `/scratch/`

The `/scratch/` folder should be used for any work-in-progress that isn't ready to share yet.
Although everyone in your group will have **read-and-write access**, you can create your own folders inside `/scratch` and choose your own permissions for them.

The contents of `/scratch/` will be **different** on different VMs in your SRE.

#### Backup space: `/backup/`

The `/backup/` folder should be used for any work-in-progress that you want to have backed up.
In the event of any accidental data loss, your system administrator can restore the `/backup` folder to the state it was in at an earlier time.
This **cannot** be used to recover individual files - only the complete contents of the folder.
Everyone in your group will have **read-and-write access** to all folders on `/backup`.

The contents of `/backup/` will be **identical** on all SRDs in your SRE.

#### Output resources: `/output/`

Any outputs that you want to extract from the secure environment should be placed in the `/output/` folder on the SRD.
Everyone in your group will be able to access it, and will have **read-and-write access**.
Anything placed in here will be considered for data egress - removal from the secure research environment - by the project's principal investigator together with the data provider.

```{tip}
You may want to consider having subfolders of `/output/` to make the review of this directory easier.
```

```{hint}
For the Turing Data Study Groups, we recommend the following categories:
- Presentation
- Transformed data/derived data
- Report
- Code
- Images
```

### {{newspaper}} Bring in new files to the SRE

Bringing software into a secure research environment may constitute a security risk.
Bringing new data into the SRE may mean that the environment needs to be updated to a more secure tier.

The review of the "ingress" of new code or data will be coordinated by the designated contact for your SRE.
They will have to discuss whether this is an acceptable risk to the data security with the project's principle investigator and data provider and the decision might be "no".

```{hint}
You can make the process as easy as possible by providing as much information as possible about the code or data you'd like to bring into the environment and about how it is to be used.
```
