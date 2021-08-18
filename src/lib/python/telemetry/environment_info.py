"""environment information module"""
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

import sys
import platform
import subprocess

from util.logger import LOGGER


class EnvironmentInfo:
    """Class for capturing information about the environment where images are being built"""


    # pylint: disable=R0903
    def __init__(self):
        """
        """
        self.environment = {}
        self.environment["pythonVersion"] = get_python_version()
        self.environment["pythonVersionDetailed"] = get_python_version_detailed()
        # pylint: disable=E1128
        self.environment["nodeVersion"] = get_node_version()
        self.environment["goVersion"] = get_go_version()
        self.git = get_git_version()
        self.ssh = get_ssh_version()
        self.environment["libraries"] = {"git": self.git, "ssh": self.ssh}


def get_python_version():
    """Queries system for python version"""
    return platform.python_version()

def get_python_version_detailed():
    """Queries system for a more detailed python version"""
    return sys.version

def get_node_version():
    """Not currently implemented."""
    return None

def get_go_version():
    """Not currently implemented"""
    return None

def get_git_version():
    """Returns the git version."""
    try:
        with subprocess.Popen(['git', '--version'],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT) as proc:
            out, _ = proc.communicate()
            return out.decode("UTF-8").strip()
    except OSError as error:
        LOGGER.info(error)
        return None

def get_ssh_version():
    """Returns the ssh version."""
    try:
        with subprocess.Popen(['ssh', '-V'],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT) as proc:
            out, _ = proc.communicate()
            return out.decode("UTF-8").strip()
    except FileNotFoundError as error:
        LOGGER.info('The ssh client is not installed.')
        return None
    except OSError as error:
        LOGGER.info(error)
        return None
