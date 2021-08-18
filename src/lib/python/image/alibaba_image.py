"""Alibaba image module"""
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
from time import time
import json
from aliyunsdkcore.acs_exception.exceptions import ServerException
from image.alibaba_disk import AlibabaDisk
from image.alibaba_client import AlibabaClient
from image.base_image import BaseImage
from metadata.cloud_metadata import CloudImageMetadata
from metadata.cloud_tag import CloudImageTags
from util.config import get_config_value, get_list_from_config_yaml
from util.logger import LOGGER
from util.retrier import Retrier
from util.misc import save_image_id

class AlibabaImage(BaseImage):
    """ Class for handling Alibaba image related actions """

    def __init__(self, working_dir, input_disk_path):
        super().__init__(working_dir, input_disk_path)
        self.disk = AlibabaDisk(input_disk_path, working_dir)
        self.client = AlibabaClient()
        self.prev_progress = None
        self.image_id = None

    def clean_up(self):
        """ Clean-up cloud objects created by this class and its members """
        LOGGER.info('Cleaning-up AlibabaImage artifacts.')
        if self.disk is not None:
            self.disk.clean_up()
        LOGGER.info('Completed AlibabaImage clean-up.')

    def upload_disk(self):
        """ Upload the disk to cloud """
        self.disk.upload()

    def create_image(self, image_name):
        """ Create image implementation for Alibaba """
        images_json = self.client.describe_images(None, image_name)
        if int(images_json['TotalCount']) == 0:
            LOGGER.debug('No old images named \'%s\' were found', image_name)
        else:
            # image names are unique, delete only one image
            image_id = images_json['Images']['Image'][0]['ImageId']
            LOGGER.info('Image \'%s\' already exists, its id is \'%s\', deleting it', image_name,
                        image_id)
            self.client.delete_image(image_id)

        # start image creation
        LOGGER.info('Started creation of image \'%s\' at %s', image_name,
                    datetime.datetime.now().strftime('%H:%M:%S'))
        start_time = time()
        imported_image = self.client.import_image(get_config_value('ALIBABA_BUCKET'),
                                                  self.disk.uploaded_disk_name, image_name)
        if 'Code' in imported_image.keys():
            if imported_image['Code'] == 'InvalidOSSObject.NotFound':
                raise RuntimeError('ImportImageRequest could not find uloaded disk \'' +
                                   image_name + '\'')
            if imported_image['Code'] == 'InvalidImageName.Duplicated':
                raise RuntimeError('Image \'' + image_name + '\' still exists, ' +
                                   'should have been removed by this point')
            if imported_image['Code'] == 'ImageIsImporting':
                raise RuntimeError('Another image named \'' + image_name + '\' is in the ' +
                                   'process of importing, probably from the previous run. ' +
                                   'Delete it first.')

        if 'ImageId' not in imported_image.keys() or 'TaskId' not in imported_image.keys():
            LOGGER.info('Alibaba response to ImportImageRequest:')
            LOGGER.info(json.dumps(imported_image, sort_keys=True, indent=4,
                                   separators=(',', ': ')))
            raise RuntimeError('ImageId and/or TaskId were not found in the response ' +
                               'cannot initiate image import')
        self.image_id = imported_image['ImageId']

        # save image id in artifacts dir json file
        save_image_id(self.image_id)

        task_id = imported_image['TaskId']
        LOGGER.info('Started image import with image id \'%s\' and task id \'%s\'', self.image_id,
                    task_id)

        task_status_count = int(get_config_value('ALIBABA_IMAGE_IMPORT_MONITOR_RETRY_COUNT'))
        task_status_delay = int(get_config_value('ALIBABA_IMAGE_IMPORT_MONITOR_RETRY_DELAY'))
        if self.monitor_task(task_id, task_status_count, task_status_delay):
            LOGGER.info('Image \'%s\' imported after %d seconds',
                        self.image_id, time() - start_time)
        else:
            canceled_task_msg = 'Image import failed or took too long, ' + \
                                'canceling task \'{}\' and '.format(task_id) + \
                                'deleting image \'{}\''.format(self.image_id)
            LOGGER.info(canceled_task_msg)
            self.client.cancel_task(task_id)
            self.client.delete_image(self.image_id)
            raise RuntimeError('Failed to import image \'{}\' after monitoring it for {} retries'.
                               format(self.image_id, task_status_count))

        # Add image_id and location (region) to the metadata used for image registration
        metadata = CloudImageMetadata()
        metadata.set(self.__class__.__name__, 'image_id', self.image_id)
        metadata.set(self.__class__.__name__, 'location', get_config_value('ALIBABA_REGION'))

        # Add tags to image
        LOGGER.info('Add tags to image \'%s\'', self.image_id)
        self.client.add_tags(self.image_id, 'image', CloudImageTags(metadata).get())

        # Add tags to associated snapshot
        images_json = self.client.describe_images(self.image_id, None)
        if not 'Images' in images_json.keys():
            LOGGER.error('No image data found for image \'%s\'', self.image_id)
            LOGGER.error('Unable to tag snapshot.')
        else:
            snapshot_id = images_json['Images']['Image'][0] \
                              ['DiskDeviceMappings']['DiskDeviceMapping'][0]['SnapshotId']
            LOGGER.info('Add tags to snapshot \'%s\'', snapshot_id)
            self.client.add_tags(snapshot_id, 'snapshot', CloudImageTags(metadata).get())

    def share_image(self):
        """Reads a list of account IDs and shares the image with each of those accounts."""
        share_account_ids = get_list_from_config_yaml('ALIBABA_IMAGE_SHARE_ACCOUNT_IDS')
        if share_account_ids:
            try:
                LOGGER.info("Share the image with multiple accounts.")
                self.client.share_image_with_accounts(self.image_id, share_account_ids)

            except ServerException as exc:
                LOGGER.exception(exc)
                if exc.get_error_code() == 'InvalidAccount.NotFound' and \
                    exc.get_error_msg().startswith('The specified parameter "AddAccount.n" or ' +
                                                   '"RemoveAccount.n"  does not exist.'):
                    raise RuntimeError('InvalidAccount.NotFound: Check if the account IDs are ' +
                                       'correct') from exc
                if exc.get_error_code() == 'InvalidImageId.NotFound' and \
                    exc.get_error_msg().startswith('The specified ImageId does not exist'):
                    raise RuntimeError('InvalidImageId.NotFound: Check if the Image ID exists') \
                        from exc
                raise exc

            # Acknowledge all the account-ids that the image was shared with.
            if self.is_share_image_succeeded(share_account_ids):
                LOGGER.info("Image sharing with other accounts was successful")
        else:
            LOGGER.info("No account IDs found for sharing the image")

    def is_share_image_succeeded(self, share_account_ids):
        """Helper utility for share_image() that goes through the list of share_account_ids
           and confirms that the image was shared with all accounts. The function logs any
           error during its execution without propagating it up."""
        response_json = None
        try:
            LOGGER.info("Checking which accounts were added for sharing this image")
            response_json = self.client.describe_image_share_permission(self.image_id)

        except ServerException as exc:
            LOGGER.exception(exc)
            if exc.get_error_code() == 'InvalidImageId.NotFound' and \
                exc.get_error_msg().startswith('The specified ImageId does not exist'):
                raise RuntimeError('InvalidImageId.NotFound: Check if the Image ID exists') \
                    from exc
            raise exc

        num_accounts = len(response_json['Accounts']['Account'])
        shared_accounts = []
        for each_account in range(num_accounts):
            account_id = response_json['Accounts']['Account'][each_account]['AliyunId']
            shared_accounts.append(int(account_id))

        counter = 0
        for an_account in share_account_ids:
            if an_account in shared_accounts:
                LOGGER.info("The image was successfully shared with account: %s", an_account)
                counter += 1
            else:
                LOGGER.warning("The image was not shared with account: %s", an_account)

        # Confirm that the number of accounts in share_account_ids and image's
        # 'LaunchPermissions' are matching.
        return counter == len(share_account_ids)

    def monitor_task(self, task_id, task_status_count, task_status_delay):
        """ Monitor task progress by issuing DescribeTaskAttributeRequest requets
            task_status_count - max number of requests
            task_status_delay - delay between requests
            return True if the task succeeded, False otherwise """
        self.prev_progress = None
        unsuccessful_finish_msg = 'Task finished unsuccessfully, note \'TaskProcess\' value'
        def _monitor_task():
            task = self.client.describe_task_attribute(task_id)
            if 'TaskProcess' not in task.keys() or 'TaskStatus' not in task.keys():
                LOGGER.info('Alibaba response to DescribeTaskAttributeRequest:')
                LOGGER.info(json.dumps(task, sort_keys=True, indent=4, separators=(',', ': ')))
                raise RuntimeError('TaskStatus and/or TaskProcess were not found in the response ' +
                                   'cannot monitor task')

            if task['TaskStatus'] != 'Processing' and task['TaskStatus'] != 'Waiting' and \
               task['TaskStatus'] != 'Finished':
                LOGGER.info('Alibaba response to DescribeTaskAttributeRequest:')
                LOGGER.info(json.dumps(task, sort_keys=True, indent=4, separators=(',', ': ')))
                raise RuntimeError('Unexpected TaskStatus \'{}\' for task \'{}\''.
                                   format(task['TaskStatus'], task_id))

            if task['TaskProcess'] != self.prev_progress:
                self.prev_progress = task['TaskProcess']
                LOGGER.info('Task progress: \'%s\'', task['TaskProcess'])
            if task['TaskStatus'] == 'Finished':
                if task['TaskProcess'] == '100%':
                    return True
                LOGGER.info(unsuccessful_finish_msg)
                LOGGER.info('Alibaba response to DescribeTaskAttributeRequest:')
                LOGGER.info(json.dumps(task, sort_keys=True, indent=4, separators=(',', ': ')))
                raise RuntimeError(unsuccessful_finish_msg)
            return False

        retrier = Retrier(_monitor_task)
        retrier.tries = task_status_count
        retrier.delay = task_status_delay
        try:
            return retrier.execute()
        except RuntimeError as exp:
            if exp.args[0] == unsuccessful_finish_msg:
                return False
            raise
