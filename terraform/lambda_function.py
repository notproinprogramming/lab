import boto3
import botocore
import os
import logging
import urllib.parse
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ENDPOINT_URL = os.getenv('ENDPOINT_URL', 'http://localhost:4566')

s3 = boto3.client(
    's3',
    endpoint_url=ENDPOINT_URL,
    region_name='us-east-1',
    aws_access_key_id='test',
    aws_secret_access_key='test',
    config=botocore.client.Config(
        s3={'addressing_style': 'path'},
        signature_version='s3v4'
    )
)

def handler(event, context):
    try:
        if isinstance(event, str):
            try:
                event = json.loads(event)
            except json.JSONDecodeError:
                logger.error("Invalid JSON format received")
                return {
                    'statusCode': 400,
                    'body': "Invalid JSON format"
                }
        
        logger.info(f"Full event details: {json.dumps(event)}")
        
        if not event.get('Records'):
            logger.error("No Records found in event")
            return {
                'statusCode': 400,
                'body': "No Records found in event"
            }
            
        record = event['Records'][0]
        logger.info(f"Record details: {json.dumps(record)}")
        
        source_bucket = record['s3']['bucket']['name']
        source_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        logger.info(f"Attempting to access: bucket={source_bucket}, key={source_key}")
        
        destination_bucket = os.environ['DESTINATION_BUCKET']
        
        logger.info(f"Copying {source_key} from {source_bucket} to {destination_bucket}")
        
        try:
            s3.head_object(Bucket=source_bucket, Key=source_key)
        except Exception as e:
            logger.error(f"Source file not found: {str(e)}")
            raise
        
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        s3.copy_object(
            Bucket=destination_bucket,
            Key=source_key,
            CopySource=copy_source
        )
        
        message = f"File {source_key} was successfully copied from {source_bucket} to {destination_bucket}"
        logger.info(message)
        
        return {
            'statusCode': 200,
            'body': message
        }
        
    except Exception as e:
        error_message = f"Error processing file: {str(e)}"
        logger.error(error_message)
        
        return {
            'statusCode': 500,
            'body': error_message
        }
