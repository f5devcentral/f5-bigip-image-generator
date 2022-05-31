"""Azure Image module"""
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


from datetime import datetime
from time import time

from msrest import exceptions
from azure.identity import ClientSecretCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.core.exceptions import (
    ResourceNotFoundError,
    AzureError
    )

from image.azure_disk import AzureDisk
from image.base_image import BaseImage
from metadata.cloud_metadata import CloudImageMetadata
from util.config import get_config_value
from util.logger import LOGGER
from util.retrier import Retrier

class AzureImage(BaseImage):
    """ Create F5 BIG-IP image based on disk uploaded to Azure Storage Account """
    def __init__(self, working_dir, input_disk_path):
        super().__init__(working_dir, input_disk_path)
        self.disk = AzureDisk(input_disk_path, working_dir)
        self.metadata = CloudImageMetadata()
        self.compute_client = None
        self.image_name = None


    def clean_up(self):
        """ Clean-up """


    def create_image(self, image_name):
        """ Create image implementation for Azure """
        self.image_name = image_name

        self.open_compute_client()

        # if an image with the same name exists, delete it
        if self.does_image_exist():
            LOGGER.info('Delete an old image named \'%s\'.', self.image_name)
            self.compute_client.images.begin_delete(
                get_config_value('AZURE_RESOURCE_GROUP'), self.image_name + '.vhd')
            if self.wait_for_image_deletion():
                raise RuntimeError('Failed to delete old \'{}\' image'.format(self.image_name))

        # create the image
        self.issue_image_creation_commands()

        # Do not implement tags for images in Azure. Because tags in Azure are too global,
        # and metadata (an alternative to tags) does not have Python API for images in Azure.


    def open_compute_client(self):
        """ Open compute management client """
        try:
            credentials = ClientSecretCredential(
                tenant_id=get_config_value('AZURE_TENANT_ID'),
                client_id=get_config_value('AZURE_APPLICATION_ID'),
                client_secret=get_config_value('AZURE_APPLICATION_SECRET'))
            self.compute_client = ComputeManagementClient(
                credential=credentials,
                subscription_id=get_config_value('AZURE_SUBSCRIPTION_ID')
            )
        except exceptions.AuthenticationError as exc:
            # check if more specific message can be provided
            error_key = 'error'
            if hasattr(exc, 'inner_exception') and hasattr(exc.inner_exception, 'error_response') \
                and error_key in exc.inner_exception.error_response:
                error_dict = exc.inner_exception.error_response
                bad_parameter = None
                if error_dict[error_key] == 'invalid_request':
                    bad_parameter = 'AZURE_TENANT_ID'
                if error_dict[error_key] == 'unauthorized_client':
                    bad_parameter = 'AZURE_APPLICATION_ID'
                if error_dict[error_key] == 'invalid_client':
                    bad_parameter = 'AZURE_APPLICATION_SECRET'

                if bad_parameter:
                    azure_failure_msg = 'Azure did not accept the request. Possible fix:'
                    raise RuntimeError('{} verify that \'{}\' is correct.'.format(
                        azure_failure_msg, bad_parameter)) from exc
            raise
        return True

    def does_image_exist(self):
        """ Wrap around get method to determine whether the image exists.
            Expects to get msrestazure.azure_exceptions.CloudError exception
            with error.error equal to 'ResourceNotFound' when image does not exist,
            or error.error equal to 'NotFound' when image is on the last stage of its existence.
            Also providing a particular subscription exception, since it is likely to be
            a first Azure compute call that is issued.
            Returns True or False.
        """
        try:
            self.compute_client.images.get(get_config_value('AZURE_RESOURCE_GROUP'),
                                           self.image_name)
        except ResourceNotFoundError:
            LOGGER.info("Image does not already exist.")
            return False
        except AzureError as az_error:
            LOGGER.error("Azure error: %s", az_error)
            raise
        # azure exception "NotFound" was removed

        LOGGER.info('Image already exists')
        return True


    def wait_for_image_deletion(self):
        """ Wait for image to be deleted """

        def _wait_for_image_deletion():
            """ Check if image does not exist """
            return not self.does_image_exist()

        retrier = Retrier(_wait_for_image_deletion)
        retrier.tries = int(get_config_value('AZURE_DELETE_IMAGE_RETRY_COUNT'))
        retrier.delay = int(get_config_value('AZURE_DELETE_IMAGE_RETRY_DELAY'))

        if retrier.execute():
            LOGGER.info('Preexisting image \'%s\' has been deleted.', self.image_name)
        else:
            raise RuntimeError('Exhausted all {} retries for image \'{}\' to be deleted.'.
                               format(retrier.tries, self.image_name))


    def issue_image_creation_commands(self):
        """ Initiate image creation and wait for image to be ready """

        # start image creation
        LOGGER.info('Started creation of image \'%s\' at %s.', self.image_name,
                    datetime.now().strftime('%H:%M:%S'))
        start_time = time()
        async_create_image = self.compute_client.images.begin_create_or_update(
            get_config_value('AZURE_RESOURCE_GROUP'),
            self.image_name,
            {
                'location': get_config_value('AZURE_REGION'),
                'storage_profile': {
                    'os_disk': {
                        'os_type': 'Linux',
                        'os_state': "Generalized",
                        'blob_uri': self.disk.uploaded_disk_url,
                        'caching': "ReadWrite"
                    }
                },
                'hyperVGeneration': 'V1'
            }
        )

        # wait for image to be ready
        LOGGER.info('Created image %s', async_create_image.result())
        LOGGER.info('Creation of image \'%s\' took %d seconds.', self.image_name,
                    time() - start_time)
