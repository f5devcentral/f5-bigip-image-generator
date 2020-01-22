"""Azure image name"""
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


from image.image_name import ImageName
from image.image_name import ImageNameRules
from image.image_name import ImageNameTransform
from util.config import get_config_value

class AzureImageName(ImageName):
    """Azure image name"""
    def __init__(self):

        # Valid Length = 1 to 80 characters(Tested in Azure Portal and is allowed)
        # alphanumeric characters - 0-9a-zA-Z
        # The name must begin with a letter or number, end with a letter, number or
        # underscore, and may contain only letters, numbers, underscores, periods, or hyphens.

        min_chars = int(get_config_value('AZURE_IMAGE_NAME_LENGTH_MIN'))
        max_chars = int(get_config_value('AZURE_IMAGE_NAME_LENGTH_MAX'))

        rules = ImageNameRules(min_chars, max_chars,
                               match_regex= \
                                   r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.\_]{0,78}[a-zA-Z0-9\_])?$')
        # Use default replacement char ('-') and padding (10 chars)
        transform = ImageNameTransform(disallowed_regex=r'[^a-zA-Z0-9\-\.\_]',
                                       to_lower=False)
        super().__init__(rules, transform)
