"""Azure disk module"""
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


import json
from multiprocessing import Process
import os
from time import time, sleep

from azure.common import AzureException, AzureMissingResourceHttpError

from azure.storage.blob import BlobClient
from image.base_disk import BaseDisk
from metadata.cloud_metadata import CloudImageMetadata
from metadata.cloud_tag import CloudImageTags
from util.config import get_config_value
from util.logger import LOGGER
from util.retrier import Retrier


class AzureDisk(BaseDisk):
    """
    Manage Azure disk
    """
    # pylint: disable=too-many-instance-attributes
    def __init__(self, input_disk_path, working_dir):
        """Initialize azure disk object."""
        # First initialize the super class.
        super().__init__(input_disk_path, working_dir)
        self.uploaded_disk_url = None

        self.connection_string = get_config_value('AZURE_STORAGE_CONNECTION_STRING')
        self.container_name = get_config_value('AZURE_STORAGE_CONTAINER_NAME')
        self.blob = None
        self.progress_cb_lu = 0
        self.metadata = CloudImageMetadata()

    def clean_up(self):
        """Clean-up the uploaded disk after image generation."""

    def set_uploaded_disk_name(self, disk_name):
        """Set the uploaded disk name"""
        # As Azure disk takes its name from the image-name (unlike other clouds where
        # the disk-name are auto-generated during disk extraction), append disk extension
        # to the uploaded disk name.
        self.uploaded_disk_name = disk_name + '.vhd'
        LOGGER.info("The uploaded disk name is '%s'.", self.uploaded_disk_name)

    def extract(self):
        """Extract the vhd disk out of tar.gz."""
        self.disk_to_upload = BaseDisk.decompress(self.input_disk_path, '.vhd', self.working_dir)
        LOGGER.info("Azure disk_to_upload = '%s'", self.disk_to_upload)

    def _get_tags(self):
        tags = CloudImageTags(self.metadata)
        tags.title_case_keys()
        return tags.get()

    def _progress_cb(self, byte_up, byte_total):
        sec = int(time())

        # No update within 10 second interval
        if sec-self.progress_cb_lu > 10:
            self.progress_cb_lu = sec
            byte_up //= (1<<20)
            byte_total //= (1<<20)
            LOGGER.info('Uploaded %d MB of total %d MB', byte_up, byte_total)

    def upload(self):
        """ Upload a F5 BIG-IP VE image to provided container """

        def upload_azure():
            with open(self.disk_to_upload,'rb') as vhd_file:
                self.blob.upload_blob(
                    vhd_file.read(),
                    blob_type="PageBlob",
                    metadata=self._get_tags()
                    )

        def _upload_impl():
            """ Azure blob upload implementation """
            timeout = int(get_config_value('AZURE_BLOB_UPLOAD_TIMEOUT'))

            try:
                self.connection_string = get_config_value('AZURE_STORAGE_CONNECTION_STRING')
                LOGGER.info("create blob client")
                self.blob = BlobClient.from_connection_string(
                    conn_str=self.connection_string,
                    container_name=self.container_name,
                    blob_name=self.uploaded_disk_name,
                    connection_timeout=timeout
                    )

                LOGGER.info(self._get_tags())
                nonlocal upload_azure
                upload_azure_p = Process(target=upload_azure)
                upload_azure_p.start()
                limit = int(timeout/10)
                for _ in range(limit):
                    if not upload_azure_p.is_alive():
                        break
                    sleep(10)
                    os.write(1, b".")
                else:
                    raise TimeoutError

                LOGGER.info(self.blob.get_blob_properties())
                local_blob_size = os.stat(self.disk_to_upload).st_size

                uploaded_blob_size = self.blob.get_blob_properties().get("size")

                LOGGER.info("uploaded blob size: %s and local blob_size: %s", \
                            str(uploaded_blob_size), str(local_blob_size))
                if uploaded_blob_size != local_blob_size:
                    return False

            except AzureMissingResourceHttpError:
                LOGGER.error("Exception during uploading %s", self.disk_to_upload)
                return False
            except AzureException:
                LOGGER.error("Exception during uploading %s", self.disk_to_upload)
                return False
            except TimeoutError:
                LOGGER.error("Timeout while uploading")
                return False

            self.uploaded_disk_url = self.blob.url
            # save uploaded disk in artifacts dir json file
            vhd_url_json = {"vhd_url": self.uploaded_disk_url}
            artifacts_dir = get_config_value("ARTIFACTS_DIR")
            with open(artifacts_dir + "/vhd_url.json", "w") as vhd_url_json_file:
                json.dump(vhd_url_json, vhd_url_json_file)

            # insert file with vhd url
            self.metadata.set(self.__class__.__name__, 'vhd_url', self.uploaded_disk_url)
            self.metadata.set(self.__class__.__name__, 'image_id', self.uploaded_disk_name)
            LOGGER.info('Uploaded disk url is: %s', self.uploaded_disk_url)
            return True

        retrier = Retrier(_upload_impl)
        retrier.tries = int(get_config_value('AZURE_BLOB_UPLOAD_COMPLETED_RETRY_COUNT'))
        retrier.delay = int(get_config_value('AZURE_BLOB_UPLOAD_COMPLETED_RETRY_DELAY'))
        LOGGER.info("Waiting for blob %s to be uploaded.", self.disk_to_upload)

        if retrier.execute():
            LOGGER.info("blob [%s] is ready.", self.disk_to_upload)
            return True
        LOGGER.error("blob [%s] was still not ready after checking [%d] times!",
                     self.disk_to_upload, retrier.tries)
        raise RuntimeError("Runtime Error Occured during Azure Disk Upload")
