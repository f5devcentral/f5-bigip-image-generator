"""AWS image module"""
# Copyright (C) 2019-2020 F5 Networks, Inc
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
from boto3 import Session
from botocore.exceptions import ClientError, ParamValidationError

from image.base_image import BaseImage
from image.aws_disk import AWSDisk
from image.aws_snapshot import AWSSnapshot
from metadata.cloud_metadata import CloudImageMetadata
from metadata.cloud_tag import CloudImageTags
from util.config import get_config_value, get_list_from_config_yaml
from util.logger import LOGGER
from util.retrier import Retrier
from util.misc import save_image_id


class AWSImage(BaseImage):
    """Class for handling AWS image related actions"""

    AWS_IMAGE_ROOT_VOLUME = '/dev/xvda'

    def __init__(self, working_dir, input_disk_path):
        super().__init__(working_dir, input_disk_path)
        self.session = Session(
            aws_access_key_id=get_config_value('AWS_ACCESS_KEY_ID'),
            aws_secret_access_key=get_config_value('AWS_SECRET_ACCESS_KEY'),
            region_name=get_config_value('AWS_REGION')
        )

        self.disk = AWSDisk(input_disk_path, working_dir, self.session)

        # Create ec2 client object for performing low-level image actions.
        self.ec2_client = self.session.client('ec2')

        # Record REGION in the metadata.
        self.metadata = CloudImageMetadata()
        self.metadata.set(self.__class__.__name__, 'location', self.session.region_name)
        self.snapshot = None
        self.image_id = None

    def clean_up(self):
        """Clean-up cloud objects created by this class and its members."""
        LOGGER.info("Cleaning-up AWSImage artifacts.")

        # Clean-up the snapshot only if image generation didn't succeed. In case of a
        # successful image generation, the snapshot is associated with the image and
        # stays in-use. Trying to delete it in that case would always fail.
        if self.image_id is None and self.snapshot is not None:
            self.snapshot.clean_up()
        if self.disk is not None:
            self.disk.clean_up()
        LOGGER.info("Completed AWSImage clean-up.")

    def create_image(self, image_name):
        """Create image implementation for AWS"""
        # image name must be unique
        self.delete_old_image(image_name)

        #start image creation
        LOGGER.info('Started creation of image %s at %s', image_name,
                    datetime.datetime.now().strftime('%H:%M:%S'))
        start_time = time()
        try:
            response = self.ec2_client.register_image(
                Architecture="x86_64",
                BlockDeviceMappings=[
                    {
                        "DeviceName": AWSImage.AWS_IMAGE_ROOT_VOLUME,
                        "Ebs":
                        {
                            "DeleteOnTermination": True,
                            "SnapshotId": self.snapshot.snapshot_id,
                            "VolumeType": "gp2"
                        }
                    }
                ],
                EnaSupport=True,
                Description=image_name,
                Name=image_name,
                RootDeviceName=AWSImage.AWS_IMAGE_ROOT_VOLUME,
                SriovNetSupport="simple",
                VirtualizationType="hvm"
                )
        except (ClientError, ParamValidationError) as botocore_exception:
            LOGGER.exception(botocore_exception)
            raise RuntimeError('register_image failed for image\'{}\'!'.format(image_name))

        # get image id
        try:
            LOGGER.trace("register_image() response: %s", response)
            self.image_id = response['ImageId']
        except KeyError as key_error:
            LOGGER.exception(key_error)
            raise RuntimeError('could not find \'ImageId\' key for image {} '.format(image_name) +
                               'in create_image response: {}'.format(response))
        LOGGER.info('Image id: %s', self.image_id)

        # save image id in artifacts dir json file
        save_image_id(self.image_id)

        # wait till the end of the image creation
        self.wait_for_image_availability()
        LOGGER.info('Creation of %s image took %d seconds', self.image_id, time() - start_time)

        LOGGER.info('Tagging %s as the image_id.', self.image_id)
        self.metadata.set(self.__class__.__name__, 'image_id', self.image_id)

        # add tags to the image
        self.create_tags()

    def delete_old_image(self, image_name):
        """ Check if an image with the same name already exists and delete it.
            This is unlikely to happen unless the image name is specified in the configuration."""

        response = self.find_image(image_name)
        num_images = len(response['Images'])
        if num_images not in (0, 1, 2):
            raise RuntimeError('Number of images named {} '.format(image_name) +
                               'expected to be 0 or 1 (maybe 2, due to AWS replicability issues),' +
                               ' but found {}. '.format(num_images) +
                               '(Should have received InvalidAMIName.Duplicate error during ' +
                               'the previous image creation). Please delete them manually.')

        if num_images in (1, 2):
            try:
                first_image_id = response['Images'][0]['ImageId']
                if num_images == 2:
                    second_image_id = response['Images'][1]['ImageId']
            except KeyError as key_error:
                LOGGER.exception(key_error)
                raise RuntimeError('could not find ImageId key for image {} '.format(image_name) +
                                   'in describe_images response: {}'.format(response))

            LOGGER.info('There is an old image %s named %s, deleting it.', first_image_id,
                        image_name)
            self.delete_image(first_image_id)
            if num_images == 2:
                LOGGER.info('There is an old image %s named %s, deleting it.', second_image_id,
                            image_name)
                self.delete_image(second_image_id)

    def find_image(self, image_name):
        """ Find image by name. Return response"""
        try:
            response = self.ec2_client.describe_images(
                Filters=[{'Name': 'name', 'Values':[image_name]}])
        except (ClientError, ParamValidationError) as botocore_exception:
            LOGGER.exception(botocore_exception)
            raise RuntimeError('describe_images failed for image \'{}\' !'.format(image_name))
        LOGGER.trace('describe_images response for image %s: %s', image_name, response)
        return response

    def delete_image(self, image_id):
        """ Delete image by image id. Return response"""
        try:
            self.ec2_client.deregister_image(ImageId=image_id)
        except (ClientError, ParamValidationError) as botocore_exception:
            LOGGER.exception(botocore_exception)
            raise RuntimeError('deregister_image failed for image \'{}\' !'.format(image_id))

    def wait_for_image_availability(self):
        """ Wait for image to be created and available """
        def _wait_for_image_availability():
            """Awaits the describe_images() to successfully acknowledge availability
            of the given image."""
            try:
                response = self.ec2_client.describe_images(ImageIds=[self.image_id])
            except (ClientError, ParamValidationError) as botocore_exception:
                LOGGER.exception(botocore_exception)
                raise RuntimeError('EC2.Client.describe_images() failed for {} !'.
                                   format(self.image_id))
            if not response:
                raise RuntimeError('EC2.Client.describe_images() returned none response!')
            try:
                if response['Images'][0]['State'] == 'available':
                    return True
                return False
            except (KeyError, IndexError) as image_describe_exception:
                LOGGER.exception(image_describe_exception)
                raise RuntimeError('EC2.Client.describe_images() did not have ' +
                                   '[\'Images\'][0][\'State\'] in its response: response \'{}\''.
                                   format(response))

        retrier = Retrier(_wait_for_image_availability)
        retrier.tries = int(get_config_value('AWS_CREATE_IMAGE_RETRY_COUNT'))
        retrier.delay = int(get_config_value('AWS_CREATE_IMAGE_RETRY_DELAY'))
        LOGGER.info('Waiting for the image %s to become available.', self.image_id)

        if retrier.execute():
            LOGGER.info('Image [%s] is created in AWS.', self.image_id)
        else:
            raise RuntimeError('Exhausted all \'{}\' retries for image {} to become available.'.
                               format(self.image_id, retrier.tries))

    def get_image_tag_metadata(self):
        """Returns associated image metadata tags through the member variable metadata."""
        metadata_tags = CloudImageTags(self.metadata)
        return metadata_tags.get()

    def create_tags(self):
        """ Create tags for image. Tags are fetched from metadata. """
        image_tags = self.get_image_tag_metadata()
        tags_to_add = []
        for tag in image_tags:
            tags_to_add.append({'Key': tag, 'Value': image_tags[tag]})

        try:
            response = self.ec2_client.create_tags(Resources=[self.image_id], Tags=tags_to_add)
        except (ClientError, ParamValidationError) as botocore_exception:
            LOGGER.exception(botocore_exception)
            raise RuntimeError('create_tags failed for image\'{}\'!\n'.format(self.image_id))
        LOGGER.trace('create_tags response for image %s: %s', self.image_id, response)

    def prep_disk(self):
        """Performs the leg work to convert the S3 Disk represented by self.disk into
        a snapshot from which an AWSImage can be created."""
        LOGGER.info("Prepare the uploaded s3 disk for image generation.")

        # Convert the s3Disk into an AWS Snapshot.
        self.snapshot = AWSSnapshot(self.ec2_client, self.disk.bucket_name,
                                    self.disk.uploaded_disk_name)
        self.snapshot.create_snapshot()
        LOGGER.info("AWS Disk preparation is complete for image creation.")

    def share_image(self):
        """Reads a list of AWS accounts and shares the AMI with each of those accounts."""
        share_account_ids = get_list_from_config_yaml('AWS_IMAGE_SHARE_ACCOUNT_IDS')
        if share_account_ids:
            LOGGER.info("Share the AMI with multiple AWS accounts.")
            for dest_account_id in share_account_ids:
                try:
                    LOGGER.info('Sharing image with account-id: %s', dest_account_id)

                    # Share the image with the destination account
                    response = self.ec2_client.modify_image_attribute(
                        ImageId=self.image_id,
                        Attribute='launchPermission',
                        OperationType='add',
                        UserIds=[str(dest_account_id)]
                    )
                    LOGGER.trace("image.modify_attribute response => %s", response)
                except ClientError as client_error:
                    LOGGER.exception(client_error)
                    # Log the error around malformed Account-id and move on.
                    if client_error.response['Error']['Code'] == 'InvalidAMIAttributeItemValue':
                        LOGGER.error('Malformed account-id: %s', dest_account_id)
                    else:
                        # Any other type of error can be irrecoverable and might
                        # point to a deeper malaise.
                        raise RuntimeError('aws IMAGE was not shared with other accounts')

            # Acknowledge all the account-ids that the image was shared with.
            self.is_share_image_succeeded(share_account_ids)
        else:
            LOGGER.info("No account IDs found for sharing AMI")

    def is_share_image_succeeded(self, share_account_ids):
        """Helper utility for share_image() that goes through the list of share_account_ids
        and confirms that the image was shared with all accounts. The function logs any
        error during its execution without propagating it up."""
        try:
            LOGGER.info("Checking which accounts were added for sharing this AMI")
            image_launch_perms = self.ec2_client.describe_image_attribute(
                ImageId=self.image_id,
                Attribute='launchPermission',
                DryRun=False
            )
            LOGGER.trace("image.describe_attribute() response => %s", image_launch_perms)
        except ClientError as client_error:
            # Simply log the exception without propagating it.
            LOGGER.exception(client_error)
            return False

        # Create a list of account IDs that has launch permission
        launch_permission_accounts = []
        for each in image_launch_perms['LaunchPermissions']:
            launch_permission_accounts.append(each['UserId'])

        counter = 0
        # Check which accounts were added for sharing this AMI
        for account_id in share_account_ids:
            if str(account_id) in launch_permission_accounts:
                LOGGER.info("The AMI was successfully shared with account: %s", account_id)
                counter += 1
            else:
                LOGGER.warning("The AMI was not shared with account: %s", account_id)

        # Confirm that the number of accounts in share_account_ids and image's
        # 'LaunchPermissions' are matching.
        return counter == len(share_account_ids)
