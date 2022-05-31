"""Base Image module"""
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


from image.base_disk import BaseDisk

class BaseImage():
    """
    Base class for all platform specific derivations
    """
    def __init__(self, working_dir, input_disk_path):
        self.working_dir = working_dir
        self.disk = BaseDisk(input_disk_path, working_dir)

        self.cloud_disk_url = None
        self.prepared_image_names = []
        self.created_objects = []

    def clean_up(self):
        """Walk through objects created in the cloud and clean
           them up if the clean up flag is True.
        """
        raise NotImplementedError("clean_up() unimplemented.")

    def extract_disk(self):
        """Extract disk for upload"""
        self.disk.extract()

    def set_uploaded_disk_name(self, uploaded_disk_name):
        """Set the name of the uploaded disk name"""
        self.disk.set_uploaded_disk_name(uploaded_disk_name)

    def update_image_name(self):
        """Validate and fix up image name"""

    def upload_disk(self):
        """Upload the disk to cloud"""
        self.disk.upload()

    def prep_disk(self):
        """Perform any processing needed for disk"""

    def create_image(self, image_name):
        """Create cloud image"""

    def copy_image(self):
        """Make image copy"""

    def share_image(self):
        """Share image with other accounts"""

    def get_prepared_image_names(self):
        """Get list of prepared images"""
        return self.prepared_image_names

    def create_metadata(self):
        """Create metadata file"""

    def dry_run(self):
        """Perform environment checks"""
