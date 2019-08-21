"""Google image name"""
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

class GoogleImageName(ImageName):
    """Google image name"""
    def __init__(self):
        # 1-63 chars.  First char is lower alpha, middle chars lower alpha, number,
        # or dash.  Last char is lower alpha or number (no dash).  One character
        # is acceptable.
        min_chars = int(get_config_value('GCE_IMAGE_NAME_LENGTH_MIN'))
        max_chars = int(get_config_value('GCE_IMAGE_NAME_LENGTH_MAX'))
        rules = ImageNameRules(min_chars, max_chars,
                               match_regex='^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$')

        # Use default replacement char ('-') and padding (10 chars)
        transform = ImageNameTransform(disallowed_regex='[^a-z0-9-]',
                                       to_lower=True)

        super().__init__(rules, transform)
