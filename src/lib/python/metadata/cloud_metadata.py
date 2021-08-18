"""Image Metadata"""
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


import os

from metadata.metadata import Metadata
from metadata.metadata_util import MetadataFileUtil
from util.logger import LOGGER

class CloudImageMetadata(Metadata):
    """Image Metadata"""

    def __init__(self):
        self.artifacts_dir = None
        super().__init__()

    def load_artifact_files(self, artifacts_dir):
        """Load files from the artifacts directory"""
        if not os.path.isdir(artifacts_dir):
            raise ValueError('Missing directory: {}'.format(artifacts_dir))

        self.artifacts_dir = artifacts_dir

        metadata_files = MetadataFileUtil(artifacts_dir).get_all_metadata_filenames()
        if metadata_files:
            super().load_files(metadata_files)
        else:
            LOGGER.debug('No metadata files to load')
