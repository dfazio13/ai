library(shiny)
library(shinyjs)
library(httr2)
library(jsonlite)
library(DBI)
library(RSQLite)
library(curl)
library(bslib)

# ============================================================================
# CONFIGURATION
# ============================================================================

ENABLE_AUDIO_RESPONSES <- Sys.getenv("ENABLE_AUDIO_RESPONSES", "false") == "true"
AUDIO_VOICE <- Sys.getenv("AUDIO_VOICE", "nova")

is_production <- Sys.getenv("RENDER") != ""

if (is_production) {
  BASE_DIR <- "."
  AUDIO_DIR <- "/app/data/audio"
  DB_PATH <- "/app/data/chat_sessions.db"
} else {
  BASE_DIR <- getwd()
  AUDIO_DIR <- file.path(BASE_DIR, "audio")
  if (file.exists(file.path(BASE_DIR, ".Renviron"))) {
    readRenviron(file.path(BASE_DIR, ".Renviron"))
  }
  DB_PATH <- file.path(BASE_DIR, "chat_sessions.db")
}

if (!dir.exists(AUDIO_DIR)) {
  dir.create(AUDIO_DIR, recursive = TRUE)
}

OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
  stop("OPENAI_API_KEY environment variable not set!")
}

# Read knowledge base
kb_file <- file.path(BASE_DIR, "Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt")
if (file.exists(kb_file)) {
  base_texto <- readLines(kb_file, warn = FALSE, encoding = "UTF-8")
} else {
  base_texto <- "Base de conhecimento não encontrada."
}

# ============================================================================
# DATABASE FUNCTIONS
# ============================================================================

init_database <- function(db_path) {
  con <- dbConnect(RSQLite::SQLite(), db_path)
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      direction TEXT,
      message TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )")
  
  return(con)
}

log_message <- function(con, user_id, direction, message) {
  dbExecute(con,
            "INSERT INTO messages (user_id, direction, message) VALUES (?, ?, ?)",
            params = list(user_id, direction, message))
}

get_user_history <- function(con, user_id, limit = 10) {
  query <- "SELECT direction, message, created_at 
            FROM messages 
            WHERE user_id = ? 
            ORDER BY created_at DESC 
            LIMIT ?"
  
  result <- dbGetQuery(con, query, params = list(user_id, limit))
  
  if (nrow(result) > 0) {
    result <- result[order(result$created_at), ]
  }
  
  return(result)
}

# ============================================================================
# AI FUNCTIONS
# ============================================================================

ask_flora <- function(question, user_id, con_db, base_knowledge, api_key) {
  tryCatch({
    # Get conversation history
    history <- get_user_history(con_db, user_id, limit = 10)
    
    # Build conversation messages
    messages <- list(
      list(
        role = "system",
        content = paste(
          "Você é Mia, especialista SEBRAE que ajuda empreendedores brasileiros a crescerem seus negócios.",
          "O SEBRAE oferece cursos, consultorias e ferramentas gratuitas para pequenos negócios.",
          "\n\n╔═════════════════════════════════════════╗",
          "\n║  MISSÃO: Ser útil + Oferecer opções    ║",
          "\n╚═════════════════════════════════════════╝",
          "\n\n🔒 REGRA CRÍTICA - USO EXCLUSIVO DA BASE DE CONHECIMENTO:",
          "\n   ⚠️ Você DEVE usar APENAS informações da base de conhecimento fornecida",
          "\n   ⚠️ NÃO use conhecimento geral ou externo",
          "\n   ⚠️ Se a informação NÃO estiver na base, diga: 'Essa informação específica não está disponível.'",
          "\n\n⚡ IMPORTANTE - LIMITE DE RESPOSTA:",
          "\n  - Máximo 500 caracteres",
          "\n  - Use quebras de linha para facilitar leitura",
          "\n  - Use emojis para destacar informações",
          "\n\n📚 BASE DE CONHECIMENTO:\n",
          paste(base_knowledge, collapse = "\n")
        )
      )
    )
    
    # Add conversation history
    if (nrow(history) > 0) {
      for (i in 1:nrow(history)) {
        role <- if (history$direction[i] == "in") "user" else "assistant"
        messages <- append(messages, list(list(
          role = role,
          content = history$message[i]
        )))
      }
    }
    
    # Add current question
    messages <- append(messages, list(list(
      role = "user",
      content = question
    )))
    
    # Call OpenAI API
    resp <- httr2::request("https://api.openai.com/v1/chat/completions") |>
      httr2::req_auth_bearer_token(api_key) |>
      httr2::req_body_json(list(
        model = "gpt-4o-mini",
        messages = messages,
        temperature = 0.7,
        max_tokens = 500
      )) |>
      httr2::req_timeout(60) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    reply <- resp$choices[[1]]$message$content
    return(reply)
    
  }, error = function(e) {
    return("Desculpe, tive um problema técnico. Por favor, tente novamente.")
  })
}

transcribe_audio <- function(audio_path, api_key) {
  tryCatch({
    resp <- httr2::request("https://api.openai.com/v1/audio/transcriptions") |>
      httr2::req_auth_bearer_token(api_key) |>
      httr2::req_body_multipart(
        file = curl::form_file(audio_path, type = "audio/webm"),
        model = "whisper-1",
        language = "pt"
      ) |>
      httr2::req_timeout(300) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    return(resp$text)
  }, error = function(e) {
    return(NULL)
  })
}

generate_audio <- function(text, voice = "nova") {
  tryCatch({
    # Clean text for TTS
    clean <- gsub("1️⃣", "Opção 1: ", text)
    clean <- gsub("2️⃣", "Opção 2: ", clean)
    clean <- gsub("3️⃣", "Opção 3: ", clean)
    clean <- gsub("4️⃣", "Opção 4: ", clean)
    clean <- gsub("[\U0001F300-\U0001F9FF]", "", clean)
    clean <- gsub("[\U0001F600-\U0001F64F]", "", clean)
    clean <- gsub("[\U0001F680-\U0001F6FF]", "", clean)
    clean <- gsub("[•→◆★▪▫]", "", clean)
    clean <- gsub("\\*+", "", clean)
    clean <- gsub("\\n+", ". ", clean)
    clean <- gsub("\\s+", " ", clean)
    clean <- trimws(clean)
    
    temp_audio <- tempfile(fileext = ".mp3")
    
    httr2::request("https://api.openai.com/v1/audio/speech") |>
      httr2::req_auth_bearer_token(Sys.getenv("OPENAI_API_KEY")) |>
      httr2::req_body_json(list(
        model = "tts-1",
        input = clean,
        voice = voice,
        response_format = "mp3"
      )) |>
      httr2::req_timeout(90) |>
      httr2::req_perform(path = temp_audio)
    
    audio_data <- readBin(temp_audio, "raw", file.info(temp_audio)$size)
    unlink(temp_audio)
    
    return(audio_data)
  }, error = function(e) {
    return(NULL)
  })
}

# ============================================================================
# SHINY UI
# ============================================================================

ui <- page_fluid(
  useShinyjs(),  # Enable shinyjs
  theme = bs_theme(
    version = 5,
    bg = "#ffffff",
    fg = "#212529",
    primary = "#0d6efd",
    base_font = font_google("Roboto"),
    heading_font = font_google("Poppins")
  ),
  
  tags$head(
    tags$style(HTML("
      .chat-container {
        max-width: 800px;
        margin: 0 auto;
        height: 80vh;
        display: flex;
        flex-direction: column;
      }
      
      .chat-header {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        padding: 20px;
        border-radius: 15px 15px 0 0;
        text-align: center;
      }
      
      .chat-messages {
        flex: 1;
        overflow-y: auto;
        padding: 20px;
        background: #f8f9fa;
        border-left: 1px solid #dee2e6;
        border-right: 1px solid #dee2e6;
      }
      
      .message {
        margin-bottom: 15px;
        display: flex;
        align-items: flex-start;
      }
      
      .message.user {
        justify-content: flex-end;
      }
      
      .message-bubble {
        max-width: 70%;
        padding: 12px 16px;
        border-radius: 18px;
        word-wrap: break-word;
        white-space: pre-wrap;
      }
      
      .message.user .message-bubble {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border-bottom-right-radius: 4px;
      }
      
      .message.assistant .message-bubble {
        background: white;
        color: #212529;
        border: 1px solid #dee2e6;
        border-bottom-left-radius: 4px;
        box-shadow: 0 1px 2px rgba(0,0,0,0.1);
      }
      
      .chat-input-area {
        padding: 20px;
        background: white;
        border: 1px solid #dee2e6;
        border-radius: 0 0 15px 15px;
        border-top: 2px solid #667eea;
      }
      
      .input-group {
        display: flex;
        gap: 10px;
      }
      
      #user_input {
        flex: 1;
        border-radius: 25px;
        border: 2px solid #e9ecef;
        padding: 12px 20px;
        font-size: 16px;
      }
      
      #user_input:focus {
        border-color: #667eea;
        outline: none;
        box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
      }
      
      #send_btn {
        border-radius: 25px;
        padding: 12px 30px;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        border: none;
        color: white;
        font-weight: 600;
        transition: transform 0.2s;
      }
      
      #send_btn:hover {
        transform: scale(1.05);
      }
      
      .typing-indicator {
        display: none;
        padding: 10px;
        color: #6c757d;
        font-style: italic;
      }
      
      .typing-indicator.active {
        display: block;
      }
      
      .audio-player {
        margin-top: 10px;
      }
      
      .welcome-message {
        text-align: center;
        color: #6c757d;
        padding: 40px 20px;
      }
      
      .welcome-message h3 {
        color: #667eea;
        margin-bottom: 15px;
      }
    "))
  ),
  
  div(class = "chat-container",
      div(class = "chat-header",
          h2("💬 Mia - Assistente Virtual SEBRAE"),
          p("Olá! Sou a Mia, sua especialista em pequenos negócios. Como posso ajudar?")
      ),
      
      div(class = "chat-messages", id = "chat_messages",
          uiOutput("messages_ui"),
          div(class = "typing-indicator", id = "typing_indicator", "Mia está digitando...")
      ),
      
      div(class = "chat-input-area",
          div(class = "input-group",
              textInput("user_input", NULL, placeholder = "Digite sua mensagem aqui...", width = "100%"),
              actionButton("send_btn", "Enviar", class = "btn-primary")
          ),
          div(style = "margin-top: 10px; text-align: center;",
              checkboxInput("enable_audio", "Habilitar respostas em áudio", value = ENABLE_AUDIO_RESPONSES)
          )
      )
  )
)

# ============================================================================
# SHINY SERVER
# ============================================================================

server <- function(input, output, session) {
  
  # Initialize database connection
  con <- init_database(DB_PATH)
  
  # Generate unique user ID for this session
  user_id <- paste0("web_", session$token)
  
  # Reactive values for messages
  messages <- reactiveVal(list())
  
  # Check if new user and show welcome
  observe({
    history <- get_user_history(con, user_id, limit = 1)
    
    if (nrow(history) == 0) {
      welcome_msg <- paste0(
        "Olá! 👋 Seja bem-vindo ao SEBRAE!\n\n",
        "Sou a Mia, sua assistente virtual especialista em pequenos negócios. ",
        "Estou aqui para te ajudar a crescer! 🚀\n\n",
        "Posso te ajudar com:\n",
        "💼 Formalização (abrir MEI, trocar para ME)\n",
        "💰 Gestão financeira (preços, fluxo de caixa, lucro)\n",
        "📦 Estoque e fornecedores\n",
        "📱 Marketing e redes sociais\n",
        "🎓 Cursos e ferramentas gratuitas\n",
        "📊 Planejamento do seu negócio\n\n",
        "Como posso te ajudar hoje? 😊"
      )
      
      log_message(con, user_id, "out", welcome_msg)
      
      current_msgs <- list(list(
        role = "assistant",
        content = welcome_msg,
        timestamp = Sys.time()
      ))
      
      messages(current_msgs)
    }
  })
  
  # Send message when button clicked or Enter pressed
  observeEvent(input$send_btn, {
    send_message()
  })
  
  observeEvent(input$user_input, {
    if (input$user_input != "" && grepl("\n$", input$user_input)) {
      send_message()
    }
  })
  
  # Send message function
  send_message <- function() {
    user_msg <- trimws(input$user_input)
    
    if (user_msg == "") return()
    
    # Add user message to chat
    current_msgs <- messages()
    current_msgs[[length(current_msgs) + 1]] <- list(
      role = "user",
      content = user_msg,
      timestamp = Sys.time()
    )
    messages(current_msgs)
    
    # Log user message
    log_message(con, user_id, "in", user_msg)
    
    # Clear input
    updateTextInput(session, "user_input", value = "")
    
    # Show typing indicator
    shinyjs::runjs("document.getElementById('typing_indicator').classList.add('active');")
    
    # Get AI response
    reply <- ask_flora(user_msg, user_id, con, base_texto, OPENAI_API_KEY)
    
    # Log assistant message
    log_message(con, user_id, "out", reply)
    
    # Generate audio if enabled
    audio_data <- NULL
    if (input$enable_audio && nchar(reply) <= 1000) {
      audio_data <- generate_audio(reply, AUDIO_VOICE)
    }
    
    # Add assistant message to chat
    current_msgs <- messages()
    current_msgs[[length(current_msgs) + 1]] <- list(
      role = "assistant",
      content = reply,
      audio = audio_data,
      timestamp = Sys.time()
    )
    messages(current_msgs)
    
    # Hide typing indicator
    shinyjs::runjs("document.getElementById('typing_indicator').classList.remove('active');")
    
    # Scroll to bottom
    shinyjs::runjs("
      var chatMessages = document.getElementById('chat_messages');
      chatMessages.scrollTop = chatMessages.scrollHeight;
    ")
  }
  
  # Render messages UI
  output$messages_ui <- renderUI({
    msgs <- messages()
    
    if (length(msgs) == 0) {
      return(div(class = "welcome-message",
                 h3("👋 Bem-vindo!"),
                 p("Faça sua primeira pergunta para começar.")))
    }
    
    lapply(msgs, function(msg) {
      msg_class <- if (msg$role == "user") "message user" else "message assistant"
      
      content_div <- div(class = "message-bubble", HTML(gsub("\n", "<br>", msg$content)))
      
      # Add audio player if audio data is available
      if (!is.null(msg$audio)) {
        audio_base64 <- base64enc::base64encode(msg$audio)
        audio_player <- tags$audio(
          controls = "controls",
          class = "audio-player",
          tags$source(
            src = paste0("data:audio/mp3;base64,", audio_base64),
            type = "audio/mp3"
          )
        )
        
        div(class = msg_class,
            div(
              content_div,
              audio_player
            ))
      } else {
        div(class = msg_class, content_div)
      }
    })
  })
  
  # Clean up database connection on session end
  session$onSessionEnded(function() {
    dbDisconnect(con)
  })
}

# ============================================================================
# RUN APP
# ============================================================================

shinyApp(ui = ui, server = server)
