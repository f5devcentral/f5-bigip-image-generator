"""alibaba_image_name module"""
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

class AlibabaImageName(ImageName):
    """Check if Alibaba name transformation is needed"""

    def __init__(self):
        """Set rules and transformations for alibaba image name"""
        # The name of the user-defined image, [2, 128] English or Chinese characters.
        # It must begin with an uppercase/lowercase letter or a Chinese character,
        # and may contain numbers, _ or -. It cannot begin with http:// or https://.

        min_chars = int(get_config_value('ALIBABA_IMAGE_NAME_LENGTH_MIN'))
        max_chars = int(get_config_value('ALIBABA_IMAGE_NAME_LENGTH_MAX'))
        rules = ImageNameRules(min_chars, max_chars,
                               match_regex=r'^(?!(https://|http://))[a-zA-Z][a-zA-Z0-9\-_]+$')

        transform = ImageNameTransform(disallowed_regex=r'[^a-zA-Z0-9\-_]', replacement_char='-',
                                       to_lower=False)

        super().__init__(rules, transform)
