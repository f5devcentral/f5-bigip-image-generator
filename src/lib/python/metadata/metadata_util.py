"""Image metadata file utilities."""
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


import os
import yaml

from util.logger import LOGGER

def get_metadata_config_dir(base_dir=None):
    """Get config directory using a reference directory"""
    if not os.path.isdir(base_dir):
        raise ValueError('Missing directory: {}'.format(base_dir))

    config_dir = '{}/resource/metadata'.format(base_dir)
    if not os.path.isdir(config_dir):
        raise ValueError('Missing directory: {}'.format(config_dir))

    return config_dir


class MetadataConfigFileUtil():
    """Metdata config filename helper"""
    def __init__(self, artifacts_dir, context):
        """Initialize based on file location and identifiers"""
        config_dir = get_metadata_config_dir(artifacts_dir)

        self.config_dir = config_dir
        self.context = context

    def get_mapped_filename(self):
        """Get context-based config filename (encoded in filename)"""
        return '{}/image_{}.yml'.format(self.config_dir, self.context)

    def get_filename(self, source):
        """Get config filename for a source (encoded in filename)"""
        return '{}/{}.yml'.format(self.config_dir, source)

    def get_all_config_filenames(self, sources):
        """Get all config filenames for a platform and a list of sources."""
        all_config_filenames = []

        # base context config
        all_config_filenames.append(self.get_mapped_filename())

        # extra sources
        for source in sources:
            config_filename = self.get_filename(source)
            all_config_filenames.append(config_filename)

        return all_config_filenames


class MetadataFileUtil():
    """Metadata filename helper"""

    def __init__(self, artifacts_dir):
        """Initialize based on file location"""
        if not os.path.isdir(artifacts_dir):
            raise ValueError('Missing directory: {}'.format(artifacts_dir))

        self.artifacts_dir = artifacts_dir

    def get_filename(self, source):
        """Get metadata filename for a source (encoded in filename)"""
        return '{}/{}.json'.format(self.artifacts_dir, source)

    def get_all_metadata_filenames(self):
        """Get all metadata filenames from config file"""
        all_metadata_filenames = []

        config_dir = get_metadata_config_dir(self.artifacts_dir)
        metadata_source_file = '{}/build_sources.yml'.format(config_dir)
        if not os.path.isfile(metadata_source_file):
            raise ValueError('Missing file: {}'.format(metadata_source_file))

        with open(metadata_source_file) as metadata_sources:
            sources = yaml.safe_load(metadata_sources)['build_sources']

            if sources is None:
                LOGGER.debug('No sources to append to file list')
            else:
                for source in sources:
                    metadata_filename = self.get_filename(source)
                    all_metadata_filenames.append(metadata_filename)

        return all_metadata_filenames
