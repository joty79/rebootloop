<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows_10/11-0078D4?style=for-the-badge&logo=windows11&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Language-PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/Workflow-AutoLogon_%2B_Task_Scheduler-0F766E?style=for-the-badge" alt="Workflow">
</p>

<h1 align="center">🔁 Reboot Loop</h1>

<p align="center">
  <b>Μικρό setup για αυτόματο reboot test μετά από sign-in.</b><br>
  <sub>PowerShell setup → AutoLogon → Task Scheduler → reboot loop</sub>
</p>

## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| 🎛️ | **[reboot-loop.ps1](#-reboot-loopps1)** | Το μοναδικό script για start, reboot loop, timers, status, stop και cleanup. |

## 🎛️ reboot-loop.ps1

> Το κύριο all-in-one manager για χρήση σε client PC.

### Το πρόβλημα

- Σε field use είναι εύκολο να μπερδευτούν πολλά διαφορετικά script names.
- Το ίδιο tool χρειάζεται setup, προσωρινό stop και πλήρες remove.
- Για γρήγορο BSOD testing, ένα entrypoint είναι πιο πρακτικό.

### Η λύση

Το script συγκεντρώνει όλες τις ενέργειες σε ένα σημείο και υποστηρίζει είτε parameters είτε μικρό interactive menu.

```text
reboot-loop.ps1
  -> Start BSOD boot test
  -> Loop
  -> Change reboot timers
  -> Status
  -> Stop reboot test
  -> Stop and clean up
  -> Stop, clean up, and delete folder
```

Αυτό είναι πλέον το μόνο script που χρειάζεται για το εργαλείο.

Στο πρώτο `Setup`, αν χρειάζεται admin rights, κάνει μόνο του relaunch elevated. Από εκεί και πέρα τα επόμενα boots δεν χρειάζονται νέο input.
Για local account χωρίς password, στο prompt του password απλώς πατάς `Enter`.
Αν το ανοίξεις χωρίς parameters, κάνει elevation πριν εμφανίσει το menu ώστε όλο το interactive flow να γίνει στο elevated window από την αρχή.
Στο τέλος του `Setup` σε ρωτάει αν θέλεις να ξεκινήσει το test αμέσως ή αργότερα.

### Usage

**Από terminal:**
```powershell
# Interactive menu
.\reboot-loop.ps1

# Full setup
.\reboot-loop.ps1 -Action Setup

# Change timers only
.\reboot-loop.ps1 -Action Configure -SignInGraceDelaySeconds 8 -StopTimeoutSeconds 90 -ShutdownDelaySeconds 10

# Show status
.\reboot-loop.ps1 -Action Status

# Disable loop
.\reboot-loop.ps1 -Action Disable

# Remove loop
.\reboot-loop.ps1 -Action Remove

# Remove loop and delete files
.\reboot-loop.ps1 -Action Remove -DeleteFiles
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Action` | `string` | interactive menu | Δέχεται `Setup`, `Configure`, `Status`, `Disable`, `Remove`. |
| `-SignInGraceDelaySeconds` | `int` | current config | Μικρή καθυστέρηση μετά το sign-in πριν αρχίσει το countdown του reboot. |
| `-StopTimeoutSeconds` | `int` | current config | Ο χρόνος που περιμένει το παράθυρο πριν κάνει reboot μόνο του. |
| `-ShutdownDelaySeconds` | `int` | current config | Ο χρόνος του `shutdown /r /t ...` αφού επιλεγεί reboot. |
| `-DeleteFiles` | `switch` | `False` | Χρήσιμο μόνο με `-Action Remove`. Θέλει elevated PowerShell. |
| `-TaskName` | `string` | `RebootLoop` | Το όνομα του `Scheduled Task`. |

💡 Για local account χωρίς password:
στο `Setup` όταν ζητήσει password, άφησέ το κενό και πάτα `Enter`.

## 🔁 Loop Runtime
> Το ίδιο το `reboot-loop.ps1` τρέχει και το reboot loop όταν το καλεί το `Scheduled Task`.

### Το loop flow

```text
Logon
  -> Scheduled Task
    -> reboot-loop.ps1 -Action Loop
      -> live countdown on screen
      -> Enter = reboot now
      -> Esc = cancel current reboot and open menu
      -> timeout -> shutdown /r
```

Αυτό κρατάει όλο το logic σε ένα μόνο file.

## 📦 Installation

### Quick Setup
```powershell
# 1. Άνοιξε elevated PowerShell στο folder
Set-Location "D:\Users\joty79\scripts\reboot"

# 2. Τρέξε το all-in-one manager
.\reboot-loop.ps1
```

### Menu

Όταν ανοίξει το menu, θα δεις:

```text
1. Start BSOD boot test
2. Show current status
3. Stop reboot test
4. Stop and clean up
```

Μετά το `Start BSOD boot test`, το script:
- ζητάει timers
- ζητάει και μικρό sign-in delay πριν αρχίσει το countdown
- ζητάει password ή blank `Enter` για local no-password account
- κάνει setup το `AutoLogon` και το `Scheduled Task`
- στο τέλος ζητάει `Enter` για άμεσο reboot ή `Esc` για cancel προς το παρόν

Μετά το πρώτο reboot/sign-in θα δεις ξανά το script window.
Αυτό είναι αναμενόμενο, γιατί το loop είναι interactive και πρέπει να μπορείς να πατήσεις `Esc` για να ακυρώσεις το τρέχον reboot και να μπεις στο menu.
Το loop κάνει επίσης μικρό sign-in grace delay, χτυπάει `beep`, και προσπαθεί να τραβήξει focus/attention πριν αρχίσει το countdown.

Μετά το `Stop and clean up`, το tool σε ρωτάει αν θέλεις να σβηστεί και το folder.
Αν πατήσεις `Y`, προγραμματίζει και τη διαγραφή του.
Αν όμως το folder φαίνεται να είναι git repo/worktree, η αυτόματη διαγραφή μπλοκάρεται για προστασία.

💡 Αν ποτέ χρειαστείς αλλαγή timers χωρίς να ξανατρέξεις όλο το setup, το advanced CLI action παραμένει διαθέσιμο:
`.\reboot-loop.ps1 -Action Configure -SignInGraceDelaySeconds 8 -StopTimeoutSeconds 30 -ShutdownDelaySeconds 5`

### Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 / 11 |
| **Runtime** | PowerShell 7 preferred, fallback to Windows PowerShell 5.1 |
| **Permissions** | Elevated PowerShell για setup/disable του `AutoLogon` |

## 📁 Project Structure

```text
reboot/
├── reboot-loop.ps1           # Κύριο all-in-one manager
├── reboot-loop.config.json   # Config για stop window και shutdown delay
├── PROJECT_RULES.md          # Μακροχρόνιες αποφάσεις/guardrails του repo
├── CHANGELOG.md              # Καταγραφή αλλαγών
└── README.md                 # Οδηγίες χρήσης
```

## 🧠 Technical Notes

<details>
<summary><b>Γιατί όχι shell:startup;</b></summary>

Το `Startup` folder εξαρτάται από το shell startup και είναι πιο fragile όταν θέλεις επαναλαμβανόμενα reboot tests. Το `Task Scheduler` είναι πιο προβλέψιμο και καθαρίζεται ευκολότερα.

</details>

<details>
<summary><b>Τι κάνει το reboot.disabled;</b></summary>

Είναι ένα απλό local flag file. Αν υπάρχει, το `reboot-loop.ps1 -Action Loop` κάνει exit χωρίς reboot ώστε να έχεις χρόνο να τρέξεις `Disable` ή `Remove`.

</details>

<details>
<summary><b>Τι ρίσκο έχει το AutoLogon;</b></summary>

Το password αποθηκεύεται για να μπορεί να γίνει αυτόματο sign-in. Αυτό είναι χρήσιμο μόνο για test machine ή προσωρινό workflow και πρέπει να απενεργοποιείται όταν τελειώσει το test.
Για local account χωρίς password, το tool μπορεί να ρυθμίσει `AutoLogon` και με empty password.

</details>

<details>
<summary><b>Πού αλλάζω τον timer χωρίς να πειράζω αρχεία;</b></summary>

Χρησιμοποίησε το ίδιο `reboot-loop.ps1` με το advanced CLI `-Action Configure`. Το script γράφει το `reboot-loop.config.json` και το ίδιο το loop το διαβάζει στο επόμενο run.

</details>

---

<p align="center">
  <sub>Built for Windows reboot testing · AutoLogon aware · Easy stop path</sub>
</p>
