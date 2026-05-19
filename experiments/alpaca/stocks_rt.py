from alpaca.data.live import CryptoDataStream, OptionDataStream, StockDataStream
import os

api_key = os.getenv("ALPACAMARKETS_API_KEY")
secret_key = os.getenv("ALPACAMARKETS_SECRET_KEY")
stock_stream = StockDataStream(api_key, secret_key)


async def quote_data_handler(data):
    # quote data will arrive here
    print(data)

stock_stream.subscribe_quotes(quote_data_handler, "SPY")

stock_stream.run()


