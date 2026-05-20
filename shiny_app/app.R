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
        value_box("Null Values", tableOutput("queried_null_values")),
        
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
      
      value_box("Null Values", tableOutput("total_null_values"))
      
      # TODO add last-updated status, database size, available size in disk.
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
    password = Sys.getenv("STOCKDB_SHINY_PASS")
  )

  session$onSessionEnded(
    function() { dbDisconnect(con) }
  )
  
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
  
  
  ## For Main Section:
  
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
    format(length(available_symbol), big.mark=",")
  })
  
  output$total_latest_ts <- renderText({"Placeholder"})
  output$total_duplicate_row_count <- renderText({"Placeholder"})
  output$total_null_values <- renderTable({data.frame( Place = c("Holder") )})
  
}


shinyApp(ui, server)
