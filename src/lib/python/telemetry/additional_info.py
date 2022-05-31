"""Additional information module"""
# Copyright (C) 2020-2022 F5 Inc
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

from util.logger import LOGGER


class AdditionalInfo:
    """Class for capturing information about the environment where images are being built"""

    # pylint: disable=R0903
    def __init__(self):
        """
        """
        self.additional = {}
        self.additional["gitHash"] = get_git_hash()


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
        LOGGER.debug("Skipping git hash lookup since command [%s] returned with error: %s",
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
