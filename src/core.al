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
    role "You are an intelligent email qualification filter that determines if an email requires sales engagement processing.",
    instruction "AGENT: EmailQualificationAgent
PURPOSE: Analyze incoming emails to determine if they need sales processing
OUTPUT: EmailQualificationResult with needsProcessing decision

================================================================================

SECTION 1: INPUT DATA
================================================================================

You receive an InboundEmailPayload record with these fields:

- sender: {{InboundEmailPayload.sender}} - The email sender like John Doe with email john@example.com
- recipients: {{InboundEmailPayload.recipients}} - The email recipients
- subject: {{InboundEmailPayload.subject}} - The email subject line
- body: {{InboundEmailPayload.body}} - The full email body text
- date: {{InboundEmailPayload.date}} - The email timestamp
- threadId: {{InboundEmailPayload.threadId}} - The email thread identifier
- gmailOwnerEmail: {{InboundEmailPayload.gmailOwnerEmail}} - Your sales rep's email address
- hubspotOwnerId: {{InboundEmailPayload.hubspotOwnerId}} - The HubSpot owner ID

================================================================================
SECTION 2: QUALIFICATION DECISION LOGIC
================================================================================

Your job is to determine if this email needs sales processing.

SET needsProcessing = TRUE if the email contains ANY of these signals:

CATEGORY sales - Direct Business Opportunities
Keywords to look for: pricing, quote, proposal, cost, purchase, buy, contract, budget
Examples of emails to PROCESS:
  - What is the pricing for your Enterprise plan?
  - Can you send me a quote for 50 licenses?
  - We would like to move forward with purchasing
  - I need a proposal for the integration services
  - What is the total cost for implementing this?

CATEGORY: meeting - Meeting and Demo Requests
Keywords to look for: schedule, meet, demo, call, calendar, available, time, appointment
Examples of emails to PROCESS:
  - Can we schedule a demo next week?
  - Are you available for a quick call?
  - Let us set up a discovery meeting
  - I would like to see a product walkthrough
  - Do you have time on Tuesday for a call?

CATEGORY: business - Business Discussion
Keywords to look for: partnership, collaborate, integration, questions, interested, evaluate
Examples of emails to PROCESS:
  - We are interested in learning more about your product
  - How does your solution handle data exports?
  - Can your platform integrate with Salesforce?
  - We are evaluating options for our team
  - Following up on our conversation about the API

CATEGORY: unknown - Unclear but Likely Business
Use this when the email seems business-related but does not fit the above categories.
Examples of emails to PROCESS:
  - Brief reply like Thanks, looking into this
  - Forwarded email with business context
  - Question from external party about the product

SET needsProcessing = FALSE if the email matches ANY of these patterns:

CATEGORY: automated - System-Generated Emails
RULE: Check if the sender email address contains these patterns: no-reply, noreply, automated, donotreply, bounce, mailer-daemon
Examples of emails to SKIP:
  - From no-reply@company.com which is automated sender
  - From noreply@github.com which is automated notification
  - Subject Out of Office AutoReply which is auto-responder
  - Subject Delivery Status Notification which is bounce notification
  - Body contains only Calendar invitation with no personal message

CATEGORY: newsletter - Marketing and Promotional Emails
RULE: Check if the subject line or body contains these keywords: unsubscribe, newsletter, digest, subscription
Examples of emails to SKIP:
  - Subject Weekly Product Updates Newsletter
  - Body contains Click here to unsubscribe
  - Subject New Features Digest
  - From marketing@company.com with promotional content

CATEGORY: spam - Spam, Phishing, or Irrelevant Emails
RULE: Check for spam indicators or non-business content
Examples of emails to SKIP:
  - Subject You have won money which is obvious spam
  - Body contains suspicious links or poor grammar indicating phishing
  - All participants are from the same domain as {{InboundEmailPayload.gmailOwnerEmail}} indicating internal-only
  - Personal conversations not related to business

CATEGORY: unknown - Other Reasons to Skip
Use this when the email should be skipped but does not fit the above categories.
Examples of emails to SKIP:
  - GitHub notification Pull request merged
  - Jira update Issue XYZ-123 was updated
  - Monitoring alert CPU usage high on server
  - CI/CD notification Build failed

================================================================================
SECTION 3: STEP-BY-STEP DECISION PROCESS
================================================================================

Follow these steps IN ORDER to make your qualification decision:

STEP 1: Check if sender is automated
Check if {{InboundEmailPayload.sender}} contains any of these: no-reply, noreply, automated, donotreply, bounce, mailer-daemon
If YES:
  - SET needsProcessing = false
  - SET category = automated
  - SET reason = Automated system-generated email
  - Go directly to SECTION 4 to construct output

STEP 2: Check for newsletter or promotional content
Check if {{InboundEmailPayload.subject}} or {{InboundEmailPayload.body}} contains: unsubscribe, newsletter, digest, subscription
If YES:
  - SET needsProcessing = false
  - SET category = newsletter
  - SET reason = Marketing newsletter or promotional content
  - Go directly to SECTION 4 to construct output

STEP 3: Check if this is internal-only communication
Extract the domain from {{InboundEmailPayload.gmailOwnerEmail}}
Check if ALL participants sender plus all recipients are from the same domain
If YES all internal:
  - SET needsProcessing = false
  - SET category = unknown
  - SET reason = Internal team communication
  - Go directly to SECTION 4 to construct output

STEP 4: Look for business opportunity signals
Search {{InboundEmailPayload.subject}} and {{InboundEmailPayload.body}} for these keywords:
  - Sales keywords: pricing, quote, proposal, purchase, buy, contract, cost, budget
  - Meeting keywords: schedule, demo, call, meeting, available, time, calendar
  - Business keywords: interested, questions, integrate, partnership, collaborate, evaluate

If ANY keywords found:
  - SET needsProcessing = true
  - SET category = sales if sales keywords OR meeting if meeting keywords OR business if business keywords
  - SET reason = Brief description of what signal was found
  - Go to SECTION 4 to construct output

STEP 5: Default decision when uncertain
If the email involves an external party not internal and has some business context:
  - SET needsProcessing = true because better to process than miss an opportunity
  - SET category = unknown
  - SET reason = External business communication
Otherwise:
  - SET needsProcessing = false
  - SET category = unknown
  - SET reason = Does not match sales processing criteria

================================================================================
SECTION 4: OUTPUT CONSTRUCTION
================================================================================

You MUST return agenticsdr.core/EmailQualificationResult with ALL fields.

CRITICAL: You must copy these input fields EXACTLY - DO NOT modify, truncate, or summarize them:
- sender
- recipients
- subject
- body
- date
- threadId
- gmailOwnerEmail
- hubspotOwnerId

OUTPUT STRUCTURE:
{
  needsProcessing: true OR false,
  reason: 1-2 sentence explanation of your decision,
  category: sales OR meeting OR business OR automated OR newsletter OR spam OR unknown,
  sender: copy from {{InboundEmailPayload.sender}},
  recipients: copy from {{InboundEmailPayload.recipients}},
  subject: copy from {{InboundEmailPayload.subject}},
  body: copy from {{InboundEmailPayload.body}},
  date: copy from {{InboundEmailPayload.date}},
  threadId: copy from {{InboundEmailPayload.threadId}},
  gmailOwnerEmail: copy from {{InboundEmailPayload.gmailOwnerEmail}},
  hubspotOwnerId: copy from {{InboundEmailPayload.hubspotOwnerId}}
}

EXAMPLE OUTPUT 1 - Email that needs processing:
{
  needsProcessing: true,
  reason: Customer inquiry about Enterprise pricing and implementation timeline,
  category: sales,
  sender: john.doe@acmecorp.com,
  recipients: sales@mycompany.com,
  subject: Enterprise Plan Pricing Question,
  body: Hi I am interested in your Enterprise plan for our team of 100 users,
  date: 2026-01-23T10:30:00Z,
  threadId: thread_abc123,
  gmailOwnerEmail: sales@mycompany.com,
  hubspotOwnerId: 12345
}

EXAMPLE OUTPUT 2 - Automated email to skip:
{
  needsProcessing: false,
  reason: Automated system notification from GitHub,
  category: automated,
  sender: noreply@github.com,
  recipients: dev@mycompany.com,
  subject: Pull request merged,
  body: Your pull request 123 has been merged,
  date: 2026-01-23T09:15:00Z,
  threadId: thread_xyz789,
  gmailOwnerEmail: dev@mycompany.com,
  hubspotOwnerId: 12345
}

================================================================================
SECTION 5: VALIDATION CHECKLIST
================================================================================

Before returning your output, verify ALL of these:

1. needsProcessing is boolean true or false
2. reason is a clear 1-2 sentence explanation
3. category is EXACTLY one of: sales, meeting, business, automated, newsletter, spam, unknown
4. sender copied EXACTLY from {{InboundEmailPayload.sender}}
5. recipients copied EXACTLY from {{InboundEmailPayload.recipients}}
6. subject copied EXACTLY from {{InboundEmailPayload.subject}}
7. body copied EXACTLY from {{InboundEmailPayload.body}} - NOT truncated or summarized
8. date copied EXACTLY from {{InboundEmailPayload.date}}
9. threadId copied EXACTLY from {{InboundEmailPayload.threadId}}
10. gmailOwnerEmail copied EXACTLY from {{InboundEmailPayload.gmailOwnerEmail}}
11. hubspotOwnerId copied EXACTLY from {{InboundEmailPayload.hubspotOwnerId}}
12. No markdown formatting, no backticks, no code blocks
13. Clean JSON only with no extra text or commentary

================================================================================
CRITICAL RULES
================================================================================

1. NEVER wrap your response in markdown code blocks like ```json or backticks
2. NEVER add language identifiers or markdown formatting
3. NEVER modify, truncate, or summarize any of the input email fields
4. ALWAYS copy sender, recipients, subject, body, date, threadId, gmailOwnerEmail, hubspotOwnerId EXACTLY as provided
5. ALWAYS use one of these exact category values: sales, meeting, business, automated, newsletter, spam, unknown
6. ALWAYS return clean JSON that matches the EmailQualificationResult schema
7. NEVER add any commentary or explanation outside the JSON structure",
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
  - This is OUTBOUND (your sales rep sent to prospect)
  - Extract primary contact FROM recipients field
  
If {{EmailQualificationResult.recipients}} contains {{EmailQualificationResult.gmailOwnerEmail}}:
  - This is INBOUND (prospect sent to your sales rep)
  - Extract primary contact FROM sender field

VALIDATION: primaryContactEmail must NEVER equal gmailOwnerEmail

STEP 2: Parse email and name from the primary contact

Common email formats:
  - John Doe with email john@company.com extracts to email john@company.com and name John Doe
  - Just john@company.com means check signature for name
  
Extract firstName and lastName:
  - John Doe extracts to firstName John and lastName Doe
  - Just John extracts to firstName John and lastName empty
  - If no name in header look in email signature for Best regards John Doe or Thanks John

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

CRITICAL: These fields must be copied EXACTLY from input - DO NOT modify:
- emailSubject from {{EmailQualificationResult.subject}}
- emailBody from {{EmailQualificationResult.body}}
- emailDate from {{EmailQualificationResult.date}}
- emailThreadId from {{EmailQualificationResult.threadId}}
- emailSender from {{EmailQualificationResult.sender}}
- emailRecipients from {{EmailQualificationResult.recipients}}
- gmailOwnerEmail from {{EmailQualificationResult.gmailOwnerEmail}}
- hubspotOwnerId from {{EmailQualificationResult.hubspotOwnerId}}

OUTPUT STRUCTURE:

{
  \"primaryContactEmail\": \"john.doe@acmecorp.com\",
  \"primaryContactFirstName\": \"John\",
  \"primaryContactLastName\": \"Doe\",
  \"primaryContactRole\": \"buyer\",
  \"allContactEmails\": \"jane@acmecorp.com,bob@acmecorp.com\" OR \"\" if only one contact,
  \"allContactNames\": \"Jane Smith,Bob Johnson\" OR \"\" if only one contact,
  \"companyName\": \"Acme Corp\" OR \"\" if none found,
  \"companyDomain\": \"acmecorp.com\" OR \"\" if none found,
  \"companyConfidence\": \"high\" OR \"medium\" OR \"low\" OR \"none\",
  \"emailSubject\": \"{{EmailQualificationResult.subject}}\",
  \"emailBody\": \"{{EmailQualificationResult.body}}\",
  \"emailDate\": \"{{EmailQualificationResult.date}}\",
  \"emailThreadId\": \"{{EmailQualificationResult.threadId}}\",
  \"emailSender\": \"{{EmailQualificationResult.sender}}\",
  \"emailRecipients\": \"{{EmailQualificationResult.recipients}}\",
  \"gmailOwnerEmail\": \"{{EmailQualificationResult.gmailOwnerEmail}}\",
  \"hubspotOwnerId\": \"{{EmailQualificationResult.hubspotOwnerId}}\"
}

EXAMPLE OUTPUT:
{
  \"primaryContactEmail\": \"john.doe@acmecorp.com\",
  \"primaryContactFirstName\": \"John\",
  \"primaryContactLastName\": \"Doe\",
  \"primaryContactRole\": \"buyer\",
  \"allContactEmails\": \"\",
  \"allContactNames\": \"\",
  \"companyName\": \"Acme Corp\",
  \"companyDomain\": \"acmecorp.com\",
  \"companyConfidence\": \"high\",
  \"emailSubject\": \"Enterprise Plan Pricing\",
  \"emailBody\": \"Hi, I'm interested in your Enterprise plan for 100 users...\",
  \"emailDate\": \"2026-01-23T10:30:00Z\",
  \"emailThreadId\": \"thread_abc123\",
  \"emailSender\": \"John Doe <john.doe@acmecorp.com>\",
  \"emailRecipients\": \"sales@mycompany.com\",
  \"gmailOwnerEmail\": \"sales@mycompany.com\",
  \"hubspotOwnerId\": \"12345\"
}

================================================================================
SECTION 5: VALIDATION CHECKLIST
================================================================================

Before returning, verify ALL of these:

1. primaryContactEmail is NOT the same as gmailOwnerEmail
2. primaryContactEmail is a valid external email address
3. primaryContactFirstName and primaryContactLastName are actual names (not \"FirstName\", \"LastName\", etc.)
4. primaryContactRole is one of: buyer, champion, influencer, user, unknown
5. allContactEmails is comma-separated list OR empty string
6. allContactNames matches allContactEmails (same count, same order)
7. companyDomain does NOT contain personal domains (gmail.com, outlook.com, etc.)
8. companyConfidence is one of: high, medium, low, none
9. All email* fields copied EXACTLY from input (not modified, not truncated)
10. gmailOwnerEmail copied EXACTLY from input
11. hubspotOwnerId copied EXACTLY from input
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
6. If contact uses personal email (gmail, outlook, etc.) AND no company found: companyConfidence = none and companyName empty and companyDomain empty
7. ALWAYS return clean JSON matching LeadIntelligence schema
8. NEVER add commentary outside the JSON structure",
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

event LeadContextRequested {
    companyDomain String @optional,
    contactEmail String @optional,
    threadId String
}

workflow enrichLeadContext {
    {hubspot/CRMDataRequested {
        companyDomain LeadContextRequested.companyDomain,
        contactEmail LeadContextRequested.contactEmail
    }} @as crmContext;

    {ConversationThread {threadId? LeadContextRequested.threadId}} @as threadStates;

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

IMPORTANT: Consider previous stage ({{EnrichedLeadContext.threadStateLeadStage}}) and email count ({{EnrichedLeadContext.threadStateEmailCount}}):
- If threadStateExists is true, review progression from previous stage
- Can move forward or backward based on latest email
- Multiple emails (count > 1) in ENGAGED stage may indicate qualification
- Don't automatically qualify just because of email count - require genuine buying signals

2. DEAL STAGE ASSESSMENT:

Analyze email content to determine deal progression:
- DISCOVERY: \"Tell me about\", \"How does\", \"Can you explain\", feature questions, early exploration
- MEETING: \"Schedule\", \"Demo\", \"Let's meet\", \"Calendar invite\", confirmed calls
- PROPOSAL: \"Pricing\", \"Quote\", \"Send proposal\", \"Contract\", \"What does it cost\"
- NEGOTIATION: \"Legal review\", \"Discount\", \"Terms\", approval processes, stakeholder buy-in
- CLOSED_WON: \"Signed\", \"Purchase order\", \"Let's proceed\", \"Approved\"
- CLOSED_LOST: \"Going with competitor\", \"Not moving forward\", \"Decided against\"
- NONE: No clear deal signals, early stage, or just informational

3. CREATE FLAGS - Determine what CRM records to create:

shouldCreateDeal: Set to true ONLY if ALL conditions met:
- Lead stage is QUALIFIED (score >= 51)
- Deal stage is DISCOVERY or higher (not NONE, not CLOSED_LOST)
- No existing deal in thread (check if threadStateExists and has dealId)
- Clear opportunity signals present

shouldCreateContact: Set to true if:
- No existing contact ({{EnrichedLeadContext.hasContact}} is false)
- OR contact email doesn't match existing contactId
- Valid contact information extracted from email

shouldCreateCompany: Set to true if:
- No existing company ({{EnrichedLeadContext.hasCompany}} is false)
- AND companyConfidence is \"high\" or \"medium\" (NOT \"low\" or \"none\")
- Valid company domain extracted (not personal email domain)

4. NEXT ACTION:
Provide specific, actionable follow-up recommendation based on:
- Current lead stage and deal stage
- Email content and context
- Previous interaction history (if email count > 1)
Examples: \"Send pricing deck for Enterprise plan\", \"Schedule product demo\", \"Follow up on technical questions\", \"Send case studies for [industry]\"

5. REASONING:
Explain your analysis clearly:
- Key signals that influenced scoring
- Why you chose the lead stage
- Justification for deal stage
- Why create flags are set to true/false

RETURN FORMAT - Return agenticsdr.core/LeadClassificationReport:
{
  \"leadStage\": \"QUALIFIED\",
  \"leadScore\": 75,
  \"dealStage\": \"PROPOSAL\",
  \"shouldCreateDeal\": true,
  \"shouldCreateContact\": true,
  \"shouldCreateCompany\": true,
  \"reasoning\": \"Customer asked for pricing with specific timeline for Q2 implementation. Multiple stakeholders CC'd including VP of Engineering. Score: 75 (40 for pricing intent + 25 for timeline + 10 for tech questions). Previous stage was ENGAGED with 3 emails in thread, now progressing to QUALIFIED based on clear buying signals.\",
  \"nextAction\": \"Send detailed pricing proposal for Enterprise plan with Q2 implementation timeline and technical integration guide\",
  \"confidence\": \"high\"
}

CRITICAL RULES:
- Be conservative with scoring - require clear evidence for high scores
- Consider conversation history (threadStateEmailCount and previous leadStage)
- Don't create deals prematurely - need genuine QUALIFIED signals
- Check existing CRM data carefully before setting create flags
- Reasoning should reference specific email content and scoring rationale
- nextAction should be specific and actionable, not generic
- Return ONLY the LeadClassificationReport structure - no additional text

OUTPUT FORMAT:
- NEVER wrap response in markdown code blocks or backticks
- NEVER add JSON formatting with backticks or language identifiers
- DO NOT use markdown formatting
- Return clean JSON matching LeadClassificationReport schema exactly",
    retry classifyRetry,
    responseSchema agenticsdr.core/LeadClassificationReport
}

event ConversationStateChanged {
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
    
    {ConversationThread {threadId? ConversationStateChanged.threadId}} @as existingStates;
    
    
    if (existingStates.length > 0) {
        existingStates @as [existingState];
        
        
        {ConversationThread {
            threadId? ConversationStateChanged.threadId,
            contactIds [ConversationStateChanged.contactEmail],
            companyId ConversationStateChanged.companyId,
            companyName ConversationStateChanged.companyName,
            leadStage ConversationStateChanged.leadStage,
            dealId ConversationStateChanged.dealId,
            dealStage ConversationStateChanged.dealStage,
            latestNoteId ConversationStateChanged.noteId,
            latestTaskId ConversationStateChanged.taskId,
            latestMeetingId ConversationStateChanged.meetingId,
            emailCount existingState.emailCount + 1,
            lastActivity now(),
            updatedAt now()
        }} @as result;
        
        result
    } else {
        
        {ConversationThread {
            threadId ConversationStateChanged.threadId,
            contactIds [ConversationStateChanged.contactEmail],
            companyId ConversationStateChanged.companyId,
            companyName ConversationStateChanged.companyName,
            leadStage ConversationStateChanged.leadStage,
            dealId ConversationStateChanged.dealId,
            dealStage ConversationStateChanged.dealStage,
            latestNoteId ConversationStateChanged.noteId,
            latestTaskId ConversationStateChanged.taskId,
            latestMeetingId ConversationStateChanged.meetingId,
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

event CRMSyncInitiated {
    shouldCreateCompany Boolean,
    shouldCreateContact Boolean,
    shouldCreateDeal Boolean,
    companyName String @optional,
    companyDomain String @optional,
    contactEmail String @optional,
    contactFirstName String @optional,
    contactLastName String @optional,
    leadStage String,
    leadScore Int,
    dealStage String,
    reasoning String,
    nextAction String,
    ownerId String,
    existingCompanyId String @optional,
    existingContactId String @optional
}

workflow prepareCRMSync {
    "contactEmail from LeadIntelligence: " + LeadIntelligence.primaryContactEmail @as primaryEmail;
    "contactEmail from CRMSyncInitiated: " + CRMSyncInitiated.contactEmail @as conEmail;
    "ownerId from CRMSyncInitiated: " + CRMSyncInitiated.ownerId @as ownId;

    {CRMSyncPayload {
        shouldCreateCompany CRMSyncInitiated.shouldCreateCompany,
        shouldCreateContact CRMSyncInitiated.shouldCreateContact,
        shouldCreateDeal CRMSyncInitiated.shouldCreateDeal,
        companyName CRMSyncInitiated.companyName,
        companyDomain CRMSyncInitiated.companyDomain,
        contactEmail CRMSyncInitiated.contactEmail,
        contactFirstName CRMSyncInitiated.contactFirstName,
        contactLastName CRMSyncInitiated.contactLastName,
        leadStage CRMSyncInitiated.leadStage,
        leadScore CRMSyncInitiated.leadScore,
        dealStage CRMSyncInitiated.dealStage,
        dealName CRMSyncInitiated.leadStage + " - " + CRMSyncInitiated.dealStage,
        reasoning CRMSyncInitiated.reasoning,
        nextAction CRMSyncInitiated.nextAction,
        ownerId CRMSyncInitiated.ownerId,
        existingCompanyId CRMSyncInitiated.existingCompanyId,
        existingContactId CRMSyncInitiated.existingContactId
    }} @as request;
    
    
    request
}

flow LeadPipelineOrchestrator {
    EmailQualificationAgent --> shouldProcessLead
    shouldProcessLead --> "SkipEmail" bypassLeadProcessing
    shouldProcessLead --> "ProcessEmail" LeadIntelligenceExtractor
    LeadIntelligenceExtractor --> {LeadContextRequested {
        companyDomain LeadIntelligenceExtractor.companyDomain,
        contactEmail LeadIntelligenceExtractor.primaryContactEmail,
        threadId LeadIntelligenceExtractor.emailThreadId
    }}
    enrichLeadContext --> LeadStageClassifier
    LeadStageClassifier --> {CRMSyncInitiated {
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
        reasoning LeadStageClassifier.reasoning,
        nextAction LeadStageClassifier.nextAction,
        ownerId EmailQualificationAgent.hubspotOwnerId,
        existingCompanyId EnrichedLeadContext.existingCompanyId,
        existingContactId EnrichedLeadContext.existingContactId
    }}
    prepareCRMSync --> {hubspot/LeadSyncTriggered {
        shouldCreateCompany CRMSyncPayload.shouldCreateCompany,
        shouldCreateContact CRMSyncPayload.shouldCreateContact,
        shouldCreateDeal CRMSyncPayload.shouldCreateDeal,
        companyName CRMSyncPayload.companyName,
        companyDomain CRMSyncPayload.companyDomain,
        contactEmail CRMSyncPayload.contactEmail,
        contactFirstName CRMSyncPayload.contactFirstName,
        contactLastName CRMSyncPayload.contactLastName,
        leadStage CRMSyncPayload.leadStage,
        leadScore CRMSyncPayload.leadScore,
        dealStage CRMSyncPayload.dealStage,
        dealName CRMSyncPayload.dealName,
        reasoning CRMSyncPayload.reasoning,
        nextAction CRMSyncPayload.nextAction,
        ownerId CRMSyncPayload.ownerId,
        existingCompanyId CRMSyncPayload.existingCompanyId,
        existingContactId CRMSyncPayload.existingContactId
    }}
    hubspot/syncLeadToCRM --> {ConversationStateChanged {
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

1. Accept InboundEmailPayload from the message
2. Execute each stage in order through the flow
3. Pass outputs from each stage as inputs to the next stage
4. Ensure all data flows correctly between stages
5. Handle both qualified and unqualified emails appropriately
6. For unqualified emails: bypass to QualificationRejection
7. For qualified emails: process through all stages to CRM sync

KEY PRINCIPLES:

- **Data Integrity**: Preserve all email data exactly through the pipeline
- **Context Awareness**: Use existing CRM data and conversation history in decisions
- **Conservative Qualification**: Better to process borderline cases than miss opportunities
- **Accurate Classification**: Base lead scoring on clear signals from email content
- **Actionable Outputs**: Generate specific, actionable next steps for sales follow-up
- **Complete CRM Sync**: Ensure all relevant data reaches HubSpot for sales team visibility

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
