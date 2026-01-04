# canvas_auth.R - Production version for Render
library(httr)
library(jsonlite)

# Get from Canvas Developer Keys
CANVAS_BASE_URL <- Sys.getenv("CANVAS_BASE_URL", "https://YOUR_INSTITUTION.instructure.com")
CANVAS_CLIENT_ID <- Sys.getenv("CANVAS_CLIENT_ID")
CANVAS_CLIENT_SECRET <- Sys.getenv("CANVAS_CLIENT_SECRET")

# Redirect URI - automatically detects if running locally or on Render
get_redirect_uri <- function() {
  # Check if running on Render (production)
  render_url <- Sys.getenv("RENDER_EXTERNAL_URL")
  
  if (render_url != "") {
    # Production: use Render URL
    return(render_url)
  } else {
    # Local development
    return("http://localhost:3838")
  }
}

REDIRECT_URI <- get_redirect_uri()

# Step 1: Redirect to Canvas login
get_canvas_auth_url <- function() {
  paste0(
    CANVAS_BASE_URL, "/login/oauth2/auth?",
    "client_id=", CANVAS_CLIENT_ID,
    "&response_type=code",
    "&redirect_uri=", URLencode(REDIRECT_URI),
    "&scope=url:GET|/api/v1/users/:user_id"
  )
}

# Step 2: Exchange code for token
get_canvas_token <- function(code) {
  response <- POST(
    url = paste0(CANVAS_BASE_URL, "/login/oauth2/token"),
    body = list(
      grant_type = "authorization_code",
      client_id = CANVAS_CLIENT_ID,
      client_secret = CANVAS_CLIENT_SECRET,
      redirect_uri = REDIRECT_URI,
      code = code
    ),
    encode = "form"
  )
  
  content(response, as = "parsed")
}

# Step 3: Get user info from Canvas
get_canvas_user <- function(access_token) {
  response <- GET(
    url = paste0(CANVAS_BASE_URL, "/api/v1/users/self"),
    add_headers(Authorization = paste("Bearer", access_token))
  )
  
  content(response, as = "parsed")
}

# Step 4: Check course enrollment
check_enrollment <- function(access_token, course_id) {
  response <- GET(
    url = paste0(CANVAS_BASE_URL, "/api/v1/courses/", course_id, "/enrollments"),
    add_headers(Authorization = paste("Bearer", access_token)),
    query = list(
      type = "StudentEnrollment",
      state = "active"
    )
  )
  
  enrollments <- content(response, as = "parsed")
  return(length(enrollments) > 0)
}
