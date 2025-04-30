import json
import boto3
import os
import uuid

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

    transcribe.start_transcription_job(
        TranscriptionJobName=job_name,
        Media={'MediaFileUri': file_uri},
        MediaFormat=key.split('.')[-1],
        LanguageCode='auto',
        OutputBucketName=bucket
    )

    # המתן לסיום העבודה
    while True:
        status = transcribe.get_transcription_job(TranscriptionJobName=job_name)
        if status['TranscriptionJob']['TranscriptionJobStatus'] in ['COMPLETED', 'FAILED']:
            break
        time.sleep(5)

    if status['TranscriptionJob']['TranscriptionJobStatus'] == 'COMPLETED':
        transcript_uri = status['TranscriptionJob']['Transcript']['TranscriptFileUri']
        transcript_data = requests.get(transcript_uri).json()
        original_text = transcript_data['results']['transcripts'][0]['transcript']

        # תרגום
        translated = translate.translate_text(
            Text=original_text,
            SourceLanguageCode='auto',
            TargetLanguageCode='en'
        )['TranslatedText']

        # ניתוח סנטימנט
        sentiment_result = comprehend.detect_sentiment(
            Text=translated,
            LanguageCode='en'
        )

        # שמירת התוצאה
        table.put_item(Item={
            'id': str(uuid.uuid4()),
            'original_text': original_text,
            'translated_text': translated,
            'sentiment': sentiment_result['Sentiment'],
            'details': sentiment_result['SentimentScore']
        })

    return {'statusCode': 200, 'body': 'Done'}
