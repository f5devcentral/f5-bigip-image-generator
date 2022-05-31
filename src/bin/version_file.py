#!/usr/bin/env python3
"""Version file metadata CLI

   Creates version file metadata file and config file."""
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



import argparse
import logging

from metadata.version_file import VersionFile

def main():
    """Main version file helper"""
    parser = argparse.ArgumentParser(description='Create tag string')
    parser.add_argument('-d', '--debug', action='store_true',
                        help='Print debug messages')
    parser.add_argument('-f', '--file', required=True,
                        help='Version file')
    parser.add_argument('-o', '--out-base-dir', required=True,
                        help='Output base directory')

    args = parser.parse_args()

    if args.debug:
        logging.basicConfig(level=logging.DEBUG)

    version = VersionFile(args.file, args.out_base_dir)

    # Load version file and create metadata and config files
    version.load()
    version.create_metadata()
    version.create_config()

if __name__ == "__main__":
    main()
