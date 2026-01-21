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
    category String @enum("business", "meeting", "sales", "automated", "newsletter", "spam", "unknown") @optional,
    sender String,
    recipients String,
    subject String,
    body String,
    date String,
    threadId String,
    gmailOwnerEmail String,
    hubspotOwnerId String
}

agent NeedSDRProcessing {
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

RETURN FORMAT (return ALL fields including email data):
{
  \"needsProcessing\": true/false,
  \"reason\": \"Brief explanation (1 sentence)\",
  \"category\": \"business\" | \"meeting\" | \"sales\" | \"automated\" | \"newsletter\" | \"spam\" | \"unknown\",
  \"sender\": \"{{EmailData.sender}}\",
  \"recipients\": \"{{EmailData.recipients}}\",
  \"subject\": \"{{EmailData.subject}}\",
  \"body\": \"{{EmailData.body}}\",
  \"date\": \"{{EmailData.date}}\",
  \"threadId\": \"{{EmailData.threadId}}\",
  \"gmailOwnerEmail\": \"{{EmailData.gmailOwnerEmail}}\",
  \"hubspotOwnerId\": \"{{EmailData.hubspotOwnerId}}\"
}

CRITICAL OUTPUT FORMAT RULES:
- Return ALL fields from SDRProcessingCheck (including email data passthrough)
- Use actual values from EmailData for the email fields
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
    primaryContactFirstName String @optional,
    primaryContactLastName String @optional,
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
- Sender: {{SDRProcessingCheck.sender}}
- Recipients: {{SDRProcessingCheck.recipients}}
- Subject: {{SDRProcessingCheck.subject}}
- Body: {{SDRProcessingCheck.body}}
- Date: {{SDRProcessingCheck.date}}
- Thread ID: {{SDRProcessingCheck.threadId}}
- Gmail Owner: {{SDRProcessingCheck.gmailOwnerEmail}}
- HubSpot Owner ID: {{SDRProcessingCheck.hubspotOwnerId}}

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
  \"primaryContactFirstName\": \"John\",
  \"primaryContactLastName\": \"Doe\",
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

record CombinedContext {
    existingCompanyId String @optional,
    existingCompanyName String @optional,
    existingContactId String @optional,
    hasCompany Boolean @default(false),
    hasContact Boolean @default(false),
    threadStateExists Boolean @default(false),
    threadStateLeadStage String @default("NEW"),
    threadStateEmailCount Int @default(0)
}

event fetchCombinedContext {
    companyDomain String @optional,
    contactEmail String @optional,
    threadId String
}

workflow fetchCombinedContext {
    console.log("🔍 SDR: fetchCombinedContext - companyDomain: " + fetchCombinedContext.companyDomain + ", contactEmail: " + fetchCombinedContext.contactEmail + ", threadId: " + fetchCombinedContext.threadId);
    
    {hubspot/fetchCRMContext {
        companyDomain fetchCombinedContext.companyDomain,
        contactEmail fetchCombinedContext.contactEmail
    }} @as crmContext;
    
    console.log("🔍 SDR: CRM Context - hasCompany: " + crmContext.hasCompany + ", hasContact: " + crmContext.hasContact);
    console.log("🔍 SDR: Existing IDs - Company: " + crmContext.existingCompanyId + ", Contact: " + crmContext.existingContactId);
    
    "NEW" @as threadStateLeadStage;
    0 @as threadStateEmailCount;
    
    {ThreadState {threadId? fetchCombinedContext.threadId}} @as threadStates;
    
    console.log("🔍 SDR: Thread query returned " + threadStates.length + " results");
    
    if (threadStates.length > 0) {
        threadStates @as [ts, __];
        ts.leadStage @as threadStateLeadStage;
        ts.emailCount @as threadStateEmailCount;
        console.log("🔍 SDR: Existing thread - Stage: " + threadStateLeadStage + ", Count: " + threadStateEmailCount)
    };
    
    {CombinedContext {
        existingCompanyId crmContext.existingCompanyId,
        existingCompanyName crmContext.existingCompanyName,
        existingContactId crmContext.existingContactId,
        hasCompany crmContext.hasCompany,
        hasContact crmContext.hasContact,
        threadStateExists threadStates.length > 0,
        threadStateLeadStage threadStateLeadStage,
        threadStateEmailCount threadStateEmailCount
    }}
}

record LeadAnalysisData {
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

EXISTING CONTEXT:
- Has Existing Company: {{CombinedContext.hasCompany}}
- Existing Company ID: {{CombinedContext.existingCompanyId}}
- Has Existing Contact: {{CombinedContext.hasContact}}
- Thread State Exists: {{CombinedContext.threadStateExists}}
- Previous Lead Stage: {{CombinedContext.threadStateLeadStage}}
- Email Count: {{CombinedContext.threadStateEmailCount}}

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
- Return ONLY the LeadAnalysisData structure

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap response in markdown code blocks
- NEVER use markdown formatting",
    retry classifyRetry,
    responseSchema agenticsdr.core/LeadAnalysisData
}

event updateThreadState {
    threadId String,
    contactEmail String,
    companyId String @optional,
    companyName String @optional,
    leadStage String,
    dealId String @optional,
    dealStage String @optional
}

workflow updateThreadState {
    console.log("🧵 SDR: updateThreadState - threadId: " + updateThreadState.threadId);
    
    {ThreadState {threadId? updateThreadState.threadId}} @as existingStates;
    
    console.log("🧵 SDR: Thread query returned " + existingStates.length + " results");
    
    if (existingStates.length > 0) {
        existingStates @as [existingState, __];
        
        console.log("🧵 SDR: Updating existing thread, current count: " + existingState.emailCount);
        
        {ThreadState {
            threadId? updateThreadState.threadId,
            contactIds [updateThreadState.contactEmail],
            companyId updateThreadState.companyId,
            companyName updateThreadState.companyName,
            leadStage updateThreadState.leadStage,
            dealId updateThreadState.dealId,
            dealStage updateThreadState.dealStage,
            emailCount existingState.emailCount + 1,
            lastActivity now(),
            updatedAt now()
        }} @as result;
        
        console.log("🧵 SDR: Thread updated, new count: " + result.emailCount);
        result
    } else {
        console.log("🧵 SDR: Creating new thread state");
        
        {ThreadState {
            threadId updateThreadState.threadId,
            contactIds [updateThreadState.contactEmail],
            companyId updateThreadState.companyId,
            companyName updateThreadState.companyName,
            leadStage updateThreadState.leadStage,
            dealId updateThreadState.dealId,
            dealStage updateThreadState.dealStage,
            emailCount 1,
            lastActivity now()
        }} @as result;
        
        console.log("🧵 SDR: Thread created, ID: " + result.threadId);
        result
    }
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

record CRMUpdateRequest {
    shouldCreateCompany Boolean,
    shouldCreateContact Boolean,
    shouldCreateDeal Boolean,
    companyName String,
    companyDomain String,
    contactEmail String,
    contactFirstName String,
    contactLastName String,
    leadStage String,
    leadScore Int,
    dealStage String,
    dealName String,
    reasoning String,
    nextAction String,
    ownerId String,
    existingCompanyId String,
    existingContactId String
}

event prepareCRMUpdateRequest {
    shouldCreateCompany Boolean,
    shouldCreateContact Boolean,
    shouldCreateDeal Boolean,
    companyName String,
    companyDomain String,
    contactEmail String,
    contactFirstName String,
    contactLastName String,
    leadStage String,
    leadScore Int,
    dealStage String,
    reasoning String,
    nextAction String,
    ownerId String,
    existingCompanyId String,
    existingContactId String
}

workflow prepareCRMUpdateRequest {
    console.log("📤 SDR: Preparing CRM update request");
    console.log("The value is: " + prepareCRMUpdateRequest.shouldCreateCompany);

    {CRMUpdateRequest {
        shouldCreateCompany prepareCRMUpdateRequest.shouldCreateCompany,
        shouldCreateContact prepareCRMUpdateRequest.shouldCreateContact,
        shouldCreateDeal prepareCRMUpdateRequest.shouldCreateDeal,
        companyName prepareCRMUpdateRequest.companyName,
        companyDomain prepareCRMUpdateRequest.companyDomain,
        contactEmail prepareCRMUpdateRequest.contactEmail,
        contactFirstName prepareCRMUpdateRequest.contactFirstName,
        contactLastName prepareCRMUpdateRequest.contactLastName,
        leadStage prepareCRMUpdateRequest.leadStage,
        leadScore prepareCRMUpdateRequest.leadScore,
        dealStage prepareCRMUpdateRequest.dealStage,
        dealName prepareCRMUpdateRequest.companyName + " - " + prepareCRMUpdateRequest.leadStage,
        reasoning prepareCRMUpdateRequest.reasoning,
        nextAction prepareCRMUpdateRequest.nextAction,
        ownerId prepareCRMUpdateRequest.ownerId,
        existingCompanyId prepareCRMUpdateRequest.existingCompanyId,
        existingContactId prepareCRMUpdateRequest.existingContactId
    }} @as request;
    
    console.log("✅ SDR: CRMUpdateRequest record created");
    console.log("  contactEmail: " + request.contactEmail);
    console.log("  contactFirstName: " + request.contactFirstName);
    console.log("  ownerId: " + request.ownerId);
    console.log("  Flags: Company=" + request.shouldCreateCompany + " Contact=" + request.shouldCreateContact + " Deal=" + request.shouldCreateDeal);
    console.log("📤 SDR: Passing CRMUpdateRequest to hubspot/updateCRMFromLead");
    
    request
}

flow sdrManager {
    NeedSDRProcessing --> needsSDRProcessing
    needsSDRProcessing --> "SkipEmail" skipProcessing
    needsSDRProcessing --> "ProcessEmail" ExtractLeadInfo
    ExtractLeadInfo --> {fetchCombinedContext {
        companyDomain ExtractedLeadInfo.company.domain,
        contactEmail ExtractedLeadInfo.primaryContactEmail,
        threadId ExtractedLeadInfo.emailThreadId
    }}
    fetchCombinedContext --> LeadAnalysis
    LeadAnalysis --> {prepareCRMUpdateRequest {
        shouldCreateCompany LeadAnalysis.shouldCreateCompany,
        shouldCreateContact LeadAnalysis.shouldCreateContact,
        shouldCreateDeal LeadAnalysis.shouldCreateDeal,
        companyName ExtractedCompany.name,
        companyDomain ExtractedCompany.domain,
        contactEmail ExtractedLeadInfo.primaryContactEmail,
        contactFirstName ExtractedLeadInfo.primaryContactFirstName,
        contactLastName ExtractedLeadInfo.primaryContactLastName,
        leadStage LeadAnalysis.leadStage,
        leadScore LeadAnalysis.leadScore,
        dealStage LeadAnalysis.dealStage,
        reasoning LeadAnalysis.reasoning,
        nextAction LeadAnalysis.nextAction,
        ownerId EmailData.hubspotOwnerId,
        existingCompanyId CombinedContext.existingCompanyId,
        existingContactId CombinedContext.existingContactId
    }}
    prepareCRMUpdateRequest --> {hubspot/updateCRMFromLead {
        shouldCreateCompany CRMUpdateRequest.shouldCreateCompany,
        shouldCreateContact CRMUpdateRequest.shouldCreateContact,
        shouldCreateDeal CRMUpdateRequest.shouldCreateDeal,
        companyName CRMUpdateRequest.companyName,
        companyDomain CRMUpdateRequest.companyDomain,
        contactEmail CRMUpdateRequest.contactEmail,
        contactFirstName CRMUpdateRequest.contactFirstName,
        contactLastName CRMUpdateRequest.contactLastName,
        leadStage CRMUpdateRequest.leadStage,
        leadScore CRMUpdateRequest.leadScore,
        dealStage CRMUpdateRequest.dealStage,
        dealName CRMUpdateRequest.dealName,
        reasoning CRMUpdateRequest.reasoning,
        nextAction CRMUpdateRequest.nextAction,
        ownerId CRMUpdateRequest.ownerId,
        existingCompanyId CRMUpdateRequest.existingCompanyId,
        existingContactId CRMUpdateRequest.existingContactId
    }}
    hubspot/updateCRMFromLead --> {updateThreadState {
        threadId ExtractedLeadInfo.emailThreadId,
        contactEmail ExtractedLeadInfo.primaryContactEmail,
        companyId hubspot/CRMUpdateResult.companyId,
        companyName hubspot/CRMUpdateResult.companyName,
        leadStage LeadAnalysis.leadStage,
        dealId hubspot/CRMUpdateResult.dealId,
        dealStage LeadAnalysis.dealStage
    }}
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
    
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("🔔 SDR: New email received");
    console.log("  From: " + gmail/Email.sender);
    console.log("  To: " + gmail/Email.recipients);
    console.log("  Subject: " + gmail/Email.subject);
    console.log("  Thread ID: " + gmail/Email.thread_id);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
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

    {sdrManager {message emailData}}
}
