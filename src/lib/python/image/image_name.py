"""Base image name module"""
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


import random
import re
import string

class ImageNameRules: #pylint: disable=too-few-public-methods
    """Image name rules data class"""
    def __init__(self, min_chars=1, max_chars=128, match_regex='^[a-zA-z0-9-]+$'):
        if not isinstance(min_chars, int):
            raise ValueError('min_chars must be an integer')
        if min_chars <= 0:
            raise ValueError('min_chars must be greater than zero.')
        if not isinstance(max_chars, int):
            raise ValueError('max_chars must be an integer')
        if min_chars > max_chars:
            raise ValueError('min_chars must be less than or equal to max_chars.')
        if match_regex is None or match_regex == '':
            raise ValueError('match_regex is required.')
        try:
            re.compile(match_regex)
        except re.error as exc:
            raise ValueError('match_regex is invalid: {}'.format(str(exc))) from exc

        self.min_chars = min_chars
        self.max_chars = max_chars
        self.match_regex = match_regex

class ImageNameTransform: #pylint: disable=too-few-public-methods
    """Image name transform data class"""
    def __init__(self, disallowed_regex='[^a-zA-Z0-9-]', replacement_char='-',
                 trailing_char_count=10, to_lower=False):
        if disallowed_regex is None or disallowed_regex == '':
            raise ValueError('disallowed_regex is required.')
        try:
            re.compile(disallowed_regex)
        except re.error as exc:
            raise ValueError('disallowed_regex is invalid: {}'.format(str(exc))) from exc
        if replacement_char is None or len(replacement_char) != 1:
            raise ValueError('One replacement_char is required.')
        if trailing_char_count is None or trailing_char_count < 2:
            raise ValueError('At least two trailing characters required.')
        if not isinstance(to_lower, bool):
            raise ValueError('to_lower must be boolean')

        self.disallowed_regex = disallowed_regex
        self.replacement_char = replacement_char
        self.trailing_char_count = trailing_char_count
        self.to_lower = to_lower

class ImageName():
    """Base class for all platform-specific name derivations"""
    def __init__(self, rules, transform=None):
        if rules is None:
            raise ValueError('rules is required.')

        self.rules = rules
        self.transform = transform

    def apply_transform(self, name):
        """Apply transform to the image name"""
        if name is None or name == '':
            raise ValueError('name is required.')
        if self.transform is None:
            raise ValueError('Transform has not been set')

        # Generate random chars (reserve one char for the separator)
        random_chars = ''.join(random.choices(string.ascii_uppercase + string.digits,
                                              k=(self.transform.trailing_char_count-1)))
        name = '{} {}'.format(name, random_chars)
        trailing_char_count = self.transform.trailing_char_count

        # Transform to lower if requested
        if self.transform.to_lower:
            name = name.lower()

        # Replace non-allowed chars with replacement character
        name = re.sub(self.transform.disallowed_regex,
                      self.transform.replacement_char, name)

        # Remove repeated special characters that may have resulted from substitution
        remove_dups_pattern = \
            '(?P<char>[' + re.escape(self.transform.replacement_char) + '])(?P=char)+'
        name = re.sub(remove_dups_pattern, r'\1', name)

        # Determine if random characters can/should be trimmed
        if self.rules.max_chars is not None and len(name) > self.rules.max_chars:
            # Check to see if random postfix can be trimmed
            excess_chars = len(name) - self.rules.max_chars
            if excess_chars > self.transform.trailing_char_count:
                raise ValueError(
                    'Excess {} chars in name exceed length of random postfix {}.'.format(
                        excess_chars, self.transform.trailing_char_count))

            # Trim random number portion (including separator if it would be the
            # only remaining char).
            if excess_chars >= (self.transform.trailing_char_count - 1):
                excess_chars = self.transform.trailing_char_count

            name = name[:-excess_chars]
            trailing_char_count = self.transform.trailing_char_count - excess_chars

        self.check_valid_name(name)

        return (name, trailing_char_count)

    def check_valid_name(self, name):
        """Check if image name is valid"""
        if name is None or name == '':
            raise ValueError('name is required.')

        # Check length
        if self.rules.min_chars is not None and len(name) < self.rules.min_chars:
            raise ValueError('Name {} length {} is less than minimum length {}'.format(
                name, len(name), self.rules.min_chars))

        if self.rules.max_chars is not None and len(name) > self.rules.max_chars:
            raise ValueError('Name {} length {} is greater than maximum length {}'.format(
                name, len(name), self.rules.max_chars))

        # Check characters
        if not bool(re.search(self.rules.match_regex, name)):
            raise ValueError('Found unexpected characters not matching {} in {}'.format(
                self.rules.match_regex, name))
