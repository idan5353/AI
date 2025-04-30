import json
import boto3
import os
import uuid
import time
from decimal import Decimal

s3 = boto3.client('s3')
transcribe = boto3.client('transcribe')
translate = boto3.client('translate')
comprehend = boto3.client('comprehend')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key = record['s3']['object']['key']
    job_name = f"transcribe-{uuid.uuid4()}"
    file_uri = f"s3://{bucket}/{key}"
    
    # עיבוד סיומת הקובץ
    media_format = key.split('.')[-1].lower().strip()
    valid_formats = ['mp3', 'mp4', 'wav', 'flac', 'ogg', 'amr', 'webm', 'm4a']
    if media_format not in valid_formats:
        raise ValueError(f"Unsupported media format: {media_format}")
    
    # התחלת עבודת תמלול
    transcribe.start_transcription_job(
        TranscriptionJobName=job_name,
        Media={'MediaFileUri': file_uri},
        MediaFormat=media_format,
        LanguageCode='en-US',
        OutputBucketName=bucket,
        OutputKey=f"transcripts/{key}-transcript.json"
    )
    
    # המתן לסיום העבודה
    while True:
        status = transcribe.get_transcription_job(TranscriptionJobName=job_name)
        job_status = status['TranscriptionJob']['TranscriptionJobStatus']
        if job_status in ['COMPLETED', 'FAILED']:
            break
        time.sleep(5)
    
    if job_status == 'COMPLETED':
        # גישה לקובץ תמלול דרך S3 API במקום URL ישירות
        transcript_key = f"transcripts/{key}-transcript.json"
        response = s3.get_object(Bucket=bucket, Key=transcript_key)
        transcript_data = json.loads(response['Body'].read().decode('utf-8'))
        original_text = transcript_data['results']['transcripts'][0]['transcript']
        
        # זיהוי שפה
        language_response = comprehend.detect_dominant_language(
            Text=original_text
        )
        detected_language_code = language_response['Languages'][0]['LanguageCode']
        
        # תרגום
        translated = translate.translate_text(
            Text=original_text,
            SourceLanguageCode=detected_language_code,
            TargetLanguageCode='en'
        )['TranslatedText']
        
        # ניתוח סנטימנט
        sentiment_result = comprehend.detect_sentiment(
            Text=translated,
            LanguageCode='en'
        )
        
        # המרת ערכי הסנטימנט לdecimal עבור DynamoDB
        sentiment_scores = {k: Decimal(str(v)) for k, v in sentiment_result['SentimentScore'].items()}
        
        # שמירת התוצאה ב-DynamoDB
        table.put_item(Item={
            'id': str(uuid.uuid4()),
            'original_text': original_text,
            'translated_text': translated,
            'sentiment': sentiment_result['Sentiment'],
            'details': sentiment_scores,
            'source_file': key
        })
    
    return {
        'statusCode': 200,
        'body': 'Done'
    }
