# generate_logs.py
import csv
import random
from datetime import datetime, timedelta

def generate_logs(filename='render_logs.csv', rows=100):
    headers = ['timestamp', 'device_id', 'frame_rate', 'gpu_usage', 'latency_ms']
    devices = [f'iac-vx{i}' for i in range(1, 5)]

    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(headers)

        start_time = datetime.now()
        for i in range(rows):
            timestamp = start_time - timedelta(seconds=i*10)
            row = [
                timestamp.isoformat(),
                random.choice(devices),
                random.uniform(59.5, 60.1),
                random.uniform(75.0, 95.0),
                random.randint(15, 25)
            ]
            writer.writerow(row)
    print(f"Generated {rows} rows in {filename}")

if __name__ == '__main__':
    generate_logs()