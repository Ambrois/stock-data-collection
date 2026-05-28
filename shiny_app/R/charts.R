local_candlestick_plotter_path <- function() {
  app_file_path("www", "candlestick-auto-width.js")
}

dyAutoWidthCandlestick <- function(dygraph) {
  dyPlotter(
    dygraph = dygraph,
    name = "AutoWidthCandlestickPlotter",
    path = local_candlestick_plotter_path(),
    version = "1.0"
  )
}

choose_candle_minutes <- function(visible_start, visible_end, config) {
  visible_minutes <- as.numeric(difftime(
    visible_end,
    visible_start,
    units = "mins"
  ))

  if (is.na(visible_minutes) || visible_minutes <= 0) {
    return(1)
  }

  min_candle_size <- ceiling(visible_minutes / config$target_max_visible_candles)
  chosen_size <- config$candle_sizes_minutes[
    config$candle_sizes_minutes >= min_candle_size
  ][1]

  if (is.na(chosen_size)) {
    return(tail(config$candle_sizes_minutes, 1))
  }

  chosen_size
}

aggregate_ohlc <- function(df, candle_minutes) {
  if (candle_minutes <= 1) {
    return(df |> arrange(.data$ts))
  }

  candle_seconds <- candle_minutes * 60

  df |>
    arrange(.data$ts) |>
    mutate(
      candle_ts = as.POSIXct(
        floor(as.numeric(.data$ts) / candle_seconds) * candle_seconds,
        origin = "1970-01-01",
        tz = "UTC"
      )
    ) |>
    group_by(.data$symbol, .data$candle_ts) |>
    summarize(
      ts = dplyr::first(.data$candle_ts),
      open = dplyr::first(.data$open),
      high = max(.data$high, na.rm = TRUE),
      low = min(.data$low, na.rm = TRUE),
      close = dplyr::last(.data$close),
      .groups = "drop"
    ) |>
    arrange(.data$symbol, .data$ts)
}

create_chart_zoom_draw_callback <- function() {
  # dyRangeSelector wraps zoomCallback without preserving the dygraph instance.
  # drawCallback receives the graph directly and fires after zoom/pan redraws.
  htmlwidgets::JS(
    "function(graph, isInitial) {
      if (!graph || !graph.xAxisRange) {
        return;
      }

      var el = graph.maindiv_;

      while (el && !/_candles$/.test(el.id)) {
        el = el.parentElement;
      }

      if (!el) {
        return;
      }

      var outputId = el.id.replace(/_candles$/, '');
      var range = graph.xAxisRange();

      if (!range || range.length !== 2) {
        return;
      }

      if (!window.stockChartZoomTimers) {
        window.stockChartZoomTimers = {};
      }

      clearTimeout(window.stockChartZoomTimers[outputId]);
      window.stockChartZoomTimers[outputId] = setTimeout(function() {
        Shiny.setInputValue('chart_zoom', {
          id: outputId,
          min: range[0],
          max: range[1],
          nonce: Math.random()
        }, {priority: 'event'});
      }, 200);
    }"
  )
}

make_chart_card <- function(symbol) {
  card(dygraphOutput(paste0(symbol, "_candles")))
}

register_chart_outputs <- function(
    input,
    output,
    bars_data,
    selected_date_window,
    zoom_ranges,
    config) {
  chart_zoom_draw_callback <- create_chart_zoom_draw_callback()

  output$chart_stack <- renderUI({
    req(input$symbols)
    do.call(tagList, lapply(input$symbols, make_chart_card))
  })

  observe({
    req(input$symbols)

    lapply(input$symbols, function(this_symbol) {
      local({
        symbol_now <- this_symbol
        output_id <- paste0(symbol_now, "_candles")

        output[[output_id]] <- renderDygraph({
          df <- bars_data() |>
            filter(.data$symbol == symbol_now)

          validate(
            need(nrow(df) > 0, paste("No data found for", symbol_now))
          )

          visible_range <- zoom_ranges[[symbol_now]]

          if (is.null(visible_range)) {
            visible_range <- selected_date_window()
          }

          candle_minutes <- choose_candle_minutes(
            visible_start = visible_range$start,
            visible_end = visible_range$end,
            config = config
          )

          df <- aggregate_ohlc(df, candle_minutes)

          ohlc <- xts(
            x = df[, c("open", "high", "low", "close")],
            order.by = df$ts
          )

          dygraph(ohlc, main = symbol_now, group = "charts") |>
            dyAutoWidthCandlestick() |>
            dyRangeSelector(retainDateWindow = TRUE) |>
            dyCallbacks(drawCallback = chart_zoom_draw_callback)
        })
      })
    })
  })
}
