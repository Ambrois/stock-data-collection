import asyncio
import json
import os
import websockets
import time
import json


REPORT_EVERY = 10.0  # seconds

ALPACA_KEY = os.environ["ALPACAMARKETS_API_KEY"]
ALPACA_SECRET = os.environ["ALPACAMARKETS_SECRET_KEY"]

# Pick one feed:
#   v2/sip, v2/iex, v2/delayed_sip, v1beta1/boats, v1beta1/overnight
WS_URL = "wss://stream.data.alpaca.markets/v2/iex"

async def alpaca_stream():

    msg_count = 0
    byte_count = 0
    last_report = time.monotonic()

    async with websockets.connect(WS_URL, 
                                  ping_interval=20, 
                                  ping_timeout=20) as ws:
        # 1) Authenticate
        await ws.send(json.dumps({
            "action": "auth",
            "key": ALPACA_KEY,
            "secret": ALPACA_SECRET,
        }))

        # Read auth response(s)
        auth_resp = await ws.recv()
        print("AUTH:", auth_resp)

        # 2) Subscribe
        await ws.send(json.dumps({
            "action": "subscribe",
            "quotes": ["SPY"],
            "statuses": ["*"],
        }))

        sub_resp = await ws.recv()
        print("SUB:", sub_resp)

        # 3) Consume messages forever
        async for raw in ws:
            now = time.monotonic()

            # Alpaca sends arrays of messages
            byte_count += len(raw) 
            msgs = json.loads(raw)
            msg_count += len(msgs) 

            for m in msgs:
                t = m.get("T")
                if t == "q":  # quote
                    # print(f'QUOTE {m["S"]} bid={m["bp"]}@{m["bs"]} ask={m["ap"]}@{m["as"]} time={m["t"]}')
                    pass
                elif t in ("b", "u", "d"):  # bar / updatedBar / dailyBar
                    print(f'BAR({t}) {m["S"]} o={m["o"]} h={m["h"]} l={m["l"]} c={m["c"]} v={m["v"]} t={m["t"]}')
                else:
                    # statuses, LULDs, corrections, cancel/errors, etc.
                    print("OTHER:", m)

            if now - last_report >= REPORT_EVERY:
                mps = msg_count / (now - last_report)
                bps = byte_count / (now - last_report)

                print(f"{mps:.1f} msgs/sec | {bps/1e6:.2f} MB/sec")

                msg_count = 0
                byte_count = 0
                last_report = now

async def main():
    # simple reconnect loop
    while True:
        try:
            await alpaca_stream()
        except Exception as e:
            print("Disconnected:", repr(e))
            await asyncio.sleep(2)

if __name__ == "__main__":
    asyncio.run(main())

