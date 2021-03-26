## GCE

In GCE, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to a GCE bucket.
3. Create the virtual machine image.


### Prerequisites

You need the system requirements described [here](../../../README.md), as well as [sufficient permissions][9] to create or describe the following resources:

* Credentials/API Keys
* SSH Keys uploaded
* Application credentials
* [GCE Bucket storage container][1]

See this [GCE article][9] for more service account information.


###  User guide

Define the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters on the command line with leading dashes (for example, `--gce-bucket`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|GCE_BUCKET|Yes|[value]|GCE disk storage bucket used during image generation.|
|GCE_IMAGE_FAMILY_NAME|No|[value]|An optional [Family Name][10] to assign to the generated image.|
|GCE_IMAGE_UPLOAD_CHUNK_SIZE|No|[value]|Set the size of `chunks` used to upload images to GCS. If unset, the default chunk-size will be used. See [NOTES](#NOTES) below.|
|GCE_PROJECT_ID|No|[value]|GCP Project ID to use for uploaded images. If not specified, the project id associated with the service account will be used.|
|GOOGLE_APPLICATION_CREDENTIALS|No|[value]|Service account auth credentials as a JSON string or a file path ending in .json.  For help with generating these credentials, refer to bit.ly/2MYQpHN. If credentials are not explictly set, Application Default Credentials will be used for authentication.|

##### NOTES
-----------

It is recommended to pass the credentials via ENV or CLI, rather than putting them in a configuration file.

Google storage API uploads data to a bucket in chunks; if an entire chunk cannot
be uploaded in ~60s, a timeout error will occur. Use the parameter
GCE_IMAGE_UPLOAD_CHUNK_SIZE to set a chunk-size that you know can be uploaded
within 60 seconds to work around timeout issues.

---------------

#### Example

The following example generates an  LTM_1SLOT image for a BIG-IP VE 15.X. For deployed image sizes for various BIG-IP VE versions, see the [K14946][4] article.

```
./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p gce -m ltm -b 1

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



[1]: https://cloud.google.com/storage/docs/creating-buckets
[9]: https://cloud.google.com/iam/docs/creating-managing-service-accounts
[3]: https://github.com/f5devcentral/f5-bigip-image-generator/blob/master/README.md#image-generator-prerequisites
[4]: https://support.f5.com/csp/article/K14946
[10]: https://cloud.google.com/compute/docs/images#image_families

