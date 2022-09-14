# AWS Quick Start Guide

In AWS, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to an [S3 Bucket storage][1] container.
3. Create the virtual machine image.


## Requirements

You need the system requirements (also described [here](../../../README.md)) to create the following resources: 

### AWS prerequisites

* SSH keys uploaded (see [AWS documentation][14])
* [S3 Bucket][1] cloud storage container to store or stage your images (required if creating a public cloud image)
* Credentials/API keys:

  * IAM Policy (similar to this [example][16]) with import permissions (required if creating a public cloud image).
  * AWS [VM Import Service Role][2] named, **vmimport** (see, [Required service role][8] topic)

  ##### NOTE:
  ------------------------
  F5 recommends passing the credentials using ENV or CLI, rather than putting them in a configuration file. Consult [this article][12] for steps.

  ------------------------

### Virtual machine host prerequisites

* Working docker environment
* 100 GB of disk space
* [Hardware virtualization][6] for example, [i3.metal][11] instance type (optional)

### BIG-IP Image Generator Tool prerequisites

* BIG-IP ISO (with optional EHF ISO) from [F5 Downloads][9]
* Open Virtualization Format Tool from [VMware][22] (The ovftool is required for images on AWS and VMware; for example, *VMware-ovftool-4.4.3-18663434-lin.x86_64.bundle*.) 


## AWS parameter definitions

Use the following parameters in a config.yaml file or set as an environment variable.  Optionally, you can use these parameters at the command line with leading dashes (for example, `--aws-region`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|AWS_ACCESS_KEY_ID|Yes|[value]|Public key id string used for AWS account access.|
|AWS_BUCKET|Yes|[value]|AWS S3 bucket used during image generation.|
|AWS_IMAGE_SHARE_ACCOUNT_IDS|No|[value]|List of AWS account IDs with which you want the generated image shared.|
|AWS_REGION|Yes|[value]|Region to use for AWS image generation.|
|AWS_SECRET_ACCESS_KEY|Yes|[value]|Public key string used for AWS account access.|
|AWS_SESSION_TOKEN|No|[value]|Temporary session token used for AWS account access.|
   

## Create image for AWS using Docker container

The following procedure demonstrates using a private image with the [Docker][15] container method for AWS Cloud. This procedure does NOT assume the target image is using the same environment. 

1. Provision Ubuntu with [Docker][10] and [hardware virtualization][6], like [i3.metal][11] instance type on a root device with a minimum of 100 GB of disk space.

2. Create directories for build outputs:

   ```
   cd /home/ubuntu
   mkdir -p output_images output_artifacts logs
   ```
   
3. Upload the VMware ovftool bundle file and the ISO to the local directory: 

   ```
   /home/ubuntu/VMware-ovftool-4.4.3-18663434-lin.x86_64.bundle
   ```

4. Install the ovftool on the Host. The default install location is ``/usr/lib`` directory. You must copy the ovftool to your local directory:

   ```
   chmod +x VMware-ovftool-4.4.3-18663434-lin.x86_64.bundle 

   sudo ./VMware-ovftool-4.4.3-18663434-lin.x86_64.bundle --eulas-agreed 

   sudo cp -r /usr/lib/vmware-ovftool /home/ubuntu/vmware-ovftool 
   ```

5. Run/start the container and mount your local directory ``/home/ubuntu``  into the container’s ``/mnt`` directory:

   ```
   sudo docker run -it --device="/dev/kvm" -v "/home/ubuntu:/mnt" f5devcentral/f5-bigip-image-generator:latest  
   ```
   
   This will launch an interactive shell for the BIG-IP Image Generator Tool container: 
   
   ```
   /mnt # 
   ```
   
6. Install the Ovftool on the container using the container shell: 

   a. Copy the ovftool from your Ubuntu host over to the container’s filesystem: 
 
      ```
      cp -r /mnt/vmware-ovftool /usr/lib/vmware-ovftool/;  

      sudo chmod +x /usr/lib/vmware-ovftool/ovftool /usr/lib/vmware-ovftool/ovftool.bin; 

      PATH=$PATH:/usr/lib/vmware-ovftool/:/f5 
      ```

   b. Confirm the ovftool successfully copied/installed on the container:

      ```
      /mnt # which ovftool 

      /usr/lib/vmware-ovftool/ovftool 

      /mnt # ovftool --version 

      VMware ovftool 4.4.3 (build-18663434) 
      ```

7. Create/upload [config.yaml file][5] and store this config.yaml file in your host’s ``/home/ubuntu`` directory, which you must mount and make visible to the running container under ``/mnt`` or directly on the container file system.  For example:

   ```
   cat << EOF > config.yaml 

   ISO: "/mnt/BIGIP-15.1.4.1-0.0.15.iso" 

   MODULES: "all" 

   BOOT_LOCATIONS: "2"  

   REUSE: "Yes" 

   IMAGE_DIR: "/mnt/output_images/" 

   ARTIFACTS_DIR: "/mnt/output_artifacts/" 

   LOG_FILE: "/mnt/logs/" 

   PLATFORM: "aws" 

   AWS_REGION: "us-east-1" 

   AWS_BUCKET: "your-target-bucket"  

   AWS_ACCESS_KEY_ID="XXXXXXXXXX" # Replacing "XXXXX" with your values.

   AWS_SECRET_ACCESS_KEY="XXXXXXXXXXXXXXXXXX" # Replacing "XXXXX" with your values.

   EOF 
   ```
   Consult the main [ReadMe file here][5] for complete config file details.


8. Run the config file. The following example generates an  ALL (All Modules, 2 Slots) image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][4] article.

   ```
   build-image -c config.yaml

   ```
 
  An image is created from the ISO, uploaded to an existing s3 bucket, after which is converted into a snapshot, and registered with an AWS AMI ID. 

  **NOTE**: You can find all build images/artifacts/logs stored in the host directories ``/output_images /output_artifacts /logs``.

##### TIP:
------------------------
To prevent installing VMware ovftools repeatedly with every run, save changes to the container:  
  
1. Exit the container: `` /mnt # exit ``.
2. From the host, obtain ``Container_ID`` from the container you just ran: ``sudo docker ps -a``.
3. [Commit][13] the changes: ``sudo docker commit --change "ENV PATH=$PATH:/usr/lib/vmware-ovftool/:/f5" [CONTAINER_ID] f5-bigip-image-generator:with-ovftool``.
      
    For example:
    ```
    sudo docker commit --change "ENV PATH=$PATH:/usr/lib/vmware-ovftool/:/f5" e7b5b895d793 f5-bigip-image-generator:with-ovftool
    ```
4. The next time, you can run the container with ovftool pre-installed: ``sudo docker run -it --device="/dev/kvm" -v "/home/ubuntu:/mnt" f5-bigip-image-generator:with-ovftool``.

------------------------




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


[1]: https://docs.aws.amazon.com/quickstarts/latest/s3backup/step-1-create-bucket.html
[2]: https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html
[3]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#image-generator-prerequisites
[4]: https://support.f5.com/csp/article/K14946
[5]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#create-config-file
[6]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#virtualization-requirements
[7]: https://docs.aws.amazon.com/vm-import/latest/userguide/vmie_prereqs.html#iam-permissions-image
[8]: https://docs.aws.amazon.com/vm-import/latest/userguide/vmie_prereqs.html#vmimport-role
[9]: https://downloads.f5.com
[10]: https://docs.docker.com/engine/install/ubuntu/
[11]: https://aws.amazon.com/ec2/instance-types/i3/
[12]: https://clouddocs.f5.com/products/extensions/f5-cloud-failover/latest/userguide/aws.html#create-and-assign-an-iam-role
[13]: https://docs.docker.com/engine/reference/commandline/commit/
[14]:https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html
[15]: https://hub.docker.com/r/f5devcentral/f5-bigip-image-generator
[16]: https://cloudsolutions.pages.gitswarm.f5net.com/ve-public-cloud/shared/aws-ha-IAM.html
[22]: https://developer.vmware.com/tool/ovf


