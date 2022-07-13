"""AWS disk module"""
# Copyright (C) 2019-2022 F5 Inc
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.



from botocore.exceptions import ClientError

from image.base_disk import BaseDisk
from util.config import get_config_value
from util.logger import LOGGER


class AWSDisk(BaseDisk):
    """Class for handling AWS disk related actions"""
    def __init__(self, input_disk_path, working_dir, session):
        """Initialize aws disk object."""
        super().__init__(input_disk_path, working_dir)
        self.session = session

        # Create s3 resource object for performing high-level disk actions.  We'll use this wherever
        # possible since it automatically calls several lower-level functions for us.
        self.s3_resource = self.session.resource('s3')

        # Create s3 client object for performing low-level disk actions.  We'll use this for any
        # operations which aren't supported by the s3 resource object.
        self.s3_client = self.session.client('s3')

        self.bucket_name = get_config_value('AWS_BUCKET')
        if not self.bucket_name:
            raise RuntimeError("AWS_BUCKET is missing.")

    def clean_up(self):
        """Clean-up."""
        try:
            if self.bucket_name is not None and self.uploaded_disk_name is not None:
                LOGGER.debug("Deleting '%s' from the bucket '%s'.",
                             self.uploaded_disk_name, self.bucket_name)
                self.delete_uploaded_disk(self.uploaded_disk_name)
        except ClientError as client_error:
            # Log the exception without propagating it further.
            LOGGER.exception(client_error)

    def extract(self):
        """Extract the vmdk disk out of zip."""
        LOGGER.debug("Extracting '.vmdk' disk file from [%s].", self.input_disk_path)
        self.disk_to_upload = BaseDisk.decompress(self.input_disk_path, '.vmdk', self.working_dir)
        LOGGER.info("AWS disk_to_upload = '%s'", self.disk_to_upload)

    def is_bucket_exist(self):
        """Checks if a bucket with self.bucket_name exists in S3."""
        try:
            return self.s3_resource.Bucket(self.bucket_name).creation_date is not None
        except ClientError as client_error:
            LOGGER.exception(client_error)
        return False

    def is_disk_exist(self, disk_name):
        """Checks if the given disk_name exists in the bucket in S3"""
        try:
            bucket = self.get_bucket()
            if bucket is not None:
                bucket_objs = list(bucket.objects.filter(Prefix=disk_name))
                return bucket_objs and bucket_objs[0].key == disk_name
        except ClientError as client_error:
            LOGGER.exception(client_error)
        return False

    def delete_uploaded_disk(self, disk_name):
        """Deletes the given disk_name from the self.bucket_name S3 bucket."""
        if self.is_disk_exist(disk_name):
            self.s3_client.delete_object(Bucket=self.bucket_name, Key=disk_name)
            LOGGER.info("Deleted '%s' from bucket '%s'.", disk_name, self.bucket_name)

    def create_bucket(self):
        """Creates a bucket self.bucket_name in S3"""
        try:
            self.s3_resource.create_bucket(Bucket=self.bucket_name,
                                           CreateBucketConfiguration={
                                               'LocationConstraint': self.session.region_name})
        except ClientError as client_error:
            # Suppress the error around trying to create an already existing bucket.
            if client_error.response['Error']['Code'] == 'BucketAlreadyExists' or \
               client_error.response['Error']['Code'] == 'BucketAlreadyOwnedByYou':
                LOGGER.error("Tried to create an already existing bucket '%s'.",
                             self.bucket_name)
            else:
                LOGGER.exception(client_error)
                raise

    def get_bucket(self):
        """Get the S3 bucket object for the self.bucket_name"""
        bucket = None
        try:
            if self.is_bucket_exist() is True:
                LOGGER.debug("'%s' bucket exists.", self.bucket_name)
                bucket = self.s3_resource.Bucket(self.bucket_name)
        except ClientError as client_error:
            LOGGER.exception(client_error)
            # Suppress the error around non-existent bucket.
            if client_error.response['Error']['Code'] == 'NoSuchBucket':
                LOGGER.error("Bucket '%s' doesn't exist.", self.bucket_name)
            else:
                LOGGER.exception(client_error)
                # Re-raise the exception to force the caller to handle it.
                raise

        return bucket

    def upload(self):
        """Upload the disk to the s3 bucket represented by AWS_BUCKET"""
        try:
            if self.is_bucket_exist() is False:
                LOGGER.debug("Creating '%s' bucket as it doesn't exist.", self.bucket_name)
                self.create_bucket()

            self.uploaded_disk_name = BaseDisk.decorate_disk_name(self.disk_to_upload)

            LOGGER.info("Uploading '%s' to the bucket '%s'.", self.uploaded_disk_name,
                        self.bucket_name)
            self.s3_client.upload_file(self.disk_to_upload, self.bucket_name,
                                       self.uploaded_disk_name)
            LOGGER.info("Successfully uploaded '%s'.", self.uploaded_disk_name)
        except ClientError as client_error:
            LOGGER.exception(client_error)
            raise RuntimeError("AWS upload disk operation failed.") from client_error
