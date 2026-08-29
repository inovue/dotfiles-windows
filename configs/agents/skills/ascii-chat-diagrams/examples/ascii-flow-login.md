# ASCII User Flow Example (W = 120 ch)

Hand-drawn flow for chat alignment. No Nerd Font. Generate shell with:

`python $ascii frame --mode flow --title "Login Flow" --file flow-steps.txt`

```text
┌─ [ Login Flow ] ─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Flow: Signup (ASCII)                                                                                                 │
│  [1 Form]  --->  [ Submit ]  --->  [2 OTP]  --->  [3 Home]                                                           │
│  | email/password |              | 6-digit   |                                                                       │
│  fail ---> { ERR: retry }                                                                                            │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
