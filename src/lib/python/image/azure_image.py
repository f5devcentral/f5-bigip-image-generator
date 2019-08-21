"""Azure Image module"""
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



from image.azure_disk import AzureDisk
from image.base_image import BaseImage

class AzureImage(BaseImage):
    """
    Upload F5 BIG-IP VE image to provided Azure Storage Account
    """
    def __init__(self, working_dir, input_disk_path):
        super().__init__(working_dir, input_disk_path)
        self.disk = AzureDisk(input_disk_path, working_dir)

    def clean_up(self):
        """clean-up"""
