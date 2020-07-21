"""Platform information module"""
# Copyright (C) 2020 F5 Networks, Inc
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

from sys import platform


class PlatformInfo:
    """Class for capturing information about the platform where images are being built"""

    # pylint: disable=R0903
    def __init__(self):
        """
        """
        self.platform = {}
        self.platform["os"] = get_os()


def get_os():
    """Queries the system for the operating system."""
    if platform == "win32":
        return "Windows"
    if platform == "darwin":
        return "OS X"
    return "Linux"
