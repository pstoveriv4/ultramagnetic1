print("importing modules")
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime

for i in range(1,15000):
    csv_file_path = f"./file{i}.csv"
    parquet_file_path = f"./parquetFiles/file{i}.parquet"
    
    print("defining df variable")
    df = pd.read_csv(csv_file_path)

    print("defining table variable")
    table = pa.Table.from_pandas(df)

    print("write the parquet table file")
    pq.write_table(table, parquet_file_path)

    now = datetime.now()
    time = now.strftime("%H:%M")
    print(f"Iteration completed at {time}")

print("***************************************")
print(f"CSV to Parquet completeted at {time}")
print("***************************************")
