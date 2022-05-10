# Azure Quick Start Guide

In Azure, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to a [storage container][1].
3. Create the virtual machine image, convert that image to an Azure image, and place it within the same Azure resource group where the existing storage container resides.

## Requirements

You need the system requirements described [here](../../../README.md), as well as the following:


### Azure prerequisites   

* Credentials/API keys
  * SSH keys uploaded (see [Azure documentation][12])
  * [A service principle with contributor role permissions][2]

  ##### NOTE
  ----------------------------------

  F5 recommends passing the credentials via `ENV` or `CLI`, rather than putting them in a configuration file. Consult [this article][7] for steps.

  ----------------------------------
  
* [Storage Container][1] and [storage connection strings][3]

### Virtual machine host prerequisites

* Working Docker environment
* 100 GB of disk space
* [Hardware virtualization][8] for example, [Dv3 or Ev3][9] virtual machine type (optional)

### BIG-IP Image Generator Tool prerequisites

* BIG-IP ISO (with optional EHF ISO) from [F5 Downloads][11]


### Create an application

When creating a BIG-IP image in Azure, you MUST also [create an application][4]. Consult the following tips:

* When registering the application, you do NOT need to specify **Redirect assignment**.
* When adding a **Role assignment**, select **Contributor**. Doing so assigns access to the newly created **Service Principle** (having the same name as the application).  
* To authenticate the application, create a **Client Secret**.

## Parameter definitions

Use the following parameters in a config.yaml file or set as an environment variable.  Optionally, you can use these parameters on the command line with leading dashes (for example, `--azure_storage_container_name`).

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


## Create image for Azure using Docker container

The following procedure demonstrates using a private image with the [Docker][13] container method for Azure Cloud. This procedure does NOT assume the target image is using the same environment. 

1. Provision Ubuntu with [Docker][10] and [hardware virtualization][8], like [Dv3 or Ev3][9] virtual machine type on a root device with a minimum of 100 GB of disk space.

2. Create directories for build outputs:

   ```
   cd /home/ubuntu
   mkdir -p output_images output_artifacts logs
   ```
   
3. Upload the BIG-IP ISO file and optional EHF ISO to the local directory. For example, 

   ```
   /home/ubuntu/BIGIP-15.1.5-0.0.10.iso 
   ```

4. Run/start the container and mount your local directory ``/home/ubuntu``  into the container’s ``/mnt`` directory:

   ```
   sudo docker run -it --device="/dev/kvm" -v "/home/ubuntu:/mnt" f5devcentral/f5-bigip-image-generator:latest  
   ```
   
   This will launch an interactive shell for the BIG-IP Image Generator Tool container: 
   
   ```
   /mnt # 
   ```
   
5. Create/upload [config.yaml file][6] and store this config.yaml file in your host’s ``/home/ubuntu`` directory, which you must mount and make visible to the running container under ``/mnt`` or directly on the container file system.  For example:

   ```
   cat << EOF > config.yaml 

   ISO: "/mnt/BIGIP-15.1.4.1-0.0.15.iso" 

   MODULES: "all"  

   BOOT_LOCATIONS: "2"  

   REUSE: "Yes" 

   IMAGE_DIR: "/mnt/output_images/" 

   ARTIFACTS_DIR: "/mnt/output_artifacts/" 

   LOG_FILE: "/mnt/logs/" 

   PLATFORM: "azure" 

   AZURE_REGION: "Australia East" 

   AZURE_RESOURCE_GROUP: "XXXXX" # Replacing "XXXXX" with your values.

   AZURE_STORAGE_CONTAINER_NAME: "your-target-container" 

   AZURE_STORAGE_CONNECTION_STRING: "DefaultEndpointsProtocol=https;AccountName=XXXXX;AccountKey=KEdIPX/XXX XXXXX==;EndpointSuffix=core.windows.net" # Replacing "XXXXX" with your values.

   AZURE_SUBSCRIPTION_ID: "XXXXX" # Replacing "XXXXX" with your values.

   AZURE_TENANT_ID: "XXXXX" # Replacing "XXXXX" with your values.

   AZURE_APPLICATION_ID: "XXXXX" # Replacing "XXXXX" with your values.

   AZURE_APPLICATION_SECRET: "XXXXX" # Replacing "XXXXX" with your values.

   EOF 
   ```
   Consult the main [ReadMe file here][6] for complete config file details.


6. Run the config file. The following example generates an ALL (All Modules, 2 Slots) image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][5] article.

   ```
   build-image -c config.yaml

   ```
 
   An image is created from the ISO and uploaded to an existing [storage container][1].

### Copyright

Copyright (C) 2019-2022 F5 Inc.

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
[6]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#create-config-file
[7]: https://clouddocs.f5.com/products/extensions/f5-cloud-failover/latest/userguide/azure.html#create-and-assign-a-managed-service-identity-msi
[8]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#virtualization-requirements
[9]: https://azure.microsoft.com/en-us/blog/nested-virtualization-in-azure/
[10]: https://docs.docker.com/engine/install/ubuntu/
[11]: https://downloads.f5.com
[12]: https://docs.microsoft.com/en-us/azure/virtual-machines/linux/create-ssh-keys-detailed
[13]: https://hub.docker.com/r/f5devcentral/f5-bigip-image-generator


