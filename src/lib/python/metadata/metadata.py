"""Metadata base class"""
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


import json
import os

from util.logger import LOGGER
from util.singleton import Singleton

class Metadata(Singleton):
    """Metadata class to load metadata from json files."""

    def __init__(self):
        self.metadata = {}

    def load_files(self, metadata_files):
        """Load metadata from files"""
        LOGGER.debug('Load metadata files...')
        for metadata_file in metadata_files:
            LOGGER.debug('Loading %s...', metadata_file)
            if not os.path.exists(metadata_file):
                raise ValueError('No such file or directory: {}'.format(metadata_file))
            if os.stat(metadata_file).st_size == 0:
                raise ValueError('Empty metadata file: {}'.format(metadata_file))

            with open(metadata_file) as metadata_contents:
                new_metadata = json.load(metadata_contents)
                if 'build_source' not in new_metadata:
                    raise ValueError('build_source field not found in {}'.format(new_metadata))

                # Each build_source can have only one set of metadata
                build_source = new_metadata['build_source']
                if build_source in self.metadata:
                    raise ValueError('Source {} already loaded'.format(build_source))

                # Remove any empty strings
                self.metadata[build_source] = \
                    {k: v for k, v in new_metadata.items() if v != u''}

        LOGGER.trace('metadata:%s', json.dumps(self.metadata, indent=4, sort_keys=True))

    def get(self):
        """Get metadata"""
        return self.metadata

    def set(self, build_source, key, value):
        """Set metadata"""
        if build_source not in self.metadata:
            self.metadata[build_source] = {}
        self.metadata[build_source][key] = value

    def clear(self):
        """Clear metadata"""
        self.metadata = {}

    def __str__(self):
        """Print metadata."""
        return json.dumps(self.metadata, sort_keys=True)
