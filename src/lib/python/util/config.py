"""Module containing functionality for the config system.  The config system is currently
initialized by BASH code, so there's not much to do here.  If/when we migrate the config system to
Python we'll expand this module into a full class."""
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
import json

import yaml
from yaml import YAMLError

from util.logger import LOGGER


# pylint: disable=pointless-string-statement
def get_config_accepted(key):
    """Look up accepted regular expressions which were configured during program startup."""

    key = key.upper().replace('-', '_')

    """
    # Ensure that the config system has been initialized first.
    initialized = os.getenv('CONFIG_SYSTEM_INITIALIZED')
    if not initialized:
        script_dir = os.path.realpath(os.path.dirname(__file__))
        init_config_path = script_dir + '/../../../bin/init_config'
        subprocess.call(init_config_path, shell=True)
    """

    # Look up the accepted regex for the desired key by using the config system prefix.
    env_prefix = os.getenv('ENVIRONMENT_VARIABLE_PREFIX') or ''
    accepted_prefix = "ACCEPTED_"
    return os.getenv(env_prefix + accepted_prefix + key)


# pylint: disable=pointless-string-statement
def get_config_value(key):
    """Look up values which were configured during program startup."""

    key = key.upper().replace('-', '_')

    """
    # Ensure that the config system has been initialized first.
    initialized = os.getenv('CONFIG_SYSTEM_INITIALIZED')
    if not initialized:
        script_dir = os.path.realpath(os.path.dirname(__file__))
        init_config_path = script_dir + '/../../../bin/init_config'
        subprocess.call(init_config_path, shell=True)
    """

    # Look up the value for the desired key by using the config system prefix.
    prefix = os.getenv('ENVIRONMENT_VARIABLE_PREFIX') or ''
    return os.getenv(prefix + key)

# pylint: disable=pointless-string-statement
def set_config_value(key, value):
    """Set a config key by prefixing it with a predefined value"""

    key = key.upper().replace('-', '_')

    """
    # Ensure that the config system has been initialized first.
    initialized = os.getenv('CONFIG_SYSTEM_INITIALIZED')
    if not initialized:
        script_dir = os.path.realpath(os.path.dirname(__file__))
        init_config_path = script_dir + '/../../../bin/init_config'
        subprocess.call(init_config_path, shell=True)
    """

    # Look up the value for the desired key by using the config system prefix.
    prefix = os.getenv('ENVIRONMENT_VARIABLE_PREFIX') or ''
    env_key = prefix + key
    if value is None:
        if env_key in os.environ:
            del os.environ[env_key]
    else:
        os.environ[env_key] = value


def get_dict_from_config_json(key):
    """Retrieves a value from the config system and returns its JSON file or JSON string contents
    as a dictionary."""

    # Retrieve string value for key
    value_string = get_config_value(key)
    if not value_string:
        error_message = "Value for key [{}] is missing.  Unable to proceed!".format(key)
        LOGGER.error(error_message)
        raise ValueError(error_message)

    # Convert JSON file or JSON string to a dictionary
    if value_string.endswith('.json'):
        try:
            with open(value_string, "r") as value_file:
                value_dict = json.load(value_file)
        except ValueError:
            LOGGER.error("Unable to parse JSON from file [%s]!", value_string)
            raise
    else:
        try:
            value_dict = json.loads(value_string)
        except ValueError:
            LOGGER.error("Unable to parse JSON from string [%s]!", value_string)
            raise

    # Return the dictionary
    return value_dict


def get_list_from_config_yaml(key):
    """Retrieves a value from the config system and returns its YAML file or JSON string contents
    as a list.
    Returns an empty list for an empty YAML content."""

    # Retrieve string value for key
    value_string = get_config_value(key)
    if not value_string:
        return []

    # Convert YAML file or JSON string to a list
    if value_string.endswith('.yml') or value_string.endswith('.yaml'):
        try:
            with open(value_string, "r") as value_file:
                value_list = yaml.safe_load(value_file)
        except YAMLError:
            LOGGER.error("Unable to parse YAML from file [%s]!", value_string)
            raise
    else:
        try:
            value_list = json.loads(value_string)
        except ValueError:
            LOGGER.error("Unable to parse JSON from string [%s]!", value_string)
            raise

    # Return the list
    return value_list
