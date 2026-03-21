# ElevenLabs Agent Connection Troubleshooting Guide

## Issue: Widget Not Reaching Agent

If your messages aren't reaching the ElevenLabs agent, follow this debugging guide.

## Debug Logging Output

When you send a message, watch the Xcode console for these log messages:

### Expected Flow (Success)
```
📤 [Widget] Sending message: Hello
✅ [Widget] Saved user message
🚀 [Widget] Calling ElevenLabs service...
🎤 [ElevenLabs] Sending message: Hello
🎤 [ElevenLabs] Request URL: https://elevenlabs-proxy.taylordrew4u.workers.dev
🎤 [ElevenLabs] Request Body: ["message": "Hello", "access_code": "9856"]
🎤 [ElevenLabs] Response Status: 200
🎤 [ElevenLabs] Response Data: {...}
🎤 [ElevenLabs] Parsed JSON: {...}
📥 [Widget] Received response: <agent response>
✅ [Widget] Saved AI response
```

## Troubleshooting Steps

### Step 1: Check Proxy URL
The proxy URL configured is:
```
https://elevenlabs-proxy.taylordrew4u.workers.dev
```

**Check if it's accessible:**
- Open this URL in a web browser
- You should see a proxy response (not a 404 or error)

**If it's down:**
- Verify the Cloudflare Worker is running
- Check the worker logs in Cloudflare dashboard

### Step 2: Verify Access Code
Access code: `9856`

**If you see error 401/403 in logs:**
- Access code might be wrong
- Verify code matches your proxy setup
- Update in ElevenLabsAgentService.swift line 20

### Step 3: Check Console Logs

**Send a test message and look for:**

1. **"🚀 [Widget] Calling ElevenLabs service..."**
   - Confirms widget is sending the request

2. **"🎤 [ElevenLabs] Response Status: XXX"**
   - 200 = Success ✅
   - 400 = Bad request (check message format)
   - 401/403 = Auth error (check access code)
   - 500 = Server error (proxy issue)
   - Other = Network issue

3. **"🎤 [ElevenLabs] Response Data:"**
   - Shows actual response from proxy
   - Copy this for troubleshooting

### Step 4: Test Proxy Directly

You can test the proxy endpoint directly from a terminal:

```bash
curl -X POST https://elevenlabs-proxy.taylordrew4u.workers.dev \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello",
    "access_code": "9856"
  }'
```

**Expected response:**
- Status: 200
- Body: JSON with "response" or "message" field

### Step 5: Verify Agent Configuration

Current configuration:
- **Agent ID**: `agent_7401ka31ry6qftr9ab89em3339w9`
- **API Key**: `sk_40b434d2a8deebbb7c6683dba782412a0dcc9ff571d042ca`
- **Access Code**: `9856`
- **Proxy URL**: `https://elevenlabs-proxy.taylordrew4u.workers.dev`

**If any have changed:**
1. Update in `ElevenLabsAgentService.swift` (lines 18-21)
2. Rebuild and test

### Step 6: Network Connectivity

**Check if network is the issue:**
- Send a message
- Look for any network error messages
- Try with WiFi + mobile data

**If still failing:**
- Check firewall/VPN blocking
- Try from different network

## Common Error Messages & Solutions

### "Response Status: 400"
**Problem**: Bad request format  
**Solution**:
- Check message is not empty
- Check JSON serialization is working
- Verify access code format

### "Response Status: 401/403"
**Problem**: Authentication failed  
**Solution**:
- Verify access code: `9856`
- Check proxy is configured with correct code
- Ask proxy administrator to reset credentials

### "Response Status: 500"
**Problem**: Proxy server error  
**Solution**:
- Proxy service might be down
- Check Cloudflare Worker status
- Restart the worker if needed

### "Response Status: Other (502, 503, 504)"
**Problem**: Service temporarily unavailable  
**Solution**:
- Wait a few moments and retry
- Check if ElevenLabs API is having issues
- Check proxy gateway status

### "No data" or Empty Response
**Problem**: Empty response body  
**Solution**:
- Check proxy is returning valid JSON
- Verify agent is properly configured
- Check conversation ID is being saved

### Message appears in widget but doesn't reach agent
Problem: Message saves but agent isn't responding
**Solution**:
- Check ElevenLabs service status
- Verify proxy endpoint is correct
- Check network connectivity

## Advanced Debugging

### Add Test Message

Edit `ElevenLabsAgentService.swift` to add a test endpoint:

```swift
func testConnection() async throws -> String {
    print("🧪 Testing proxy connection...")
    return try await sendToProxy("Test message from BitBuddy")
}
```

Then call from widget:
```swift
let testResponse = try await elevenLabsService.testConnection()
print("Test response: \(testResponse)")
```

### Enable Network Logging

To log all HTTP requests, add to AppDelegate:

```swift
let config = URLSessionConfiguration.default
config.waitsForConnectivity = true
config.shouldUseExtendedBackgroundIdleMode = true
```

### Check Proxy Logs

If you have access to Cloudflare Workers dashboard:
1. Go to Workers → your worker
2. Check "Tail" for real-time logs
3. Look for requests matching your message text

## Quick Checklist

- [ ] Proxy URL is accessible from browser
- [ ] Access code is correct (9856)
- [ ] Console shows "Response Status: 200"
- [ ] JSON response has expected fields
- [ ] No network errors in console
- [ ] Agent ID is valid
- [ ] Agent is active in ElevenLabs dashboard

## Still Not Working?

1. **Collect debug information:**
   - Copy all console output
   - Screenshot of error messages
   - Current configuration values
   - Exact message you sent

2. **Check proxy logs:**
   - Access Cloudflare dashboard
   - View worker tail logs
   - Look for your requests

3. **Test proxy independently:**
   - Use curl command above
   - Try from different network
   - Verify with raw HTTP client

4. **Verify agent status:**
   - Log into ElevenLabs dashboard
   - Confirm agent exists
   - Check agent is active/enabled
   - Verify credentials match

## Debug Output Example

Here's what successful debug output should look like:

```
📤 [Widget] Sending message: How do I structure a joke?
✅ [Widget] Saved user message
🚀 [Widget] Calling ElevenLabs service...
🎤 [ElevenLabs] Sending message: How do I structure a joke?
🎤 [ElevenLabs] Request URL: https://elevenlabs-proxy.taylordrew4u.workers.dev
🎤 [ElevenLabs] Request Body: ["message": "How do I structure a joke?", "access_code": "9856"]
🎤 [ElevenLabs] Response Status: 200
🎤 [ElevenLabs] Response Data: {"response":"A joke typically has setup, build-up, and punchline..."}
🎤 [ElevenLabs] Parsed JSON: ["response": "A joke typically..."]
📥 [Widget] Received response: A joke typically has setup, build-up, and punchline...
✅ [Widget] Saved AI response
```

---

## Support Resources

- **ElevenLabs Documentation**: https://elevenlabs.io/docs
- **Agent API Docs**: https://elevenlabs.io/docs/agents
- **Proxy Setup Guide**: Check your proxy configuration documentation

---

**Last Updated**: February 20, 2026
