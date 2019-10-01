"""Cloud image registration handler."""
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


import copy
import json
import requests

from metadata.metadata_util import MetadataConfigFileUtil
from metadata.metadata_filter import MetadataFilter
from util.config import get_config_value
from util.logger import LOGGER
from util.retrier import Retrier

class CloudImageRegister(MetadataFilter):
    """Class used to register image."""
    def __init__(self, metadata):
        if metadata is None:
            raise ValueError('metadata is required.')

        # Initialize registration data
        self.registration_data = None

        # Get platform from build image metadata
        metadata_values = metadata.get()
        if 'build-image' not in metadata_values:
            raise ValueError('build-image not found in metadata')
        if 'platform' not in metadata_values['build-image']:
            raise ValueError('platform not found in build-image metadata')
        platform = metadata_values['build-image']['platform']

        # Create lists of metadata/config files for parent
        context = 'register'
        register_config_files = \
            MetadataConfigFileUtil(metadata.artifacts_dir, context). \
                get_all_config_filenames(['VersionFile'])

        # Init metadata filter with metadata/config files
        MetadataFilter.__init__(self, metadata, register_config_files)
        self.filter(platform)

    @staticmethod
    def get_bundle(metadata):
        """Supports the legacy bundle attribute used to kick off cloud BVTs"""

        # To keep this change localized so that it can be removed later,
        # a metadata dictionary is used as the input rather than separate
        # modules and boot_locations inputs.

        # Check inputs
        if metadata is None:
            raise ValueError('metadata is required.')

        for key in ['modules', 'boot_locations']:
            if key not in metadata:
                raise ValueError('{} attribute missing from metadata'.format(key))
            if metadata[key] is None:
                raise ValueError('{} is required'.format(key))

        # Get attributes once for readability
        modules = metadata['modules']
        boot_locations = metadata['boot_locations']

        # Format the bundle
        if modules == "all":
            return '{}-modules-{}boot-loc'.format(modules, boot_locations)

        return '{}-{}boot-loc'.format(modules, boot_locations)

    def register_image(self, skip_post=False):
        """Register image."""

        # Check for URL
        cir_url = get_config_value('IMAGE_REGISTRATION_URL')
        if (cir_url is None) and (not skip_post):
            LOGGER.trace('IMAGE_REGISTRATION_URL is not defined. Skip image registration.')
            return

        # Format data
        metadata = copy.deepcopy(self.metadata)
        self.registration_data = {}

        # Azure supports both ASM and ARM models.  We are using ARM now.
        if ('platform' in metadata) and (metadata['platform'] == 'azure'):
            metadata['platform'] = 'azurerm'

        # These metadata attributes are used as keys in the registry
        for key in ['platform', 'image_id', 'image_name']:
            # special case mapping for register API platform -> cloud
            if key not in metadata:
                raise ValueError('{} attribute missing from metadata'.format(key))
            if key == 'platform':
                self.registration_data['cloud'] = str(metadata[key])
            else:
                self.registration_data[key] = str(metadata[key])
            del metadata[key]

        # Add bundle attribute to support legacy cloud BVT
        metadata['bundle'] = self.get_bundle(metadata)

        # All other metadata attributes are considered registry attributes
        self.registration_data['attributes'] = json.dumps(metadata, sort_keys=True)

        if skip_post:
            LOGGER.info('skip_post flag is set. Skip image registration.')
            LOGGER.trace('Registration data:%s', self.registration_data)
            return

        # Register image
        self.post_to_url(cir_url)

    def post_to_url(self, cir_url):
        """Post data to URL with retries"""
        def _post_to_url():
            try:
                # Note: Total retry time is timeout (in the requests.post call) + retrier.delay
                LOGGER.debug('Post to URL:%s', cir_url)
                response = requests.post(url=cir_url, data=self.registration_data, timeout=60.0)
                LOGGER.debug('Response: %s:%s', response, response.text)
            except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as exception:
                LOGGER.debug('Caught exception:%s', exception)
                return False
            return True

        retrier = Retrier(_post_to_url)
        retrier.tries = int(get_config_value('IMAGE_REGISTRATION_RETRY_COUNT'))
        retrier.delay = int(get_config_value('IMAGE_REGISTRATION_RETRY_DELAY'))
        LOGGER.info('Attempt to register cloud image.')
        LOGGER.debug('Register cloud image detail: %s', self.registration_data)

        if retrier.execute():
            LOGGER.info('Cloud image was registered')
        else:
            raise RuntimeError('Exhausted all [{}] retries for image registration.'.
                               format(retrier.tries))
