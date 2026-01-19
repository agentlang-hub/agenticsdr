module agenticsdr.core

entity SDRConfig {
    id UUID @id @default(uuid()),
    gmailOwnerEmail String,
    hubspotOwnerId String
}

entity ThreadState {
    threadId String @id,
    contactIds String[],
    companyId String @optional,
    companyName String @optional,
    leadStage String @enum("NEW", "ENGAGED", "QUALIFIED", "DISQUALIFIED") @default("NEW"),
    dealId String @optional,
    dealStage String @enum("DISCOVERY", "MEETING", "PROPOSAL", "NEGOTIATION", "CLOSED_WON", "CLOSED_LOST") @optional,
    lastActivity DateTime @default(now()),
    emailCount Int @default(1),
    createdAt DateTime @default(now()),
    updatedAt DateTime @default(now())
}

record SkipResult {
    skipped Boolean,
    reason String
}

record EmailData {
    sender String,
    recipients String,
    subject String,
    body String,
    date String,
    threadId String,
    gmailOwnerEmail String,
    hubspotOwnerId String
}

record SDRProcessingCheck {
    needsProcessing Boolean,
    reason String,
    category String @enum("business", "meeting", "sales", "automated", "newsletter", "spam", "unknown") @optional
}

agent EmailSDRProcessing {
    llm "sonnet_llm",
    role "You are an intelligent email filter that determines if an email needs SDR processing.",
    instruction "Analyze the email to determine if it should be processed by the SDR system.

INPUT DATA:
- Sender: {{EmailData.sender}}
- Recipients: {{EmailData.recipients}}
- Subject: {{EmailData.subject}}
- Body: {{EmailData.body}}
- Date: {{EmailData.date}}

CLASSIFICATION RULES:

✅ NEEDS PROCESSING (needsProcessing: true) - Process if:
- Business discussion with clients/prospects
- Meeting coordination or scheduling
- Sales conversation or proposal
- Follow-up on commercial opportunity
- Onboarding or product discussion
- Question about products/services
- Demo request or trial discussion

❌ SKIP (needsProcessing: false) - Skip if:
- Automated sender (contains: no-reply, noreply, automated, donotreply)
- Newsletter or digest (subject contains: unsubscribe, newsletter, digest)
- Marketing blast or promotional email
- System notification (password reset, account alert)
- Internal team communication (if all participants are from same domain)
- Spam or suspicious content
- Out of office replies

RETURN FORMAT:
{
  \"needsProcessing\": true/false,
  \"reason\": \"Brief explanation (1 sentence)\",
  \"category\": \"business\" | \"meeting\" | \"sales\" | \"automated\" | \"newsletter\" | \"spam\" | \"unknown\"
}

CRITICAL OUTPUT FORMAT RULES:
- Return ONLY the SDRProcessingCheck structure
- NEVER wrap response in markdown code blocks
- NEVER use markdown formatting",
    retry classifyRetry,
    responseSchema agenticsdr.core/SDRProcessingCheck
}

record ExtractedContact {
    email String,
    name String @optional,
    firstName String @optional,
    lastName String @optional,
    role String @enum("buyer", "user", "influencer", "champion", "unknown") @default("unknown")
}

record ExtractedCompany {
    name String @optional,
    domain String @optional,
    confidence String @enum("high", "medium", "low", "none") @default("none"),
    source String @enum("domain", "signature", "body", "unknown") @optional
}

record ExtractedLeadInfo {
    contacts ExtractedContact[],
    primaryContactEmail String @optional,
    company ExtractedCompany,
    emailSubject String,
    emailBody String,
    emailDate String,
    emailThreadId String,
    emailSender String,
    emailRecipients String,
    gmailOwnerEmail String,
    hubspotOwnerId String
}

agent ExtractLeadInfo {
    llm "sonnet_llm",
    role "You extract comprehensive lead information from emails including contacts, company details, and context.",
    instruction "Extract ALL relevant lead information from the email.

INPUT DATA:
- Sender: {{EmailData.sender}}
- Recipients: {{EmailData.recipients}}
- Subject: {{EmailData.subject}}
- Body: {{EmailData.body}}
- Date: {{EmailData.date}}
- Thread ID: {{EmailData.threadId}}
- Gmail Owner: {{EmailData.gmailOwnerEmail}}
- HubSpot Owner ID: {{EmailData.hubspotOwnerId}}

EXTRACTION TASKS:

1. CONTACTS - Extract all external participants:
   - Parse: 'Name <email@domain.com>' or 'email@domain.com'
   - Extract: email, name, firstName, lastName
   - Determine role: buyer (decision maker), champion (advocate), influencer (evaluator), user (end user), unknown
   - EXCLUDE the Gmail owner email
   - Identify primaryContactEmail (main external stakeholder)

2. COMPANY - Identify the company:
   
   COMMON PERSONAL EMAIL DOMAINS (DO NOT USE AS COMPANY):
   - gmail.com, googlemail.com, outlook.com, hotmail.com, live.com
   - yahoo.com, ymail.com, fastmail.com, fastmail.fm
   - protonmail.com, proton.me, icloud.com, me.com, mac.com
   - aol.com, mail.com, email.com
   
   STRATEGY (in order):
   a) Check email signature for company name (high confidence, source: signature)
   b) Look for explicit company mentions in body (medium confidence, source: body)
   c) Extract from business email domain (high confidence, source: domain)
      - SKIP if domain is in personal email list
      - Example: alice@acme.com → domain: acme.com, name: Acme
   
   If NO company found:
   - Set confidence: \"none\"
   - Set name and domain to empty string

3. CONTEXT - Preserve email metadata:
   - emailSubject, emailBody, emailDate, emailThreadId
   - emailSender, emailRecipients
   - gmailOwnerEmail, hubspotOwnerId

RETURN FORMAT:
{
  \"contacts\": [
    {\"email\": \"john@acme.com\", \"name\": \"John Doe\", \"firstName\": \"John\", \"lastName\": \"Doe\", \"role\": \"buyer\"}
  ],
  \"primaryContactEmail\": \"john@acme.com\",
  \"company\": {
    \"name\": \"Acme Corp\",
    \"domain\": \"acme.com\",
    \"confidence\": \"high\",
    \"source\": \"domain\"
  },
  \"emailSubject\": \"...\",
  \"emailBody\": \"...\",
  \"emailDate\": \"...\",
  \"emailThreadId\": \"...\",
  \"emailSender\": \"...\",
  \"emailRecipients\": \"...\",
  \"gmailOwnerEmail\": \"...\",
  \"hubspotOwnerId\": \"...\"
}

RULES:
- Use ACTUAL data from email
- Do NOT include Gmail owner in contacts
- For personal emails without company, set company.confidence to \"none\"
- Return ONLY the ExtractedLeadInfo structure

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap response in markdown code blocks
- NEVER use markdown formatting",
    retry classifyRetry,
    responseSchema agenticsdr.core/ExtractedLeadInfo
}

record HubSpotContext {
    existingCompanyId String @optional,
    existingCompanyName String @optional,
    existingContactId String @optional,
    existingDealId String @optional,
    threadStateExists Boolean @default(false),
    threadStateLeadStage String @default("NEW"),
    threadStateEmailCount Int @default(0),
    hasCompany Boolean @default(false),
    hasContact Boolean @default(false),
    hasDeal Boolean @default(false)
}

@public event fetchHubSpotContext {
    companyDomain String @optional,
    contactEmail String @optional,
    threadId String
}

workflow fetchHubSpotContext {
    {ThreadState {threadId? fetchHubSpotContext.threadId}} @as threadStates;
    {hubspot/Company {domain? fetchHubSpotContext.companyDomain}} @as companies;
    {hubspot/Contact {email? fetchHubSpotContext.contactEmail}} @as contacts;
    
    threadStates @as [ts, __];
    companies @as [comp, __];
    contacts @as [cont, __];
    
    {HubSpotContext {
        existingCompanyId comp.id,
        existingCompanyName comp.name,
        existingContactId cont.id,
        threadStateExists threadStates.length > 0,
        threadStateLeadStage ts.leadStage,
        threadStateEmailCount ts.emailCount,
        hasCompany companies.length > 0,
        hasContact contacts.length > 0
    }}
}

record LeadAnalysis {
    leadStage String @enum("NEW", "ENGAGED", "QUALIFIED", "DISQUALIFIED"),
    leadScore Int,
    dealStage String @enum("DISCOVERY", "MEETING", "PROPOSAL", "NEGOTIATION", "CLOSED_WON", "CLOSED_LOST", "NONE") @default("NONE"),
    shouldCreateDeal Boolean,
    shouldCreateContact Boolean,
    shouldCreateCompany Boolean,
    reasoning String,
    nextAction String,
    confidence String @enum("high", "medium", "low")
}

agent LeadAnalysis {
    llm "sonnet_llm",
    role "You analyze lead information and existing CRM context to determine lead stage, deal stage, and next actions.",
    instruction "Analyze the lead based on the extracted email information and existing HubSpot context.

INPUT DATA:

EXTRACTED FROM EMAIL:
- Contacts: {{ExtractedLeadInfo.contacts}}
- Primary Contact: {{ExtractedLeadInfo.primaryContactEmail}}
- Company Name: {{ExtractedLeadInfo.company.name}}
- Company Domain: {{ExtractedLeadInfo.company.domain}}
- Company Confidence: {{ExtractedLeadInfo.company.confidence}}
- Email Subject: {{ExtractedLeadInfo.emailSubject}}
- Email Body: {{ExtractedLeadInfo.emailBody}}

EXISTING HUBSPOT CONTEXT:
- Has Existing Company: {{HubSpotContext.hasCompany}}
- Existing Company ID: {{HubSpotContext.existingCompanyId}}
- Has Existing Contact: {{HubSpotContext.hasContact}}
- Has Existing Deal: {{HubSpotContext.hasDeal}}
- Thread State Exists: {{HubSpotContext.threadStateExists}}
- Previous Lead Stage: {{HubSpotContext.threadStateLeadStage}}
- Email Count: {{HubSpotContext.threadStateEmailCount}}

ANALYSIS TASKS:

1. LEAD STAGE ASSESSMENT:

Score (0-100):
+40: Explicit buying intent (purchase, buy, pricing, contract)
+30: Meeting request or scheduled call
+20: Product/feature questions
+20: Multiple stakeholders
+15: Response to outreach
+10: Technical questions
+10: Timeline mentioned
-20: Just acknowledgment
-30: Unsubscribe/not interested
-50: Spam

Stage:
- NEW (0-20): Initial contact
- ENGAGED (21-50): Active conversation
- QUALIFIED (51-100): Strong buying signals
- DISQUALIFIED (<0): Not interested

Consider PREVIOUS lead stage - progress forward unless clear regression.

2. DEAL STAGE ASSESSMENT:

- DISCOVERY: \"Tell me about\", \"How does\", feature questions
- MEETING: \"Schedule\", \"Demo\", confirmed calls
- PROPOSAL: \"Pricing\", \"Quote\", \"Contract\"
- NEGOTIATION: \"Legal review\", \"Discount\", approvals
- CLOSED_WON: \"Signed\", \"Purchase order\"
- CLOSED_LOST: \"Going with competitor\"
- NONE: No deal signals

shouldCreateDeal = true IF:
- Lead stage is QUALIFIED
- Deal stage >= DISCOVERY
- No existing deal

3. NEXT ACTION:
Recommend specific follow-up action.

4. CREATE FLAGS:
- shouldCreateContact: true if no existing contact
- shouldCreateCompany: true if no existing company AND company.confidence is high or medium

RETURN FORMAT:
{
  \"leadStage\": \"QUALIFIED\",
  \"leadScore\": 75,
  \"dealStage\": \"PROPOSAL\",
  \"shouldCreateDeal\": true,
  \"shouldCreateContact\": true,
  \"shouldCreateCompany\": true,
  \"reasoning\": \"Customer asked for pricing with timeline.\",
  \"nextAction\": \"Send pricing proposal and schedule demo\",
  \"confidence\": \"high\"
}

RULES:
- Be conservative with scoring
- Consider conversation history
- Return ONLY the LeadAnalysis structure

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap response in markdown code blocks
- NEVER use markdown formatting",
    retry classifyRetry,
    responseSchema agenticsdr.core/LeadAnalysis
}

agent UpdateCRM {
    llm "gpt_llm",
    role "You are a CRM update agent that creates and executes a plan to update HubSpot based on lead analysis.",
    instruction "Based on the lead analysis and existing HubSpot context, create and execute a plan to update the CRM.

INPUT DATA:

EXTRACTED INFO:
- Contacts: {{ExtractedLeadInfo.contacts}}
- Primary Contact: {{ExtractedLeadInfo.primaryContactEmail}}
- Company Name: {{ExtractedLeadInfo.company.name}}
- Company Domain: {{ExtractedLeadInfo.company.domain}}
- Company Confidence: {{ExtractedLeadInfo.company.confidence}}
- HubSpot Owner ID: {{ExtractedLeadInfo.hubspotOwnerId}}
- Email Thread ID: {{ExtractedLeadInfo.emailThreadId}}

EXISTING CONTEXT:
- Has Company: {{HubSpotContext.hasCompany}}
- Existing Company ID: {{HubSpotContext.existingCompanyId}}
- Has Contact: {{HubSpotContext.hasContact}}
- Existing Contact ID: {{HubSpotContext.existingContactId}}
- Has Deal: {{HubSpotContext.hasDeal}}
- Thread State Exists: {{HubSpotContext.threadStateExists}}

LEAD ANALYSIS:
- Lead Stage: {{LeadAnalysis.leadStage}}
- Lead Score: {{LeadAnalysis.leadScore}}
- Deal Stage: {{LeadAnalysis.dealStage}}
- Should Create Deal: {{LeadAnalysis.shouldCreateDeal}}
- Should Create Contact: {{LeadAnalysis.shouldCreateContact}}
- Should Create Company: {{LeadAnalysis.shouldCreateCompany}}
- Reasoning: {{LeadAnalysis.reasoning}}
- Next Action: {{LeadAnalysis.nextAction}}

YOUR TASK:

Execute the following CRM updates using the available tools:

1. COMPANY (if shouldCreateCompany is true):
   - Create Company with domain and name from ExtractedLeadInfo.company
   - Set lifecycle_stage based on leadStage
   - Set ai_lead_score to leadScore

2. CONTACT (if shouldCreateContact is true):
   - Create Contact with email, firstName, lastName from ExtractedLeadInfo.primaryContactEmail
   - Associate with company if it exists

3. THREAD STATE:
   - Create or update ThreadState with threadId from ExtractedLeadInfo.emailThreadId
   - Update contactIds, companyId, leadStage, dealStage
   - Increment emailCount if updating

4. DEAL (if shouldCreateDeal is true):
   - Create Deal with appropriate stage
   - Associate with company and contact
   - Create Note summarizing the deal creation

5. ENGAGEMENT:
   - Create Note with lead analysis summary
   - Create Task for follow-up based on nextAction

Use the HubSpot entities directly: hubspot/Company, hubspot/Contact, hubspot/Deal, hubspot/Note, hubspot/Task
Use agenticsdr.core/ThreadState for thread tracking

Execute each action systematically and return a summary.",
    tools [hubspot/Company, hubspot/Contact, hubspot/Deal, hubspot/Note, hubspot/Task, agenticsdr.core/ThreadState]
}

workflow skipProcessing {
    {SkipResult {
        skipped true,
        reason "Email does not need SDR processing"
    }}
}

decision needsSDRProcessing {
    case (needsProcessing == true) {
        ProcessEmail
    }
    case (needsProcessing == false) {
        SkipEmail
    }
}

flow sdrManager {
    EmailSDRProcessing --> needsSDRProcessing
    needsSDRProcessing --> "SkipEmail" skipProcessing
    needsSDRProcessing --> "ProcessEmail" ExtractLeadInfo
    ExtractLeadInfo --> {fetchHubSpotContext {companyDomain ExtractedLeadInfo.company.domain, contactEmail ExtractedLeadInfo.primaryContactEmail, threadId ExtractedLeadInfo.emailThreadId}}
    fetchHubSpotContext --> LeadAnalysis
    LeadAnalysis --> UpdateCRM
}

@public agent sdrManager {
    llm "gpt_llm",
    role "You are an intelligent SDR agent that manages the complete sales development workflow.",
    instruction "Process the email through the complete SDR pipeline:
    
1. Check if email needs SDR processing
2. Extract all lead information (contacts, company, context)
3. Fetch relevant HubSpot data (existing company, contacts, deals, thread state)
4. Analyze lead and determine stages
5. Update CRM with generated plan

The email data is provided in the message. Execute the flow systematically."
}

workflow @after create:gmail/Email {
    {SDRConfig? {}} @as [config];
    
    {EmailData {
        sender gmail/Email.sender,
        recipients gmail/Email.recipients,
        subject gmail/Email.subject,
        body gmail/Email.body,
        date gmail/Email.date,
        threadId gmail/Email.thread_id,
        gmailOwnerEmail config.gmailOwnerEmail,
        hubspotOwnerId config.hubspotOwnerId
    }} @as emailData;
    
    console.log("🔔 New email received: " + gmail/Email.subject);
    console.log("📧 Thread ID: " + gmail/Email.thread_id);

    {sdrManager {message emailData}}
}
