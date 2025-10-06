# etl.py
import os
import time
import boto3
import pandas as pd
from io import StringIO
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

S3_BUCKET = os.environ.get('S3_BUCKET')
REDSHIFT_WORKGROUP = os.environ.get('REDSHIFT_WORKGROUP')
DB_NAME = 'dev'
INPUT_KEY = 'raw/render_logs.csv'
TABLE_NAME = 'performance_summary'

s3_client = boto3.client('s3')
redshift_client = boto3.client('redshift-data')

def main():
    logging.info("Starting ETL process...")

    logging.info(f"Extracting data from s3://{S3_BUCKET}/{INPUT_KEY}")
    csv_obj = s3_client.get_object(Bucket=S3_BUCKET, Key=INPUT_KEY)
    body = csv_obj['Body'].read().decode('utf-8')
    df = pd.read_csv(StringIO(body))

    logging.info("Transforming data: calculating aggregates.")
    df['timestamp'] = pd.to_datetime(df['timestamp'])
    df['gpu_usage'] = df['gpu_usage'].round(2)
    df['frame_rate'] = df['frame_rate'].round(2)

    summary_df = df.groupby('device_id').agg(
        avg_frame_rate=('frame_rate', 'mean'),
        avg_gpu_usage=('gpu_usage', 'mean'),
        max_latency_ms=('latency_ms', 'max'),
        log_count=('timestamp', 'count')
    ).reset_index()

    logging.info("Transformation complete. Summary:\n%s", summary_df)

    logging.info(f"Loading data into Redshift table: {TABLE_NAME}")

    create_table_sql = f"""
    CREATE TABLE IF NOT EXISTS {TABLE_NAME} (
        device_id VARCHAR(50),
        avg_frame_rate FLOAT,
        avg_gpu_usage FLOAT,
        max_latency_ms INTEGER,
        log_count INTEGER
    );
    """
    execute_sql(create_table_sql)

    truncate_sql = f"TRUNCATE TABLE {TABLE_NAME};"
    execute_sql(truncate_sql)

    for index, row in summary_df.iterrows():
        insert_sql = f"""
        INSERT INTO {TABLE_NAME} (device_id, avg_frame_rate, avg_gpu_usage, max_latency_ms, log_count)
        VALUES ('{row['device_id']}', {row['avg_frame_rate']}, {row['avg_gpu_usage']}, {row['max_latency_ms']}, {row['log_count']});
        """
        execute_sql(insert_sql)

    logging.info("Successfully loaded data into Redshift.")

def execute_sql(sql_statement):
    try:
        response = redshift_client.execute_statement(
            WorkgroupName=REDSHIFT_WORKGROUP,
            Database=DB_NAME,
            Sql=sql_statement
        )
        statement_id = response['Id']

        status = 'STARTED'
        while status in ['STARTED', 'SUBMITTED']:
            desc = redshift_client.describe_statement(Id=statement_id)
            status = desc['Status']
            if status in ['FINISHED', 'FAILED', 'ABORTED']:
                break
            time.sleep(1)

        if status != 'FINISHED':
            raise RuntimeError(f"SQL statement failed: {desc}")
    except Exception as e:
        logging.error(f"Error executing SQL: {e}")
        raise


if __name__ == '__main__':
    main()