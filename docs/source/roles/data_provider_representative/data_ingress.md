(role_dpr_ingress)=

# Data ingress process

The **Dataset Provider Representative** plays an important role in data ingress.
As well as being involved in agreeing an appropriate security tier for a project, they may also prepare the data to be uploaded.

## Bringing data into the environment

Talk to your {ref}`role_system_manager` to discuss possible methods of bringing data into the environments.
It may be convenient to use [Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer/).
In this case you will not need log-in credentials, as your {ref}`role_system_manager` can provide a short-lived secure access token which will let you upload data.

```{tip}
You may want to keep the following considerations in mind when transferring data in order to reduce the chance of a data breach.

- Use of short-lived access tokens limits the time within which an attacker can operate.
- Letting your {ref}`role_system_manager` know a fixed IP address you will be connecting from (_e.g._ a corporate VPN) limits the places an attacker can operate from.
- Communicating with your {ref}`role_system_manager` through a secure out-of-band channel (_e.g._ encrypted email) reduces the chances that an attacker can intercept or alter your messages in transit.

```

## Preparing input data for the Data Safe Haven

### Avoid archives

The input data is presented to researchers on a read-only filesystem.
This means that researchers will be unable to extract inputs in-place.
Instead, they would have to extract to a read-write space within the environment.
This could unnecessarily duplicate the data and leads to a greater risk of loss of integrity as the inputs can be modified (intentionally or accidentally).

### Avoiding name clashes

In the recommended upload process there is no protection for overwriting files.
It is therefore important to avoid uploading files with the same pathname as the later files will replace existing files.

To help avoid name clashes, if you are uploading multiple data sets you should use unique names for each data set.
For example, if the data sets are single files, use unique file names.
If data sets consist of multiple files, collect them in uniquely named directories.

If there are multiple data providers uploading data to a single SRE, each provider should use a uniquely named directory, or prepend their files with a unique name.

### Avoiding data leakage

If all data providers are uploading to the same storage container, then they may be able to see the files uploaded by other data providers.

Although they will not be able to access or download these files, a potential issue is that sensitive information may be visible in either the file names or directory structure of the uploaded data.

If possible, data providers should avoid the use of any identifying information in the filenames or directory structure of the data that they upload.
This is not always possible, since some data providers may require identifying information to be part of filenames or directory structures.

### Describe the data

Explaining the structure and format of the data will help researchers be most effective.
It is a good idea to upload a plain text file explaining the directory structure, file format, data columns, meaning of special terms, _etc._.
This file will be easy for researchers to read using tools inside the environment and they will be able to find it alongside the data.

### Data integrity

You will want to ensure that researchers have the correct data and that they can verify this.
We recommend using [checksums](https://www.redhat.com/sysadmin/hashing-checksums) to do this.

A checksum is a short string computed in a one-way process from some data.
A small change in the data (even a single bit) will result in a different checksum.
We can therefore use checksums to verify that data has not been changed.
In the safe haven this is useful for verifying that the data inside the environment is complete and correct.
It proves the data has not been modified or corrupted during transfer.

We recommended considering the hashing algorithms `md5sum` and `sha256`.
They are common algorithms built into many operating systems, and included in the Data Safe Haven.
`md5sum` is fast and sufficient for integrity checks.
`sha256` is slower but more secure, it better protects against malicious modification.

You can generate a checksum file, which can be used to verify the integrity of files.
If you upload this file then researchers will be able to independently verify data integrity within the environment.

Here are instructions to generate a checksum file using the `md5sum` algorithm for a data set stored in the `input` directory.

```console
find ./mnt/input/ -type fl -exec md5sum {} + > hashes.txt
```

`find` searches the `data` directory for files and symbolic links (`-type fl`).
`find` also runs the checksum command `md5sum` on all matching files (`-exec md5sum {} +`).
Finally, the checksums are written to a file called `hashes.txt` (`> hashes.txt`).

The data can be checked, by comparing to the checksums.

```console
md5sum -c hashes.txt
```

If a file has changed the command will return a non-zero exit code (an error).
The failing files will be listed as `<filename>: FAILED` in the output.
Those files can be easily identified using `grep`

```console
md5sum -c hashes.txt | grep FAILED
```

To use the `sha256` algorithm, replace `md5sum` with `sha256` in the above commands.
