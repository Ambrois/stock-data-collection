from alpaca.data.historical import OptionsHistoricalDataClient
from alpaca.data.requests import OptionsBarsRequest
from alpaca.data.timeframe import TimeFrame
from datetime import datetime
import os

# no keys required for crypto data
api_key = os.getenv("ALPACAMARKETS_API_KEY")
secret_key = os.getenv("ALPACAMARKETS_SECRET_KEY")

client = OptionsHistoricalDataClient(api_key, secret_key)

request_params = OptionsBarsRequest(
                        symbol_or_symbols=["SPY"],
                        timeframe=TimeFrame.Day,
                        start=datetime(2025, 1, 1),
                        end=datetime(2026, 1, 5)
                 )

bars = client.get_option_bars(request_params)

# convert to dataframe
bars = bars.df

# access bars as list - important to note that you must access by symbol key
# even for a single symbol request - models are agnostic to number of symbols
bars.head()
