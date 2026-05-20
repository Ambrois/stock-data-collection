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
        verbatimTextOutput("quality_checks")
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
    data_unix_min <- dbGetQuery(con, 
      "
      SELECT *
      FROM hist_minutely_bars
      WHERE symbol = ANY($1::text[])
        AND ts >= $2
        AND ts < $3
      ORDER BY symbol, ts;
      ", params = list(symbols, start_ts, end_ts))
    
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
        output_id <- paste0(this_symbol, "_candles")
        
        output[[output_id]] <- renderDygraph({
          df <- bars_data() |>
            filter(.data$symbol == this_symbol)
          
          validate(
            need(nrow(df) > 0, paste("No data found for", this_symbol))
          )
          
          ohlc <- xts(
            x = df[, c("open", "high", "low", "close")],
            order.by = df$ts
          )
          
          dygraph(ohlc, main = this_symbol, group = "charts") |> 
            dyCandlestick(compress = TRUE) |> 
            dyRangeSelector()
        })
      })
    })
  })
  

  ## Outputs for "Data" Page
  
  output$approx_total_rows <- renderText({
    "1,234,567"  ### TODO
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
  
  output$quality_checks <- renderPrint({
    n_duplicated_rows <- bars_data() |> 
      group_by(symbol, ts) |> 
      summarize(size = n()) |> 
      filter(size > 1) |> 
      count()
    
    null_vals <- bars_data() |> 
      summarize(across(everything(), ~ sum(is.na(.))))
    
    ### TODO how many minutes are accounted for?
    ###   should be the row count divided by the theoretical number of market minutes
    ###   within the timespan
    
    list(n_duplicated_rows, null_vals)
  })
}


shinyApp(ui, server)