"""Product information module"""
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
import os
import re
import subprocess
import yaml

from util.logger import LOGGER


class ProductInfo:
    """Class for capturing information about the product being built"""

    # pylint: disable=R0903
    def __init__(self):
        """
        """
        self.product = {}
        self.operating_system = get_os()
        self.product["version"] = get_version()
        self.product["locale"] = get_locale()
        self.product["installDate"] = get_install_date()
        self.product["installationId"] = get_installation_id()
        self.product["installedComponents"] = get_installed_components(self.operating_system)

    def to_json(self):
        """Output build info as pre-formatted JSON string"""
        output = json.dumps(self.product, indent=4, sort_keys=True)
        return output

def get_os():
    """Returns either Ubuntu or Alpine based on running system."""
    with os.popen("awk -F= '/^NAME/{print $2}' /etc/os-release") as stream:
        output = stream.read()
        if re.search("Alpine", output):
            return "Alpine"
        if re.search("Ubuntu", output):
            return "Ubuntu"
        return "OS not supported"


def get_version():
    """Gets the version of the image generator used in the run."""
    dir_path = os.path.dirname(os.path.realpath(__file__))
    with open(dir_path + '/../../../resource/vars/shared_vars.yml') as vars_file:
        shared_vars = yaml.load(vars_file, Loader=yaml.FullLoader)
        return shared_vars['VERSION_NUMBER']['default']
    return "error retrieving version number"

def get_locale():
    """Gets the locale of the image generator used in the run."""
    with os.popen("locale | grep LANG= | awk -F '=' {'print $2'}") as stream:
        output = stream.read().strip()
        if len(output) == 0:
            try:
                output = os.environ['LANG']
            except KeyError:
                return "could not get locale"

        return output

def get_install_date():
    """returns the date that the image generator was installed."""
    return "2020-05-10 23:37:25.355259"

def get_installation_id():
    """returns id of installation."""
    return "fde0cdd8-d0d6-11e9-8307-0242ac110002"

def get_installed_components(operating_system):
    """returns installed programs related to image generator.

    Abreviated yaml input looks like this:
    _________________________________________
    installComponents:
    alibaba:
        - oss2: python
        - aliyun-python-sdk-ecs: python
    aws:
        - boto3: python
        - moto: python
    _________________________________________
    components = the whole doc except first line
    components = like alibaba or aws
    package    = like oss2 or boto3
    tool       = like python or linux

    For the return it looks like this:
    ______________________________________________
    "installedComponents": {
            "alibaba": {
                "aliyun-python-sdk-ecs": "4.17.6",
                "oss2": "2.8.0"
            },
            "aws": {
                "boto3": "1.10.10",
                "moto": "1.3.13"
            }
    }
    ______________________________________________
    component_return = like alibaba or aws

    """
    script_dir = os.path.dirname(__file__)
    if operating_system == "Ubuntu":
        rel_path = "../../../resource/telemetry/product_ubuntu.yml"
    elif operating_system == "Alpine":
        rel_path = "../../../resource/telemetry/product_alpine.yml"
    else:
        LOGGER.error("unknown operating system")
        return "error getting operating system"
    abs_additional_file_path = os.path.join(script_dir, rel_path)
    main_file_path = os.path.join(script_dir, "../../../resource/telemetry/product.yml")
    install_components = {}
    for abs_file_path in [abs_additional_file_path, main_file_path]:
        with open(abs_file_path) as file:
            yaml_output = yaml.load(file, Loader=yaml.FullLoader)
            components = yaml_output['installComponents']
            for component in components:
                component_return = {}
                for package_info in components[component]:
                    package = list(package_info.keys())[0]
                    tool = list(package_info.values())[0]
                    if tool == "python":
                        component_return[package] = get_python_version(package)
                    elif tool == "linux":
                        component_return[package] = get_linux_version(package, operating_system)
                install_components[component] = component_return
    return install_components

def get_python_version(package):
    """Returns the version number for a pip package."""
    with os.popen("pip3 show " + package + "|grep Version| awk -F ' ' {'print $2'}") as stream:
        output = stream.read().strip()
    return output


def get_linux_version(package, operating_system):
    """Returns Ubuntu version number of package."""
    if operating_system == "Ubuntu":
        with subprocess.Popen(["apt", "show", package], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE) as process:
            output = str(process.communicate()[0])
            version = output.split("\\n")[1].split(" ")[1]
            return version
    elif operating_system == "Alpine":
        process = subprocess.Popen(["sudo", "apk", "search",
                                    "-v", "-x", package],
                                   stdout=subprocess.PIPE)
        output = str(process.communicate()[0])
        return output.split(" ")[0]
    else:
        LOGGER.error("operating system %s not supported", operating_system)
        return ""
