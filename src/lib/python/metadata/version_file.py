"""Version file handler

   Creates version file metadata file and config file from version file in product ISO."""
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
import os
import time
import yaml

from metadata.metadata_util import get_metadata_config_dir
from util.logger import LOGGER

class VersionFile():
    """Version file handler"""

    def __init__(self, version_file, artifacts_dir=None):
        self.start_time = time.time()

        # Get config/metadata dirs
        self.artifacts_dir = artifacts_dir
        self.config_dir = get_metadata_config_dir(artifacts_dir)

        self.version = {}
        self.version_file = version_file

    def load(self):
        """Load version file into a dictionary adding version_ to each attribute"""
        with open(self.version_file) as version:
            for line in version:
                (key, val) = line.split(': ')
                key = 'version_' + key.lower()
                val = val.rstrip('\n')
                self.version[key] = val

        LOGGER.debug('formatted version data:%s',
                     json.dumps(self.version, indent=4, sort_keys=True))

    def create_metadata(self):
        """Create version metadata file"""

        # Add information about how this was built to attributes
        version_metadata = copy.deepcopy(self.version)
        version_metadata['build_source'] = self.__class__.__name__

        # Create metadata dir if needed
        if not os.path.exists(self.artifacts_dir):
            os.makedirs(self.artifacts_dir)

        # Create version metadata file
        metadata_file = '{}/{}.json'.format(self.artifacts_dir, self.__class__.__name__)
        LOGGER.debug('Create metadata file:%s', metadata_file)
        with open(metadata_file, 'w') as version:
            LOGGER.debug('version_metadata:%s',
                         json.dumps(version_metadata, indent=4, sort_keys=True))
            json.dump(version_metadata, version, indent=4, sort_keys=True)

    def create_config(self):
        """Create version config file"""
        version_config = {}
        version_config['all'] = {}
        version_config['all'][self.__class__.__name__] = list(self.version.keys())

        # Create config dir if needed
        if not os.path.exists(self.config_dir):
            os.makedirs(self.config_dir)

        # Create version config file
        config_file = '{}/{}.yml'.format(self.config_dir, self.__class__.__name__)
        LOGGER.debug('Create config file:%s', config_file)
        with open(config_file, 'w') as version:
            LOGGER.debug('version_config:%s', version_config)
            yaml.dump(version_config, version, default_flow_style=False)
