# Simulate a group discussion
- Add the users to the group - e.g. johandy@, aaron@, sithu@

## 1. Seed Conversation data
```
Aaron Yue — Mon 8 Jun, 9:14 AM Morning all! HOD gave the green light for our annual team building 🎉 She said keep it around S$3k for now, nothing fancy. We've got the floor to pick something.
Johandy Tantra — Mon 8 Jun, 9:21 AM Nice. Headcount is 40 including the two new hires. Can we please NOT do another sports day 😅 my knees still haven't recovered from last year.
Terence Lim — Mon 8 Jun, 9:26 AM Seconded on no strenuous outdoor stuff. FYI Johandy and I are both still on physio after the half-marathon, so anything high-impact is out for us.
Aaron Yue — Mon 8 Jun, 9:40 AM What about something creative/indoor? Art jamming or a cooking class could be fun and low-key. People have been stressed after the Q2 push.
Terence Lim — Mon 8 Jun, 9:52 AM I like the cooking idea! But please make sure it's halal-certified — there are 6 of us who need halal, and one vegetarian. Last year's caterer messed this up.
Sithu Kyaw — Mon 8 Jun, 10:03 AM Noted Terence. So far: indoor, creative, halal-friendly, ~S$3k, no high-impact activities. 👍
------------------------------------
Johandy Tantra — Tue 9 Jun, 2:11 PM One scheduling thing — can we do a weekday afternoon? A few people have caregiving duties in the evenings, so weekends/nights are hard. Half-day during work hours would be ideal.
Aaron Yue — Tue 9 Jun, 2:18 PM +1 weekday afternoon. Also let's give everyone enough lead time — last year the invite came 5 days before and half the team had clashes.
Terence Lim — Tue 9 Jun, 2:35 PM Targeting sometime in late July then? That gives us a few weeks.
Sithu Kyaw — Tue 9 Jun, 2:40 PM Late July works. I'll float a tentative date this week so people can block calendars.
------------------------------------
Sithu Kyaw — Wed 10 Jun, 11:05 AM Catching up on this thread 👋 Summary of where we are:
Budget ~S$3k, 40 pax
Indoor + creative, halal-certified food, no high-impact activities
Weekday afternoon, late July, need 2+ weeks notice Did we land on cooking class vs art jamming? And do we know if we need an AOR for this?
Terence Lim — Wed 10 Jun, 11:12 AM I'd vote cooking class if the budget allows — feels more bonding. Art jamming as backup.
Johandy Tantra — Wed 10 Jun, 11:20 AM On the AOR — not sure. It's under S$6k so maybe not? But we'd be using an external vendor, so someone should double-check the rules.
Aaron Yue — Wed 10 Jun, 11:31 AM Also we haven't picked a vendor yet or gotten a quote. Can someone take that?
Johandy Tantra — Wed 10 Jun, 11:45 AM Sithu, didn't you say you were testing an AI teammate that could help plan this end-to-end? Might be a good guinea pig 😄
Sithu Kyaw — Wed 10 Jun, 11:47 AM Ha, funny you ask — yes. Let me run it through and report back. 🤖
```

## 2. Start
> {agent_name} I've shared our planning chat with you. Read the thread and tell me what's already been decided and what's still open for our team building according to the guidelines for teambuilding activities
 
## 3. Ask recommendation for vendors
> {agent_name} recommend 2–3 vendor options that fit all of that and stay compliant with our team building policy. Use only approved vendors.

## 4. Pick option and draft AOR
> {agent_name} ok lets go with FoodCraft. Do we need an AOR? If yes can you help draft it?

Check that the AOR document is created in the sharepoint folder, and go thru with confirmation from the agent if required

## 4b. (if not already) update the teams chat name
> {agent_name} update the teams chat name to the ID please so it's easier to search and follow

## 5. Request quote
This demo tenant is restricted to sending emails outside so for this demo we can just send it to our own email in the tenant.
> {agent_name} ok help me draft the email to request for quotation. Send it to {your_user@M365CPI15651853.onmicrosoft.com}

## 6. Reply email with a fake quotation
Right now you should have received an email from the agent - login to outlook and reply below and check that the subject has something like `Quotation Request for ...` as the subject and not just a `Draft`

```
Dear CPF Board Team,

Thank you for considering FoodCraft Experiences for your upcoming team-building
activity. We are pleased to provide our quotation below for your AOR submission.

------------------------------------------------------------
QUOTATION (GST-inclusive)
------------------------------------------------------------
Package: Signature Team-Building Cooking Class (half-day, ~3.5 hours)
Rate: S$85.00 per pax (GST-inclusive)
Estimated total for 40 pax: S$3,400.00 (GST-inclusive)

Cost breakdown (per pax, GST-inclusive):
- Hands-on guided cooking session & facilitation .... S$60.00
- Ingredients & cooking materials ................... S$15.00
- Plated meal of dishes prepared (lunch included) ... S$10.00
Food/meal: INCLUDED — participants enjoy the dishes they prepare as a
full sit-down meal, plus free-flow coffee/tea and water.

------------------------------------------------------------
DIETARY & HALAL
------------------------------------------------------------
- Our kitchen and menu are Halal-certified (MUIS).
- Vegetarian menu available at no additional charge.
- We accommodate common dietary restrictions and allergies (e.g. nut-free,
  seafood-free, no pork/lard) with advance notice of at least 5 working days.

------------------------------------------------------------
VENUE & ACCESSIBILITY
------------------------------------------------------------
- Venue: FoodCraft Culinary Studio, 71 Ayer Rajah Crescent, Singapore 139951
- Fully wheelchair-accessible: step-free entrance, lift access, accessible
  washrooms, and adjustable-height cooking stations available on request.

------------------------------------------------------------
AVAILABLE SLOTS (Late July 2026, weekday afternoons)
------------------------------------------------------------
- Tue, 21 Jul 2026 — 1:30 PM to 5:00 PM
- Wed, 22 Jul 2026 — 1:30 PM to 5:00 PM
- Thu, 30 Jul 2026 — 1:30 PM to 5:00 PM
(Slots are subject to availability at time of confirmation.)

------------------------------------------------------------
GROUP SIZE
------------------------------------------------------------
- Minimum: 15 pax
- Maximum: 50 pax per session
(Your group of 40 pax is comfortably accommodated in a single session.)

------------------------------------------------------------
TERMS & CONDITIONS
------------------------------------------------------------
- Quotation validity: 30 days from the date of this email.
- A 50% deposit confirms the booking; balance due 7 days before the event.
- Final headcount and dietary requirements to be confirmed at least 5 working
  days prior to the event.
- Rescheduling permitted up to 7 working days before the event at no charge.
- Pricing is held within our CPF approved-vendor band (S$70–S$90 per pax).

We would be delighted to host your team. Please let us know your preferred slot
and we will reserve it pending your AOR approval.

Warm regards,
FoodCraft Experiences
```

Wait for a while and there should be
- A notification from the agent triggered via teams to summarize the quote (Sometimes this might trigger DLP in the tenant and so the notification body might be missing)
- Check the document and it should put a comment in the document with a summary of the incoming quotation.

## 7. Send a placeholder calendar invite
> {agent_name} thanks for the update. Can you send a placeholder invite for 30 Jul 2026 130 to 5pm?