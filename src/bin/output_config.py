#!/usr/bin/env python3

"""Gather config vars and output json file"""
# Copyright (C) 2019-2021 F5 Networks, Inc
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

import argparse
import json
import sys

from util.config import get_config_vars
from util.logger import LOGGER
from util.misc import create_log_handler

def main():
    """main command handler"""
    parser = argparse.ArgumentParser(description='Output configuration variables to a file')
    parser.add_argument('-a', '--artifacts-dir', required=True,
                        help='Absolute path to the artifacts directory')

    args = parser.parse_args()

    # create log handler for the global LOGGER
    create_log_handler()

    # gather config variable info
    config_vars = get_config_vars()

    # Dump alpha sorted file
    output_file = args.artifacts_dir + '/build_config.json'
    with open(output_file, 'w') as output_fp:
        json.dump(config_vars, output_fp, sort_keys=True, indent=4)

    LOGGER.info('Wrote config to: %s', output_file)
    sys.exit(0)

if __name__ == "__main__":
    main()
