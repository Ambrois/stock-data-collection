from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockBarsRequest
from alpaca.data.timeframe import TimeFrame
import psycopg
import pandas as pd
from datetime import datetime, timedelta
import os
import io
import time

api_key = os.getenv("ALPACAMARKETS_API_KEY")
secret_key = os.getenv("ALPACAMARKETS_SECRET_KEY")

client = StockHistoricalDataClient(api_key, secret_key)

## make list of sp500 names, read from file
p = os.path
this_dir = p.dirname(p.abspath(__file__))
with open(p.join(this_dir, "sp500_symbols_2026-05-13.txt")) as file:
    sp500_symbols = [symbol.strip() for symbol in file]


def get_min_bars_since_2016(symbol):
    request_params = StockBarsRequest(
        symbol_or_symbols=symbol,
        timeframe=TimeFrame.Minute,
        start=datetime(2016, 1, 1),
    )

    print(f"\tRequesting bars...")
    bars = client.get_stock_bars(request_params)
    print("\tBars received.")
    return bars.df


def clean_bars(bars):
    ## flatten
    bars = bars.reset_index()

    ## rename to match psql table
    bars = bars.rename(columns={"trade_count": "tradecount"})
    bars = bars.rename(columns={"timestamp": "ts"})

    ## convert time to unix epoch in minutes
    bars["ts"] = bars["ts"].apply(
        lambda x: int(x.value // 6e10)
    )

    ## make volume and tradecount all int
    bars["volume"] = bars["volume"].apply(int)
    bars["tradecount"] = bars["tradecount"].apply(int)

    ## avoid conflicts inside the dataframe itself
    bars = bars.drop_duplicates(subset=["symbol", "ts"])

    return bars


def bulk_send_psql(bars, conninfo) -> None:
    ## write bars to csv in memory
    buffer = io.StringIO()
    bars.to_csv(buffer, index=False, header=False)
    buffer.seek(0)

    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:

            # create staging table to copy into
            print("\tCreating staging table")
            cur.execute("""
                CREATE TEMP TABLE staging_table (
                    symbol VARCHAR(5),
                    ts INTEGER,
                    open DOUBLE PRECISION,
                    high DOUBLE PRECISION,
                    low DOUBLE PRECISION,
                    close DOUBLE PRECISION,
                    volume BIGINT,
                    tradecount BIGINT,
                    vwap DOUBLE PRECISION
                ) ON COMMIT DROP;
            """)

            # copy in-memory csv into staging table
            print("\tCopying to staging table")
            with cur.copy("""
                COPY staging_table (
                    symbol, ts, open, high,
                    low, close, volume, tradecount, vwap
                ) FROM STDIN WITH (FORMAT CSV)
            """) as copy:
                copy.write(buffer.getvalue())

            # insert temp table into main table, ignoring repeats.
            print("\tInserting into main table")
            cur.execute("""
                INSERT INTO public.hist_minutely_bars (
                    symbol, ts, open, high,
                    low, close, volume, tradecount, vwap
                )
                SELECT
                    symbol, ts, open, high,
                    low, close, volume, tradecount, vwap
                FROM staging_table
                ON CONFLICT (symbol, ts) DO NOTHING;
            """)


def format_duration(seconds):
    seconds = max(0, int(round(seconds)))
    hours, remainder = divmod(seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {seconds}s"
    return f"{seconds}s"


if __name__ == "__main__":
    stock_db_password = os.getenv("STOCKDB_SCRIPT_PASS")

    if stock_db_password is None:
        raise RuntimeError("Missing environment variable: STOCKDB_SCRIPT_PASS")

    conninfo = (
        f"postgresql://script_writer:{stock_db_password}"
        f"@localhost:5432/stockdb"
    )

    started_at = time.monotonic()
    total_symbols = len(sp500_symbols)

    for i, symbol in enumerate(sp500_symbols):

        # main thing
        print(f"Starting for symbol {i + 1} of {total_symbols}: {symbol}...")
        bars = get_min_bars_since_2016(symbol)
        bars = clean_bars(bars)
        bulk_send_psql(bars, conninfo)

        # time keeping
        completed = i + 1
        progress_pct = (completed / total_symbols) * 100
        elapsed_seconds = time.monotonic() - started_at
        avg_seconds_per_symbol = elapsed_seconds / completed
        remaining_seconds = avg_seconds_per_symbol * (total_symbols - completed)
        estimated_finish = datetime.now().astimezone() + timedelta(seconds=remaining_seconds)
        finish_label = estimated_finish.strftime("%Y-%m-%d %H:%M %Z")

        print(
            f"Done with {symbol}. Progress: {progress_pct:.3f}% | "
            f"ETA: {format_duration(remaining_seconds)} | "
            f"Finish: {finish_label}"
        )

