library(shiny)
library(bslib)
library(tidyverse)
library(dygraphs)
library(xts)
library(DBI)
library(RPostgres)

app_file_path <- function(...) {
  relative_path <- file.path(...)
  candidates <- c(
    relative_path,
    file.path("shiny_app", relative_path)
  )

  path <- candidates[file.exists(candidates)][1]

  if (is.na(path)) {
    stop("Unable to find app file: ", relative_path, call. = FALSE)
  }

  path
}

source_app_file <- function(...) {
  source(app_file_path(...), local = parent.frame())
}

source_app_file("R", "ui.R")
source_app_file("R", "data.R")
source_app_file("R", "charts.R")
source_app_file("R", "summaries.R")

app_config <- list(
  market_tz = "America/New_York",
  # Market starts at 7:30, but query a wider bound.
  query_start_time = "07:00:00",
  query_end_time = "20:00:00",
  candle_sizes_minutes = c(
    1, 2, 5, 10, 15, 30, 60,
    60 * 2,
    60 * 4,
    60 * 6.5,
    60 * 13,
    60 * 6.5 * 5
  ),
  target_max_visible_candles = 300
)

ui <- create_app_ui()

server <- function(input, output, session) {
  con <- connect_stock_db()

  session$onSessionEnded(function() {
    dbDisconnect(con)
  })

  available_symbols <- get_available_symbols(con)

  session$onFlushed(function() {
    updateSelectizeInput(
      session,
      inputId = "symbols",
      choices = available_symbols,
      selected = head(available_symbols, 2),
      server = TRUE
    )
  }, once = TRUE)

  bars_data <- reactive({
    req(input$symbols)
    req(input$date_range)

    get_bars(
      con = con,
      symbols = input$symbols,
      start_date = input$date_range[1],
      end_date = input$date_range[2],
      config = app_config
    )
  })

  selected_date_window <- reactive({
    req(input$date_range)

    date_window_for_range(input$date_range, app_config)
  })

  zoom_ranges <- reactiveValues()

  selected_symbols_or_empty <- reactive({
    selected_symbols <- input$symbols

    if (!is.null(selected_symbols)) {
      return(selected_symbols)
    }

    character()
  })

  observeEvent(input$symbols, {
    selected_symbols <- selected_symbols_or_empty()

    for (name in names(reactiveValuesToList(zoom_ranges))) {
      if (!name %in% selected_symbols) {
        zoom_ranges[[name]] <- NULL
      }
    }
  })

  observeEvent(input$date_range, {
    for (symbol in selected_symbols_or_empty()) {
      zoom_ranges[[symbol]] <- NULL
    }
  })

  observeEvent(input$chart_zoom, {
    zoom <- input$chart_zoom
    req(zoom$id)
    req(zoom$min)
    req(zoom$max)

    selected_symbols <- selected_symbols_or_empty()

    if (length(selected_symbols) <= 0) {
      selected_symbols <- zoom$id
    }

    zoom_range <- list(
      start = as.POSIXct(zoom$min / 1000, origin = "1970-01-01", tz = "UTC"),
      end = as.POSIXct(zoom$max / 1000, origin = "1970-01-01", tz = "UTC")
    )

    for (symbol in selected_symbols) {
      old_range <- zoom_ranges[[symbol]]

      if (
        is.null(old_range) ||
        abs(as.numeric(difftime(old_range$start, zoom_range$start, units = "secs"))) > 1 ||
        abs(as.numeric(difftime(old_range$end, zoom_range$end, units = "secs"))) > 1
      ) {
        zoom_ranges[[symbol]] <- zoom_range
      }
    }
  })

  register_chart_outputs(
    input = input,
    output = output,
    bars_data = bars_data,
    selected_date_window = selected_date_window,
    zoom_ranges = zoom_ranges,
    config = app_config
  )

  register_summary_outputs(
    input = input,
    output = output,
    con = con,
    bars_data = bars_data,
    available_symbols = available_symbols
  )
}

shinyApp(ui, server)
