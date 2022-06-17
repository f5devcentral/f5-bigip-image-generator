"""BuildInfo module"""
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


import json
from os.path import dirname
from pathlib import Path

from util.logger import LOGGER
from telemetry.platform_info import PlatformInfo
from telemetry.environment_info import EnvironmentInfo
from telemetry.product_info import ProductInfo


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
        "ubuntu": ("apt list --installed", r"(^.*?)/.*?\s(.*?)\s.*"),
        # apk list
        "alpine": ("apk -v info", r"(^.*?)-(.*)"),
    }

    def __init__(self):
        """
        Class that other information gathering classes inherit from

        All information gathering from this class means that all other
        information gathering classes also need that information
        """

        LOGGER.info("Collecting information about installed software on the build machine")

        platform = PlatformInfo()
        environment = EnvironmentInfo()
        product = ProductInfo()
        self.build_info = {}
        self.build_info["platform"] = platform.platform
        self.build_info["environment"] = environment.environment
        self.build_info["product"] = product.product

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
