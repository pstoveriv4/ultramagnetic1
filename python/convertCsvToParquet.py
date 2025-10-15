print("importing modules")
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

print("defining csv_file_path variable")
csv_file_path = "/home/auroradp/csvFile10.csv"

print("defining df variable")
df = pd.read_csv(csv_file_path)

print("defining table variable")
table = pa.Table.from_pandas(df)

print("defining parquet_file_path variable")
parquet_file_path = "/home/auroradp/file10.parquet"

print("write the parquet table file")
pq.write_table(table, parquet_file_path)
