"""Platform information module"""
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

import sys

class PlatformInfo:
    """Class for capturing information about the platform where images are being built"""

    # pylint: disable=R0903
    def __init__(self):
        """
        """
        self.platform = {}
        self.platform["os"] = get_os(sys.platform)


def get_os(platform):
    """Queries the system for the operating system."""
    if platform == "win32":
        return "Windows"
    if platform == "darwin":
        return "OS X"
    pretty_name = "Linux"
    with open('/etc/os-release', 'r') as os_release:
        lines = os_release.readlines()
        for line in lines:
            if "PRETTY_NAME" in line:
                # Take off everything before and after quotes
                pretty_name = line.strip().split("\"",1)[1].split("\"",1)[0]
        return pretty_name
