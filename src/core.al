module agenticsdr.core

entity SalesEngagementConfig {
    id UUID @id @default(uuid()),
    gmailOwnerEmail String,
    hubspotOwnerId String
}

entity ConversationThread {
    threadId String @id,
    contactIds String[],
    companyId String @optional,
    companyName String @optional,
    leadStage String @enum("NEW", "ENGAGED", "QUALIFIED", "DISQUALIFIED") @default("NEW"),
    dealId String @optional,
    dealStage String @enum("DISCOVERY", "MEETING", "PROPOSAL", "NEGOTIATION", "CLOSED_WON", "CLOSED_LOST") @optional,
    latestNoteId String @optional,
    latestTaskId String @optional,
    latestMeetingId String @optional,
    lastActivity DateTime @default(now()),
    emailCount Int @default(1),
    createdAt DateTime @default(now()),
    updatedAt DateTime @default(now())
}

record QualificationRejection {
    skipped Boolean,
    reason String
}

record InboundEmailPayload {
    sender String,
    recipients String,
    subject String,
    body String,
    date String,
    threadId String,
    gmailOwnerEmail String,
    hubspotOwnerId String
}

record EmailQualificationResult {
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

agent EmailQualificationAgent {
    llm "sonnet_llm",
    role "You are an intelligent email qualification agent who determines if an email requires sales engagement processing.",
    tools [sdr.core/InboundEmailPayload],
    instruction "You receive an InboundEmailPayload instance as input. Your job is to determine if this email needs sales processing.",
    retry classifyRetry,
    responseSchema agenticsdr.core/EmailQualificationResult
}

record LeadIntelligence {
    primaryContactEmail String,
    primaryContactFirstName String,
    primaryContactLastName String,
    primaryContactRole String @enum("buyer", "user", "influencer", "champion", "unknown") @default("unknown"),
    allContactEmails String @optional,
    allContactNames String @optional,
    companyName String,
    companyDomain String,
    companyConfidence String @enum("high", "medium", "low", "none") @default("none"),
    emailSubject String,
    emailBody String,
    emailDate String,
    emailThreadId String,
    emailSender String,
    emailRecipients String,
    gmailOwnerEmail String,
    hubspotOwnerId String
}

agent LeadIntelligenceExtractor {
    llm "sonnet_llm",
    role "You are an expert at extracting structured lead intelligence from sales emails including contact details, company information, and relationship context.",
    instruction "AGENT: LeadIntelligenceExtractor
PURPOSE: Extract contact and company information from qualified sales emails
OUTPUT: LeadIntelligence with structured contact and company data

================================================================================
SECTION 1: INPUT DATA
================================================================================

You receive an EmailQualificationResult record with these fields:

- sender: {{EmailQualificationResult.sender}} - The email sender
- recipients: {{EmailQualificationResult.recipients}} - The email recipients  
- subject: {{EmailQualificationResult.subject}} - The email subject line
- body: {{EmailQualificationResult.body}} - The full email body text
- date: {{EmailQualificationResult.date}} - The email timestamp
- threadId: {{EmailQualificationResult.threadId}} - The email thread identifier
- gmailOwnerEmail: {{EmailQualificationResult.gmailOwnerEmail}} - YOUR sales rep's email (NOT the lead)
- hubspotOwnerId: {{EmailQualificationResult.hubspotOwnerId}} - The HubSpot owner ID

================================================================================
SECTION 2: CONTACT EXTRACTION
================================================================================

CRITICAL UNDERSTANDING:
The Gmail owner {{EmailQualificationResult.gmailOwnerEmail}} is YOUR sales rep, NOT the lead.
You must find the EXTERNAL contact (the prospect or customer).

STEP 1: Determine who the primary contact is

If {{EmailQualificationResult.sender}} equals {{EmailQualificationResult.gmailOwnerEmail}}:
  - This is OUTBOUND your sales rep sent email to prospect
  - Extract primary contact FROM recipients field
  - If multiple recipients parse the first external email address
  
If {{EmailQualificationResult.recipients}} contains {{EmailQualificationResult.gmailOwnerEmail}}:
  - This is INBOUND prospect sent email to your sales rep
  - Extract primary contact FROM sender field

If BOTH sender and recipients contain {{EmailQualificationResult.gmailOwnerEmail}} (reply-all scenario):
  - This is a GROUP CONVERSATION
  - Primary contact is the sender IF sender is not gmailOwnerEmail
  - Otherwise extract first external recipient from recipients list

VALIDATION: primaryContactEmail must NEVER equal gmailOwnerEmail

EDGE CASES:
- Multiple recipients: Parse as comma-separated and extract first non-gmailOwner email
- Malformed email: john.doe@acmecorp.com without name - use john as firstName, doe as lastName from email
- No name found anywhere: Use first part of email before @ as firstName, empty lastName

STEP 2: Parse email and name from the primary contact

Common email formats you will encounter:
  - John Doe with email john@company.com extracts to email john@company.com and name John Doe
  - John Doe angle bracket john@company.com angle bracket extracts same way
  - Just john@company.com means check signature for name
  - Multiple recipients comma separated like john@company.com, jane@company.com means take first one
  
Extract firstName and lastName:
  - Full name John Doe extracts to firstName John and lastName Doe
  - Single name John extracts to firstName John and lastName empty string
  - Email-only john.doe@company.com can extract firstName john and lastName doe from email prefix
  - If no name in header look in email signature for Best regards John Doe or Thanks John or similar patterns

STEP 3: Determine primary contact role

Analyze email content and titles to assign role:

buyer - Has decision-making and budget authority
  Look for: CEO, CTO, CFO, VP, Director, \"I will approve\", budget owner
  
champion - Internal advocate who promotes your solution
  Look for: let me introduce you, I love this, enthusiastic tone
  
influencer - Evaluates and recommends but doesn't decide
  Look for: Manager, Lead, I will recommend, evaluating options
  
user - Will use product but doesn't make buying decision
  Look for: Engineer, Analyst, Developer, technical questions
  
\"unknown\" - Not enough information to determine role

STEP 4: Extract additional contacts

Look for other external contacts (NOT Gmail owner) in:
  - CC'd people in recipients
  - Mentions like \"I have included Jane from our team\"

If additional contacts found:
  - allContactEmails: jane at company dot com comma bob at company dot com (comma-separated)
  - allContactNames: Jane Smith comma Bob Johnson (comma-separated, same order)

If ONLY one contact:
  - allContactEmails: empty string
  - allContactNames: empty string

================================================================================
SECTION 3: COMPANY EXTRACTION
================================================================================

PERSONAL EMAIL DOMAINS - Do NOT use these as companies:
gmail.com, googlemail.com, outlook.com, outlook.live.com, hotmail.com, live.com, msn.com, yahoo.com, yahoo.co.uk, ymail.com, rocketmail.com, fastmail.com, fastmail.fm, hey.com, protonmail.com, proton.me, pm.me, icloud.com, me.com, mac.com, aol.com, mail.com, email.com, gmx.com, zoho.com

Try these strategies IN ORDER until you find company information:

STRATEGY 1: Email Signature with confidence high
Look at the bottom of {{EmailQualificationResult.body}} for email signature.
Patterns to find:
  - John Doe Senior Engineer Acme Corp
  - John Doe VP of Sales at Acme Corp
  - Company name on its own line near title

If found in signature:
  - companyName: Extract the company name like Acme Corp
  - companyDomain: Try to extract from signature or use primary contact email domain
  - companyConfidence: high

STRATEGY 2: Business Email Domain with confidence high
Extract domain from primaryContactEmail.
Example: john@acmecorp.com has domain acmecorp.com

Check if domain is NOT in personal email list above.
If it is a business domain:
  - companyDomain: Use the extracted domain like acmecorp.com
  - companyName: Convert domain to name like acmecorp.com becomes Acme Corp
  - companyConfidence: high

STRATEGY 3: Mentioned in Email Body with confidence medium
Look for company mentions in {{EmailQualificationResult.body}}:
  - I work at Acme Corp
  - We are from Acme Corp
  - Here at Acme Corp
  - Acme Corp is interested in

If found:
  - companyName: Extract the mentioned company name
  - companyDomain: Try to infer or leave empty if unclear
  - companyConfidence: medium

STRATEGY 4: No Company Found with confidence none
If primary contact uses personal email like gmail or outlook AND no company found:
  - companyName: empty string
  - companyDomain: empty string
  - companyConfidence: none

================================================================================
SECTION 4: OUTPUT CONSTRUCTION
================================================================================

You MUST return agenticsdr.core/LeadIntelligence with ALL fields.

CRITICAL: These fields must be copied EXACTLY from input - DO NOT modify, truncate, or leave empty:
- emailSubject from {{EmailQualificationResult.subject}}
- emailBody from {{EmailQualificationResult.body}}
- emailDate from {{EmailQualificationResult.date}}
- emailThreadId from {{EmailQualificationResult.threadId}}
- emailSender from {{EmailQualificationResult.sender}}
- emailRecipients from {{EmailQualificationResult.recipients}}
- gmailOwnerEmail from {{EmailQualificationResult.gmailOwnerEmail}}
- hubspotOwnerId from {{EmailQualificationResult.hubspotOwnerId}} ← CRITICAL: This is the HubSpot owner ID (like \"85257652\"). You MUST copy this EXACTLY as provided. NEVER leave this empty or use empty string.

OUTPUT STRUCTURE:

{
  primaryContactEmail: john.doe@acmecorp.com,
  primaryContactFirstName: John,
  primaryContactLastName: Doe,
  primaryContactRole: buyer,
  allContactEmails: jane@acmecorp.com,bob@acmecorp.com OR empty string if only one contact,
  allContactNames: Jane Smith,Bob Johnson OR empty string if only one contact,
  companyName: Acme Corp OR empty string if none found,
  companyDomain: acmecorp.com OR empty string if none found,
  companyConfidence: high OR medium OR low OR none,
  emailSubject: copy exactly from {{EmailQualificationResult.subject}},
  emailBody: copy exactly from {{EmailQualificationResult.body}},
  emailDate: copy exactly from {{EmailQualificationResult.date}},
  emailThreadId: copy exactly from {{EmailQualificationResult.threadId}},
  emailSender: copy exactly from {{EmailQualificationResult.sender}},
  emailRecipients: copy exactly from {{EmailQualificationResult.recipients}},
  gmailOwnerEmail: copy exactly from {{EmailQualificationResult.gmailOwnerEmail}},
  hubspotOwnerId: copy exactly from {{EmailQualificationResult.hubspotOwnerId}}
}

EXAMPLE OUTPUT:
{
  primaryContactEmail: john.doe@acmecorp.com,
  primaryContactFirstName: John,
  primaryContactLastName: Doe,
  primaryContactRole: buyer,
  allContactEmails: empty string,
  allContactNames: empty string,
  companyName: Acme Corp,
  companyDomain: acmecorp.com,
  companyConfidence: high,
  emailSubject: Enterprise Plan Pricing,
  emailBody: Hi I am interested in your Enterprise plan for 100 users,
  emailDate: 2026-01-23T10:30:00Z,
  emailThreadId: thread_abc123,
  emailSender: John Doe from john.doe@acmecorp.com,
  emailRecipients: sales@mycompany.com,
  gmailOwnerEmail: sales@mycompany.com,
  hubspotOwnerId: 12345
}

================================================================================
SECTION 5: VALIDATION CHECKLIST
================================================================================

Before returning, verify ALL of these:

1. primaryContactEmail is NOT the same as gmailOwnerEmail
2. primaryContactEmail is a valid external email address
3. primaryContactFirstName and primaryContactLastName are actual names not placeholder text like FirstName or LastName
4. primaryContactRole is one of: buyer, champion, influencer, user, unknown
5. allContactEmails is comma-separated list OR empty string
6. allContactNames matches allContactEmails (same count, same order)
7. companyDomain does NOT contain personal domains (gmail.com, outlook.com, etc.)
8. companyConfidence is one of: high, medium, low, none
9. All email* fields copied EXACTLY from input (not modified, not truncated)
10. gmailOwnerEmail copied EXACTLY from input
11. hubspotOwnerId copied EXACTLY from input - THIS IS CRITICAL! Verify the value matches the input exactly (e.g., \"85257652\"). NEVER use empty string \"\"
12. No markdown formatting, no backticks, no code blocks
13. Clean JSON only

================================================================================
CRITICAL RULES
================================================================================

1. NEVER use placeholder values like placeholder values
2. ALWAYS extract real data from the email
3. NEVER wrap response in markdown code blocks or backticks
4. NEVER modify or truncate the email metadata fields
5. ALWAYS copy emailSubject, emailBody, emailDate, emailThreadId, emailSender, emailRecipients, gmailOwnerEmail, hubspotOwnerId EXACTLY
6. CRITICAL: hubspotOwnerId MUST be copied exactly from input. If input has \"85257652\", output must have \"85257652\". NEVER output empty string \"\" for hubspotOwnerId
7. If contact uses personal email (gmail, outlook, etc.) AND no company found: companyConfidence = none and companyName empty and companyDomain empty
8. ALWAYS return clean JSON matching LeadIntelligence schema
9. NEVER add commentary outside the JSON structure",
    retry classifyRetry,
    responseSchema agenticsdr.core/LeadIntelligence
}

record EnrichedLeadContext {
    existingCompanyId String @optional,
    existingCompanyName String @optional,
    existingContactId String @optional,
    hasCompany Boolean @default(false),
    hasContact Boolean @default(false),
    threadStateExists Boolean @default(false),
    threadStateLeadStage String @default("NEW"),
    threadStateEmailCount Int @default(0)
}

event enrichLeadContext {
    companyDomain String @optional,
    contactEmail String @optional,
    threadId String
}

workflow enrichLeadContext {
    {hubspot/retrieveCRMData {
        companyDomain enrichLeadContext.companyDomain,
        contactEmail enrichLeadContext.contactEmail
    }} @as crmContext;

    {ConversationThread {threadId? enrichLeadContext.threadId}} @as threadStates;

    if (threadStates.length > 0) {
        threadStates @as [ts];

        {EnrichedLeadContext {
            existingCompanyId crmContext.existingCompanyId,
            existingCompanyName crmContext.existingCompanyName,
            existingContactId crmContext.existingContactId,
            hasCompany crmContext.hasCompany,
            hasContact crmContext.hasContact,
            threadStateExists threadStates.length > 0,
            threadStateLeadStage ts.leadStage,
            threadStateEmailCount ts.emailCount
        }}
    } else {
        {EnrichedLeadContext {
            existingCompanyId crmContext.existingCompanyId,
            existingCompanyName crmContext.existingCompanyName,
            existingContactId crmContext.existingContactId,
            hasCompany crmContext.hasCompany,
            hasContact crmContext.hasContact,
            threadStateExists threadStates.length > 0,
            threadStateLeadStage "NEW",
            threadStateEmailCount 0
        }}
    }
}

record LeadClassificationReport {
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

agent LeadStageClassifier {
    llm "sonnet_llm",
    role "You analyze lead information and existing CRM context to determine lead stage, deal stage, and next actions.",
    instruction "Analyze the lead based on the extracted email information and existing HubSpot context.

INPUT DATA:

EXTRACTED FROM EMAIL (LeadIntelligence):
- Primary Contact Email: {{LeadIntelligence.primaryContactEmail}}
- Primary Contact Name: {{LeadIntelligence.primaryContactFirstName}} {{LeadIntelligence.primaryContactLastName}}
- Primary Contact Role: {{LeadIntelligence.primaryContactRole}}
- All Contact Emails: {{LeadIntelligence.allContactEmails}}
- All Contact Names: {{LeadIntelligence.allContactNames}}
- Company Name: {{LeadIntelligence.companyName}}
- Company Domain: {{LeadIntelligence.companyDomain}}
- Company Confidence: {{LeadIntelligence.companyConfidence}}
- Email Subject: {{LeadIntelligence.emailSubject}}
- Email Body: {{LeadIntelligence.emailBody}}
- Email Date: {{LeadIntelligence.emailDate}}
- Thread ID: {{LeadIntelligence.emailThreadId}}

EXISTING CRM CONTEXT (EnrichedLeadContext):
- Has Existing Company in CRM: {{EnrichedLeadContext.hasCompany}}
- Existing Company ID: {{EnrichedLeadContext.existingCompanyId}}
- Existing Company Name: {{EnrichedLeadContext.existingCompanyName}}
- Has Existing Contact in CRM: {{EnrichedLeadContext.hasContact}}
- Existing Contact ID: {{EnrichedLeadContext.existingContactId}}
- Conversation Thread Exists: {{EnrichedLeadContext.threadStateExists}}
- Previous Lead Stage: {{EnrichedLeadContext.threadStateLeadStage}}
- Email Count in Thread: {{EnrichedLeadContext.threadStateEmailCount}}

ANALYSIS TASKS:

1. LEAD STAGE ASSESSMENT:

Calculate Lead Score (0-100) based on email content:
+40: Explicit buying intent (purchase, buy, pricing, contract, proposal)
+30: Meeting request or scheduled call (let's meet, schedule, demo request)
+25: Budget/timeline discussion (this quarter, next month, allocated budget)
+20: Product/feature questions showing use case understanding
+20: Multiple stakeholders involved (CC'd decision makers, mentions team)
+15: Response to outreach (replying to your email, following up)
+15: Specific technical/integration questions
+10: General questions about capabilities
+5: Positive engagement signals (interested, sounds good, let's explore)
-20: Just acknowledgment without substance (thanks, got it, ok)
-30: Unsubscribe/not interested/stop contact requests
-50: Spam, automated, or irrelevant content

Determine Lead Stage based on score AND previous stage:
- NEW (0-20): Initial contact, exploratory stage
- ENGAGED (21-50): Active conversation, showing interest
- QUALIFIED (51-100): Strong buying signals, clear opportunity
- DISQUALIFIED (<0): Not interested or invalid

IMPORTANT CONTEXT AWARENESS:
Consider previous stage {{EnrichedLeadContext.threadStateLeadStage}} and email count {{EnrichedLeadContext.threadStateEmailCount}}:

If threadStateExists is true:
  - Review progression from previous stage
  - Stage can move FORWARD if email shows progress like NEW to ENGAGED to QUALIFIED
  - Stage can move BACKWARD if email shows regression like QUALIFIED to ENGAGED if they go cold
  - Multiple emails count greater than 1 in ENGAGED stage MAY indicate qualification BUT only if genuine buying signals present
  - Do NOT automatically qualify just because of email count require actual buying intent

If threadStateExists is false:
  - This is first email in conversation
  - Score purely based on email content
  - Be conservative with qualification on first email unless very strong signals

SCORING ADJUSTMENT FOR CONTEXT:
- If previous stage was QUALIFIED and current email maintains interest: Keep score high 60 plus
- If previous stage was ENGAGED and current shows buying intent: Boost score by 10
- If previous stage was NEW and current asks questions: Normal scoring no bonus

2. DEAL STAGE ASSESSMENT:

Analyze email content to determine deal progression:
- DISCOVERY: Tell me about, How does it work, Can you explain, feature questions, early exploration
- MEETING: Schedule, Demo request, Let us meet, Calendar invite, confirmed calls
- PROPOSAL: Pricing request, Quote needed, Send proposal, Contract discussion, What does it cost
- NEGOTIATION: Legal review, Discount request, Terms discussion, approval processes, stakeholder buy-in
- CLOSED_WON: Signed contract, Purchase order received, Let us proceed, Approved by leadership
- CLOSED_LOST: Going with competitor, Not moving forward, Decided against purchasing
- NONE: No clear deal signals, early stage, or just informational

3. CREATE FLAGS - Determine what CRM records to create:

shouldCreateDeal: Set to true ONLY if ALL conditions met:
- Lead stage is QUALIFIED with score 51 or higher
- Deal stage is DISCOVERY or higher NOT NONE and NOT CLOSED_LOST
- No existing deal already exists check {{EnrichedLeadContext.threadStateExists}} and verify no dealId present
- Clear opportunity signals present in the email

IMPORTANT: If threadStateExists is true AND you see previous dealId data, do NOT create a new deal even if qualified. A deal already exists for this conversation.

shouldCreateContact: Set to true if:
- No existing contact ({{EnrichedLeadContext.hasContact}} is false)
- OR contact email doesn't match existing contactId
- Valid contact information extracted from email

shouldCreateCompany: Set to true if:
- No existing company in CRM where {{EnrichedLeadContext.hasCompany}} is false
- AND companyConfidence is high or medium NOT low or none
- AND valid company domain extracted that is not a personal email domain

4. NEXT ACTION:
Provide specific actionable follow-up recommendation based on:
- Current lead stage and deal stage
- Email content and context  
- Previous interaction history if email count is greater than 1
Examples: Send pricing deck for Enterprise plan, Schedule product demo, Follow up on technical questions, Send case studies for their industry

5. REASONING:
Explain your analysis clearly including:
- Key signals that influenced scoring with specific examples from email
- Why you chose the lead stage referencing score calculation
- Justification for deal stage based on email content
- Why each create flag is set to true or false
- If conversation history exists explain how previous stage influenced decision

6. CONFIDENCE LEVEL:
Assign confidence based on clarity of signals:
- high: Clear unambiguous buying signals or explicit requests, multiple strong indicators
- medium: Some buying signals but mixed with other content, moderate certainty
- low: Weak signals or highly ambiguous content, uncertain classification

RETURN FORMAT - Return agenticsdr.core/LeadClassificationReport:
{
  leadStage: QUALIFIED,
  leadScore: 75,
  dealStage: PROPOSAL,
  shouldCreateDeal: true,
  shouldCreateContact: true,
  shouldCreateCompany: true,
  reasoning: Customer asked for pricing with specific timeline for Q2 implementation. Multiple stakeholders CCd including VP of Engineering. Score is 75 calculated as 40 for pricing intent plus 25 for timeline plus 10 for tech questions. Previous stage was ENGAGED with 3 emails in thread now progressing to QUALIFIED based on clear buying signals,
  nextAction: Send detailed pricing proposal for Enterprise plan with Q2 implementation timeline and technical integration guide,
  confidence: high
}

CRITICAL VALIDATION BEFORE OUTPUT:

1. Check if dealId already exists in thread:
   - Look at {{EnrichedLeadContext.threadStateExists}} and check for dealId in thread
   - If deal already exists set shouldCreateDeal to false even if qualified
   - Avoid creating duplicate deals for same conversation

2. Validate score matches stage:
   - NEW stage must have score 0 to 20
   - ENGAGED stage must have score 21 to 50
   - QUALIFIED stage must have score 51 to 100
   - DISQUALIFIED stage must have score less than 0
   - If score and stage mismatch adjust one of them

3. Validate create flags logic:
   - If hasCompany is true then shouldCreateCompany must be false
   - If hasContact is true then shouldCreateContact should usually be false unless updating
   - If leadStage is not QUALIFIED then shouldCreateDeal must be false

CRITICAL RULES:
- Be conservative with scoring require clear evidence for high scores not assumptions
- Consider conversation history threadStateEmailCount and previous leadStage always
- Do NOT create deals prematurely need genuine QUALIFIED signals with score 51 plus
- Check existing CRM data carefully before setting create flags to avoid duplicates
- Reasoning must reference specific email content and scoring rationale with examples
- nextAction must be specific and actionable not generic advice like follow up
- confidence should reflect certainty of your classification high for clear signals low for ambiguous
- Return ONLY the LeadClassificationReport structure no additional text or commentary

OUTPUT FORMAT:
- NEVER wrap response in markdown code blocks or backticks
- NEVER add JSON formatting with backticks or language identifiers
- DO NOT use markdown formatting
- Return clean JSON matching LeadClassificationReport schema exactly
- Ensure all enum values match exactly: NEW ENGAGED QUALIFIED DISQUALIFIED for leadStage
- Ensure dealStage matches: DISCOVERY MEETING PROPOSAL NEGOTIATION CLOSED_WON CLOSED_LOST NONE",
    retry classifyRetry,
    responseSchema agenticsdr.core/LeadClassificationReport
}

event trackConversationState {
    threadId String,
    contactEmail String,
    companyId String @optional,
    companyName String @optional,
    leadStage String,
    dealId String @optional,
    dealStage String @optional,
    noteId String @optional,
    taskId String @optional,
    meetingId String @optional
}

workflow trackConversationState {
    
    {ConversationThread {threadId? trackConversationState.threadId}} @as existingStates;
    
    
    if (existingStates.length > 0) {
        existingStates @as [existingState];
        
        
        {ConversationThread {
            threadId? trackConversationState.threadId,
            contactIds [trackConversationState.contactEmail],
            companyId trackConversationState.companyId,
            companyName trackConversationState.companyName,
            leadStage trackConversationState.leadStage,
            dealId trackConversationState.dealId,
            dealStage trackConversationState.dealStage,
            latestNoteId trackConversationState.noteId,
            latestTaskId trackConversationState.taskId,
            latestMeetingId trackConversationState.meetingId,
            emailCount existingState.emailCount + 1,
            lastActivity now(),
            updatedAt now()
        }} @as result;
        
        result
    } else {
        
        {ConversationThread {
            threadId trackConversationState.threadId,
            contactIds [trackConversationState.contactEmail],
            companyId trackConversationState.companyId,
            companyName trackConversationState.companyName,
            leadStage trackConversationState.leadStage,
            dealId trackConversationState.dealId,
            dealStage trackConversationState.dealStage,
            latestNoteId trackConversationState.noteId,
            latestTaskId trackConversationState.taskId,
            latestMeetingId trackConversationState.meetingId,
            emailCount 1,
            lastActivity now()
        }} @as result;
        
        result
    }
}

workflow bypassLeadProcessing {
    {QualificationRejection {
        skipped true,
        reason "Email does not need SDR processing"
    }}
}

decision shouldProcessLead {
    case (needsProcessing == true) {
        ProcessEmail
    }
    case (needsProcessing == false) {
        SkipEmail
    }
}

record CRMSyncPayload {
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

flow LeadPipelineOrchestrator {
    EmailQualificationAgent --> shouldProcessLead
    shouldProcessLead --> "SkipEmail" bypassLeadProcessing
    shouldProcessLead --> "ProcessEmail" LeadIntelligenceExtractor
    LeadIntelligenceExtractor --> {enrichLeadContext {
        companyDomain LeadIntelligenceExtractor.companyDomain,
        contactEmail LeadIntelligenceExtractor.primaryContactEmail,
        threadId LeadIntelligenceExtractor.emailThreadId
    }}
    enrichLeadContext --> LeadStageClassifier
    LeadStageClassifier --> {hubspot/syncLeadToCRM {
        shouldCreateCompany LeadStageClassifier.shouldCreateCompany,
        shouldCreateContact LeadStageClassifier.shouldCreateContact,
        shouldCreateDeal LeadStageClassifier.shouldCreateDeal,
        companyName LeadIntelligenceExtractor.companyName,
        companyDomain LeadIntelligenceExtractor.companyDomain,
        contactEmail LeadIntelligenceExtractor.primaryContactEmail,
        contactFirstName LeadIntelligenceExtractor.primaryContactFirstName,
        contactLastName LeadIntelligenceExtractor.primaryContactLastName,
        leadStage LeadStageClassifier.leadStage,
        leadScore LeadStageClassifier.leadScore,
        dealStage LeadStageClassifier.dealStage,
        dealName LeadStageClassifier.leadStage + " - " + LeadStageClassifier.dealStage,
        reasoning LeadStageClassifier.reasoning,
        nextAction LeadStageClassifier.nextAction,
        ownerId EmailQualificationAgent.hubspotOwnerId,
        existingCompanyId EnrichedLeadContext.existingCompanyId,
        existingContactId EnrichedLeadContext.existingContactId
    }}
    hubspot/syncLeadToCRM --> {trackConversationState {
        threadId LeadIntelligenceExtractor.emailThreadId,
        contactEmail LeadIntelligenceExtractor.primaryContactEmail,
        companyId hubspot/CRMSyncResult.companyId,
        companyName hubspot/CRMSyncResult.companyName,
        leadStage LeadStageClassifier.leadStage,
        dealId hubspot/CRMSyncResult.dealId,
        dealStage LeadStageClassifier.dealStage,
        noteId hubspot/CRMSyncResult.noteId,
        taskId hubspot/CRMSyncResult.taskId,
        meetingId hubspot/CRMSyncResult.meetingId
    }}
}

@public agent LeadPipelineOrchestrator {
    llm "gpt_llm",
    role "You are an intelligent sales pipeline orchestrator that manages the complete lead engagement workflow from email to CRM.",
    instruction "You orchestrate the end-to-end lead processing pipeline. When an email arrives, execute the LeadPipelineOrchestrator flow systematically.

PIPELINE OVERVIEW:

The email data is provided in the message as InboundEmailPayload. Execute each stage of the pipeline:

STAGE 1: EMAIL QUALIFICATION (EmailQualificationAgent)
- Analyze incoming email to determine if it requires sales processing
- Filter out automated emails, newsletters, spam, internal communications
- Qualify business opportunities, sales inquiries, meeting requests
- Output: EmailQualificationResult with needsProcessing flag

STAGE 2: LEAD INTELLIGENCE EXTRACTION (LeadIntelligenceExtractor)
- Extract contact information (primary contact, additional stakeholders, roles)
- Identify company information (name, domain, confidence level)
- Preserve all email metadata for CRM context
- Output: LeadIntelligence with structured contact and company data

STAGE 3: CRM CONTEXT ENRICHMENT (enrichLeadContext workflow)
- Query HubSpot CRM for existing company records by domain
- Query HubSpot CRM for existing contact records by email
- Retrieve conversation thread history and previous lead stage
- Combine CRM data with thread state for full context
- Output: EnrichedLeadContext with existing CRM data and conversation history

STAGE 4: LEAD CLASSIFICATION & SCORING (LeadStageClassifier)
- Analyze email content to score lead quality (0-100)
- Determine lead stage: NEW, ENGAGED, QUALIFIED, DISQUALIFIED
- Identify deal stage: DISCOVERY, MEETING, PROPOSAL, NEGOTIATION, etc.
- Consider conversation history and previous interactions
- Decide what CRM records to create (contact, company, deal)
- Recommend specific next action
- Output: LeadClassificationReport with stage, score, recommendations

STAGE 5: CRM SYNCHRONIZATION (syncLeadToCRM workflow)
- Create or update company record in HubSpot (if needed)
- Create or update contact record in HubSpot (if needed)
- Create deal record in HubSpot (if qualified opportunity)
- Create engagement note with analysis and context
- Create follow-up task with recommended next action
- Schedule follow-up meeting (if appropriate)
- Output: CRMSyncResult with created/updated record IDs

STAGE 6: CONVERSATION STATE TRACKING (trackConversationState workflow)
- Update or create ConversationThread entity
- Track email count, lead stage progression, deal associations
- Maintain conversation history for future context
- Record latest activities (notes, tasks, meetings)
- Output: Updated ConversationThread record

EXECUTION INSTRUCTIONS:

1. Accept InboundEmailPayload from the message input
2. Execute each stage in order through the LeadPipelineOrchestrator flow
3. Pass outputs from each stage as inputs to the next stage maintaining data integrity
4. Ensure all data flows correctly between stages without loss
5. Handle both qualified and unqualified emails appropriately
6. For unqualified emails bypass directly to QualificationRejection workflow
7. For qualified emails process through all 6 stages to complete CRM sync

ERROR HANDLING:
- If any stage fails preserve as much data as possible
- Missing data should use empty strings or default values not null
- If CRM sync fails still attempt to track conversation state
- Log errors but continue pipeline execution where possible

KEY PRINCIPLES:

- Data Integrity: Preserve all email data exactly through the pipeline never truncate or modify
- Context Awareness: Use existing CRM data and conversation history in all decisions
- Conservative Qualification: Better to process borderline cases than miss sales opportunities
- Accurate Classification: Base lead scoring on clear signals from email content not assumptions
- Actionable Outputs: Generate specific actionable next steps for sales follow-up not generic advice
- Complete CRM Sync: Ensure all relevant data reaches HubSpot for sales team visibility
- Conversation Continuity: Always check thread history to understand conversation progression

DATA FLOW VALIDATION:
- EmailQualificationResult must pass ALL email fields to LeadIntelligence unchanged
- LeadIntelligence must pass ALL email fields to downstream workflows unchanged
- Each stage must preserve data from previous stages
- Final ConversationThread must have complete context from entire pipeline

The email data is provided in the message. Execute the LeadPipelineOrchestrator flow systematically through all stages."
}

workflow @after create:gmail/Email {
    {SalesEngagementConfig? {}} @as [config];
    
    
    {InboundEmailPayload {
        sender gmail/Email.sender,
        recipients gmail/Email.recipients,
        subject gmail/Email.subject,
        body gmail/Email.body,
        date gmail/Email.date,
        threadId gmail/Email.thread_id,
        gmailOwnerEmail config.gmailOwnerEmail,
        hubspotOwnerId config.hubspotOwnerId
    }} @as emailData;

    {LeadPipelineOrchestrator {message emailData}}
}
