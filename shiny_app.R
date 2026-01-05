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

cat("\n╔════════════════════════════════════════════╗\n")
cat("║  SEBRAE CHATBOT - STARTING UP              ║\n")
cat("╚════════════════════════════════════════════╝\n\n")

ENABLE_AUDIO_RESPONSES <- Sys.getenv("ENABLE_AUDIO_RESPONSES", "false") == "true"
AUDIO_VOICE <- Sys.getenv("AUDIO_VOICE", "nova")

cat("[CONFIG] Audio Responses:", if(ENABLE_AUDIO_RESPONSES) "ENABLED" else "DISABLED", "\n")
cat("[CONFIG] Audio Voice:", AUDIO_VOICE, "\n")

is_production <- Sys.getenv("RENDER") != ""
cat("[CONFIG] Environment:", if(is_production) "PRODUCTION (Render)" else "DEVELOPMENT (Local)", "\n")

if (is_production) {
  BASE_DIR <- "."
  AUDIO_DIR <- "/app/data/audio"
  DB_PATH <- "/app/data/chat_sessions.db"
  cat("[CONFIG] Base Directory: /app\n")
  cat("[CONFIG] Audio Directory: /app/data/audio\n")
  cat("[CONFIG] Database Path: /app/data/chat_sessions.db\n")
} else {
  BASE_DIR <- getwd()
  AUDIO_DIR <- file.path(BASE_DIR, "audio")
  cat("[CONFIG] Base Directory:", BASE_DIR, "\n")
  cat("[CONFIG] Audio Directory:", AUDIO_DIR, "\n")
  if (file.exists(file.path(BASE_DIR, ".Renviron"))) {
    cat("[CONFIG] Loading .Renviron file...\n")
    readRenviron(file.path(BASE_DIR, ".Renviron"))
    cat("[CONFIG] ✓ .Renviron loaded\n")
  } else {
    cat("[CONFIG] ⚠ No .Renviron file found\n")
  }
  DB_PATH <- file.path(BASE_DIR, "chat_sessions.db")
  cat("[CONFIG] Database Path:", DB_PATH, "\n")
}

if (!dir.exists(AUDIO_DIR)) {
  cat("[CONFIG] Creating audio directory:", AUDIO_DIR, "\n")
  dir.create(AUDIO_DIR, recursive = TRUE)
  cat("[CONFIG] ✓ Audio directory created\n")
} else {
  cat("[CONFIG] ✓ Audio directory exists\n")
}

OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
  cat("[CONFIG] ❌ ERROR: OPENAI_API_KEY not set!\n")
  stop("OPENAI_API_KEY environment variable not set!")
} else {
  key_preview <- paste0(substr(OPENAI_API_KEY, 1, 7), "...", substr(OPENAI_API_KEY, nchar(OPENAI_API_KEY)-4, nchar(OPENAI_API_KEY)))
  cat("[CONFIG] ✓ OPENAI_API_KEY is set:", key_preview, "\n")
}

# Read knowledge base
kb_file <- file.path(BASE_DIR, "Base_Conhecimento.txt")
cat("[CONFIG] Knowledge base file:", kb_file, "\n")
if (file.exists(kb_file)) {
  cat("[CONFIG] Reading knowledge base...\n")
  base_texto <- readLines(kb_file, warn = FALSE, encoding = "UTF-8")
  cat("[CONFIG] ✓ Knowledge base loaded:", length(base_texto), "lines,", sum(nchar(base_texto)), "chars\n")
} else {
  cat("[CONFIG] ❌ ERROR: Knowledge base file not found!\n")
  base_texto <- "Base de conhecimento não encontrada."
}

cat("\n[CONFIG] ✓ Configuration complete!\n")
cat("════════════════════════════════════════════\n\n")

# ============================================================================
# DATABASE FUNCTIONS
# ============================================================================

init_database <- function(db_path) {
  cat("[DB INIT] Connecting to database:", db_path, "\n")
  con <- dbConnect(RSQLite::SQLite(), db_path)
  
  cat("[DB INIT] Creating messages table if not exists...\n")
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      direction TEXT,
      message TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )")
  
  # Check if table exists and has data
  count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM messages")$count
  cat("[DB INIT] ✓ Database initialized. Total messages:", count, "\n")
  
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
    cat("[ASK_FLORA] Starting AI request\n")
    cat("[ASK_FLORA] Question:", question, "\n")
    cat("[ASK_FLORA] User ID:", user_id, "\n")
    
    # Get conversation history
    history <- get_user_history(con_db, user_id, limit = 10)
    cat("[ASK_FLORA] Retrieved", nrow(history), "history messages\n")
    
    # Build conversation messages
    messages <- list(
      list(
        role = "system",
        content = paste(
          "You are FinMentor, an AI tutor specialized in corporate finance dedicated to making complex concepts crystal clear.",
          "Your purpose is to ensure every student truly understands the material through clear explanations and step-by-step guidance.",
          "\n\n╔═════════════════════════════════════════╗",
          "\n║  MISSION: Explain clearly + Build mastery ║",
          "\n╚═════════════════════════════════════════╝",
          "\n\n🔒 CRITICAL RULE - KNOWLEDGE BASE ONLY:",
          "\n   ⚠️ You MUST use ONLY information from the provided course knowledge base",
          "\n   ⚠️ DO NOT use general knowledge or external sources",
          "\n   ⚠️ If information is NOT in the knowledge base, say: 'This topic isn't covered in your course materials. Please consult your instructor.'",
          "\n\n📖 DIDACTIC TEACHING METHOD:",
          "\n  1. DEFINE: Start with clear definitions using course terminology",
          "\n  2. EXPLAIN: Break concepts into simple, logical steps",
          "\n  3. EXAMPLE: Provide concrete examples from the knowledge base",
          "\n  4. CONNECT: Link to related concepts the student already learned",
          "\n  5. CHECK: Ask if clarification is needed before moving forward",
          "\n\n✅ CLARITY STANDARDS:",
          "\n  - Use simple, direct language - avoid jargon unless defined",
          "\n  - Number steps clearly (Step 1, Step 2, etc.)",
          "\n  - Use analogies when they help understanding",
          "\n  - Highlight formulas separately with clear variable definitions",
          "\n  - Use emojis: 📌 for definitions, 🔢 for formulas, 💡 for key insights, ⚠️ for common mistakes",
          "\n\n🎯 RESPONSE STRUCTURE:",
          "\n  - Short answer: Direct response (200-400 chars)",
          "\n  - Detailed explanation: Structured teaching (no limit, but stay focused)",
          "\n  - Always end with: 'Does this make sense? Would you like me to explain any part differently?'",
          "\n\n📚 COURSE KNOWLEDGE BASE:\n",
          paste(base_knowledge, collapse = "\n")
        )
      )
    )
    cat("[ASK_FLORA] System prompt created (", nchar(messages[[1]]$content), "chars)\n")
    
    # Add conversation history
    if (nrow(history) > 0) {
      for (i in 1:nrow(history)) {
        role <- if (history$direction[i] == "in") "user" else "assistant"
        messages <- append(messages, list(list(
          role = role,
          content = history$message[i]
        )))
      }
      cat("[ASK_FLORA] Added", nrow(history), "history messages to context\n")
    }
    
    # Add current question
    messages <- append(messages, list(list(
      role = "user",
      content = question
    )))
    cat("[ASK_FLORA] Total messages in request:", length(messages), "\n")
    
    # Call OpenAI API
    cat("[ASK_FLORA] Sending request to OpenAI API...\n")
    cat("[ASK_FLORA] Model: gpt-4o-mini\n")
    cat("[ASK_FLORA] Temperature: 0.7\n")
    cat("[ASK_FLORA] Max tokens: 500\n")
    
    api_start <- Sys.time()
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
    api_end <- Sys.time()
    
    cat("[ASK_FLORA] ✓ API response received in", round(as.numeric(api_end - api_start), 2), "seconds\n")
    
    reply <- resp$choices[[1]]$message$content
    cat("[ASK_FLORA] ✓ Response extracted:", nchar(reply), "chars\n")
    cat("[ASK_FLORA] ✓ Response preview:", substr(reply, 1, 100), "...\n")
    
    # Check token usage if available
    if (!is.null(resp$usage)) {
      cat("[ASK_FLORA] Tokens - Prompt:", resp$usage$prompt_tokens, 
          "| Completion:", resp$usage$completion_tokens,
          "| Total:", resp$usage$total_tokens, "\n")
    }
    
    return(reply)
    
  }, error = function(e) {
    cat("[ASK_FLORA ERROR] ❌ Failed to get AI response\n")
    cat("[ASK_FLORA ERROR] Error type:", class(e)[1], "\n")
    cat("[ASK_FLORA ERROR] Error message:", e$message, "\n")
    cat("[ASK_FLORA ERROR] Full error:", toString(e), "\n")
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
    cat("[AUDIO] Starting audio generation...\n")
    cat("[AUDIO] Text length:", nchar(text), "chars\n")
    cat("[AUDIO] Voice:", voice, "\n")
    
    # Clean text for TTS
    cat("[AUDIO] Cleaning text for TTS...\n")
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
    cat("[AUDIO] Cleaned text length:", nchar(clean), "chars\n")
    
    temp_audio <- tempfile(fileext = ".mp3")
    cat("[AUDIO] Temp file:", temp_audio, "\n")
    
    cat("[AUDIO] Calling OpenAI TTS API...\n")
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
    
    cat("[AUDIO] ✓ TTS API response received\n")
    audio_data <- readBin(temp_audio, "raw", file.info(temp_audio)$size)
    cat("[AUDIO] ✓ Audio data read:", length(audio_data), "bytes\n")
    unlink(temp_audio)
    
    return(audio_data)
  }, error = function(e) {
    cat("[AUDIO ERROR] ❌ Failed to generate audio\n")
    cat("[AUDIO ERROR] Error:", e$message, "\n")
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
      /* Reset and base styles */
      body {
        margin: 0;
        padding: 0;
        height: 100vh;
        overflow: hidden;
      }
      
      .container-fluid {
        padding: 0 !important;
        height: 100vh;
      }
      
      /* Main chat container - full screen */
      .chat-container {
        width: 100%;
        height: 100vh;
        display: flex;
        flex-direction: column;
        background: #f5f7fa;
      }
      
      /* Header - modern professional look */
      .chat-header {
        background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #7e8ba3 100%);
        color: white;
        padding: 24px 40px;
        box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        position: relative;
        z-index: 10;
      }
      
      .chat-header h2 {
        margin: 0 0 8px 0;
        font-size: 28px;
        font-weight: 600;
        letter-spacing: -0.5px;
      }
      
      .chat-header p {
        margin: 0;
        opacity: 0.95;
        font-size: 16px;
        font-weight: 400;
      }
      
      /* Messages area - full height with proper scrolling */
      .chat-messages {
        flex: 1;
        overflow-y: auto;
        padding: 30px 20px;
        background: linear-gradient(to bottom, #f5f7fa 0%, #e8ecf1 100%);
      }
      
      /* Custom scrollbar */
      .chat-messages::-webkit-scrollbar {
        width: 8px;
      }
      
      .chat-messages::-webkit-scrollbar-track {
        background: #e8ecf1;
      }
      
      .chat-messages::-webkit-scrollbar-thumb {
        background: #cbd5e0;
        border-radius: 4px;
      }
      
      .chat-messages::-webkit-scrollbar-thumb:hover {
        background: #a0aec0;
      }
      
      /* Message containers */
      .message {
        margin-bottom: 20px;
        display: flex;
        align-items: flex-start;
        animation: fadeIn 0.3s ease-in;
      }
      
      @keyframes fadeIn {
        from {
          opacity: 0;
          transform: translateY(10px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      
      .message.user {
        justify-content: flex-end;
      }
      
      /* Message bubbles */
      .message-bubble {
        max-width: 95%;
        padding: 20px 28px;
        border-radius: 12px;
        word-wrap: break-word;
        white-space: pre-wrap;
        line-height: 1.6;
        font-size: 15px;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
      }
      
      /* User messages - right side, blue */
      .message.user .message-bubble {
        background: linear-gradient(135deg, #2563eb 0%, #1e40af 100%);
        color: white;
        border-bottom-right-radius: 4px;
      }
      
      /* Assistant messages - left side, white */
      .message.assistant .message-bubble {
        background: white;
        color: #1f2937;
        border-bottom-left-radius: 4px;
        box-shadow: 0 2px 12px rgba(0, 0, 0, 0.1);
      }
      
      /* Input area - fixed at bottom */
      .chat-input-area {
        padding: 24px 20px;
        background: white;
        border-top: 1px solid #e5e7eb;
        box-shadow: 0 -4px 12px rgba(0, 0, 0, 0.05);
      }
      
      .input-group {
        display: flex;
        gap: 12px;
        align-items: center;
      }
      
      /* Input field - modern design */
      #user_input {
        flex: 1;
        border-radius: 28px;
        border: 2px solid #e5e7eb;
        padding: 14px 24px;
        font-size: 15px;
        transition: all 0.2s ease;
        background: #f9fafb;
      }
      
      #user_input:focus {
        border-color: #2563eb;
        outline: none;
        box-shadow: 0 0 0 4px rgba(37, 99, 235, 0.1);
        background: white;
      }
      
      /* Send button - modern blue */
      #send_btn {
        border-radius: 28px;
        padding: 14px 32px;
        background: linear-gradient(135deg, #2563eb 0%, #1e40af 100%);
        border: none;
        color: white;
        font-weight: 600;
        font-size: 15px;
        transition: all 0.2s ease;
        cursor: pointer;
        box-shadow: 0 4px 12px rgba(37, 99, 235, 0.3);
      }
      
      #send_btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 16px rgba(37, 99, 235, 0.4);
      }
      
      #send_btn:active {
        transform: translateY(0);
      }
      
      /* Typing indicator */
      .typing-indicator {
        display: none;
        padding: 12px 20px;
        color: #6b7280;
        font-style: italic;
        font-size: 14px;
      }
      
      .typing-indicator.active {
        display: block;
      }
      
      /* Audio player */
      .audio-player {
        margin-top: 12px;
        width: 100%;
        max-width: 400px;
        border-radius: 8px;
      }
      
      /* Welcome message */
      .welcome-message {
        text-align: center;
        color: #6b7280;
        padding: 60px 40px;
        animation: fadeIn 0.5s ease-in;
      }
      
      .welcome-message h3 {
        color: #2563eb;
        margin-bottom: 16px;
        font-size: 20px;
        font-weight: 600;
      }
      
      .welcome-message p {
        color: #6b7280;
        font-size: 15px;
      }
      
      /* Audio checkbox */
      .checkbox {
        display: flex;
        align-items: center;
        gap: 8px;
        color: #6b7280;
        font-size: 14px;
        margin-top: 12px;
        justify-content: center;
      }
      
      /* Responsive design for mobile */
      @media (max-width: 768px) {
        .chat-header {
          padding: 20px 20px;
        }
        
        .chat-header h2 {
          font-size: 22px;
        }
        
        .chat-header p {
          font-size: 14px;
        }
        
        .chat-messages {
          padding: 20px 16px;
        }
        
        .chat-input-area {
          padding: 16px 16px;
        }
        
        .message-bubble {
          max-width: 90%;
          font-size: 14px;
        }
        
        #user_input {
          padding: 12px 18px;
          font-size: 14px;
        }
        
        #send_btn {
          padding: 12px 24px;
          font-size: 14px;
        }
      }
    "))
  ),
  
  div(class = "chat-container",
      div(class = "chat-header",
          h2("💬 FinMentor"),
          p("How can I help?")
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
  
  cat("\n╔════════════════════════════════════════════╗\n")
  cat("║  NEW USER SESSION STARTED                  ║\n")
  cat("╚════════════════════════════════════════════╝\n")
  cat("[SESSION] Session token:", session$token, "\n")
  cat("[SESSION] Database path:", DB_PATH, "\n")
  
  # Initialize database connection
  cat("[DATABASE] Initializing database connection...\n")
  con <- init_database(DB_PATH)
  cat("[DATABASE] ✓ Database connection established\n")
  
  # Generate unique user ID for this session
  user_id <- paste0("web_", session$token)
  cat("[SESSION] User ID:", user_id, "\n")
  cat("════════════════════════════════════════════\n\n")
  
  # Reactive values for messages
  messages <- reactiveVal(list())
  
  # Check if new user and show welcome
  observe({
    cat("[WELCOME] Checking if new user...\n")
    history <- get_user_history(con, user_id, limit = 1)
    cat("[WELCOME] User has", nrow(history), "previous messages\n")
    
    if (nrow(history) == 0) {
      cat("[WELCOME] New user detected! Sending welcome message...\n")
      welcome_msg <- paste0(
        "Hello! 👋 Welcome to your Corporate Finance course!\n\n",
        "I'm Professor Finance, your AI tutor dedicated to helping you master financial concepts. ",
        "I'm here to guide you every step of the way! 📚\n\n",
        "I can help you with:\n",
        "💰 Financial Analysis (ratios, statements, performance metrics)\n",
        "📊 Capital Budgeting (NPV, IRR, project evaluation)\n",
        "💼 Corporate Valuation (DCF, multiples, company worth)\n",
        "🏦 Capital Structure (debt, equity, optimal financing)\n",
        "📈 Risk & Return (CAPM, portfolio theory, cost of capital)\n",
        "💡 Working Capital Management (cash flow, liquidity)\n",
        "🎯 Strategic Financial Decisions\n\n",
        "How can I help you today? 🤓"
      )
      
      log_message(con, user_id, "out", welcome_msg)
      cat("[WELCOME] Welcome message logged to database\n")
      
      current_msgs <- list(list(
        role = "assistant",
        content = welcome_msg,
        timestamp = Sys.time()
      ))
      
      messages(current_msgs)
      cat("[WELCOME] ✓ Welcome message displayed\n")
    } else {
      cat("[WELCOME] Returning user - skipping welcome message\n")
    }
  })
  
  # Send message when button clicked or Enter pressed
  observeEvent(input$send_btn, {
    cat("[EVENT] Send button clicked\n")
    send_message()
  })
  
  observeEvent(input$user_input, {
    if (input$user_input != "" && grepl("\n$", input$user_input)) {
      cat("[EVENT] Enter key pressed in input field\n")
      send_message()
    }
  })
  
  # Send message function
  send_message <- function() {
    user_msg <- trimws(input$user_input)
    
    if (user_msg == "") {
      cat("[DEBUG] Empty message, ignoring\n")
      return()
    }
    
    cat("\n========================================\n")
    cat("[MESSAGE RECEIVED] User:", user_id, "\n")
    cat("[MESSAGE CONTENT] Length:", nchar(user_msg), "chars\n")
    cat("[MESSAGE TEXT]", user_msg, "\n")
    cat("========================================\n")
    
    # Add user message to chat
    current_msgs <- messages()
    current_msgs[[length(current_msgs) + 1]] <- list(
      role = "user",
      content = user_msg,
      timestamp = Sys.time()
    )
    messages(current_msgs)
    cat("[UI] User message added to chat UI\n")
    
    # Log user message
    tryCatch({
      log_message(con, user_id, "in", user_msg)
      cat("[DATABASE] User message logged successfully\n")
    }, error = function(e) {
      cat("[DATABASE ERROR] Failed to log user message:", e$message, "\n")
    })
    
    # Clear input
    updateTextInput(session, "user_input", value = "")
    cat("[UI] Input field cleared\n")
    
    # Show typing indicator
    tryCatch({
      shinyjs::runjs("document.getElementById('typing_indicator').classList.add('active');")
      cat("[UI] Typing indicator shown\n")
    }, error = function(e) {
      cat("[UI ERROR] Failed to show typing indicator:", e$message, "\n")
    })
    
    # Get AI response
    cat("[AI] Calling OpenAI API...\n")
    start_time <- Sys.time()
    reply <- ask_flora(user_msg, user_id, con, base_texto, OPENAI_API_KEY)
    end_time <- Sys.time()
    cat("[AI] Response received in", round(as.numeric(end_time - start_time), 2), "seconds\n")
    cat("[AI] Response length:", nchar(reply), "chars\n")
    cat("[AI] Response preview:", substr(reply, 1, 100), "...\n")
    
    # Log assistant message
    tryCatch({
      log_message(con, user_id, "out", reply)
      cat("[DATABASE] AI response logged successfully\n")
    }, error = function(e) {
      cat("[DATABASE ERROR] Failed to log AI response:", e$message, "\n")
    })
    
    # Generate audio if enabled
    audio_data <- NULL
    if (input$enable_audio && nchar(reply) <= 1000) {
      cat("[AUDIO] Generating audio response (voice:", AUDIO_VOICE, ")\n")
      audio_start <- Sys.time()
      audio_data <- generate_audio(reply, AUDIO_VOICE)
      audio_end <- Sys.time()
      if (!is.null(audio_data)) {
        cat("[AUDIO] Audio generated successfully in", round(as.numeric(audio_end - audio_start), 2), "seconds\n")
        cat("[AUDIO] Audio size:", length(audio_data), "bytes\n")
      } else {
        cat("[AUDIO] Audio generation failed\n")
      }
    } else if (input$enable_audio) {
      cat("[AUDIO] Response too long for audio (", nchar(reply), "chars)\n")
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
    cat("[UI] AI response added to chat UI\n")
    
    # Hide typing indicator
    tryCatch({
      shinyjs::runjs("document.getElementById('typing_indicator').classList.remove('active');")
      cat("[UI] Typing indicator hidden\n")
    }, error = function(e) {
      cat("[UI ERROR] Failed to hide typing indicator:", e$message, "\n")
    })
    
    # Scroll to bottom
    tryCatch({
      shinyjs::runjs("
        var chatMessages = document.getElementById('chat_messages');
        chatMessages.scrollTop = chatMessages.scrollHeight;
      ")
      cat("[UI] Scrolled to bottom\n")
    }, error = function(e) {
      cat("[UI ERROR] Failed to scroll:", e$message, "\n")
    })
    
    cat("[COMPLETE] Message processing finished\n")
    cat("========================================\n\n")
  }
  
  # Render messages UI
  output$messages_ui <- renderUI({
    msgs <- messages()
    cat("[UI RENDER] Rendering", length(msgs), "messages\n")
    
    if (length(msgs) == 0) {
      cat("[UI RENDER] No messages - showing welcome placeholder\n")
      return(div(class = "welcome-message",
                 h3("👋 Bem-vindo!"),
                 p("Faça sua primeira pergunta para começar.")))
    }
    
    cat("[UI RENDER] Building UI for", length(msgs), "messages\n")
    lapply(msgs, function(msg) {
      msg_class <- if (msg$role == "user") "message user" else "message assistant"
      
      content_div <- div(class = "message-bubble", HTML(gsub("\n", "<br>", msg$content)))
      
      # Add audio player if audio data is available
      if (!is.null(msg$audio)) {
        cat("[UI RENDER] Adding audio player for message\n")
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
    cat("\n[SESSION] User session ending:", user_id, "\n")
    cat("[DATABASE] Closing database connection...\n")
    dbDisconnect(con)
    cat("[DATABASE] ✓ Connection closed\n")
    cat("[SESSION] ✓ Session ended\n\n")
  })
}

# ============================================================================
# RUN APP
# ============================================================================

shinyApp(ui = ui, server = server)