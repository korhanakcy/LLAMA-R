library(shiny)
library(curl)
library(jsonlite)


model_list <- read.table(text = system("ollama list", intern = TRUE),
                         sep = "\t", row.names = NULL)
# tabs at the end of each model row adds an additional empty column
model_list$MODIFIED <- NULL
colnames(model_list) <- c("NAME", "ID", "SIZE", "MODIFIED")
model_list$NAME <- trimws(model_list$NAME)

ui <- fluidPage(
  div(
    titlePanel("ollama sql_coder with Shiny"),
    style = "color: white; background-color: #3d3f4e"
  ),
  sidebarLayout(
    sidebarPanel(
      h3("Welcome to ollama, sir!"),
      
      selectInput("model_name", "Model Name",
                  choices = c("llama2:latest", "llama2-uncensored:latest",
                              "codellama:latest",
                              "medllama2:latest", "orca-mini:latest",
                              "mistral:latest", "samantha-mistral:latest",
                              "orca-mini:3b"), selected = "llama2:latest"),
      tags$hr(),
      sliderInput("temperature", "Temperature", min = 0.1, max = 1.0, value = 0.3, step = 0.1),
      sliderInput("max_length", "Maximum Length", min = 1, max = 2048, value = 512, step = 1),
      tags$hr(),
      textAreaInput(inputId = "sysprompt", label = "SYSTEM PROMPT", height = "200px", value = "You are a expert sql scripter and you will just answering the script that what wanted sql script, answer with just script no more instruction or information. 

Example input: I want to see the every data in table_name 
Your output: Select * from table_name"),
      tags$hr(),
      tags$div(
        style="text-align:center; margin-top: 15px; color: white; background-color: #ffffff",
        a(href="https://github.com/korhanakcy", target="_blank",
          img(src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png", height="30px"),
          "View source code on Github"
        )
      ),
      style = "background-color: #1a1b1f; color: white"
    )
    ,
    mainPanel(
      tags$style(type = "text/css", ".shiny-output-error {visibility: hidden;}"),
      tags$style(type = "text/css", ".shiny-output-error:before {content: ' Check your inputs or API key';}"),
      tags$style(type = "text/css", "label {font-weight: bold;}"),
      fluidRow(
        column(12,tags$h3("Script History"),tags$hr(),uiOutput("chat_history"),tags$hr())
      ),
      fluidRow(
        column(11,textAreaInput(inputId = "user_message", placeholder = "What would you like to script?:", label="USER PROMPT", width = "100%")),
        column(1,actionButton("send_message", "Send",icon = icon("play"),height = "350px"))
      ),style = "background-color: #4990bf")
  ),style = "background-color: #000000")

server <- function(input, output, session) {
  chat_data <- reactiveVal(data.frame())
  
  # Download model if not present
  observeEvent(input$model_name, {
    if(!(input$model_name %in% model_list$NAME)){
      system(paste0("ollama pull ", input$model_name))
      # Update model list
      model_list <- read.table(text = system("ollama list", intern = TRUE),
                               sep = "\t", row.names = NULL)
      # tabs at the end of each model row adds an additional empty column
      model_list$MODIFIED <- NULL
      colnames(model_list) <- c("NAME", "ID", "SIZE", "MODIFIED")
      model_list$NAME <- trimws(model_list$NAME)
    }
  })
  
  call_api_with_curl <- function(json_payload) {
    h <- new_handle()
    handle_setopt(h, copypostfields = json_payload)
    handle_setheaders(h,
                      "Content-Type" = "application/json",
                      "Accept" = "application/json")
    response <- curl_fetch_memory("http://localhost:11434/api/generate", handle = h)
    # Parse the response
    parsed_response <- fromJSON(rawToChar(response$content))
    return(trimws(parsed_response$response))
  }
  
  call_ollama_api <- function(prompt, model_name, temperature, max_length, sysprompt) {
    data_list <- list(model = model_name, prompt = prompt, system = sysprompt,
                      stream = FALSE,
                      options = list(temperature = temperature,
                                     num_predict = max_length))
    json_payload <- toJSON(data_list, auto_unbox = TRUE)
    call_api_with_curl(json_payload)
  }
  
  observeEvent(input$send_message, {
    if (input$user_message != "") {
      new_data <- data.frame(source = "User", message = input$user_message, stringsAsFactors = FALSE)
      chat_data(rbind(chat_data(), new_data))
      gpt_res <- call_ollama_api(prompt = input$user_message,
                                 model_name = input$model_name,
                                 temperature = input$temperature,
                                 max_length = input$max_length,
                                 sysprompt = input$sysprompt)
      if (!is.null(gpt_res)) {
        gpt_data <- data.frame(source = "ollama", message = gpt_res, stringsAsFactors = FALSE)
        chat_data(rbind(chat_data(), gpt_data))
      }
      
      updateTextInput(session, "user_message", value = "")
    }
  })
  
  output$chat_history <- renderUI({
    chatBox <- lapply(1:nrow(chat_data()), function(i) {
      tags$div(class = ifelse(chat_data()[i, "source"] == "User", "alert alert-secondary", "alert alert-success"),
               HTML(paste0("<b>", chat_data()[i, "source"], ":</b> ", text = chat_data()[i, "message"])))
    })
    do.call(tagList, chatBox)
  })
  
  observeEvent(input$download_button, {
    if (nrow(chat_data()) > 0) {
      session$sendCustomMessage(type = "downloadData", message = "download_data")
    }
  })
}
shinyApp(ui = ui, server = server)
