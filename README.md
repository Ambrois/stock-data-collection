# Stock Data Collection

This repository is a working stock-market data collection and dashboard project. It pulls minute-level U.S. equity data from Alpaca, stores the normalized bars in a local PostgreSQL/TimescaleDB database, and serves a Shiny dashboard for inspecting the stored data. The live dashboard is available at https://stockdb.ambrois.uk.

The project is organized around three concerns:

- ingesting and backfilling stock bars
- storing those bars in a queryable time-series database
- visualizing and monitoring the database through a self-hosted Shiny app

## Data

The central dataset is minute OHLCV bar data for S&P 500 symbols. The active symbols are stored in `scripts/sp500_symbols_2026-05-13.txt`.

The main database table is `public.hist_minutely_bars`. The scripts treat `(symbol, ts)` as the unique row identity, where `ts` is a Unix epoch timestamp in minutes.

Expected bar columns:

- `symbol`: stock ticker
- `ts`: minute-level Unix timestamp
- `open`, `high`, `low`, `close`: OHLC prices
- `volume`: traded volume
- `tradecount`: number of trades
- `vwap`: volume-weighted average price

The Shiny app also expects a `symbols` table or view for populating symbol selectors.

## Ingestion Scripts

`scripts/get_recent_stock_bars.py` is the main updater. It uses Alpaca's historical stock data API, checks the latest stored timestamp for each symbol, requests bars beginning one minute after that point, and inserts new rows into PostgreSQL.

The insert path is built for large batches: rows are cleaned in pandas, written to an in-memory CSV buffer, copied into a temporary staging table with `psycopg`, and merged into `public.hist_minutely_bars` with `ON CONFLICT (symbol, ts) DO NOTHING`.

If a symbol has no existing data, the updater starts from January 1 of the year ten years before the current year. Progress logging includes the current symbol, percent complete, estimated remaining time, and estimated finish time.

## Shiny Dashboard

The dashboard lives in `shiny_app/`. `app.R` wires together the UI, database access, chart rendering, and summary outputs from the files under `shiny_app/R/`.

Main modules:

- `R/ui.R`: Shiny UI layout, tabs, cards, inputs, and status panels.
- `R/data.R`: PostgreSQL connection helpers, bar queries, Timescale chunk queries, storage stats, timestamp formatting, and systemd command helpers.
- `R/charts.R`: candlestick chart registration, OHLC aggregation, zoom synchronization, and adaptive candle sizing.
- `R/summaries.R`: queried-data summaries, database status outputs, storage outputs, and system status outputs.
- `www/candlestick-auto-width.js`: custom dygraphs candlestick plotter that adjusts candle body width based on visible point spacing.

The `Stock View` tab supports selecting up to three symbols and a date range. It renders synchronized candlestick charts with a range selector, aggregates candles as the visible range changes, and reports row counts, latest timestamps, and missing-value counts for the selected slice.

The `DataBase Info` tab reports broader operational status:

- PostgreSQL service status
- last ingest result and timestamp from `stockdb-update.service`
- next ingest time from `stockdb-update.timer`
- estimated total row count
- unique symbol count
- earliest and latest stored timestamps
- Timescale table, index, total size, chunk count, and per-chunk details

Some data-quality outputs are still placeholders.


## Experiments

The `experiments/` directory contains prototypes and one-off scripts used while building the ingestion and database workflow.

`experiments/psql_scripts/` includes:

- `get_hist_min_stock_bars_2016-2026.py`: historical backfill from January 1, 2016 onward.
- `get_past_week_min_stock_bars.py`: earlier SQLAlchemy-based recent-bar loader.
- `batch_migrate_to_timescale.fish`: weekly chunk migration from `hist_minutely_bars_old` into the active table.

`experiments/alpaca_scripts/` includes small Alpaca API probes:

- historical stock bars
- latest stock quotes
- live stock quote streaming
- direct websocket streaming and throughput reporting
- historical options bars

The repository also contains sample and scratch artifacts such as `experiments/SPY_minutely_2025-01-01_to_2026-01-01.csv`.

## Operations Notes

`docs/systemd-notes.md` documents a self-hosted deployment pattern for the Shiny app without including machine-specific hostnames, domains, paths, or secrets. The general route is:

```text
public DNS name
  -> HTTPS reverse proxy
  -> Shiny app service
  -> PostgreSQL/TimescaleDB
```

`scripts/cloudflare_ddns.sh` is an operational helper for the hosted dashboard. It updates the Cloudflare DNS record for `stockdb.ambrois.uk` when the host's public IPv4 address changes.
