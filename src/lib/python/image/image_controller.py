#!/usr/bin/env python3
"""Prepare Cloud Image"""
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


import json
import os
import shutil
import tempfile
import time

from datetime import timedelta

from metadata.cloud_metadata import CloudImageMetadata
from metadata.cloud_register import CloudImageRegister
from util.logger import LOGGER


class ImageController(): # pylint: disable=too-many-instance-attributes
    """Controller to prepare cloud image"""

    def __init__(self, artifacts_dir, cloud_type, image_disk_path, should_clean=True):
        self.start_time = time.time()
        self.artifacts_dir = artifacts_dir
        self.cloud_type = cloud_type
        self.image_name = None
        self.image_disk_path = image_disk_path
        self.metadata = None
        self.status = 'failure'
        self.transformed_image_name = None
        self.working_dir = None
        self.should_clean = should_clean
        self.cloud_image = None

        if not os.path.isdir(artifacts_dir):
            raise ValueError("Missing or invalid artifacts directory '{}'.".format(artifacts_dir))
        if not os.path.isfile(image_disk_path):
            raise ValueError("Missing image disk '{}'.".format(image_disk_path))

        # Create a working directory under the artifacts dir to temporarily store
        # various build constructs and files.
        self.create_working_dir(artifacts_dir)

        try:
            # Factory (could be a separate object)
            # pylint: disable=import-outside-toplevel
            if cloud_type == 'alibaba':
                from image.alibaba_image import AlibabaImage
                self.cloud_image = AlibabaImage(self.working_dir, self.image_disk_path)
            elif cloud_type == 'aws':
                from image.aws_image import AWSImage
                self.cloud_image = AWSImage(self.working_dir, self.image_disk_path)
            elif cloud_type == 'azure':
                from image.azure_image import AzureImage
                self.cloud_image = AzureImage(self.working_dir, self.image_disk_path)
            elif cloud_type == 'gce':
                from image.google_image import GoogleImage
                self.cloud_image = GoogleImage(self.working_dir, self.image_disk_path)
            else:
                raise ValueError('Unexpected cloud type: {}'.format(cloud_type))
            # pylint: enable=import-outside-toplevel
            self.cloud_image_name = self.image_name_factory(cloud_type)
        except BaseException as base_exception:
            LOGGER.exception(base_exception)
            raise base_exception

    def clean_up(self):
        """Cleans-up the cloud and local artifacts created by this object."""
        try:
            if self.should_clean is True:
                if self.cloud_image is not None:
                    LOGGER.info("Cleaning up image controller constructs.")
                    self.cloud_image.clean_up()
                    self.cloud_image = None
                if self.working_dir is not None and os.path.isdir(self.working_dir):
                    LOGGER.debug("Removing working dir '%s'.", self.working_dir)
                    shutil.rmtree(self.working_dir)
                    self.working_dir = None
            else:
                LOGGER.debug("Skipping removal of working dir '%s'.", self.working_dir)
        except OSError as os_exception:
            # Simply log the exception without propagating.
            LOGGER.error(os_exception)

    @staticmethod
    def image_name_factory(cloud_type):
        """Factory pattern for ImageName"""
        # pylint: disable=import-outside-toplevel
        if cloud_type == 'alibaba':
            from image.alibaba_image_name import AlibabaImageName
            return AlibabaImageName()
        if cloud_type == 'aws':
            from image.aws_image_name import AWSImageName
            return AWSImageName()
        if cloud_type == 'azure':
            from image.azure_image_name import AzureImageName
            return AzureImageName()
        if cloud_type == 'gce':
            from image.google_image_name import GoogleImageName
            return GoogleImageName()
        raise ValueError('Unexpected cloud type: {}'.format(cloud_type))
        # pylint: enable=import-outside-toplevel

    @staticmethod
    def check_valid_name(cloud_type, user_image_name):
        """Check if user-supplied image name is valid"""
        cloud_image_name = ImageController.image_name_factory(cloud_type)
        cloud_image_name.check_valid_name(user_image_name)

    def set_image_name(self, seed_image_name='', user_image_name=''):
        """Set/Transform image name"""
        if user_image_name != '':
            user_image_name = user_image_name.strip()
            self.cloud_image_name.check_valid_name(user_image_name)
            self.image_name = user_image_name
        else:
            if seed_image_name == '':
                raise ValueError('seed_image_name or user_image_name is required')
            self.image_name = \
                self.cloud_image_name.apply_transform(seed_image_name.strip())[0]

    def initialize_image_metadata(self, artifacts_dir, pipeline_build=False):
        """Initialize image metadata"""
        self.metadata = CloudImageMetadata()
        self.metadata.load_artifact_files(artifacts_dir)

        # Set common metadata values
        self.metadata.set(self.__class__.__name__, 'input', self.image_disk_path)
        self.metadata.set(self.__class__.__name__, 'image_name', self.image_name)
        if pipeline_build is True:
            self.metadata.set(self.__class__.__name__, 'build_type', 'pipeline')
        else:
            self.metadata.set(self.__class__.__name__, 'build_type', 'local')

        # License model is currently hardwired
        self.metadata.set(self.__class__.__name__, 'license_model', 'byol')

    def prepare(self, seed_image_name='', user_image_name=''):
        """Main controller"""
        try:
            self.set_image_name(seed_image_name, user_image_name)
            LOGGER.info("Starting prepare cloud image '%s'.", self.image_name)
            self.cloud_image.set_uploaded_disk_name(self.image_name)

            pipeline_build = os.getenv('CI') is not None
            self.initialize_image_metadata(self.artifacts_dir, pipeline_build)

            self.cloud_image.extract_disk()
            self.cloud_image.upload_disk()
            self.cloud_image.prep_disk()

            self.metadata.set(self.__class__.__name__, 'build_operation', 'create')
            self.cloud_image.create_image(self.image_name)
            build_time = time.time() - self.start_time
            self.metadata.set(self.__class__.__name__, 'build_time',
                              str(timedelta(seconds=build_time)))
            self.status = 'success'
            self.metadata.set(self.__class__.__name__, 'status', self.status)

            self.cloud_image.share_image()
            self.create_metadata()
            self.register_image()
            self.create_report()
            LOGGER.info("Finished prepare cloud image '%s'.", self.image_name)

        except BaseException as base_exception:
            LOGGER.exception(base_exception)
            raise base_exception

    def create_working_dir(self, artifacts_dir):
        """Create temporary directory"""
        self.working_dir = tempfile.mkdtemp('', "image_" + self.cloud_type + "_",
                                            artifacts_dir)
        LOGGER.debug("Working directory = '%s'.", self.working_dir)

    def register_image(self):
        """Register image with CIR"""
        CloudImageRegister(self.metadata).register_image()

    def create_metadata(self):
        """Create metadata file"""
        # initialize input/output
        input_metadata = self.metadata.get()
        output_metadata = {'status': self.status}

        # Place metadata from self and cloud image class in output metadata
        build_sources = [self.__class__.__name__, self.cloud_image.__class__.__name__]
        for build_source in build_sources:
            if build_source in input_metadata:
                output_metadata.update(input_metadata[build_source])

        # Write metadata file
        metadata_file = '{}/prepare_cloud_image.json'.format(self.artifacts_dir)
        with open(metadata_file, 'w') as metadata_fp:
            json.dump(output_metadata, metadata_fp, indent=4, sort_keys=True)

    def create_report(self):
        """Create report of created images"""

    def dry_run(self):
        """Perform environment checks"""
        self.cloud_image.dry_run()
