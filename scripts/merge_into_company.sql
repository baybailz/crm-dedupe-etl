-- Final load step against the real CRM table. MERGE (not INSERT) keyed on the
-- source record, so re-running the pipeline is idempotent: a record that was
-- already imported updates in place instead of inserting again.
--
-- Assumes the CRM company table gains a source_record_key column (nullable,
-- only populated for vendor-imported rows). If the CRM table can't be
-- altered, keep an import_ledger table keyed the same way and anti-join it.

merge into crm.company t
using dedupe.companies_to_import s
   on t.source_record_key = s.source_record_key
when not matched then
    insert (company_id, company_name, address, city, state, zip,
            phone_number, website, primary_contact, source_record_key)
    values (s.company_id, s.company_name, s.address, s.city, s.state, s.zip,
            s.phone_number, s.website, s.primary_contact, s.source_record_key);
