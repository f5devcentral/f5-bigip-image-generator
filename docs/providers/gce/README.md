# GCE Quick Start Guide

In GCE, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to a GCE bucket.
3. Create the virtual machine image.


## Requirements

You need the system requirements described [here](../../../README.md), as well as the following:


### GCE prerequisites   

* Credentials/API Keys

  * SSH Keys uploaded (see [Google Cloud documentation][12])
  * [Application credentials][9] with *Compute Engine Instance Admin (v1)* and *Service Account User* roles

    ##### NOTE
  ----------------------------------

  F5 recommends passing the credentials via `ENV` or `CLI`, rather than putting them in a configuration file. Consult [this article][7] for steps.

  ----------------------------------

* [GCE Bucket storage container][1]

See this [GCE article][9] for more service account information.

### Virtual machine host prerequisites

* Working Docker environment
* 100 GB of disk space
* Hardware virtualization for example, [enabling nested virtualization][5] (optional)

### BIG-IP Image Generator Tool prerequisites

* BIG-IP ISO (with optional EHF ISO) from [F5 Downloads][6]



##  Parameter definitions


Use the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters on the command line with leading dashes (for example, `--gce-bucket`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|GCE_BUCKET|Yes|[value]|GCE disk storage bucket used during image generation.|
|GOOGLE_APPLICATION_CREDENTIALS|Yes|[value]|Service account auth credentials as a JSON string or a file path ending in .json.  For help with generating these credentials, refer to bit.ly/2MYQpHN. .|


## Create image for GCE using Docker container

The following procedure demonstrates using a private image with the [Docker][11] container method for Google Cloud. This procedure does NOT assume the target image is using the same environment.


1. Provision Ubuntu with [Docker][10] and hardware virtualization, like [Enabling nested virtualization][5] on a root device with a minimum of 100 GB of disk space.
2. Create some directories for build outputs: 

   ```
   cd /home/ubuntu
   mkdir -p output_images output_artifacts logs 
   ```
   
3. Provide [Application credentials][9] with *Compute Engine Instance Admin (v1)* and *Service Account User* roles.
4. Upload the BIG-IP ISO file (from [F5 Downloads][6]) and optional EHF ISO to the local directory. For example, 

   ```
   /home/ubuntu/BIGIP-15.1.5-0.0.10.iso 
   ```

5. Run/start the [storage container][1] and mount your local directory ``/home/ubuntu``  into the container’s ``/mnt`` directory:

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

   PLATFORM: "gce" 

   GCE_BUCKET: "your-target-bucket" 

   GOOGLE_APPLICATION_CREDENTIALS: "/mnt/application_default_credentials.json" 

   EOF 
   ```
   Consult the main [ReadMe file here][8] for complete config file details.
 
7. Run the config file. The following example generates an ALL (All Modules, 2 Slots) image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][4] article.

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



[1]: https://cloud.google.com/storage/docs/creating-buckets

[3]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#image-generator-prerequisites
[4]: https://support.f5.com/csp/article/K14946
[5]: https://cloud.google.com/compute/docs/instances/nested-virtualization/enabling
[6]: https://downloads.f5.com
[7]: https://clouddocs.f5.com/products/extensions/f5-cloud-failover/latest/userguide/gcp.html#create-and-assign-an-iam-role
[8]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#create-config-file
[9]: https://cloud.google.com/iam/docs/creating-managing-service-accounts
[10]: https://docs.docker.com/engine/install/ubuntu/
[11]: https://hub.docker.com/r/f5devcentral/f5-bigip-image-generator
[12]: https://cloud.google.com/compute/docs/connect/create-ssh-keys



