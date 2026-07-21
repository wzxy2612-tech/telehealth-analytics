import duckdb

# 连接到你当前目录下的 duckdb 文件
con = duckdb.connect('sources/telehealth/telehealth.duckdb')

# 执行查询并打印结果（最多显示 200 行）
query = """
SELECT table_schema, table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_schema IN ('marts', 'ehr_marts') 
ORDER BY table_schema, table_name;
"""
con.sql(query).show(max_rows=200)
