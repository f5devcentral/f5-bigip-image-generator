#!/usr/bin/env python3

""" Read user defined values for LV sizes """
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



import sys
from os.path import basename
from util.logger import LOGGER
from util.misc import create_log_handler, read_lv_sizes

def main():
    """ Wrapper to read user defined values for LV sizes """
    # create log handler for the global LOGGER
    create_log_handler()

    if len(sys.argv) != 2:
        LOGGER.error('%s received %s arguments, expected 1', basename(__file__), len(sys.argv) - 1)
        sys.exit(1)

    try:
        read_lv_sizes(sys.argv[1])
    except RuntimeError as runtime_exception:
        LOGGER.exception(runtime_exception)
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
