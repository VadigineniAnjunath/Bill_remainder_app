# Bill Radar

Personal money tracker: salary, subscriptions, EMIs, chitti, insurance savings (N26 Spaces), bills and debts.

## Current version
`index.html` is the web version (runs as a claude.ai artifact). It stores data in the account storage and keeps a copy in the browser.

Features:
- Subscriptions, EMIs (balance owed, optional end date), chitti (months left), insurance, bills
- Pays-from account (Commerzbank / N26 / Cash) and monthly transfer suggestions
- Set-aside savings for quarterly/yearly payments with monthly reminders and history
- Debts (I owe / owed to me) with partial payments
- 12-month summary, freed-money reminder when an EMI or chitti ends
- Edit for every item

## Next
Flutter Android app with local storage and notifications. Data moves over by importing the JSON backup.

## Data
Never commit personal data. Backups (`*backup*.json`) are ignored by Git.
