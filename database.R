# database.R
library(DBI)
library(RSQLite)

# Initialize database
init_database <- function() {
  con <- dbConnect(SQLite(), "ai_tutor.db")
  
  # Create tables
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS users (
      user_id TEXT PRIMARY KEY,
      name TEXT,
      email TEXT,
      first_login TIMESTAMP,
      last_login TIMESTAMP
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS usage_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      tokens_used INTEGER,
      cost_usd REAL,
      conversation_length INTEGER,
      FOREIGN KEY(user_id) REFERENCES users(user_id)
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS conversations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      session_id TEXT,
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      role TEXT,
      content TEXT,
      FOREIGN KEY(user_id) REFERENCES users(user_id)
    )
  ")
  
  dbDisconnect(con)
}

# Log student login
log_student_login <- function(user_id, name) {
  con <- dbConnect(SQLite(), "ai_tutor.db")
  
  dbExecute(con, "
    INSERT OR REPLACE INTO users (user_id, name, last_login)
    VALUES (?, ?, CURRENT_TIMESTAMP)
  ", params = list(user_id, name))
  
  dbDisconnect(con)
}

# Log API usage
log_usage <- function(user_id, tokens, cost, conversation_length) {
  con <- dbConnect(SQLite(), "ai_tutor.db")
  
  dbExecute(con, "
    INSERT INTO usage_log (user_id, tokens_used, cost_usd, conversation_length)
    VALUES (?, ?, ?, ?)
  ", params = list(user_id, tokens, cost, conversation_length))
  
  dbDisconnect(con)
}

# Get user statistics
get_user_stats <- function(user_id) {
  con <- dbConnect(SQLite(), "ai_tutor.db")
  
  stats <- dbGetQuery(con, "
    SELECT 
      COUNT(*) as message_count,
      SUM(tokens_used) as total_tokens,
      SUM(cost_usd) as total_cost
    FROM usage_log
    WHERE user_id = ?
  ", params = list(user_id))
  
  dbDisconnect(con)
  return(as.list(stats))
}

# Initialize on first run
init_database()