# Welcome to the F5 BIG-IP Image Generator Tool

You will find the following information:

* [Introduction](#introduction)
* [Prerequisites](#prerequisites)
  * [Image Generator prerequisites](#image-generator-prerequisites)
  * [Supported platforms and prerequisites](#supported-platforms-and-prerequisites)
  * [Environment recommendations](#environment-recommendations)
* [Setup guide](#setup-guide)
  * [Docker container setup](#docker-container-setup) 
* [User guide](#user-guide)
  * [Create config file](#create-config-file)
  * [Monitor progress](#monitor-progress)
  * [Locate files](#locate-files)
* [Troubleshooting guide](#troubleshooting-guide)
* [Support guide](#support-guide)
  * [Known issues](#known-issues)

## Introduction

The F5 Virtual Edition (VE) team developed the F5 BIG-IP Image Generator internally to do the following:

* Create custom images from the .ISO file for F5 BIG-IP VE releases or for hot-fixes that are not available on the various public cloud marketplaces.
* Provide pre-deployment file customization of BIG-IP (for example, SSH keys, trusted certificates, custom packages, and so forth).
* Automatically publish images to public cloud providers.
* Simplify deployment workflows, such as encrypting custom images in AWS (prevents launching an instance in the marketplace first).

##### SECURITY WARNING
----------------------
It is your responsibility to:

1.	Secure and restrict access to the environment on which you run the VE Image Generator tool, and in your cloud environment. 
2.	Remove any sensitive data on the created image PRIOR to automatically publishing the image to the cloud.

------------------------------

## Prerequisites
This section provides prerequisites for running the F5 Image Generator, creating virtual images, and for supported cloud providers.

#### Image Generator prerequisites
The following table lists system requirements for using the Image Generator to create  virtualized images of the following supported BIG-IP ISO packages:

| Component                 | Version                                                         | Recommended System Requirements|                                                      
|---------------------------| :---------------------------------------------------------------| :------------------------------|
| F5 BIG-IP Image Generator | 1.0                                                             | - **Memory**: 1GB memory <br> - **Disk space**: depends on number of images you want to create.<br> See following BIG-IP VE system requirements.|                                                             
| [F5 BIG-IP VE][1]         | - BIG-IP 13.1.0.2+ (except Alibaba) <br>- BIG-IP 14.X<br> - BIG-IP 14.1.0.3+ (for Alibaba ONLY)<br> - BIG-IP 15.X          | A minimum of 20GB per image    |    
| Ubuntu (F5 Image Generator-validated)                    | 18.04 LTS operating system       | Tools: <br>- Git<br> - Python 3.x<br> - Cloud provider SDK tools <br> See [setup script][2].|
| Open Virtualization Format Tool (ovftool) | 4.3.0 | If you deploy in VMware (ESX/i Server) or AWS cloud, you must install the [ovftool][22] for creating the virtual disk. |
	 

#### Supported platforms and prerequisites
The following table lists supported public and private cloud platforms as well as account setup requirements:

| Cloud Provider            | Requirements                                                                                                        
|---------------------------| :---------------------------------------------------------------|
|Alibaba                    |  BIG-IP 14.1.0.3+ and sufficient permissions to create or describe the following resources:<br> - Credentials/API Keys<br> - SSH Keys uploaded<br> - Application credentials<br> - [OSS, Bucket storage container][29] <br>(See this [Alibaba article][30] for more Resource Access Manager (RAM) information.)|
| AWS                       | Sufficient permissions to create or describe the following resources:<br> - credentials/API Keys<br> - [S3 Bucket Storage Container][12]<br> - Install the [ovftool][22] for creating the virtual disk.<br> - IAM Role with import permissions <br>(See this [AWS article][3] for more VM Import Service Role information.) |
| Azure                     | Sufficient permissions to create or describe the following resources:<br> - Credentials/API Keys<br> - [Storage Container][11] and [storage connection strings][28]<br> (For more information, see this articles about [creating a service principle][10].)|
| Google Cloud (GCE)        | Sufficient permissions to create or describe the following resources:<br> - Credentials/API Keys<br> - Application  credentials<br> - [Storage Container][13] <br>(See this [GCE article][9] for more service account information.)|

The following supported platforms require no specific configuration:

* **QCOW2** (KVM Red Hat Enterprise Linux/CentOS; OpenStack) - See [VE Setup for KVM][18] for more information.
* **VHD** (Microsoft Hyper-V) - See [VE Setup for Hyper-V][17] for more information.
* **VMware** (ESX/i Server) - See [VE Setup for vSphere][14] for more information. For advanced setup, see [creating ISO using TMOS-cloud-init][15] and [configuring user data][16]. 


##### Virtualization requirements
The Image Generator tool generates a virtual disk image from the BIG-IP product ISO. During the creation, you can specify a cloud provider. Doing so generates a virtual disk image, automatically uploads that disk to that cloud provider, and creates a virtual machine image. Options include:

* **Enabling virtualization** creates a virtual disk in **10-15 minutes** (RECOMMENDED). 
* Disabling virtualization creates a virtual disk in 1-2 hours. 

##### Tip
----------
F5 recommends running the Image Generator Tool in environments where virtualization is enabled (for example, **AWS i3.metal** instance or [GCE's KVM licensing flag for instances][25]). 

Execution times differ between cloud providers, usually taking 5-20 minutes depending on the image size. The BIG-IP Image Generator will display a **warning**, if you run the script in an **insufficient** environment **without virtualization** support.

For more information about virtualization support, see [KVM Virtualization][4].

-------------------------------------------------------------------------------

### Environment recommendations
Due to several required tools/SDKs to generate images, F5 Networks recommends using a standalone machine/environment for the BIG-IP Image Generator. F5 provides a [setup script][2] to assist in setting up that environment. The script installs Python packages in a virtual environment to isolate them from the rest of the system; however, the script also installs other tools, such as zip, directly into the base environment. These packages are not downloaded from F5 repositories, but come from the respective project repositories. It is your responsibility to verify that these packages are safe to use. 


## Setup guide

This section provides steps for installing the generator tool, and then using the setup script. The setup script installs tools/SDKs required to generate images for all supported platforms, and takes several minutes to complete. During this setup process, certain services will require a restart.

1. Do one of the following to install the BIG-IP Image Generator source code.

   * Clone
     
     `$ git init` <br/>
     `$ git clone https://github.com/f5devcentral/f5-bigip-image-generator.git` <br/>
     `or` <br/>
     `$ git clone git@github.com:f5devcentral/f5-bigip-image-generator.git` <br/>
     `$ cd f5-bigip-image-generator` <br/>
     `$ git checkout v1.0` (checkout the tag associated with the release version you want to install)
     
   * Download
   
     1. Point your browser to https://github.com/f5devcentral/f5-bigip-image-generator, open the branch with the tag associated with the release you want to install, click **Download**, and then select the file type (zip, tar.gz, tar.bz2, or tar) you want to install.
     2. At your command line, type the following (this example is uses tar.gz file type):
    
        `$ scp -i ~/.ssh/my_key Downloads/f5-bigip-image-generator-1.0.tar.gz ubuntu@image-generator-ip:/home/ubuntu/` <br/>
        `$ ssh -i ~/.ssh/my_key ubuntu@image-generator-ip` <br/>
        `ubuntu@image-generator-ip:~$ tar -xzvf f5-bigip-image-generator-1.0.tar.gz` <br/>
        `ubuntu@image-generator-ip:~$ cd f5-bigip-image-generator-1.0`  

2. To run the [setup script][2], type:  

   `./setup-build-env`
   
   Options include:
   
   * `--add-dev-tools` - installs additional tools for development, such as pylint, shellcheck, and bats

3. Restart your computer, or log out, and then log back into your system.

### Docker container setup
To avoid installing programs to your environment and enable running simultaneous image-builds on the same computer, you can set up a Docker container and build BIG-IP images using that container.

1. To build the Docker image, change directories to the ``docker`` directory and type, ``./build-docker-image``.
2. To pass in variables to the container, add a ``config.yml`` file to that ``docker`` directory, which you want mounted when running the container. Avoid keeping credentials in this config.yml file. Instead, consider passing in credentials as environment variables, similar to other docker containers, with the ``-e`` flag.
3. After your container is built, run that container to build an image by running the ``build-image`` script as you would normally at the end of your docker run command (passing parameters is the same, as if not using a container). For example:

   ### qcow2 

   ```
      docker run -it --device="/dev/kvm" -v "$(pwd):/mnt" -v "$(pwd)/../images:/workdir/images" ubuntu:ve_image_generator /bin/bash -c "/workdir/build-image -c /mnt/config.yml -i /mnt/BIGIP-15.0.1-0.0.11.iso -p qcow2 -m ltm -b 1;"
   ```
       
   ##### NOTE
   ---------------------------------------------------
   This example mounts the current directory as a volume, so that you can pass in the config file, read the source iso, output the images, and so forth (rather than the container's filesystem).
   
   ---------------------------------------------------
   
   ### OVA or AWS
  
   If building an ova or aws image, then you need [ovftool][22]. Download and add the ovftool.bundle, which is renamed``ovftool.bundle``,  file into the ``docker`` folder. To make the file executable, type: 

   ```
    chmod +x ovftool.bundle
   ```

   and then run:
  
   ```
      docker run --device="/dev/kvm" -it -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" -v "$(pwd):/mnt" -v "$(pwd)/../images:/workdir/images" ubuntu:ve_image_generator /bin/bash -c "/mnt/ovftool.bundle;  /workdir/build-image -c /mnt/config.yml -i /mnt/BIGIP-15.0.1-0.0.11.iso -p aws -m ltm -b 1;"
   ```   
   
   ##### TIP
   ---------------------------------------------------
   Once you read and accept the ovftool EULA, to auto-accept the EULA you can append this: ``--eulas-agreed --required --delete-install-components`` as a parameter to running the ``ovftool.bundle`` install.
   
   ---------------------------------------------------
   
   ### Without KVM hardware acceleration


   Remove ``–device=”/dev/kvm”`` parameter, which indicates that Docker does not have access to that device. For example:

   ```
      docker run -it -v "$(pwd):/mnt" -v "$(pwd)/../images:/workdir/images" ubuntu:ve_image_generator /bin/bash -c "/workdir/build-image -c /mnt/config.yml -i /mnt/BIGIP-15.0.1-0.0.11.iso -p qcow2 -m ltm -b 1;"
   ```
   
   For more information about virtualization support, see [KVM Virtualization][4]. 

## User guide

This section provides steps for creating a [config.yml][5] file that defines frequently used settings and shared variables that the BIG-IP Image Generator will use for creating custom images, running the Image Generator tool, and then customizing log details for monitoring progress. 

### Create config file

1. Create a [config.yml][5] for frequently used settings and shared variables. The BIG-IP Image Generator will only use the variable definitions applicable to the specified provider and ignores other variables.

2. Define the following shared parameters or set as an environment variable. Optionally, use these parameters on the command line with leading dashes (for example, `--platform`). In some cases, you can use a shorthand flag. If a parameter is defined in multiple places, then the priority in descending order is:
command line >  configuration file >  environment variable. To access the Image Generator help file, run `-h/--help`.

    |Parameter|Flag|Required|Values|Description|
    |:--------|:---|:-------|:-----|:----------|
    |BOOT_LOCATIONS|-b|Yes|[1 \| 2]|Number of boot locations used in the source ISO file.|
    |CLOUD_IMAGE_NAME| |No|[value]|The name of the generated cloud image.  The name is subject to cloud provider naming restrictions  and is not guaranteed to succeed.  If you provide no name, then one is generated automatically  based on the detected properties of the source ISO file.|
    |CONFIG_FILE|-c|No|[value]|Full path to a YAML configuration file containing a list of parameter key/value pairs used during image generation.|
    |EHF_ISO|-e|No|[value]|Full path to an engineering hotfix ISO file for installation on top of the existing ISO file.|
    |EHF_ISO_SIG|-x|No|[value]|Full path to an engineering hotfix ISO signature file used to validate the engineering hotfix ISO.|
    |HELP|-h|No| |Print help and usage information, and then exit the program.|
    |IMAGE_DIR| |No|[value]|The directory where you want generated images to reside. Provide either an absolute path or a relative path. If this directory does not exist, the tool will create it.|
    |IMAGE_SIG_ENCRYPTION_TYPE| |No|[value]|Encryption type to use when signing images.|
    |IMAGE_SIG_PRIVATE_KEY| |No|[value]|Path to private key file used to sign images.|
    |IMAGE_SIG_PUBLIC_KEY| |No|[value]|Path to public key file used to verify images.|
    |IMAGE_TAGS| |No|[value]|List of key value pairs to set as tags/labels for the image.|
    |ISO|-i|Yes|[value]|Full path to a BIG-IP ISO file used as a basis for image generation.|
    |ISO_SIG|-s|No|[value]|Full path to an ISO signature file used to validate the ISO.|
    |ISO_SIG_VERIFICATION_ENCRYPTION_TYPE| |No|[value]|Encryption type to use when signing/verifying ISO or Virtual disks|
    |ISO_SIG_VERIFICATION_PUBLIC_KEY| |No|[value]|Path to public key file used to verify an ISO.|
    |LOG_FILE| |No|[value]|Log filename that overrides the default log filename created in the logs directory. You can use a full path, directory, or filename. If full path, then the log file uses the full path. If directory, then the image generator creates a new log file in the specified directory. If filename, then the tool creates a log file in the logs directory using the specified filename.|
    |LOG_LEVEL| |No|[CRITICAL \| ERROR \| WARNING \| INFO \| DEBUG \| TRACE]|Log level to use for the log file, indicating the lowest message severity level that can appear in the log file.|
    |MODULES|-m|Yes|[all \| ltm]|BIG-IP components supported by the specified image.|
    |PLATFORM|-p|Yes|[alibaba \| aws \| azure \| gce \| qcow2 \| vhd \| vmware]|The target platform for generated images.|
    |REUSE| |No| |Keep local files created by previous runs of the same <PLATFORM, MODULES, BOOT_LOCATIONS> combination.|    
    |UPDATE_IMAGE_FILES| |No|[value]|Files you want injected into the image. For each of the injections, required values include source (file or directory) and destination (absolute full path).|
    |UPDATE_IMAGE_FILES_IGNORE_URL_TLS| |No| |Ignore TSL certificate verification when downloading files to be injected into the image.|
    |VERSION|-v|No| |Print version information, and then exit the program.|

3. When specifying a cloud provider, supply the following provider-specific information:

   * [Alibaba][26]
   * [AWS][6]
   * [Azure][7] - When creating BIG-IP images in Azure, you must also [create an application][31]. Consult the [Azure ReadMe][7] file for more information.
   
   * [GCE ][8]  
    
   The following platforms do not currently require platform-specific configuration:
   
   * QCOW2 (KVM Red Hat Enterprise Linux/CentOS; OpenStack)
   * VHD (Microsoft Hyper-V)
   * VMware (ESX/i Server)

4. OPTIONAL: The Image Generator tool can inject additional files (for example, keys, certs, and custom lx packages) into the virtual disk image to allow for image customization. You can do this using the command line; however, the syntax is simpler using the configuration file:

   ```
      UPDATE_IMAGE_FILES:   
      -  source: "/home/ubuntu/custom/authorized_keys"
         destination: "/home/admin/.ssh/authorized_keys"
      -  source: "/home/ubuntu/custom/trusted-ca.pem"
         destination: "/config/ssl/ssl.crt/trusted-ca.pem"
      -  source: "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.8.0/f5-declarative-onboarding-1.8.0-2.noarch.rpm"
         destination: "/config/f5-declarative-onboarding-1.8.0-2.noarch.rpm"
      -  source: "https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.15.0/f5-appsvcs-3.15.0-6.noarch.rpm"
         destination: "/config/f5-appsvcs-3.15.0-6.noarch.rpm"
      -  source: "https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.7.0/f5-telemetry-1.7.0-1.noarch.rpm"
         destination: "/config/f5-telemetry-1.7.0-1.noarch.rpm"   
   ```
       

   ##### IMPORTANT
   -----------------------
   Avoid overwriting existing system related files unless directed by F5 networks. Place these additional files in typical locations where you store customizations. For example, place files in the `/config` directory where they can be included in the user configuration set (UCS) file or in the `/shared` directory, so each slot can access the customizations. Otherwise, you will lose these changes during an upgrade. For more information about UCS, see the  *file inclusion into UCS archives* topic on [AskF5][24].  

   --------------------------------

5. OPTIONAL: The default behavior of the Image Generator does not attempt to use previously created local artifacts. To enable this feature, use the `--reuse` option. If you receive an error during file-upload to a cloud provider, then only the cloud portion of image generation will rerun for a subsequent image generation. Be aware that if you have already generated the virtual disk during previous runs, then using this option will prevent you from applying the '--update_image_files' option.

   **Example:**
   
   1. Build an image, type: `./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p qcow2 -m ltm -b 1--image-tag "Name: my-custom-vm-v12.1.1" --image-tag "org: shared-services`
   2. Reuse the environment associated with the specified source image, platform, modules, and boot locations, type: `./build-image --reuse -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p qcow2 -m ltm -b 1--image-tag "Name: my-custom-vm-v12.1.1" --image-tag "org: shared-services`.

6.	OPTIONAL: You can assign image tags to published images; however, rules for image tag definitions change depending upon the target, cloud provider ([Alibaba][26], [AWS][21], [Azure][19], and [GCE ][20]). 
    Currently, the Image Generator tool does not validate for each cloud provider's image tag:key and image tag:value pairing. Therefore, if you do NOT 
    properly define your image tag:key/value pair for the target cloud platform, then your image is created, but your image will not have the tags that 
    you defined. To define image tags, consult one of the following examples:
    
    Configuration file (recommended):

    ```
      IMAGE_TAGS:
      - name: "my-custom-ami-v15.0.0"
      - org: "shared-services"
      - project: "alpha"
    ```
    
    Command line:

    ```
     --image-tags ‘{"name":"my-custom-ami-v15.0.0"},{"org":"shared-services"},{"project":"alpha"}’
    ``` 



### Monitor progress

1. The Image Generator will provide high-level progress information on the console. For more details, see the log file associated with the job, located in the logs directory. Log files use the following naming convention: 
`image-PLATFORM-MODULES-BOOT_LOCATIONS` (for example, image-gce-ltm-1slot). 
2. To adjust the log level output to the log file, use the `--log-level` parameter.
   
### Locate files

You can locate files in the following directories:
   
* **artifacts** - Artifacts created during image generation. Directory structure is based on source image, platform, modules, and boot locations.
* **docs** - Supporting documentation
* **images** - The Image Generator tool generates a virtual disk image from the BIG-IP product ISO in the default, `images` directory. Use the `IMAGE_DIR` parameter to override this default value and store images in a different directory.
* **logs** - Log files. The `LOG_FILE` parameter can be used to override this default value. Default log file name is based on platform, modules, and boot locations.
* **src** - build-image script and other source files.

## Troubleshooting guide

This section provides troubleshooting information for setting up the environment and running the Image Generator tool, as well as common issues with supported cloud providers.

**Setup error message**:

The virtual environment was not created successfully because ensurepip is not
available. On Debian/Ubuntu systems, you need to install the python3-venv
package using the following command.

`apt-get install python3-venv`

**Remedy**:
You see this error, when you have not run the Setup Script. Run the [setup script][2].

**Environment error message**:
`qemu-system-x86_64: cannot set up guest memory 'pc.ram': Cannot allocate memory`

**Remedy**:
You see this error when you run in an environment with minimal memory. Increase memory for the environment.

**Environment error message**:
```
  Watchdog timer expired! (7201 seconds).
       Killing 'qemu' with pid 6073!

  Further explanation:
  The 'qemu' process should complete within a reasonable amount of time.
  If it does not, then we kill it to prevent it from blocking the build
  process indefinitely.   It is likely this is an intermittent issue and
  the next build will complete successfully.
```

**Remedy**:
Likely caused by either running in an environment that does not support virtualization or running in a lightweight environment. See [Prerequisites](#prerequisites).

**Missing packages error message**:
```
  Traceback (most recent call last):
   File "/home/ubuntu/ve-image-generator/src/lib/bash/../../bin/read_injected_files.py", line 22, in <module>
     from util.injected_files import read_injected_files
   File "/home/ubuntu/ve-image-generator/src/lib/python/util/injected_files.py", line 24, in <module>
     import distro
```

**Remedy**:
It is possible that the setup script encountered an error and did not complete, or was run as a different user. Run the setup script again, and then review the output.

**KVM permissions error message**:
```
  Could not access KVM kernel module: Permission denied
  qemu-system-x86_64: failed to initialize KVM: Permission denied
```

**Remedy**:

* Restart your system or log out and back in to your system.
* Check that the user is in the kvm group in: <br/>

  `/etc/group` <br/>
  `kvm:x:115:ubuntu` <br/>
  
  Shows user ubuntu in the kvm group.

* Check that the permissions is correct in the following file: <br/>

   `/lib/udev/rules.d/60-qemu-system-common.rules` <br/>
   (`KERNEL=="kvm", GROUP="kvm", MODE="0666"`)

* Check that the following is NOT present:<br/>

  `/var/run/reboot-required` <br/>
  
  You may have run the setup script, and ignored the reboot message.

**Runtime error message**:

* Review the log file. When you encounter an error, the log file can contain more detailed information regarding the error. 
* Change the log level. For troubleshooting, consider changing the log level to DEBUG or TRACE.

**AWS error message**:
`The service role <vmimport> does not exist or does not have sufficient permissions for the service to continue.`

**Remedy**:
AWS requires an **IAM Role** with import permissions (see the [AWS User Guide][3] for more information).

**VMware and AWS error message**:
`ovftool isn't installed or missing from PATH. Please install it before trying again.`

**Remedy**:
Download and install the [ovftool][22] before trying again.

## Support guide
Although the F5 BIG-IP Image Generator Tool is community-supported, the VE instances deployed from the images generated by this tool are supported by [F5 Support][23].

To report defects and security vulnerabilties, or submit enhancements and general questions open an issue within the GitHub repository. 

1. In the top-right corner, expand :heavy_plus_sign: **More**, and then select **New Issues** from the list. 
2. Enter a title, a description, and then click **Submit new issue**.

### Known issues
All known issues are now on the GitHub **Issues** tab for better tracking and visibility. Sort the [issues list][27] by expanding the **Label** column and selecting **Known issue**.



### Copyright

Copyright (C) 2019-2020 F5 Networks, Inc.

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







[1]: https://downloads.f5.com/esd/productlines.jsp
[2]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/setup-build-env
[3]: https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html
[4]: http://manpages.ubuntu.com/manpages/bionic/man1/kvm-ok.1.html
[5]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/docs/examples/config.yml
[6]: https://github.com/f5devcentral/f5-bigip-image-generator/tree/master/docs/providers/aws
[7]: https://github.com/f5devcentral/f5-bigip-image-generator/tree/master/docs/providers/azure
[8]: https://github.com/f5devcentral/f5-bigip-image-generator/tree/master/docs/providers/gce
[9]: https://cloud.google.com/iam/docs/creating-managing-service-accounts
[10]: https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli?view=azure-cli-latest
[11]: https://docs.microsoft.com/en-us/rest/api/storageservices/create-container 
[12]: https://docs.aws.amazon.com/quickstarts/latest/s3backup/step-1-create-bucket.html
[13]: https://cloud.google.com/storage/docs/creating-buckets
[14]: https://clouddocs.f5.com/cloud/public/v1/vmware/vmware_setup.html
[15]: https://github.com/f5devcentral/tmos-cloudinit/tree/master/tmos_configdrive_builder
[16]: https://github.com/f5devcentral/tmos-cloudinit
[17]: https://clouddocs.f5.com/cloud/public/v1/hyperv_index.html
[18]: https://clouddocs.f5.com/cloud/public/v1/kvm_index.html
[19]: https://docs.microsoft.com/en-us/azure/storage/blobs/storage-blob-container-properties-metadata
[20]: https://cloud.google.com/compute/docs/labeling-resources
[21]: https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/Using_Tags.html#tag-restrictions
[22]: https://code.vmware.com/web/tool/4.3.0/ovf
[23]: https://www.f5.com/company/contact/regional-offices#product-support
[24]: https://support.f5.com/csp/article/K4422
[25]: https://cloud.google.com/compute/docs/instances/enable-nested-virtualization-vm-instances#enablenestedvirt
[26]: https://github.com/f5devcentral/f5-bigip-image-generator/tree/master/docs/providers/alibaba
[27]: https://github.com/f5devcentral/f5-bigip-image-generator/issues?q=is%3Aopen+is%3Aissue+label%3A%22known+issue%22
[28]: https://docs.microsoft.com/en-us/azure/storage/common/storage-configure-connection-string
[29]: https://www.alibabacloud.com/help/doc-detail/31885.htm
[30]: https://www.alibabacloud.com/help/doc-detail/92270.htm?spm=a2c63.p38356.b99.123.319c412aF3kxA0
[31]: https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal            
