

import pandas as pd
from sqlalchemy import create_engine

# --- CONFIGURATION ---
DB_URL = 'postgresql://postgres@localhost:5432/brazil_retail'
FILE_PATH = '/Users/eoghankealy/Documents/data_projects/brazil_retail_SQL/data_csv_files/olist_order_reviews_dataset.csv'

def import_data():
    try:
        # 1. Create the database engine
        engine = create_engine(DB_URL)
        
        print(f"--- Accessing file: {FILE_PATH} ---")
        
        # 2. Read the CSV
        # Using engine='python' as it handles multiline text and 
        # messy quotes much better than the default C engine
        df = pd.read_csv(
            FILE_PATH, 
            encoding='utf8', 
            engine='python', 
            on_bad_lines='warn',
            quotechar='"'
        )
        
        print(f"--- CSV Read Successful. Found {len(df)} records. ---")
        print("--- Sending data to PostgreSQL (raw.order_reviews)... ---")

        # 3. Upload to PostgreSQL
        # if_exists='append' preserves our manually defined schema
        # and just loads the data in without dropping the table
        df.to_sql(
            'order_reviews', 
            con=engine, 
            schema='raw', 
            if_exists='append',
            index=False
        )

        print(f"--- Success! {len(df)} records loaded into raw.order_reviews ---")
        
    except Exception as e:
        print(f"--- ERROR: {e} ---")

if __name__ == "__main__":
    import_data()