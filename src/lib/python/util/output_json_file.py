"""OutputJsonFile module"""
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


import json
import uuid
from os.path import dirname
from pathlib import Path

import telemetry.operation_info
from telemetry.operation_info import read_file_value
from util.config import get_config_value
from util.logger import LOGGER


class OutputJsonFile:
    """Class for capturing information about the environment where images are being built"""

    def __init__(self):
        """
        Class that other information gathering classes inherit from

        All information gathering from this class means that all other
        information gathering classes also need that information
        """

        LOGGER.info("Collecting information about installed software on the build machine")

        self.json_info = {}
        self.json_info["modules"] = telemetry.operation_info.get_module()
        self.json_info["uuid"] = uuid.uuid1().hex
        self.json_info["image_name"] = get_image_name()
        self.json_info["image_id"] = get_image_id()
        self.json_info["platform"] = telemetry.operation_info.get_platform()
        self.json_info["boot_locations"] = telemetry.operation_info.get_boot_locations()
        self.json_info["modules"] = telemetry.operation_info.get_module()
        self.json_info["result"] = telemetry.operation_info.get_result()
        self.json_info["start_time"] = telemetry.operation_info.get_start_time()
        self.json_info["end_time"] = telemetry.operation_info.get_end_time()
        self.get_platform_specific_info()
        self.output_file_path = "./" # set default output to main folder

    def to_json(self):
        """Output build info as pre-formatted JSON string"""
        output = json.dumps(self.json_info, indent=4, sort_keys=True)
        return output

    def set_output_path(self, path):
        """Pass in a path to set output file path of object."""
        self.output_file_path = path

    def to_file(self):
        """Output build info as pre-formatted JSON string to file at specified path"""
        LOGGER.debug("Writing build info to specified file as a JSON string")
        output = self.to_json()
        LOGGER.trace("json output info: %s", output)
        Path(dirname(self.output_file_path)).mkdir(parents=True, exist_ok=True)
        with open(self.output_file_path, 'w') as output_file:
            LOGGER.trace("output_file: %s", self.output_file_path)
            output_file.writelines(output)
        LOGGER.debug("Wrote build info to [%s]", self.output_file_path)


    def get_platform_specific_info(self):
        """Gets platform then directs to the correct platform info gathering function."""
        plat = get_config_value("PLATFORM")
        if plat == "aws":
            self.get_aws_info()
        if plat == "alibaba":
            self.get_alibaba_info()
        if plat == "gce":
            self.get_gce_info()
        if plat == "azure":
            self.get_azure_info()
        if is_hypervisor_image(plat):
            location_dir = read_file_value("location.json", "location_dir")
            self.json_info["location"] = location_dir

    def get_aws_info(self):
        """Gets aws specific info."""
        self.json_info["aws_image_id"] = read_file_value("image_id.json", "image_id")
        self.json_info["aws_region"] = get_config_value("AWS_REGION")

    def get_alibaba_info(self):
        """Gets alibaba specific."""
        self.json_info["alibaba_image_id"] = read_file_value("image_id.json", "image_id")
        self.json_info["alibaba_region"] = get_config_value('ALIBABA_REGION')
        self.json_info["alibaba_location"] = read_file_value("alibaba_location.json",
                                                             "alibaba_location")

    def get_gce_info(self):
        """Gets gce specific info."""
        self.json_info["gce_project"] = read_file_value("prepare_cloud_image.json", "gce_project")
        self.json_info["gce_location"] = read_file_value("gce_location.json", "gce_location")

    def get_azure_info(self):
        """Gets azure specific info."""
        self.json_info["azure_resource_group"] = get_config_value('AZURE_RESOURCE_GROUP')
        self.json_info["azure_region"] = get_config_value('AZURE_REGION')
        self.json_info["azure_location"] = read_file_value("vhd_url.json", "vhd_url")


def get_image_name():
    """Retrieves the image name from config system."""
    plat = get_config_value("PLATFORM")
    if is_hypervisor_image(plat):
        return get_config_value("HYPERVISOR_IMAGE_NAME")

    return get_config_value("CLOUD_IMAGE_NAME")


def get_image_id():
    """Retrieves image id."""
    plat = get_config_value("PLATFORM")
    if plat in ("aws", "alibaba"):
        return telemetry.operation_info.read_file_value("prepare_cloud_image.json", "image_id")
    return get_image_name()


def is_hypervisor_image(plat):
    """Checks if platform is a hypervisor. Returns true for hypervisor, false for cloud."""
    hypervisor_list = ["vmware", "qcow2", "vhd"]
    if plat in hypervisor_list:
        return True
    return False
