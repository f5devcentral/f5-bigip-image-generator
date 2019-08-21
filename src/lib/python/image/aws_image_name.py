"""aws_image_name module"""
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


class AWSImageName(ImageName):
    """
    Contains naming rules and transformations for AWS images

    Official naming rules from EC2 console:
    AMI names must be between 3 and 128 characters long, and may contain letters, numbers, '(',
    ')', '.', '-', '/' and '_'

    Note that we use a tighter restriction on the maximum length than what's officially allowed.
    This is done to provide parity with the other clouds and allow room for additional suffixes
    on top of names which are already close to the current limit.
    """

    def __init__(self):
        """Set rules and transformations to be used later"""
        min_chars = int(get_config_value('AWS_IMAGE_NAME_LENGTH_MIN'))
        max_chars = int(get_config_value('AWS_IMAGE_NAME_LENGTH_MAX'))
        rules = ImageNameRules(min_chars, max_chars, match_regex=r'^[a-zA-Z0-9\(\).\-\/_]+$')
        transform = ImageNameTransform(disallowed_regex=r'[^a-zA-Z0-9\(\).\-\/_]')
        super().__init__(rules, transform)
