## Alibaba

In Albaba, the image generator tool will do the following:

1. Create a virtual disk image of BIG-IP 14.1.0.3+ locally.
2. Upload the virtual disk image to an Alibaba OSS bucket.
3. Create the virtual machine image.

For more information, consult the [Import custom images][2] topic.

### Prerequisites

You need the system requirements described [here](../../../README.md), as well as [sufficient RAM permissions][9] to create or describe the following resources:

* Credentials/API Keys
* SSH Keys uploaded
* Application credentials
* [RAM (Resource Access Manager) role][4] with import permissions (specifically, ``AliyunECSImageImportDefaultRole`` and ``AliyunECSImageImportRolePolicy``)
* [OSS, Bucket storage container][1]



###  User guide

Define the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters on the command line with leading dashes (for example, `--ALIBABA-BUCKET`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|ALIBABA_ACCESS_KEY_ID|Yes|[value]|Public key id string used for Alibaba account access.|
|ALIBABA_ACCESS_KEY_SECRET|Yes|[value]|Private key string used for Alibaba account access.|
|ALIBABA_BUCKET|Yes|[value]|Alibaba OSS bucket used for image storage.|
|ALIBABA_REGION|Yes|[value]|Alibaba ECS region used for image generation.|
|ALIBABA_IMAGE_SHARE_ACCOUNT_IDS|No|[value]|List of Alibaba account IDs with which you want the generated image shared.|


##### NOTE
----------

It is recommended to pass the credentials via ENV or CLI, rather than putting them in a configuration file.

---------------

#### Example

The following example generates an  LTM_1SLOT image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][5] article.


```
./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p alibaba -m ltm -b 1

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






[1]: https://www.alibabacloud.com/help/doc-detail/31885.htm
[2]: https://www.alibabacloud.com/help/doc-detail/25464.htm
[9]: https://www.alibabacloud.com/help/doc-detail/92270.htm?spm=a2c63.p38356.b99.123.319c412aF3kxA0
[4]: https://www.alibabacloud.com/help/doc-detail/25542.htm
[5]: https://support.f5.com/csp/article/K14946



