"""AWS snapshot module"""
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


import datetime

from botocore.exceptions import ClientError

from util.config import get_config_value
from util.logger import LOGGER
from util.retrier import Retrier


class AWSSnapshot():
    """Class that converts a S3 storage disk into an AWS volume."""
    def __init__(self, ec2_client, s3_bucket, s3_disk):
        self.s3_bucket = s3_bucket
        self.s3_disk = s3_disk

        # ec2_client object to perform various EC2 operations.
        self.ec2_client = ec2_client
        LOGGER.trace("self.s3_disk = '%s'", self.s3_disk)
        LOGGER.trace("self.s3_bucket = '%s'", self.s3_bucket)

        # Snapshot created from the uploaded 's3_disk'.
        self.snapshot_id = None

        # Import-task-id for the disk import operation.
        self.import_task_id = None

    def clean_up(self):
        """Delete cloud artifacts created during the life-time of this object."""
        try:
            # Cancel pending import-task.
            self.cancel_import_task()
        except ClientError as client_error:
            # Log the underlying error without propagating it further.
            LOGGER.exception(client_error)

        try:
            # Delete the snapshot.
            self.delete_snapshot()
        except ClientError as client_error:
            # Log the underlying error without propagating it further.
            LOGGER.exception(client_error)

        # Always reset to None to avoid re-running the code.
        self.snapshot_id = None
        self.import_task_id = None

    def create_snapshot(self):
        """Creates a snapshot from the uploaded s3_disk."""
        try:
            description = datetime.datetime.now().strftime('%Y%m%d%H%M%S') + '--BIGIP-Volume-From-'
            description += self.s3_disk
            LOGGER.info("Importing the disk [s3://%s/%s] as a snapshot in AWS.",
                        self.s3_bucket, self.s3_disk)
            response = self.ec2_client.import_snapshot(Description=description,
                                                       DiskContainer={
                                                           "Format": "vmdk",
                                                           "UserBucket": {
                                                               "S3Bucket": self.s3_bucket,
                                                               "S3Key": self.s3_disk
                                                           }
                                                       })
            LOGGER.trace("import_snapshot() Response => '%s'", response)
            self.import_task_id = response['ImportTaskId']
            LOGGER.info("TaskId for the import_snapshot() operation  => [%s]",
                        self.import_task_id)
            # Wait for the snapshot import to complete.
            self.is_snapshot_ready(self.import_task_id)

            # As the import operation successfully completed, reset it back to None
            # to avoid trying to cancel a completed import-task during clean-up.
            self.import_task_id = None
        except RuntimeError as runtime_error:
            LOGGER.exception(runtime_error)
            raise

    def is_snapshot_ready(self, import_task_id):
        """Checks if a snapshot with the given import_task_id exists and its
        status is 'completed'."""
        def _is_snapshot_ready():
            """Awaits the import operation represented by the import_task_id to reach
            'completed' status."""
            try:
                LOGGER.trace("Querying the status of import-task [%s].", import_task_id)
                response = \
                    self.ec2_client.describe_import_snapshot_tasks(
                        ImportTaskIds=[import_task_id])
                if not response:
                    raise RuntimeError("describe_import_snapshot_tasks() returned none response!")

                LOGGER.trace("Response from describe_import_snapshot_tasks => '%s'",
                             response)
                task_status = response['ImportSnapshotTasks'][0]['SnapshotTaskDetail']['Status']
                if task_status == 'error':
                    # Print the response before raising an exception.
                    LOGGER.debug("describe_import_snapshot_tasks() response for [%s] => [%s]",
                                 import_task_id, response)
                    raise RuntimeError("import-snapshot task [{}] in unrecoverable 'error' state.".
                                       format(import_task_id))

                return task_status == 'completed'
            except ClientError as client_error:
                LOGGER.exception(client_error)
                raise RuntimeError("describe_import_snapshot_tasks() failed for [{}]!".
                                   format(import_task_id))

        retrier = Retrier(_is_snapshot_ready)
        retrier.tries = int(get_config_value('AWS_IMPORT_SNAPSHOT_TASK_RETRY_COUNT'))
        retrier.delay = int(get_config_value('AWS_IMPORT_SNAPSHOT_TASK_RETRY_DELAY'))
        LOGGER.info("Waiting for the import snapshot task [%s] to complete.", import_task_id)
        try:
            if retrier.execute():
                LOGGER.info("import_snapshot_task [%s] is completed.", import_task_id)
                # Call it one last time to get the snapshot_id.
                response = \
                self.ec2_client.describe_import_snapshot_tasks(
                    ImportTaskIds=[import_task_id])
                self.snapshot_id = \
                    response['ImportSnapshotTasks'][0]['SnapshotTaskDetail']['SnapshotId']
                LOGGER.info("SnapshotID = [%s].", self.snapshot_id)
                return True
            LOGGER.warning("import_snapshot_task [%s] didn't complete after checking [%d] times!",
                           import_task_id, retrier.tries)
            return False
        except RuntimeError as runtime_exception:
            LOGGER.exception(runtime_exception)
            raise

    def delete_snapshot(self):
        """Delete the AWS snapshot created by this object."""
        if self.snapshot_id is not None:
            LOGGER.info("Deleting the snapshot '%s'.", self.snapshot_id)
            self.ec2_client.delete_snapshot(SnapshotId=self.snapshot_id)
            LOGGER.info("Successfully deleted snapshot '%s'.", self.snapshot_id)

    def cancel_import_task(self):
        """Cancel an on-going import task as represented by the self.import_task_id.
        As per AWS, this only works on "pending" import tasks. For a completed task
        this would essentially be a NO-OP."""
        if self.import_task_id is not None:
            LOGGER.info("Cancelling pending import task '%s'.", self.import_task_id)
            self.ec2_client.cancel_import_task(ImportTaskId=self.import_task_id)
            LOGGER.info("Successfully cancelled pending import task '%s'.", self.import_task_id)
