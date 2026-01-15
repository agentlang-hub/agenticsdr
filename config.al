{
  "agentlang": {
    "service": {
      "port": 8080
    },
    "store": {
      "type": "sqlite",
      "dbname": "agenticsdr.db"
    },
    "monitoring": {
      "enabled": true
    },
    "retry": [
      {
        "name": "classifyRetry",
        "attempts": 3,
        "backoff": {
          "strategy": "linear",
          "delay": 2,
          "magnitude": "seconds",
          "factor": 2
        }
      }
    ]
  },
  "gmail": {
    "gmail/GmailConfig": {
      "gmailClientId": "#js getLocalEnv('GMAIL_CLIENT_ID', '')",
      "gmailClientSecret": "#js getLocalEnv('GMAIL_CLIENT_SECRET', '')",
      "gmailRefreshToken": "#js getLocalEnv('GMAIL_REFRESH_TOKEN', '')",
      "gmailPollIntervalMinutes": "#js parseInt(getLocalEnv('GMAIL_POLL_INTERVAL_MINUTES', '15'))",
      "gmailPollMinutes": "#js parseInt(getLocalEnv('GMAIL_POLL_MINUTES', '2'))"
    }
  },
  "agenticsdr": {
    "agenticsdr.core/SDRConfig": {
      "gmailOwnerEmail": "#js getLocalEnv('GMAIL_EMAIL', '')",
      "hubspotOwnerId": "#js getLocalEnv('HUBSPOT_OWNER_ID', '')"
    }
  },
  "hubspot": {
    "hubspot/HubSpotConfig": {
      "accessToken": "#js getLocalEnv('HUBSPOT_ACCESS_TOKEN', '')",
      "pollIntervalMinutes": "#js parseInt(getLocalEnv('HUBSPOT_POLL_INTERVAL_MINUTES', '15'))",
      "searchResultLimit": "#js parseInt(getLocalEnv('HUBSPOT_SEARCH_RESULT_LIMIT', '100'))",
      "apiTimeout": "#js parseInt(getLocalEnv('HUBSPOT_API_TIMEOUT_MS', '30000'))",
      "active": true
    }
  },
  "agentlang.ai": [
    {
      "agentlang.ai/LLM": {
                "name": "sonnet_llm",
                "service": "anthropic",
                "config": {
                    "model": "claude-sonnet-4-5"
                }
            }
    },
    {
      "agentlang.ai/LLM": {
                "name": "gpt_llm",
                "service": "openai",
                "config": {
                    "model": "gpt-5.2"
                }
            }
    }
  ]
}
