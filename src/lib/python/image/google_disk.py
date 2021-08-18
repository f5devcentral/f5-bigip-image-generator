"""Google disk module"""
# Copyright (C) 2019-2021 F5 Networks, Inc
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



import datetime

import google.auth
from google.cloud import storage
from google.oauth2 import service_account
from google.api_core.exceptions import GoogleAPIError

from image.base_disk import BaseDisk
from util.misc import ensure_value_from_dict
from util.config import get_config_value
from util.config import get_dict_from_config_json
from util.logger import LOGGER

class GoogleDisk(BaseDisk):
    """
    Manage Google disk
    """
    def __init__(self, input_disk_path):
        """Initialize google disk object."""
        # First initialize the super class.
        super().__init__(input_disk_path)
        self.bucket = None

    def clean_up(self):
        """Clean-up the uploaded disk after image generation."""
        # Delete the uploaded disk as it no longer needs to be retained.
        try:
            if self.bucket and self.uploaded_disk_name:
                self.delete_blob()
        except google.cloud.exceptions.NotFound as exception:
            # Report the exception without propagating it up to ensure this
            # doesn't stop the rest of the clean-up.
            LOGGER.error("Caught exception during '%s' disk deletion.",
                         self.uploaded_disk_name)
            LOGGER.exception(exception)
        except RuntimeError as runtime_exception:
            LOGGER.error("Caught runtime exception during '%s' disk deletion.",
                         self.uploaded_disk_name)
            LOGGER.exception(runtime_exception)

    def extract(self):
        """
        Input disk is already tar.gz file of disk.tar.
        Just copy the path.
        """
        self.disk_to_upload = self.input_disk_path
        LOGGER.info("Google disk_to_upload is '%s'.", self.disk_to_upload)

    def get_blob(self, disk_path):
        """
        Gets the GCE disk blob representing the given disk_path.
        """
        blob = None
        try:
            blob = self.bucket.get_blob(disk_path)
        except google.cloud.exceptions.NotFound as exception:
            LOGGER.exception(exception)
            raise exception
        return blob

    def init_bucket(self):
        """
        Populate the bucket object based on GCE credential and GCE_BUCKET.
        """
        try:
            # start storage client
            creds_dict = get_dict_from_config_json('GOOGLE_APPLICATION_CREDENTIALS')
            credentials = service_account.Credentials.from_service_account_info(creds_dict)
            project = ensure_value_from_dict(creds_dict, "project_id")
        except ValueError as value_exc:
            LOGGER.exception(value_exc)
            raise RuntimeError("Failed to initialize GOOGLE_APPLICATION_CREDENTIALS credentials.") \
                from value_exc

        try:
            storage_client = storage.Client(credentials=credentials, project=project)
        except google.auth.exceptions.DefaultCredentialsError as exception:
            LOGGER.exception(exception)
            raise RuntimeError("storage.Client failed with DefaultCredentialsError.") \
                from exception
        # ensure bucket exists
        bucket_name = get_config_value('GCE_BUCKET')
        if not bucket_name:
            raise RuntimeError("GCE_BUCKET is missing.")

        try:
            self.bucket = storage_client.lookup_bucket(bucket_name)
        except google.api_core.exceptions.BadRequest as exception:
            LOGGER.exception(exception)
            raise RuntimeError("storage_client.lookup_bucket failed with BadRequest.") \
                from exception

        if self.bucket is None:
            LOGGER.info('Creating bucket [%s]', bucket_name)
            try:
                self.bucket = storage_client.create_bucket(bucket_name)
            except GoogleAPIError as exception:
                LOGGER.exception(exception)
                raise RuntimeError("storage_client.create_bucket failed.") from exception

        LOGGER.debug("init_bucket completed successfully.")

    def delete_blob(self):
        """
        Delete the blob corresponding to self.uploaded_disk_name if it exists.
        """
        try:
            # Populate the bucket if not already.
            if self.bucket is None:
                self.init_bucket()

            if self.uploaded_disk_name is None:
                raise RuntimeError("Trying to delete a non-existent uploaded disk.")

            blob = self.get_blob(self.uploaded_disk_name)
            if blob is not None:
                LOGGER.info("Deleting blob '%s'.", self.uploaded_disk_name)
                self.bucket.delete_blob(self.uploaded_disk_name)

                blob = self.get_blob(self.uploaded_disk_name)
                if blob is not None:
                    raise RuntimeError("Deleting blob '{}' silently failed as it still exists."
                                       .format(self.uploaded_disk_name))
        except google.cloud.exceptions.NotFound as exception:
            LOGGER.exception(exception)
            raise exception
        except RuntimeError as runtime_exception:
            raise runtime_exception

    def upload(self):
        """
        Upload tar.gz stored at self.disk_to_upload to Google storage
        """
        try:
            # Populate the bucket if not already.
            if self.bucket is None:
                self.init_bucket()

            # form blob name
            prefix = datetime.datetime.now().strftime('%Y%m%d') + '/'
            self.uploaded_disk_name = prefix + BaseDisk.decorate_disk_name(self.disk_to_upload)

            # delete the blob if it exists
            self.delete_blob()

            # create blob
            blob = self.bucket.blob(self.uploaded_disk_name)
            if blob is None:
                raise RuntimeError("Factory constructor for blob '{}' failed."
                                   .format(self.uploaded_disk_name))

            # upload blob
            LOGGER.info("Started to upload '%s' at '%s'.", self.uploaded_disk_name,
                        datetime.datetime.now().strftime('%H:%M:%S'))
            blob.upload_from_filename(self.disk_to_upload)
            LOGGER.info("Finished to upload '%s' at '%s'.", self.uploaded_disk_name,
                        datetime.datetime.now().strftime('%H:%M:%S'))
            if not blob.exists():
                raise RuntimeError("Uploading blob '{}' failed.".format(self.uploaded_disk_name))
        except RuntimeError as exception:
            LOGGER.exception(exception)
            raise exception
