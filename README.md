# Procurement Portal — Multi-Currency Raw Material Costing

An SAP BTP ABAP Environment (Steampunk) application that lets procurement users cost imported raw materials in a preferred currency by pulling **live exchange rates** from an external API and applying them to purchase line items in real time.

Built entirely with **RAP (RESTful ABAP Programming Model)** on managed scenario with draft, and written strictly to **Clean ABAP** and **ABAP Cloud** conventions — no classic ABAP syntax used in the stack.

---

## 🚀 Live Demo
You can view the deployment live here: [Explore the App](https://a396c05d-a792-494b-a9f2-5b3f674def78.abap-web.ap21.hana.ondemand.com/sap/bc/ui5_ui5/sap/zscmproc)

---

## Table of Contents

- [What This Project Does](#what-this-project-does)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Application Safely](#running-the-application-safely)
- [Key Features](#key-features)
- [Unit Testing](#unit-testing)
- [Code Quality & ATC Compliance](#code-quality--atc-compliance)
- [Coding Standards](#coding-standards)
- [Project Structure](#project-structure)

---

## What This Project Does

The Procurement Portal manages purchase requests for imported raw materials and automatically recalculates their cost in a company's preferred currency by fetching current foreign-exchange rates from the [Open Exchange Rates](https://open.er-api.com) API.

At a glance, it:

- Exposes a managed RAP business object for procurement documents, with full draft support.
- Provides a `RefreshRate` action that calls out to an external HTTP destination, parses the JSON response, and updates the exchange rate and cost fields on the document.
- Enforces field control so that once a procurement item is **Approved**, its cost-relevant fields are locked from further edits.
- Assigns document numbers via an SAP-managed number range object.

---

## Architecture

| Layer | Artifact | Purpose |
|---|---|---|
| Data Model | CDS `define view entity` (root + child) | Interface and root/child projection views over the transparent tables |
| Behavior | Managed RAP behavior definition + behavior class | Draft handling, validations, determinations, actions |
| Service Binding | OData V4 UI service binding | Exposes the business object to Fiori Elements / SAPUI5 |
| Integration | `cl_http_destination_provider` | Outbound call to the exchange rate API via a BTP destination |
| Number Range | Number range object (RAP-integrated) | Generates procurement document IDs |
| Test Doubles | CDS test doubles + local test class | Isolated, side-effect-free behavior testing |

All artifacts use **released C1 APIs only** and are implemented against the managed RAP BO pattern with UUID technical keys.

---

## Prerequisites

Before installing, make sure you have:

- Access to an **SAP BTP ABAP Environment (Steampunk)** tenant.
- **ADT (ABAP Development Tools) for Eclipse**, latest version.
- A **communication arrangement** and **destination** configured for outbound calls to `open.er-api.com` (or your chosen exchange rate provider).
- Authorization to create packages, transport requests, and number range objects in your system.
- A transport-enabled package assigned to your development system.

---

## Installation

1. **Open ADT** and connect to your BTP ABAP Environment system.
2. **Create or select a package** for the project (must be assigned to a software component that allows Cloud development).
3. **Import the repository objects** in the following order to satisfy dependencies:
   1. Domains / data elements (currency and amount fields)
   2. Database tables (procurement header and item)
   3. Number range object
   4. CDS interface views → CDS projection views
   5. Behavior definition and behavior class (root + child)
   6. Service definition and service binding
   7. Demo data provider class
   8. Local test class (see [Unit Testing](#unit-testing))
4. **Activate all objects** as a single activation batch to avoid intermediate syntax errors from cross-dependencies.
5. **Assign the OData service binding** to a Fiori Elements app (List Report / Object Page) if a UI is required, or consume it directly via the service binding preview in ADT.

---

## Configuration

The `RefreshRate` action requires an HTTP destination to reach the exchange rate API:

1. In the BTP cockpit, create a **destination** (e.g. `EXCHANGE_RATE_API`) pointing to `https://open.er-api.com`.
2. Create a matching **communication system** and **communication arrangement** in the ABAP environment, referencing the same destination name.
3. The behavior class resolves the destination at runtime via:

   ```abap
   cl_http_destination_provider=>create_by_name( 'EXCHANGE_RATE_API' )
   ```

4. No API key is required for the default Open Exchange Rates endpoint used here; if you switch providers, store any required credentials in the destination configuration — **never hardcode credentials in ABAP code**.

---

## Running the Application Safely

- **Always test in a development/sandbox client first.** The `RefreshRate` action performs a live outbound HTTP call — do not point it at production destinations until the destination and error handling have been validated.
- **Use draft mode** when creating or editing procurement documents. Changes are only persisted to the database on `Save`, so in-progress edits (including a bad exchange rate fetch) can be discarded safely.
- **Respect field control.** Once a procurement item's status is `Approved`, cost fields become read-only at the OData/Fiori layer. Do not attempt to bypass this by calling `MODIFY ENTITIES ... IN LOCAL MODE` from custom code — that mode is for test isolation only and skips all field-control and authorization checks.
- **Monitor the outbound call.** If the exchange rate API is unreachable or returns malformed JSON, the action should fail gracefully and populate the RAP `failed` and `reported` tables rather than raising an uncaught exception. Check the trace in ADT's ABAP Debugger or the application log if a refresh fails silently.
- **Run the unit test suite before every transport release** (see below) to catch regressions in the JSON parsing and currency conversion logic before they reach QA.

---

## Key Features

- Live exchange rate refresh via external API integration
- Multi-currency cost calculation for imported raw materials
- Draft-enabled managed RAP business object
- Number-range-based document ID assignment
- Field control locking approved procurement items
- Fully isolated unit tests using CDS test doubles

---

## Unit Testing

Unit tests for the procurement behavior logic live in the **local test class** tab within the behavior class's test include (`<behavior_class>.clas.testclasses.abap`), rather than a separate global test class. Keeping the tests local to the behavior class keeps them tightly scoped to the business object they exercise and avoids exposing test-only dependencies outside the class.

The local test class covers:

- **CDS test doubles** for the procurement root and child entities, so tests run against in-memory fixtures instead of the database.
- **`RefreshRate` action tests**, asserting the exchange rate and cost fields are updated correctly after a simulated API response.
- **JSON parsing tests**, including a regression test for the fixed `CX_SY_RANGE_OUT_OF_BOUNDS` issue — verifying that dynamically computed substring lengths correctly handle exchange rate payloads of varying size.
- **Field control tests** (`feature_ctrl_approved_locks_fields`), which invoke the controlled action **without** `IN LOCAL MODE` and assert on the populated `failed` table, since `IN LOCAL MODE` intentionally bypasses field-control checks and would produce a false pass.
- **Number range assignment tests**, confirming a unique document ID is generated on creation.

To run the tests in ADT:

1. Right-click the behavior class in the Project Explorer.
2. Select **Run As → ABAP Unit Test**.
3. Review results in the ABAP Unit view; all test doubles run in isolation and make no changes to persistent data.

---

## Code Quality & ATC Compliance
 
The full project has been run through the **ABAP Test Cockpit (ATC)** using the Clean ABAP / Cloud-readiness check variant to validate that every artifact is release-eligible for the ABAP Cloud programming model.
 
Key remediation carried out as a result of the ATC findings:
 
- **Hardcoded strings eliminated.** All literal messages and labels previously embedded directly in ABAP statements (e.g. exception text, log messages, action feedback) have been replaced with:
  - **Text symbols** for UI-facing and log-facing static text, and
  - **Message classes** for structured, translatable messages raised from validations, determinations, and the `RefreshRate` action.
- **No magic literals remain** in conditionals or comparisons — all thresholds and fixed values are now named constants, per Clean ABAP guidance.
- **Translatability.** Since all user-facing text now resolves through text symbols and message classes rather than inline literals, the application is ready for translation without further code changes.
- **Cloud-readiness confirmed.** ATC reported no remaining findings against released, non-Cloud-compatible statements — the project uses exclusively C1-released APIs.
To re-run the check yourself in ADT:
 
1. Right-click the package (`ZSCM_PROCUREMENT`) in the Project Explorer.
2. Select **ATC → Run as → ABAP Test Cockpit With...**
3. Choose the Clean ABAP / Cloud-readiness check variant assigned to your system.
4. Review findings in the ATC Problems view before releasing any transport.
> **Tip:** Run ATC as part of your pre-transport checklist alongside the ABAP Unit test suite — a clean ATC run and a green unit test run are both required before a transport is released.

---

## Coding Standards

This project strictly enforces:

**Clean ABAP**
- Inline declarations (`DATA(...)`, `FIELD-SYMBOL(...)`)
- No magic literals — named constants only
- `RETURNING` parameters preferred over `EXPORTING`
- Class-based exceptions only
- `NEW` instead of `CREATE OBJECT`

**ABAP Cloud / RAP**
- Released C1 APIs only
- No classic ABAP syntax (e.g. `GET TIME STAMP FIELD`, classic `SELECT` without host variable escaping, `CREATE OBJECT`)
- Managed RAP with draft
- UUID technical keys
- `define view entity` only — no legacy `define view` syntax
- CDS test doubles used exclusively in behavior class unit tests

---

## Project Structure

```
procurement-portal/
├── ddic/
│   ├── domains and data elements
│   └── database tables (header, item)
├── numberrange/
│   └── number range object
├── cds/
│   ├── base views (R_*)
│   └── projection views (C_*)
├── behavior/
│   ├── behavior definition
│   ├── behavior class
│   └── testclasses.abap   ← local unit test class
├── service/
    ├── service definition
    └── service binding

```
