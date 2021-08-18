"""Base Disk module"""
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



import datetime
import os
import tarfile
import zipfile
from pathlib import Path

from util.logger import LOGGER


class BaseDisk:
    """
    Base disk class for all platform specific derivations
    """

    def __init__(self, input_disk_path, working_dir=None):
        if not os.path.isfile(input_disk_path):
            self.input_disk_path = None
            LOGGER.error("'%s' (input_disk_path to BaseDisk.__init__) is not a file.",
                         input_disk_path)
            LOGGER.error('BaseDisk cannot be properly initialized.')
            raise RuntimeError('Invalid input disk path {}'.format(input_disk_path))
        self.input_disk_path = input_disk_path

        # If a working directory is given, make sure it exists.
        if working_dir is not None:
            if not os.path.isdir(working_dir):
                LOGGER.error("'%s' (working_dir to BaseDisk.__init__) is not a directory.",
                             working_dir)
                raise RuntimeError('Invalid working dir path {}'.format(working_dir))

        self.working_dir = working_dir
        LOGGER.debug("BaseDisk.input_disk_path is '%s'.", self.input_disk_path)
        self.disk_to_upload = None
        self.uploaded_disk_name = None

    def clean_up(self):
        """
        Walk through objects created on the machine
        and clean them up if the clean up flag is True.
        """
        raise NotImplementedError("clean_up() unimplemented.")

    def extract(self):
        """Extract disk for upload.
        Real work to be done by the derived class implementations"""

    def upload(self):
        """Upload disk to the cloud storage.
        Real work to be done by the derived class implementations"""
        LOGGER.info("BaseDisk.uploaded_disk_name is '%s'.", self.uploaded_disk_name)

    def set_uploaded_disk_name(self, disk_name):
        """Set the uploaded disk name"""

    @staticmethod
    def decompress(input_disk, output_file_ext, output_dir):
        """Extracts the file with output_file_ext from the given input disk and
        stores it under output_dir. The function returns extracted file's full
        path. If the input_disk contains multiple files with output_file_ext,
        the function would return the first one among them."""
        out_file = None
        try:
            if str.endswith(input_disk, (".tar.gz", ".tgz")):
                with tarfile.open(input_disk, "r:gz") as tar_file:
                    for file_name in tar_file.getnames():
                        if file_name.endswith(output_file_ext):
                            tar_file.extract(member=file_name, path=output_dir)
                            out_file = os.path.join(output_dir, file_name)
                            break
            elif str.endswith(input_disk, ".zip"):
                with zipfile.ZipFile(input_disk, "r") as zip_file:
                    for file_name in zip_file.namelist():
                        if file_name.endswith(output_file_ext):
                            zip_file.extract(member=file_name, path=output_dir)
                            out_file = os.path.join(output_dir, file_name)
                            break
            else:
                input_file_ext = "".join(Path(input_disk).suffixes)
                raise NotImplementedError("Extension {} is not supported.  Unable to extract "
                                          "compressed disk {}!".format(input_file_ext, input_disk))
        except (tarfile.ReadError, zipfile.BadZipFile) as read_error:
            LOGGER.exception(read_error)
            raise RuntimeError("Failed to read {} file".format(input_disk)) from read_error
        except RuntimeError as runtime_error:
            LOGGER.exception(runtime_error)
            raise runtime_error

        # out_file must be populated by now.
        if out_file is None:
            raise RuntimeError("No {} file found in the {} archive."
                               .format(output_file_ext, input_disk))

        return out_file

    @staticmethod
    def decorate_disk_name(disk_path):
        """Appends the timestamp as a prefix to the given disk_path to generate
        a unique disk-name."""
        if disk_path:
            result = datetime.datetime.now().strftime('%Y%m%d--%H%M%S')
            result += "--" + os.path.basename(disk_path)
        else:
            raise RuntimeError("decorate_disk_name() received an empty disk_path argument.")
        return result
