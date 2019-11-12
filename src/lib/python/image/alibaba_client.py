"""Alibaba client module"""
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


import json
import aliyunsdkcore.request
from aliyunsdkcore.client import AcsClient
from aliyunsdkcore.acs_exception.exceptions import ClientException, ServerException
from aliyunsdkecs.request.v20140526.AddTagsRequest \
    import AddTagsRequest
from aliyunsdkecs.request.v20140526.DeleteImageRequest \
    import DeleteImageRequest
from aliyunsdkecs.request.v20140526.DescribeImagesRequest \
    import DescribeImagesRequest
from aliyunsdkecs.request.v20140526.ImportImageRequest \
    import ImportImageRequest
from aliyunsdkecs.request.v20140526.CancelTaskRequest \
    import CancelTaskRequest
from aliyunsdkecs.request.v20140526.DescribeTaskAttributeRequest \
    import DescribeTaskAttributeRequest
from aliyunsdkecs.request.v20140526.DescribeImageSharePermissionRequest \
    import DescribeImageSharePermissionRequest
from aliyunsdkecs.request.v20140526.ModifyImageSharePermissionRequest \
    import ModifyImageSharePermissionRequest


from util.config import get_config_value
from util.logger import LOGGER


class AlibabaClient():
    """ Class for sending requests to Alibaba cloud services """

    @staticmethod
    def __get_acs_client():
        """ Setup and return a client to Alibaba cloud service.
            Requires ALIBABA_ACCESS_KEY_ID and ALIBABA_ACCESS_KEY_SECRET to be set. """
        client = AcsClient(get_config_value('ALIBABA_ACCESS_KEY_ID'),
                           get_config_value('ALIBABA_ACCESS_KEY_SECRET'),
                           get_config_value('ALIBABA_REGION'))
        return client


    def __send_request(self, request):
        """ Send a request to Alibaba cloud services """
        aliyunsdkcore.request.set_default_protocol_type('https')
        request.set_protocol_type('https')
        request.set_accept_format('json')
        client = self.__get_acs_client()
        try:
            response_str = client.do_action_with_exception(request)
        except ClientException as exc:
            LOGGER.exception(exc)
            raise RuntimeError('Check correctness of ALIBABA_REGION configuration variable')
        except ServerException as exc:
            LOGGER.exception(exc)
            if exc.get_error_code() == 'InvalidAccessKeyId.NotFound' and \
                    exc.get_error_msg() == 'Specified access key is not found.':
                raise RuntimeError('InvalidAccessKeyId.NotFound: Check correctness of ' +
                                   'ALIBABA_ACCESS_KEY_ID configuration variable')
            if exc.get_error_code() == 'IncompleteSignature' and \
                    exc.get_error_msg().startswith('The request signature does not conform to ' +
                                                   'Aliyun standards'):
                raise RuntimeError('IncompleteSignature: Check correctness of ' +
                                   'ALIBABA_ACCESS_KEY_SECRET configuration variable')
            if exc.get_error_code() == 'InvalidAccessKeySecret' and \
                    exc.get_error_msg() == 'The AccessKeySecret is incorrect. Please check ' + \
                                           'your AccessKeyId and AccessKeySecret.':
                raise RuntimeError('InvalidAccessKeySecret: Check correctness of ' +
                                   'ALIBABA_ACCESS_KEY_ID and ALIBABA_ACCESS_KEY_SECRET ' +
                                   'configuration variables')
            raise exc

        response = json.loads(response_str)
        if 'Code' in response.keys():
            LOGGER.warning('Request to Alibaba has \'Code\' attribute. Full Alibaba response:')
            LOGGER.warning(json.dumps(response, sort_keys=True, indent=4, separators=(',', ': ')))
        return response

    def add_tags(self, resource_id, resource_type, tags):
        """ Add Resource Tags by resource id.
            Return Alibaba response """

        # Transform tags dictionary to array of dictionaries
        tags_array = []
        for key, value in tags.items():
            array_entry = {"Key":key, "Value":value}
            tags_array.append(array_entry)

        request = AddTagsRequest()
        request.set_ResourceId(resource_id)
        request.set_ResourceType(resource_type)
        request.set_Tags(tags_array)
        return self.__send_request(request)

    def delete_image(self, image_id):
        """ Delete image by image id
            Return Alibaba response """
        request = DeleteImageRequest()
        request.set_ImageId(image_id)
        return self.__send_request(request)

    def describe_images(self, image_id, image_name):
        """ Send request to get details of images
            Filter by image id and name
            Return Alibaba response """
        request = DescribeImagesRequest()
        if image_id:
            request.set_ImageId(image_id)
        if image_name:
            request.set_ImageName(image_name)
        return self.__send_request(request)

    def import_image(self, oss_bucket, oss_object, image_name):
        """ Form and send request to to import image
            Return Alibaba response """
        oss_image = [{'OSSBucket': oss_bucket, 'OSSObject': oss_object}]
        request = ImportImageRequest()
        request.set_DiskDeviceMappings(oss_image)
        request.set_OSType('Linux')
        request.set_Architecture('x86_64')
        request.set_Platform('Others Linux')
        request.set_ImageName(image_name)
        request.set_Description(image_name)
        return self.__send_request(request)

    def cancel_task(self, task_id):
        """ Send request to cancel task by task id
            Return Alibaba response """
        request = CancelTaskRequest()
        request.set_TaskId(task_id)
        return self.__send_request(request)

    def describe_task_attribute(self, task_id):
        """ Send request to get task state with matching id
            Return Alibaba response """
        request = DescribeTaskAttributeRequest()
        request.set_TaskId(task_id)
        return self.__send_request(request)

    def share_image_with_accounts(self, image_id, share_account_ids):
        """ Send request to share image with other alibaba
            accounts. Return Alibaba response """
        request = ModifyImageSharePermissionRequest()
        request.set_ImageId(image_id)
        request.set_AddAccounts(share_account_ids)
        return self.__send_request(request)

    def describe_image_share_permission(self, image_id):
        """Print description of an image's share permissions"""
        if image_id is None or not image_id:
            raise Exception('No image id provided')
        request = DescribeImageSharePermissionRequest()
        if image_id:
            request.set_ImageId(image_id)
        return self.__send_request(request)
