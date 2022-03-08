# Alibaba Quick Start Guide

In Alibaba, the image generator tool will do the following:

1. Create a virtual disk image of BIG-IP 14.1.0.3+ locally.
2. Upload the virtual disk image to an Alibaba OSS bucket.
3. Create the virtual machine image.

For more information, consult the [Import custom images][2] topic.

## Requirements

You need the system requirements described [here](../../../README.md), as well as the following:

* Credentials/API Keys:
  
  * SSH Keys uploaded (see [Alibaba documentation][9]) 
  * Application credentials - [RAM (Resource Access Manager) role][4] with import permissions (specifically, ``AliyunECSImageImportDefaultRole`` and ``AliyunECSImageImportRolePolicy``)

    ##### NOTE
    ----------------------------------

    F5 recommends passing the credentials via `ENV` or `CLI`, rather than putting them in a configuration file. 

    ----------------------------------

* [OSS, Bucket storage container][1]


### Virtual machine host prerequisites

* Working Docker environment
* 100 GB of disk space
* [Hardware virtualization][3] (optional)

### BIG-IP Image Generator Tool prerequisites

* BIG-IP ISO (with optional EHF ISO) from [F5 Downloads][10]

## Parameter definitions

Use the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters on the command line with leading dashes (for example, `--ALIBABA-BUCKET`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|ALIBABA_ACCESS_KEY_ID|Yes|[value]|Public key id string used for Alibaba account access.|
|ALIBABA_ACCESS_KEY_SECRET|Yes|[value]|Private key string used for Alibaba account access.|
|ALIBABA_BUCKET|Yes|[value]|Alibaba OSS bucket used for image storage.|
|ALIBABA_REGION|Yes|[value]|Alibaba ECS region used for image generation.|
|ALIBABA_IMAGE_SHARE_ACCOUNT_IDS|No|[value]|List of Alibaba account IDs with which you want the generated image shared.|
|ALIBABA_UPLOAD_INTERNAL_OSS_ENDPOINT|No|[value]|Define if using an OSS internal endpoint within the Alibaba Cloud. Do NOT use this variable if building images outside Alibaba Cloud.|



## Create image for Alibaba using Docker container

The following procedure demonstrates using a private image with the [Docker][11] container method for Alibaba Cloud.This procedure does NOT assume the target image is using the same environment. 


1. Provision Ubuntu with [Docker][7] and [hardware virtualization][3] on a root device with a minimum of 100 GB of disk space.
2. Create some directories for build outputs: 

   ```
   cd /home/ubuntu
   mkdir -p output_images output_artifacts logs 
   ```
   
3. Provide [Application credentials][4] with import permissions:

   ```
   AliyunECSImageImportDefaultRole
   AliyunECSImageImportRolePolicy
   ```

4. Upload the BIG-IP ISO file (from [F5 Downloads][10]) and optional EHF ISO to the local directory. For example, 

   ```
   /home/ubuntu/BIGIP-15.1.5-0.0.10.iso 
   ```

5. Run/start the [storage container][1] and mount your local directory to ``/home/ubuntu``  into the container’s ``/mnt`` directory:

   ```
   sudo docker run -it --device="/dev/kvm" -v "/home/ubuntu:/mnt" f5devcentral/f5-bigip-image-generator:latest  
   ```
   
   This will launch an interactive shell for the BIG-IP Image Generator Tool container: 
   
   ```
   /mnt # 
   ```

6. Create/upload [config.yaml file][8] and store this config.yaml file in your host’s ``/home/ubuntu`` directory, which you must mount and make visible to the running container under ``/mnt`` or directly on the container file system.  For example:

   ```
   cat << EOF > config.yaml 

   ISO: "/mnt/BIGIP-15.1.4.1-0.0.15.iso" 

   MODULES: "all"  

   BOOT_LOCATIONS: "2"  

   REUSE: "Yes" 

   IMAGE_DIR: "/mnt/output_images/" 

   ARTIFACTS_DIR: "/mnt/output_artifacts/" 

   LOG_FILE: "/mnt/logs/" 

   PLATFORM: "alibaba" 

   ALIBABA_ACCESS_KEY_ID: "your-alibaba-access-public-key-string" 

   ALIBABA_ACCESS_KEY_SECRET: "your-alibaba-access-private-key-string" 
   
   ALIBABA_BUCKET: "your-target-bucket"
   
   ALIBABA_REGION: "your-target-region"

   EOF 
   ```
   
   Consult the main [ReadMe file here][8] for complete config file details.
 
7. Run the config file. The following example generates an (All Modules, 2 Slots) image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][5] article.

   ```
   build-image -c config.yaml

   ```
 
   An image is created from the ISO and uploaded to an existing [storage container][1].






#### Copyright

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


#### Contributor License Agreement

Individuals or business entities who contribute to this project must have
completed and submitted the F5 Contributor License Agreement.






[1]: https://www.alibabacloud.com/help/doc-detail/31885.htm
[2]: https://www.alibabacloud.com/help/en/doc-detail/25464.htm
[3]: https://www.alibabacloud.com/help/en/doc-detail/60576.htm
[4]: https://www.alibabacloud.com/help/doc-detail/25542.htm
[5]: https://support.f5.com/csp/article/K14946
[6]: https://www.alibabacloud.com/help/en/doc-detail/51793.htm?spm=a3c0i.23458820.2359477120.8.206b7d3fM2mGGs
[7]: https://docs.docker.com/engine/install/ubuntu/
[8]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#create-config-file
[9]: https://www.alibabacloud.com/help/en/doc-detail/51793.html
[10]: https://downloads.f5.com
[11]: https://hub.docker.com/r/f5devcentral/f5-bigip-image-generator




