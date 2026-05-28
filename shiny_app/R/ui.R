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
      "))
    ),

    theme = bs_theme(
      version = 5,
      bootswatch = "sandstone"
    ),

    navset_tab(
      nav_panel(
        "Stock View",

        page_sidebar(
          sidebar = sidebar(
            selectizeInput(
              inputId = "symbols",
              label = "Symbols (up to 3)",
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

          card(
            uiOutput("chart_stack")
          ),

          card(
            card_header("Overview"),
            layout_columns(
              value_box("Queried Row Count", textOutput("queried_row_count")),
              value_box("Latest Timestamp (PT)", textOutput("queried_latest_ts"))
            )
          ),
          card(
            class = "null-values-card",
            card_header("Missing Values"),
            tableOutput("queried_null_values")
          )
        )
      ),

      nav_panel(
        "DataBase Info",

        card(
          card_header("System Status"),
          layout_columns(
            card(
              card_header("PostgreSQL"),
              textOutput("postgres_status", inline = TRUE),
            ),
            card(
              card_header("Last Ingest Result"),
              textOutput("update_result", inline = TRUE),
            ),
            card(
              card_header("Last Ingest Time"),
              textOutput("update_start_time", inline = TRUE),
            ),
            card(
              card_header("Next Ingest Time"),
              textOutput("next_update")
            ),
            card(
              card_header("Status Page Refreshed"),
              textOutput("page_refreshed")
            )
          )
        ),

        card(
          card_header("Overview"),
          layout_columns(
            value_box("Estimated Total Row Count", textOutput("total_row_count")),
            value_box("Unique Symbol Count", textOutput("available_symbol_count")),
            value_box("Earliest Timestamp (PT)", textOutput("total_ts_start")),
            value_box("Latest Timestamp (PT)", textOutput("total_ts_end"))
          )
        ),

        card(
          card_header("Storage"),
          layout_columns(
            value_box("Table Size", textOutput("table_size")),
            value_box("Index Size", textOutput("index_size")),
            value_box("Total Size", textOutput("total_size")),
            value_box(
              "Timescale Chunk Count",
              textOutput("chunk_count")
            ),
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

      )
    )
  )
}
