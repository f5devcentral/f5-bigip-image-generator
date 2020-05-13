"""Google Image module"""
# Copyright (C) 2019 F5 Networks, Inc
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



from google.oauth2 import service_account
from googleapiclient import discovery
from googleapiclient.errors import HttpError

from image.base_image import BaseImage
from image.google_disk import GoogleDisk
from metadata.cloud_metadata import CloudImageMetadata
from metadata.cloud_tag import CloudImageTags
from util.config import get_config_value
from util.config import get_dict_from_config_json
from util.misc import ensure_value_from_dict
from util.logger import LOGGER
from util.retrier import Retrier


class GoogleImage(BaseImage):
    """
    Google class for all platform specific derivations
    """
    def __init__(self, working_dir, input_disk_path):
        super().__init__(working_dir, input_disk_path)
        self.disk = GoogleDisk(input_disk_path)

        # Retrieve credentials dictionary
        creds_dict = get_dict_from_config_json("GOOGLE_APPLICATION_CREDENTIALS")

        # Obtain project ID from the credentials dictionary
        self.gce_project_id = ensure_value_from_dict(creds_dict, "project_id")
        LOGGER.info("Using project_id: '%s'", self.gce_project_id)

        # Record project ID in metadata
        self.metadata = CloudImageMetadata()
        self.metadata.set(self.__class__.__name__, 'gce_project', self.gce_project_id)

        # Create a service object from the credentials dictionary
        self.gce_credentials = service_account.Credentials.from_service_account_info(creds_dict)
        self.gce_service = discovery.build('compute', 'v1', credentials=self.gce_credentials)

    def clean_up(self):
        """Clean-up cloud objects created by this class and its members."""
        LOGGER.info("Cleaning-up GoogleImage artifacts.")

        if self.disk is not None:
            self.disk.clean_up()
        LOGGER.info("Completed GoogleImage clean-up.")

    def extract_disk(self):
        """Extract disk for upload"""
        BaseImage.extract_disk(self)


    # returns True if image exists, False otherwise
    def image_exists(self, image_name):
        """Check if image already exists in gce"""
        try:
            # pylint: disable=no-member
            request = self.gce_service.images().get(project=self.gce_project_id, image=image_name)
            result = request.execute()
            if not result:
                result = False
            else:
                result = True
        except HttpError as exp:
            if exp.resp.status == 404:
                result = False
            else:
                raise exp
        return result


    def is_image_deleted(self, image_name):
        """Waits for the image to be deleted."""

        retrier = Retrier(lambda s: not self.image_exists(s), image_name)
        retrier.tries = int(get_config_value('GCE_IMAGE_DELETE_COMPLETED_RETRY_COUNT'))
        retrier.delay = int(get_config_value('GCE_IMAGE_DELETE_COMPLETED_RETRY_DELAY'))
        LOGGER.info('Waiting for image [%s] to be deleted.', image_name)
        try:
            if retrier.execute():
                LOGGER.info("Image [%s] was deleted.", image_name)
                return True
            LOGGER.warning("Image [%s] was still not deleted after checking [%d] times!",
                           image_name, retrier.tries)
            return False
        except HttpError as exp:
            LOGGER.exception(exp)
            return False


    # delete the image, then wait for the deletion to complete
    # returns True if deletion was successful or image does not exist, False otherwise
    def delete_image(self, image_name):
        """Delete image from GCE"""
        image_deleted = False
        try:
            # pylint: disable=no-member
            request = self.gce_service.images().delete(project=self.gce_project_id, \
                                                       image=image_name)
            request.execute()
        except HttpError as exp:
            if exp.resp.status == 404:
                LOGGER.info("Image doesn't exist")
                image_deleted = True
            else:
                LOGGER.exception(exp)
                raise exp
            return image_deleted

        return self.is_image_deleted(image_name)


    def insert_image(self, image_name):
        """Create image in GCE and then check for status = READY"""
        bucket_name = get_config_value('GCE_BUCKET')
        image_body = {
            "name": image_name,
            "rawDisk": {
                # In the following line the bucket name along with blob name is required
                "source": "https://storage.googleapis.com/{}/{}".format(
                    bucket_name, self.disk.uploaded_disk_name)
            }
        }
        family_name = get_config_value('GCE_IMAGE_FAMILY_NAME')
        if family_name:
            image_body['family'] = family_name

        try:
            # pylint: disable=no-member
            request = self.gce_service.images().insert(project=self.gce_project_id, body=image_body)
            result = request.execute()
        except HttpError as exp:
            LOGGER.exception(exp)
            raise exp

        if not result:
            return False

        LOGGER.debug("Image creation response: '%s'", result)
        return self.is_image_ready(image_name)


    def is_image_ready(self, image_name):
        """Checks if the given image is ready."""
        def _is_image_ready():
            """Checks if an image with image_name exists and status is READY"""
            # pylint: disable=no-member
            request = self.gce_service.images().get(project=self.gce_project_id,
                                                    image=image_name)
            result = request.execute()
            if not result or result['status'] == 'FAILED':
                raise RuntimeError("Creation of image [{}] failed!".format(image_name))
            return result['status'] == 'READY'

        retrier = Retrier(_is_image_ready)
        retrier.tries = int(get_config_value('GCE_IMAGE_CREATE_COMPLETED_RETRY_COUNT'))
        retrier.delay = int(get_config_value('GCE_IMAGE_CREATE_COMPLETED_RETRY_DELAY'))
        LOGGER.info("Waiting for image [%s] to be ready.", image_name)
        try:
            if retrier.execute():
                LOGGER.info("Image [%s] is ready.", image_name)
                self.metadata.set(self.__class__.__name__, 'image_id', image_name)
                return True
            LOGGER.warning("Image [%s] was still not ready after checking [%d] times!",
                           image_name, retrier.tries)
            return False
        except HttpError as exp:
            LOGGER.exception(exp)
            return False
        except RuntimeError as runtime_exception:
            LOGGER.exception(runtime_exception)
            return False


    def tag_image(self, image_name):
        """Associate image tags with image"""
        LOGGER.info('Set image labels.')

        # Get current labels fingerprint.  To avoid/detect conflicts, you must
        # provide the current label fingerprint (reference) when you request to
        # set image labels.  This fingerprint value is updated whenever labels
        # are updated and the set labels request will fail if the labels were
        # updated out of band.
        try:
            # pylint: disable=no-member
            request = self.gce_service.images().get(project=self.gce_project_id,
                                                    image=image_name)
            result = request.execute()
            label_fingerprint = result['labelFingerprint']
        except HttpError as exp:
            LOGGER.error("Exception setting image labels:")
            LOGGER.exception(exp)
            return False

        if not result:
            return False

        if label_fingerprint is None or label_fingerprint == '':
            LOGGER.info('Label fingerprint was empty.')
            return False

        cloud_image_tags = CloudImageTags(self.metadata)
        cloud_image_tags.transform_values(to_lower=True, disallowed_regex='[^a-z0-9-]')
        image_labels = cloud_image_tags.get()

        set_labels_body = {
            "labels": image_labels,
            "labelFingerprint": label_fingerprint
        }

        try:
            # pylint: disable=no-member
            request = self.gce_service.images().setLabels(project=self.gce_project_id,
                                                          resource=image_name, body=set_labels_body)
            result = request.execute()
        except HttpError as exp:
            LOGGER.error("Exception setting image labels:")
            LOGGER.exception(exp)
            return False

        if not result:
            return False

        LOGGER.debug("Image set labels response: %s", result)
        return True


    def create_image(self, image_name):
        LOGGER.info("Checking if the image '%s' already exists.", image_name)

        # Check if an image with image_name already exists. If so, delete the image
        result = self.image_exists(image_name)
        if not result:
            LOGGER.info("The image '%s' does not exist.", image_name)
        else:
            LOGGER.info("The image '%s' exists.", image_name)
            result = self.delete_image(image_name)
            if not result:
                LOGGER.error("Could not delete the image '%s', exiting.", image_name)
                raise SystemExit(-1)

        LOGGER.info("Attempting to create an image '%s'.", image_name)

        result = self.insert_image(image_name)
        if not result:
            LOGGER.error("The image '%s' was not created successfully.", image_name)
            raise SystemExit(-1)

        result = self.tag_image(image_name)
        if not result:
            LOGGER.error("The image '%s' was not tagged successfully.", image_name)
            raise SystemExit(-1)

        LOGGER.info("Image '%s' creation succeeded.", image_name)
