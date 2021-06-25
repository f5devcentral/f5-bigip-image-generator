"""Image metadata filter"""
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


import copy
import json
import os
import re
import yaml

from util.logger import LOGGER

class MetadataFilter():
    """Image metadata filter."""

    def __init__(self, metadata, config_files):
        if config_files is None:
            raise ValueError('config_files is required.')
        if metadata is None:
            raise ValueError('metadata is required.')

        self.all_metadata = metadata.get()
        self.config_files = config_files

        # Filtered metadata
        self.metadata = None

        # Config attribute keys from input files
        self.config_attribute_keys = None

    def __load_config_attribute_keys(self, platform=None):
        """Load config attributes"""
        # Load attributes to include in metadata
        LOGGER.debug('Load config files.')

        # Always use 'all' and add optional platform
        self.config_attribute_keys = {}
        platforms = ['all']
        if platform is not None:
            platforms.append(platform)

        # Load config files
        for config_file in self.config_files:
            LOGGER.debug('Loading %s...', config_file)

            # Check for empty file
            if os.stat(config_file).st_size == 0:
                raise ValueError('Empty config file: {}'.format(config_file))

            with open(config_file) as config:
                new_config = yaml.safe_load(config)

                # Get build sources for all platforms
                for config_platform in platforms:
                    # If config file has platform def, add build sources
                    if config_platform in new_config:
                        for build_source in new_config[config_platform]:
                            # Create empty list before adding attribute keys
                            if build_source not in self.config_attribute_keys:
                                self.config_attribute_keys[build_source] = []
                            self.config_attribute_keys[build_source] += \
                                new_config[config_platform][build_source]

            # Attributes must be unique.  Check if attributes already exist for any source
            check_keys = []
            for build_source in list(self.config_attribute_keys.keys()):
                for attribute in self.config_attribute_keys[build_source]:
                    if attribute not in check_keys:
                        check_keys.append(attribute)
                    else:
                        raise ValueError(
                            'Duplicate attribute {} found in config'.format(attribute))
        LOGGER.trace('config_attribute_keys:%s', self.config_attribute_keys)

    def filter(self, platform=None):
        """Filter metadata using config files."""
        self.__load_config_attribute_keys(platform)

        # Build metadata by walking config data and grabbing appropriate metadata
        self.metadata = {}
        LOGGER.debug('Filter metadata using config attribute keys')
        for source_key, source_attribute_keys in self.config_attribute_keys.items():
            LOGGER.debug('Add attributes for source %s', source_key)
            if source_key not in self.all_metadata:
                raise ValueError('Metadata source_key:{} not found'.format(source_key))

            for attribute_key in source_attribute_keys:
                LOGGER.trace('  Add attribute for key %s:%s', source_key, attribute_key)
                if attribute_key not in self.all_metadata[source_key]:
                    raise ValueError('Metadata for key {}:{} not found'.format(
                        source_key, attribute_key))
                self.metadata[attribute_key] = self.all_metadata[source_key][attribute_key]

        LOGGER.trace('metadata:%s', json.dumps(self.metadata, indent=4, sort_keys=True))

    def title_case_keys(self):
        """Transform keys to TitleCase. Note if words in a key aren't properly
           TitleCased or broken up, this won't fix that (e.g. version_jobid is
           transformed to VersionJobid rather than VersionJobId)."""
        LOGGER.debug('Transform keys to TitleCase')

        # Use a copy to avoid changing the data structure that is being iterated over
        metadata = copy.deepcopy(self.metadata)

        for key in metadata:
            # Replace non-alphanumeric with spaces to prepare to capitalize first char of each word
            new_key = ''.join(c if c.isalnum() else ' ' for c in key)

            # Capitalize first char of each word
            new_key = ''.join(word.title() for word in new_key.split())

            # Replace existing key with TitleCase key
            LOGGER.trace('Tranform key %s to %s', key, new_key)
            self.metadata[new_key] = self.metadata.pop(key)

        LOGGER.trace('metadata:%s', json.dumps(self.metadata, indent=4, sort_keys=True))

    def transform_values(self, to_lower=False,
                         disallowed_regex='[^a-zA-Z0-9-]', replacement_char='-'):
        """Transform data values"""
        LOGGER.debug('Transform metadata values')

        if disallowed_regex is not None and disallowed_regex != '':
            try:
                re.compile(disallowed_regex)
            except re.error as exc:
                raise ValueError('disallowed_regex is invalid: {}'.format(str(exc))) from exc

            if replacement_char is None or replacement_char == '':
                raise ValueError('Replacement character is required for disallowed_regex')

        for key, val in self.metadata.items():
            # convert values to lower as requested
            if to_lower:
                val = val.lower()

            # substitute replacement character as requested
            if disallowed_regex is not None and disallowed_regex != '':
                val = re.sub(disallowed_regex, replacement_char, val)

            self.metadata[key] = val

        LOGGER.trace('metadata:%s', json.dumps(self.metadata, indent=4, sort_keys=True))

    def get(self):
        """Get metadata"""
        return self.metadata

    def __str__(self):
        """Print metadata."""
        return json.dumps(self.metadata, sort_keys=True)
