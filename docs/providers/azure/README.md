## Azure

In Azure, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to a [storage container][1].
3. Create the virtual machine image.

### Prerequisites

You need the system requirements described [here](../../../README.md), as well as [sufficient permissions][2] to create or describe the following resources:

* Credentials/API keys
* SSH keys uploaded
* [Storage Container][1] and [storage connection strings][3]

##### Create an application

When creating a BIG-IP image in Azure, you MUST also [create an application][4]. Consult the following tips:

* When registering the application, you do NOT need to specify **Redirect assignment**.
* When adding a **Role assignment**, select **Contributor**. Doing so assigns access to the newly created **Service Principle** (having the same name as the application).  
* To authenticate the application, create a **Client Secret**.

###  User guide

Define the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters on the command line with leading dashes (for example, `--azure_storage_container_name`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|AZURE_APPLICATION_ID|Yes|[value]|Application (client role) ID to access Azure tenant.|
|AZURE_APPLICATION_SECRET|Yes|[value]|Application (client role) secret to access Azure tenant.|
|AZURE_REGION|Yes|[value]|Region to use for Azure image generation.|
|AZURE_RESOURCE_GROUP|Yes|[value]|Azure resource group containing the images.|
|AZURE_STORAGE_CONNECTION_STRING|Yes|[value]|Azure storage connection string used for account access.|
|AZURE_STORAGE_CONTAINER_NAME|Yes|[value]|Name of Azure storage container to use for generated images.|
|AZURE_SUBSCRIPTION_ID|Yes|[value]|ID of subscription to Azure account.|
|AZURE_TENANT_ID|Yes|[value]|ID of Azure Active Directory (Azure AD) tenant.|

##### NOTE
-----------

F5 recommends passing the credentials via `ENV` or `CLI`, rather than putting them in a configuration file.

-----------------

#### Example

The following example generates an  LTM_1SLOT image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][5] article.

```
./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p azure -m ltm -b 1

```

### Copyright

Copyright (C) 2019-2021 F5 Networks, Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at  

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)  

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations under
the License.


### Contributor License Agreement

Individuals or business entities who contribute to this project must have
completed and submitted the F5 Contributor License Agreement.




[1]: https://docs.microsoft.com/en-us/rest/api/storageservices/create-container
[2]: https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
[3]: https://docs.microsoft.com/en-us/azure/storage/common/storage-configure-connection-string
[4]: https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
[5]: https://support.f5.com/csp/article/K14946


