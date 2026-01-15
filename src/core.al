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

record EmailRelevanceResult {
    isRelevant Boolean,
    reason String,
    category String @enum("business", "meeting", "sales", "automated", "newsletter", "spam", "unknown") @optional,
    gmailOwnerEmail String @optional,
    hubspotOwnerId String @optional,
    emailSender String @optional,
    emailRecipients String @optional,
    emailSubject String @optional,
    emailBody String @optional,
    emailDate String @optional,
    emailThreadId String @optional
}

record SkipResult {
    skipped Boolean,
    reason String
}

record ExtractedContact {
    email String,
    name String @optional,
    firstName String @optional,
    lastName String @optional,
    role String @enum("buyer", "user", "influencer", "champion", "unknown") @default("unknown")
}

record MultiContactResult {
    contacts ExtractedContact[],
    primaryContactEmail String @optional,
    excludedEmails String[]
}

record CompanyResolutionResult {
    resolved Boolean,
    companyName String @optional,
    domain String @optional,
    confidence String @enum("high", "medium", "low") @default("low"),
    source String @enum("domain", "signature", "existing", "conversation") @optional
}

record LeadQualificationResult {
    qualified Boolean,
    score Int,
    stage String @enum("NEW", "ENGAGED", "QUALIFIED", "DISQUALIFIED"),
    reasoning String,
    nextAction String @optional
}

record DealStageResult {
    stage String @enum("DISCOVERY", "MEETING", "PROPOSAL", "NEGOTIATION", "CLOSED_WON", "CLOSED_LOST"),
    reasoning String,
    confidence String @enum("high", "medium", "low"),
    shouldCreateDeal Boolean
}

record MeetingInfo {
    title String,
    body String,
    date String,
    participants String[]
}

agent filterEmailRelevance {
    llm "sonnet_llm",
    role "You are an intelligent email filter that protects the CRM from irrelevant noise.",
    instruction "Analyze the email to determine if it should be processed in the CRM.

INPUT DATA:
- Sender: {{EmailData.sender}}
- Recipients: {{EmailData.recipients}}
- Subject: {{EmailData.subject}}
- Body: {{EmailData.body}}
- Date: {{EmailData.date}}

CLASSIFICATION RULES:

✅ RELEVANT (isRelevant: true) - Process if:
- Business discussion with clients/prospects
- Meeting coordination or scheduling
- Sales conversation or proposal
- Follow-up on commercial opportunity
- Onboarding or product discussion
- Question about products/services
- Demo request or trial discussion

❌ IRRELEVANT (isRelevant: false) - Skip if:
- Automated sender (contains: no-reply, noreply, automated, donotreply)
- Newsletter or digest (subject contains: unsubscribe, newsletter, digest)
- Marketing blast or promotional email
- System notification (password reset, account alert)
- Internal team communication (if all participants are from same domain as owner)
- Spam or suspicious content
- Out of office replies

RETURN FORMAT:
if it should be processed:

{
  \"isRelevant\": true,
  \"reason\": \"Brief explanation (1 sentence)\",
  \"category\": \"business\" | \"meeting\" | \"sales\" | \"automated\" | \"newsletter\" | \"spam\" | \"unknown\",
  \"gmailOwnerEmail\": gmail_main_owner_email,
  \"hubspotOwnerId\": hubspot_owner_id,
  \"emailSender\": sender,
  \"emailRecipients\": recipients,
  \"emailSubject\": subject,
  \"emailBody\": body,
  \"emailDate\": date,
  \"emailThreadId\": thread_id
}

if it shouldn't be processed:

{
 \"isRelevant\": false,
  \"reason\": \"Brief explanation (1 sentence)\",
  \"category\": \"business\" | \"meeting\" | \"sales\" | \"automated\" | \"newsletter\" | \"spam\" | \"unknown\"
}

CRITICAL: Return ONLY the EmailRelevanceResult structure, no markdown formatting.

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticsdr.core/EmailRelevanceResult
}

agent extractMultipleContacts {
    llm "sonnet_llm",
    role "You extract all external participants from an email conversation, excluding the Gmail owner.",
    instruction "Extract ALL external contact information from the email thread.

INPUT DATA:
- Sender: {{EmailRelevanceResult.emailSender}}
- Recipients: {{EmailRelevanceResult.emailRecipients}}
- Body: {{EmailRelevanceResult.emailBody}}
- Gmail Owner Email: {{EmailRelevanceResult.gmailOwnerEmail}}

EXTRACTION RULES:

1. Parse email addresses and names from:
   - Sender field (format: 'Name <email@domain.com>' or just 'email@domain.com')
   - Recipients field (may contain multiple, comma-separated)
   - CC recipients (if present)

2. EXCLUDE the Gmail owner:
   - {{EmailRelevanceResult.gmailOwnerEmail}} is the USER, NOT a contact
   - Do NOT include this email in the contacts list

3. For each external participant, extract:
   - email (required)
   - full name (if available from 'Name <email>' format)
   - firstName (split from name)
   - lastName (split from name, can be empty)
   - role (infer from email content and context):
     * 'buyer' - decision maker, executive, mentions budget/approval
     * 'champion' - enthusiastic supporter, internal advocate
     * 'influencer' - provides input, evaluates options
     * 'user' - end user, technical evaluator
     * 'unknown' - cannot determine role

4. Determine primaryContactEmail:
   - If sender is external → primaryContactEmail = sender
   - If recipients contain external emails → primaryContactEmail = first external recipient
   - Primary contact is the main stakeholder

5. List all excluded emails (including Gmail owner)

RETURN FORMAT:
{
  \"contacts\": [
    {\"email\": \"actual@email.com\", \"name\": \"John Doe\", \"firstName\": \"John\", \"lastName\": \"Doe\", \"role\": \"buyer\"},
    {\"email\": \"another@email.com\", \"name\": \"Jane Smith\", \"firstName\": \"Jane\", \"lastName\": \"Smith\", \"role\": \"user\"}
  ],
  \"primaryContactEmail\": \"actual@email.com\",
  \"excludedEmails\": [\"{{EmailRelevanceResult.gmailOwnerEmail}}\"]
}

CRITICAL RULES:
- Use ACTUAL data from the email, not examples
- Do NOT include {{EmailRelevanceResult.gmailOwnerEmail}} in contacts
- If name not in email format, try to find in signature or body
- Return empty array if no external contacts found
- Return ONLY the MultiContactResult structure, no markdown

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticsdr.core/MultiContactResult
}

agent resolveCompany {
    llm "sonnet_llm",
    role "You identify the company/account associated with an email conversation.",
    instruction "Determine which company this conversation is with.

INPUT DATA:
- Contacts: {{MultiContactResult.contacts}}
- Primary Contact Email: {{MultiContactResult.primaryContactEmail}}
- Email Body: {{EmailData.body}}
- Email Signature: (look for company name in body/signature)

RESOLUTION STRATEGY (try in order):

1. DOMAIN MATCHING (highest confidence)
   - Extract domain from primary contact email
   - Example: alice@acme.com → domain: acme.com, name: Acme
   - Clean up domain name (remove .com, capitalize)

2. SIGNATURE PARSING (medium-high confidence)
   - Look for company name in email signature
   - Common patterns:
     * Line with just company name
     * Line with title + company (e.g., \"CEO at Acme Corp\")
     * Footer with company information

3. CONVERSATION DOMINANCE (medium confidence)
   - If multiple external domains, choose most frequent
   - Example: 3 from acme.com, 1 from other.com → acme.com

4. EXPLICIT MENTION (low-medium confidence)
   - Company name mentioned in body
   - Phrases like \"At [Company]\" or \"[Company] team\"

RETURN FORMAT:
{
  \"resolved\": true/false,
  \"companyName\": \"Acme Corp\" (human-readable name),
  \"domain\": \"acme.com\" (canonical domain),
  \"confidence\": \"high\" | \"medium\" | \"low\",
  \"source\": \"domain\" | \"signature\" | \"existing\" | \"conversation\"
}

RULES:
- If ambiguous or unclear, set resolved: false
- Do NOT guess company names
- Use actual domain from email addresses
- Clean domain: remove www, .com/etc for name generation
- Return ONLY the CompanyResolutionResult structure, no markdown

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticsdr.core/CompanyResolutionResult
}

agent qualifyLead {
    llm "sonnet_llm",
    role "You qualify leads based on email conversations to determine if they are sales-worthy.",
    instruction "Evaluate this company/lead based on the conversation.

INPUT DATA:
- Company: {{CompanyResolutionResult.companyName}}
- Contacts: {{MultiContactResult.contacts}}
- Email Subject: {{EmailData.subject}}
- Email Body: {{EmailData.body}}
- Thread Email Count: {{ThreadState.emailCount}}
- Current Lead Stage: {{ThreadState.leadStage}}

QUALIFICATION CRITERIA:

Score (0-100):
+40: Explicit buying intent (mentions: purchase, buy, pricing, contract)
+30: Meeting request or scheduled call
+20: Product/feature questions indicating evaluation
+20: Multiple stakeholders involved (>1 contact)
+15: Response to outreach (shows engagement)
+10: Detailed technical questions
+10: Timeline mentioned (urgency)
-20: Just saying thanks/acknowledgment
-30: Unsubscribe or not interested
-50: Spam or irrelevant

Stage Assessment:
- NEW (0-20): Initial contact, no clear intent
- ENGAGED (21-50): Active conversation, some interest
- QUALIFIED (51-100): Strong buying signals, ready for deal
- DISQUALIFIED (<0): Not interested, spam, bad fit

Next Action Suggestions:
- QUALIFIED: \"Create deal and move to discovery\"
- ENGAGED: \"Continue nurturing, share case study\"
- NEW: \"Send follow-up email with value proposition\"
- DISQUALIFIED: \"Mark as closed-lost, stop outreach\"

RETURN FORMAT:
{
  \"qualified\": true (if score >= 51),
  \"score\": 75,
  \"stage\": \"QUALIFIED\",
  \"reasoning\": \"Customer explicitly asked for pricing and demo. Multiple stakeholders involved.\",
  \"nextAction\": \"Create deal and schedule discovery call\"
}

RULES:
- Be conservative with scoring
- Previous stage context matters (cannot go from DISQUALIFIED to QUALIFIED without strong evidence)
- Return ONLY the LeadQualificationResult structure, no markdown

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticsdr.core/LeadQualificationResult
}

agent classifyDealStage {
    llm "sonnet_llm",
    role "You analyze sales conversations to determine the appropriate deal stage.",
    instruction "Determine the deal stage based on conversation signals.

INPUT DATA:
- Email Subject: {{EmailData.subject}}
- Email Body: {{EmailData.body}}
- Current Deal Stage: {{ThreadState.dealStage}}
- Lead Stage: {{ThreadState.leadStage}}
- Thread Email Count: {{ThreadState.emailCount}}

STAGE DEFINITIONS:

🔍 DISCOVERY (Initial exploration)
- Signals: \"Tell me about\", \"How does it work\", \"What are the options\"
- Customer is learning about solution
- Questions about features, use cases, fit

📅 MEETING (Formal engagement scheduled/completed)
- Signals: \"Let's schedule\", \"Demo\", \"Call confirmed\", \"Meeting notes\"
- Calendar invite sent/received
- Formal presentation or demo occurred

📄 PROPOSAL (Commercial discussion)
- Signals: \"Pricing\", \"Quote\", \"Proposal\", \"Terms\", \"Contract\"
- Specific pricing shared
- Commercial terms discussed
- MSA or contract mentioned

🤝 NEGOTIATION (Final details)
- Signals: \"Legal review\", \"Negotiate\", \"Discount\", \"Final approval\"
- Back-and-forth on terms
- Stakeholder approvals happening
- Close date discussed

✅ CLOSED_WON (Deal won)
- Signals: \"Contract signed\", \"Purchase order\", \"Let's proceed\", \"Approved\"
- Clear commitment to buy
- Signed agreement

❌ CLOSED_LOST (Deal lost)
- Signals: \"Going with competitor\", \"Not moving forward\", \"Budget cut\"
- Explicit rejection
- Went with alternative

STAGE PROGRESSION RULES:
- Stages must progress forward (cannot skip)
- Exception: Can jump to CLOSED_LOST from any stage
- Cannot reopen CLOSED deals
- Deal should only be created if stage >= DISCOVERY

RETURN FORMAT:
{
  \"stage\": \"MEETING\",
  \"reasoning\": \"Demo scheduled for next Tuesday. Customer confirmed attendance.\",
  \"confidence\": \"high\",
  \"shouldCreateDeal\": true (only if lead is QUALIFIED and stage >= DISCOVERY)
}

RULES:
- Be conservative with stage progression
- If unsure, keep current stage
- shouldCreateDeal = true only if: leadStage == QUALIFIED AND stage >= DISCOVERY
- Return ONLY the DealStageResult structure, no markdown

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticsdr.core/DealStageResult
}

agent extractMeetingInfo {
    llm "sonnet_llm",
    role "You extract meeting information from emails to log in CRM.",
    instruction "Extract meeting details from the email.

INPUT DATA:
- Subject: {{EmailData.subject}}
- Body: {{EmailData.body}}
- Date: {{EmailData.date}}
- Participants: {{MultiContactResult.contacts}}

EXTRACTION RULES:

Title:
- Use email subject if it's descriptive
- If subject is \"Re: ...\" or generic, create a better title
- Format: \"[Meeting Type] with [Company]\"
- Examples: \"Demo Call with Acme Corp\", \"Discovery Meeting - Q1 Planning\"

Body:
- Summarize the email content
- Highlight key points, decisions, action items
- Format as structured summary:
  * Overview: [1-2 sentence summary]
  * Key Discussion Points: [bullet list]
  * Action Items: [numbered list if present]
  * Next Steps: [what happens next]
- Keep it concise but informative

Date:
- Use the email date/time
- Keep in ISO 8601 format

Participants:
- List all contact emails from MultiContactResult

RETURN FORMAT:
{
  \"title\": \"Discovery Call with Acme Corp\",
  \"body\": \"Overview: Initial discovery call...\n\nKey Points:\n- Discussed current workflow...\",
  \"date\": \"2024-01-15T10:30:00Z\",
  \"participants\": [\"contact@acme.com\", \"another@acme.com\"]
}

RULES:
- Always generate a meaningful title
- Summary should be CRM-appropriate (professional)
- Return ONLY the MeetingInfo structure, no markdown

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticsdr.core/MeetingInfo
}

event findOrCreateCompany {
    domain String,
    name String
}

workflow findOrCreateCompany {

    {hubspot/Company {domain? findOrCreateCompany.domain}} @as companies;
    
    if (companies.length > 0) {
        companies @as [company];
        company
    } else {
        {hubspot/Company {
            domain findOrCreateCompany.domain,
            name findOrCreateCompany.name,
            lifecycle_stage "lead",
            lead_status "NEW",
            ai_lead_score 0
        }} @as newCompany;

        newCompany
    }
}

event updateCompanyLeadStage {
    companyId String,
    leadStage String,
    leadScore Int
}

workflow updateCompanyLeadStage {
    if (updateCompanyLeadStage.leadStage == "QUALIFIED") {
        "salesqualifiedlead" @as lifecycleStage;
        "IN_PROGRESS" @as leadStatus
    } else if (updateCompanyLeadStage.leadStage == "ENGAGED") {
        "marketingqualifiedlead" @as lifecycleStage;
        "OPEN" @as leadStatus
    } else if (updateCompanyLeadStage.leadStage == "NEW") {
        "lead" @as lifecycleStage;
        "NEW" @as leadStatus
    } else {
        "other" @as lifecycleStage;
        "UNQUALIFIED" @as leadStatus
    };
    
    {hubspot/Company {
        id? updateCompanyLeadStage.companyId,
        lifecycle_stage lifecycleStage,
        lead_status leadStatus,
        ai_lead_score updateCompanyLeadStage.leadScore
    }}
}

event ensureContact {
    email String,
    firstName String,
    lastName String,
    companyId String @optional
}

workflow ensureContact {
    {hubspot/Contact {email? ensureContact.email}} @as foundContacts;
    
    if (foundContacts.length > 0) {
        foundContacts @as [contact];
        contact
    } else {
        // Create new contact with company association
        {hubspot/Contact {
            email ensureContact.email,
            first_name ensureContact.firstName,
            last_name ensureContact.lastName,
            company ensureContact.companyId
        }}
    }
}

event ensureMultipleContacts {
    contacts String,
    companyId String @optional
}

event findOrCreateThreadState {
    threadId String
}

workflow findOrCreateThreadState {
    {ThreadState {threadId? findOrCreateThreadState.threadId}} @as states;
    
    if (states.length > 0) {
        states @as [state];
        state
    } else {
        {ThreadState {
            threadId findOrCreateThreadState.threadId,
            leadStage "NEW"
        }}
    }
}

event updateThreadState {
    threadId String,
    contactIds String[] @optional,
    companyId String @optional,
    companyName String @optional,
    leadStage String @optional,
    dealId String @optional,
    dealStage String @optional,
    incrementEmailCount Boolean @default(false)
}

workflow updateThreadState {
    {ThreadState {threadId? updateThreadState.threadId}} @as [existingState];
    
    {ThreadState {
        threadId? updateThreadState.threadId,
        contactIds updateThreadState.contactIds,
        companyId updateThreadState.companyId,
        companyName updateThreadState.companyName,
        leadStage updateThreadState.leadStage,
        dealId updateThreadState.dealId,
        dealStage updateThreadState.dealStage,
        emailCount existingState.emailCount + 1,
        lastActivity now(),
        updatedAt now()
    }}
}

event ensureDeal {
    companyId String,
    dealStage String,
    dealName String,
    contactIds String[],
    ownerId String
}

workflow ensureDeal {
    {hubspot/Deal {
        deal_name ensureDeal.dealName,
        deal_stage ensureDeal.dealStage,
        owner ensureDeal.ownerId,
        associated_company ensureDeal.companyId,
        associated_contacts ensureDeal.contactIds,
        description "Deal created from email thread"
    }} @as createdDeal;

    {hubspot/Note {
        note_body "Deal created: " + ensureDeal.dealName + " (Stage: " + ensureDeal.dealStage + "). Created via Agentic SDR from email thread.",
        owner ensureDeal.ownerId,
        associated_company ensureDeal.companyId,
        associated_contacts ensureDeal.contactIds,
        associated_deal createdDeal.id
    }};
    
    createdDeal
}

event createMeetingEngagement {
    title String,
    body String,
    date String,
    ownerId String,
    contactIds String[],
    companyId String @optional,
    dealId String @optional
}

workflow createMeetingEngagement {
    {hubspot/Meeting {
        meeting_title createMeetingEngagement.title,
        meeting_body createMeetingEngagement.body,
        meeting_date createMeetingEngagement.date,
        owner createMeetingEngagement.ownerId,
        associated_contacts createMeetingEngagement.contactIds,
        associated_companies createMeetingEngagement.companyId,
        associated_deals createMeetingEngagement.dealId
    }}
}

event createThreadNote {
    companyId String,
    contactIds String[],
    noteBody String,
    ownerId String,
    dealId String @optional
}

workflow createThreadNote {
    {hubspot/Note {
        note_body createThreadNote.noteBody,
        owner createThreadNote.ownerId,
        associated_company createThreadNote.companyId,
        associated_contacts createThreadNote.contactIds,
        associated_deal createThreadNote.dealId
    }}
}

event createFollowUpTask {
    title String,
    description String,
    dueDate String,
    ownerId String,
    companyId String @optional,
    contactId String @optional,
    dealId String @optional
}

workflow createFollowUpTask {
    {hubspot/Task {
        title createFollowUpTask.title,
        description createFollowUpTask.description,
        due_date createFollowUpTask.dueDate,
        owner createFollowUpTask.ownerId,
        status "NOT_STARTED",
        task_type "TODO",
        associated_company createFollowUpTask.companyId,
        associated_contact createFollowUpTask.contactId,
        associated_deal createFollowUpTask.dealId
    }}
}

decision isEmailRelevant {
    case (isRelevant == true) {
        ProcessEmail
    }
    case (isRelevant == false) {
        SkipEmail
    }
}

decision shouldQualifyLead {
    case (qualified == true) {
        LeadQualified
    }
    case (qualified == false) {
        LeadNotQualified
    }
}

decision shouldCreateDeal {
    case (shouldCreateDeal == true) {
        CreateDeal
    }
    case (shouldCreateDeal == false) {
        NoDeal
    }
}

workflow skipProcessing {
    {SkipResult {
        skipped true,
        reason "Email filtered out (automated sender or newsletter)"
    }}
}

flow sdrManager {
    filterEmailRelevance --> isEmailRelevant
    isEmailRelevant --> "SkipEmail" {skipProcessing {reason EmailRelevanceResult.reason}}
    isEmailRelevant --> "ProcessEmail" extractMultipleContacts
    extractMultipleContacts --> resolveCompany
    resolveCompany --> {findOrCreateThreadState {threadId EmailData.threadId}}
    findOrCreateThreadState --> {findOrCreateCompany {
        domain CompanyResolutionResult.domain,
        name CompanyResolutionResult.companyName
    }}
    findOrCreateCompany --> qualifyLead
    qualifyLead --> {updateCompanyLeadStage {
        companyId company.id,
        leadStage LeadQualificationResult.stage,
        leadScore LeadQualificationResult.score
    }}
    updateCompanyLeadStage --> classifyDealStage
    classifyDealStage --> shouldCreateDeal
    shouldCreateDeal --> extractMeetingInfo
    extractMeetingInfo --> {ensureContact {
        email MultiContactResult.primaryContactEmail,
        firstName "Contact",
        lastName "Person",
        companyId company.id
    }}
    shouldCreateDeal --> "CreateDeal" {ensureDeal {
        companyId company.id,
        dealStage DealStageResult.stage,
        dealName CompanyResolutionResult.companyName + " - " + LeadQualificationResult.stage,
        contactIds [MultiContactResult.primaryContactEmail],
        ownerId SDRConfig.hubspotOwnerId
    }}
    ensureDeal --> {createMeetingEngagement {
        title MeetingInfo.title,
        body MeetingInfo.body,
        date MeetingInfo.date,
        ownerId SDRConfig.hubspotOwnerId,
        contactIds [MultiContactResult.primaryContactEmail],
        companyId company.id,
        dealId createdDeal.id
    }}
    createMeetingEngagement --> {createThreadNote {
        companyId company.id,
        contactIds [MultiContactResult.primaryContactEmail],
        noteBody "✅ QUALIFIED LEAD | Score: " + LeadQualificationResult.score + " | Lead Stage: " + LeadQualificationResult.stage + " | Deal Stage: " + DealStageResult.stage + "\n\nReasoning: " + LeadQualificationResult.reasoning + "\n\nNext Action: " + LeadQualificationResult.nextAction,
        ownerId SDRConfig.hubspotOwnerId,
        dealId createdDeal.id
    }}
    createThreadNote --> {updateThreadState {
        threadId EmailData.threadId,
        companyId company.id,
        companyName CompanyResolutionResult.companyName,
        leadStage LeadQualificationResult.stage,
        dealId createdDeal.id,
        dealStage DealStageResult.stage,
        incrementEmailCount true
    }}
    shouldCreateDeal --> "NoDeal" {createMeetingEngagement {
        title MeetingInfo.title,
        body MeetingInfo.body,
        date MeetingInfo.date,
        ownerId SDRConfig.hubspotOwnerId,
        contactIds [MultiContactResult.primaryContactEmail],
        companyId company.id
    }}
    shouldCreateDeal --> "NoDeal" {createThreadNote {
        companyId company.id,
        contactIds [MultiContactResult.primaryContactEmail],
        noteBody "📊 Lead Analysis | Score: " + LeadQualificationResult.score + " | Stage: " + LeadQualificationResult.stage + "\n\nNot yet qualified for deal creation.\n\nReasoning: " + LeadQualificationResult.reasoning + "\n\nNext Action: " + LeadQualificationResult.nextAction,
        ownerId SDRConfig.hubspotOwnerId
    }}
    shouldCreateDeal --> "NoDeal" {updateThreadState {
        threadId EmailData.threadId,
        companyId company.id,
        companyName CompanyResolutionResult.companyName,
        leadStage LeadQualificationResult.stage,
        incrementEmailCount true
    }}
}

@public agent sdrManager {
    llm "gpt_llm",
    role "You are an intelligent SDR agent that manages the complete sales development workflow: filtering emails, extracting contacts, resolving companies, qualifying leads, and orchestrating HubSpot CRM updates.",
    instruction "Process the email through the complete SDR pipeline:
    
1. Filter for relevance
2. Extract all external contacts
3. Resolve the company/account
4. Qualify the lead (company-level)
5. Classify deal stage (if applicable)
6. Update HubSpot CRM (companies, contacts, deals, meetings, notes)
7. Maintain conversation state (ThreadState)

The email data is provided in the message. Execute the flow systematically."
}

workflow @after create:gmail/Email {
    // Fetch SDR configuration
    {SDRConfig? {}} @as [config];
    
    // Prepare email data context
    "Email thread_id: " + gmail/Email.thread_id +
    " | Sender: " + gmail/Email.sender +
    " | Recipients: " + gmail/Email.recipients +
    " | Subject: " + gmail/Email.subject +
    " | Body: " + gmail/Email.body +
    " | Date: " + gmail/Email.date +
    " | Gmail Owner: " + config.gmailOwnerEmail +
    " | HubSpot Owner ID: " + config.hubspotOwnerId @as emailContext;
    
    console.log("🔔 New email received: " + gmail/Email.subject);
    console.log("📧 Thread ID: " + gmail/Email.thread_id);
    
    // Invoke the main SDR agent
    {sdrManager {message emailContext}}
}
