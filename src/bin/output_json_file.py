#!/usr/bin/env python3

"""gather information then create output json file"""
# Copyright (C) 2019-2020 F5 Networks, Inc
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

from util.output_json_file import OutputJsonFile
from util.logger import LOGGER
from util.misc import create_log_handler

def main():
    """main output json information file function"""
    # create log handler for the global LOGGER
    create_log_handler()

    output_path = sys.argv[1]

    # gather output json file info
    output_json_file = OutputJsonFile()
    LOGGER.info("Information in output file:")
    LOGGER.info(output_json_file.json_info)
    if (len(output_path) > 4 and output_path[-5:] == ".json"):
        output_json_file.set_output_path(output_path)
    else:
        output_json_file.set_output_path(output_path + "output_info.json")
    output_json_file.to_file()
    sys.exit(0)


if __name__ == "__main__":
    main()
