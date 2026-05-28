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
      SELECT SUM(GREATEST(c.reltuples, 0))::bigint AS estimated_rows
      FROM timescaledb_information.chunks ch
      JOIN pg_class c
        ON c.oid = format('%I.%I', ch.chunk_schema, ch.chunk_name)::regclass
      WHERE ch.hypertable_schema = 'public'
        AND ch.hypertable_name = 'hist_minutely_bars';
    "
  )

  if (nrow(result) <= 0 || is.na(result$estimated_rows[1])) {
    return(NA)
  }

  result$estimated_rows[1]
}

get_total_timestamp_range <- function(con) {
  result <- dbGetQuery(
    con,
    "
      SELECT MIN(ts) AS min_ts, MAX(ts) AS max_ts
      FROM hist_minutely_bars;
    "
  )

  if (
    nrow(result) <= 0 ||
    is.na(result$min_ts[1]) ||
    is.na(result$max_ts[1])
  ) {
    return(NULL)
  }

  list(
    start = format_unix_minute(result$min_ts[1]),
    end = format_unix_minute(result$max_ts[1])
  )
}

get_database_storage_stats <- function(con) {
  result <- dbGetQuery(
    con,
    "
      SELECT
        pg_size_pretty(SUM(pg_relation_size(
          format('%I.%I', chunk_schema, chunk_name)::regclass
        ))::bigint) AS table_size,
        pg_size_pretty(SUM(pg_indexes_size(
          format('%I.%I', chunk_schema, chunk_name)::regclass
        ))::bigint) AS index_size,
        pg_size_pretty(SUM(pg_total_relation_size(
          format('%I.%I', chunk_schema, chunk_name)::regclass
        ))::bigint) AS total_size
      FROM timescaledb_information.chunks
      WHERE hypertable_schema = 'public'
        AND hypertable_name = 'hist_minutely_bars';
    "
  )

  if (nrow(result) <= 0) {
    return(data.frame(table_size = NA, index_size = NA, total_size = NA))
  }

  result
}

get_chunk_summary <- function(con) {
  result <- dbGetQuery(
    con,
    "
      SELECT
        COUNT(*) AS chunk_count,
        MIN(range_start_integer) AS min_range_start,
        MAX(range_end_integer) AS max_range_end
      FROM timescaledb_information.chunks
      WHERE hypertable_schema = 'public'
        AND hypertable_name = 'hist_minutely_bars';
    "
  )

  if (
    nrow(result) <= 0 ||
    is.na(result$chunk_count[1]) ||
    result$chunk_count[1] <= 0
  ) {
    return(NULL)
  }

  list(
    chunk_count = as.numeric(result$chunk_count[1]),
    range_start = format_unix_minute(result$min_range_start[1]),
    range_end = format_unix_minute(result$max_range_end[1])
  )
}

get_chunk_details <- function(con) {
  result <- dbGetQuery(
    con,
    "
      SELECT
        ch.chunk_name,
        ch.range_start_integer,
        ch.range_end_integer,
        GREATEST(c.reltuples, 0)::bigint AS estimated_rows,
        pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
      FROM timescaledb_information.chunks ch
      JOIN pg_class c
        ON c.oid = format('%I.%I', ch.chunk_schema, ch.chunk_name)::regclass
      WHERE ch.hypertable_schema = 'public'
        AND ch.hypertable_name = 'hist_minutely_bars'
      ORDER BY ch.range_start_integer;
    "
  )

  if (nrow(result) <= 0) {
    return(result)
  }

  result |>
    mutate(
      range_start = format_unix_minute(.data$range_start_integer),
      range_end = format_unix_minute(.data$range_end_integer),
      estimated_rows = paste0(
        "~",
        format(as.numeric(.data$estimated_rows), big.mark = ",", scientific = FALSE)
      )
    ) |>
    select(
      Chunk = "chunk_name",
      `Range Start` = "range_start",
      `Range End` = "range_end",
      `Estimated Rows` = "estimated_rows",
      `Total Size` = "total_size"
    )
}

format_unix_minute <- function(unix_minute) {
  format(
    as.POSIXct(
      as.numeric(unix_minute) * 60,
      origin = "1970-01-01",
      tz = "America/Los_Angeles"
    ),
    "%Y-%m-%d %H:%M:%S"
  )
}

format_timestamp <- function(timestamp) {
  format(
    as.POSIXct(timestamp, tz = "America/Los_Angeles"),
    "%Y-%m-%d %H:%M:%S"
  )
}

run_systemctl <- function(args) {
  output <- system2(
    "systemctl",
    args = args,
    stdout = TRUE,
    stderr = TRUE
  )
  paste(output, collapse = "\n")
}
