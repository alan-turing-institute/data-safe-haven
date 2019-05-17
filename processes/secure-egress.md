# Intro
The data that you loaded into the Turing Safe Haven may have been sensitive – commercially or legally required by law. Before reports and results can be extracted from the Safe Haven to be ready for publication, there needs to be a declassification process.

# Declassification
See [egress documentation](egress.md)

# Removing data without declassification
There may be situations that require data egress without going through the process of declassification.  Due to the sensitivity of the data we will only ever release this data to the original data owner that sent it to us in the first place, or if it is to comply with law.

In the first instance we will require written notification from the lead collaborator that they request an un-declassified copy of their data. By making this request the collaborator understands the [`something about the security implications`].

The Turing will encrypt the data with a strong encryption and strong key. You will need to provide us your IP address of the computer being used to activate the transfer.

## Azure
The easiest way to retrieve your data is to use the Azure Storage Explorer, [here](https://azure.microsoft.com/en-gb/features/storage-explorer/). We will put the encrypted data on a new storage account that you will only be able to access using a secret link.
We will then send you in an encrypted email the secret link to access the data along with the key to decrypt the data after transit. For additional security these 2 items can be delivered separately.

## SFTP
We will send you a encrypted email with the address of the FTP server and a key to access the secure area. We will then notify you that the data is ready to download. We will then send the key via a separate secure channel to unlock the data.

## Physically bring in a disk
Alternatively, you can bring us a physical device.
Please let us know when you will come to the Turing to deliver the data.
We will then send the key via a separate secure channel to unlock the data.
