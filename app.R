# ==== Packages ====
# Les dépendances sont maintenant gérées par {renv}.
# Il suffit de charger les librairies nécessaires.
# Au déploiement, "renv::restore()" installera automatiquement
# les bonnes versions listées dans renv.lock.

library(shiny)
library(plotly)
library(DT)
library(readr)
library(dplyr)
library(tidyr)
library(lubridate)
library(scales)
library(cachem)
library(digest)

# ==== data loader (CSV optionnel ou génération) ====
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

# ==== helpers & cache ====
cache <- cachem::cache_mem()
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

# ==== UI (shiny de base + CSS/JS via www/) ====
ui <- navbarPage(
  title = div(
    tags$img(src = "logo.png", height = 24, onerror="this.style.display='none'"),
    HTML("Finance Dashboard")
  ),
  header = tagList(
    tags$link(rel="stylesheet", type="text/css", href="styles.css"),
    tags$script(src="app.js")
  ),
  
  h1("Dashboard des données financières",

     style="text-align:center;padding:15px 15px;background-color:#ccc;border-radius:10px;"),
  
  tabPanel(
    "Dashboard",
    div(class = "layout",
        div(class = "sidebar",
            h4("Effectuez vos filtres :"),
            dateRangeInput("dater", "Période", start = min(fin_data$date), end = max(fin_data$date)),
            selectInput("region", "Région", choices = c("Toutes", sort(unique(fin_data$region))), selected = "Toutes"),
            selectInput("category", "Catégorie", choices = c("Toutes", sort(unique(fin_data$category))), selected = "Toutes"),
            selectInput("product", "Produit", choices = c("Tous", sort(unique(fin_data$product))), selected = "Tous"),
            checkboxInput("darkmode", "Mode sombre", value = FALSE),
            hr(),
            downloadButton("dl_csv", "Télécharger CSV"),
            actionButton("reset_filters", "Réinitialiser")
        ),
        div(class = "content",
            div(class = "kpi-row",
                div(class = "kpi",h6("Revenus"),  textOutput("kpi_rev")),
                div(class = "kpi", h6("Dépenses"), textOutput("kpi_exp")),
                div(class = "kpi", h6("Marge brute"), textOutput("kpi_gp")),
                div(class = "kpi",h6("Taux de marge"), textOutput("kpi_margin"))
            ),
            div(class = "row-2",
                div(class = "card", plotlyOutput("ts_revenue", height = "360px")),
                div(class = "card", plotlyOutput("bar_region",  height = "360px"))
            ),
            div(class = "row-2",
                div(class = "card", plotlyOutput("stack_category", height = "340px")),
                div(class = "card", plotlyOutput("top_products",   height = "340px"))
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
                actionButton("reset_filters2", "Réinitialiser les filtres")
            )
        )
    )
  ),
  
  tabPanel(
    "À propos",
    div(class = "content",
        div(class = "card",
            h4("Infos dataset"),
            verbatimTextOutput("about"),
            p("Astuce: sur les graphiques Plotly, utilisez la molette ou la sélection pour zoomer, et cliquez sur la légende pour masquer/afficher des séries.")
        )
    )
  )
)

# ==== SERVER ====
server <- function(input, output, session) {
  
  observe({
    session$sendCustomMessage("toggle-dark", list(enable = isTRUE(input$darkmode)))
  })
  
  r_filtered <- reactive({
    df <- fin_data |>
      dplyr::filter(date >= input$dater[1], date <= input$dater[2])
    if (input$region  != "Toutes") df <- df |> dplyr::filter(region == input$region)
    if (input$category != "Toutes") df <- df |> dplyr::filter(category == input$category)
    if (input$product != "Tous")   df <- df |> dplyr::filter(product == input$product)
    df
  })
  
  observe({
    kp <- kpis(r_filtered())
    output$kpi_rev    <- renderText(fmt_eur(kp$Revenue))
    output$kpi_exp    <- renderText(fmt_eur(kp$Expenses))
    output$kpi_gp     <- renderText(fmt_eur(kp$GP))
    output$kpi_margin <- renderText(fmt_pct(kp$Margin))
  })
  
  output$ts_revenue <- renderPlotly({
    df <- r_filtered() |>
      dplyr::group_by(month) |>
      dplyr::summarise(Revenue = sum(revenue), .groups="drop")
    plot_ly(df, x = ~month, y = ~Revenue, type = "scatter", mode = "lines+markers",
            hovertemplate = "%{x|%b %Y}<br>Revenus: %{y:,} €<extra></extra>") |>
      layout(title = "Revenus mensuels", yaxis = list(tickformat = ",.0f"))
  })
  
  output$bar_region <- renderPlotly({
    df <- r_filtered() |>
      dplyr::group_by(region) |>
      dplyr::summarise(Revenue = sum(revenue), GP = sum(gp), .groups="drop")
    plot_ly(df, x = ~region, y = ~Revenue, type = "bar", name = "Revenus") |>
      add_trace(y = ~GP, type = "bar", name = "Marge brute") |>
      layout(barmode = "group", title = "Par région", yaxis = list(tickformat=",.0f"))
  })
  
  output$stack_category <- renderPlotly({
    df <- r_filtered() |>
      dplyr::group_by(month, category) |>
      dplyr::summarise(Revenue = sum(revenue), .groups="drop")
    plot_ly(df, x = ~month, y = ~Revenue, color = ~category, type = "bar") |>
      layout(barmode="stack", title="Revenus par catégorie")
  })
  
  output$top_products <- renderPlotly({
    df <- r_filtered() |>
      dplyr::group_by(product) |>
      dplyr::summarise(Revenue = sum(revenue), .groups="drop") |>
      dplyr::arrange(dplyr::desc(Revenue)) |>
      dplyr::slice_head(n = 10)
    plot_ly(df, x = ~Revenue, y = ~reorder(product, Revenue), type = "bar", orientation = "h") |>
      layout(title="Top produits", xaxis = list(tickformat=",.0f"), yaxis = list(title=""))
  })
  
  output$tbl <- DT::renderDT({
    DT::datatable(
      r_filtered() |> dplyr::arrange(dplyr::desc(date)),
      options = list(pageLength = 10, scrollX = TRUE, dom = "Bfrtip"),
      filter = "top", rownames = FALSE
    )
  })
  
  output$dl_csv <- downloadHandler(
    filename = function() paste0("export_finances_", Sys.Date(), ".csv"),
    content = function(file) readr::write_csv(fin_data, file)
  )
  
  output$dl_view <- downloadHandler(
    filename = function() paste0("export_vue_", Sys.Date(), ".csv"),
    content = function(file) readr::write_csv(r_filtered(), file)
  )
  
  observeEvent(input$reset_filters, {
    updateSelectInput(session, "region", selected="Toutes")
    updateSelectInput(session, "category", selected="Toutes")
    updateSelectInput(session, "product", selected="Tous")
    updateDateRangeInput(session, "dater", start=min(fin_data$date), end=max(fin_data$date))
  })
  
  observeEvent(input$reset_filters2, {
    session$sendInputMessage("reset_filters", list())
    updateSelectInput(session, "region", selected="Toutes")
    updateSelectInput(session, "category", selected="Toutes")
    updateSelectInput(session, "product", selected="Tous")
    updateDateRangeInput(session, "dater", start=min(fin_data$date), end=max(fin_data$date))
  })
  
  output$about <- renderText({
    paste0("Observations: ", nrow(fin_data),
           "\nPériode: ", format(min(fin_data$date), "%Y-%m-%d"), " → ", format(max(fin_data$date), "%Y-%m-%d"),
           "\nColonnes: ", paste(colnames(fin_data), collapse=", "))
  })
}

shinyApp(ui, server)
