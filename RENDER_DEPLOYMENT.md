# 🚀 Deploying to Render.com - Complete Guide

This guide will walk you through deploying your SEBRAE chatbot to Render.com so you can share it with your students.

## 📋 Prerequisites

1. **GitHub Account** - To host your code
2. **Render Account** - Free at [render.com](https://render.com)
3. **OpenAI API Key** - From [platform.openai.com](https://platform.openai.com/api-keys)

## 🎯 Quick Deploy (Recommended)

### Option 1: Deploy with render.yaml (Easiest!)

1. **Push your code to GitHub:**
```bash
cd "c:/users/dimas/Dropbox/NUS/teaching/2025-2026/AI/render4"

# Initialize git repository
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit - SEBRAE Shiny Chatbot"

# Add your GitHub repository
git remote add origin https://github.com/dfazio13/ai.git

# Push to GitHub
git push -u origin main
```

2. **Connect to Render:**
   - Go to [dashboard.render.com](https://dashboard.render.com)
   - Click **"New +"** → **"Blueprint"**
   - Connect your GitHub repository
   - Render will automatically detect `render.yaml`
   - Click **"Apply"**

3. **Add your OpenAI API Key:**
   - After deployment starts, go to your service
   - Click **"Environment"** in the left sidebar
   - Find `OPENAI_API_KEY` 
   - Click **"Generate Value"** or enter your key manually
   - Click **"Save Changes"**

4. **Wait for deployment** (5-10 minutes first time)

5. **Access your app** at: `https://sebrae-chatbot.onrender.com`

That's it! 🎉

---

## 🔧 Option 2: Manual Deployment

If you prefer to set up manually:

### Step 1: Push Code to GitHub

```bash
git init
git add .
git commit -m "SEBRAE Shiny Chatbot"
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPO.git
git push -u origin main
```

### Step 2: Create New Web Service on Render

1. Go to [dashboard.render.com](https://dashboard.render.com)
2. Click **"New +"** → **"Web Service"**
3. Connect your GitHub repository
4. Configure the service:

**Basic Settings:**
- **Name:** `sebrae-chatbot` (or your choice)
- **Region:** Choose closest to your students
- **Branch:** `main`
- **Root Directory:** Leave empty
- **Environment:** `Docker`

**Plan:**
- Select **"Free"** (or paid plan for better performance)

**Advanced:**
- **Auto-Deploy:** ✅ Yes (automatic updates when you push to GitHub)
- **Health Check Path:** `/`

### Step 3: Add Environment Variables

In the **Environment** section, add:

| Key | Value | Notes |
|-----|-------|-------|
| `OPENAI_API_KEY` | `sk-your-key-here` | **Required** - Your OpenAI API key |
| `ENABLE_AUDIO_RESPONSES` | `true` | Optional - Enable voice responses |
| `AUDIO_VOICE` | `nova` | Optional - Voice selection |
| `PORT` | `10000` | Auto-set by Render |

### Step 4: Add Persistent Disk (Important!)

To save conversation history:

1. In your service settings, find **"Disks"**
2. Click **"Add Disk"**
3. Configure:
   - **Name:** `chat-data`
   - **Mount Path:** `/app/data`
   - **Size:** `1 GB` (free tier)
4. Click **"Save"**

### Step 5: Deploy!

1. Click **"Create Web Service"**
2. Wait for the build (5-10 minutes first time)
3. Your app will be live at: `https://YOUR-APP-NAME.onrender.com`

---

## 📁 Required Files Checklist

Make sure these files are in your repository:

```
✅ shiny_app.R                          # Main app
✅ Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt  # Knowledge base
✅ Dockerfile                           # Container config
✅ render.yaml                          # Render config (optional but recommended)
✅ .gitignore                          # Git ignore rules
✅ README.md                           # Documentation
```

**Important:** Do NOT commit `.Renviron` with real API keys!

---

## 🎓 Sharing with Students

### Option 1: Direct Link
Simply share: `https://your-app-name.onrender.com`

### Option 2: QR Code
1. Generate QR code at [qr-code-generator.com](https://www.qr-code-generator.com/)
2. Use your Render URL
3. Add to presentations/handouts

### Option 3: Custom Domain (Optional)
1. In Render dashboard, go to **"Settings"**
2. Scroll to **"Custom Domains"**
3. Add your domain (e.g., `chatbot.seusite.com.br`)
4. Follow DNS instructions

---

## ⚙️ Configuration Options

### Free Tier Limitations
- **Sleep after 15 min inactivity** - First request takes ~30 seconds to wake up
- **750 hours/month** - Usually sufficient for classroom use
- **100 GB bandwidth/month**
- **512 MB RAM**

### Upgrade Considerations
If you have many students using it simultaneously:
- **Starter ($7/month):** No sleep, better performance
- **Standard ($25/month):** More RAM, faster responses

### Audio Responses
Audio responses use more bandwidth and API credits:
```yaml
# In render.yaml or Environment Variables
ENABLE_AUDIO_RESPONSES: true  # Enable voice
AUDIO_VOICE: nova             # Voice choice
```

Cost impact: ~$0.015 per audio response

---

## 🔍 Monitoring Your App

### View Logs
1. Go to your service on Render
2. Click **"Logs"** tab
3. See real-time activity and errors

### Check Health
Visit: `https://your-app-name.onrender.com/`
Should show the chat interface

### Monitor Usage
- Go to **"Metrics"** tab on Render
- See requests, CPU, memory usage
- Monitor bandwidth

### Database Backup
Download conversation history:
1. Go to **"Shell"** tab in Render
2. Run: `cat /app/data/chat_sessions.db > ~/backup.db`
3. Download from Render dashboard

---

## 🐛 Troubleshooting

### Issue: "Application Failed to Respond"
**Cause:** App crashed or taking too long to start
**Solution:**
1. Check logs for errors
2. Verify `OPENAI_API_KEY` is set correctly
3. Make sure `Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt` is in repo
4. Try manual deploy

### Issue: "API Key Not Found"
**Solution:**
1. Go to **Environment** in Render
2. Add `OPENAI_API_KEY` variable
3. Click **"Save Changes"**
4. Manually deploy again

### Issue: App Sleeps on Free Tier
**Solution:**
1. **Upgrade to paid plan** ($7/month - no sleep)
2. **Use cron-job.org** to ping app every 14 minutes:
   - Sign up at [cron-job.org](https://cron-job.org)
   - Add job: `GET https://your-app.onrender.com`
   - Schedule: Every 14 minutes
3. **Accept the limitation** - First request takes 30 seconds

### Issue: "Out of Memory"
**Cause:** Too many simultaneous users on free tier
**Solution:**
- Upgrade to Starter plan (more RAM)
- Optimize by disabling audio: `ENABLE_AUDIO_RESPONSES=false`
- Ask students to close tabs when done

### Issue: Database Not Persisting
**Solution:**
1. Check **Disks** in Render settings
2. Ensure disk is mounted to `/app/data`
3. Verify mount path matches in `shiny_app.R`

### Issue: Can't Access Knowledge Base
**Solution:**
1. Verify `Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt` is in GitHub repo
2. Check file encoding is UTF-8
3. Look at logs for file read errors

---

## 🔄 Updating Your App

### Automatic Updates (If auto-deploy enabled)
```bash
# Make changes locally
git add .
git commit -m "Update chatbot responses"
git push origin main
# Render automatically deploys!
```

### Manual Updates
1. Make changes locally
2. Push to GitHub
3. Go to Render dashboard
4. Click **"Manual Deploy"** → **"Deploy latest commit"**

---

## 💰 Cost Estimation for Classroom Use

### Render Costs
- **Free tier:** $0/month (with sleep)
- **Starter:** $7/month (no sleep, better for active classes)

### OpenAI Costs (approximate)
- **GPT-4o-mini:** ~$0.01 per conversation (very cheap!)
- **Audio responses:** ~$0.015 per response
- **Example:** 30 students, 10 conversations each = ~$3/month

**Total estimated cost:** $7-10/month for active classroom use

---

## 🎨 Customization Ideas

### Change App Name/Branding
Edit in `shiny_app.R`:
```r
h2("💬 Mia - Assistente Virtual SEBRAE"),
# Change to:
h2("💬 [Your Institution] - Chat Assistant"),
```

### Add Authentication
Require login for students:
```r
# Add to top of server function
if (is.null(session$user)) {
  showModal(modalDialog(
    title = "Login Required",
    textInput("student_id", "Student ID:"),
    footer = actionButton("login", "Login")
  ))
}
```

### Custom Analytics
Track which topics students ask about:
```r
# Log topics
topic <- extract_topic(user_msg)
log_analytics(user_id, topic, timestamp)
```

---

## 📊 Student Usage Guidelines

Share these tips with your students:

### Getting Started
1. Visit: `https://your-app.onrender.com`
2. Wait for Mia's welcome message
3. Type your question in Portuguese
4. Press Enter or click "Enviar"

### Best Practices
- **Be specific** in your questions
- **One topic at a time** works best
- **Use the menu options** Mia provides
- **Refresh the page** if something goes wrong

### Privacy
- Conversations are saved for learning purposes
- Don't share personal sensitive information
- Each browser session gets a unique ID

---

## 🆘 Getting Help

### Documentation
- **README.md** - General setup and usage
- **MIGRATION_GUIDE.md** - Technical details
- **This Guide** - Render-specific deployment

### Render Support
- [Render Documentation](https://render.com/docs)
- [Render Community Forum](https://community.render.com/)
- [Render Status Page](https://status.render.com/)

### OpenAI Issues
- [OpenAI Platform Status](https://status.openai.com/)
- [OpenAI Documentation](https://platform.openai.com/docs)
- Check API key validity and credits

---

## ✅ Post-Deployment Checklist

After successful deployment:

- [ ] App is accessible at Render URL
- [ ] Welcome message appears correctly
- [ ] Chat functionality works (send/receive messages)
- [ ] Knowledge base responses are accurate
- [ ] Audio works (if enabled)
- [ ] Database persists conversations
- [ ] Logs show no errors
- [ ] Share URL with test group
- [ ] Collect initial feedback
- [ ] Monitor usage and performance
- [ ] Set up backup routine

---

## 🎉 Success!

Your chatbot is now live and ready for students! 

**Your app URL:** `https://YOUR-APP-NAME.onrender.com`

**Next steps:**
1. Test thoroughly with different questions
2. Share with a small group first
3. Collect feedback and iterate
4. Monitor usage and costs
5. Enjoy helping students learn! 🎓

---

**Questions?** Check the troubleshooting section or review the logs in Render dashboard.

**Need help?** Post in Render Community or check Render's excellent documentation.

Good luck with your deployment! 🚀
