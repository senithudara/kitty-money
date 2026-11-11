<p align="center">
  <img src="Design/readme/icon.png" width="128" alt="Kitty Money icon">
</p>

<h1 align="center">Kitty Money</h1>

<p align="center">
  A personal finance app for iPhone that tracks Sri Lankan bank accounts automatically from SMS.
</p>

---

## Features

- **Accounts dashboard**: balances for every bank account, with a selectable total.
- **Automatic SMS tracking**: bank SMS (BOC, Commercial Bank, People's Bank) are read through a Shortcuts automation, recorded as transactions and synced to the bank's balance.
- **Smart categories**: merchants are categorized from keywords, Apple Maps place types or on-device Apple Intelligence, and the app learns from your corrections.
- **Budgets**: monthly limits per category or overall, with what's left to spend.
- **Subscriptions**: renewal reminders, LKR or foreign currency with daily exchange-rate conversion, and auto-recorded renewals.
- **Installments**: Koko and Mintpay plans with schedules, due-date reminders and payment matching.
- **Savings and investments**: savings goals with monthly deposits, plus CSE holdings with price refresh.
- **Widgets**: home and lock screen widgets showing budget left, balance and upcoming payments.
- **Privacy**: all data stays on the device, with optional Face ID lock, CSV export and full JSON backup and restore.

## Tech stack

- SwiftUI, SwiftData and Swift Charts
- App Intents (Shortcuts), WidgetKit and UserNotifications
- MapKit and Foundation Models for merchant categorization
- No backend, no accounts, no paid services

## Requirements

- Xcode 16 or later
- iOS 17 or later (Apple Intelligence features need iOS 26 on a supported iPhone)
- A free Apple ID is enough to run it on your own iPhone (apps signed this way expire after 7 days and need re-running from Xcode)

## Getting started

1. Open `KittyMoney.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, choose your team for both the **KittyMoney** and **KittyMoneyWidgetExtension** targets. If needed, change the bundle identifiers and the App Group (`group.com.senithudara.kittymoney.shared`) to your own.
3. Select your iPhone and press **⌘R**.
4. In the app, open **Settings → Set up and test SMS tracking** and follow the steps to create the Shortcuts automations.

## Project structure

```
KittyMoney/
  App/            App entry point and tab bar
  Models/         SwiftData models
  Features/       Screens (Home, Budgets, Payments, Wealth, Settings…)
  Services/       SMS parsing, reminders, exchange rates, logos, backup, widget sync
  Components/     Shared UI pieces
  Theme/          Colors and formatting
KittyMoneyWidget/ Home and lock screen widgets
Design/           App icon sources
```
