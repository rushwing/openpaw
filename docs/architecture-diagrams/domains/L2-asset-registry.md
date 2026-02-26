# OpenPaw Architecture Diagrams — L2 Asset Registry (Entity + Lifecycle) (ASCII)

> Scope: domain-level design of `domains/asset_registry/`.
> Focus: canonical asset entities, version/provenance relationships, and publish/deprecate lifecycle rules.

---

## Diagram A — Entity / Ownership Model (Asset Registry as Source of Truth)

```text
               OpenPaw L2 — Asset Registry (Entity Model / Ownership)

  Purpose:
    Canonical registry for reusable problem-solving assets (HTML + video), with versioning and provenance.


   +-----------------------------------------------------------------------------------+
   | Problem                                                                           |
   |-----------------------------------------------------------------------------------|
   | problem_id (UUID)                                                                 |
   | problem_signature (UNIQUE dedup key)                                              |
   | normalized_text?                                                                  |
   | image_phash?                                                                      |
   | topic_tags[]                                                                      |
   | created_at                                                                        |
   |-----------------------------------------------------------------------------------|
   | Rule: same ProblemSignature => same canonical Problem                             |
   +-----------------------------------------------------------------------------------+
                          | 1
                          | owns versions for both asset types
                          | 1..*
                          v

   +-----------------------------------------------------------------------------------+
   | AssetVersion                                                                       |
   |-----------------------------------------------------------------------------------|
   | asset_version_id (UUID)                                                            |
   | problem_id (FK -> Problem)                                                         |
   | asset_type (solution_html | video)                                                 |
   | version_no (int, monotonic per problem + asset_type)                               |
   | status (draft | processing | published | deprecated | failed)                      |
   | content_status (ready | processing | failed) [especially useful for video]         |
   | storage_key (html file / mp4 / bundle path)                                        |
   | parent_asset_version_id? (for corrections / derivations)                           |
   | source_proposal_id? (CorrectionProposal / expert submission, if applicable)        |
   | created_at                                                                         |
   | published_at?                                                                      |
   | deprecated_at?                                                                     |
   +-----------------------------------------------------------------------------------+
          | 1
          | must have provenance
          | 1
          v

   +-----------------------------------------------------------------------------------+
   | ProvenanceRecord                                                                   |
   |-----------------------------------------------------------------------------------|
   | provenance_id (UUID)                                                               |
   | asset_version_id (FK -> AssetVersion, UNIQUE)                                      |
   | created_by_type (ai_generation | user_correction | expert_answer | system_migration)|
   | model_id?                                                                          |
   | skill_name?                                                                        |
   | prompt_version?                                                                    |
   | embedding_model? (model used to index into Qdrant; must match embedding_model_global)|
   | user_id? (human contributor)                                                       |
   | correction_proposal_id?                                                            |
   | workflow_run_id?                                                                   |
   | correlation_id?                                                                    |
   | created_at                                                                         |
   +-----------------------------------------------------------------------------------+


  Logical Views (same table, filtered by asset_type)
  --------------------------------------------------

   +---------------------------+           +---------------------------+
   | Solution Asset View       |           | Video Asset View          |
   | asset_type=solution_html  |           | asset_type=video          |
   | content_status usually    |           | content_status may be     |
   | ready immediately         |           | processing/ready/failed   |
   +---------------------------+           +---------------------------+


  Key Domain Invariants (enforced by service + DB constraints)
  ------------------------------------------------------------

   1) ProblemSignature uniqueness
      UNIQUE(problem_signature)

   2) No overwrite, only new versions
      new generation/correction/expert answer => INSERT new AssetVersion

   3) One published version at a time per (problem_id, asset_type)
      partial unique index on status='published'

   4) Every AssetVersion must have ProvenanceRecord
      transactional create(version + provenance)

   5) Assets are never deleted
      deprecated only (status transition)
```

---

## Diagram B — Version Lifecycle / Publish Flow (State + Domain Events)

```text
                    OpenPaw L2 — AssetVersion Lifecycle (Publish / Deprecate / Rollback)

  Creation Sources
  ----------------
   - AI generation (solve_workflow / video_workflow)
   - Accepted user correction
   - Accepted expert bounty answer
   - System migration


                                  +----------------------+
                                  |   processing         |
                                  | content_status=...   |
                                  +----------------------+
                                     | success / content ready
                                     | emit asset.AssetVersionCreated
                                     v
   +----------------------+      +----------------------+      +----------------------+
   | draft (optional)     |----->| ready (unpublished)   |----->| published           |
   | metadata staged      |      | content_status=ready  |      | visible to users    |
   +----------------------+      +----------------------+      +----------------------+
           |                               |   ^                          |
           | validation fail               |   | publish newer version    | deprecate
           v                               |   | (auto/manual)            | emit AssetDeprecated
   +----------------------+                |   |                          v
   | failed               |                |   |                 +----------------------+
   | content_status=failed|                |   +-----------------| deprecated          |
   +----------------------+                |     rollback/re-publish previous version   |
                                           |     emit AssetVersionPublished             |
                                           +--------------------------------------------+


  Publish Semantics (critical invariant)
  --------------------------------------

   Publish(version = V_new for problem P, type T):
     1) Find currently published version V_old for (P, T) [if any]
     2) Set V_old.status -> ready (or keep historical non-published state)
     3) Set V_new.status -> published
     4) Emit asset.AssetVersionPublished(previous_version_id=V_old?)

   NOTE:
   - "Rollback" is just re-publish an older version (no special restore primitive needed)
   - Deprecated versions are not deleted and remain auditable


  Event Emission Points (domain events)
  -------------------------------------

   Problem first seen:
     -> asset.ProblemRegistered

   Any new version created:
     -> asset.AssetVersionCreated

   Version promoted to active:
     -> asset.AssetVersionPublished

   Version deprecated:
     -> asset.AssetDeprecated

   (Workflow-facing UI event for video completion — confirmed in contracts)
     -> asset.AssetVideoReady
```

---

## Service Operations (conceptual mapping)

- `get_or_create_problem(problem_signature, normalized_text, phash, topic_tags)`
- `create_asset_version(problem_id, asset_type, content_ref, provenance, ...)`
- `publish_version(asset_version_id, published_by)`
- `deprecate_version(asset_version_id, reason, deprecated_by)`
- `get_published(problem_signature, asset_type)`

---

## Implementation Notes (important)

- Use DB constraints for invariants where possible (not only Python checks).
- `publish_version()` should be transactional to preserve single-published-version invariant.
- Version numbers should be monotonic per `(problem_id, asset_type)`.
- Model/workflow details belong in `ProvenanceRecord`, not in `AssetVersion`.
- `content_status` helps represent async video generation without breaking asset identity.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/adr/ADR-002-asset-as-sot-ledger.md`
- `domains/asset_registry/README.md`
- `docs/context-packs/L1-domain-map.md`
- `workflows/retrieve_or_generate/state_machine.md`
