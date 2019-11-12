"""Alibaba disk module"""
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



import os
import random
import string
import time
import oss2
from image.base_disk import BaseDisk
from util.config import get_config_value
from util.logger import LOGGER
from util.retrier import Retrier

class AlibabaDisk(BaseDisk):
    """Class for handling Alibaba disk related actions"""

    def __init__(self, input_disk_path, working_dir):
        """Initialize Alibaba disk object."""
        super().__init__(input_disk_path, working_dir)
        self.bucket = None

    def clean_up(self):
        """Clean-up."""
        if self.disk_to_upload is not None and os.path.exists(self.disk_to_upload):
            LOGGER.debug("Deleting the local disk that was (or had to be) uploaded:= '%s'",
                         self.disk_to_upload)
            os.remove(self.disk_to_upload)
        else:
            failed_delete_file_msg = "Could not find (and delete) the local disk that " + \
                                     "was (or had to be) uploaded: {}".format(self.disk_to_upload)
            LOGGER.debug(failed_delete_file_msg)

        LOGGER.debug("Cleaning up the uploaded disk from Alibaba storage")
        self.upload_cleanup()

    def extract(self):
        """Extract the qcow2 disk out of zip."""
        LOGGER.debug("Extracting '.qcow2 disk file from [%s].", self.input_disk_path)
        self.disk_to_upload = BaseDisk.decompress(self.input_disk_path, '.qcow2', self.working_dir)
        LOGGER.info("Alibaba disk_to_upload = '%s'", self.disk_to_upload)

    def upload(self):
        """Upload disk with OSS2 (Alibaba Python SDK)
           resumable_upload is used to upload large size files"""
        number_of_threads = self.set_number_of_threads()
        self.set_bucket()
        AlibabaDisk.iter = 0
        def _resumable_upload():
            self.uploaded_disk_name = 'bakery-' + os.path.basename(self.disk_to_upload) + '-' + \
                                      ''.join(random.choices(string.digits, k=6))
            AlibabaDisk.iter += 1
            LOGGER.info('Upload iteration number %d', AlibabaDisk.iter)
            LOGGER.info('Uploading %s as %s', self.disk_to_upload, self.uploaded_disk_name)
            start_time = time.time()
            time.sleep(1)
            result = False
            try:
                resumable_store = oss2.resumable.ResumableStore(root=self.working_dir)
                oss2.resumable_upload(self.bucket, self.uploaded_disk_name, self.disk_to_upload,
                                      store=resumable_store, num_threads=number_of_threads)
                result = True
            except FileNotFoundError as exc:
                LOGGER.exception(exc)
                raise RuntimeError('Could not find file to upload: {}'.format(self.disk_to_upload))
            except oss2.exceptions.NoSuchUpload as exc:
                LOGGER.error('Upload failed. UploadId: %s', exc.details['UploadId'])
                LOGGER.exception(exc)

            LOGGER.info('Iteration %d of upload took %d seconds', AlibabaDisk.iter,
                        time.time() - start_time)
            if not result:
                self.upload_cleanup()
            return result

        retrier = Retrier(_resumable_upload)
        retrier.tries = int(get_config_value('ALIBABA_UPLOAD_FILE_RETRY_COUNT'))
        retrier.delay = int(get_config_value('ALIBABA_UPLOAD_FILE_RETRY_DELAY'))

        if retrier.execute():
            LOGGER.info('Finished upload of %s', self.disk_to_upload)
        else:
            raise RuntimeError('Exhausted all {} retries for file {} to upload.'.
                               format(retrier.tries, self.uploaded_disk_name))

    @staticmethod
    def set_number_of_threads():
        """number of threads should not be higher than oss2.defaults.connection_pool_size"""
        if int(get_config_value('ALIBABA_THREAD_COUNT')) > int(oss2.defaults.connection_pool_size):
            number_of_threads_message = 'Will use only ' + \
                '{} threads for the image upload, '.format(oss2.defaults.connection_pool_size) + \
                'the limit is imposed by oss2.defaults.connection_pool_size'
            LOGGER.warning(number_of_threads_message)
            return int(oss2.defaults.connection_pool_size)
        return int(get_config_value('ALIBABA_THREAD_COUNT'))

    def set_bucket(self):
        """Return bucket for uploaded files"""
        access_key = get_config_value('ALIBABA_ACCESS_KEY_ID')
        secret_key = get_config_value('ALIBABA_ACCESS_KEY_SECRET')
        auth = oss2.Auth(access_key, secret_key)

        region = get_config_value('ALIBABA_REGION')
        bucket_name = get_config_value('ALIBABA_BUCKET')
        self.bucket = oss2.Bucket(auth, 'https://oss-' + region + '.aliyuncs.com', bucket_name)

        try:
            self.bucket.get_bucket_info()
        except oss2.exceptions.SignatureDoesNotMatch as exc:
            LOGGER.exception(exc)
            raise RuntimeError('Bad credentials to get bucket info')
        except oss2.exceptions.ServerError as exc:
            if exc.details['Code'] == 'InvalidBucketName':
                LOGGER.exception(exc)
                raise RuntimeError('Invalid bucket name: ' + exc.details['BucketName'])
            LOGGER.exception(exc)
            raise RuntimeError('Unexpected Alibaba oss server error. ' +
                               'One of possible errors: invalid credentials.')
        except oss2.exceptions.RequestError as exc:
            LOGGER.exception(exc)
            raise RuntimeError('Alibaba oss request error. ' +
                               'One of possible errors: invalid Alibaba region.')

    def upload_cleanup(self):
        """clean up after a (single iteration of a) failed upload
           instead of resuming the upload, start from scratch"""
        self.delete_file_from_storage()
        self.delete_fragments_from_storage()

        # also delete checkpoint, since fragments are deleted
        upload_dir = os.path.join(self.working_dir,
                                  oss2.resumable._UPLOAD_TEMP_DIR) # pylint: disable=protected-access
        for checkpoint in os.listdir(upload_dir):
            os.unlink(os.path.join(upload_dir, checkpoint))

    def delete_file_from_storage(self):
        """delete file from storage"""
        if self.bucket.object_exists(self.uploaded_disk_name):
            LOGGER.info('Storage file %s exists, deleting it', self.uploaded_disk_name)
            self.bucket.delete_object(self.uploaded_disk_name)
        else:
            LOGGER.info('Storage file %s does not exist, no need to delete it',
                        self.uploaded_disk_name)

    def delete_fragments_from_storage(self):
        """delete fragments from storage without rethrowing any exceptions, since it is a cleanup
           (fragments of successfully uploaded file are deleted automatically)"""
        found = False
        for fragments in self.bucket.list_multipart_uploads().upload_list:
            if fragments.key == self.uploaded_disk_name:
                found = True
                LOGGER.info('Found fragments for file %s upload id %s, deleting them',
                            self.uploaded_disk_name, fragments.upload_id)
                self.bucket.abort_multipart_upload(fragments.key, fragments.upload_id)
        if not found:
            LOGGER.info('Did not find any fragments for file %s, no need to delete them',
                        self.uploaded_disk_name)
