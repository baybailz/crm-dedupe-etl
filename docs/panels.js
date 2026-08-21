/* Console tabs for this scenario.
   tabs:    [{key, label, count()}]  in display order
   render:  {key: () => html}        S.tablePanel / S.incomingPanel are generic
   afterRun(action) -> tab key to show when a run finishes
   toast(action, before, after) -> message after a run */
'use strict';

// Rows that arrived in the last run get a flash. Every render of the company
// tab remembers the ids it drew, so the run that follows knows what is new.
let seenIds = null, freshIds = new Set();

function panelCompany(){
  // dim_company is incremental, so the merge decides physical order.
  // The dimension reads by id.
  const rows = [...(S.D.tables.dim_company || [])].sort((a, b) => a.company_id - b.company_id);
  const sid = 'search_dim_company';
  const q = (S.searchState[sid] || '').trim().toLowerCase();
  const body = rows
    .filter(c => !q || `${c.company_name} ${c.address} ${c.city} ${c.website}`.toLowerCase().includes(q))
    .map(c => `
    <tr${freshIds.has(c.company_id) ? ' class="rownew"' : ''}>
      <td class="num mono faded">${S.esc(c.company_id)}</td>
      <td><b>${S.esc(c.company_name)}</b></td>
      <td>${S.esc(c.address)}<span class="sub2">${S.esc(c.city)}, ${S.esc(c.state)} ${S.esc(c.zip ?? '')}</span></td>
      <td class="mono faded">${S.esc(c.phone_number ?? '—')}</td>
      <td class="faded">${S.esc(c.website ?? '—')}</td>
      <td><span class="mono faded">${S.esc(c.source)}</span>
          ${c.source_record_key ? `<span class="sub2 mono">${S.esc(c.source_record_key)}</span>` : ''}</td>
    </tr>`).join('');
  seenIds = new Set(rows.map(c => c.company_id));
  return `<div class="card">
    <div class="cardhead"><h2 class="mono">dim_company</h2>
      <span class="hint">the company dimension after every load so far</span>
      <span class="spacer"></span>${S.searchBox(sid, S.searchState[sid] || '', 'search companies…')}</div>
    ${body ? S.tableHTML(['ID', 'Company', 'Address', 'Phone', 'Website', 'Source'], body)
           : '<div class="empty">No companies match that search.</div>'}
  </div>`;
}

function panelIncoming(){
  if (!S.D.next?.name) {
    return `<div class="card"><div class="empty">
      <div class="big">✦</div>
      <b>All company files are loaded.</b><br>
      <span>${S.fmtN(S.D.summary.companies_total)} companies in the CRM.</span><br>
      <button class="btn btn-primary" id="resetBtn2">Reset the demo ↺</button>
    </div></div>`;
  }
  const rows = S.D.next.rows.map((r, i) => `
    <tr>
      <td class="num faded">${i + 1}</td>
      <td><b>${S.esc(r.company_name)}</b></td>
      <td>${S.esc([r.address_1, r.address_2, r.address_3].filter(Boolean).join(' · '))}
          <span class="sub2">${S.esc(r.city)}, ${S.esc(r.state)} ${S.esc(r.zip)}</span></td>
      <td class="mono faded">${S.esc(r.primary_phone_number || '—')}</td>
      <td class="faded">${S.esc(r.website || '—')}</td>
    </tr>`).join('');
  return `<div class="card">
    <div class="cardhead"><h2><span class="mono">incoming/${S.esc(S.D.next.name)}.csv</span></h2>
      <span class="hint">raw company data, not yet imported</span></div>
    ${S.tableHTML(['#', 'Company', 'Address', 'Phone', 'Website'], rows)}
    <div class="loadbar">${S.runButton('loadBtn')}</div>
  </div>`;
}

function panelDupes(){
  const dupes = S.D.tables.dim_company_duplicates || [];
  const records = new Set(dupes.map(d => d.record_key)).size;
  const rows = dupes.map(r => `
    <tr>
      <td class="mono faded">${S.esc(r.record_key)}</td>
      <td><b>${S.esc(r.company_name)}</b><span class="sub2">${S.esc(r.address_1 ?? '')}</span></td>
      <td>${S.esc(r.matched_name)}<span class="sub2">${S.esc(r.matched_address ?? '')}</span></td>
      <td>${S.meter(r.name_similarity)}</td>
      <td>${S.meter(r.address_similarity)}</td>
      <td><span class="badge b-dup">${S.ICO.copy}duplicate</span></td>
    </tr>`).join('');
  return `<div class="card">
    <div class="cardhead"><h2 class="mono">dim_company_duplicates</h2>
      <span class="hint">one row per collision · ${dupes.length} pairs across ${records} records</span></div>
    ${dupes.length
      ? S.tableHTML(['Record', 'Purchased record', 'Matched against', 'Name sim', 'Addr sim', 'Class'], rows)
      : '<div class="empty"><div class="big">✓</div>No duplicate pairs yet.</div>'}
  </div>`;
}

window.PANELS = {
  tabs: [
    {key:'incoming', label:'incoming/*.csv', count:() => S.D.next?.name ? S.D.next.rows.length : 0},
    {key:'company', label:'dim_company', count:() => (S.D.tables.dim_company || []).length},
    {key:'dupes', label:'dim_company_duplicates', count:() => (S.D.tables.dim_company_duplicates || []).length},
  ],
  render: {incoming: panelIncoming, company: panelCompany, dupes: panelDupes},
  afterRun: action => {
    const ids = (S.D.tables.dim_company || []).map(c => c.company_id);
    freshIds = seenIds ? new Set(ids.filter(id => !seenIds.has(id))) : new Set();
    return action === S.CFG.actions.reset ? 'incoming' : 'company';
  },
  toast: (action, before, after) => {
    if (action === S.CFG.actions.reset) return 'Demo reset ↺';
    const parts = [], add = (n, w) => {if (n > 0) parts.push(`<b>${n}</b> ${w}`);};
    add((after.companies_total ?? 0) - (before.companies_total ?? 0), 'new companies imported');
    add((after.duplicates_blocked ?? 0) - (before.duplicates_blocked ?? 0), 'duplicates blocked');
    return parts.length ? parts.join(' · ') : 'Load complete';
  },
};
