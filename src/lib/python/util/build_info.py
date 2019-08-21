"""BuildInfo module"""
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


from subprocess import CalledProcessError, check_output, STDOUT

import json
import re
from os.path import dirname
from pathlib import Path
import distro as distro_info

from util.logger import LOGGER


class BuildInfo:
    """Class for capturing information about the environment where images are being built"""

    # Data structure containing distro-specific commands and regex filters to pass to inner function
    package_manager_commands = {
        # 'yum list installed' output example: 'zlib.x86_64    1.2.7-18.el7    @anaconda'
        "centos": ("yum list installed", r"(^.*?)\s(.*?)\s.*"),
        # 'ovftool -v' output example: 'VMware ovftool 4.3.0 (build-13375754)'
        "ovftool": ("ovftool -v", r"^VMware\s(ovftool)\s(.*?)\s.*"),
        # 'pip3 freeze' output example: 'PyYAML==3.12'
        "python": ("pip3 freeze", r"(^.*?)==(.*)"),
        # 'apt list --installed' output example: 'zip/bionic,now 3.0-11build1 amd64 [installed]'
        "ubuntu": ("apt list --installed", r"(^.*?)/.*?\s(.*?)\s.*")
    }

    def __init__(self):
        """
        Gathers information about:
            * Git hash of project (if applicable)
            * Linux distro name and version
            * Version information for installed packages
            * Version information for standalone software
            * Version information for active Python modules
        Example:
            {
                "git_hash": "abcdefghijklmnopqrstuvwxyz1234567890",
                "distro": {
                    "name": "fake-os",
                    "version": "1.0"
                },
                "packages": {
                    "foo": "1.0",
                    "bar": "2.0"
                },
                "standalone_software": {
                    "foo": "1.0",
                    "bar": "2.0"
                },
                "python_modules": {
                    "foo": "1.0",
                    "bar": "2.0",
                }
            }
        """
        LOGGER.info("Collecting information about installed software on the build machine")
        self.build_info = {}
        self.build_info["git_hash"] = get_git_hash()
        self.build_info["distro"] = get_distro()
        self.build_info["packages"] = get_packages()
        self.build_info["standalone_software"] = get_standalone_software()
        self.build_info["python_modules"] = get_python_modules()

    def to_json(self):
        """Output build info as pre-formatted JSON string"""
        output = json.dumps(self.build_info, indent=4, sort_keys=True)
        return output

    def to_file(self, build_info_file_path):
        """Output build info as pre-formatted JSON string to file at specified path"""
        LOGGER.debug("Writing build info to specified file as a JSON string")
        output = self.to_json()
        LOGGER.trace("build_info: %s", output)
        Path(dirname(build_info_file_path)).mkdir(parents=True, exist_ok=True)
        with open(build_info_file_path, 'w') as output_file:
            LOGGER.trace("output_file: %s", build_info_file_path)
            output_file.writelines(output)
        LOGGER.debug("Wrote build info to [%s]", build_info_file_path)


def get_git_hash():
    """Determine git hash of project (if applicable)"""
    command = "git status"
    return_code = 0
    try:
        check_output(command.split(), universal_newlines=True, stderr=STDOUT).split('\n')
    except FileNotFoundError:
        return_code = 1
        LOGGER.debug("Skipping git hash lookup since git was not found on the system")
    except CalledProcessError as error:
        return_code = error.returncode
        LOGGER.warning("Skipping git hash lookup since command [%s] returned with error: %s",
                       command, error.output)
    if return_code != 0:
        return "none"

    # This is a git repository, so we'll look up the hash value for the HEAD commit
    command = "git rev-parse HEAD"
    try:
        output = check_output(command.split(), universal_newlines=True, stderr=STDOUT).split('\n')
    except CalledProcessError as error:
        LOGGER.warning("Skipping git hash lookup since command [%s] returned with error: %s",
                       command, error.output)
        return "none"
    git_hash = output[0]
    LOGGER.debug("Git hash: %s", git_hash)
    return git_hash


def get_distro():
    """Collect Linux distro name and version"""
    LOGGER.debug("Collecting Linux distro name and version")
    distro = {}
    distro_data = distro_info.linux_distribution(full_distribution_name=False)
    distro["name"] = distro_data[0]
    distro["version"] = distro_data[1]
    return distro


def get_packages():
    """Collect version information for installed packages"""
    LOGGER.debug("Collecting version information for installed packages")
    distro_data = distro_info.linux_distribution(full_distribution_name=False)
    distro_command = BuildInfo.package_manager_commands[distro_data[0]]
    packages = _command_key_values_to_dict(*distro_command)
    return packages


def get_standalone_software():
    """Collect version information for standalone software"""
    LOGGER.debug("Collecting version information for standalone software")
    standalone_software = {}

    # ovftool
    ovftool_command = BuildInfo.package_manager_commands["ovftool"]
    standalone_software.update(_command_key_values_to_dict(*ovftool_command))

    return standalone_software


def get_python_modules():
    """Collect version information for active Python modules"""
    LOGGER.debug("Collecting version information for active Python modules")
    python_command = BuildInfo.package_manager_commands["python"]
    python_modules = _command_key_values_to_dict(*python_command)
    return python_modules


def _command_key_values_to_dict(command, regex):
    """Runs a command in a subprocess, searches the output of the command for key/value pairs
    using the specified regex, and returns a dictionary containing those pairs"""
    dictionary = {}
    LOGGER.debug("Searching for version information using command: %s", command)
    try:
        lines = check_output(command.split(),
                             universal_newlines=True,
                             stderr=STDOUT).split('\n')
    except FileNotFoundError:
        LOGGER.warning("Command [%s] not found on system.  Unable to check version!", command)
        return dictionary
    except CalledProcessError as error:
        LOGGER.warning("Skipping version information since command [%s] returned with error: %s",
                       command, error.output)
        return dictionary

    for line in lines:
        LOGGER.trace("Regex search string: %s", regex)
        LOGGER.trace("Regex search line: %s", line)
        search = re.search(regex, line)
        if search:
            LOGGER.trace("Regex succeeded")
            dictionary[search.group(1)] = search.group(2)
        else:
            LOGGER.trace("Regex failed")
    LOGGER.trace("Completed dictionary: %s", dictionary)
    return dictionary
