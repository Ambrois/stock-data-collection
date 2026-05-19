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
        value_box("Total Rows", textOutput("total_rows")),
        value_box("Symbols", textOutput("num_symbols")),
        value_box("Latest Timestamp", textOutput("latest_ts"))
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
  
  # conn <- dbConnect(
  #   RPostgres::Postgres(),
  #   dbname = "stockdb",
  #   host = "localhost",
  #   port = 5432,
  #   user = "postgres",
  # )
  # 
  # session$OnSessionEnded(
  #   function() { dbDisconnect(con) }
  # )
  
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
      WHERE symbol = ANY($1)
        AND ts >= $2
        AND ts < $3
      ORDER BY symbol, ts;
      ", params = list(symbols, start_ts, end_ts))
    
    ## convert time from unix min to POSIXct
    data_unix_min |> 
      mutate(ts = as.POSIXct(ts * 60, origin="1970-01-01", tz="UTC"))
    
  }
  
  

  fake_data <- reactive({
    days <- seq(input$date_range[1], input$date_range[2], by = "day")
    n <- length(days)
    
    close <- cumsum(rnorm(n)) + 100
    open <- close + rnorm(n, sd = 0.5)
    spread <- runif(n, 0.5, 2)
    
    data.frame(
      day = days,
      open = round(open, 2),
      high = round(pmax(open, close) + spread, 2),
      low = round(pmin(open, close) - spread, 2),
      close = round(close, 2)
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
    
    lapply(
      input$symbols, 
      function(symbol) {
        ### do this for each input symbol
        output_id <- paste0(symbol, "_candles")
        
        output[[output_id]] <- renderDygraph({
          data <- fake_data()
          
          ohlc <- xts(
            x = data[, c("open", "high", "low", "close")],
            order.by = data$day
          )
          
          dygraph(ohlc, main = "Some Chart",
                  group = "charts") |> 
            dyCandlestick(compress = TRUE) |> 
            dyRangeSelector()         
        })
      }
    )
  })
  

  ## Outputs for "Data" Page
  output$total_rows <- renderText({
    "1,234,567"
  })
  
  output$num_symbols <- renderText({
    "503"
  })
  
  output$latest_ts <- renderText({
    as.character(Sys.time())
  })
  
  output$quality_checks <- renderPrint({
    list(
      duplicate_rows = 0,
      stale_symbols = 3,
      status = "Using fake data for now"
    )
  })
}

shinyApp(ui, server)