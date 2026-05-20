library(shiny)
library(bslib)
library(tidyverse)
library(dygraphs)
library(xts)
library(DBI)
library(RPostgres)

ui <- page_fluid(
  title = "Dashboard",
  
  theme = bs_theme(
    version = 5,
    bootswatch = "sandstone"
  ),
  
  navset_tab(
    
    nav_panel(
      "Stocks",
      
      page_sidebar(
        sidebar = sidebar(
          selectizeInput(inputId = "symbols",
                      label = "Symbol",
                      choices = c("AAPL", "MSFT", "NVDA"),
                      selected = c("AAPL", "NVDA"),
                      multiple = TRUE,
                      options = list(maxItems=3)),
          dateRangeInput(
            inputId = "date_range",
            label = "Date Range",
            start = Sys.Date() - 90,
            end = Sys.Date()
          )
        ),
        
        
        card(
          uiOutput("chart_stack")
        )
      )
    ),
    
    nav_panel(
      "Data",
      
      layout_columns(
        value_box("Queried Row Count", textOutput("queried_rows")),
        value_box("Symbols", textOutput("num_symbols")),
        value_box("Latest Timestamp", textOutput("latest_ts")),
        value_box("Total DB Row Count Estimate", textOutput("approx_total_rows"))
      ),
      
      card(
        card_header("Data Quality Checks"),
        layout_columns(
          value_box("Duplicated Rows Count", textOutput("n_duplicated_rows")),
          value_box("Null Values By Symbol", tableOutput("null_values"))
        ),
      )
    )
  )
)

server <- function(input, output, session) {
  
  # Getting and Handling Data
  
  con <- dbConnect(
    RPostgres::Postgres(),
    dbname = "stockdb",
    host = "localhost",
    port = 5432,
    user = "shiny_app",
    password = Sys.getenv("STOCKDB_PASSWORD")
  )

  session$onSessionEnded(
    function() { dbDisconnect(con) }
  )
  
  get_bars <- function(symbols, start_date, end_date) {
    
    # convert date to unix minutes
    market_tz <- "America/New_York"
    
    start_dt <- as.POSIXct(
      paste(start_date, "07:00:00"),  ### market starts at 7:30 but wanna overestimate bounds
      tz = market_tz
    )
    
    end_dt <- as.POSIXct(
      paste(end_date, "20:00:00"),
      tz = market_tz
    )
    
    start_ts <- floor(as.numeric(start_dt) / 60)
    end_ts <- ceiling(as.numeric(end_dt) / 60)
    
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
  
  ## Get real data
  bars_data <- reactive({
    req(input$symbols)
    req(input$date_range)
    
    get_bars(
      symbols = input$symbols,
      start_date = input$date_range[1],
      end_date = input$date_range[2]
    )
  })
  
  
  # UI Outputs
  
  ## Outputs for "Stocks" Page
  
  make_card <- function(symbol) {
    card( dygraphOutput( paste0(symbol, "_candles") ) )
  }
  
  output$chart_stack <- renderUI({
    req(input$symbols)
    tagList( 
      !!! lapply(input$symbols, make_card)  ### '!!!' is arg unpacking
      )
  })
  
  ### whenever an input (symbol, date range) changes,
  ###   update the relevant charts
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
          
          ohlc <- xts(
            x = df[, c("open", "high", "low", "close")],
            order.by = df$ts
          )
          
          dygraph(ohlc, main = symbol_now, group = "charts") |> 
            dyCandlestick(compress = FALSE) |> 
            dyRangeSelector()
        })
      })
    })
  })
  

  ## Outputs for "Data" Page
  
  output$approx_total_rows <- renderText({
    result <- dbGetQuery(con,
      "
        SELECT reltuples::bigint AS estimated_rows
        FROM pg_class
        WHERE oid = 'hist_minutely_bars'::regclass;
      "
    )
    n <- result[[1]][1]
    format(n, big.mark=",", scientific = FALSE)
    
  })
  
  output$queried_rows <- renderText({
    format(nrow(bars_data()), big.mark = ",")
  })
  
  output$num_symbols <- renderText({
    format(n_distinct( bars_data()$symbol ), big.mark = ",")
  })
  
  output$latest_ts <- renderText({
    df <- bars_data()
    req(nrow(df) > 0)
    as.character(max(df$ts, na.rm = TRUE))
  })
  
  output$n_duplicated_rows <- renderText({
    n_dup <- bars_data() |> 
      group_by(symbol, ts) |> 
      summarize(size = n()) |> 
      filter(size > 1) |> 
      pull(n)
    
    format(n_dup, big.mark = ",")
  })
  
  output$null_values <- renderTable({
    bars_data() |> 
      group_by(symbol) |> 
      summarize(across(everything(), ~ sum(is.na(.))))
  })
}


shinyApp(ui, server)