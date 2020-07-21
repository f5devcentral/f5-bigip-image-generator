"""BuildInfo module for telemetry"""
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

from telemetry.build_info import BuildInfo
from telemetry.operation_info import OperationInfo


class BuildInfoTelemetry(BuildInfo):
    """Class for capturing information about the environment where images are being built"""

    def __init__(self):
        """
        Gathers information to be sent to telemetry

        Info includes:
            * Operation info
            * Platform info
            * Product info
            * Environment info
        """

        super().__init__()
        operation = OperationInfo()
        self.build_info["Operation"] = operation.operation

    def to_json(self):
        """Output build info as pre-formatted JSON string"""
        output = json.dumps(self.build_info, indent=4, sort_keys=True)
        return output
