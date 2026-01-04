# SEBRAE Chatbot - Shiny Web Application

A modern web-based chatbot powered by OpenAI GPT, designed to help Brazilian entrepreneurs with business guidance from SEBRAE (Brazilian Micro and Small Business Support Service).

## 🎯 Key Features

- **Interactive Web Chat Interface**: Modern, responsive chat UI built with Shiny
- **AI-Powered Responses**: Uses OpenAI GPT-4 for intelligent conversations
- **Audio Support**: Optional text-to-speech responses
- **Conversation History**: SQLite database stores all conversations
- **Portuguese Language**: Fully optimized for Brazilian Portuguese
- **Knowledge Base**: Specialized SEBRAE knowledge for MEI (Individual Microentrepreneur) guidance

## 📋 What Changed from Twilio Version

### Before (Twilio)
- WhatsApp integration via Twilio webhooks
- Plumber API for webhook handling
- SMS/WhatsApp message delivery
- Required Twilio account and phone number

### After (Shiny)
- **Web-based chat interface** - No Twilio needed!
- Clean, modern UI with gradient design
- Real-time chat experience
- Direct browser access
- No SMS/phone costs

## 🚀 Quick Start

### Prerequisites

1. **R** (version 4.0 or higher)
2. **OpenAI API Key** - Get one at [https://platform.openai.com/api-keys](https://platform.openai.com/api-keys)

### Installation

1. Install required R packages:
```r
install.packages(c(
  "shiny",
  "bslib",
  "httr2",
  "jsonlite",
  "DBI",
  "RSQLite",
  "curl",
  "base64enc"
))
```

2. Set up environment variables:
```bash
# Copy the example file
cp .Renviron.example .Renviron

# Edit .Renviron and add your OpenAI API key
OPENAI_API_KEY=sk-your-actual-key-here
ENABLE_AUDIO_RESPONSES=true
AUDIO_VOICE=nova
```

3. Run the application:
```r
# Option 1: Run directly
shiny::runApp("shiny_app.R", port = 3838)

# Option 2: Use the helper script
source("run_local.R")
```

4. Open your browser at `http://localhost:3838`

## 🐳 Docker Deployment

### Build and Run with Docker

```bash
# Build the Docker image
docker build -t sebrae-chatbot .

# Run the container
docker run -p 8080:8080 \
  -e OPENAI_API_KEY=your_key_here \
  -e ENABLE_AUDIO_RESPONSES=true \
  -v $(pwd)/data:/app/data \
  sebrae-chatbot
```

Access at `http://localhost:8080`

## ☁️ Deploy to Cloud Services

### Render.com

1. Create a new Web Service
2. Connect your GitHub repository
3. Configure:
   - **Environment**: Docker
   - **Build Command**: `docker build -t sebrae-chatbot .`
   - **Start Command**: Automatic from Dockerfile
4. Add environment variable:
   - `OPENAI_API_KEY` = your OpenAI key

### Shinyapps.io

```r
# Install rsconnect
install.packages("rsconnect")

# Configure your account
rsconnect::setAccountInfo(
  name = "your-account",
  token = "your-token",
  secret = "your-secret"
)

# Deploy
rsconnect::deployApp(
  appName = "sebrae-chatbot",
  appFiles = c("shiny_app.R", "Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt")
)
```

### Heroku

1. Install Heroku CLI
2. Create app:
```bash
heroku create your-app-name
heroku stack:set container
git push heroku main
heroku config:set OPENAI_API_KEY=your_key_here
```

## 📁 Project Structure

```
├── shiny_app.R                          # Main Shiny application
├── Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt  # Knowledge base
├── Dockerfile                           # Docker configuration
├── run_local.R                          # Local development script
├── .Renviron.example                    # Environment variables template
├── data/                                # SQLite database and audio files
│   ├── chat_sessions.db                 # Conversation history
│   └── audio/                           # Generated audio responses
└── README.md                            # This file
```

## 🎨 UI Features

- **Gradient Header**: Beautiful purple gradient design
- **Message Bubbles**: User messages (right, purple) and bot messages (left, white)
- **Typing Indicator**: Shows when Mia is thinking
- **Audio Player**: Optional audio responses with inline player
- **Responsive Design**: Works on desktop, tablet, and mobile
- **Emoji Support**: Rich emoji usage for better communication

## 💡 Usage Examples

### Basic Questions
```
User: "Quanto custa abrir MEI?"
Mia: "Ótima notícia! 🚀 Abrir MEI é totalmente GRATUITO!
      Você só paga o imposto mensal (DAS)..."
```

### Knowledge Base Queries
```
User: "Como fazer fluxo de caixa?"
Mia: "Oi! Fluxo de caixa é o controle de entradas e saídas...
      💡 Dica: O SEBRAE tem planilha gratuita!"
```

## 🔧 Configuration Options

### Environment Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `OPENAI_API_KEY` | OpenAI API key (required) | - | Your API key |
| `ENABLE_AUDIO_RESPONSES` | Enable text-to-speech | `false` | `true`/`false` |
| `AUDIO_VOICE` | TTS voice selection | `nova` | `alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer` |

### Voice Options
- **alloy**: Neutral, balanced voice
- **echo**: Clear, professional voice
- **fable**: Warm, expressive voice
- **onyx**: Deep, authoritative voice
- **nova**: Friendly, energetic voice ⭐ (recommended)
- **shimmer**: Soft, gentle voice

## 📊 Database

The app uses SQLite to store conversation history:

```sql
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT,           -- Unique user identifier
  direction TEXT,         -- "in" (user) or "out" (assistant)
  message TEXT,           -- Message content
  created_at TIMESTAMP    -- Creation timestamp
)
```

Access database file at: `data/chat_sessions.db`

## 🐛 Troubleshooting

### Issue: "OPENAI_API_KEY environment variable not set!"
**Solution**: Create `.Renviron` file with your API key

### Issue: Audio not playing
**Solution**: 
1. Check `ENABLE_AUDIO_RESPONSES=true` in `.Renviron`
2. Ensure browser supports HTML5 audio
3. Check browser console for errors

### Issue: Database locked error
**Solution**: Close other connections to `chat_sessions.db`

### Issue: Port already in use
**Solution**: Change port in `runApp()`:
```r
shiny::runApp("shiny_app.R", port = 8080)
```

## 🔒 Security Notes

1. **Never commit** `.Renviron` with real API keys
2. Use `.gitignore` to exclude sensitive files:
```gitignore
.Renviron
*.db
data/
audio/
```
3. Rotate API keys regularly
4. Use environment variables in production

## 📝 Development Notes

### Adding New Knowledge

Edit `Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt` with new information. The AI will automatically use it in responses.

### Customizing UI

Modify CSS in `tags$style(HTML("..."))` section of `shiny_app.R`:
- Change colors in gradient backgrounds
- Adjust message bubble styles
- Modify fonts and spacing

### Extending Functionality

Common extensions:
- Add user authentication
- Implement conversation export
- Add file upload support
- Create admin dashboard
- Add analytics tracking

## 📜 License

This project is for educational and business support purposes.

## 🆘 Support

For issues and questions:
1. Check this README
2. Review error messages in R console
3. Inspect browser console (F12) for JavaScript errors
4. Verify API key is valid and has credits

## 🎉 Credits

- **OpenAI**: GPT-4 and Whisper API
- **SEBRAE**: Knowledge base content
- **R Shiny**: Web framework
- **Community**: Open-source packages used

---

Made with ❤️ for Brazilian entrepreneurs
