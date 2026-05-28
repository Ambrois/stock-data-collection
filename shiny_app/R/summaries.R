register_summary_outputs <- function(
    input,
    output,
    con,
    bars_data,
    available_symbols) {
  storage_stats <- get_database_storage_stats(con)
  chunk_summary <- get_chunk_summary(con)

  output$queried_row_count <- renderText({
    format(nrow(bars_data()), big.mark = ",")
  })

  output$queried_latest_ts <- renderText({
    df <- bars_data()
    req(nrow(df) > 0)
    format_timestamp(max(df$ts, na.rm = TRUE))
  })

  output$queried_null_values <- renderTable({
    df <- bars_data()
    validate(need(nrow(df) > 0, "No rows queried."))

    df |>
      group_by(symbol) |>
      summarize(across(everything(), ~ sum(is.na(.))))
  })

  output$total_row_count <- renderText({
    n <- get_total_row_count(con)

    if (is.na(n)) {
      return("Unavailable")
    }

    paste0("~", format(as.numeric(n), big.mark = ",", scientific = FALSE))
  })

  output$available_symbol_count <- renderText({
    format(length(available_symbols), big.mark = ",")
  })

  output$total_ts_start <- renderText({
    ts_range <- get_total_timestamp_range(con)

    if (is.null(ts_range)) {
      return("Unavailable")
    }

    ts_range$start
  })

  output$total_ts_end <- renderText({
    ts_range <- get_total_timestamp_range(con)

    if (is.null(ts_range)) {
      return("Unavailable")
    }

    ts_range$end
  })

  output$table_size <- renderText({
    storage_stats$table_size[1]
  })

  output$index_size <- renderText({
    storage_stats$index_size[1]
  })

  output$total_size <- renderText({
    storage_stats$total_size[1]
  })

  output$chunk_count <- renderText({
    if (is.null(chunk_summary)) {
      return("Unavailable")
    }

    format(chunk_summary$chunk_count, big.mark = ",")
  })

  output$chunk_range_start <- renderText({
    if (is.null(chunk_summary)) {
      return("Unavailable")
    }

    chunk_summary$range_start
  })

  output$chunk_range_end <- renderText({
    if (is.null(chunk_summary)) {
      return("Unavailable")
    }

    chunk_summary$range_end
  })

  output$total_null_values <- renderTable({
    data.frame(Place = c("Holder"))
  })

  output$chunk_details <- renderTable({
    get_chunk_details(con)
  })
}
