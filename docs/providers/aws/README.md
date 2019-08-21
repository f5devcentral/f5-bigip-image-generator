## AWS

In AWS, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to an [S3 Bucket storage][1] container.


### Prerequisites

You need the system requirements described [here][3], as well as sufficient permissions for a [VM Import Service Role][2] to create or describe the following resources: 

* Credentials/API keys 
* SSH keys uploaded 
* [S3 Bucket][1] 
* IAM Role with import permissions (see this [AWS article][2] for more information)

### User guide

Define the following parameters in a config file or set as an environment variable.  Optionally, you can use these parameters at the command line with leading dashes (for example, `--aws-region`).

|Parameter|Required|Values|Description|
|:--------|:-------|:-----|:----------|
|AWS_ACCESS_KEY_ID|Yes|[value]|Public key id string used for AWS account access.|
|AWS_BUCKET|Yes|[value]|AWS S3 bucket used during image generation.|
|AWS_IMAGE_MAX_RETRY|No|[[0-9]+]|The number of times to retry image related operations when running AWS commands.|
|AWS_IMAGE_SHARE_ACCOUNT_IDS|No|[value]|List of AWS account IDs or the path to the .yml file containing the list of account IDs with which you want the generated AWS AMI shared.|
|AWS_REGION|Yes|[value]|Region to use for AWS image generation.|
|AWS_SECRET_ACCESS_KEY|Yes|[value]|Public key string used for AWS account access.|

##### NOTE:
------------
F5 recommends passing the credentials via ENV or CLI, rather than putting them in a configuration file.

------------------

#### Example:
```
./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p aws -m ltm -b 1

```



[1]: https://docs.aws.amazon.com/quickstarts/latest/s3backup/step-1-create-bucket.html
[2]: https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html
[3]: https://gitlab.f5net.com/vteam-cloud/ve-image-generator/blob/dev/README.md#image-generator-prerequisites

