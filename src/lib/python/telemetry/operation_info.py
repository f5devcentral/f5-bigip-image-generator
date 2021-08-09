"""Platform information module"""
# Copyright (C) 2020-2021 F5 Networks, Inc
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
import subprocess
import re
import ast

from util.config import get_config_value

class OperationInfo:
    """Class for capturing information about the environment where images are being built"""

    # pylint: disable=R0903
    def __init__(self):
        """
        """
        self.operation = {}
        self.operation["product"] = get_product()
        self.operation["productVersion"] = get_product_version()
        self.operation["productBaseBuild"] = get_product_base_build()
        self.operation["productBuild"] = get_product_build()
        self.operation["platform"] = get_platform()
        self.operation["module"] = get_module()
        self.operation["bootLocations"] = get_boot_locations()
        self.operation["nestedVirtualization"] = get_nested_virt()
        self.operation["updateImageFiles"] = get_update_image_files()
        self.operation["updateLvSizes"] = get_update_lv_sizes()
        self.operation["result"] = get_result()
        self.operation["resultSummary"] = get_result_summary()
        self.operation["startTime"] = get_start_time()
        self.operation["endTime"] = get_end_time()
        self.operation["disableSplash"] = get_disable_splash()
        self.operation["consoleDevicesInput"] = get_console_devices_input()


def get_product():
    """Gets the product that the image generator is being used to build"""
    return "BIG-IP"

def get_product_version():
    """Gets the version of the product that is being built."""
    return read_file_value("VersionFile.json", "version_version")

def get_product_base_build():
    """Gets the build number of the original iso being built."""
    return read_file_value("VersionFile.json", "version_basebuild")

def get_product_build():
    """
    Gets the build number of the hotfix iso or
    if there is none, gets it from the original iso being built.
    """
    return read_file_value("VersionFile.json", "version_build")

def get_platform():
    """Gets the platform (example: azure)."""
    return get_config_value("platform")

def get_module():
    """Gets the module (example: ltm)."""
    return get_config_value("modules")

def get_boot_locations():
    """gets how many boot locations to create in the image."""
    return get_config_value("boot_locations")

def get_nested_virt():
    """returns enabled or disabled for nested virtualization on system."""
    with subprocess.Popen(["grep", "-c", "-E", "svm|vmx", "/proc/cpuinfo"],
            stdout=subprocess.PIPE) as process:
        output = re.findall(r'\d+', str(process.communicate()[0]))
        if output[0] != '0':
            return "enabled"
        return "disabled"

def get_update_image_files():
    """returns enabled or disabled for if files are being updated."""
    image_files = get_config_value("UPDATE_IMAGE_FILES")
    if image_files is None:
        return "disabled"
    return "enabled"

def get_update_lv_sizes():
    """returns if we are updating image lv sizes."""
    lv_sizes = get_config_value("UPDATE_LV_SIZES")
    if lv_sizes is None:
        return "disabled"
    return "enabled"

def get_result():
    """returns if the build was a success or failure."""
    return read_file_value("end_file.json", "result")

def get_result_summary():
    """not yet implemented."""
    return ""

def get_start_time():
    """returns at what time the build began."""
    return read_file_value("start_file.json", "build_start_time")

def get_end_time():
    """returns at what time the build finished."""
    return read_file_value("end_file.json", "build_end_time")

def get_disable_splash():
    """Get the config value for disable_splash."""
    return get_config_value("disable_splash")

def get_console_devices_input():
    """Gets the config value for console_devices."""
    console_input = get_config_value("console_devices")
    if console_input is None:
        return ""
    list_consoles = ast.literal_eval(console_input)

    # ttyS0 is required and should be removed from user-defined consoles.
    if 'ttyS0' in list_consoles:
        list_consoles.remove('ttyS0')

    string_list = " console=".join(list_consoles)
    return string_list

def read_file_value(file_name, value_name):
    """Reads a file from the artifacts directory and returns a value."""
    artifacts_dir = get_config_value("ARTIFACTS_DIR")
    if not os.path.exists(artifacts_dir + "/" + file_name):
        return None
    with open(artifacts_dir + "/" + file_name, "r") as art_file:
        info = json.load(art_file)
        return info[value_name]
