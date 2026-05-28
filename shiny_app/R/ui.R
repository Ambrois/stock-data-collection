create_app_ui <- function() {
  page_fluid(
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

        .scrollable-table-card {
          max-height: 28rem;
          overflow: auto;
        }

        .scrollable-table-card table {
          margin-bottom: 0;
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
            selectizeInput(
              inputId = "symbols",
              label = "Symbol",
              choices = NULL,
              selected = NULL,
              multiple = TRUE,
              options = list(maxItems = 3)
            ),
            dateRangeInput(
              inputId = "date_range",
              label = "Date Range",
              start = Sys.Date() - 30,
              end = Sys.Date()
            )
          ),

          layout_columns(
            value_box("Queried Row Count", textOutput("queried_row_count")),
            value_box("Latest Timestamp (PT)", textOutput("queried_latest_ts"))
          ),
          card(
            class = "null-values-card",
            card_header("Null Values"),
            tableOutput("queried_null_values")
          ),
          card(
            uiOutput("chart_stack")
          )
        )
      ),

      nav_panel(
        "DataBase Info",

        card(
          card_header("Overview"),
          layout_columns(
            value_box("Estimated Total Row Count", textOutput("total_row_count")),
            value_box("Unique Symbol Count", textOutput("available_symbol_count")),
            value_box("Timestamp Range (PT)", textOutput("total_ts_range"))
          )
        ),

        card(
          card_header("Storage"),
          layout_columns(
            value_box("Table Size", textOutput("table_size")),
            value_box("Index Size", textOutput("index_size")),
            value_box("Total Size", textOutput("total_size"))
          )
        ),

        card(
          card_header("Timescale Chunks"),
          layout_columns(
            value_box("Chunk Count", textOutput("chunk_count")),
            value_box("Chunk Range (PT)", textOutput("chunk_range"))
          ),
          div(
            class = "scrollable-table-card",
            tableOutput("chunk_details")
          )
        ),

        card(
          class = "null-values-card",
          card_header("Data Quality"),
          tableOutput("total_null_values")
        )

        # TODO add last-updated status, database size, available size in disk.
      )
    )
  )
}
