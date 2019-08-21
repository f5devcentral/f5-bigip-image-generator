"""Common utilities for all other modules and classes"""
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



from util.logger import LOGGER


def is_supported_cloud(cloud_type):
    """Checks if the given cloud is a supported cloud."""
    supported_clouds = ['alibaba', 'aws', 'azure', 'gce']
    return cloud_type in supported_clouds


def ensure_value_from_dict(value_dict, key):
    """Attempts to retrieve a value from a dictionary.  Throws an exception if it's empty."""
    try:
        value = value_dict[key]
    except ValueError:
        LOGGER.error("Unable to retrieve key [%s] from dictionary!", key)
        raise
    if not value:
        error_message = "Dictionary contained an empty value for key [{}]!".format(key)
        LOGGER.error(error_message)
        raise ValueError(error_message)
    return value


def remove_prefix_from_string(prefix, string):
    """Removes a prefix from a string if it exists.  Otherwise returns the unmodified string."""
    if string.startswith(prefix):
        string = string[len(prefix):]
    return string
