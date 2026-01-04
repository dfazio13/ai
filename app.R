# app.R
library(shiny)
library(DBI)
library(RSQLite)

source("openai_helper.R")
source("canvas_auth_production.R")  # Instead of "canvas_auth.R"
source("database.R")

ui <- fluidPage(
  titlePanel("AI Tutorial Assistant"),
  
  # Authentication UI
  uiOutput("auth_ui"),
  
  # Main app UI (only shown when authenticated)
  uiOutput("main_ui")
)

server <- function(input, output, session) {
  
  # Reactive values for authentication
  user_data <- reactiveValues(
    authenticated = FALSE,
    canvas_token = NULL,
    user_info = NULL,
    conversation = list()
  )
  
  # Check for OAuth callback
  observe({
    query <- parseQueryString(session$clientData$url_search)
    
    if (!is.null(query$code)) {
      # Exchange code for token
      token_data <- get_canvas_token(query$code)
      user_data$canvas_token <- token_data$access_token
      
      # Get user info
      user_info <- get_canvas_user(token_data$access_token)
      user_data$user_info <- user_info
      
      # Check enrollment (update course_id)
      if (check_enrollment(token_data$access_token, "YOUR_COURSE_ID")) {
        user_data$authenticated <- TRUE
        
        # Log login
        log_student_login(user_info$id, user_info$name)
        
        # Clear URL parameters
        updateQueryString("?", mode = "replace")
      } else {
        showNotification("You are not enrolled in this course", type = "error")
      }
    }
  })
  
  # Authentication UI
  output$auth_ui <- renderUI({
    if (!user_data$authenticated) {
      div(
        style = "text-align: center; margin-top: 100px;",
        h2("Welcome to AI Tutorial Assistant"),
        p("Please log in with your Canvas account to continue"),
        actionButton("login_btn", "Login with Canvas", 
                     class = "btn-primary btn-lg",
                     onclick = paste0("window.location.href='", get_canvas_auth_url(), "'"))
      )
    }
  })
  
  # Main app UI
  output$main_ui <- renderUI({
    req(user_data$authenticated)
    
    fluidRow(
      column(12,
             h3(paste("Welcome,", user_data$user_info$name)),
             hr()
      ),
      column(8,
             h4("AI Chat Tutor"),
             uiOutput("chat_history"),
             textAreaInput("user_message", "Your Question:", 
                           width = "100%", rows = 3),
             actionButton("send_btn", "Send", class = "btn-success")
      ),
      column(4,
             h4("Your Progress"),
             verbatimTextOutput("usage_stats"),
             hr(),
             h4("Modules"),
             uiOutput("modules_list")
      )
    )
  })
  
  # Chat history display
  output$chat_history <- renderUI({
    req(user_data$authenticated)
    
    if (length(user_data$conversation) == 0) {
      return(p("Start by asking a question!"))
    }
    
    chat_html <- lapply(user_data$conversation, function(msg) {
      if (msg$role == "user") {
        div(class = "alert alert-info", 
            strong("You: "), msg$content)
      } else {
        div(class = "alert alert-success", 
            strong("AI Tutor: "), msg$content)
      }
    })
    
    do.call(tagList, chat_html)
  })
  
  # Handle send button
  observeEvent(input$send_btn, {
    req(input$user_message != "")
    
    # Add user message to conversation
    user_data$conversation <- append(
      user_data$conversation,
      list(list(role = "user", content = input$user_message))
    )
    
    # Call OpenAI API
    withProgress(message = "AI is thinking...", {
      
      # Add system prompt for educational context
      messages <- c(
        list(list(
          role = "system",
          content = "You are a helpful educational tutor. Explain concepts clearly and ask follow-up questions to ensure understanding."
        )),
        user_data$conversation
      )
      
      ai_response <- chat_with_ai(messages)
      
      # Add AI response to conversation
      user_data$conversation <- append(
        user_data$conversation,
        list(list(role = "assistant", content = ai_response$message))
      )
      
      # Log usage to database
      log_usage(
        user_id = user_data$user_info$id,
        tokens = ai_response$tokens,
        cost = ai_response$cost,
        conversation_length = length(user_data$conversation)
      )
    })
    
    # Clear input
    updateTextAreaInput(session, "user_message", value = "")
  })
  
  # Usage statistics
  output$usage_stats <- renderText({
    req(user_data$authenticated)
    
    stats <- get_user_stats(user_data$user_info$id)
    
    paste(
      "Messages sent:", stats$message_count, "\n",
      "Tokens used:", stats$total_tokens, "\n",
      "Estimated cost: $", round(stats$total_cost, 4)
    )
  })
  
  # Module list
  output$modules_list <- renderUI({
    # Define your tutorial modules
    modules <- c(
      "Introduction to R",
      "Data Visualization",
      "Statistical Analysis",
      "Machine Learning Basics"
    )
    
    lapply(modules, function(module) {
      actionButton(
        paste0("module_", gsub(" ", "_", module)),
        module,
        class = "btn btn-outline-primary btn-block",
        style = "margin-bottom: 10px;"
      )
    })
  })
}

shinyApp(ui, server)