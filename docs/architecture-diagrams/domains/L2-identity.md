# OpenPaw Architecture Diagrams — L2 Identity (Auth / Subscription / Entitlement / Quota) (ASCII)

> Scope: domain-level design of `domains/identity/`.
> Focus: identity/auth components, subscription and entitlement ownership, quota checks, and event-driven integration with rewards settlement.

---

## Diagram A — Identity Domain Component Model (Auth + Subscription + Entitlement + Quota)

```text
         OpenPaw L2 — Identity (Component Model: Auth / Subscription / Entitlement / Quota)

  Purpose:
    Own user identity, subscription state, device linkage, and entitlement/quota policies.
    Provide authorization context to workflows without becoming the source of points facts.


  External Interfaces
  -------------------

   +---------------------+     +----------------------+     +----------------------+
   | API Gateway / App   |     | Telegram / Web login |     | Payment Webhook      |
   +---------------------+     +----------------------+     +----------------------+
              \                         |                          /
               \                        |                         /
                \                       |                        /
                 v                      v                       v
       +------------------------------------------------------------------+
       | Identity Application Facade / Service Layer                      |
       |------------------------------------------------------------------|
       | - register_user()                                                |
       | - authenticate() / issue session/token                           |
       | - activate_subscription()                                        |
       | - link_device()                                                  |
       | - check_quota()/consume_quota() (entitlement-based, not points) |
       +------------------------------------------------------------------+
                 |                 |                    |               |
                 v                 v                    v               v

   +----------------------+  +----------------------+  +----------------------+  +----------------------+
   | Auth Module          |  | Subscription Module  |  | Entitlement Module  |  | Device Link Module   |
   |----------------------|  |----------------------|  |----------------------|  |----------------------|
   | credentials/session  |  | plan/tier lifecycle  |  | feature flags by tier|  | Pi / device binding  |
   | token claims         |  | renewal/expiry state |  | quota rules          |  | local-only mode flag |
   | authn/authz helpers  |  | webhook validation   |  | request eligibility  |  | trust relationship   |
   +----------------------+  +----------------------+  +----------------------+  +----------------------+
                 \                 \                    /               /
                  \                 \                  /               /
                   +--------------------------------------------------+
                   | Identity Domain Service / Invariants             |
                   |--------------------------------------------------|
                   | - user uniqueness                                |
                   | - tier/plan consistency                          |
                   | - entitlement validity windows                   |
                   | - quota non-negative (identity quota only)       |
                   | - device ownership and link policy               |
                   +--------------------------------------------------+
                                      |
                                      | DB transaction + outbox
                                      v
   +----------------------------------------------------------------------------------+
   | Identity Storage                                                                  |
   |----------------------------------------------------------------------------------|
   | users                                                                             |
   | subscriptions                                                                     |
   | entitlements                                                                      |
   | quota_counters / quota_usage (entitlement-based quotas)                           |
   | linked_devices                                                                    |
   | sessions / auth_tokens (if persisted)                                             |
   | outbox (identity.* events)                                                        |
   +----------------------------------------------------------------------------------+


  Key identity events (published)
  -------------------------------
   - identity.UserRegistered
   - identity.SubscriptionActivated
   - identity.DeviceLinked

  Boundary rule:
   identity manages entitlement/quota access control;
   rewards_ledger manages monetary/points facts (do NOT duplicate points balance here).
```

---

## Diagram B — Subscription / Entitlement / Quota Event Flow (and Reward Trigger Boundary)

```text
      OpenPaw L2 — Identity (Subscription + Entitlement + Quota Flow)

  1) Registration / Auth Flow (simplified)
  ----------------------------------------

   User registers / logs in
      |
      v
   +------------------------------+
   | identity.register/auth       |
   +------------------------------+
      |
      +--> create / load User
      +--> issue session / token claims
      +--> emit identity.UserRegistered (first-time only)
      |
      v
   [API gateway / workflows receive user_id, tenant_id, tier context]


  2) Subscription Activation Flow (critical boundary)
  ---------------------------------------------------

   Payment Provider webhook / billing event
      |
      v
   +------------------------------+
   | identity.activate_subscription|
   | validate plan + period       |
   +------------------------------+
      |
      +--> update Subscription state (tier, expires_at)
      +--> update Entitlement set (features, limits)
      +--> refresh quota allowance (identity quota counters)
      +--> emit identity.SubscriptionActivated
      |
      v
   +----------------------------------------------+
   | RewardSettlementWorkflow (separate workflow)  |
   | consumes SubscriptionActivated                |
   +----------------------------------------------+
      |
      v
   rewards_ledger.PointsEarned (subscription_grant)

   Important:
   - identity.SubscriptionActivated is NOT the points fact
   - rewards_ledger.PointsEarned is the authoritative credit event


  3) Quota Check / Consume Flow (entitlement-based, not ledger-based)
  -------------------------------------------------------------------

   Incoming request (e.g. SubmitProblem)
      |
      v
   +------------------------------+
   | identity.check_quota()       |
   | inputs: user_id, tier, action|
   +------------------------------+
      |
      | evaluate against entitlements + quota counters
      v
   +------------------------------+
   | allowed?                     |
   +------------------------------+
      | no                               | yes
      v                                  v
   reject request /                reserve or consume quota unit
   OPENPAW_IDENTITY_QUOTA_EXCEEDED + update quota_usage counter
                                   + continue to workflow

   Notes:
   - quota can be request-count, daily limits, or tier feature flags
   - points charging (if any) is still separate in rewards_ledger


  4) Device Linking Flow (Pi local mode)
  --------------------------------------

   User links Raspberry Pi device
      |
      v
   +------------------------------+
   | identity.link_device()       |
   | device ownership checks      |
   | local_only_mode flag         |
   +------------------------------+
      |
      +--> persist linked_devices
      +--> emit identity.DeviceLinked


  5) Idempotency / Reliability Notes
  ----------------------------------

   Payment webhook replay:
    -> subscription activation idempotency key (provider_event_id or invoice_id)
    -> prevents duplicate entitlement refresh / duplicate event emission

   identity.* event delivery:
    -> outbox relay (publish)
    -> inbox dedup in consumers (reward_settlement, sync, analytics)
```

---

## Key Entities (conceptual)

- `User`
- `Subscription`
- `Entitlement`
- `QuotaCounter` / `QuotaUsage`
- `LinkedDevice`

---

## Service Operations (conceptual mapping)

- `register_user(...)`
- `authenticate(...)` / `issue_token(...)`
- `activate_subscription(...)`
- `check_quota(user_id, action, amount=1)`
- `consume_quota(user_id, action, amount=1)`
- `link_device(user_id, device_id, local_only_mode)`

---

## Implementation Notes (important)

- Keep `identity` and `rewards_ledger` responsibilities separate: entitlements/quota vs points facts.
- Prefer idempotent subscription activation keyed by billing provider event/invoice IDs.
- Quota counters may be mutable (domain-owned operational counters), unlike ledger entries.
- Include `subscription_tier` and entitlement claims in auth context for fast policy checks.
- Emit identity events via outbox to ensure downstream reward/sync consumers do not miss updates.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/context-packs/L1-domain-map.md`
- `docs/architecture-diagrams/domains/L2-rewards-ledger.md`
- `docs/architecture-diagrams/components/L2-event-bus-reliability.md`
- `docs/architecture-diagrams/components/L2-policy-engine.md`
- `contracts/events/v0.json`
- `contracts/commands/v0.json`
