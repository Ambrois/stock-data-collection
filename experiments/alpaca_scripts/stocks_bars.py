from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockBarsRequest
from alpaca.data.timeframe import TimeFrame
from datetime import datetime
import os

# no keys required for crypto data
api_key = os.getenv("ALPACAMARKETS_API_KEY")
secret_key = os.getenv("ALPACAMARKETS_SECRET_KEY")

client = StockHistoricalDataClient(api_key, secret_key)

request_params = StockBarsRequest(
                        symbol_or_symbols=["SPY"],
                        timeframe=TimeFrame.Minute,
                        start=datetime(2025, 1, 1),
                        end=datetime(2025, 2, 1)
                 )

bars = client.get_stock_bars(request_params)

# convert to dataframe
bars = bars.df


# Sending to psql

bars = bars.reset_index()

bars['timestamp'] = bars['timestamp'].apply(
            lambda x:
            int(x.value // 6e10)
        )

