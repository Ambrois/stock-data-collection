connect_stock_db <- function() {
  dbConnect(
    RPostgres::Postgres(),
    dbname = "stockdb",
    host = "localhost",
    port = 5432,
    user = "shiny_app",
    password = Sys.getenv("STOCKDB_SHINY_PASS")
  )
}

date_window_for_range <- function(date_range, config) {
  list(
    start = as.POSIXct(
      paste(date_range[1], config$query_start_time),
      tz = config$market_tz
    ),
    end = as.POSIXct(
      paste(date_range[2], config$query_end_time),
      tz = config$market_tz
    )
  )
}

get_available_symbols <- function(con) {
  dbGetQuery(con, " SELECT symbol FROM symbols ORDER BY symbol; ")$symbol
}

get_bars <- function(con, symbols, start_date, end_date, config) {
  date_window <- date_window_for_range(c(start_date, end_date), config)

  start_ts <- floor(as.numeric(date_window$start) / 60)
  end_ts <- ceiling(as.numeric(date_window$end) / 60)

  data_unix_min <- dbGetQuery(
    con,
    "
      SELECT *
      FROM hist_minutely_bars
      WHERE symbol = ANY(string_to_array($1, ','))
        AND ts >= $2
        AND ts < $3
      ORDER BY symbol, ts;
    ",
    params = list(
      paste(symbols, collapse = ","),
      start_ts,
      end_ts
    )
  )

  data_unix_min |>
    mutate(ts = as.POSIXct(ts * 60, origin = "1970-01-01", tz = "UTC"))
}

get_total_row_count <- function(con) {
  result <- dbGetQuery(
    con,
    "
      SELECT reltuples::bigint AS estimated_rows
      FROM pg_class
      WHERE oid = 'public.hist_minutely_bars'::regclass;
    "
  )

  if (nrow(result) <= 0 || is.na(result$estimated_rows[1])) {
    return(NA)
  }

  result$estimated_rows[1]
}
