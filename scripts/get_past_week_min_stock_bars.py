from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockBarsRequest
from alpaca.data.timeframe import TimeFrame
from datetime import datetime, timedelta
import os
from sqlalchemy.engine import URL
from sqlalchemy import create_engine
from sqlalchemy.types import String, Integer, Float, BigInteger
from sqlalchemy.dialects.postgresql import insert

api_key = os.getenv("ALPACAMARKETS_API_KEY")
secret_key = os.getenv("ALPACAMARKETS_SECRET_KEY")
stock_db_password = os.getenv("STOCKDB_SCRIPT_PASSWORD")

client = StockHistoricalDataClient(api_key, secret_key)

## make list of sp500 names
p = os.path
this_dir = p.dirname(p.abspath(__file__))
with open(p.join(this_dir, "sp500_symbols_2026-05-13.txt")) as file:
    sp500_symbols = [symbol.strip() for symbol in file]


week_ago_date = datetime.now() - timedelta(days=30)

# Loop over sp500:
for i,symbol in enumerate(sp500_symbols):

    request_params = StockBarsRequest(
                            symbol_or_symbols=symbol,
                            timeframe=TimeFrame.Minute,
                            start = week_ago_date,
                     )

    print(f"Requesting bars for {symbol} (Symbol {i+1}/{len(sp500_symbols)})...")
    bars = client.get_stock_bars(request_params)
    print("Bars received, sending to PSQL...")

    bars = bars.df

    bars = bars.reset_index()

    ## rename to match psql table
    bars = bars.rename(columns={'trade_count':'tradecount'})
    bars = bars.rename(columns={'timestamp':'ts'})

    ## convert time to unix epoch in minutes
    bars['ts'] = bars['ts'].apply(
            lambda x: int(x.value // 6e10)
            )


    # Sending to PSQL
    url = URL.create(
        drivername="postgresql+psycopg",
        username="script_writer",
        password=stock_db_password,
        host="localhost",
        port=5432,
        database="stockdb",
    )

    engine = create_engine(url)

    def insert_ignore_duplicates(table, conn, keys, data_iter):
        rows = [dict(zip(keys, row)) for row in data_iter]
        if not rows: return 0
        stmt = insert(table.table).values(rows)
        stmt = stmt.on_conflict_do_nothing(
            index_elements=["symbol", "ts"]
        )
        result = conn.execute(stmt)
        return result.rowcount

    bars.to_sql(
            name = "hist_minutely_bars",
            con = engine,
            schema = "public",
            if_exists = "append",
            index = False,
            chunksize = 10_000,
            method = insert_ignore_duplicates,
            dtype = {
                "symbol" : String(5),
                "ts" : Integer,
                "open" : Float(53),
                "high" : Float(53),
                "low"  : Float(53),
                "close": Float(53),
                "volume" : BigInteger,
                "tradecount" : BigInteger,
                "vwap": Float(53),
                },
            )

    print("Sent {symbol} bars to PSQL :3")

