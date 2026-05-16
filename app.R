library(shiny)
library(bslib)
library(tidyverse)
library(dygraphs)
library(xts)

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
  
  output$total_rows <- renderText({
    "1,234,567"
  })
  
  output$num_symbols <- renderText({
    "503"
  })
  
  output$latest_ts <- renderText({
    as.character(Sys.time())
  })
  
  
  make_card <- function(symbol) {
    card( dygraphOutput( paste0(symbol, "_candles") ) )
  }
  
  output$chart_stack <- renderUI({
    tagList( 
      !!! lapply(input$symbols, make_card)  #!!! is arg unpacking
      )
  })
  
  
  # whenever an input (symbol, date range) changes,
  #   update the relevant charts
  observe({
    
    lapply(
      input$symbols, 
      function(symbol) {
        # do this for each input symbol
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
  

  output$quality_checks <- renderPrint({
    list(
      duplicate_rows = 0,
      stale_symbols = 3,
      status = "Using fake data for now"
    )
  })
}

shinyApp(ui, server)