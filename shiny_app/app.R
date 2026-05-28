library(shiny)
library(bslib)
library(tidyverse)
library(dygraphs)
library(xts)
library(DBI)
library(RPostgres)

ui <- page_fluid(
  title = "Dashboard",
  tags$head(
    tags$style(HTML("
      .null-values-card .card-body {
        padding-top: 0.75rem;
      }

      .null-values-card table {
        width: 100%;
        margin-bottom: 0;
        font-size: 1rem;
        line-height: 1.25;
      }

      .null-values-card th,
      .null-values-card td {
        padding: 0.35rem 0.5rem;
        vertical-align: middle;
      }
    "))
  ),
  
  theme = bs_theme(
    version = 5,
    bootswatch = "sandstone"
  ),
  
  navset_tab(
    
    nav_panel(
      "Stock Info",
      
      page_sidebar(
        sidebar = sidebar(
          selectizeInput(inputId = "symbols",
                      label = "Symbol",
                      choices = NULL,
                      selected = NULL,
                      multiple = TRUE,
                      options = list(maxItems=3)),
          dateRangeInput(
            inputId = "date_range",
            label = "Date Range",
            start = Sys.Date() - 30,
            end = Sys.Date()
          )
        ),
        
        ## Data
        layout_columns(
          value_box("Queried Row Count", textOutput("queried_row_count")),
          value_box("Latest Timestamp", textOutput("queried_latest_ts")),
          value_box("Duplicated Rows Count", textOutput("queried_duplicate_row_count"))
        ),
        card(
          class = "null-values-card",
          card_header("Null Values"),
          tableOutput("queried_null_values")
        ),
        
        ## Charts
        card(
          uiOutput("chart_stack")
        )
        
      )
    ),
    
    nav_panel(
      "DataBase Info",
      
      layout_columns(
        value_box("Approximate Total Row Count", textOutput("total_row_count")),
        value_box("Unique Symbol Count", textOutput("available_symbol_count")),
        value_box("Latest Timestamp", textOutput("total_latest_ts")),
        value_box("Duplicated Rows Count", textOutput("total_duplicate_row_count"))
      ),
      
      card(
        class = "null-values-card",
        card_header("Null Values"),
        tableOutput("total_null_values")
      )
      
      # TODO add last-updated status, database size, available size in disk.
    )
  )
)

local_candlestick_plotter_path <- function() {
  candidates <- c(
    file.path("www", "candlestick-auto-width.js"),
    file.path("shiny_app", "www", "candlestick-auto-width.js")
  )

  path <- candidates[file.exists(candidates)][1]

  if (is.na(path)) {
    stop("Unable to find candlestick-auto-width.js", call. = FALSE)
  }

  path
}

dyAutoWidthCandlestick <- function(dygraph) {
  dyPlotter(
    dygraph = dygraph,
    name = "AutoWidthCandlestickPlotter",
    path = local_candlestick_plotter_path(),
    version = "1.0"
  )
}

server <- function(input, output, session) {
  
  # Setup
  
  con <- dbConnect(
    RPostgres::Postgres(),
    dbname = "stockdb",
    host = "localhost",
    port = 5432,
    user = "shiny_app",
    password = Sys.getenv("STOCKDB_SHINY_PASS")
  )

  session$onSessionEnded(
    function() { dbDisconnect(con) }
  )

  # Configuration

  market_tz <- "America/New_York"
  query_start_time <- "07:00:00"  ### market starts at 7:30 but wanna overestimate bounds
  query_end_time <- "20:00:00"
  candle_sizes_minutes <- c(
    1, 2, 5, 10, 15, 30, 60,
    60 * 2,
    60 * 4,
    60 * 6.5,
    60 * 13,
    60 * 6.5 * 5
  )
  target_max_visible_candles <- 300
  
  ## Get available symbols
  available_symbols <- dbGetQuery(con, 
    " SELECT symbol FROM symbols ORDER BY symbol; "
  )$symbol
  
  ## For Sidebar:
  session$onFlushed(function() {
    updateSelectizeInput(
      session,
      inputId = "symbols",
      choices = available_symbols,
      selected = head(available_symbols, 2),
      server = TRUE
    )
  }, once = TRUE)
  
  
  # Data Helpers

  date_window_for_range <- function(date_range) {
    list(
      start = as.POSIXct(
        paste(date_range[1], query_start_time),
        tz = market_tz
      ),
      end = as.POSIXct(
        paste(date_range[2], query_end_time),
        tz = market_tz
      )
    )
  }
  
  get_bars <- function(symbols, start_date, end_date) {
    
    # convert date to unix minutes
    date_window <- date_window_for_range(c(start_date, end_date))
    
    start_ts <- floor(as.numeric(date_window$start) / 60)
    end_ts <- ceiling(as.numeric(date_window$end) / 60)
    
    # querying data
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
    
    ## convert time from unix min to POSIXct
    data_unix_min |> 
      mutate(ts = as.POSIXct(ts * 60, origin="1970-01-01", tz="UTC"))
    
  }
  
  ## Get bars data for selected symbols
  bars_data <- reactive({
    req(input$symbols)
    req(input$date_range)
    
    get_bars(
      symbols = input$symbols,
      start_date = input$date_range[1],
      end_date = input$date_range[2]
    )
  })

  # Chart Helpers

  choose_candle_minutes <- function(visible_start, visible_end) {
    visible_minutes <- as.numeric(difftime(
      visible_end,
      visible_start,
      units = "mins"
    ))

    if (is.na(visible_minutes) || visible_minutes <= 0) {
      return(1)
    }

    min_candle_size <- ceiling(visible_minutes / target_max_visible_candles)
    chosen_size <- candle_sizes_minutes[candle_sizes_minutes >= min_candle_size][1]

    if (is.na(chosen_size)) {
      return(tail(candle_sizes_minutes, 1))
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

  # dyRangeSelector wraps zoomCallback without preserving the dygraph instance.
  # drawCallback receives the graph directly and fires after zoom/pan redraws.
  chart_zoom_draw_callback <- htmlwidgets::JS(
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

  # Reactives and Chart State

  selected_date_window <- reactive({
    req(input$date_range)

    date_window_for_range(input$date_range)
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
  
  
  # UI Outputs
  
  ## Outputs for "Stock Info" Page
  
  ### Charts
  make_card <- function(symbol) {
    card( dygraphOutput( paste0(symbol, "_candles") ) )
  }
  
  output$chart_stack <- renderUI({
    req(input$symbols)
    tagList( 
      !!! lapply(input$symbols, make_card)  ### '!!!' is arg unpacking
      )
  })
  
  #### whenever an input (symbol, date range) changes,
  ####   update the relevant charts
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
            visible_end = visible_range$end
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
  
  ### Queried Data Summaries
  
  output$queried_row_count <- renderText({
    format(nrow(bars_data()), big.mark = ",")
  })
  
  output$queried_latest_ts <- renderText({
    df <- bars_data()
    req(nrow(df) > 0)
    as.character(max(df$ts, na.rm = TRUE))
  })
  
  output$queried_duplicate_row_count <- renderText({
    n_dup <- bars_data() |> 
      count(symbol, ts, name = "size") |> 
      filter(size > 1) |> 
      summarize(total = sum(size - 1), .groups = "drop") |> 
      pull(total)
    
    format(n_dup, big.mark = ",")
  })
  
  output$queried_null_values <- renderTable({
    df <- bars_data()
    validate( need(nrow(df) > 0, "No rows queried.") ) 
    df |> 
      group_by(symbol) |> 
      summarize(across(everything(), ~ sum(is.na(.))))
  })

  
  ## Outputs for "DataBase Info" Page
  
  output$total_row_count <- renderText({
    result <- dbGetQuery(con,
    "
      SELECT reltuples::bigint AS estimated_rows
      FROM pg_class
      WHERE oid = 'public.hist_minutely_bars'::regclass;
    ")
    
    if (nrow(result) <= 0 || is.na(result$estimated_rows[1])) {
      return("Unavailable")
    }
    
    n <- result$estimated_rows[1]
    format(n, big.mark = ",", scientific = FALSE)
  })
  
  output$available_symbol_count <- renderText({
    format(length(available_symbols), big.mark=",")
  })
  
  output$total_latest_ts <- renderText({"Placeholder"})
  output$total_duplicate_row_count <- renderText({"Placeholder"})
  output$total_null_values <- renderTable({data.frame( Place = c("Holder") )})
  
}


shinyApp(ui, server)
