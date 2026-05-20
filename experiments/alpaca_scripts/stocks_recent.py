from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockLatestQuoteRequest
import os

api_key = os.getenv("ALPACAMARKETS_API_KEY")
secret_key = os.getenv("ALPACAMARKETS_SECRET_KEY")

client = StockHistoricalDataClient(api_key, secret_key)

multisymbol_request_params = StockLatestQuoteRequest(symbol_or_symbols=["SPY", "GLD", "TLT"])

latest_multisymbol_quotes = client.get_stock_latest_quote(multisymbol_request_params)

spy_latest_ask_price = latest_multisymbol_quotes["SPY"].ask_price
