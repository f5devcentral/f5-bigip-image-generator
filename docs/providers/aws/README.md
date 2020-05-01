## AWS

In AWS, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to an [S3 Bucket storage][1] container.
3. Create the virtual machine image.


### Prerequisites

You need the system requirements described [here](../../../README.md), as well as sufficient permissions for a [VM Import Service Role][2] to create or describe the following resources: 

* Credentials/API keys 
* SSH keys uploaded 
* [S3 Bucket][1] 
* IAM Role with import permissions (see this [AWS article][2] for more information)
* Install the [ovftool][22] for creating the virtual disk.

### User guide

Define the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters at the command line with leading dashes (for example, `--aws-region`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|AWS_ACCESS_KEY_ID|Yes|[value]|Public key id string used for AWS account access.|
|AWS_BUCKET|Yes|[value]|AWS S3 bucket used during image generation.|
|AWS_IMAGE_SHARE_ACCOUNT_IDS|No|[value]|List of AWS account IDs with which you want the generated image shared.|
|AWS_REGION|Yes|[value]|Region to use for AWS image generation.|
|AWS_SECRET_ACCESS_KEY|Yes|[value]|Public key string used for AWS account access.|

##### NOTE:
------------
F5 recommends passing the credentials via ENV or CLI, rather than putting them in a configuration file.

------------------

#### Example:

The following example generates an  LTM_1SLOT image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][4] article.

```
./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p aws -m ltm -b 1

```

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


[1]: https://docs.aws.amazon.com/quickstarts/latest/s3backup/step-1-create-bucket.html
[2]: https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html
[3]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#image-generator-prerequisites
[22]: https://code.vmware.com/web/tool/4.3.0/ovf
[4]: https://support.f5.com/csp/article/K14946


