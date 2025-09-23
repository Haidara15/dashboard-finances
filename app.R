# ==== Packages ====
library(shiny)
library(highcharter)
library(DT)
library(readr)
library(dplyr)
library(tidyr)
library(lubridate)
library(scales)
library(cachem)
library(digest)

# ==== data loader ====
load_finance_data <- function() {
  csv_path <- file.path("data", "finances.csv")
  if (file.exists(csv_path)) {
    df <- readr::read_csv(csv_path, show_col_types = FALSE)
  } else {
    set.seed(42)
    dates <- seq(as.Date("2024-01-01"), by = "month", length.out = 24)
    regions <- c("EMEA", "AMER", "APAC")
    categories <- c("SaaS", "Services", "Hardware")
    products <- c("Alpha", "Beta", "Gamma", "Delta")
    base <- expand.grid(date = dates, region = regions, category = categories, product = products)
    base <- base |>
      dplyr::mutate(
        revenue = round(runif(dplyr::n(), 5000, 55000) * (1 + as.numeric(format(date, "%m"))/24), 0),
        expenses = round(revenue * runif(dplyr::n(), 0.45, 0.85), 0)
      )
    df <- base |> dplyr::mutate(gp = revenue - expenses)
  }
  df |>
    dplyr::mutate(
      date = as.Date(date),
      year = lubridate::year(date),
      month = lubridate::floor_date(date, "month")
    ) |>
    dplyr::relocate(year, month, .after = date)
}
fin_data <- load_finance_data()

# ==== helpers ====
fmt_eur <- scales::label_dollar(prefix = "", big.mark = " ", suffix = " €", accuracy = 1)
fmt_pct <- scales::label_percent(accuracy = 0.1)
kpis <- function(df) {
  df |>
    dplyr::summarise(
      Revenue = sum(revenue, na.rm = TRUE),
      Expenses = sum(expenses, na.rm = TRUE),
      GP = sum(gp, na.rm = TRUE),
      Margin = ifelse(sum(revenue) > 0, sum(gp)/sum(revenue), NA_real_)
    )
}

# ==== UI ====
ui <- navbarPage(
  title = div(
    tags$img(src = "logo.png", height = 24, onerror="this.style.display='none'"),
    HTML("Finance Dashboard")
  ),
  header = tagList(
    tags$link(rel="stylesheet", type="text/css", href="styles.css"),
    tags$script(src="app.js")
  ),
  
  tabPanel(
    "Dashboard",
    div(class = "layout",
        
        div(class = "sidebar",
            h4("Filtres"),
            dateRangeInput("dater", "Période", start = min(fin_data$date), end = max(fin_data$date)),
            selectInput("region", "Région", choices = c("Toutes", sort(unique(fin_data$region))), selected = "Toutes"),
            selectInput("category", "Catégorie", choices = c("Toutes", sort(unique(fin_data$category))), selected = "Toutes"),
            selectInput("product", "Produit", choices = c("Tous", sort(unique(fin_data$product))), selected = "Tous"),
            checkboxInput("darkmode", "Mode sombre", value = FALSE),
            hr(),
            
            div(class = "btn-container",
                downloadButton("dl_csv", "Télécharger CSV"),
                actionButton("reset_filters", "Réinitialiser")
            )
            
            # downloadButton("dl_csv", "Télécharger CSV"),
            # actionButton("reset_filters", "Réinitialiser")
        ),
        
        div(class = "content",
            div(class = "kpi-row",
                div(class = "kpi", h6("Revenus"),  textOutput("kpi_rev")),
                div(class = "kpi", h6("Dépenses"), textOutput("kpi_exp")),
                div(class = "kpi", h6("Marge brute"), textOutput("kpi_gp")),
                div(class = "kpi", h6("Taux de marge"), textOutput("kpi_margin"))
            ),
            # Row 1
            div(class = "graph-row",
                div(class = "card", highchartOutput("ts_revenue", width = "100%", height = "360px")),
                div(class = "card", highchartOutput("bar_region", width = "100%", height = "360px"))
            ),
            # Row 2
            div(class = "graph-row",
                div(class = "card", highchartOutput("stack_category", width = "100%", height = "340px")),
                div(class = "card", highchartOutput("top_products", width = "100%", height = "340px"))
            )
        )
    )
  ),
  
  tabPanel(
    "Transactions",
    div(class = "content",
        div(class = "card",
            DT::DTOutput("tbl"),
            br(),
            div(style="display:flex; gap:.5rem; flex-wrap:wrap",
                downloadButton("dl_view", "Exporter la vue"),
                actionButton("reset_filters2", "Réinitialiser")
            ),
            hr(),
            h4("Infos dataset"),
            verbatimTextOutput("about")
        )
    )
  )
)

# ==== SERVER ====
server <- function(input, output, session) {
  
  # Dark mode
  observe({
    session$sendCustomMessage("toggle-dark", list(enable = isTRUE(input$darkmode)))
  })
  
  # Data filtrée
  r_filtered <- reactive({
    df <- fin_data |>
      dplyr::filter(date >= input$dater[1], date <= input$dater[2])
    if (input$region  != "Toutes") df <- df |> dplyr::filter(region == input$region)
    if (input$category != "Toutes") df <- df |> dplyr::filter(category == input$category)
    if (input$product != "Tous")   df <- df |> dplyr::filter(product == input$product)
    df
  })
  
  # KPIs
  observe({
    kp <- kpis(r_filtered())
    output$kpi_rev    <- renderText(fmt_eur(kp$Revenue))
    output$kpi_exp    <- renderText(fmt_eur(kp$Expenses))
    output$kpi_gp     <- renderText(fmt_eur(kp$GP))
    output$kpi_margin <- renderText(fmt_pct(kp$Margin))
  })
  
  # Graphiques
  output$ts_revenue <- renderHighchart({
    df <- r_filtered() |>
      dplyr::group_by(month) |>
      dplyr::summarise(Revenue = sum(revenue), .groups="drop")
    hchart(df, "line", hcaes(x = month, y = Revenue)) |>
      hc_title(text = "Revenus mensuels") |>
      hc_yAxis(labels = list(format = "{value:,.0f} €"))
  })
  
  output$bar_region <- renderHighchart({
    df <- r_filtered() |>
      dplyr::group_by(region) |>
      dplyr::summarise(Revenue = sum(revenue), GP = sum(gp), .groups="drop")
    highchart() |>
      hc_chart(type = "column") |>
      hc_add_series(data = df$Revenue, name = "Revenus", categories = df$region) |>
      hc_add_series(data = df$GP, name = "Marge brute") |>
      hc_title(text = "Par région")
  })
  
  output$stack_category <- renderHighchart({
    df <- r_filtered() |>
      dplyr::group_by(month, category) |>
      dplyr::summarise(Revenue = sum(revenue), .groups="drop")
    hchart(df, "column", hcaes(x = month, y = Revenue, group = category)) |>
      hc_plotOptions(series = list(stacking = "normal")) |>
      hc_title(text = "Revenus par catégorie")
  })
  
  output$top_products <- renderHighchart({
    df <- r_filtered() |>
      dplyr::group_by(product) |>
      dplyr::summarise(Revenue = sum(revenue), .groups="drop") |>
      dplyr::arrange(desc(Revenue)) |> dplyr::slice_head(n = 10)
    hchart(df, "bar", hcaes(x = product, y = Revenue)) |>
      hc_title(text = "Top produits") |>
      hc_yAxis(labels = list(format = "{value:,.0f} €"))
  })
  
  # Tableau
  output$tbl <- DT::renderDT({
    DT::datatable(
      r_filtered() |> dplyr::arrange(desc(date)),
      options = list(pageLength = 10, scrollX = TRUE),
      filter = "top", rownames = FALSE
    )
  })
  
  # Exports
  output$dl_csv <- downloadHandler(
    filename = function() paste0("export_finances_", Sys.Date(), ".csv"),
    content = function(file) readr::write_csv(fin_data, file)
  )
  
  output$dl_view <- downloadHandler(
    filename = function() paste0("export_vue_", Sys.Date(), ".csv"),
    content = function(file) readr::write_csv(r_filtered(), file)
  )
  
  # Reset
  observeEvent(input$reset_filters, {
    updateSelectInput(session, "region", selected="Toutes")
    updateSelectInput(session, "category", selected="Toutes")
    updateSelectInput(session, "product", selected="Tous")
    updateDateRangeInput(session, "dater", start=min(fin_data$date), end=max(fin_data$date))
  })
  
  observeEvent(input$reset_filters2, {
    updateSelectInput(session, "region", selected="Toutes")
    updateSelectInput(session, "category", selected="Toutes")
    updateSelectInput(session, "product", selected="Tous")
    updateDateRangeInput(session, "dater", start=min(fin_data$date), end=max(fin_data$date))
  })
  
  # Infos dataset sous tableau
  output$about <- renderText({
    paste0("Observations: ", nrow(fin_data),
           "\nPériode: ", format(min(fin_data$date), "%Y-%m-%d"), " → ", format(max(fin_data$date), "%Y-%m-%d"),
           "\nColonnes: ", paste(colnames(fin_data), collapse=", "))
  })
}

shinyApp(ui, server)
