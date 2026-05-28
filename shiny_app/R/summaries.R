register_summary_outputs <- function(
    input,
    output,
    con,
    bars_data,
    available_symbols) {
  output$queried_row_count <- renderText({
    format(nrow(bars_data()), big.mark = ",")
  })

  output$queried_latest_ts <- renderText({
    df <- bars_data()
    req(nrow(df) > 0)
    as.character(max(df$ts, na.rm = TRUE))
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

  output$total_latest_ts <- renderText({
    latest_ts <- get_total_latest_ts(con)

    if (is.na(latest_ts)) {
      return("Unavailable")
    }

    as.character(latest_ts)
  })

  output$total_null_values <- renderTable({
    data.frame(Place = c("Holder"))
  })
}
