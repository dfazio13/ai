# openai_helper.R
library(httr)
library(jsonlite)

# Store API key securely (use .Renviron file)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")

chat_with_ai <- function(messages, model = "gpt-4o") {
  
  response <- POST(
    url = "https://api.openai.com/v1/chat/completions",
    add_headers(
      "Authorization" = paste("Bearer", OPENAI_API_KEY),
      "Content-Type" = "application/json"
    ),
    body = toJSON(list(
      model = model,
      messages = messages,
      temperature = 0.7,
      max_tokens = 1000
    ), auto_unbox = TRUE),
    encode = "json"
  )
  
  if (status_code(response) == 200) {
    content <- content(response, as = "parsed")
    return(list(
      message = content$choices[[1]]$message$content,
      tokens = content$usage$total_tokens,
      cost = calculate_cost(content$usage, model)
    ))
  } else {
    stop("OpenAI API error: ", content(response, as = "text"))
  }
}

calculate_cost <- function(usage, model) {
  # GPT-4o pricing (as of 2024)
  if (model == "gpt-4o") {
    input_cost <- usage$prompt_tokens * 0.005 / 1000
    output_cost <- usage$completion_tokens * 0.015 / 1000
    return(input_cost + output_cost)
  }
  return(0)
}