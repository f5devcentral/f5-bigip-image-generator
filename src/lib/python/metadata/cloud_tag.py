"""Cloud image tagging handler."""
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
import re

from metadata.metadata_util import MetadataConfigFileUtil
from metadata.metadata_filter import MetadataFilter
from util.config import get_list_from_config_yaml
from util.logger import LOGGER

class CloudImageTags(MetadataFilter):
    """Class used to generate image tags"""

    def __init__(self, metadata):
        # Create list of metadata config files for parent
        if metadata is None:
            raise ValueError('metadata is required.')

        context = 'tag'
        tag_config_files = MetadataConfigFileUtil(metadata.artifacts_dir, context). \
            get_all_config_filenames(['VersionFile'])

        # Init metadata with metadata/config files
        MetadataFilter.__init__(self, metadata, tag_config_files)
        self.filter()

        # Add user defined tags to the config/metadata
        user_tags = get_list_from_config_yaml('IMAGE_TAGS')
        for user_tag in user_tags:
            for key, value in user_tag.items():
                self.metadata[key] = value

        # Remove tags user requested to exclude
        user_exclude_tags = get_list_from_config_yaml('IMAGE_TAGS_EXCLUDE')
        for key in user_exclude_tags:
            if key in self.metadata:
                del self.metadata[key]
                LOGGER.info('Excluded key [%s] from image tags.', key)
            else:
                LOGGER.info('Key [%s] does not exist in image tags and cannot be excluded.', key)


    def format(self, pair_separator=',', kv_separator='=', label_kv=False, sub_chars=None):
        """Format metadata to be posted to cloud environment.

        Format:
            <key1><kv_separator><value1><pair_separator><key2><kv_separator><value2>
        """

        metadata = copy.deepcopy(self.metadata)

        # Replace value spaces with dashes
        for key in metadata.keys():
            metadata[key] = metadata[key].lower().replace(' ', '-')

            if sub_chars is not None and sub_chars != '':
                metadata[key] = re.sub(sub_chars, '_', metadata[key])

        # Label 'Key=key,Value=value' if requested
        if label_kv:
            label_kv_metadata = copy.deepcopy(metadata)
            metadata = {}
            for key in label_kv_metadata.keys():
                new_key = 'Key={}'.format(key)
                new_val = 'Value={}'.format(label_kv_metadata[key])
                metadata[new_key] = new_val

        # Generate the string and strip the JSON decorators
        tags = json.dumps(metadata, separators=(pair_separator, kv_separator), sort_keys=True)
        tags = tags[1:-1]
        tags = tags.replace('"', '')
        return tags
