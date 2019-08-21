## GCE

In GCE, the image generator tool will do the following:

1. Create a virtual disk image locally.
2. Upload the virtual disk image to a GCE bucket.
3. Create the virtual machine image.


### Prerequisites

You need the system requirements described [here][3], as well as [sufficient permissions][9] to create or describe the following resources:

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
|GOOGLE_APPLICATION_CREDENTIALS|Yes|[value]|Service account auth credentials as a JSON string or a file path ending in .json.  For help with generating these credentials, refer to bit.ly/2MYQpHN. .|

##### NOTE
----------

It is recommended to pass the credentials via ENV or CLI, rather than putting them in a configuration file.

---------------

#### Example

```
./build-image -i /var/tmp/BIGIP-15.0.0-0.0.39.iso -c config.yml -p gce -m ltm -b 1

```

[1]: https://cloud.google.com/storage/docs/creating-buckets
[9]: https://cloud.google.com/iam/docs/creating-managing-service-accounts
[3]: https://gitlab.f5net.com/vteam-cloud/ve-image-generator/blob/dev/README.md#image-generator-prerequisites

