# Source folders (read live via SharePoint / OneDrive MCP tools)

Both folders are shared with the whole tenant, so the teammate identity can read them.

## Guidelines folder
https://m365cpi15651853.sharepoint.com/:f:/s/cpfb-demo/IgBqjQMV8IcZQ58I9RnUZv7GAd3LzJaps-sZBumBDWnHh64?e=mYrt04

Contains the governing documents for team-building events:

- **AOR Guide** — when an AOR is required, the step-by-step process, quote rules by event
  value (1 quote / 3 quotes / tender), approval routing and processing times, and common
  mistakes to avoid.
- **AOR Template** — the form to fill in (event details, purpose, headcount, budget
  breakdown, vendor details, inclusivity, compliance declaration) and the AOR reference
  format `AOR-[YEAR]-[DEPT]-XXX`.
- **Team Building Guidelines** — per-pax spending caps, inclusivity requirements (halal,
  accessibility), restricted venues, advance-notice rules.
- **Approved Vendor List** — approved vendors by category (team building / catering /
  venue) with pax ranges, per-pax prices, halal flags, and contacts.

> Read the specific file you need and quote the exact figure or rule. Do not cache or
> assume values — they can change in the source.

## AORs folder
https://m365cpi15651853.sharepoint.com/:f:/s/cpfb-demo/IgB2sTib7ComSZxwUjsn2JlzAd9nw_11jFNBzRoM88iQPwI?e=LhgqJU

Where AOR documents are created and tracked. Use it to:

- Check for an existing work-in-progress AOR before creating a new one (avoid duplicates).
- Create the new AOR document (titled with its AOR ID) from the template.
- Record vendor quotes, decisions, and compliance notes as the case progresses.

## Other context sources (beyond the two folders)

The case lives across more than SharePoint. Use these MCP tool servers to gather and
correlate context, always keyed by the AOR ID and the event name:

- **`mcp_TeamsServer`** — read this chat and other Teams chats/channels about the event;
  rename the event's group chat to include the AOR ID.
- **`mcp_MailTools`** — find and send email (vendor quote requests/replies, approvals);
  keep the AOR ID in the subject.
- **`mcp_CalendarTools`** — confirm event date, attendees, and holds.
- **`mcp_M365Copilot`** — broad retrieval across the organiser's accessible content when
  you are unsure where something lives.

> Do not rely on short-lived chat memory. After any reset, re-gather context from these
> sources using the AOR ID.
