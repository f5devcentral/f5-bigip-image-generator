## Azure

In Azure, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to a [storage container][1].

### Prerequisites

You need the system requirements described [here](../../../README.md), as well as [sufficient permissions][2] to create or describe the following resources:

* Credentials/API keys
* SSH keys uploaded
* [Storage Container][1] and [storage connection strings][4]

See this [Azure article][2] for more service account information.


###  User guide

Define the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters on the command line with leading dashes (for example, `--azure_storage_container_name`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|AZURE_IMAGE_MAX_RETRY|No|[[0-9]+]|The number of times to retry image related operations when running Azure commands.|
|AZURE_STORAGE_CONNECTION_STRING|Yes|[value]|Azure storage connection string used for account access.|
|AZURE_STORAGE_CONTAINER_NAME|Yes|[value]|Name of Azure storage container to use for generated images.|

##### NOTE
-----------

F5 recommends passing the credentials via `ENV` or `CLI`, rather than putting them in a configuration file.

-----------------

#### Example

```
./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p azure -m ltm -b 1

```
[1]: https://docs.microsoft.com/en-us/rest/api/storageservices/create-container
[2]: https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
[3]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#image-generator-prerequisites
[4]: https://docs.microsoft.com/en-us/azure/storage/common/storage-configure-connection-string



