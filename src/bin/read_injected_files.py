#!/usr/bin/env python3

"""Read info about injected files"""
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



import sys
from os.path import basename
from util.injected_files import read_injected_files
from util.config import get_config_value
from util.logger import LOGGER, create_file_handler

def main():
    """main read function"""
    # Add a file handler to the global LOGGER
    log_file = get_config_value('LOG_FILE')
    log_level = get_config_value('LOG_LEVEL').upper()
    create_file_handler(LOGGER, log_file, log_level)

    if len(sys.argv) != 2:
        LOGGER.error('%s received %s arguments, expected 2', basename(__file__), len(sys.argv))
        sys.exit(1)

    try:
        read_injected_files(sys.argv[1])
    except RuntimeError as runtime_exception:
        LOGGER.exception(runtime_exception)
        sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    main()
